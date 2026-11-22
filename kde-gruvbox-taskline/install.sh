#!/usr/bin/env bash
# Gruvbox Taskline for KDE Plasma 6: user-level installer (no sudo).
# For Klassy, Better Blur DX and the SilentSDDM login screen, run the Gruvbox Klassy
# system installer first:  sudo ../kde-gruvbox-klassy/install-system.sh
# This script still works without it; those parts are just skipped.
#
#   ./install.sh
#   LAUNCHERS="..." ./install.sh    # custom pinned apps
#   WALLPAPER=0 ./install.sh        # keep your current wallpaper
#   FONT=0 ./install.sh             # keep your current font
#
# Your current config is backed up to ~/plasma-backup-<timestamp>/ first.
set -euo pipefail

GRUVBOX_REPO="https://github.com/printesoi/kde-gruvbox.git"
PAPIRUS_TAG="20260801"
PAPIRUS_URL="https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/$PAPIRUS_TAG.tar.gz"
BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice.tar.xz"
INTER_URL="https://github.com/rsms/inter/releases/download/v4.1/Inter-4.1.zip"
KURO_REPO="https://github.com/bouteillerAlan/kuro.git"
FANCYTASKS_URL="https://github.com/DayDve/FancyTasksNG/releases/download/v2.3.0/FancyTasksNG.plasmoid"
FANCYTASKS_SHA256="5c8719e922bf86b3a87d3a16dc84abc466b1ac94df0e9a0dea6eba9f39e1efb0"
STATION_REPO="https://github.com/EliverLara/kde-control-station.git"
GEOMETRY_REPO="https://github.com/peterfajdiga/kwin4_effect_geometry_change.git"
WALLPAPER_URL="https://gruvbox-wallpapers.pages.dev/wallpapers/anime/Kita.png"

LAUNCHERS="${LAUNCHERS:-applications:systemsettings.desktop,applications:org.kde.discover.desktop,preferred://filemanager,preferred://browser}"
WALLPAPER="${WALLPAPER:-1}"
FONT="${FONT:-1}"

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
MANIFEST="$DATA/gruvbox-taskline/installed.txt"   # what this script added, for uninstall.sh --purge
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
clone() { git clone -q --depth 1 "$1" "$TMP/$2"; }
record() { grep -qxF "$1" "$MANIFEST" 2>/dev/null || echo "$1" >> "$MANIFEST"; }
has_plasmoid() { kpackagetool6 -t "$1" --list 2>/dev/null | grep -qx "$2"; }
install_plasmoid() {   # $1 type, $2 path, $3 plugin id
  if has_plasmoid "$1" "$3"; then kpackagetool6 -t "$1" -u "$2" >/dev/null
  else kpackagetool6 -t "$1" -i "$2" >/dev/null; record "plasmoid:$1:$3"; fi
}
icon_theme_present() { [[ -d "$DATA/icons/$1" || -d "$HOME/.icons/$1" || -d "/usr/share/icons/$1" ]]; }

