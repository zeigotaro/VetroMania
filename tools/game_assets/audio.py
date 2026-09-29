from __future__ import annotations

import argparse
import hashlib
import json
import math
import tempfile
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_OUT = ROOT / "game" / "assets" / "audio"
SR = 32000
TAU = math.tau
INT16_MAX = 32767
SFX_TARGET_DB = -3.0
MUSIC_TARGET_DB = -8.0
EDGE_FADE = 0.008


def sample_count(seconds: float) -> int:
    return max(1, int(round(seconds * SR)))


def beats_to_seconds(beats: float, bpm: float) -> float:
    return beats * 60.0 / bpm


def beats_to_samples(beats: float, bpm: float) -> int:
    return sample_count(beats_to_seconds(beats, bpm))


def db_to_amp(db: float) -> float:
    return 10.0 ** (db / 20.0)


def peak_db(signal: np.ndarray) -> float:
    peak = float(np.max(np.abs(signal)))
    if peak <= 1e-12:
        return -120.0
    return 20.0 * math.log10(peak)


def rms_db(signal: np.ndarray) -> float:
    rms = float(np.sqrt(np.mean(np.square(signal))))
    if rms <= 1e-12:
        return -120.0
    return 20.0 * math.log10(rms)


def seeded_rng(name: str) -> np.random.Generator:
    digest = hashlib.sha256(f"vetromania-audio:{name}".encode("utf-8")).digest()
    seed = int.from_bytes(digest[:8], "big", signed=False)
    return np.random.default_rng(seed)


