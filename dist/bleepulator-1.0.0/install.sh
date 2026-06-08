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