# ---------- preflight ----------
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root."
[[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] || die "This needs a running KDE Plasma session."
for c in plasmashell qdbus6 kpackagetool6 kwriteconfig6 kreadconfig6 plasma-apply-lookandfeel \
         plasma-apply-desktoptheme plasma-apply-colorscheme plasma-apply-cursortheme curl git tar unzip sha256sum python3; do
  command -v "$c" >/dev/null || die "Missing command: $c"
done
mkdir -p "$(dirname "$MANIFEST")"; touch "$MANIFEST"

# ---------- backup ----------
BACKUP="$HOME/plasma-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc plasmarc kdeglobals kwinrc kwinrulesrc ksplashrc kcminputrc; do
  [[ -f "$CONF/$f" ]] && cp -a "$CONF/$f" "$BACKUP/"
done
[[ -f "$CONF/klassy/klassyrc" ]] && mkdir -p "$BACKUP/klassy" && cp -a "$CONF/klassy/klassyrc" "$BACKUP/klassy/"
say "Backed up current config to $BACKUP"

# ---------- look and feel ----------
say "Global theme Breeze Dark"
plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null

if [[ -d /usr/share/plasma/desktoptheme/openSUSE ]]; then
  say "Plasma style openSUSE (follows the Gruvbox colors)"
  plasma-apply-desktoptheme openSUSE >/dev/null
else
  warn "openSUSE Plasma style not found (it ships with openSUSE). Using Breeze, which also follows the colors."
  plasma-apply-desktoptheme default >/dev/null
fi

say "Gruvbox colors"
clone "$GRUVBOX_REPO" gruvbox
mkdir -p "$DATA/color-schemes"
[[ -f "$DATA/color-schemes/Gruvbox.colors" ]] || record "$DATA/color-schemes/Gruvbox.colors"
cp "$TMP/gruvbox/color-schemes/Gruvbox.colors" "$DATA/color-schemes/"
plasma-apply-colorscheme Gruvbox >/dev/null

say "Papirus-Light icons"
if icon_theme_present Papirus-Light; then
  echo "    already installed"
else
  curl -fsSL -o "$TMP/papirus.tar.gz" "$PAPIRUS_URL"
  mkdir -p "$TMP/papirus" "$DATA/icons"
  tar -xzf "$TMP/papirus.tar.gz" -C "$TMP/papirus" --strip-components=1 \
      "papirus-icon-theme-$PAPIRUS_TAG/Papirus" "papirus-icon-theme-$PAPIRUS_TAG/Papirus-Light"
  for t in Papirus Papirus-Light; do   # Papirus-Light is mostly links into Papirus
    [[ -d "$DATA/icons/$t" ]] || record "$DATA/icons/$t"
    rm -rf "$DATA/icons/$t"; cp -a "$TMP/papirus/$t" "$DATA/icons/"
  done
fi
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons /usr/lib*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)"
if [[ -n "$CHANGEICONS" ]]; then "$CHANGEICONS" Papirus-Light
else kwriteconfig6 --file kdeglobals --group Icons --key Theme Papirus-Light; fi

say "Bibata-Modern-Ice cursor"
if ! icon_theme_present Bibata-Modern-Ice; then
  curl -fsSL -o "$TMP/bibata.tar.xz" "$BIBATA_URL"
  mkdir -p "$DATA/icons" "$HOME/.icons"
  tar -xJf "$TMP/bibata.tar.xz" -C "$DATA/icons"
  ln -sfn "$DATA/icons/Bibata-Modern-Ice" "$HOME/.icons/Bibata-Modern-Ice"   # the cursor KCM only scans ~/.icons
  record "$DATA/icons/Bibata-Modern-Ice"; record "$HOME/.icons/Bibata-Modern-Ice"
fi
plasma-apply-cursortheme Bibata-Modern-Ice >/dev/null

if [[ "$FONT" == 1 ]]; then
  say "Inter font"
  if fc-list 2>/dev/null | grep -qE '/Inter\.ttc|InterVariable'; then
    echo "    already installed"
  else
    curl -fsSL -o "$TMP/inter.zip" "$INTER_URL"
    mkdir -p "$DATA/fonts/inter"
    unzip -q -o -j "$TMP/inter.zip" Inter.ttc InterVariable.ttf InterVariable-Italic.ttf -d "$DATA/fonts/inter"
    fc-cache -f "$DATA/fonts" >/dev/null 2>&1 || true
    record "$DATA/fonts/inter"
  fi
  kwriteconfig6 --file kdeglobals --group General --key font "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
fi

say "Kuro splash screen"
clone "$KURO_REPO" kuro
mkdir -p "$DATA/plasma/look-and-feel"
[[ -d "$DATA/plasma/look-and-feel/a2n.kuro" ]] || record "$DATA/plasma/look-and-feel/a2n.kuro"
rm -rf "$DATA/plasma/look-and-feel/a2n.kuro"
cp -r "$TMP/kuro/a2n.kuro" "$DATA/plasma/look-and-feel/"
kwriteconfig6 --file ksplashrc --group KSplash --key Theme a2n.kuro
kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML

if [[ "$WALLPAPER" == 1 ]]; then
  say "Kita wallpaper"
  WP_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
  mkdir -p "$WP_DIR"
  [[ -f "$WP_DIR/Kita.png" ]] || { curl -fsSL -o "$WP_DIR/Kita.png" "$WALLPAPER_URL"; record "$WP_DIR/Kita.png"; }
  plasma-apply-wallpaperimage "$WP_DIR/Kita.png" >/dev/null
fi

# ---------- widgets ----------
say "FancyTasksNG v2.3.0 (task manager with per-app colored lines)"
curl -fsSL -o "$TMP/FancyTasksNG.plasmoid" "$FANCYTASKS_URL"
echo "$FANCYTASKS_SHA256  $TMP/FancyTasksNG.plasmoid" | sha256sum -c --quiet - || die "FancyTasksNG download doesn't match the expected checksum."
install_plasmoid Plasma/Applet "$TMP/FancyTasksNG.plasmoid" io.github.daydve.fancytasksng

