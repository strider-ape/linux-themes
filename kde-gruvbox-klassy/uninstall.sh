#!/usr/bin/env bash
# Undo the Gruvbox Klassy rice.
#
#   ./uninstall.sh                      # restore the newest ~/plasma-backup-*
#   ./uninstall.sh ~/plasma-backup-XYZ  # restore a specific backup
#   ./uninstall.sh --purge [backup]     # also delete the user-level themes/widgets/Kara
#   sudo ./uninstall.sh --system        # remove what install-system.sh installed
set -euo pipefail

MANIFEST=/var/lib/gruvbox-klassy/installed-files.txt

if [[ "${1:-}" == "--system" ]]; then
  [[ $EUID -eq 0 ]] || { echo "Run with sudo: sudo $0 --system" >&2; exit 1; }
  [[ -f "$MANIFEST" ]] || { echo "Nothing to remove ($MANIFEST not found)." >&2; exit 1; }
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      /usr/*|/etc/sddm.conf.d/50-silent.conf) rm -rf -- "$f" ;;
      *) echo "skipping unexpected path: $f" ;;
    esac
  done < "$MANIFEST"
  rm -f "$MANIFEST"; fc-cache -f >/dev/null
  echo "==> System parts removed. SDDM is back to the openSUSE/Breeze theme; log out and back in for KWin."
  exit 0
fi

[[ $EUID -ne 0 ]] || { echo "Run as your normal user (only --system needs sudo)." >&2; exit 1; }
PURGE=0
[[ "${1:-}" == "--purge" ]] && { PURGE=1; shift; }
BACKUP="${1:-$(ls -dt "$HOME"/plasma-backup-* 2>/dev/null | head -1 || true)}"
[[ -d "$BACKUP" ]] || { echo "No backup found (looked for ~/plasma-backup-*)." >&2; exit 1; }

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"

echo "==> Restoring $BACKUP"
if systemctl --user -q is-active plasma-plasmashell.service 2>/dev/null; then
  systemctl --user stop plasma-plasmashell.service
  cp -a "$BACKUP"/. "$CONF"/
  systemctl --user start plasma-plasmashell.service
else
  kquitapp6 plasmashell || true
  cp -a "$BACKUP"/. "$CONF"/
  (kstart plasmashell >/dev/null 2>&1 &)
fi
qdbus6 org.kde.KWin /KWin reconfigure || true

# Re-apply the restored icon/cursor/colors to the live session
ICONS="$(kreadconfig6 --file kdeglobals --group Icons --key Theme || true)"
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons /usr/lib*/libexec/plasma-changeicons /usr/lib/*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)"
[[ -n "$CHANGEICONS" && -n "$ICONS" ]] && "$CHANGEICONS" "$ICONS" || true
CURSOR="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme || true)"
plasma-apply-cursortheme "${CURSOR:-breeze_cursors}" >/dev/null 2>&1 || true
SCHEME="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme || true)"
[[ -n "$SCHEME" ]] && plasma-apply-colorscheme "$SCHEME" >/dev/null 2>&1 || true

if (( PURGE )); then
  echo "==> Removing user-level themes and widgets"
  rm -rf "$DATA"/icons/Reversal-blue{,-dark,-light} "$DATA/icons/Bibata-Modern-Ice" "$HOME/.icons/Bibata-Modern-Ice" \
         "$DATA/color-schemes/Gruvbox.colors" "$DATA/plasma/look-and-feel/a2n.kuro" \
         "$CONF/plasma-workspace/env/kara.sh"
  for id in KdeControlStation AndromedaLauncher org.dhruv8sh.kara; do
    kpackagetool6 -t Plasma/Applet -r "$id" >/dev/null 2>&1 || true
  done
  kpackagetool6 -t KWin/Effect -r kwin4_effect_geometry_change >/dev/null 2>&1 || true
  rm -rf "$HOME"/.local/lib*/qml/org/dhruv8sh "$HOME"/.local/lib*/libkara.so*
  echo "    (Virtual desktops added by install.sh were kept; remove them in System Settings → Virtual Desktops.)"
fi
echo "==> Done. Log out and back in to fully reset KWin effects."
