#!/bin/bash
# =============================================================================
# Bleepulator distribution builder
#
# Generates all OGA files from source, then packages them into the repo root:
#   bleepulator_<VERSION>_all.deb   — double-click installer, no deps
#   bleepulator-<VERSION>.tar.gz    — manual install / GNOME-Look
#
# Usage:
#   bash build_dist.sh [VERSION]         # default: 1.0.0
#
# Build dependencies (not required by end-users):
#   sudo apt install ffmpeg python3-numpy dpkg
# =============================================================================

set -e

VERSION="${1:-1.0.0}"
MAINTAINER="Simon Hans Edasi <simonhansedasi@gmail.com>"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$REPO_ROOT"
SOUNDS_STAGE="$SCRIPT_DIR/_sounds_stage"            # shared OGA staging area (inside src/, cleaned up)
TAR_STAGE="$SCRIPT_DIR/bleepulator-$VERSION"        # tarball tree (inside src/, cleaned up)
DEB_STAGE="$SCRIPT_DIR/_deb_stage"                  # .deb tree (inside src/, cleaned up)

echo "=== Bleepulator dist builder — v$VERSION ==="
echo ""


# -----------------------------------------------------------------------------
# Check build dependencies
# -----------------------------------------------------------------------------
for cmd in ffmpeg python3 dpkg-deb; do
    command -v "$cmd" &>/dev/null || { echo "Error: $cmd is required."; exit 1; }
done
python3 -c "import numpy" 2>/dev/null || {
    echo "Error: numpy is required.  sudo apt install python3-numpy"
    exit 1
}


# -----------------------------------------------------------------------------
# Clean
# -----------------------------------------------------------------------------
rm -rf "$SOUNDS_STAGE" "$TAR_STAGE" "$DEB_STAGE"
mkdir -p "$SOUNDS_STAGE" "$DIST_DIR"


# -----------------------------------------------------------------------------
# Generate WAV files into the staging area
# Overrides OUT_DIR so we never touch ~/.local/share/
# -----------------------------------------------------------------------------
echo "[1/4] Generating sounds..."
python3 - <<PYEOF
import sys
sys.path.insert(0, "$SCRIPT_DIR")
import generate_sounds
generate_sounds.OUT_DIR = "$SOUNDS_STAGE"
generate_sounds.main()
PYEOF


# -----------------------------------------------------------------------------
# Convert WAV → OGA
# Pre-convert so end-users need no ffmpeg
# -----------------------------------------------------------------------------
echo "[2/4] Converting WAV to OGA..."
for wav in "$SOUNDS_STAGE/"*.wav; do
    ffmpeg -i "$wav" -c:a libvorbis -q:a 5 "${wav%.wav}.oga" -y -loglevel quiet
    rm "$wav"
done
OGA_COUNT=$(ls "$SOUNDS_STAGE/"*.oga | wc -l)
echo "  $OGA_COUNT OGA files"


# =============================================================================
# BUILD: .deb
# =============================================================================
echo "[3/4] Building .deb..."

# File tree
mkdir -p "$DEB_STAGE/DEBIAN"
mkdir -p "$DEB_STAGE/usr/share/sounds/bleepulator/stereo"
mkdir -p "$DEB_STAGE/usr/share/doc/bleepulator"

cp "$SOUNDS_STAGE/"*.oga     "$DEB_STAGE/usr/share/sounds/bleepulator/stereo/"
cp "$SCRIPT_DIR/index.theme" "$DEB_STAGE/usr/share/sounds/bleepulator/index.theme"
cp "$SCRIPT_DIR/README_DIST.md" "$DEB_STAGE/usr/share/doc/bleepulator/README"

# DEBIAN/control
cat > "$DEB_STAGE/DEBIAN/control" << EOF
Package: bleepulator
Version: $VERSION
Architecture: all
Maintainer: $MAINTAINER
Description: FM-synthesized droid sound theme for GNOME
 Replaces system notification sounds with electronic chirps and warbles.
 No sampled audio, no copyright issues. Survives apt upgrades.
EOF

# DEBIAN/postinst
# Runs after dpkg copies files. Activates the theme for the installing user,
# sets up the Yaru resilience layer, and patches the login autostart.
# gsettings requires a running D-Bus session — this works when the user
# double-clicks the .deb in a live GNOME session. If it fails (e.g. headless
# install), a fallback message is printed with the one-liner to run manually.
cat > "$DEB_STAGE/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
set -e

