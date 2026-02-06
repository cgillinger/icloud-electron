#!/bin/bash
# icloud-electron.sh - Launcher script for iCloud Electron
# Symlink this to /usr/local/bin/icloud-electron for system-wide access

# Resolve the script's actual location (follows symlinks)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

if [ ! -f "$SCRIPT_DIR/main.js" ]; then
    echo "Error: main.js not found in $SCRIPT_DIR" >&2
    echo "Make sure this script is in the icloud-electron directory or symlinked to it." >&2
    exit 1
fi

if [ $# -lt 2 ]; then
    echo "Usage: icloud-electron <service> <title>" >&2
    echo "Example: icloud-electron photos Photos" >&2
    exit 1
fi

npx --prefix "$SCRIPT_DIR" electron "$SCRIPT_DIR" "$@"
