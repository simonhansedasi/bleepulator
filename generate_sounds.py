#!/usr/bin/env python3
"""Bleepulator — FM-synthesized droid sound theme generator."""

import numpy as np
import wave
import os

SAMPLE_RATE = 44100
OUT_DIR = os.path.expanduser("~/.local/share/sounds/bleepulator/stereo")


# ── primitives ──────────────────────────────────────────────────────────────

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
    """FM sweep from f0 → f1. mf=modulator freq, md=modulator depth."""
    n = int(dur * SAMPLE_RATE)
    t = np.arange(n) / SAMPLE_RATE
    freqs = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(freqs) / SAMPLE_RATE
    mod = md * np.sin(2 * np.pi * mf * t) if mf > 0 else 0
    return np.sin(phase + mod) * _env(n) * amp


def beep(dur, freq, mf=20, md=0.3, amp=0.8):
    return chirp(dur, freq, freq, mf=mf, md=md, amp=amp)


def gap(dur=0.04):
    return np.zeros(int(dur * SAMPLE_RATE))


def cat(*parts):
    return np.concatenate(parts)


def normalize(sig, peak=0.85):
    m = np.max(np.abs(sig))
    return sig * (peak / m) if m > 0 else sig


# ── sound definitions ────────────────────────────────────────────────────────

def snd_bell():
    """Short upward zap — terminal bell."""
    return chirp(0.15, 1200, 2600, mf=45, md=0.5)


def snd_error():
    """Worried descending two-part warble."""
    return cat(
        chirp(0.30, 1800, 600, mf=25, md=1.3, amp=0.75),
        gap(0.06),
        chirp(0.40, 1100, 350, mf=18, md=1.8, amp=0.65),
    )


def snd_warning():
    """Three rapid concerned staccato beeps."""
    g = gap(0.04)
    return cat(
        beep(0.10, 1500, mf=30, md=0.5),
        g,
        beep(0.10, 1750, mf=35, md=0.5),
        g,
        beep(0.14, 1300, mf=25, md=0.7),
    )


def snd_info():
    """Cheerful two-step ascending chirp."""
    return cat(
        chirp(0.14, 900, 1700, mf=30, md=0.3),
        gap(0.03),
        chirp(0.20, 1700, 2500, mf=42, md=0.45),
    )


def snd_message():
    """Excited double-chirp — new message."""
    return cat(
        chirp(0.11, 1400, 2300, mf=48, md=0.55),
        gap(0.03),
        chirp(0.10, 2100, 2900, mf=55, md=0.4),
    )


def snd_volume():
    """Quick rising tone — volume feedback."""
    return chirp(0.11, 700, 1500, mf=20, md=0.2, amp=0.65)


def snd_battery_low():
    """Slow mournful descending wail."""
    return cat(
        chirp(0.55, 1300, 500, mf=14, md=2.2, amp=0.7),
        gap(0.12),
        chirp(0.65, 950, 280, mf=11, md=2.8, amp=0.6),
    )


def snd_attention():
    """Four rapid ascending pings — needs attention."""
    parts = []
    for i, (f0, f1) in enumerate([(800,1100),(1100,1500),(1500,2000),(2000,2800)]):
        parts.extend([chirp(0.09, f0, f1, mf=40+i*6, md=0.55), gap(0.02)])
    return cat(*parts)


def snd_complete():
    """Triumphant ascending arpeggio — operation done."""
    notes = [(500,800),(800,1200),(1200,1700),(1700,2600)]
    parts = []
    for i, (f0, f1) in enumerate(notes):
        parts.extend([chirp(0.14, f0, f1, mf=28+i*5, md=0.25+i*0.1), gap(0.02)])
    return cat(*parts)


def snd_trash():
    """Short downward bloop."""
    return chirp(0.22, 1700, 380, mf=22, md=0.9, amp=0.7)


def snd_login():
    """Full excited R2-D2 startup sequence."""
    return cat(
        chirp(0.15, 800, 2100, mf=40, md=0.9),
        gap(0.04),
        chirp(0.10, 2100, 1500, mf=50, md=0.6),
        gap(0.03),
        chirp(0.20, 1000, 2700, mf=36, md=1.1),
        gap(0.05),
        beep(0.11, 2300, mf=65, md=0.4),
        gap(0.03),
        chirp(0.22, 1200, 750, mf=28, md=1.3),
        gap(0.04),
        chirp(0.30, 550, 2400, mf=44, md=1.0),
    )


def snd_logout():
    """Tired R2-D2 winding down."""
    return cat(
        chirp(0.22, 1900, 900, mf=24, md=1.1),
        gap(0.07),
        chirp(0.28, 1300, 600, mf=19, md=1.4),
        gap(0.09),
        beep(0.16, 800, mf=14, md=0.9, amp=0.65),
        gap(0.06),
        chirp(0.45, 650, 180, mf=13, md=2.2, amp=0.55),
    )


def snd_power_off():
    """Ominous final descending sweep."""
    return cat(
        chirp(0.20, 1600, 800, mf=20, md=1.0),
        gap(0.08),
        chirp(0.60, 800, 150, mf=10, md=3.0, amp=0.5),
    )


def snd_window_close():
    """Short soft downward blip."""
    return chirp(0.12, 1100, 600, mf=18, md=0.4, amp=0.6)


def snd_minimize():
    """Tiny downward zip."""
    return chirp(0.08, 1400, 800, mf=25, md=0.3, amp=0.55)


def snd_maximize():
    """Tiny upward zip."""
    return chirp(0.08, 800, 1600, mf=25, md=0.3, amp=0.55)


# ── event map ────────────────────────────────────────────────────────────────

SOUNDS = {
    # notification
    "bell":                        snd_bell,
    "dialog-error":                snd_error,
    "dialog-warning":              snd_warning,
    "dialog-information":          snd_info,
    "dialog-question":             snd_info,
    # messaging
    "message-new-instant":         snd_message,
    "message-new-email":           snd_message,
    # system
    "audio-volume-change":         snd_volume,
    "battery-low":                 snd_battery_low,
    "window-attention-active":     snd_attention,
    "window-attention-inactive":   snd_attention,
    "complete":                    snd_complete,
    "trash-empty":                 snd_trash,
    # session
    "desktop-login":               snd_login,
    "service-login":               snd_login,
    "desktop-logout":              snd_logout,
    "service-logout":              snd_logout,
    "system-ready":                snd_login,
    "suspend-start":               snd_logout,
    "suspend-resume":              snd_login,
    "power-plug":                  snd_volume,
    "power-unplug":                snd_trash,
    # window events
    "window-close":                snd_window_close,
    "window-minimized":            snd_minimize,
    "window-maximized":            snd_maximize,
    "window-unminimized":          snd_maximize,
}


# ── output ───────────────────────────────────────────────────────────────────

def save_wav(path, signal):
    signal = normalize(signal)
    samples = np.clip(signal * 32767, -32767, 32767).astype(np.int16)
    # stereo: duplicate mono channel
    stereo = np.column_stack([samples, samples])
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'w') as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SAMPLE_RATE)
        f.writeframes(stereo.tobytes())


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing sounds to {OUT_DIR}")
    for name, fn in SOUNDS.items():
        path = os.path.join(OUT_DIR, f"{name}.wav")
        save_wav(path, fn())
        print(f"  {name}.wav")
    print(f"\nGenerated {len(SOUNDS)} sounds.")


if __name__ == "__main__":
    main()
