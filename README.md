# Bleepulator

FM-synthesized droid beeps for your Linux desktop. Replaces system notification
sounds with a set of electronic chirps and warbles — no sampled audio, no
copyright issues, survives system updates.

## Install

### Ubuntu / Debian (recommended)

Double-click `bleepulator_1.0.0_all.deb`.

Or from the terminal:

```
sudo dpkg -i bleepulator_1.0.0_all.deb
```

Log out and back in. Done.

### Other distros (manual)

```
tar xzf bleepulator-1.0.0.tar.gz
bash bleepulator-1.0.0/install.sh
```

Log out and back in for the login sound to take effect. All other sounds are
active immediately.

## Preview

```
canberra-gtk-play --id="dialog-error"
canberra-gtk-play --id="desktop-login"
```

## Sounds

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
| desktop-login | full startup sequence |
| desktop-logout | winding-down sequence |
| window-close / minimize / maximize | short blips |

## Uninstall

**If installed via .deb:**

```
sudo apt remove bleepulator
gsettings reset org.gnome.desktop.sound theme-name
```

**If installed manually:**

```
rm -rf ~/.local/share/sounds/bleepulator
rm -rf ~/.local/share/sounds/Yaru
rm -f  ~/.config/autostart/libcanberra-login-sound.desktop
gsettings reset org.gnome.desktop.sound theme-name
gsettings reset org.gnome.desktop.sound event-sounds
```