def fade_edges(signal: np.ndarray, seconds: float = EDGE_FADE) -> np.ndarray:
    count = min(len(signal) // 2, sample_count(seconds))
    if count <= 1:
        return signal
    ramp = np.linspace(0.0, 1.0, count, endpoint=False)
    signal[:count] *= ramp
    signal[-count:] *= ramp[::-1]
    return signal


def remove_dc(signal: np.ndarray) -> np.ndarray:
    return signal - float(np.mean(signal))


def normalize(signal: np.ndarray, target_db: float) -> np.ndarray:
    peak = float(np.max(np.abs(signal)))
    if peak <= 1e-12:
        return signal.copy()
    signal = signal * (db_to_amp(target_db) / peak)
    clipped = float(np.max(np.abs(signal)))
    if clipped >= 0.999:
        signal *= 0.998 / clipped
    return signal


def finalize(
    signal: np.ndarray, target_db: float, *, fade_seconds: float = EDGE_FADE
) -> np.ndarray:
    signal = np.asarray(signal, dtype=np.float64)
    if not np.isfinite(signal).all():
        raise ValueError("signal contains NaN or inf")
    signal = remove_dc(signal)
    signal = fade_edges(signal, fade_seconds)
    signal = normalize(signal, target_db)
    if float(np.max(np.abs(signal))) > 1.0:
        raise ValueError("signal clips after normalization")
    return signal


def write_wav(path: Path, signal: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(np.rint(signal * INT16_MAX), -INT16_MAX, INT16_MAX).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(pcm.tobytes())


def lowpass(signal: np.ndarray, cutoff_hz: float) -> np.ndarray:
    if cutoff_hz <= 0.0:
        return np.zeros_like(signal)
    dt = 1.0 / SR
    rc = 1.0 / (TAU * cutoff_hz)
    alpha = dt / (rc + dt)
    out = np.empty_like(signal)
    out[0] = alpha * signal[0]
    for index in range(1, len(signal)):
        out[index] = out[index - 1] + alpha * (signal[index] - out[index - 1])
    return out


def highpass(signal: np.ndarray, cutoff_hz: float) -> np.ndarray:
    if cutoff_hz <= 0.0:
        return signal.copy()
    dt = 1.0 / SR
    rc = 1.0 / (TAU * cutoff_hz)
    alpha = rc / (rc + dt)
    out = np.empty_like(signal)
    out[0] = signal[0]
    prev = signal[0]
    for index in range(1, len(signal)):
        out[index] = alpha * (out[index - 1] + signal[index] - prev)
        prev = signal[index]
    return out


def adsr(
    count: int, attack: float, decay: float, sustain: float, release: float
) -> np.ndarray:
    total = count / SR
    span = attack + decay + release
    if span > total * 0.95 and span > 0.0:
        scale = (total * 0.95) / span
        attack *= scale
        decay *= scale
        release *= scale
    a = min(count, int(round(attack * SR)))
    d = min(count - a, int(round(decay * SR)))
    r = min(count - a - d, int(round(release * SR)))
    sustain_start = a + d
    release_start = max(sustain_start, count - r)
    env = np.empty(count, dtype=np.float64)
    if a > 0:
        env[:a] = np.linspace(0.0, 1.0, a, endpoint=False)
    if d > 0:
        env[a : a + d] = np.linspace(1.0, sustain, d, endpoint=False)
    if release_start > sustain_start:
        env[sustain_start:release_start] = sustain
    if r > 0:
        start_level = env[release_start - 1] if release_start > 0 else sustain
        env[release_start:] = np.linspace(
            start_level, 0.0, count - release_start, endpoint=False
        )
    if release_start == count:
        env[-1] = 0.0
    return env


def freq_contour(start_hz: float, end_hz: float, seconds: float) -> np.ndarray:
    count = sample_count(seconds)
    if start_hz <= 0.0 or end_hz <= 0.0:
        return np.linspace(start_hz, end_hz, count, endpoint=False)
    return np.geomspace(start_hz, end_hz, count, endpoint=False)


def _phase(
    freq: float | np.ndarray,
    count: int,
    vibrato_rate: float = 0.0,
    vibrato_cents: float = 0.0,
) -> np.ndarray:
    if np.isscalar(freq):
        freq_array = np.full(count, float(freq), dtype=np.float64)
    else:
        freq_array = np.asarray(freq, dtype=np.float64)
        if len(freq_array) != count:
            raise ValueError("frequency contour length mismatch")
    if vibrato_rate and vibrato_cents:
        t = np.arange(count, dtype=np.float64) / SR
        vib = np.sin(TAU * vibrato_rate * t) * vibrato_cents
        freq_array = freq_array * np.power(2.0, vib / 1200.0)
    phase = np.cumsum(freq_array / SR, dtype=np.float64)
    phase = np.concatenate((np.array([0.0]), phase[:-1]))
    return np.mod(phase, 1.0)


def organ_wave(freq: float | np.ndarray, count: int) -> np.ndarray:
    phase = _phase(freq, count)
    out = (
        1.0 * np.sin(TAU * phase)
        + 0.55 * np.sin(TAU * phase * 2.0 + 0.04)
        + 0.30 * np.sin(TAU * phase * 3.0 + 0.11)
        + 0.18 * np.sin(TAU * phase * 4.0 + 0.07)
        + 0.12 * np.sin(TAU * phase * 6.0 + 0.19)
    )
    return out / 2.15


def oscillator(
    kind: str,
    freq: float | np.ndarray,
    seconds: float,
    *,
    duty: float = 0.5,
    vibrato_rate: float = 0.0,
    vibrato_cents: float = 0.0,
    rng: np.random.Generator | None = None,
    fm_index: float = 0.0,
    fm_ratio: float = 2.0,
) -> np.ndarray:
    count = sample_count(seconds)
    if kind == "noise":
        if rng is None:
            rng = np.random.default_rng(0)
        return rng.uniform(-1.0, 1.0, count)
    if kind == "organ":
        return organ_wave(freq, count)
    phase = _phase(freq, count, vibrato_rate=vibrato_rate, vibrato_cents=vibrato_cents)
    if kind == "sine":
        if fm_index:
            mod = _phase(
                np.asarray(freq) * fm_ratio
                if not np.isscalar(freq)
                else float(freq) * fm_ratio,
                count,
            )
            return np.sin(TAU * phase + fm_index * np.sin(TAU * mod))
        return np.sin(TAU * phase)
    if kind == "square":
        return np.where(phase < duty, 1.0, -1.0)
    if kind == "triangle":
        return 2.0 * np.abs(2.0 * phase - 1.0) - 1.0
    if kind == "saw":
        return 2.0 * phase - 1.0
    raise ValueError(f"unknown oscillator {kind}")


def tone(
    freqs: float
    | np.ndarray
    | list[float | np.ndarray]
    | tuple[float | np.ndarray, ...],
    seconds: float,
    *,
    wave: str = "square",
    amp: float = 1.0,
    duty: float = 0.5,
    attack: float = 0.004,
    decay: float = 0.05,
    sustain: float = 0.65,
    release: float = 0.06,
    lowpass_hz: float | None = None,
    highpass_hz: float | None = None,
    vibrato_rate: float = 0.0,
    vibrato_cents: float = 0.0,
    noise_mix: float = 0.0,
    fm_index: float = 0.0,
    fm_ratio: float = 2.0,
    rng: np.random.Generator | None = None,
) -> np.ndarray:
    count = sample_count(seconds)
    sources = (
        [freqs] if np.isscalar(freqs) or isinstance(freqs, np.ndarray) else list(freqs)
    )
    out = np.zeros(count, dtype=np.float64)
    for idx, source in enumerate(sources):
        detune = 1.0 + 0.002 * (idx - (len(sources) - 1) / 2.0)
        part = oscillator(
            wave,
            np.asarray(source) * detune
            if isinstance(source, np.ndarray)
            else float(source) * detune,
            seconds,
            duty=duty,
            vibrato_rate=vibrato_rate,
            vibrato_cents=vibrato_cents,
            rng=rng,
            fm_index=fm_index,
            fm_ratio=fm_ratio,
        )
        out += part
    out /= max(1, len(sources))
    if noise_mix > 0.0:
        out = (1.0 - noise_mix) * out + noise_mix * oscillator(
            "noise", 1.0, seconds, rng=rng
        )
    out *= adsr(count, attack, decay, sustain, release) * amp
    if lowpass_hz is not None:
        out = lowpass(out, lowpass_hz)
    if highpass_hz is not None:
        out = highpass(out, highpass_hz)
    return out


NOTE_OFFSETS = {
    "C": 0,
    "C#": 1,
    "DB": 1,
    "D": 2,
    "D#": 3,
    "EB": 3,
    "E": 4,
    "F": 5,
    "F#": 6,
    "GB": 6,
    "G": 7,
    "G#": 8,
    "AB": 8,
    "A": 9,
    "A#": 10,
    "BB": 10,
    "B": 11,
}


def note_to_midi(note: int | str | None) -> int | None:
    if note is None:
        return None
    if isinstance(note, int):
        return note
    token = note.strip().upper()
    if token in {"R", "REST", "-"}:
        return None
    if token[-2] in {"#", "B"}:
        name = token[:-1]
        octave = int(token[-1])
    else:
        name = token[0]
        octave = int(token[1:])
    return NOTE_OFFSETS[name] + (octave + 1) * 12


def midi_to_hz(note: int | str | None) -> float | None:
    midi = note_to_midi(note)
    if midi is None:
        return None
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def chord(*notes: int | str) -> list[float]:
    return [float(midi_to_hz(note)) for note in notes if midi_to_hz(note) is not None]


def mix_at(target: np.ndarray, signal: np.ndarray, start: int) -> None:
    if start >= len(target):
        return
    end = min(len(target), start + len(signal))
    target[start:end] += signal[: end - start]


def noise_burst(
    seconds: float,
    *,
    rng: np.random.Generator,
    low_hz: float | None = None,
    high_hz: float | None = None,
    decay: float = 18.0,
    amp: float = 1.0,
) -> np.ndarray:
    burst = oscillator("noise", 1.0, seconds, rng=rng)
    t = np.arange(len(burst), dtype=np.float64) / SR
    burst *= np.exp(-t * decay) * amp
    if low_hz is not None:
        burst = lowpass(burst, low_hz)
    if high_hz is not None:
        burst = highpass(burst, high_hz)
    return burst


def kick(seconds: float = 0.36, *, amp: float = 1.0) -> np.ndarray:
    t = np.arange(sample_count(seconds), dtype=np.float64) / SR
    freq = 160.0 * np.exp(-t * 9.0) + 34.0
    body = tone(
        freq,
        seconds,
        wave="sine",
        amp=0.95,
        attack=0.0,
        decay=0.1,
        sustain=0.0,
        release=0.18,
    )
    click = noise_burst(
        seconds * 0.22,
        rng=seeded_rng(f"kick-{seconds}-{amp}"),
        high_hz=1800.0,
        decay=45.0,
        amp=0.22,
    )
    out = body
    out[: len(click)] += click
    return out * amp


def snare(seconds: float = 0.22, *, amp: float = 1.0) -> np.ndarray:
    rng = seeded_rng(f"snare-{seconds}-{amp}")
    body = tone(
        180.0,
        seconds,
        wave="triangle",
        amp=0.35,
        attack=0.0,
        decay=0.04,
        sustain=0.0,
        release=0.09,
    )
    noise = noise_burst(seconds, rng=rng, high_hz=900.0, decay=22.0, amp=1.0)
    return (body + noise) * amp


def hat(seconds: float = 0.09, *, amp: float = 1.0) -> np.ndarray:
    rng = seeded_rng(f"hat-{seconds}-{amp}")
    noise = noise_burst(seconds, rng=rng, high_hz=4500.0, decay=55.0, amp=1.0)
    return highpass(noise, 5000.0) * amp


def chiming(
    notes: list[int | str],
    step: float,
    tail: float,
    *,
    wave: str = "square",
    amp: float = 0.9,
    vib: float = 0.0,
    rng_name: str = "chime",
) -> np.ndarray:
    total = step * max(1, len(notes) - 1) + tail
    out = np.zeros(sample_count(total), dtype=np.float64)
    rng = seeded_rng(rng_name)
    for idx, item in enumerate(notes):
        freq = midi_to_hz(item)
        if freq is None:
            continue
        signal = tone(
            freq,
            tail,
            wave=wave,
            amp=amp,
            attack=0.002,
            decay=0.08,
            sustain=0.4,
            release=0.18,
            vibrato_rate=5.0,
            vibrato_cents=vib,
            lowpass_hz=4400.0,
            rng=rng,
        )
        mix_at(out, signal, sample_count(idx * step))
    return out


def render_notes(
    total_beats: float,
    bpm: float,
    events: list[tuple[float, int | str | list[int | str], float, float, dict]],
    synth,
) -> np.ndarray:
    out = np.zeros(beats_to_samples(total_beats, bpm), dtype=np.float64)
    for start, pitch, duration, velocity, kwargs in events:
        seconds = beats_to_seconds(duration, bpm)
        if isinstance(pitch, list):
            freqs = [
                float(midi_to_hz(item))
                for item in pitch
                if midi_to_hz(item) is not None
            ]
        else:
            hz = midi_to_hz(pitch)
            if hz is None:
                continue
            freqs = hz
        mix_at(
            out, synth(freqs, seconds, velocity, kwargs), beats_to_samples(start, bpm)
        )
    return out


def lead_voice(freqs, seconds: float, velocity: float, kwargs: dict) -> np.ndarray:
    return tone(
        freqs,
        seconds,
        wave="square",
        amp=0.42 * velocity,
        duty=kwargs.get("duty", 0.28),
        attack=0.004,
        decay=0.08,
        sustain=0.5,
        release=0.07,
        lowpass_hz=3600.0,
        vibrato_rate=5.6,
        vibrato_cents=kwargs.get("vibrato", 18.0),
    )


def bass_voice(freqs, seconds: float, velocity: float, kwargs: dict) -> np.ndarray:
    return tone(
        freqs,
        seconds,
        wave=kwargs.get("wave", "triangle"),
        amp=0.46 * velocity,
        attack=0.002,
        decay=0.07,
        sustain=0.74,
        release=0.05,
        lowpass_hz=kwargs.get("lowpass_hz", 1800.0),
    )


def pluck_voice(freqs, seconds: float, velocity: float, kwargs: dict) -> np.ndarray:
    return tone(
        freqs,
        seconds,
        wave=kwargs.get("wave", "saw"),
        amp=0.34 * velocity,
        attack=0.001,
        decay=0.09,
        sustain=0.18,
        release=0.05,
        lowpass_hz=kwargs.get("lowpass_hz", 2800.0),
        noise_mix=0.08,
    )


def organ_voice(freqs, seconds: float, velocity: float, kwargs: dict) -> np.ndarray:
    return tone(
        freqs,
        seconds,
        wave="organ",
        amp=0.50 * velocity,
        attack=0.03,
        decay=0.24,
        sustain=0.88,
        release=0.18,
        lowpass_hz=kwargs.get("lowpass_hz", 2200.0),
    )


def airy_pad(
    chords: list[list[int | str]], bpm: float, bars: int, *, seed: str
) -> np.ndarray:
    total = bars * 4.0
    out = np.zeros(beats_to_samples(total, bpm), dtype=np.float64)
    for bar, notes in enumerate(chords):
        seconds = beats_to_seconds(4.0, bpm)
        start = beats_to_samples(bar * 4.0, bpm)
        tone_part = tone(
            chord(*notes),
            seconds,
            wave="triangle",
            amp=0.13,
            attack=0.1,
            decay=0.3,
            sustain=0.78,
            release=0.25,
            lowpass_hz=1200.0,
            noise_mix=0.18,
            rng=seeded_rng(f"{seed}-tone-{bar}"),
        )
        wind = noise_burst(
            seconds,
            rng=seeded_rng(f"{seed}-wind-{bar}"),
            low_hz=1200.0,
            high_hz=200.0,
            decay=0.12,
            amp=0.22,
        )
        mix_at(out, tone_part + wind * 0.35, start)
    return out


def crash_site() -> np.ndarray:
    bpm = 96
    bars = 16
    chords = [
        ["D3", "A3", "D4", "F4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["F3", "C4", "F4", "A4"],
        ["C3", "G3", "C4", "E4"],
        ["G2", "D3", "G3", "Bb3"],
        ["D3", "A3", "D4", "F4"],
        ["A2", "E3", "A3", "C4"],
        ["D3", "A3", "D4", "F4"],
        ["D3", "A3", "D4", "F4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["F3", "C4", "F4", "A4"],
        ["C3", "G3", "C4", "E4"],
        ["G2", "D3", "G3", "Bb3"],
        ["A2", "E3", "A3", "C4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["A2", "E3", "A3", "C4"],
    ]
    out = airy_pad(chords, bpm, bars, seed="crash-site")
    bass = []
    arp = []
    ticks = np.zeros_like(out)
    for bar, notes in enumerate(chords):
        root = notes[0]
        fifth = notes[1]
        bass.extend(
            [
                (
                    bar * 4.0 + 0.0,
                    root,
                    1.5,
                    0.95,
                    {"wave": "triangle", "lowpass_hz": 900.0},
                ),
                (
                    bar * 4.0 + 2.0,
                    fifth,
                    1.0,
                    0.75,
                    {"wave": "triangle", "lowpass_hz": 1100.0},
                ),
            ]
        )
        pattern = [
            notes[0],
            notes[2],
            notes[1],
            notes[3],
            notes[2],
            notes[1],
            notes[2],
            notes[3],
        ]
        if bar >= 8:
            pattern = [
                notes[2],
                notes[3],
                notes[1],
                notes[2],
                notes[3],
                notes[2],
                notes[1],
                notes[0],
            ]
        for step, note in enumerate(pattern):
            velocity = 0.34 if step % 4 else 0.42
            arp.append(
                (
                    bar * 4.0 + step * 0.5,
                    note,
                    0.42,
                    velocity,
                    {"wave": "triangle", "lowpass_hz": 2500.0},
                )
            )
        for beat in range(4):
            pos = beats_to_samples(bar * 4.0 + beat + 0.5, bpm)
            mix_at(ticks, hat(0.045, amp=0.11 + 0.02 * (beat % 2)), pos)
    mix_at(out, render_notes(bars * 4.0, bpm, bass, bass_voice), 0)
    mix_at(out, render_notes(bars * 4.0, bpm, arp, pluck_voice), 0)
    mix_at(out, ticks, 0)
    return finalize(out, MUSIC_TARGET_DB, fade_seconds=0.02)


def hull_cathedral() -> np.ndarray:
    bpm = 108
    bars = 16
    chords = [
        ["D3", "A3", "D4", "F4"],
        ["G2", "D3", "G3", "Bb3"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["C3", "G3", "C4", "E4"],
        ["F2", "C3", "F3", "A3"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
        ["G2", "D3", "G3", "Bb3"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["G2", "D3", "G3", "Bb3"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
    ]
    out = np.zeros(beats_to_samples(bars * 4.0, bpm), dtype=np.float64)
    organ = render_notes(
        bars * 4.0,
        bpm,
        [
            (bar * 4.0, notes, 3.8, 0.9 if bar % 4 else 1.0, {"lowpass_hz": 2000.0})
            for bar, notes in enumerate(chords)
        ],
        organ_voice,
    )
    mix_at(out, organ, 0)
    melody_notes = [
        "A4",
        "D5",
        "F5",
        "E5",
        "D5",
        "C5",
        "Bb4",
        "A4",
        "G4",
        "A4",
        "D5",
        "C#5",
        "D5",
        "F5",
        "E5",
        "D5",
        "F5",
        "G5",
        "A5",
        "F5",
        "E5",
        "D5",
        "C5",
        "Bb4",
        "A4",
        "C5",
        "D5",
        "E5",
        "F5",
        "E5",
        "D5",
        "A4",
    ]
    melody = []
    for idx, note in enumerate(melody_notes):
        start = idx * 2.0
        duration = 1.4 if idx % 8 in {2, 6} else 1.0
        melody.append(
            (start, note, duration, 0.95 if idx % 8 == 0 else 0.75, {"vibrato": 20.0})
        )
    bass = []
    plucks = []
    drums = np.zeros_like(out)
    for bar, notes in enumerate(chords):
        walk = [notes[0], notes[1], notes[2], notes[1]]
        for beat, note in enumerate(walk):
            bass.append(
                (
                    bar * 4.0 + beat,
                    note,
                    0.9,
                    0.65 + 0.05 * (beat == 0),
                    {"wave": "triangle", "lowpass_hz": 1400.0},
                )
            )
            plucks.append(
                (
                    bar * 4.0 + beat + 0.5,
                    [notes[1], notes[3]],
                    0.45,
                    0.46,
                    {"wave": "saw", "lowpass_hz": 2400.0},
                )
            )
        for beat in range(4):
            if beat in {0, 2}:
                mix_at(
                    drums,
                    kick(0.22, amp=0.16 if beat == 0 else 0.11),
                    beats_to_samples(bar * 4.0 + beat, bpm),
                )
            mix_at(
                drums,
                hat(0.055, amp=0.09),
                beats_to_samples(bar * 4.0 + beat + 0.5, bpm),
            )
    mix_at(out, render_notes(bars * 4.0, bpm, melody, lead_voice), 0)
    mix_at(out, render_notes(bars * 4.0, bpm, bass, bass_voice), 0)
    mix_at(out, render_notes(bars * 4.0, bpm, plucks, pluck_voice), 0)
    mix_at(out, drums, 0)
    return finalize(out, MUSIC_TARGET_DB, fade_seconds=0.02)


def outer_hull() -> np.ndarray:
    bpm = 128
    bars = 16
    chords = [
        ["D3", "A3", "D4", "F4"],
        ["C3", "G3", "C4", "E4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
        ["C3", "G3", "C4", "E4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["A2", "E3", "A3", "C#4"],
        ["G2", "D3", "G3", "Bb3"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["C3", "G3", "C4", "E4"],
        ["A2", "E3", "A3", "C#4"],
        ["D3", "A3", "D4", "F4"],
        ["C3", "G3", "C4", "E4"],
        ["Bb2", "F3", "Bb3", "D4"],
        ["A2", "E3", "A3", "C#4"],
    ]
    total = bars * 4.0
    out = np.zeros(beats_to_samples(total, bpm), dtype=np.float64)
    bass = []
    arp = []
    snare_track = np.zeros_like(out)
    wind = np.zeros_like(out)
    for bar, notes in enumerate(chords):
        for step in range(16):
            start = bar * 4.0 + step * 0.25
            pitch = notes[0] if step % 4 != 3 else notes[1]
            bass.append(
                (
                    start,
                    pitch,
                    0.18,
                    0.48 + 0.04 * (step % 4 == 0),
                    {"wave": "square", "lowpass_hz": 1700.0},
                )
            )
        arp_notes = [
            notes[1],
            notes[3],
            notes[2],
            notes[3],
            notes[1],
            notes[2],
            notes[3],
            notes[2],
        ]
        for step, note in enumerate(arp_notes):
            arp.append(
                (
                    bar * 4.0 + step * 0.5,
                    note,
                    0.22,
                    0.40,
                    {"wave": "square", "lowpass_hz": 3000.0},
                )
            )
        for beat in range(4):
            mix_at(
                snare_track,
                hat(0.045, amp=0.10),
                beats_to_samples(bar * 4.0 + beat + 0.25, bpm),
            )
            mix_at(
                snare_track,
                hat(0.04, amp=0.08),
                beats_to_samples(bar * 4.0 + beat + 0.75, bpm),
            )
        mix_at(snare_track, kick(0.18, amp=0.16), beats_to_samples(bar * 4.0, bpm))
        mix_at(
            snare_track, snare(0.16, amp=0.16), beats_to_samples(bar * 4.0 + 1.0, bpm)
        )
        mix_at(
            snare_track, snare(0.16, amp=0.15), beats_to_samples(bar * 4.0 + 3.0, bpm)
        )
        sweep = noise_burst(
            beats_to_seconds(4.0, bpm),
            rng=seeded_rng(f"outer-wind-{bar}"),
            low_hz=1600.0,
            high_hz=500.0,
            decay=0.35,
            amp=0.18,
        )
        mix_at(wind, sweep, beats_to_samples(bar * 4.0, bpm))
    if len(snare_track) > 0:
        fill_start = beats_to_samples(total - 1.0, bpm)
        for step in range(8):
            mix_at(
                snare_track,
                snare(0.09, amp=0.09 + 0.01 * step),
                fill_start + step * sample_count(0.06),
            )
    mix_at(out, render_notes(total, bpm, bass, bass_voice), 0)
    mix_at(out, render_notes(total, bpm, arp, pluck_voice), 0)
    mix_at(out, snare_track + wind * 0.28, 0)
    return finalize(out, MUSIC_TARGET_DB, fade_seconds=0.02)


def boss_krate() -> np.ndarray:
    bpm = 150
    bars = 16
    total = bars * 4.0
    out = np.zeros(beats_to_samples(total, bpm), dtype=np.float64)
    roots = [
        "D2",
        "D2",
        "F2",
        "Eb2",
        "D2",
        "C2",
        "Bb1",
        "A1",
        "D2",
        "D2",
        "F2",
        "Eb2",
        "D2",
        "C2",
        "Bb1",
        "A1",
    ]
    bass = []
    stabs = []
    motif = []
    drums = np.zeros_like(out)
    for bar, root in enumerate(roots):
        pattern = [0.0, 0.75, 1.5, 2.0, 2.75, 3.25]
        for step, start in enumerate(pattern):
            bass.append(
                (
                    bar * 4.0 + start,
                    root,
                    0.22,
                    0.7 + 0.08 * (step == 0),
                    {"wave": "square", "lowpass_hz": 1350.0},
                )
            )
        stab_note = note_to_midi(root) + 19
        for start in [0.5, 1.75, 3.0]:
            stabs.append(
                (
                    bar * 4.0 + start,
                    [stab_note, stab_note + 7],
                    0.18,
                    0.55,
                    {"wave": "square", "lowpass_hz": 2400.0},
                )
            )
        if bar % 4 == 3:
            motif.extend(
                [
                    (bar * 4.0 + 2.0, "D4", 0.5, 0.7, {"vibrato": 10.0}),
                    (bar * 4.0 + 2.5, "F4", 0.5, 0.72, {"vibrato": 12.0}),
                    (bar * 4.0 + 3.0, "G4", 0.5, 0.74, {"vibrato": 14.0}),
                    (bar * 4.0 + 3.5, "A4", 0.45, 0.80, {"vibrato": 18.0}),
                ]
            )
        for beat in np.arange(0.0, 4.0, 0.5):
            mix_at(
                drums,
                hat(0.035, amp=0.08),
                beats_to_samples(bar * 4.0 + float(beat), bpm),
            )
        for beat in [0.0, 1.5, 2.0, 2.75]:
            mix_at(drums, kick(0.17, amp=0.18), beats_to_samples(bar * 4.0 + beat, bpm))
        for beat in [1.0, 3.0]:
            mix_at(
                drums, snare(0.14, amp=0.20), beats_to_samples(bar * 4.0 + beat, bpm)
            )
    mix_at(out, render_notes(total, bpm, bass, bass_voice), 0)
    mix_at(out, render_notes(total, bpm, stabs, pluck_voice), 0)
    mix_at(out, render_notes(total, bpm, motif, lead_voice), 0)
    mix_at(out, drums, 0)
    return finalize(np.tanh(out * 1.45), MUSIC_TARGET_DB, fade_seconds=0.02)


def build_sfx_bank() -> dict[str, np.ndarray]:
    bank: dict[str, np.ndarray] = {}

    def put(name: str, signal: np.ndarray) -> None:
        bank[name] = finalize(signal, SFX_TARGET_DB)

    def combine(*signals: np.ndarray) -> np.ndarray:
        size = max(len(signal) for signal in signals)
        out = np.zeros(size, dtype=np.float64)
        for signal in signals:
            out[: len(signal)] += signal
        return out

    def laser(
        name: str,
        start_hz: float,
        end_hz: float,
        seconds: float,
        *,
        wave: str = "square",
        noise: float = 0.0,
        duty: float = 0.25,
        fm: float = 0.0,
        lowpass_hz: float = 4200.0,
    ) -> None:
        put(
            name,
            tone(
                freq_contour(start_hz, end_hz, seconds),
                seconds,
                wave=wave,
                amp=0.95,
                duty=duty,
                attack=0.0,
                decay=seconds * 0.35,
                sustain=0.25,
                release=seconds * 0.25,
                lowpass_hz=lowpass_hz,
                noise_mix=noise,
                fm_index=fm,
                rng=seeded_rng(name),
            ),
        )

    def impact(
        name: str,
        pitch: float,
        seconds: float,
        *,
        brightness: float = 1800.0,
        noise_decay: float = 20.0,
    ) -> None:
        rng = seeded_rng(name)
        boom = tone(
            freq_contour(pitch * 1.8, pitch, seconds),
            seconds,
            wave="triangle",
            amp=0.8,
            attack=0.0,
            decay=seconds * 0.2,
            sustain=0.0,
            release=seconds * 0.35,
            lowpass_hz=brightness,
        )
        dirt = noise_burst(
            seconds,
            rng=rng,
            high_hz=250.0,
            low_hz=brightness,
            decay=noise_decay,
            amp=0.55,
        )
        put(name, boom + dirt)

    def ring(
        name: str,
        notes: list[int | str],
        *,
        step: float,
        tail: float,
        wave: str = "square",
        amp: float = 0.7,
    ) -> None:
        put(
            name, chiming(notes, step, tail, wave=wave, amp=amp, vib=8.0, rng_name=name)
        )

    def boing(name: str, start_hz: float, end_hz: float, seconds: float) -> None:
        contour = freq_contour(start_hz, end_hz, seconds)
        put(
            name,
            tone(
                contour,
                seconds,
                wave="triangle",
                amp=0.88,
                attack=0.0,
                decay=seconds * 0.18,
                sustain=0.3,
                release=seconds * 0.2,
                lowpass_hz=2200.0,
            )
            + tone(
                contour * 1.98,
                seconds,
                wave="sine",
                amp=0.22,
                attack=0.0,
                decay=seconds * 0.14,
                sustain=0.0,
                release=seconds * 0.12,
            ),
        )

    laser("jump", 480.0, 860.0, 0.13, duty=0.28)
    put(
        "double_jump",
        combine(
            tone(
                freq_contour(220.0, 1240.0, 0.26),
                0.26,
                wave="triangle",
                amp=0.9,
                attack=0.0,
                decay=0.08,
                sustain=0.35,
                release=0.08,
                lowpass_hz=2600.0,
                noise_mix=0.18,
                rng=seeded_rng("double_jump"),
            ),
            noise_burst(
                0.14, rng=seeded_rng("dj-noise"), high_hz=1800.0, decay=28.0, amp=0.24
            ),
        ),
    )
    impact("land", 72.0, 0.11, brightness=900.0)
    put(
        "wall_kick",
        combine(
            tone(
                freq_contour(360.0, 920.0, 0.12),
                0.12,
                wave="square",
                amp=0.82,
                attack=0.0,
                decay=0.03,
                sustain=0.22,
                release=0.05,
                lowpass_hz=3400.0,
            ),
            tone(
                620.0,
                0.03,
                wave="triangle",
                amp=0.25,
                attack=0.0,
                decay=0.02,
                sustain=0.0,
                release=0.01,
            ),
        ),
    )
    put(
        "slide",
        noise_burst(0.18, rng=seeded_rng("slide"), high_hz=1400.0, decay=12.0, amp=0.55)
        + tone(
            freq_contour(440.0, 180.0, 0.18),
            0.18,
            wave="triangle",
            amp=0.28,
            attack=0.0,
            decay=0.06,
            sustain=0.05,
            release=0.04,
            lowpass_hz=2200.0,
        ),
    )
    put(
        "backdash",
        combine(
            noise_burst(
                0.16, rng=seeded_rng("backdash"), high_hz=1800.0, decay=16.0, amp=0.35
            ),
            tone(
                freq_contour(520.0, 190.0, 0.17),
                0.17,
                wave="square",
                amp=0.58,
                attack=0.0,
                decay=0.04,
                sustain=0.1,
                release=0.06,
                lowpass_hz=3000.0,
            ),
        ),
    )
    put(
        "spaceball_morph",
        combine(
            tone(
                freq_contour(510.0, 150.0, 0.18),
                0.18,
                wave="triangle",
                amp=0.65,
                attack=0.0,
                decay=0.04,
                sustain=0.2,
                release=0.07,
                lowpass_hz=1800.0,
            ),
            noise_burst(
                0.08,
                rng=seeded_rng("spaceball_morph"),
                high_hz=600.0,
                decay=24.0,
                amp=0.22,
            ),
        ),
    )
    put(
        "spaceball_roll",
        combine(
            tone(
                340.0,
                0.08,
                wave="triangle",
                amp=0.45,
                attack=0.0,
                decay=0.01,
                sustain=0.08,
                release=0.01,
                lowpass_hz=1800.0,
            ),
            noise_burst(
                0.03,
                rng=seeded_rng("spaceball_roll"),
                high_hz=2000.0,
                decay=36.0,
                amp=0.08,
            ),
        ),
    )
    for name, start, end, seconds, brightness in [
        ("swing_1", 220.0, 560.0, 0.16, 2600.0),
        ("swing_2", 260.0, 780.0, 0.18, 3200.0),
        ("swing_3", 180.0, 980.0, 0.24, 3600.0),
    ]:
        put(
            name,
            combine(
                noise_burst(
                    seconds, rng=seeded_rng(name), high_hz=1600.0, decay=10.0, amp=0.42
                ),
                tone(
                    freq_contour(start, end, seconds),
                    seconds,
                    wave="triangle",
                    amp=0.44,
                    attack=0.0,
                    decay=seconds * 0.35,
                    sustain=0.1,
                    release=seconds * 0.22,
                    lowpass_hz=brightness,
                ),
            ),
        )
    impact("hit_1", 110.0, 0.10, brightness=1300.0)
    impact("hit_2", 100.0, 0.12, brightness=1600.0)
    impact("hit_3", 90.0, 0.14, brightness=1900.0)
    ring("crit", ["D5", "A5", "D6"], step=0.03, tail=0.24, wave="square", amp=0.72)
    put(
        "home_run",
        combine(
            bank["hit_3"] * 0.9,
            chiming(
                ["D4", "A4", "D5"],
                0.0,
                0.75,
                wave="triangle",
                amp=0.48,
                vib=4.0,
                rng_name="home_run",
            ),
        ),
    )
    laser(
        "mitt_shot",
        900.0,
        420.0,
        0.12,
        wave="square",
        noise=0.03,
        duty=0.18,
        lowpass_hz=5200.0,
    )
    put(
        "mitt_charge_loop",
        tone(
            freq_contour(220.0, 720.0, 0.8),
            0.8,
            wave="triangle",
            amp=0.56,
            attack=0.02,
            decay=0.22,
            sustain=0.7,
            release=0.14,
            lowpass_hz=2600.0,
            vibrato_rate=4.0,
            vibrato_cents=5.0,
        )
        + tone(
            freq_contour(330.0, 1080.0, 0.8),
            0.8,
            wave="sine",
            amp=0.16,
            attack=0.01,
            decay=0.2,
            sustain=0.35,
            release=0.12,
        ),
    )
    put(
        "mitt_charged_shot",
        combine(
            tone(
                freq_contour(1600.0, 280.0, 0.25),
                0.25,
                wave="square",
                amp=0.92,
                attack=0.0,
                decay=0.04,
                sustain=0.15,
                release=0.08,
                lowpass_hz=5200.0,
                noise_mix=0.08,
                rng=seeded_rng("mitt_charged_shot"),
            ),
            noise_burst(
                0.08,
                rng=seeded_rng("mitt_charged_shot-hit"),
                high_hz=2500.0,
                decay=35.0,
                amp=0.18,
            ),
        ),
    )
    laser("hurt", 520.0, 180.0, 0.18, wave="square", duty=0.36, lowpass_hz=2800.0)
    put(
        "death",
        combine(
            chiming(
                ["D4", "Bb3", "G3", "D3"],
                0.12,
                0.55,
                wave="triangle",
                amp=0.42,
                vib=0.0,
                rng_name="death",
            ),
            noise_burst(
                0.32,
                rng=seeded_rng("death-noise"),
                high_hz=1200.0,
                decay=12.0,
                amp=0.18,
            ),
        ),
    )
    put(
        "enemy_die",
        combine(
            chiming(
                ["D5", "A4", "D4"],
                0.06,
                0.28,
                wave="square",
                amp=0.46,
                vib=0.0,
                rng_name="enemy_die",
            ),
            noise_burst(
                0.12,
                rng=seeded_rng("enemy_die-noise"),
                high_hz=1600.0,
                decay=18.0,
                amp=0.16,
            ),
        ),
    )
    impact("enemy_hit", 82.0, 0.09, brightness=1000.0)
    put(
        "bat_screech",
        tone(
            freq_contour(980.0, 1880.0, 0.18),
            0.18,
            wave="sine",
            amp=0.85,
            attack=0.0,
            decay=0.05,
            sustain=0.1,
            release=0.04,
            fm_index=2.3,
            fm_ratio=2.4,
        ),
    )
    put(
        "zombie_groan",
        tone(
            freq_contour(120.0, 92.0, 0.44),
            0.44,
            wave="triangle",
            amp=0.72,
            attack=0.02,
            decay=0.08,
            sustain=0.7,
            release=0.12,
            lowpass_hz=700.0,
            vibrato_rate=3.3,
            vibrato_cents=36.0,
        ),
    )
    boing("hunch_hop", 150.0, 420.0, 0.22)
    ring("pickup_coin", ["D6", "A6"], step=0.04, tail=0.16, wave="square", amp=0.68)
    ring(
        "pickup_gem",
        ["D6", "F6", "A6"],
        step=0.03,
        tail=0.22,
        wave="triangle",
        amp=0.62,
    )
    ring(
        "pickup_item_common",
        ["A5", "D6"],
        step=0.05,
        tail=0.18,
        wave="triangle",
        amp=0.56,
    )
    ring(
        "pickup_item_magic",
        ["A5", "D6", "F6"],
        step=0.04,
        tail=0.28,
        wave="triangle",
        amp=0.60,
    )
    ring(
        "pickup_item_rare",
        ["D6", "F6", "A6", "D7"],
        step=0.03,
        tail=0.40,
        wave="triangle",
        amp=0.64,
    )
    ring(
        "level_up",
        ["D4", "F4", "A4", "D5", "F5", "A5"],
        step=0.18,
        tail=0.42,
        wave="square",
        amp=0.56,
    )
    ring("tally_tick", ["D6"], step=0.0, tail=0.12, wave="triangle", amp=0.48)
    ring(
        "tally_complete",
        ["D5", "F5", "A5"],
        step=0.10,
        tail=0.25,
        wave="triangle",
        amp=0.54,
    )
    ring(
        "ability_get",
        ["D4", "F4", "A4", "C5", "D5"],
        step=0.34,
        tail=0.58,
        wave="square",
        amp=0.54,
    )
    put(
        "seal_prompt",
        combine(
            tone(
                freq_contour(140.0, 560.0, 0.9),
                0.9,
                wave="sine",
                amp=0.45,
                attack=0.06,
                decay=0.20,
                sustain=0.78,
                release=0.18,
            ),
            noise_burst(
                0.9,
                rng=seeded_rng("seal_prompt"),
                low_hz=1400.0,
                high_hz=300.0,
                decay=0.4,
                amp=0.18,
            ),
        ),
    )
    put(
        "seal_success",
        combine(
            chiming(
                ["D4", "A4", "D5", "F5"],
                0.06,
                0.52,
                wave="square",
                amp=0.48,
                vib=8.0,
                rng_name="seal_success",
            ),
            noise_burst(
                0.5,
                rng=seeded_rng("seal_success-noise"),
                high_hz=2400.0,
                decay=18.0,
                amp=0.14,
            ),
        ),
    )
    put(
        "seal_fail",
        tone(
            freq_contour(660.0, 180.0, 0.42),
            0.42,
            wave="triangle",
            amp=0.68,
            attack=0.0,
            decay=0.14,
            sustain=0.3,
            release=0.08,
            lowpass_hz=1800.0,
            vibrato_rate=5.0,
            vibrato_cents=24.0,
        ),
    )
    put(
        "boss_telegraph",
        combine(
            tone(
                freq_contour(180.0, 960.0, 0.7),
                0.7,
                wave="square",
                amp=0.54,
                attack=0.02,
                decay=0.12,
                sustain=0.72,
                release=0.16,
                lowpass_hz=2600.0,
            ),
            hat(0.06, amp=0.10),
        ),
    )
    impact("boss_hit", 74.0, 0.16, brightness=1700.0)
    put(
        "boss_slam",
        combine(
            kick(0.44, amp=1.1),
            noise_burst(
                0.50, rng=seeded_rng("boss_slam"), high_hz=900.0, decay=14.0, amp=0.40
            ),
        ),
    )
    put(
        "boss_roar",
        combine(
            tone(
                freq_contour(86.0, 120.0, 0.95),
                0.95,
                wave="saw",
                amp=0.56,
                attack=0.03,
                decay=0.12,
                sustain=0.72,
                release=0.22,
                lowpass_hz=1200.0,
                vibrato_rate=6.0,
                vibrato_cents=18.0,
            ),
            noise_burst(
                0.8, rng=seeded_rng("boss_roar"), high_hz=1600.0, decay=0.9, amp=0.18
            ),
        ),
    )
    put(
        "boss_die",
        combine(
            chiming(
                ["D4", "C4", "Bb3", "G3"],
                0.22,
                0.60,
                wave="triangle",
                amp=0.34,
                vib=0.0,
                rng_name="boss_die",
            ),
            noise_burst(
                1.8,
                rng=seeded_rng("boss_die-noise"),
                high_hz=1200.0,
                decay=2.0,
                amp=0.22,
            ),
            kick(0.36, amp=0.55),
        ),
    )
    put(
        "door_open",
        combine(
            tone(
                110.0,
                0.08,
                wave="triangle",
                amp=0.38,
                attack=0.0,
                decay=0.03,
                sustain=0.0,
                release=0.04,
            ),
            tone(
                freq_contour(240.0, 520.0, 0.24),
                0.24,
                wave="square",
                amp=0.36,
                attack=0.0,
                decay=0.05,
                sustain=0.25,
                release=0.06,
                lowpass_hz=2200.0,
            ),
        ),
    )
    put(
        "door_locked",
        combine(
            tone(
                130.0,
                0.08,
                wave="triangle",
                amp=0.48,
                attack=0.0,
                decay=0.03,
                sustain=0.0,
                release=0.04,
            ),
            tone(
                freq_contour(360.0, 220.0, 0.16),
                0.16,
                wave="square",
                amp=0.28,
                attack=0.0,
                decay=0.03,
                sustain=0.1,
                release=0.04,
                lowpass_hz=1600.0,
            ),
        ),
    )
    ring("save_pod", ["D5", "F5", "A5"], step=0.0, tail=0.70, wave="triangle", amp=0.46)
    put(
        "warp_pipe",
        tone(
            freq_contour(420.0, 120.0, 0.36),
            0.36,
            wave="triangle",
            amp=0.70,
            attack=0.0,
            decay=0.10,
            sustain=0.4,
            release=0.10,
            lowpass_hz=2200.0,
            vibrato_rate=8.0,
            vibrato_cents=10.0,
        ),
    )
    put(
        "hollow_tonk",
        combine(
            tone(
                [220.0, 330.0],
                0.16,
                wave="triangle",
                amp=0.46,
                attack=0.0,
                decay=0.04,
                sustain=0.1,
                release=0.06,
                lowpass_hz=1400.0,
            ),
            noise_burst(
                0.07,
                rng=seeded_rng("hollow_tonk"),
                high_hz=1200.0,
                decay=28.0,
                amp=0.18,
            ),
        ),
    )
    put(
        "wall_break",
        combine(
            bank["boss_slam"] * 0.55,
            noise_burst(
                0.45, rng=seeded_rng("wall_break"), high_hz=1400.0, decay=12.0, amp=0.26
            ),
        ),
    )
    ring("menu_move", ["A5"], step=0.0, tail=0.08, wave="square", amp=0.34)
    ring("menu_select", ["D6", "F6"], step=0.03, tail=0.14, wave="square", amp=0.42)
    ring("menu_back", ["F5", "D5"], step=0.04, tail=0.14, wave="triangle", amp=0.38)
    ring("menu_deny", ["C5"], step=0.0, tail=0.14, wave="square", amp=0.40)
    ring("equip_item", ["D5", "A5"], step=0.05, tail=0.18, wave="triangle", amp=0.42)
    put(
        "upgrade_success",
        combine(
            chiming(
                ["D4", "A4", "D5"],
                0.08,
                0.48,
                wave="triangle",
                amp=0.48,
                vib=4.0,
                rng_name="upgrade_success",
            ),
            noise_burst(
                0.30,
                rng=seeded_rng("upgrade_success-noise"),
                high_hz=2600.0,
                decay=20.0,
                amp=0.12,
            ),
        ),
    )
    ring("upgrade_fail", ["C5"], step=0.0, tail=0.16, wave="square", amp=0.42)
    ring("toast", ["D6"], step=0.0, tail=0.10, wave="triangle", amp=0.44)
    ring("hey_listen", ["A6", "D7"], step=0.12, tail=0.12, wave="square", amp=0.42)
    put(
        "dialogue_blip",
        tone(
            freq_contour(420.0, 500.0, 0.045),
            0.045,
            wave="square",
            amp=0.34,
            attack=0.0,
            decay=0.01,
            sustain=0.2,
            release=0.01,
            lowpass_hz=2400.0,
            vibrato_rate=20.0,
            vibrato_cents=12.0,
        ),
    )
    put(
        "title_start",
        combine(
            chiming(
                ["D3", "A3", "D4", "F4"],
                0.0,
                1.1,
                wave="organ",
                amp=0.45,
                vib=0.0,
                rng_name="title_start",
            ),
            kick(0.26, amp=0.34),
            noise_burst(
                0.20,
                rng=seeded_rng("title_start-noise"),
                high_hz=2000.0,
                decay=18.0,
                amp=0.12,
            ),
        ),
    )
    return bank


MUSIC_BUILDERS = {
    "boss_krate": (boss_krate, 150),
    "crash_site": (crash_site, 96),
    "hull_cathedral": (hull_cathedral, 108),
    "outer_hull": (outer_hull, 128),
}


def collect_stats(rel_path: str, signal: np.ndarray) -> dict[str, float | str]:
    return {
        "name": rel_path,
        "duration": len(signal) / SR,
        "peak_db": peak_db(signal),
        "rms_db": rms_db(signal),
    }


def generate_assets(out_dir: Path) -> tuple[list[dict[str, float | str]], dict]:
    (out_dir / "sfx").mkdir(parents=True, exist_ok=True)
    (out_dir / "music").mkdir(parents=True, exist_ok=True)
    for stale in list((out_dir / "sfx").glob("*.wav")) + list(
        (out_dir / "music").glob("*.wav")
    ):
        stale.unlink()
    if (out_dir / "manifest.json").exists():
        (out_dir / "manifest.json").unlink()
    stats: list[dict[str, float | str]] = []
    manifest = {"version": 1, "sfx": {}, "music": {}}

    for name, signal in sorted(build_sfx_bank().items()):
        path = out_dir / "sfx" / f"{name}.wav"
        write_wav(path, signal)
        stats.append(collect_stats(f"sfx/{name}.wav", signal))
        manifest["sfx"][name] = {"file": f"sfx/{name}.wav", "volume_db": 0.0}

    for name, (builder, bpm) in sorted(MUSIC_BUILDERS.items()):
        signal = builder()
        path = out_dir / "music" / f"{name}.wav"
        write_wav(path, signal)
        discontinuity = abs(float(signal[0]) - float(signal[-1]))
        stats.append(
            collect_stats(f"music/{name}.wav", signal)
            | {"loop_discontinuity": discontinuity}
        )
        manifest["music"][name] = {
            "file": f"music/{name}.wav",
            "loop_begin": 0,
            "loop_end": len(signal),
            "volume_db": -6.0,
            "bpm": bpm,
        }

    with (out_dir / "manifest.json").open(
        "w", encoding="utf-8", newline="\n"
    ) as handle:
        json.dump(manifest, handle, indent=2, sort_keys=True)
        handle.write("\n")
    return stats, manifest


def tree_hashes(root: Path) -> dict[str, str]:
    hashes: dict[str, str] = {}
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel == "manifest.json" or rel.endswith(".wav"):
            hashes[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    return hashes


def compare_tree(expected: Path, actual: Path) -> bool:
    left = tree_hashes(expected)
    right = tree_hashes(actual)
    if left == right:
        return True
    left_keys = sorted(set(left) - set(right))
    right_keys = sorted(set(right) - set(left))
    changed = sorted(
        path for path in set(left) & set(right) if left[path] != right[path]
    )
    for label, items in [
        ("missing-from-generated", left_keys),
        ("extra-in-generated", right_keys),
        ("changed", changed),
    ]:
        if items:
            print(f"{label}:")
            for item in items:
                print(f"  {item}")
    return False


def print_stats(stats: list[dict[str, float | str]]) -> None:
    print(f"{'name':32} {'sec':>7} {'peak':>8} {'rms':>8} {'loop_d':>8}")
    print("-" * 68)
    for entry in stats:
        loop_delta = entry.get("loop_discontinuity", "")
        loop_text = f"{float(loop_delta):8.5f}" if loop_delta != "" else " " * 8
        print(
            f"{str(entry['name']):32} "
            f"{float(entry['duration']):7.3f} "
            f"{float(entry['peak_db']):8.2f} "
            f"{float(entry['rms_db']):8.2f} "
            f"{loop_text}"
        )
        if float(entry["peak_db"]) > 0.0:
            raise ValueError(f"clipping detected in {entry['name']}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate deterministic procedural audio for VetroMania."
    )
    parser.add_argument(
        "--out",
        type=Path,
        default=DEFAULT_OUT,
        help="Output directory (default: game/assets/audio)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Regenerate into a temp dir and fail if output differs.",
    )
    args = parser.parse_args()

    if args.check:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_out = Path(temp_dir)
            stats, _ = generate_assets(temp_out)
            print_stats(stats)
            if not compare_tree(args.out, temp_out):
                return 1
            return 0

    stats, _ = generate_assets(args.out)
    print_stats(stats)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
