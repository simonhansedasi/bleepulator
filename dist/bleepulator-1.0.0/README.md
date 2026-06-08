# bleepulator

Replaces your Linux system sounds with FM-synthesized droid beeps. Fully synthesized via FM math — no sampled audio, no copyright issues.

## Quick start

```bash
sudo apt install ffmpeg python3-numpy   # one-time dependencies
bash install.sh
```

Log out and back in. Done.

## Customizing

All sound design lives in `generate_sounds.py`. Each event is a Python function that returns a numpy waveform:

```python
def snd_error():
    """Worried descending two-part warble."""
    return cat(
        chirp(0.30, 1800, 600, mf=25, md=1.3, amp=0.75),
        gap(0.06),
        chirp(0.40, 1100, 350, mf=18, md=1.8, amp=0.65),
    )
```

The `chirp(duration, freq_start, freq_end, mf=modulator_freq, md=modulator_depth)` primitive does FM synthesis. To change a sound, edit its function and re-run `bash install.sh`.

To preview without logging out:
```bash
paplay ~/.local/share/sounds/bleepulator/stereo/dialog-error.oga
canberra-gtk-play --id="dialog-error"
```

## Building a release

`build_dist.sh` pre-generates all sounds and packages them into a tarball that end-users can install without Python, numpy, or ffmpeg:

```bash
bash build_dist.sh [VERSION]   # default: 1.0.0
# → dist/bleepulator-1.0.0.tar.gz
```

The tarball contains pre-built `.oga` files and a self-contained `install.sh`. End-user installation is:

```bash
tar xzf bleepulator-1.0.0.tar.gz
bash bleepulator-1.0.0/install.sh
```

Upload the tarball to [GitHub Releases](https://github.com) and [GNOME-Look.org](https://www.gnome-look.org) (Sound Themes category) for distribution.

## Sound events

| Event | Character |
|---|---|
| bell | short upward zap |
| dialog-error | sad two-part descending warble |
| dialog-warning | three rapid staccato beeps |
| dialog-information | cheerful ascending chirp |
| message-new-instant | excited double chirp |
| audio-volume-change | brief rising sweep |
| battery-low | slow mournful wail |
| window-attention-active | four rapid ascending pings |
| complete | triumphant arpeggio |
| trash-empty | short downward bloop |
| desktop-login | full Bleepulator startup sequence |
| desktop-logout | tired winding-down sequence |
| window-close / minimize / maximize | short blips |

## How it works

### Sound generation

`generate_sounds.py` synthesizes all sounds using frequency modulation (FM) synthesis:

```
output = sin(phase + modulator_depth * sin(2π * modulator_freq * t))
```

Sweeping the carrier frequency over time creates chirps. Adjusting modulator depth controls how "buzzy" or "clean" a tone sounds. All math is numpy — no audio libraries, no external dependencies beyond ffmpeg for the WAV→OGA conversion.

### Why OGA format

GNOME's sound library (libcanberra) silently refuses `.wav` files. It requires Ogg Vorbis (`.oga`). The generator writes WAV (simpler with stdlib), then `install.sh` converts with ffmpeg and discards the WAVs.

### How GNOME resolves sound events

When a GTK app plays a sound (dialog opens, battery gets low, etc.), it calls libcanberra with an event name like `"dialog-error"`. libcanberra:

1. Reads the active sound theme name from GTK settings
2. Searches for the theme directory in this order:
   - `~/.local/share/sounds/<theme>/`   ← user-local, checked first
   - `/usr/share/sounds/<theme>/`       ← system, managed by apt
3. Plays the matching `.oga` file

The theme is activated via `gsettings set org.gnome.desktop.sound theme-name 'bleepulator'`.

### Why apt upgrades can break sound themes

Ubuntu stores system-wide GTK defaults in `/etc/gtk-3.0/settings.ini`. That file contains:

```ini
gtk-sound-theme-name = Yaru
```

`apt upgrade` can rewrite this file at any time. When it does, GTK's system settings override your per-user settings for `gtk-sound-theme-name`, so libcanberra starts looking up sounds in the Yaru theme instead of bleepulator — for every sound event, not just login.

### The resilience fix

`install.sh` installs all bleepulator sounds as symlinks into `~/.local/share/sounds/Yaru/stereo/`. Since libcanberra checks the user-local path first, our files are found before the system Yaru directory — regardless of what `/etc/gtk-3.0/settings.ini` says:

```
libcanberra looks for "Yaru/dialog-error.oga"
  → checks ~/.local/share/sounds/Yaru/stereo/dialog-error.oga  ✓ found (our file)
  → never reaches /usr/share/sounds/Yaru/                      (skipped)
```

`~/.local/share/` is never touched by apt, so this survives all future upgrades. The symlinks point back to the bleepulator directory, so re-running `install.sh` after editing sounds updates both themes automatically.

The login sound gets a second layer: its autostart `.desktop` file is overridden in `~/.config/autostart/` to play the file path directly, completely bypassing theme lookup.

## GDM login screen (optional, system-wide)

The above covers everything in your user session. If you also want the login *screen* to use bleepulator sounds (GDM runs as a separate system user with its own settings):

```bash
sudo cp -r ~/.local/share/sounds/bleepulator /usr/share/sounds/bleepulator
sudo mkdir -p /etc/dconf/db/gdm.d
sudo tee /etc/dconf/db/gdm.d/00-sound << 'EOF'
[org/gnome/desktop/sound]
theme-name='bleepulator'
event-sounds=true
EOF
sudo dconf update
```

Note: if apt upgrades the Yaru sound package, re-run the `sudo cp` line.

## Troubleshooting

**Sounds still playing Yaru after install:**

```bash
# See which file libcanberra actually opens
strace -e trace=openat canberra-gtk-play --id="dialog-error" 2>&1 | grep "\.oga"

# Clear libcanberra's path cache and re-test
rm ~/.cache/event-sound-cache.tdb.*
canberra-gtk-play --id="dialog-error"
```

If it still shows a Yaru path, check that the symlinks exist:
```bash
ls -la ~/.local/share/sounds/Yaru/stereo/ | head -5
```

**Login sound still wrong:**
```bash
cat ~/.config/autostart/libcanberra-login-sound.desktop
# Exec= line should contain --file=... not --id=...
```

## Uninstall

```bash
rm -rf ~/.local/share/sounds/bleepulator
rm -rf ~/.local/share/sounds/Yaru
rm -f  ~/.config/autostart/libcanberra-login-sound.desktop
gsettings reset org.gnome.desktop.sound theme-name
gsettings reset org.gnome.desktop.sound event-sounds
```

## Dependencies

- Python 3 + numpy
- ffmpeg (`sudo apt install ffmpeg`)
- GNOME desktop (for gsettings activation; the theme files work on any freedesktop-compliant DE)