say "KDE Control Station"
clone "$STATION_REPO" station
install_plasmoid Plasma/Applet "$TMP/station/package" KdeControlStation

# ---------- KWin ----------
say "KWin effects and window decoration"
clone "$GEOMETRY_REPO" geometry
install_plasmoid KWin/Effect "$TMP/geometry/package" kwin4_effect_geometry_change
kw() { kwriteconfig6 --file kwinrc --group "$1" --key "$2" "$3"; }
kw Plugins sheetEnabled true
kw Plugins kwin4_effect_geometry_changeEnabled true
kw Plugins kwin4_effect_shapecornersEnabled false          # square corners: Rounded Corners stays off
plugin_exists() { ls /usr/lib*/qt6/plugins/"$1" >/dev/null 2>&1; }
if plugin_exists kwin/effects/plugins/better_blur_dx.so; then kw Plugins blurEnabled false; kw Plugins better_blur_dxEnabled true
else kw Plugins blurEnabled true; warn "Better Blur DX not installed (sudo ../kde-gruvbox-klassy/install-system.sh); using Plasma's blur."; fi
if plugin_exists org.kde.kdecoration3/org.kde.klassy.so; then
  kw org.kde.kdecoration2 library org.kde.klassy
  kw org.kde.kdecoration2 theme Klassy
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Klassy
  k() { kwriteconfig6 --file klassy/klassyrc --group Windeco --key "$1" "$2"; }
  k WindowCornerRadius 0
  k RoundAllCornersWhenNoBorders false
  k ButtonCornerRadius Custom
  k ButtonCustomCornerRadius 4
else warn "Klassy not installed (sudo ../kde-gruvbox-klassy/install-system.sh); keeping your window decoration."; fi

# Gruvbox Klassy's 90% opacity rule doesn't belong to this theme: drop it if present.
# KWin 6.8 lists rules in [General] Order=; older versions used rules=.
RID=gruvbox-opacity-90
for key in Order rules; do
  cur="$(kreadconfig6 --file kwinrulesrc --group General --key "$key")"
  if [[ ",$cur," == *",$RID,"* ]]; then
    new="$(tr ',' '\n' <<<"$cur" | { grep -vx "$RID" || true; } | paste -sd, -)"
    kwriteconfig6 --file kwinrulesrc --group General --key "$key" "$new"
  fi
done
qdbus6 org.kde.KWin /KWin reconfigure

# ---------- panel ----------
say "Building the bottom panel"
python3 -I - "$HERE/layout.js.in" "$TMP/layout.js" "$LAUNCHERS" <<'EOF'
import json, sys
tpl, out, launchers = sys.argv[1:]
open(out, "w").write(open(tpl).read().replace("__LAUNCHERS__", json.dumps(launchers)))
EOF

restart_shell() {  # $1 = optional "<panel id> <AppletOrder>"
  if systemctl --user -q is-active plasma-plasmashell.service 2>/dev/null; then
    systemctl --user stop plasma-plasmashell.service
    [[ -n "${1:-}" ]] && kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
      --group Containments --group "${1%% *}" --group General --key AppletOrder "${1#* }"
    systemctl --user start plasma-plasmashell.service
    timeout 30 bash -c 'until qdbus6 org.kde.plasmashell /PlasmaShell >/dev/null 2>&1; do sleep 0.3; done'
  else
    kquitapp6 plasmashell || true
    [[ -n "${1:-}" ]] && kwriteconfig6 --file plasma-org.kde.plasma.desktop-appletsrc \
      --group Containments --group "${1%% *}" --group General --key AppletOrder "${1#* }"
    (kstart plasmashell >/dev/null 2>&1 &); sleep 5
  fi
}
restart_shell    # load the freshly installed widgets

RESULT="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$TMP/layout.js")")"
read -r _ PANEL_ID ORDER <<<"$(grep '^ORDER ' <<<"$RESULT" || true)"
[[ -n "${PANEL_ID:-}" && -n "${ORDER:-}" ]] || die "Layout script failed: $RESULT"
restart_shell "$PANEL_ID $ORDER"   # Plasma overwrites AppletOrder while running

say "Done! Log out and back in so KWin and the splash screen pick everything up."
say "Backup: $BACKUP   Undo: $HERE/uninstall.sh"
