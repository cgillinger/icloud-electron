#!/bin/bash
# install-icons.sh - Download and install iCloud icons

set -e

ICON_DIR="$HOME/.local/share/icons/icloud"
TEMP_DIR="$(mktemp -d)"

# Rensa temp-katalogen vid avbrott eller fel
trap 'rm -rf "$TEMP_DIR"' EXIT

echo "📥 Installing iCloud icons..."

# Create directories
mkdir -p "$ICON_DIR"

BASE_URL="https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps"

# Associative array: local filename -> remote icon name
declare -A ICONS=(
    [photos]="multimedia-photo-manager"
    [drive]="folder-cloud"
    [contacts]="preferences-contact-list"
    [notes]="accessories-notes"
    [mail]="internet-mail"
    [calendar]="office-calendar"
    [reminders]="stock_todo"
)

echo "  Downloading icon set..."

downloaded=0
for name in "${!ICONS[@]}"; do
    remote="${ICONS[$name]}"
    if curl -sL --fail "${BASE_URL}/${remote}.svg" -o "${TEMP_DIR}/${name}.svg" 2>/dev/null; then
        # Remove if file is empty (0 bytes)
        if [ -s "${TEMP_DIR}/${name}.svg" ]; then
            cp -f "${TEMP_DIR}/${name}.svg" "$ICON_DIR/"
            downloaded=$((downloaded + 1))
        else
            rm -f "${TEMP_DIR}/${name}.svg"
            echo "  ⚠️  Empty response for ${name} icon"
        fi
    else
        echo "  ⚠️  Could not download ${name} icon"
    fi
done

# Report results
if [ "$downloaded" -eq 0 ]; then
    echo "  ⚠️  No icons downloaded, using system default icons"
    rmdir "$ICON_DIR" 2>/dev/null || true
else
    echo "✅ ${downloaded} icon(s) installed to: $ICON_DIR"
    for f in "$ICON_DIR"/*.svg; do
        [ -f "$f" ] && echo "   $(basename "$f") ($(du -h "$f" | cut -f1))"
    done
fi

echo ""
echo "Note: Icons are from the Papirus icon theme (high quality, consistent)."
echo "      If downloads failed, system default icons will be used instead."