BLEEP_SYS="/usr/share/sounds/bleepulator/stereo"
REAL_USER="${SUDO_USER:-}"

if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    echo "bleepulator: could not detect installing user — activate manually:"
    echo "  gsettings set org.gnome.desktop.sound theme-name 'bleepulator'"
    exit 0
fi

REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
REAL_UID=$(id -u "$REAL_USER")
DBUS="unix:path=/run/user/$REAL_UID/bus"

run_as_user() {
    DBUS_SESSION_BUS_ADDRESS="$DBUS" su "$REAL_USER" -c "$1" 2>/dev/null
}

# Activate theme
if run_as_user "gsettings set org.gnome.desktop.sound theme-name 'bleepulator'" && \
   run_as_user "gsettings set org.gnome.desktop.sound event-sounds true"; then
    echo "bleepulator: theme activated."
else
    echo "bleepulator: could not reach D-Bus session — activate manually:"
    echo "  gsettings set org.gnome.desktop.sound theme-name 'bleepulator'"
fi

# Yaru resilience layer
# libcanberra checks ~/.local/share/sounds/Yaru/ before /usr/share/sounds/Yaru/,
# so symlinking our files there ensures they're used even if apt resets the
# system GTK sound theme name back to "Yaru".
YARU_DIR="$REAL_HOME/.local/share/sounds/Yaru/stereo"
mkdir -p "$YARU_DIR"
cat > "$REAL_HOME/.local/share/sounds/Yaru/index.theme" << 'EOF'
[Sound Theme]
Name=Yaru
Directories=stereo

[stereo]
OutputProfile=stereo
EOF
for oga in "$BLEEP_SYS/"*.oga; do
    ln -sf "$oga" "$YARU_DIR/$(basename "$oga")"
done
chown -R "$REAL_USER:" "$REAL_HOME/.local/share/sounds/Yaru"

# Login sound: bypass theme lookup entirely by pointing the autostart .desktop
# directly at the file path
mkdir -p "$REAL_HOME/.config/autostart"
cat > "$REAL_HOME/.config/autostart/libcanberra-login-sound.desktop" << EOF
[Desktop Entry]
Type=Application
Name=GNOME Login Sound
Comment=Plays a sound whenever you log in
Exec=/usr/bin/canberra-gtk-play --file="$BLEEP_SYS/desktop-login.oga" --description="GNOME Login"
OnlyShowIn=GNOME;Unity;
AutostartCondition=GSettings org.gnome.desktop.sound event-sounds
X-GNOME-Autostart-Phase=Application
X-GNOME-Provides=login-sound
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF
chown "$REAL_USER:" "$REAL_HOME/.config/autostart/libcanberra-login-sound.desktop"

echo "bleepulator: log out and back in for the login sound to take effect."
POSTINST
chmod 755 "$DEB_STAGE/DEBIAN/postinst"

# DEBIAN/postrm
# Cleans up Yaru symlinks and resets gsettings on removal
cat > "$DEB_STAGE/DEBIAN/postrm" << 'POSTRM'
#!/bin/bash
set -e

if [ "$1" != "remove" ] && [ "$1" != "purge" ]; then
    exit 0
fi

REAL_USER="${SUDO_USER:-}"

if [ -n "$REAL_USER" ] && [ "$REAL_USER" != "root" ]; then
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
    REAL_UID=$(id -u "$REAL_USER")
    DBUS="unix:path=/run/user/$REAL_UID/bus"

    # Reset gsettings if bleepulator was the active theme
    CURRENT=$(DBUS_SESSION_BUS_ADDRESS="$DBUS" su "$REAL_USER" -c \
        "gsettings get org.gnome.desktop.sound theme-name" 2>/dev/null || true)
    if [ "$CURRENT" = "'bleepulator'" ]; then
        DBUS_SESSION_BUS_ADDRESS="$DBUS" su "$REAL_USER" -c \
            "gsettings reset org.gnome.desktop.sound theme-name" 2>/dev/null || true
    fi

    # Remove Yaru symlinks that point into bleepulator
    YARU_DIR="$REAL_HOME/.local/share/sounds/Yaru/stereo"
    if [ -d "$YARU_DIR" ]; then
        find "$YARU_DIR" -type l | while read -r link; do
            target=$(readlink "$link")
            if echo "$target" | grep -q "bleepulator"; then
                rm -f "$link"
            fi
        done
        # Remove Yaru dir if now empty
        rmdir "$YARU_DIR" 2>/dev/null || true
        rmdir "$REAL_HOME/.local/share/sounds/Yaru" 2>/dev/null || true
    fi

    # Remove login sound patch
    DESKTOP="$REAL_HOME/.config/autostart/libcanberra-login-sound.desktop"
    if [ -f "$DESKTOP" ] && grep -q "bleepulator" "$DESKTOP"; then
        rm -f "$DESKTOP"
    fi
