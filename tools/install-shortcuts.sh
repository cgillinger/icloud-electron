#!/usr/bin/env bash
# Creates application-menu shortcuts for the iCloud services.
#
# Usage:
#   ./tools/install-shortcuts.sh                 # the common four
#   ./tools/install-shortcuts.sh photos mail     # only these
#   ./tools/install-shortcuts.sh --all           # every service
#   ./tools/install-shortcuts.sh --remove        # delete them again
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
APPS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
ICON_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/icons/icloud"

# service|slug|Window title|icon basename|fallback system icon|categories
#
# The slug names the .desktop file. It is kept short and stable so that
# regenerating shortcuts overwrites the previous ones instead of leaving
# duplicates behind in the menu.
CATALOGUE="
photos|photos|Photos|photos|multimedia-photo-manager|Network;Graphics;Photography;
iclouddrive|drive|Drive|drive|folder-cloud|Network;FileTransfer;
contacts|contacts|Contacts|contacts|x-office-address-book|Network;Office;ContactManagement;
notes|notes|Notes|notes|accessories-text-editor|Network;Office;
mail|mail|Mail|mail|internet-mail|Network;Email;
calendar|calendar|Calendar|calendar|office-calendar|Network;Office;Calendar;
reminders|reminders|Reminders|reminders|task-due|Network;Office;ProjectManagement;
pages|pages|Pages|pages|x-office-document|Network;Office;WordProcessor;
numbers|numbers|Numbers|numbers|x-office-spreadsheet|Network;Office;Spreadsheet;
keynote|keynote|Keynote|keynote|x-office-presentation|Network;Office;Presentation;
find|find|Find My|find|find-location|Network;
"

DEFAULT_SERVICES="photos iclouddrive contacts calendar"

launcher_path() {
    # Prefer a system-wide launcher when one is installed, so the shortcut
    # keeps working if the checkout is moved.
    for candidate in /usr/local/bin/icloud-app /usr/local/bin/icloud-electron; do
        [ -x "$candidate" ] && { echo "$candidate"; return; }
    done
    echo "$SCRIPT_DIR/icloud-app.sh"
}

lookup() {
    echo "$CATALOGUE" | awk -F'|' -v s="$1" '$1 == s { print; exit }'
}

remove_all() {
    local removed=0
    for file in "$APPS_DIR"/icloud-*.desktop; do
        [ -e "$file" ] || continue
        rm -f "$file"
        removed=$((removed + 1))
    done
    echo "Removed $removed shortcut(s)."
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true
    exit 0
}

case "${1:-}" in
    --remove) remove_all ;;
    --all)    SERVICES="$(echo "$CATALOGUE" | awk -F'|' 'NF {print $1}' | tr '\n' ' ')" ;;
    "")       SERVICES="$DEFAULT_SERVICES" ;;
    *)        SERVICES="$*" ;;
esac

LAUNCHER="$(launcher_path)"
mkdir -p "$APPS_DIR"

created=0
for service in $SERVICES; do
    entry="$(lookup "$service")"
    if [ -z "$entry" ]; then
        echo "Unknown service: $service" >&2
        continue
    fi

    IFS='|' read -r _ slug title icon_name fallback_icon categories <<<"$entry"

    if [ -f "$ICON_DIR/$icon_name.svg" ]; then
        icon="$ICON_DIR/$icon_name.svg"
    else
        icon="$fallback_icon"
    fi

    # StartupWMClass must match what the window actually reports. Chromium
    # names the instance after the URL it opened, and because every service
    # shares one browser process, the instance - not the class - is the part
    # that differs per service. Matching the class would give every window the
    # same icon.
    cat > "$APPS_DIR/icloud-$slug.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=iCloud $title
Comment=Access iCloud $title
Exec=$LAUNCHER $service $title
Icon=$icon
Terminal=false
StartupNotify=true
StartupWMClass=www.icloud.com__$service
Categories=$categories
EOF

    echo "  iCloud $title"
    created=$((created + 1))
done

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null || true

echo
echo "Created $created shortcut(s) in $APPS_DIR"
echo "Launcher: $LAUNCHER"
[ -d "$ICON_DIR" ] || echo "Tip: run ./install-icons.sh first for Apple-style icons."
