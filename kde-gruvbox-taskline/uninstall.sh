#!/usr/bin/env bash
# Undo the Gruvbox Taskline theme.
#
#   ./uninstall.sh                      # restore the newest ~/plasma-backup-*
#   ./uninstall.sh ~/plasma-backup-XYZ  # restore a specific backup
#   ./uninstall.sh --purge [backup]     # also remove what install.sh added (and only that)
#
# System parts (Klassy, Better Blur DX, SilentSDDM) belong to Gruvbox Klassy:
#   sudo ../kde-gruvbox-klassy/uninstall.sh --system
set -euo pipefail

[[ $EUID -ne 0 ]] || { echo "Run as your normal user." >&2; exit 1; }
PURGE=0
[[ "${1:-}" == "--purge" ]] && { PURGE=1; shift; }
BACKUP="${1:-$(ls -dt "$HOME"/plasma-backup-* 2>/dev/null | head -1 || true)}"
[[ -d "$BACKUP" ]] || { echo "No backup found (looked for ~/plasma-backup-*)." >&2; exit 1; }

CONF="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
MANIFEST="$DATA/gruvbox-taskline/installed.txt"

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

# Re-apply the restored style, icons, cursor and colors to the live session
STYLE="$(kreadconfig6 --file plasmarc --group Theme --key name || true)"
plasma-apply-desktoptheme "${STYLE:-default}" >/dev/null 2>&1 || true
ICONS="$(kreadconfig6 --file kdeglobals --group Icons --key Theme || true)"
CHANGEICONS="$(ls /usr/libexec/plasma-changeicons /usr/lib/plasma-changeicons /usr/lib*/libexec/plasma-changeicons /usr/lib/*/libexec/plasma-changeicons 2>/dev/null | head -1 || true)"
[[ -n "$CHANGEICONS" && -n "$ICONS" ]] && "$CHANGEICONS" "$ICONS" || true
CURSOR="$(kreadconfig6 --file kcminputrc --group Mouse --key cursorTheme || true)"
plasma-apply-cursortheme "${CURSOR:-breeze_cursors}" >/dev/null 2>&1 || true
SCHEME="$(kreadconfig6 --file kdeglobals --group General --key ColorScheme || true)"
[[ -n "$SCHEME" ]] && plasma-apply-colorscheme "$SCHEME" >/dev/null 2>&1 || true

if (( PURGE )); then
  if [[ -f "$MANIFEST" ]]; then
    echo "==> Removing what install.sh added"
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      case "$item" in
        plasmoid:*)
          rest="${item#plasmoid:}"; type="${rest%:*}"; id="${rest##*:}"
          kpackagetool6 -t "$type" -r "$id" >/dev/null 2>&1 && echo "    removed $id" || true ;;
        "$HOME"/*)
          rm -rf -- "$item" && echo "    removed ${item/#$HOME/\~}" ;;
        *) echo "    skipping unexpected entry: $item" ;;
      esac
    done < "$MANIFEST"
    rm -f "$MANIFEST"; rmdir "$(dirname "$MANIFEST")" 2>/dev/null || true
    fc-cache -f >/dev/null 2>&1 || true
  else
    echo "==> Nothing to purge ($MANIFEST not found)"
  fi
fi
echo "==> Done. Log out and back in to fully reset KWin."
