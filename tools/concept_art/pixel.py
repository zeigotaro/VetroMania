"""Procedural pixel-art toolkit for the VetroMania concept assets.

Everything is drawn at native resolution from simple shaded primitives, so the
output stays crisp pixel art:

- hue-shifted palette ramps (cool shadows, warm highlights);
- banded lighting from a fixed top-left key light;
- contact shadows where a front part overlaps a part behind it;
- colored selective outlines around the silhouette;
- an emission mask that scenes turn into additive bloom.
"""

from __future__ import annotations

import colorsys
import math
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw

Color = tuple[int, int, int]

LIGHT = np.array([-0.6, -0.75, 0.55])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
INK = (20, 12, 28)


def hexc(value: str) -> Color:
    value = value.lstrip("#")
    return tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))


def mix(a: Color, b: Color, t: float) -> Color:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def darken(color: Color, factor: float) -> Color:
    return tuple(int(round(v * factor)) for v in color)


def _hue_toward(hue: float, target: float, amount: float) -> float:
    delta = (target - hue + 0.5) % 1.0 - 0.5
    return (hue + delta * amount) % 1.0


def ramp(base: str | Color, steps: int = 5, *, dark: float = 0.62, light: float = 0.55,
         hue: float = 0.16, sat: float = 0.12) -> tuple[Color, ...]:
    """Return a dark-to-light ramp around `base`, which sits in the middle.

    Shadows drift toward blue-violet and gain saturation; highlights drift
    toward yellow and lose saturation, as hand-made pixel-art palettes do.
    """
    if isinstance(base, str):
        base = hexc(base)
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in base))
    mid = (steps - 1) / 2
    colors = []
    for i in range(steps):
        t = (i - mid) / mid if mid else 0.0
        if t < 0:
            vv = v * (1 + dark * t)
            ss = min(1.0, s + sat * -t)
            hh = _hue_toward(h, 0.70, hue * -t)
        else:
            vv = v + (1 - v) * light * t
            ss = max(0.0, s - sat * 1.6 * t)
            hh = _hue_toward(h, 0.14, hue * 0.6 * t)
        r, g, b = colorsys.hsv_to_rgb(hh, ss, min(1.0, vv))
        colors.append((round(r * 255), round(g * 255), round(b * 255)))
    return tuple(colors)


@dataclass(frozen=True)
class Material:
    colors: tuple[Color, ...]
    spec: Color | None = None
    spec_power: float = 18.0
    spec_cut: float = 0.62
    emissive: bool = False
    glow: Color | None = None
    ambient: float = 0.08
    diffuse: float = 0.95
    outline: Color | None = None

    def outline_color(self) -> Color:
        return self.outline or mix(darken(self.colors[0], 0.55), INK, 0.35)


def mat(base: str | Color, steps: int = 5, **options) -> Material:
    """Build a lit material from a base color and a ramp."""
    ramp_options = {k: options.pop(k) for k in ("dark", "light", "hue", "sat") if k in options}
    return Material(ramp(base, steps, **ramp_options), **options)


def glow(base: str | Color, *, core: str | Color = "#ffffff", steps: int = 4) -> Material:
    """An emissive material: bright, barely lit, and recorded for bloom."""
    base = hexc(base) if isinstance(base, str) else base
    core = hexc(core) if isinstance(core, str) else core
    colors = tuple(mix(base, core, t) for t in np.linspace(0.0, 0.85, steps))
    return Material(colors, emissive=True, glow=base, ambient=0.55, diffuse=0.6)


def _normalize(nx: np.ndarray, ny: np.ndarray, nz: np.ndarray) -> np.ndarray:
    n = np.stack([nx, ny, nz], axis=-1).astype(np.float64)
    length = np.linalg.norm(n, axis=-1, keepdims=True)
    return n / np.maximum(length, 1e-9)


def _erode(mask: np.ndarray) -> np.ndarray:
    p = np.pad(mask, 1, constant_values=False)
    return p[1:-1, 1:-1] & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]


