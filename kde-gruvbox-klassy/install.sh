#!/usr/bin/env bash
# Gruvbox Klassy rice for KDE Plasma 6 — user-level installer (no sudo).
# Run `sudo ./install-system.sh` first for Klassy, blur, rounded corners, SilentSDDM
# and the build tools Kara needs. This script still works without it; those parts
# are just skipped.
#
#   ./install.sh
#   LAUNCHERS="..." ./install.sh    # custom pinned apps in the dock
#   WALLPAPER=0 ./install.sh        # keep your current wallpaper
#
# Your current config is backed up to ~/plasma-backup-<timestamp>/ first.
set -euo pipefail

GRUVBOX_REPO="https://github.com/printesoi/kde-gruvbox.git"
REVERSAL_REPO="https://github.com/yeyushengfan258/Reversal-icon-theme.git"
BIBATA_URL="https://github.com/ful1e5/Bibata_Cursor/releases/download/v2.0.7/Bibata-Modern-Ice.tar.xz"
KURO_REPO="https://github.com/bouteillerAlan/kuro.git"
STATION_REPO="https://github.com/EliverLara/kde-control-station.git"
ANDROMEDA_REPO="https://github.com/EliverLara/AndromedaLauncher.git"
KARA_REPO="https://github.com/dhruv8sh/kara.git"
GEOMETRY_REPO="https://github.com/peterfajdiga/kwin4_effect_geometry_change.git"
WALLPAPER_URL="https://gruvbox-wallpapers.pages.dev/wallpapers/anime/Kita.png"

LAUNCHERS="${LAUNCHERS:-applications:systemsettings.desktop,preferred://filemanager,preferred://browser,applications:kitty.desktop}"
WALLPAPER="${WALLPAPER:-1}"

HERE="$(cd "$(dirname "$0")" && pwd)"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }
clone() { git clone -q --depth 1 "$1" "$TMP/$2"; }
install_plasmoid() { kpackagetool6 -t "$1" -u "$2" >/dev/null 2>&1 || kpackagetool6 -t "$1" -i "$2" >/dev/null; }

# ---------- preflight ----------
[[ $EUID -ne 0 ]] || die "Run as your normal user, not root."
[[ "${XDG_CURRENT_DESKTOP:-}" == *KDE* ]] || die "This needs a running KDE Plasma session."
for c in plasmashell qdbus6 kpackagetool6 kwriteconfig6 kreadconfig6 plasma-apply-lookandfeel curl git tar python3; do
  command -v "$c" >/dev/null || die "Missing command: $c"
done

# ---------- backup ----------
BACKUP="$HOME/plasma-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP"
for f in plasma-org.kde.plasma.desktop-appletsrc plasmashellrc plasmarc kdeglobals kwinrc kwinrulesrc ksplashrc kcminputrc; do
  [[ -f "$CONF/$f" ]] && cp -a "$CONF/$f" "$BACKUP/"
done
say "Backed up current config to $BACKUP"

# ---------- look and feel ----------
say "Global theme Breeze Dark + Plasma style Breeze Light"
plasma-apply-lookandfeel -a org.kde.breezedark.desktop >/dev/null
plasma-apply-desktoptheme breeze-light >/dev/null

say "Gruvbox colors"
clone "$GRUVBOX_REPO" gruvbox
mkdir -p "$DATA/color-schemes"
cp "$TMP/gruvbox/color-schemes/Gruvbox.colors" "$DATA/color-schemes/"
plasma-apply-colorscheme Gruvbox >/dev/null

say "Reversal-blue-dark icons"
clone "$REVERSAL_REPO" reversal
(cd "$TMP/reversal" && bash ./install.sh -t blue -d "$DATA/icons" >/dev/null)
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons /usr/lib*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)"
if [[ -n "$CHANGEICONS" ]]; then "$CHANGEICONS" Reversal-blue-dark
else kwriteconfig6 --file kdeglobals --group Icons --key Theme Reversal-blue-dark; fi

say "Bibata-Modern-Ice cursor"
curl -fsSL -o "$TMP/bibata.tar.xz" "$BIBATA_URL"
mkdir -p "$DATA/icons" "$HOME/.icons"
tar -xJf "$TMP/bibata.tar.xz" -C "$DATA/icons"
ln -sfn "$DATA/icons/Bibata-Modern-Ice" "$HOME/.icons/Bibata-Modern-Ice"   # cursor KCM only scans ~/.icons
plasma-apply-cursortheme Bibata-Modern-Ice >/dev/null

say "Kuro splash screen"
clone "$KURO_REPO" kuro
mkdir -p "$DATA/plasma/look-and-feel"
rm -rf "$DATA/plasma/look-and-feel/a2n.kuro"
cp -r "$TMP/kuro/a2n.kuro" "$DATA/plasma/look-and-feel/"
kwriteconfig6 --file ksplashrc --group KSplash --key Theme a2n.kuro
kwriteconfig6 --file ksplashrc --group KSplash --key Engine KSplashQML

if [[ "$WALLPAPER" == 1 ]]; then
  say "Kita wallpaper"
  WP_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")/Wallpapers"
  mkdir -p "$WP_DIR"
  curl -fsSL -o "$WP_DIR/Kita.png" "$WALLPAPER_URL"
  plasma-apply-wallpaperimage "$WP_DIR/Kita.png" >/dev/null
fi

# ---------- widgets ----------
say "KDE Control Station + Andromeda Launcher"
clone "$STATION_REPO" station;     install_plasmoid Plasma/Applet "$TMP/station/package"
clone "$ANDROMEDA_REPO" andromeda; rm -rf "$TMP/andromeda/.git"; install_plasmoid Plasma/Applet "$TMP/andromeda"

