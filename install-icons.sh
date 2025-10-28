#!/bin/bash
# install-icons.sh - Download and install iCloud icons

set -e

ICON_DIR="$HOME/.local/share/icons/icloud"
TEMP_DIR="/tmp/icloud-icons-$$"

echo "📥 Installing iCloud icons..."

# Create directories
mkdir -p "$ICON_DIR"
mkdir -p "$TEMP_DIR"

cd "$TEMP_DIR"

# Use Papirus icon theme - high quality, consistent style
echo "  Downloading icon set..."

# Photos - photo manager icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/multimedia-photo-manager.svg" -o photos.svg 2>/dev/null || \
echo "  ⚠️  Could not download Photos icon"

# Drive - cloud folder icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/folder-cloud.svg" -o drive.svg 2>/dev/null || \
echo "  ⚠️  Could not download Drive icon"

# Contacts - address book icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/preferences-contact-list.svg" -o contacts.svg 2>/dev/null || \
echo "  ⚠️  Could not download Contacts icon"

# Notes - notes/memo icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/accessories-notes.svg" -o notes.svg 2>/dev/null || \
echo "  ⚠️  Could not download Notes icon"

# Mail - mail icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/internet-mail.svg" -o mail.svg 2>/dev/null || \
echo "  ⚠️  Could not download Mail icon"

# Calendar - calendar icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/office-calendar.svg" -o calendar.svg 2>/dev/null || \
echo "  ⚠️  Could not download Calendar icon"

# Reminders - task/todo icon
curl -sL "https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-icon-theme/master/Papirus/64x64/apps/stock_todo.svg" -o reminders.svg 2>/dev/null || \
echo "  ⚠️  Could not download Reminders icon"

# Copy icons to icon directory
cp -f *.svg "$ICON_DIR/" 2>/dev/null || true

# Remove empty files (0 bytes)
find "$ICON_DIR" -type f -size 0 -delete 2>/dev/null || true

# Cleanup
cd ~
rm -rf "$TEMP_DIR"

# Check if we got any icons
if [ -z "$(ls -A $ICON_DIR 2>/dev/null)" ]; then
    echo "  ⚠️  No icons downloaded, using system default icons"
    rmdir "$ICON_DIR" 2>/dev/null || true
else
    echo "✅ Icons installed to: $ICON_DIR"
    ls -lh "$ICON_DIR" | grep -v "^total" | awk '{print "   " $9 " (" $5 ")"}'
fi

echo ""
echo "Note: Icons are from the Papirus icon theme (high quality, consistent)."
echo "      If downloads failed, system default icons will be used instead."