def _shifted(values: np.ndarray, dy: int, dx: int, fill) -> np.ndarray:
    """Return the value of the neighbor at (y + dy, x + dx) for every pixel."""
    out = np.full_like(values, fill)
    h, w = values.shape
    ys, yd = (slice(dy, h), slice(0, h - dy)) if dy >= 0 else (slice(0, h + dy), slice(-dy, h))
    xs, xd = (slice(dx, w), slice(0, w - dx)) if dx >= 0 else (slice(0, w + dx), slice(-dx, w))
    out[yd, xd] = values[ys, xs]
    return out


Shape = tuple[np.ndarray, np.ndarray]


class Sprite:
    """A layered, lit pixel canvas. Parts painted later sit in front.

    `origin` shifts the drawing coordinates, so art authored around (0, 0) can
    gain headroom (for example, for steam or a raised weapon) without edits.
    """

    def __init__(self, width: int, height: int, origin: tuple[int, int] = (0, 0)):
        self.w, self.h = width, height
        self.ox, self.oy = origin
        self.mat = np.full((height, width), -1, np.int16)
        self.idx = np.zeros((height, width), np.int16)
        self.top = np.zeros((height, width), np.int16)
        self.part = np.full((height, width), -1, np.int32)
        self.group = np.full((height, width), -1, np.int32)
        self.materials: list[Material] = []
        self._materials: dict[Material, int] = {}
        self._groups: dict[str, int] = {}
        self.parts = 0
        y, x = np.mgrid[0:height, 0:width]
        self.x = x + 0.5 - self.ox
        self.y = y + 0.5 - self.oy

    # Geometry: each returns (mask, normals) ---------------------------------

    def ellipse(self, cx, cy, rx, ry=None, angle=0.0, bulge=1.0) -> Shape:
        ry = rx if ry is None else ry
        c, s = math.cos(angle), math.sin(angle)
        dx, dy = self.x - cx, self.y - cy
        u = (dx * c + dy * s) / rx
        v = (-dx * s + dy * c) / ry
        d2 = u * u + v * v
        nz = np.sqrt(np.clip(1 - d2, 0, 1))
        nu, nv = u * bulge, v * bulge
        return d2 <= 1.0, _normalize(nu * c - nv * s, nu * s + nv * c, nz)

    def capsule(self, x0, y0, x1, y1, r0, r1=None, bulge=1.0) -> Shape:
        """A limb: a segment swept by a radius that tapers from r0 to r1."""
        r1 = r0 if r1 is None else r1
        ax, ay = x1 - x0, y1 - y0
        length2 = ax * ax + ay * ay or 1e-9
        t = np.clip(((self.x - x0) * ax + (self.y - y0) * ay) / length2, 0, 1)
        dx, dy = self.x - (x0 + ax * t), self.y - (y0 + ay * t)
        r = np.maximum(r0 + (r1 - r0) * t, 1e-6)
        nx, ny = dx / r, dy / r
        nz = np.sqrt(np.clip(1 - nx * nx - ny * ny, 0, 1))
        return np.hypot(dx, dy) <= r, _normalize(nx * bulge, ny * bulge, nz)

    def polygon(self, points, bevel=1.5, tilt=(0.0, 0.0)) -> Shape:
        return self._beveled(self.mask_polygon(points), bevel, tilt)

    def rrect(self, x0, y0, x1, y1, radius=2, bevel=1.5, tilt=(0.0, 0.0)) -> Shape:
        return self._beveled(self.mask_rrect(x0, y0, x1, y1, radius), bevel, tilt)

    def from_mask(self, mask, bevel=1.5, tilt=(0.0, 0.0)) -> Shape:
        return self._beveled(mask, bevel, tilt)

    def _beveled(self, mask, bevel, tilt) -> Shape:
        """Flat face with rounded edges: normals from an eroded height field."""
        tx, ty = tilt
        if bevel <= 0:
            flat = np.zeros((self.h, self.w))
            return mask, _normalize(flat + tx, flat + ty, flat + 1)
        dist = np.zeros(mask.shape, np.float64)
        current = mask.copy()
        for _ in range(int(math.ceil(bevel))):
            dist += current
            current = _erode(current)
        height = np.clip(dist / bevel, 0, 1)
        height = height * height * (3 - 2 * height)
        gy, gx = np.gradient(height)
        k = bevel * 1.1
        return mask, _normalize(-gx * k + tx, -gy * k + ty, np.ones_like(height))

    # Masks --------------------------------------------------------------------

    def _canvas(self):
        image = Image.new("L", (self.w, self.h), 0)
        return image, ImageDraw.Draw(image)

    def _pt(self, x, y):
        return float(x) + self.ox, float(y) + self.oy

    def mask_polygon(self, points) -> np.ndarray:
        image, draw = self._canvas()
        draw.polygon([self._pt(x, y) for x, y in points], fill=255)
        return np.array(image) > 0

    def mask_rrect(self, x0, y0, x1, y1, radius=2) -> np.ndarray:
        image, draw = self._canvas()
        draw.rounded_rectangle([*self._pt(x0, y0), *self._pt(x1, y1)], radius=radius, fill=255)
        return np.array(image) > 0

    def mask_line(self, points, width=1) -> np.ndarray:
        image, draw = self._canvas()
        draw.line([self._pt(x, y) for x, y in points], fill=255, width=width)
        return np.array(image) > 0

    def mask_ellipse(self, cx, cy, rx, ry=None) -> np.ndarray:
        ry = rx if ry is None else ry
        return ((self.x - cx) / rx) ** 2 + ((self.y - cy) / ry) ** 2 <= 1.0

    def mask_rect(self, x0, y0, x1, y1) -> np.ndarray:
        return (self.x >= x0) & (self.x < x1) & (self.y >= y0) & (self.y < y1)

    def mask_points(self, points) -> np.ndarray:
        mask = np.zeros((self.h, self.w), bool)
        for x, y in points:
            px, py = int(x + self.ox), int(y + self.oy)
            if 0 <= py < self.h and 0 <= px < self.w:
                mask[py, px] = True
        return mask

    def opaque(self) -> np.ndarray:
        return self.mat >= 0

    # Painting ---------------------------------------------------------------

    def _material(self, material: Material) -> int:
        if material not in self._materials:
            self._materials[material] = len(self.materials)
            self.materials.append(material)
        return self._materials[material]

    def _group(self, name: str | None) -> int:
        key = name if name is not None else f"#part{self.parts}"
        return self._groups.setdefault(key, len(self._groups))

    def paint(self, shape: Shape, material: Material, *, group: str | None = None,
              bias: float = 0.0, clip: np.ndarray | None = None) -> np.ndarray:
        """Light a shape with the key light and band it into the material ramp."""
        mask, normals = shape
        if clip is not None:
            mask = mask & clip
        if not mask.any():
            return mask
        n = len(material.colors)
        facing = normals @ LIGHT
        if material.emissive:
            # Emitters ignore the key light: bright core, colored rim.
            level = np.clip(normals[..., 2], 0, 1) ** 0.7 * 0.999 + bias
        else:
            level = material.ambient + material.diffuse * np.clip(facing, 0, 1) + bias
        index = np.clip(np.floor(level * n), 0, n - 1).astype(np.int16)
        if material.spec is not None:
            reflect_z = 2 * facing * normals[..., 2] - LIGHT[2]
            highlight = np.clip(reflect_z, 0, 1) ** material.spec_power
            index = np.where(highlight > material.spec_cut, n, index).astype(np.int16)
        self._write(mask, material, index, group)
        return mask

    def fill(self, mask: np.ndarray, material: Material, index: int, *, group: str | None = None) -> np.ndarray:
        """Paint a mask with one ramp entry, ignoring light (for decals and trim)."""
        if mask.any():
            n = len(material.colors)
            self._write(mask, material, np.full(mask.shape, min(index, n - 1), np.int16), group)
        return mask

    def _write(self, mask, material, index, group):
        mi = self._material(material)
        self.mat[mask] = mi
        self.idx[mask] = index[mask]
        self.top[mask] = len(material.colors) - 1
        self.part[mask] = self.parts
        self.group[mask] = self._group(group)
        self.parts += 1

    def shift(self, mask: np.ndarray, delta: int) -> None:
        """Lighten (+) or darken (-) already-painted pixels along their own ramp."""
        m = mask & (self.mat >= 0)
        self.idx[m] = np.clip(self.idx[m] + delta, 0, self.top[m])

    def erase(self, mask: np.ndarray) -> None:
        self.mat[mask] = -1
        self.part[mask] = -1

    # Rendering ----------------------------------------------------------------

    def _indices(self, contact: bool) -> np.ndarray:
        index = self.idx.copy()
        if contact:
            opaque = self.mat >= 0
            shadowed = np.zeros_like(opaque)
            # A part in front, up or to the left, casts a one-pixel shadow down-right.
            for dy, dx in ((0, -1), (-1, 0)):
                front_part = _shifted(self.part, dy, dx, -1)
                front_group = _shifted(self.group, dy, dx, -1)
                shadowed |= opaque & (front_part > self.part) & (front_group != self.group)
            index[shadowed] = np.maximum(index[shadowed] - 1, 0)
        return index

    def render(self, *, outline: bool = True, contact: bool = True,
               rim: Color | None = None) -> Image.Image:
        index = self._indices(contact)
        rgba = np.zeros((self.h, self.w, 4), np.uint8)
        opaque = self.mat >= 0
        for mi, material in enumerate(self.materials):
            sel = self.mat == mi
            if not sel.any():
                continue
            table = np.array(list(material.colors) + [material.spec or material.colors[-1]], np.uint8)
            rgba[sel, :3] = table[np.clip(index[sel], 0, len(material.colors))]
            rgba[sel, 3] = 255
        if rim is not None:
            # Back light from the right: brighten the silhouette's right and lower edges.
            edge = opaque & ((_shifted(self.mat, 0, 1, -1) < 0) | (_shifted(self.mat, 1, 0, -1) < 0))
            emissive = np.isin(self.mat, [i for i, m in enumerate(self.materials) if m.emissive])
            edge &= ~emissive
            rgba[edge, :3] = (rgba[edge, :3] * 0.45 + np.array(rim) * 0.55).astype(np.uint8)
        if outline:
            ink = np.array([m.outline_color() for m in self.materials] or [INK], np.uint8)
            for dy, dx in ((1, 0), (-1, 0), (0, -1), (0, 1)):
                neighbor = _shifted(self.mat, dy, dx, -1)
                target = (rgba[..., 3] == 0) & (neighbor >= 0)
                rgba[target, :3] = ink[neighbor[target]]
                rgba[target, 3] = 255
        return Image.fromarray(rgba, "RGBA")

    def emission(self) -> np.ndarray:
        """RGB glow contribution (floats 0..1) of every emissive pixel."""
        out = np.zeros((self.h, self.w, 3))
        for mi, material in enumerate(self.materials):
            if material.emissive:
                sel = self.mat == mi
                out[sel] = np.array(material.glow or material.colors[-1]) / 255.0
        return out


