#!/bin/bash
# install-icons.sh - Install the bundled iCloud icons
#
# The icons ship with the repository (see icons/README.md for origin and
# license), so installing them is a local copy - no network involved.

set -e

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/icons"
ICON_DIR="$HOME/.local/share/icons/icloud"

echo "📥 Installing iCloud icons..."

if [ ! -d "$SOURCE_DIR" ]; then
    echo "  ⚠️  Bundled icons not found in $SOURCE_DIR" >&2
    exit 1
fi

mkdir -p "$ICON_DIR"

installed=0
for src in "$SOURCE_DIR"/*.svg; do
    [ -f "$src" ] || continue
    cp -f "$src" "$ICON_DIR/"
    installed=$((installed + 1))
done

# Earlier versions installed the reminders icon under a misspelled name.
# The shortcut generator now uses the correct one, so drop the stray file.
rm -f "$ICON_DIR/remainders.svg"

echo "✅ ${installed} icon(s) installed to: $ICON_DIR"
for f in "$ICON_DIR"/*.svg; do
    [ -f "$f" ] && echo "   $(basename "$f") ($(du -h "$f" | cut -f1))"
done

echo ""
echo "Note: Icons are from the WhiteSur icon theme (GPL-3.0); see icons/README.md."
