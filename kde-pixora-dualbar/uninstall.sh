#!/usr/bin/env bash
# Restore the Plasma config saved by install.sh.
#
#   ./uninstall.sh                      # restore the newest ~/plasma-backup-*
#   ./uninstall.sh ~/plasma-backup-XYZ  # restore a specific backup
#   ./uninstall.sh --purge [backup]     # also delete the icons, font and widgets
set -euo pipefail

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

ICONS="$(kreadconfig6 --file kdeglobals --group Icons --key Theme 2>/dev/null || true)"
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons 2>/dev/null | head -1 || true)"
[[ -n "$CHANGEICONS" ]] && "$CHANGEICONS" "${ICONS:-breeze-dark}" || true

if (( PURGE )); then
  echo "==> Removing icons, font and widgets"
  rm -rf "$DATA"/icons/{pixora,pixora-dark,pixora-accent} "$DATA/fonts/DepartureMono"
  for id in luisbocanegra.panel.colorizer plasmusic-toolbar; do
    kpackagetool6 -t Plasma/Applet -r "$id" >/dev/null 2>&1 || true
  done
  fc-cache -f >/dev/null
  echo "    (Speeding Bullet was kept; remove it with: kpackagetool6 -t Plasma/Applet -r com.github.dip.speedingbullet)"
fi
echo "==> Done"
