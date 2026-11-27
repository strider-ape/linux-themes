#!/usr/bin/env bash
# Gruvbox Klassy — system-wide parts. Run FIRST, with sudo:
#
#   sudo ./install-system.sh
#
#  1. Build dependencies (openSUSE: zypper; Debian/Ubuntu: apt; other distros: install them yourself)
#  2. Klassy (window decoration + application style), skipped if already installed
#  3. Better Blur DX + KDE Rounded Corners (KWin effects)
#  4. SilentSDDM login theme + an SDDM drop-in config
#
# Every file written is listed in /var/lib/gruvbox-klassy/installed-files.txt
# (uninstall.sh --system removes them).
#
# These are compiled KWin/KDecoration plugins: after a Plasma update, if blur or rounded
# corners stop working, just run this script again to rebuild them.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0" >&2; exit 1; }

KLASSY_REPO="https://github.com/paulmcauley/klassy.git"
BLUR_REPO="https://github.com/xarblu/kwin-effects-better-blur-dx.git"
CORNERS_REPO="https://github.com/matinlotfali/KDE-Rounded-Corners.git"
SILENT_REPO="https://github.com/uiriansan/SilentSDDM.git"

MANIFEST=/var/lib/gruvbox-klassy/installed-files.txt
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
say() { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
mkdir -p "$(dirname "$MANIFEST")"; touch "$MANIFEST"

# ---------- 1. dependencies ----------
DEPS=(git cmake gcc-c++ gettext kf6-extra-cmake-modules
  "cmake(Qt6Core)" "cmake(Qt6DBus)" "cmake(Qt6Quick)" "cmake(Qt6Svg)" "cmake(Qt6Widgets)"
  "cmake(Qt6Xml)" "cmake(Qt6UiTools)" qt6-core-private-devel qt6-quick-devel
  "cmake(KF6Config)" "cmake(KF6ConfigWidgets)" "cmake(KF6CoreAddons)" "cmake(KF6ColorScheme)"
  "cmake(KF6FrameworkIntegration)" "cmake(KF6GuiAddons)" "cmake(KF6I18n)" "cmake(KF6KCMUtils)"
  "cmake(KF6KirigamiPlatform)" "cmake(KF6WindowSystem)" "cmake(KF6Crash)" "cmake(KF6GlobalAccel)"
  "cmake(KF6KIO)" "cmake(KF6Service)" "cmake(KF6Notifications)" "cmake(KF6ItemModels)"
  "cmake(KF6IconThemes)" "cmake(KDecoration3)" "cmake(Plasma)" "cmake(PlasmaActivities)"
  "cmake(LibTaskManager)" kwin6-devel wayland-devel libepoxy-devel libdrm-devel
  # SilentSDDM runtime
  sddm-qt6 libQt6Svg6 qt6-virtualkeyboard qt6-virtualkeyboard-imports
  qt6-multimedia qt6-multimedia-imports qt6-imageformats)
# The same, under Debian/Ubuntu names (checked against Debian Testing, Plasma 6.7)
DEPS_DEB=(git cmake g++ gettext extra-cmake-modules
  qt6-base-dev qt6-base-private-dev qt6-declarative-dev qt6-declarative-private-dev qt6-svg-dev qt6-tools-dev
  libkf6config-dev libkf6configwidgets-dev libkf6coreaddons-dev libkf6colorscheme-dev libkf6style-dev
  libkf6guiaddons-dev libkf6i18n-dev libkf6kcmutils-dev libkirigami-dev libkf6windowsystem-dev
  libkf6crash-dev libkf6globalaccel-dev libkf6kio-dev libkf6service-dev libkf6notifications-dev
  libkf6itemmodels-dev libkf6iconthemes-dev libkdecorations3-dev libplasma-dev libplasmaactivities-dev
  plasma-workspace-dev kwin-dev libwayland-dev libepoxy-dev libdrm-dev
  # SilentSDDM runtime
  sddm libqt6svg6 qml6-module-qtquick-virtualkeyboard qt6-virtualkeyboard-plugin
  qml6-module-qtmultimedia qt6-image-formats-plugins)
if command -v zypper >/dev/null; then
  say "Installing build dependencies with zypper"
  zypper --non-interactive in --no-recommends "${DEPS[@]}"
elif command -v apt-get >/dev/null; then
  say "Installing build dependencies with apt"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${DEPS_DEB[@]}"
else
  echo "No zypper or apt: make sure the equivalents of these (openSUSE names) are installed:"; printf '  %s\n' "${DEPS[@]}"
  if [[ -t 0 ]]; then read -rp "Continue? [y/N] " a; [[ "$a" == [yY]* ]] || exit 1
  else echo "No terminal to ask: continuing; a build stops with the name of anything missing."; fi
fi

# Parallel compile jobs: about one per 2 GB of RAM (all cores can freeze a low-RAM PC).
# Override with JOBS=n.
MEM_GB=$(awk '/^MemTotal/ {print int($2 / 1048576)}' /proc/meminfo)
JOBS="${JOBS:-$(( MEM_GB / 2 < 1 ? 1 : (MEM_GB / 2 < $(nproc) ? MEM_GB / 2 : $(nproc)) ))}"
say "Compiling with $JOBS job(s)"

build_install() {  # $1 name, $2 repo, $3... extra cmake args
  local name=$1 repo=$2; shift 2
  say "Building $name"
  git clone -q --depth 1 "$repo" "$TMP/$name"
  cmake -S "$TMP/$name" -B "$TMP/$name/build" -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF "$@" >"$TMP/$name.log" 2>&1 \
    || { tail -30 "$TMP/$name.log"; exit 1; }
  cmake --build "$TMP/$name/build" -j"$JOBS" >>"$TMP/$name.log" 2>&1 \
    || { tail -30 "$TMP/$name.log"; exit 1; }
  cmake --install "$TMP/$name/build" >/dev/null
  cat "$TMP/$name/build/install_manifest.txt" >> "$MANIFEST"; echo >> "$MANIFEST"
}

# ---------- 2-3. compiled plugins ----------
if [[ -e /usr/lib64/qt6/plugins/org.kde.kdecoration3/org.kde.klassy.so || -e /usr/lib/qt6/plugins/org.kde.kdecoration3/org.kde.klassy.so ]]; then
  say "Klassy already installed, skipping"
else
  build_install klassy "$KLASSY_REPO" -DBUILD_QT5=OFF
fi
build_install better-blur-dx "$BLUR_REPO"
build_install rounded-corners "$CORNERS_REPO"

# ---------- 4. SilentSDDM ----------
say "Installing SilentSDDM"
git clone -q --depth 1 -b main "$SILENT_REPO" "$TMP/silent"
THEME=/usr/share/sddm/themes/silent
rm -rf "$THEME"; mkdir -p "$THEME"
(cd "$TMP/silent" && tar --exclude=.git -cf - .) | tar -xf - -C "$THEME" --no-same-owner
echo "$THEME/" >> "$MANIFEST"
for f in redhat redhat-vf; do
  rm -rf "/usr/share/fonts/$f"; cp -r "$THEME/fonts/$f" /usr/share/fonts/
  echo "/usr/share/fonts/$f/" >> "$MANIFEST"
done
fc-cache -f >/dev/null

# Keep openSUSE's layer-shell setting (its SDDM greeter runs on kwin_wayland).
GREETER_ENV="QML2_IMPORT_PATH=$THEME/components/,QT_IM_MODULE=qtvirtualkeyboard"
grep -rqs 'QT_WAYLAND_SHELL_INTEGRATION=layer-shell' /usr/lib/sddm/sddm.conf.d/ \
  && GREETER_ENV="QT_WAYLAND_SHELL_INTEGRATION=layer-shell,$GREETER_ENV"
mkdir -p /etc/sddm.conf.d
cat > /etc/sddm.conf.d/50-silent.conf <<EOF
[General]
InputMethod=qtvirtualkeyboard
GreeterEnvironment=$GREETER_ENV

[Theme]
Current=silent
EOF
echo "/etc/sddm.conf.d/50-silent.conf" >> "$MANIFEST"
sort -u -o "$MANIFEST" "$MANIFEST"; sed -i '/^$/d' "$MANIFEST"

say "Done. Now run ./install.sh as your normal user (no sudo)."