PAGER=org.kde.plasma.pager
say "Kara workspace indicator (compiled into ~/.local)"
clone "$KARA_REPO" kara
if cmake -S "$TMP/kara" -B "$TMP/kara/build" -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
         -DCMAKE_BUILD_TYPE=Release -DKDE_INSTALL_USE_QT_SYS_PATHS=OFF >"$TMP/kara.log" 2>&1 \
   && cmake --build "$TMP/kara/build" -j"$(nproc)" >>"$TMP/kara.log" 2>&1 \
   && cmake --install "$TMP/kara/build" >/dev/null 2>&1; then
  QMLDIR="$(dirname "$(dirname "$(dirname "$(find "$HOME"/.local/lib* -name libkaraplugin.so -print -quit 2>/dev/null)")")")"
  QMLDIR="$(dirname "$QMLDIR")"     # .../lib64/qml
  mkdir -p "$CONF/plasma-workspace/env"
  cat > "$CONF/plasma-workspace/env/kara.sh" <<EOF
# Lets plasmashell find the Kara pager's QML plugin (built into ~/.local)
export QML_IMPORT_PATH="$QMLDIR\${QML_IMPORT_PATH:+:\$QML_IMPORT_PATH}"
export QML2_IMPORT_PATH="$QMLDIR\${QML2_IMPORT_PATH:+:\$QML2_IMPORT_PATH}"
EOF
  chmod +x "$CONF/plasma-workspace/env/kara.sh"
  systemctl --user set-environment QML_IMPORT_PATH="$QMLDIR" QML2_IMPORT_PATH="$QMLDIR" 2>/dev/null || true
  PAGER=org.dhruv8sh.kara
else
  warn "Kara didn't build (run sudo ./install-system.sh for its build tools). Using the standard pager."
fi

# ---------- KWin ----------
say "KWin effects, decoration and window rule"
clone "$GEOMETRY_REPO" geometry; install_plasmoid KWin/Effect "$TMP/geometry/package"
kw() { kwriteconfig6 --file kwinrc --group "$1" --key "$2" "$3"; }
kw Plugins sheetEnabled true
kw Plugins kwin4_effect_geometry_changeEnabled true
plugin_exists() { ls /usr/lib*/qt6/plugins/"$1" >/dev/null 2>&1; }
if plugin_exists kwin/effects/plugins/better_blur_dx.so; then kw Plugins blurEnabled false; kw Plugins better_blur_dxEnabled true
else warn "Better Blur DX not installed (sudo ./install-system.sh)"; fi
if plugin_exists kwin/effects/plugins/kwin4_effect_shapecorners.so; then kw Plugins kwin4_effect_shapecornersEnabled true
else warn "Rounded Corners not installed (sudo ./install-system.sh)"; fi
if plugin_exists org.kde.kdecoration3/org.kde.klassy.so; then
  kw org.kde.kdecoration2 library org.kde.klassy
  kw org.kde.kdecoration2 theme Klassy
  kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Klassy
else warn "Klassy not installed (sudo ./install-system.sh)"; fi

# 90% opacity for normal windows, added next to any rules you already have
RID=gruvbox-opacity-90
RULES="$(kreadconfig6 --file kwinrulesrc --group General --key rules)"
if [[ ",$RULES," != *",$RID,"* ]]; then
  RULES="${RULES:+$RULES,}$RID"
  kwriteconfig6 --file kwinrulesrc --group General --key rules "$RULES"
  kwriteconfig6 --file kwinrulesrc --group General --key count "$(tr ',' '\n' <<<"$RULES" | grep -c .)"
fi
for kv in "Description=Opacity 90%" types=1 wmclassmatch=0 opacityactive=90 opacityactiverule=2 opacityinactive=90 opacityinactiverule=2; do
  kwriteconfig6 --file kwinrulesrc --group "$RID" --key "${kv%%=*}" "${kv#*=}"
done
qdbus6 org.kde.KWin /KWin reconfigure

# 3 workspaces so the pill indicator has something to show
VD=org.kde.KWin.VirtualDesktopManager
n="$(qdbus6 org.kde.KWin /VirtualDesktopManager org.freedesktop.DBus.Properties.Get $VD count)"
while (( n < 3 )); do qdbus6 org.kde.KWin /VirtualDesktopManager $VD.createDesktop "$n" "Desktop $((n+1))"; n=$((n+1)); done

# ---------- panels ----------
say "Building top bar + dock"
python3 -I - "$HERE/layout.js.in" "$TMP/layout.js" "$LAUNCHERS" "$PAGER" <<'EOF'
import json, sys
tpl, out, launchers, pager = sys.argv[1:]
js = open(tpl).read().replace("__LAUNCHERS__", json.dumps(launchers)).replace("__PAGER__", json.dumps(pager))
open(out, "w").write(js)
EOF

restart_shell() {  # $1 = optional AppletOrder "<panel id> <order>"
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
restart_shell    # pick up the new widgets + Kara's QML path

RESULT="$(qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$(cat "$TMP/layout.js")")"
read -r _ PANEL_ID ORDER <<<"$(grep '^ORDER ' <<<"$RESULT" || true)"
[[ -n "${PANEL_ID:-}" && -n "${ORDER:-}" ]] || die "Layout script failed: $RESULT"
restart_shell "$PANEL_ID $ORDER"

say "Done! Log out and back in so KWin loads the compiled effects and the splash/login screen show."
say "Backup: $BACKUP   Undo: $HERE/uninstall.sh"
