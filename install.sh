#!/bin/bash
set -e

THEME_DIR="$HOME/.local/share/sounds/r2d2"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== R2-D2 Sound Theme Installer ==="

# generate WAV files
echo "Generating sounds..."
python3 "$SCRIPT_DIR/generate_sounds.py"

# copy theme index
cp "$SCRIPT_DIR/index.theme" "$THEME_DIR/index.theme"

# activate in GNOME
if command -v gsettings &> /dev/null; then
    gsettings set org.gnome.desktop.sound theme-name 'r2d2'
    gsettings set org.gnome.desktop.sound event-sounds true
    echo "GNOME sound theme set to r2d2."
else
    echo "gsettings not found — set sound theme manually in Settings > Sound."
fi

echo ""
echo "Done. Log out and back in (or restart the session) for all sounds to take effect."
echo "Theme dir: $THEME_DIR"
