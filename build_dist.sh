#!/bin/bash
# =============================================================================
# Bleepulator distribution builder
#
# Generates all OGA files from source, then packages them into a tarball that
# end-users can install without needing Python, numpy, or ffmpeg.
#
# Usage:
#   bash build_dist.sh [VERSION]
#
# Output:
#   dist/bleepulator-<VERSION>.tar.gz
# =============================================================================

set -e

VERSION="${1:-1.0.0}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
STAGE_DIR="$DIST_DIR/bleepulator-$VERSION"
SOUNDS_DIR="$STAGE_DIR/stereo"

echo "=== Bleepulator dist builder ==="
echo "Version: $VERSION"
echo ""


# -----------------------------------------------------------------------------
# Check build dependencies
# -----------------------------------------------------------------------------
if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg is required to build."
    echo "  sudo apt install ffmpeg"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "Error: python3 is required to build."
    exit 1
fi

python3 -c "import numpy" 2>/dev/null || {
    echo "Error: numpy is required to build."
    echo "  pip install numpy  OR  sudo apt install python3-numpy"
    exit 1
}


# -----------------------------------------------------------------------------
# Clean and prepare staging directory
# -----------------------------------------------------------------------------
echo "[1/4] Preparing staging directory..."
rm -rf "$STAGE_DIR"
mkdir -p "$SOUNDS_DIR"


# -----------------------------------------------------------------------------
# Generate WAV files into the staging directory
# Overrides OUT_DIR so we don't touch ~/.local/share/
# -----------------------------------------------------------------------------
echo "[2/4] Generating sounds..."
python3 - <<PYEOF
import sys, os
sys.path.insert(0, "$SCRIPT_DIR")
import generate_sounds
generate_sounds.OUT_DIR = "$SOUNDS_DIR"
generate_sounds.main()
PYEOF


# -----------------------------------------------------------------------------
# Convert WAV → OGA
# End-users won't have ffmpeg, so we pre-convert here
# -----------------------------------------------------------------------------
echo "[3/4] Converting WAV to OGA..."
for wav in "$SOUNDS_DIR/"*.wav; do
    ffmpeg -i "$wav" -c:a libvorbis -q:a 5 "${wav%.wav}.oga" -y -loglevel quiet
    rm "$wav"
done
echo "  $(ls "$SOUNDS_DIR/"*.oga | wc -l) OGA files generated"


# -----------------------------------------------------------------------------
# Copy static theme files
# -----------------------------------------------------------------------------
cp "$SCRIPT_DIR/index.theme" "$STAGE_DIR/index.theme"
cp "$SCRIPT_DIR/README.md"   "$STAGE_DIR/README.md"


# -----------------------------------------------------------------------------
# Write the end-user install.sh
# No Python, numpy, or ffmpeg required — just copies pre-built files
# -----------------------------------------------------------------------------
cat > "$STAGE_DIR/install.sh" << 'INSTALL_EOF'
#!/bin/bash
set -e

BLEEPULATOR_DIR="$HOME/.local/share/sounds/bleepulator"
YARU_DIR="$HOME/.local/share/sounds/Yaru"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Bleepulator Sound Theme Installer ==="
echo ""


# Install OGA files
echo "[1/4] Installing sounds..."
mkdir -p "$BLEEPULATOR_DIR/stereo"
cp "$SCRIPT_DIR/stereo/"*.oga "$BLEEPULATOR_DIR/stereo/"
cp "$SCRIPT_DIR/index.theme"  "$BLEEPULATOR_DIR/index.theme"
echo "  $(ls "$BLEEPULATOR_DIR/stereo/"*.oga | wc -l) sounds installed"


# Activate the theme via GNOME settings
echo "[2/4] Activating bleepulator theme..."
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.sound theme-name 'bleepulator'
    gsettings set org.gnome.desktop.sound event-sounds true
else
    echo "  gsettings not found — activate manually:"
    echo "  gsettings set org.gnome.desktop.sound theme-name 'bleepulator'"
fi


# Resilience layer: symlink sounds into a local Yaru override so they survive
# apt upgrades that reset /etc/gtk-3.0/settings.ini to theme-name=Yaru
echo "[3/4] Installing apt-resilience layer (local Yaru override)..."
mkdir -p "$YARU_DIR/stereo"
cat > "$YARU_DIR/index.theme" << 'EOF'
[Sound Theme]
Name=Yaru
Directories=stereo

[stereo]
OutputProfile=stereo
EOF
for oga in "$BLEEPULATOR_DIR/stereo/"*.oga; do
    ln -sf "$oga" "$YARU_DIR/stereo/$(basename "$oga")"
done
echo "  $(ls "$YARU_DIR/stereo/" | wc -l) symlinks created"


# Patch the login sound autostart to bypass theme lookup entirely
echo "[4/4] Patching login sound autostart..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/libcanberra-login-sound.desktop" << EOF
[Desktop Entry]
Type=Application
Name=GNOME Login Sound
Comment=Plays a sound whenever you log in
Exec=/usr/bin/canberra-gtk-play --file="$BLEEPULATOR_DIR/stereo/desktop-login.oga" --description="GNOME Login"
OnlyShowIn=GNOME;Unity;
AutostartCondition=GSettings org.gnome.desktop.sound event-sounds
X-GNOME-Autostart-Phase=Application
X-GNOME-Provides=login-sound
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF


echo ""
echo "Done! Log out and back in for the login sound to take effect."
echo "All other sounds are active immediately."
echo ""
echo "To preview:"
echo "  paplay $BLEEPULATOR_DIR/stereo/dialog-error.oga"
echo "  canberra-gtk-play --id=\"dialog-error\""
echo ""
echo "To uninstall:"
echo "  rm -rf ~/.local/share/sounds/bleepulator"
echo "  rm -rf ~/.local/share/sounds/Yaru"
echo "  rm -f  ~/.config/autostart/libcanberra-login-sound.desktop"
echo "  gsettings reset org.gnome.desktop.sound theme-name"
echo "  gsettings reset org.gnome.desktop.sound event-sounds"
INSTALL_EOF

chmod +x "$STAGE_DIR/install.sh"


# -----------------------------------------------------------------------------
# Package
# -----------------------------------------------------------------------------
echo "[4/4] Packaging..."
cd "$DIST_DIR"
tar -czf "bleepulator-$VERSION.tar.gz" "bleepulator-$VERSION/"

echo ""
echo "Built: $DIST_DIR/bleepulator-$VERSION.tar.gz"
echo "Contents:"
tar -tzf "$DIST_DIR/bleepulator-$VERSION.tar.gz" | sed 's/^/  /'
echo ""
echo "To release:"
echo "  1. Upload bleepulator-$VERSION.tar.gz to GitHub Releases"
echo "  2. Upload to https://www.gnome-look.org (Sound Themes category)"
