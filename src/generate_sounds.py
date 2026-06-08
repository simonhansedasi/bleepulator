#!/usr/bin/env python3
"""Bleepulator — FM-synthesized droid sound theme generator."""

import json
import numpy as np
import wave
import os

SAMPLE_RATE = 44100
OUT_DIR = os.path.expanduser("~/.local/share/sounds/bleepulator/stereo")
DEFS_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sound_defs.json")


# ── FM synthesis primitives ──────────────────────────────────────────────────

def _env(n, attack=0.005, decay=0.03, sustain=0.85, release=0.1):
    env = np.ones(n)
    a = max(1, int(attack * SAMPLE_RATE))
    d = max(1, int(decay * SAMPLE_RATE))
    r = max(1, int(release * SAMPLE_RATE))
    env[:a] = np.linspace(0, 1, a)
    if a + d < n:
        env[a:a+d] = np.linspace(1, sustain, d)
    if r < n:
        env[-r:] = np.linspace(env[-r], 0, r)
    return env


def chirp(dur, f0, f1, mf=0, md=0, amp=0.8):
    """FM sweep from f0 to f1. mf=modulator freq, md=modulator depth."""
    n = int(dur * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    freqs = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(freqs) / SAMPLE_RATE
    mod = md * np.sin(2 * np.pi * mf * t) if mf > 0 else 0
    return np.sin(phase + mod) * _env(n) * amp


def gap(dur=0.04):
    return np.zeros(int(dur * SAMPLE_RATE))


def normalize(sig, peak=0.85):
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig


# ── Data-driven synthesis ────────────────────────────────────────────────────

def load_defs():
    with open(DEFS_PATH) as f:
        return json.load(f)


def synthesize(segments):
    """Build a waveform from a list of segment dicts (chirp or gap)."""
    parts = []
    for seg in segments:
        if seg["type"] == "chirp":
            parts.append(chirp(
                seg["dur"], seg["f0"], seg["f1"],
                mf=seg.get("mf", 0), md=seg.get("md", 0), amp=seg.get("amp", 0.8)
            ))
        elif seg["type"] == "gap":
            parts.append(gap(seg["dur"]))
    return np.concatenate(parts) if parts else np.zeros(1)


# ── Event -> sound mapping ───────────────────────────────────────────────────
# Maps each freedesktop event name to a key in sound_defs.json.

EVENT_MAP = {
    "bell":                       "bell",
    "dialog-error":               "error",
    "dialog-warning":             "warning",
    "dialog-information":         "info",
    "dialog-question":            "info",
    "message-new-instant":        "message",
    "message-new-email":          "message",
    "audio-volume-change":        "volume",
    "battery-low":                "battery_low",
    "window-attention-active":    "attention",
    "window-attention-inactive":  "attention",
    "complete":                   "complete",
    "trash-empty":                "trash",
    "desktop-login":              "login",
    "service-login":              "login",
    "system-ready":               "login",
    "suspend-resume":             "login",
    "desktop-logout":             "logout",
    "service-logout":             "logout",
    "suspend-start":              "logout",
    "power-plug":                 "volume",
    "power-unplug":               "trash",
    "window-close":               "window_close",
    "window-minimized":           "minimize",
    "window-maximized":           "maximize",
    "window-unminimized":         "maximize",
}


# ── Output ───────────────────────────────────────────────────────────────────

def save_wav(path, signal):
    signal = normalize(signal)
    samples = np.clip(signal * 32767, -32767, 32767).astype(np.int16)
    stereo = np.column_stack([samples, samples])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'w') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(stereo.tobytes())


def main():
    defs = load_defs()
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing sounds to {OUT_DIR}")
    for event, sound_key in EVENT_MAP.items():
        sig = synthesize(defs[sound_key]["segments"])
        path = os.path.join(OUT_DIR, f"{event}.wav")
        save_wav(path, sig)
        print(f"  {event}.wav")
    print(f"\nGenerated {len(EVENT_MAP)} sounds.")


if __name__ == "__main__":
    main()