# 5x7 pixel font -----------------------------------------------------------------

_GLYPHS = {
    "A": ".###. #...# #...# ##### #...# #...# #...#",
    "B": "####. #...# #...# ####. #...# #...# ####.",
    "C": ".###. #...# #.... #.... #.... #...# .###.",
    "D": "####. #...# #...# #...# #...# #...# ####.",
    "E": "##### #.... #.... ####. #.... #.... #####",
    "F": "##### #.... #.... ####. #.... #.... #....",
    "G": ".###. #...# #.... #.### #...# #...# .####",
    "H": "#...# #...# #...# ##### #...# #...# #...#",
    "I": ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
    "J": "..### ...#. ...#. ...#. ...#. #..#. .##..",
    "K": "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
    "L": "#.... #.... #.... #.... #.... #.... #####",
    "M": "#...# ##.## #.#.# #.#.# #...# #...# #...#",
    "N": "#...# #...# ##..# #.#.# #..## #...# #...#",
    "O": ".###. #...# #...# #...# #...# #...# .###.",
    "P": "####. #...# #...# ####. #.... #.... #....",
    "Q": ".###. #...# #...# #...# #.#.# #..#. .##.#",
    "R": "####. #...# #...# ####. #.#.. #..#. #...#",
    "S": ".#### #.... #.... .###. ....# ....# ####.",
    "T": "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
    "U": "#...# #...# #...# #...# #...# #...# .###.",
    "V": "#...# #...# #...# #...# #...# .#.#. ..#..",
    "W": "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
    "X": "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
    "Y": "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
    "Z": "##### ....# ...#. ..#.. .#... #.... #####",
    "0": ".###. #...# #..## #.#.# ##..# #...# .###.",
    "1": "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
    "2": ".###. #...# ....# ...#. ..#.. .#... #####",
    "3": "##### ...#. ..#.. ...#. ....# #...# .###.",
    "4": "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
    "5": "##### #.... ####. ....# ....# #...# .###.",
    "6": "..##. .#... #.... ####. #...# #...# .###.",
    "7": "##### ....# ...#. ..#.. .#... .#... .#...",
    "8": ".###. #...# #...# .###. #...# #...# .###.",
    "9": ".###. #...# #...# .#### ....# ...#. .##..",
    " ": "..... ..... ..... ..... ..... ..... .....",
    ".": "..... ..... ..... ..... ..... ..... ..#..",
    ",": "..... ..... ..... ..... ..... ..#.. .#...",
    "!": "..#.. ..#.. ..#.. ..#.. ..#.. ..... ..#..",
    "?": ".###. #...# ....# ...#. ..#.. ..... ..#..",
    ":": "..... ..#.. ..... ..... ..... ..#.. .....",
    "'": "..#.. ..#.. .#... ..... ..... ..... .....",
    '"': ".#.#. .#.#. ..... ..... ..... ..... .....",
    "-": "..... ..... ..... .###. ..... ..... .....",
    "+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
    "/": "....# ....# ...#. ..#.. .#... #.... #....",
    "%": "##..# ##..# ...#. ..#.. .#... #..## #..##",
    "(": "...#. ..#.. .#... .#... .#... ..#.. ...#.",
    ")": ".#... ..#.. ...#. ...#. ...#. ..#.. .#...",
    ">": ".#... ..#.. ...#. ....# ...#. ..#.. .#...",
    "<": "...#. ..#.. .#... #.... .#... ..#.. ...#.",
    "#": ".#.#. .#.#. ##### .#.#. ##### .#.#. .#.#.",
    "*": "..... #.#.# .###. ##### .###. #.#.# .....",
    "=": "..... ..... ##### ..... ##### ..... .....",
    "_": "..... ..... ..... ..... ..... ..... #####",
    "&": ".##.. #..#. #.#.. .#... #.#.# #..#. .##.#",
    "$": "..#.. .#### #.#.. .###. ..#.# ####. ..#..",
    "^": "..#.. .#.#. #...# ..... ..... ..... .....",
    "|": "..#.. ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
}
FONT = {
    ch: np.array([[c == "#" for c in row] for row in rows.split()], bool)
    for ch, rows in _GLYPHS.items()
}
GLYPH_W, GLYPH_H = 5, 7