fi
POSTRM
chmod 755 "$DEB_STAGE/DEBIAN/postrm"

DEB_OUT="$REPO_ROOT/bleepulator_${VERSION}_all.deb"
dpkg-deb --build "$DEB_STAGE" "$DEB_OUT"
echo "  $DEB_OUT"


# =============================================================================
# BUILD: tarball (for GNOME-Look / other distros)
# =============================================================================
echo "[4/4] Building tarball..."

mkdir -p "$TAR_STAGE/stereo"
cp "$SOUNDS_STAGE/"*.oga     "$TAR_STAGE/stereo/"
cp "$SCRIPT_DIR/index.theme" "$TAR_STAGE/index.theme"
cp "$SCRIPT_DIR/README_DIST.md" "$TAR_STAGE/README.md"

# Tarball install.sh — no Python, numpy, or ffmpeg required
cat > "$TAR_STAGE/install.sh" << 'TARINSTALL'
#!/bin/bash
set -e

BLEEPULATOR_DIR="$HOME/.local/share/sounds/bleepulator"
YARU_DIR="$HOME/.local/share/sounds/Yaru"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Bleepulator Installer ==="
echo ""

echo "[1/4] Installing sounds..."
mkdir -p "$BLEEPULATOR_DIR/stereo"
cp "$SCRIPT_DIR/stereo/"*.oga "$BLEEPULATOR_DIR/stereo/"
cp "$SCRIPT_DIR/index.theme"  "$BLEEPULATOR_DIR/index.theme"

echo "[2/4] Activating theme..."
if command -v gsettings &>/dev/null; then
    gsettings set org.gnome.desktop.sound theme-name 'bleepulator'
    gsettings set org.gnome.desktop.sound event-sounds true
else
    echo "  gsettings not found — run this manually:"
    echo "  gsettings set org.gnome.desktop.sound theme-name 'bleepulator'"
fi

echo "[3/4] Installing apt-resilience layer..."
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

echo "[4/4] Patching login sound..."
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/libcanberra-login-sound.desktop" << EOF
[Desktop Entry]
Type=Application
Name=GNOME Login Sound
Exec=/usr/bin/canberra-gtk-play --file="$BLEEPULATOR_DIR/stereo/desktop-login.oga" --description="GNOME Login"
OnlyShowIn=GNOME;Unity;
AutostartCondition=GSettings org.gnome.desktop.sound event-sounds
X-GNOME-Autostart-Phase=Application
X-GNOME-Provides=login-sound
X-GNOME-Autostart-enabled=true
NoDisplay=true
EOF

echo ""
echo "Done. Log out and back in for the login sound to take effect."
echo ""
echo "To uninstall:"
echo "  rm -rf ~/.local/share/sounds/bleepulator ~/.local/share/sounds/Yaru"
echo "  rm -f  ~/.config/autostart/libcanberra-login-sound.desktop"
echo "  gsettings reset org.gnome.desktop.sound theme-name"
TARINSTALL
chmod +x "$TAR_STAGE/install.sh"

TAR_OUT="$REPO_ROOT/bleepulator-$VERSION.tar.gz"
cd "$SCRIPT_DIR"
tar -czf "$TAR_OUT" "bleepulator-$VERSION/"
echo "  $TAR_OUT"


# -----------------------------------------------------------------------------
# Cleanup staging dirs
# -----------------------------------------------------------------------------
rm -rf "$SOUNDS_STAGE" "$DEB_STAGE" "$TAR_STAGE"   # all inside src/, safe to nuke


echo ""
echo "=== Done ==="
echo "  .deb:    $DEB_OUT"
echo "  tarball: $TAR_OUT"
echo ""
echo "Release checklist:"
echo "  1. Tag a GitHub release and attach both files"
echo "  2. Upload tarball to https://www.gnome-look.org (Sound Themes category)"
