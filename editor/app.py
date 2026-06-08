#!/usr/bin/env python3
"""Bleepulator editor — Flask server for the sound customization UI."""

import io
import json
import os
import struct
import subprocess
import sys
import wave

import numpy as np
from flask import Flask, jsonify, render_template, request, send_file

# resolve paths relative to this file so the editor can be run from anywhere
EDITOR_DIR  = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(EDITOR_DIR)
DEFS_PATH   = os.path.join(PROJECT_DIR, "sound_defs.json")
SOUNDS_DIR  = os.path.expanduser("~/.local/share/sounds/bleepulator/stereo")

sys.path.insert(0, PROJECT_DIR)
from generate_sounds import EVENT_MAP, SAMPLE_RATE, synthesize, normalize, save_wav

app = Flask(__name__)


# ── helpers ──────────────────────────────────────────────────────────────────

def load_defs():
    with open(DEFS_PATH) as f:
        return json.load(f)


def segments_to_wav_bytes(segments):
    """Synthesize segments and return in-memory WAV bytes."""
    sig = synthesize(segments)
    sig = normalize(sig)
    samples = np.clip(sig * 32767, -32767, 32767).astype(np.int16)
    stereo = np.column_stack([samples, samples])
    buf = io.BytesIO()
    with wave.open(buf, 'w') as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(stereo.tobytes())
    buf.seek(0)
    return buf


def events_for_sound(sound_key):
    """Return all event names that map to this sound key."""
    return [ev for ev, sk in EVENT_MAP.items() if sk == sound_key]


def regenerate_ogas(sound_key, segments):
    """Synthesize WAVs for all events using this sound, then convert to OGA."""
    defs = load_defs()
    events = events_for_sound(sound_key)
    for event in events:
        wav_path = os.path.join(SOUNDS_DIR, f"{event}.wav")
        oga_path = os.path.join(SOUNDS_DIR, f"{event}.oga")
        os.makedirs(SOUNDS_DIR, exist_ok=True)
        save_wav(wav_path, synthesize(segments))
        result = subprocess.run(
            ["ffmpeg", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "5",
             oga_path, "-y", "-loglevel", "quiet"],
            capture_output=True
        )
        os.remove(wav_path)
        if result.returncode != 0:
            return False, result.stderr.decode()
    # update Yaru overlay symlinks
    yaru_dir = os.path.expanduser("~/.local/share/sounds/Yaru/stereo")
    if os.path.isdir(yaru_dir):
        for event in events:
            oga = os.path.join(SOUNDS_DIR, f"{event}.oga")
            link = os.path.join(yaru_dir, f"{event}.oga")
            if os.path.exists(oga):
                os.symlink(oga, link) if not os.path.exists(link) else None
    return True, None


# ── routes ───────────────────────────────────────────────────────────────────

@app.route("/")
def index():
    return render_template("index.html")


@app.route("/sounds")
def sounds():
    defs = load_defs()
    # attach the list of event names each sound drives
    result = {}
    for key, defn in defs.items():
        result[key] = {
            "description": defn["description"],
            "segments":    defn["segments"],
            "events":      events_for_sound(key),
        }
    return jsonify(result)


@app.route("/preview", methods=["POST"])
def preview():
    """Synthesize segments on the fly and return audio/wav."""
    data = request.get_json()
    segments = data.get("segments", [])
    buf = segments_to_wav_bytes(segments)
    return send_file(buf, mimetype="audio/wav", as_attachment=False)


@app.route("/save/<name>", methods=["POST"])
def save(name):
    """Persist updated segments to sound_defs.json and regenerate OGA files."""
    data = request.get_json()
    segments = data.get("segments", [])

    defs = load_defs()
    if name not in defs:
        return jsonify({"ok": False, "error": f"Unknown sound: {name}"}), 404

    defs[name]["segments"] = segments
    with open(DEFS_PATH, "w") as f:
        json.dump(defs, f, indent=2)

    ok, err = regenerate_ogas(name, segments)
    if not ok:
        return jsonify({"ok": False, "error": err}), 500

    return jsonify({"ok": True, "events": events_for_sound(name)})


@app.route("/audio/<name>")
def audio(name):
    """Stream the installed OGA for a sound name (first matching event)."""
    events = events_for_sound(name)
    if not events:
        return "Not found", 404
    oga_path = os.path.join(SOUNDS_DIR, f"{events[0]}.oga")
    if not os.path.exists(oga_path):
        return "File not found — run install.sh first", 404
    return send_file(oga_path, mimetype="audio/ogg")


if __name__ == "__main__":
    print("Bleepulator editor running at http://localhost:5000")
    app.run(debug=True, port=5000)