def text_width(text: str, scale: int = 1, spacing: int = 1) -> int:
    return max(0, len(text) * (GLYPH_W + spacing) - spacing) * scale


def text_mask(text: str, scale: int = 1, spacing: int = 1) -> np.ndarray:
    """Rasterize uppercase text into a boolean mask (unknown characters render as '?')."""
    width = text_width(text, 1, spacing)
    mask = np.zeros((GLYPH_H, max(width, 1)), bool)
    for i, ch in enumerate(text.upper()):
        glyph = FONT.get(ch, FONT["?"])
        x = i * (GLYPH_W + spacing)
        mask[:, x:x + GLYPH_W] |= glyph
    if scale > 1:
        mask = mask.repeat(scale, 0).repeat(scale, 1)
    return mask


# Scene canvases: float RGB in 0..1, plus a parallel glow buffer for bloom ------------

class Canvas:
    def __init__(self, width: int, height: int, color: Color = (0, 0, 0)):
        self.w, self.h = width, height
        self.rgb = np.zeros((height, width, 3))
        self.rgb[:] = np.array(color) / 255.0
        self.glow = np.zeros((height, width, 3))

    def blit(self, image: Image.Image, x: int, y: int, *, emission: np.ndarray | None = None,
             flip: bool = False, alpha: float = 1.0) -> None:
        """Alpha-composite an RGBA sprite at (x, y); emission adds to the glow buffer."""
        src = np.asarray(image.convert("RGBA"), np.float64) / 255.0
        if emission is not None:
            emission = emission.copy()
        if flip:
            src = src[:, ::-1]
            if emission is not None:
                emission = emission[:, ::-1]
        h, w = src.shape[:2]
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + w, self.w), min(y + h, self.h)
        if x0 >= x1 or y0 >= y1:
            return
        region = src[y0 - y:y1 - y, x0 - x:x1 - x]
        a = region[..., 3:4] * alpha
        self.rgb[y0:y1, x0:x1] = self.rgb[y0:y1, x0:x1] * (1 - a) + region[..., :3] * a
        if emission is not None:
            self.glow[y0:y1, x0:x1] += emission[y0 - y:y1 - y, x0 - x:x1 - x] * alpha

    def fill(self, mask: np.ndarray, color: Color, x: int = 0, y: int = 0, alpha: float = 1.0) -> None:
        h, w = mask.shape
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + w, self.w), min(y + h, self.h)
        if x0 >= x1 or y0 >= y1:
            return
        m = mask[y0 - y:y1 - y, x0 - x:x1 - x]
        view = self.rgb[y0:y1, x0:x1]
        view[m] = view[m] * (1 - alpha) + np.array(color) / 255.0 * alpha

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: Color, alpha: float = 1.0) -> None:
        self.fill(np.ones((max(y1 - y0, 0), max(x1 - x0, 0)), bool), color, x0, y0, alpha)

    def text(self, x: int, y: int, text: str, color: Color, *, scale: int = 1,
             shadow: Color | None = INK, glow: Color | None = None) -> int:
        mask = text_mask(text, scale)
        if shadow is not None:
            self.fill(mask, shadow, x + scale, y + scale)
        self.fill(mask, color, x, y)
        if glow is not None:
            h, w = mask.shape
            x0, y0 = max(x, 0), max(y, 0)
            x1, y1 = min(x + w, self.w), min(y + h, self.h)
            if x0 < x1 and y0 < y1:
                self.glow[y0:y1, x0:x1][mask[y0 - y:y1 - y, x0 - x:x1 - x]] += np.array(glow) / 255.0
        return mask.shape[1]

    def add_glow(self, mask: np.ndarray, color: Color, x: int = 0, y: int = 0, strength: float = 1.0) -> None:
        h, w = mask.shape
        x0, y0 = max(x, 0), max(y, 0)
        x1, y1 = min(x + w, self.w), min(y + h, self.h)
        if x0 < x1 and y0 < y1:
            self.glow[y0:y1, x0:x1][mask[y0 - y:y1 - y, x0 - x:x1 - x]] += np.array(color) / 255.0 * strength

    def bloom(self, radius: float = 5.0, strength: float = 0.85) -> None:
        """Additive bloom from the glow buffer: a tight core blur plus a wide halo."""
        from PIL import ImageFilter

        source = Image.fromarray((np.clip(self.glow, 0, 1) * 255).astype(np.uint8), "RGB")
        halo = np.asarray(source.filter(ImageFilter.GaussianBlur(radius)), np.float64) / 255.0
        core = np.asarray(source.filter(ImageFilter.GaussianBlur(radius * 0.35)), np.float64) / 255.0
        self.rgb = np.clip(self.rgb + (halo * 1.6 + core * 0.8) * strength, 0, 1)

    def image(self) -> Image.Image:
        return Image.fromarray((np.clip(self.rgb, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


# Noise and ordered dithering ------------------------------------------------------

BAYER4 = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0


def bayer(width: int, height: int) -> np.ndarray:
    return np.tile(BAYER4, (height // 4 + 1, width // 4 + 1))[:height, :width]


def value_noise(width: int, height: int, cell: float, seed: int, octaves: int = 4) -> np.ndarray:
    """Smooth fractal value noise in 0..1."""
    rng = np.random.default_rng(seed)
    total = np.zeros((height, width))
    amplitude, norm = 1.0, 0.0
    for octave in range(octaves):
        size = cell / (2 ** octave)
        gw, gh = int(width / size) + 3, int(height / size) + 3
        grid = rng.random((gh, gw))
        y, x = np.mgrid[0:height, 0:width] / size
        x0, y0 = x.astype(int), y.astype(int)
        fx, fy = x - x0, y - y0
        fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
        a, b = grid[y0, x0], grid[y0, x0 + 1]
        c, d = grid[y0 + 1, x0], grid[y0 + 1, x0 + 1]
        total += amplitude * ((a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy)
        norm += amplitude
        amplitude *= 0.5
    return total / norm


def quantize(values: np.ndarray, palette, *, dither: float = 1.0) -> np.ndarray:
    """Map 0..1 values onto a palette with 4x4 ordered dithering between steps."""
    colors = np.array([hexc(c) if isinstance(c, str) else c for c in palette], np.float64) / 255.0
    n = len(colors)
    scaled = np.clip(values, 0, 0.9999) * (n - 1)
    base = np.floor(scaled)
    frac = scaled - base
    threshold = bayer(values.shape[1], values.shape[0]) * dither + (1 - dither) * 0.5
    index = np.clip(base + (frac > threshold), 0, n - 1).astype(int)
    return colors[index]


# Export ------------------------------------------------------------------------------

def upscale(image: Image.Image, factor: int) -> Image.Image:
    return image.resize((image.width * factor, image.height * factor), Image.Resampling.NEAREST)


def save_png(image: Image.Image, path, scale: int = 1) -> None:
    path = _prepare(path)
    (upscale(image, scale) if scale > 1 else image).save(path, optimize=True)


def save_gif(frames: list[Image.Image], path, *, scale: int = 4, duration: int = 100,
             background: Color = (26, 18, 38)) -> None:
    """Animated preview on a solid background with one shared, undithered palette."""
    path = _prepare(path)
    flat = []
    for frame in frames:
        base = Image.new("RGBA", frame.size, background + (255,))
        base.alpha_composite(frame.convert("RGBA"))
        flat.append(upscale(base.convert("RGB"), scale))
    strip = Image.new("RGB", (flat[0].width, flat[0].height * len(flat)))
    for i, frame in enumerate(flat):
        strip.paste(frame, (0, i * frame.height))
    palette = strip.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    quantized = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in flat]
    quantized[0].save(path, save_all=True, append_images=quantized[1:], duration=duration,
                      loop=0, disposal=1, optimize=False)


def sheet(frames: list[Image.Image], columns: int, *, pad: int = 2, label: str | None = None,
          background: Color | None = None) -> Image.Image:
    """Pack same-size frames into a grid, with an optional pixel-font label strip."""
    fw = max(f.width for f in frames)
    fh = max(f.height for f in frames)
    rows = math.ceil(len(frames) / columns)
    top = GLYPH_H + 4 if label else 0
    width = columns * (fw + pad) + pad
    height = top + rows * (fh + pad) + pad
    fill = (0, 0, 0, 0) if background is None else background + (255,)
    out = Image.new("RGBA", (max(width, text_width(label or "") + 4), height), fill)
    if label:
        mask = text_mask(label)
        text = np.zeros(mask.shape + (4,), np.uint8)
        text[mask] = (235, 225, 255, 255)
        out.alpha_composite(Image.fromarray(text, "RGBA"), (pad, 2))
    for i, frame in enumerate(frames):
        cx, cy = i % columns, i // columns
        out.alpha_composite(frame.convert("RGBA"), (pad + cx * (fw + pad), top + pad + cy * (fh + pad)))
    return out


def stack(images: list[Image.Image], *, gap: int = 4, background: Color | None = None) -> Image.Image:
    width = max(i.width for i in images)
    height = sum(i.height for i in images) + gap * (len(images) - 1)
    fill = (0, 0, 0, 0) if background is None else background + (255,)
    out = Image.new("RGBA", (width, height), fill)
    y = 0
    for image in images:
        out.alpha_composite(image.convert("RGBA"), (0, y))
        y += image.height + gap
    return out


def _prepare(path):
    from pathlib import Path

    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    return path
