#!/bin/bash
# =============================================================================
# R2-D2 Sound Theme Installer
# =============================================================================
#
# WHAT THIS SCRIPT DOES
# ---------------------
# 1. Generates FM-synthesized droid sounds (via generate_sounds.py)
# 2. Converts them to OGA format (required by GNOME's sound library)
# 3. Installs them as the "r2d2" freedesktop sound theme
# 4. Activates r2d2 as your GNOME sound theme via settings
# 5. Creates a resilience layer so sounds survive apt upgrades
# 6. Patches the login sound to be extra-resilient
#
# HOW TO CUSTOMIZE
# ----------------
# All sound design lives in generate_sounds.py. Each function (snd_error,
# snd_login, etc.) returns a numpy waveform. Tweak the chirp/beep parameters
# there — frequency, duration, FM modulation depth — then re-run this script.
# No audio editing tools needed.
#
# HOW TO UNINSTALL
# ----------------
# Run: bash uninstall.sh    (or see the manual steps at the bottom of this file)
#
# =============================================================================

set -e  # exit immediately if any command fails

R2D2_DIR="$HOME/.local/share/sounds/r2d2"
YARU_DIR="$HOME/.local/share/sounds/Yaru"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== R2-D2 Sound Theme Installer ==="
echo ""


# -----------------------------------------------------------------------------
# STEP 1: Check dependencies
# -----------------------------------------------------------------------------
# ffmpeg converts WAV → OGA. GNOME's sound library (libcanberra) silently
# refuses to play WAV files — it requires Ogg Vorbis (.oga).
if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is required."
    echo "  sudo apt install ffmpeg"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required."
    exit 1
fi


# -----------------------------------------------------------------------------
# STEP 2: Generate the sound files
# -----------------------------------------------------------------------------
# generate_sounds.py synthesizes all sounds using FM math and writes WAV files
# to $R2D2_DIR/stereo/. Edit that file to customize any sound.
echo "[1/5] Generating sounds..."
python3 "$SCRIPT_DIR/generate_sounds.py"


# -----------------------------------------------------------------------------
# STEP 3: Convert WAV → OGA
# -----------------------------------------------------------------------------
# libcanberra (the GNOME event sound engine) requires Ogg Vorbis (.oga).
# We generate WAV first because numpy's stdlib wave module is simpler than
# writing Ogg directly, then convert here and discard the WAVs.
#
# ffmpeg flags:
#   -c:a libvorbis    use Ogg Vorbis codec
#   -q:a 5            quality level 5 (0–10 scale, 5 is ~160 kbps — plenty for beeps)
#   -y                overwrite output without prompting
#   -loglevel quiet   suppress ffmpeg's verbose output
echo "[2/5] Converting WAV to OGA..."
for wav in "$R2D2_DIR/stereo/"*.wav; do
    ffmpeg -i "$wav" -c:a libvorbis -q:a 5 "${wav%.wav}.oga" -y -loglevel quiet
    rm "$wav"
done


# -----------------------------------------------------------------------------
# STEP 4: Install r2d2 as a named sound theme
# -----------------------------------------------------------------------------
# A freedesktop sound theme is just a directory + index.theme descriptor.
# index.theme tells the system: "this is a theme called R2-D2, look for
# sounds in the stereo/ subdir, fall back to freedesktop if a sound is missing."
#
# Theme search path (in order):
#   ~/.local/share/sounds/     ← user local (we install here)
#   /usr/share/sounds/         ← system-wide
echo "[3/5] Installing r2d2 theme..."
cp "$SCRIPT_DIR/index.theme" "$R2D2_DIR/index.theme"

# Activate via GNOME settings
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.sound theme-name 'r2d2'
    gsettings set org.gnome.desktop.sound event-sounds true
fi


