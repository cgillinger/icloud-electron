#!/usr/bin/env bash
# Compatibility shim.
#
# The app used to be built on Electron and this script was the entry point,
# so desktop shortcuts and the /usr/local/bin symlink point here. It now
# forwards to the real launcher; see icloud-app.sh.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
exec "$SCRIPT_DIR/icloud-app.sh" "$@"
