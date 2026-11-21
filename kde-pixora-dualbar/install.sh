#!/usr/bin/env bash
# Pixora dual-bar rice for KDE Plasma 6 — one-shot installer.
# Everything installs into your home directory; no sudo needed.
#
#   ./install.sh                 # install + apply
#   LAUNCHERS="..." ./install.sh # custom pinned apps in the dock
#   MENU_LABEL="Arch" ./install.sh
#
# Your current Plasma config is backed up to ~/plasma-backup-<timestamp>/ first.
# Undo with ./uninstall.sh
set -euo pipefail

# ---------- pinned versions ----------
PIXORA_REPO="https://github.com/tsora1603/pixora-icons.git"
COLORIZER_VER="v8.1.0"
PLASMUSIC_VER="v4.3.1"
NERDFONTS_VER="v3.5.1"
SPEEDINGBULLET_REPO="https://github.com/strider-ape/speeding-bullet.git"

ICON_THEME="${ICON_THEME:-pixora-dark}"   # pixora | pixora-dark | pixora-accent
FONT="DepartureMono Nerd Font"
LAUNCHERS="${LAUNCHERS:-applications:systemsettings.desktop,preferred://filemanager,preferred://browser,applications:kitty.desktop}"
if [[ -z "${MENU_LABEL:-}" ]]; then
  MENU_LABEL="$( . /etc/os-release 2>/dev/null; echo "${NAME%% *}" )"
  MENU_LABEL="${MENU_LABEL:-Menu}"
fi

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

# ---------- preflight ----------
[[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] || die "This needs a running KDE Plasma session."
for c in plasmashell qdbus6 kpackagetool6 kwriteconfig6 curl git tar python3; do
  command -v "$c" >/dev/null || die "Missing command: $c"
done

# ---------- backup ----------
BACKUP="$HOME/plasma-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc plasmarc kdeglobals kwinrc; do
  [[ -f "$CONF/$f" ]] && cp -a "$CONF/$f" "$BACKUP/"
done
say "Backed up current config to $BACKUP"

# ---------- icons ----------
say "Installing Pixora icons"
git clone -q --depth 1 "$PIXORA_REPO" "$TMP/pixora"
mkdir -p "$DATA/icons"
for t in pixora pixora-dark pixora-accent; do
  rm -rf "${DATA:?}/icons/$t"
  cp -a "$TMP/pixora/$t" "$DATA/icons/"
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -qf "$DATA/icons/$t" 2>/dev/null || true
done

# ---------- font ----------
say "Installing $FONT"
curl -fsSL -o "$TMP/font.tar.xz" \
  "https://github.com/ryanoasis/nerd-fonts/releases/download/$NERDFONTS_VER/DepartureMono.tar.xz"
mkdir -p "$DATA/fonts/DepartureMono"
tar -xJf "$TMP/font.tar.xz" -C "$DATA/fonts/DepartureMono" --wildcards '*.otf'
fc-cache -f "$DATA/fonts" >/dev/null

# ---------- widgets ----------
install_plasmoid() {  # $1 = path to .plasmoid or directory
  kpackagetool6 -t Plasma/Applet -u "$1" >/dev/null 2>&1 || kpackagetool6 -t Plasma/Applet -i "$1" >/dev/null
}
say "Installing Panel Colorizer $COLORIZER_VER"
curl -fsSL -o "$TMP/colorizer.plasmoid" \
  "https://github.com/luisbocanegra/plasma-panel-colorizer/releases/download/$COLORIZER_VER/plasmoid-panel-colorizer-$COLORIZER_VER.plasmoid"
install_plasmoid "$TMP/colorizer.plasmoid"

say "Installing Plasmusic Toolbar $PLASMUSIC_VER"
curl -fsSL -o "$TMP/plasmusic.plasmoid" \
  "https://github.com/ccatterina/plasmusic-toolbar/releases/download/$PLASMUSIC_VER/plasmusic-toolbar-$PLASMUSIC_VER.plasmoid"
install_plasmoid "$TMP/plasmusic.plasmoid"

if [[ -d "$DATA/plasma/plasmoids/com.github.dip.speedingbullet" ]]; then
  say "Speeding Bullet already installed, leaving it as is"
else
  say "Installing Speeding Bullet (network speed widget)"
  git clone -q --depth 1 "$SPEEDINGBULLET_REPO" "$TMP/speedingbullet"
  rm -rf "$TMP/speedingbullet/.git"
  install_plasmoid "$TMP/speedingbullet"
fi

# ---------- icon theme ----------
say "Applying icon theme: $ICON_THEME"
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons /usr/lib*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)"
if [[ -n "$CHANGEICONS" ]]; then "$CHANGEICONS" "$ICON_THEME"
else kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICON_THEME"; fi

# ---------- panels ----------
say "Building top bar + dock"
PRESETS="$DATA/plasma/plasmoids/luisbocanegra.panel.colorizer/contents/ui/presets"
python3 -I - "$HERE/layout.js.in" "$PRESETS" "$TMP/layout.js" "$FONT" "$LAUNCHERS" "$MENU_LABEL" <<'EOF'
import json, sys
tpl, presets, out, font, launchers, label = sys.argv[1:]
preset = lambda n: json.dumps(json.load(open(f"{presets}/{n}/settings.json"))["globalSettings"], separators=(",", ":"))
js = open(tpl).read()
for k, v in {"__TOP__": preset("Rounded Widgets"), "__DOCK__": preset("Dock"),
             "__FONT__": font, "__LAUNCHERS__": launchers, "__MENU_LABEL__": label}.items():
    js = js.replace(k, json.dumps(v))
open(out, "w").write(js)
EOF
RESULT="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$TMP/layout.js")")"
read -r _ PANEL_ID ORDER <<<"$(grep '^ORDER ' <<<"$RESULT" || true)"
[[ -n "${PANEL_ID:-}" && -n "${ORDER:-}" ]] || die "Layout script failed: $RESULT"

# ---------- widget order (must be written while plasmashell is stopped) ----------
say "Restarting plasmashell"
if systemctl --user -q is-active plasma-plasmashell.service 2>/dev/null; then
  systemctl --user stop plasma-plasmashell.service
  kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
    --group Containments --group "$PANEL_ID" --group General --key AppletOrder "$ORDER"
  systemctl --user start plasma-plasmashell.service
else
  kquitapp6 plasmashell || true
  kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
    --group Containments --group "$PANEL_ID" --group General --key AppletOrder "$ORDER"
  (kstart plasmashell >/dev/null 2>&1 &)
fi

say "Done! Backup: $BACKUP   Undo: $HERE/uninstall.sh"
