#!/usr/bin/env python3
"""Run Godot for this project and fail on script errors.

    python tools/godot.py import                # (re)build the import cache
    python tools/godot.py test [--filter NAME]  # run the headless unit tests
    python tools/godot.py script res://x.gd     # run any SceneTree script
    python tools/godot.py smoke [--seed N]      # boot the game headless and play a scripted route
    python tools/godot.py shots [OUT_DIR]       # windowed screenshot tour (needs a display and a GPU)

Set GODOT to the Godot 4.7 console binary if it is not on PATH.
Godot only sets a non-zero exit code when a script calls quit(1), so this
wrapper also scans the output for engine and script errors.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / "game"
ERROR_LINE = re.compile(r"^(SCRIPT ERROR|ERROR:|.*Parse Error:|.*Failed to load script)")
IGNORED = ("ObjectDB instances leaked", "resources still in use at exit", "Leaked instance", "RID allocations")


def find_godot() -> str:
    candidates = [os.environ.get("GODOT", ""), "godot", "godot4", "godot-console"]
    temp = os.environ.get("TEMP", "")
    if temp:
        candidates += [str(p) for p in Path(temp, "godot").glob("Godot_v4*_console.exe")]
    for name in candidates:
        if name and (shutil.which(name) or Path(name).exists()):
            return shutil.which(name) or name
    sys.exit("Godot not found. Set the GODOT environment variable to the Godot 4.7 binary.")


def run(args: list[str], *, timeout: int = 420, fixed_fps: bool = False, headless: bool = True) -> int:
    command = [
        find_godot(),
        *(["--headless"] if headless else []),
        *(["--fixed-fps", "60"] if fixed_fps else []),
        "--path",
        str(GAME),
        *args,
    ]
    print("$", " ".join(command), flush=True)
    try:
        process = subprocess.run(command, capture_output=True, text=True, timeout=timeout, errors="replace")
    except subprocess.TimeoutExpired as expired:
        print((expired.stdout or b"").decode("utf-8", "replace") if isinstance(expired.stdout, bytes) else (expired.stdout or ""))
        print(f"Godot did not finish within {timeout} s (a script error in a SceneTree script leaves the tree running).", file=sys.stderr)
        return 124
    output = (process.stdout or "") + (process.stderr or "")
    errors = []
    for line in output.splitlines():
        print(line)
        if ERROR_LINE.match(line) and not any(token in line for token in IGNORED):
            errors.append(line)
    if errors:
        print(f"\n{len(errors)} engine/script error line(s) found", file=sys.stderr)
        return process.returncode or 1
    return process.returncode


def ensure_imported() -> int:
    cache = GAME / ".godot" / "global_script_class_cache.cfg"
    if cache.exists():
        newest = max(
            (
                p.stat().st_mtime
                for p in GAME.rglob("*")
                if p.suffix in {".gd", ".png", ".wav", ".json"} and ".godot" not in p.parts
            ),
            default=0,
        )
        if newest <= cache.stat().st_mtime:
            return 0
    return run(["--import"])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("import")
    sub.add_parser("compile")
    test = sub.add_parser("test")
    test.add_argument("--filter", default="")
    script = sub.add_parser("script")
    script.add_argument("path")
    script.add_argument("rest", nargs="*")
    smoke = sub.add_parser("smoke")
    smoke.add_argument("--seed", type=int, default=None, help="RNG seed for the run (default: a fixed one)")
    smoke.add_argument("--isolate", action="store_true", help="use save files of its own, so runs can go in parallel")
    shots = sub.add_parser("shots")
    shots.add_argument("out_dir", nargs="?", default="")
    args = parser.parse_args(argv)

    if args.command == "import":
        return run(["--import"])
    code = ensure_imported()
    if code:
        return code
    if args.command == "compile":
        return run(["--script", "res://tests/compile_all.gd"])
    if args.command == "test":
        code = run(["--script", "res://tests/compile_all.gd"])
        if code:
            return code
        extra = ["--", f"--filter={args.filter}"] if args.filter else []
        return run(["--script", "res://tests/run_tests.gd", *extra], fixed_fps=True)
    if args.command == "script":
        return run(["--script", args.path, *(["--", *args.rest] if args.rest else [])], fixed_fps=True)
    if args.command == "shots":
        out = str(Path(args.out_dir).resolve()) if args.out_dir else ""
        return run(["--script", "res://tests/shots.gd", *(["--", out] if out else [])], fixed_fps=True, headless=False)
    smoke_args = ([f"--seed={args.seed}"] if args.seed is not None else []) + (["--isolate"] if args.isolate else [])
    return run(["--script", "res://tests/smoke.gd", *(["--", *smoke_args] if smoke_args else [])], fixed_fps=True)


if __name__ == "__main__":
    raise SystemExit(main())
