#!/usr/bin/env bash
# Downloads the Chromium build the app runs on.
#
# The app ships its own browser rather than using whatever happens to be
# installed, so behaviour does not change from machine to machine. Chromium is
# BSD-licensed and may be redistributed; Google Chrome may not.
#
# This is the same trade-off `npm install` already made for Electron - a
# browser engine is downloaded once at install time - except this build
# includes the browser layer, which is what makes "Sign in with iPhone" work.
set -euo pipefail

# The revision installed on a first run. Updating deliberately does NOT reuse
# it: a pinned build never receives security patches, so `--force` fetches
# whatever is current unless a revision is named explicitly.
DEFAULT_REVISION=1674924

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="${ICLOUD_APP_CHROMIUM_DIR:-$DATA_HOME/icloud-app/chromium}"
BASE_URL="https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64"

for tool in curl unzip; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Missing required tool: $tool" >&2; exit 1; }
done

if [ -x "$INSTALL_DIR/chrome" ] && [ "${1:-}" != "--force" ]; then
    echo "Chromium is already installed: $INSTALL_DIR/chrome"
    "$INSTALL_DIR/chrome" --version
    echo "Re-run with --force to update to the current build."
    exit 0
fi

if [ -n "${ICLOUD_APP_CHROMIUM_REVISION:-}" ]; then
    CHROMIUM_REVISION="$ICLOUD_APP_CHROMIUM_REVISION"
elif [ "${1:-}" = "--force" ]; then
    # Updating means updating. Fall back to the pinned build only if the
    # archive cannot be reached.
    echo "Looking up the current Chromium build..."
    CHROMIUM_REVISION="$(curl -fsS --proto '=https' --proto-redir '=https' \
        "$BASE_URL/LAST_CHANGE" 2>/dev/null || echo "$DEFAULT_REVISION")"
else
    CHROMIUM_REVISION="$DEFAULT_REVISION"
fi

# The revision is interpolated into a URL path. Without this check, a value
# like "../../some-bucket/x" would silently redirect the download to an
# attacker's Google Cloud Storage bucket.
if ! printf '%s' "$CHROMIUM_REVISION" | grep -Eq '^[0-9]+$'; then
    echo "Invalid Chromium revision: $CHROMIUM_REVISION (digits only)" >&2
    exit 1
fi

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT

echo "Downloading Chromium r$CHROMIUM_REVISION (about 230 MB)..."
if ! curl -fL --proto '=https' --proto-redir '=https' --progress-bar \
        -o "$TMP_DIR/chrome-linux.zip" \
        "$BASE_URL/$CHROMIUM_REVISION/chrome-linux.zip"; then
    echo >&2
    echo "Revision $CHROMIUM_REVISION is no longer available." >&2
    echo "Snapshots are eventually pruned. Retry with the current build:" >&2
    echo >&2
    echo "    ICLOUD_APP_CHROMIUM_REVISION=\$(curl -s $BASE_URL/LAST_CHANGE) $0" >&2
    exit 1
fi

DIGEST="$(sha256sum "$TMP_DIR/chrome-linux.zip" | cut -d' ' -f1)"

echo "Unpacking..."
unzip -q "$TMP_DIR/chrome-linux.zip" -d "$TMP_DIR"

if [ ! -x "$TMP_DIR/chrome-linux/chrome" ]; then
    echo "Downloaded archive does not contain a Chromium build." >&2
    exit 1
fi

# Refuse to touch a directory that is not ours. Without this, a typo in
# ICLOUD_APP_CHROMIUM_DIR would move and then delete whatever it points at.
if [ -e "$INSTALL_DIR" ] && [ ! -x "$INSTALL_DIR/chrome" ]; then
    echo "Refusing to replace $INSTALL_DIR: it exists but holds no Chromium build." >&2
    echo "Move it aside yourself, or set ICLOUD_APP_CHROMIUM_DIR elsewhere." >&2
    exit 1
fi

mkdir -p "$(dirname "$INSTALL_DIR")"
PREVIOUS=""
if [ -d "$INSTALL_DIR" ]; then
    PREVIOUS="$INSTALL_DIR.previous"
    rm -rf "$PREVIOUS"
    mv "$INSTALL_DIR" "$PREVIOUS"
fi
mv "$TMP_DIR/chrome-linux" "$INSTALL_DIR"

if [ ! -x "$INSTALL_DIR/chrome" ]; then
    echo "Install failed: no executable at $INSTALL_DIR/chrome" >&2
    [ -n "$PREVIOUS" ] && mv "$PREVIOUS" "$INSTALL_DIR"
    exit 1
fi
[ -n "$PREVIOUS" ] && rm -rf "$PREVIOUS"

# Recorded so a later download can be compared against what is running. The
# snapshot archive publishes no signatures, so this is a change log, not proof
# of authenticity.
printf 'revision=%s\nsha256=%s\n' "$CHROMIUM_REVISION" "$DIGEST" \
    > "$(dirname "$INSTALL_DIR")/chromium-build.txt"

echo
echo "Installed: $("$INSTALL_DIR/chrome" --version)"
echo "Revision:  $CHROMIUM_REVISION"
echo "SHA-256:   $DIGEST"
echo "Location:  $INSTALL_DIR"