# -----------------------------------------------------------------------------
# STEP 5: Resilience layer — local Yaru override
# -----------------------------------------------------------------------------
# THE PROBLEM:
#   Ubuntu stores system-wide GTK settings in /etc/gtk-3.0/settings.ini.
#   That file contains: gtk-sound-theme-name = Yaru
#   libcanberra reads GTK settings to find the theme name, and system settings
#   take priority over user settings for this property. So when any GTK app
#   plays a sound event (dialog, notification, battery warning, etc.), it looks
#   up sounds in the "Yaru" theme — ignoring your gsettings and r2d2.
#   apt upgrade can re-write /etc/gtk-3.0/settings.ini at any time.
#
# THE FIX:
#   libcanberra searches for theme directories in this order:
#     1. ~/.local/share/sounds/Yaru/    ← checked FIRST
#     2. /usr/share/sounds/Yaru/        ← system (managed by apt)
#
#   By creating ~/.local/share/sounds/Yaru/ with symlinks to our r2d2 sounds,
#   libcanberra finds our files first — for every sound event — regardless of
#   what /etc/gtk-3.0/settings.ini says. apt never touches ~/.local/share/,
#   so this survives all future upgrades.
#
#   The symlinks mean: edit generate_sounds.py → re-run install.sh → both
#   the r2d2 theme and the Yaru override update automatically.
echo "[4/5] Installing resilience layer (local Yaru override)..."
mkdir -p "$YARU_DIR/stereo"

# Minimal index.theme for the local Yaru override.
# Name=Yaru matches what libcanberra searches for.
cat > "$YARU_DIR/index.theme" << 'EOF'
[Sound Theme]
Name=Yaru
Directories=stereo

[stereo]
OutputProfile=stereo
EOF

# Symlink every r2d2 sound into the local Yaru override.
# -s  create a symbolic link
# -f  overwrite if it already exists (safe to re-run)
for oga in "$R2D2_DIR/stereo/"*.oga; do
    ln -sf "$oga" "$YARU_DIR/stereo/$(basename "$oga")"
done


# -----------------------------------------------------------------------------
# STEP 6: Login sound — belt-and-suspenders
# -----------------------------------------------------------------------------
# The login sound is special: it's triggered by an autostart .desktop file
# (/usr/share/gnome/autostart/libcanberra-login-sound.desktop) which runs
# canberra-gtk-play early in the session. We override it in the user autostart
# directory to play the file path directly, completely bypassing theme lookup.
# This is a second layer of protection on top of the Yaru override.
#
# Desktop file format notes:
#   Exec=            command to run at login
#   AutostartCondition=GSettings ...  only run if event-sounds is enabled
#   X-GNOME-Autostart-enabled=true    override the system file's "false" default
echo "[5/5] Patching login sound autostart..."
mkdir -p "$HOME/.config/autostart"

cat > "$HOME/.config/autostart/libcanberra-login-sound.desktop" << EOF
[Desktop Entry]
Type=Application
Name=GNOME Login Sound
Comment=Plays a sound whenever you log in
Exec=/usr/bin/canberra-gtk-play --file="$R2D2_DIR/stereo/desktop-login.oga" --description="GNOME Login"
OnlyShowIn=GNOME;Unity;
AutostartCondition=GSettings org.gnome.desktop.sound event-sounds
X-GNOME-Autostart-Phase=Application
X-GNOME-Provides=login-sound
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF


# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
echo ""
echo "All done."
echo ""
echo "  r2d2 theme:   $R2D2_DIR/stereo/"
echo "  Yaru overlay: $YARU_DIR/stereo/ ($(ls "$YARU_DIR/stereo/" | wc -l) symlinks)"
echo ""
echo "Log out and back in for the login sound to take effect."
echo "All other sounds are active immediately."
echo ""
echo "To preview a sound:"
echo "  paplay $R2D2_DIR/stereo/desktop-login.oga"
echo "  canberra-gtk-play --id=\"dialog-error\""
echo ""
echo "To customize: edit generate_sounds.py, then re-run this script."


# =============================================================================
# MANUAL UNINSTALL
# =============================================================================
# rm -rf ~/.local/share/sounds/r2d2
# rm -rf ~/.local/share/sounds/Yaru
# rm -f  ~/.config/autostart/libcanberra-login-sound.desktop
# gsettings reset org.gnome.desktop.sound theme-name
# gsettings reset org.gnome.desktop.sound event-sounds
# =============================================================================
