#!/usr/bin/env bash
# Installs and updates the browser the app runs on.
#
# The app ships its own browser rather than using whatever happens to be
# installed, so behaviour does not change from machine to machine. Where that
# browser comes from is a choice, made with ICLOUD_APP_BROWSER_SOURCE:
#
#   chrome             Google Chrome, stable channel, from Google's apt
#                      repository. Verified against a GPG key pinned in this
#                      repo, independent of TLS. Has Safe Browsing. Default.
#   cft                Chrome for Testing, stable channel. Verified against
#                      Google Cloud Storage object metadata - an integrity
#                      check only, from the same server as the file. Has Safe
#                      Browsing (Google API keys are baked in; verified
#                      2026-08-06 on 151.0.7922.76).
#   chromium-snapshot  Pure open-source Chromium, for anyone who wants no
#                      proprietary code. The honest trade-off: these are trunk
#                      snapshots, not stable releases - no Safe Browsing, no
#                      signatures, no is_official_build mitigations (CFI, PGO).
#
# The choice is sticky: once installed, updates keep following the same source
# unless ICLOUD_APP_BROWSER_SOURCE says otherwise. Installs made by version
# 2.0.0 (which recorded no source) migrate to the default on their next update.
#
# Modes:
#   (none)          install if nothing is installed yet
#   --force         install the current available build, replacing what is there
#   --check         report installed versus available and exit
#   --stage         if a newer build is available, download and verify it next
#                   to the install; the launcher swaps it in on the next start
#   --apply-staged  swap a staged build into place, unless the browser is running
#
# This is the same trade-off `npm install` already made for Electron - a
# browser is downloaded once at install time - except this build includes the
# browser layer, which is what makes "Sign in with iPhone" work.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
INSTALL_DIR="${ICLOUD_APP_CHROMIUM_DIR:-$DATA_HOME/icloud-app/chromium}"
STATE_DIR="$(dirname "$INSTALL_DIR")"
BUILD_INFO="$STATE_DIR/chromium-build.txt"
STAGE_DIR="$INSTALL_DIR.staged"
STAGE_INFO="$STATE_DIR/chromium-build.txt.staged"
CHECK_STAMP="$STATE_DIR/.update-check"
LOCK_DIR="$STATE_DIR/.update-lock"

# Google's Linux package signing key, pinned in the repo so verification does
# not depend on Chrome already being installed - and so that a key swapped on
# the system cannot silently change what this script accepts.
#
#   Fingerprint: EB4C 1BFD 4F04 2F6D DDCC  EC91 7721 F63B D38B 4796
#   Refresh:     curl -fsS https://dl.google.com/linux/linux_signing_key.pub \
#                    | gpg --dearmor > tools/google-linux-signing-key.gpg
PINNED_KEYRING="$SCRIPT_DIR/google-linux-signing-key.gpg"
SYSTEM_KEYRING="/usr/share/keyrings/google-chrome.gpg"

CHROME_REPO="https://dl.google.com/linux/chrome/deb"
CFT_VERSIONS_URL="https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json"
CFT_METADATA_BASE="https://storage.googleapis.com/storage/v1/b/chrome-for-testing-public/o"
SNAPSHOT_BASE="https://storage.googleapis.com/chromium-browser-snapshots/Linux_x64"

usage() {
    # The header comment above, minus the shebang and the '# ' prefixes.
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

MODE=install
case "${1:-}" in
    "")             ;;
    --force)        MODE=force ;;
    --check)        MODE=check ;;
    --stage)        MODE=stage ;;
    --apply-staged) MODE=apply ;;
    -h|--help)      usage; exit 0 ;;
    *)              echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
esac

need() {
    command -v "$1" >/dev/null 2>&1 || { echo "Missing required tool: $1" >&2; exit 1; }
}

# Read one key from a key=value file; empty if absent.
info_get() {
    { [ -f "$1" ] && sed -n "s/^$2=//p" "$1" | head -1; } || true
}

INSTALLED_SOURCE="$(info_get "$BUILD_INFO" source)"
INSTALLED_VERSION="$(info_get "$BUILD_INFO" version)"
# 2.0.0 wrote only revision= and sha256=.
[ -z "$INSTALLED_VERSION" ] && INSTALLED_VERSION="$(info_get "$BUILD_INFO" revision)"

SOURCE="${ICLOUD_APP_BROWSER_SOURCE:-${INSTALLED_SOURCE:-chrome}}"
case "$SOURCE" in
    chrome|cft|chromium-snapshot) ;;
    *)  echo "Invalid ICLOUD_APP_BROWSER_SOURCE: $SOURCE" >&2
        echo "Valid values: chrome, cft, chromium-snapshot" >&2
        exit 1 ;;
esac

# ---------------------------------------------------------------------------
# --apply-staged: called by the launcher before it starts the browser. Needs
# no network and must be fast; everything below it does resolve-and-download.
# ---------------------------------------------------------------------------
if [ "$MODE" = apply ]; then
    [ -x "$STAGE_DIR/chrome" ] || exit 0

    # A running browser cannot have its files replaced underneath it.
    if command -v pgrep >/dev/null 2>&1 && pgrep -f "$INSTALL_DIR/" >/dev/null 2>&1; then
        echo "icloud-app: a browser update is staged, but the browser is running; it will be applied on a later launch" >&2
        exit 0
    fi

    # On systems that restrict unprivileged user namespaces, the sandbox
    # helper must be setuid root - a bit the swap cannot set without root. Do
    # not swap a working browser for one that will refuse to start.
    RESTRICT="$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)"
    if [ "$RESTRICT" = "1" ]; then
        for helper in chrome-sandbox chrome_sandbox; do
            if [ -f "$STAGE_DIR/$helper" ] && [ ! -u "$STAGE_DIR/$helper" ]; then
                cat >&2 <<EOF
icloud-app: a browser update is staged, but this system restricts unprivileged
user namespaces, so its sandbox helper must be made setuid root first:

    sudo chown root:root "$STAGE_DIR/$helper"
    sudo chmod 4755 "$STAGE_DIR/$helper"

The update will be applied on the next launch after that.
EOF
                exit 0
            fi
        done
    fi

    STAGED_VERSION="$(info_get "$STAGE_INFO" version)"
    STAGED_SOURCE="$(info_get "$STAGE_INFO" source)"

    rm -rf "$INSTALL_DIR.old"
    if [ -d "$INSTALL_DIR" ]; then
        mv "$INSTALL_DIR" "$INSTALL_DIR.old"
    fi
    if ! mv "$STAGE_DIR" "$INSTALL_DIR"; then
        [ -d "$INSTALL_DIR.old" ] && mv "$INSTALL_DIR.old" "$INSTALL_DIR"
        echo "icloud-app: applying the staged browser update failed; keeping the current browser" >&2
        exit 1
    fi
    [ -f "$STAGE_INFO" ] && mv "$STAGE_INFO" "$BUILD_INFO"
    rm -rf "$INSTALL_DIR.old"
    echo "icloud-app: browser updated to ${STAGED_VERSION:-unknown} (source: ${STAGED_SOURCE:-unknown})" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Everything else talks to the network.
# ---------------------------------------------------------------------------
need curl
if [ "$(uname -m)" != x86_64 ]; then
    echo "Only x86_64 is supported; this machine is $(uname -m)." >&2
    exit 1
fi

fetch() {
    curl -fsS --proto '=https' --proto-redir '=https' "$@"
}
fetch_big() {
    if [ "$MODE" = stage ]; then
        curl -fsSL --proto '=https' --proto-redir '=https' "$@"
    else
        curl -fL --proto '=https' --proto-redir '=https' --progress-bar "$@"
    fi
}

mkdir -p "$STATE_DIR"
# Staging and swapping must stay on the same filesystem as the install, or
# the final mv stops being atomic. Hence not mktemp's default /tmp.
TMP_DIR="$(mktemp -d "$STATE_DIR/.download.XXXXXXXX")"
HAVE_LOCK=0
cleanup() {
    rm -rf "$TMP_DIR"
    [ "$HAVE_LOCK" = 1 ] && rmdir "$LOCK_DIR" 2>/dev/null
    true
}
trap cleanup EXIT

# Each resolver sets AVAILABLE_VERSION plus what its fetcher needs. Each
# fetcher downloads, VERIFIES, unpacks, and sets NEW_BUILD (a directory whose
# ./chrome is the browser) and ARTIFACT_SHA256 (digest of what was downloaded).

resolve_chrome() {
    need gpgv
    KEYRING="$PINNED_KEYRING"
    if [ ! -f "$KEYRING" ]; then
        KEYRING="$SYSTEM_KEYRING"
        echo "Warning: pinned key missing from the repo; falling back to $KEYRING" >&2
    fi
    [ -f "$KEYRING" ] || { echo "No GPG keyring found to verify Google's repository." >&2; exit 1; }

    fetch -o "$TMP_DIR/Release"     "$CHROME_REPO/dists/stable/Release"
    fetch -o "$TMP_DIR/Release.gpg" "$CHROME_REPO/dists/stable/Release.gpg"
    if ! gpgv --keyring "$KEYRING" "$TMP_DIR/Release.gpg" "$TMP_DIR/Release" >/dev/null 2>"$TMP_DIR/gpgv.err"; then
        cat "$TMP_DIR/gpgv.err" >&2
        echo "GPG signature verification of Google's repository FAILED. Not installing." >&2
        exit 1
    fi

    # The chain: Release.gpg signs Release; Release carries the hash of
    # Packages; Packages carries the hash of the .deb.
    PACKAGES_SHA="$(awk '/^SHA256:/{s=1;next} /^[^ ]/{s=0}
        s && $3=="main/binary-amd64/Packages" {print $1; exit}' "$TMP_DIR/Release")"
    [ -n "$PACKAGES_SHA" ] || { echo "Could not find the Packages hash in the Release file." >&2; exit 1; }

    fetch -o "$TMP_DIR/Packages" "$CHROME_REPO/dists/stable/main/binary-amd64/Packages"
    echo "$PACKAGES_SHA  $TMP_DIR/Packages" | sha256sum --check --status \
        || { echo "Packages file does not match the hash signed in Release." >&2; exit 1; }

    STANZA="$(awk -v RS= '/(^|\n)Package: google-chrome-stable(\n|$)/{print; exit}' "$TMP_DIR/Packages")"
    AVAILABLE_VERSION="$(printf '%s\n' "$STANZA" | sed -n 's/^Version: //p')"
    CHROME_DEB_PATH="$(printf '%s\n' "$STANZA" | sed -n 's/^Filename: //p')"
    CHROME_DEB_SHA256="$(printf '%s\n' "$STANZA" | sed -n 's/^SHA256: //p')"
    if [ -z "$AVAILABLE_VERSION" ] || [ -z "$CHROME_DEB_PATH" ] || [ -z "$CHROME_DEB_SHA256" ]; then
        echo "Could not parse google-chrome-stable out of the Packages file." >&2
        exit 1
    fi
}

fetch_chrome() {
    [ "$MODE" = stage ] || echo "Downloading Google Chrome $AVAILABLE_VERSION (about 140 MB)..."
    fetch_big -o "$TMP_DIR/chrome.deb" "$CHROME_REPO/$CHROME_DEB_PATH"
    echo "$CHROME_DEB_SHA256  $TMP_DIR/chrome.deb" | sha256sum --check --status \
        || { echo "Downloaded .deb does not match the signed SHA-256. Not installing." >&2; exit 1; }
    ARTIFACT_SHA256="$CHROME_DEB_SHA256"

    mkdir "$TMP_DIR/deb"
    if command -v dpkg-deb >/dev/null 2>&1; then
        dpkg-deb -x "$TMP_DIR/chrome.deb" "$TMP_DIR/deb"
    else
        # Non-Debian systems: a .deb is an ar archive holding data.tar.*.
        need ar; need tar
        (cd "$TMP_DIR/deb" && ar x "$TMP_DIR/chrome.deb")
        DATA_TAR="$(find "$TMP_DIR/deb" -maxdepth 1 -name 'data.tar.*' | head -1)"
        [ -n "$DATA_TAR" ] || { echo "No data.tar.* inside the .deb - not a Debian package?" >&2; exit 1; }
        if ! tar -xf "$DATA_TAR" -C "$TMP_DIR/deb"; then
            echo "Could not unpack ${DATA_TAR##*/}. If it is .zst, install zstd (or dpkg)." >&2
            exit 1
        fi
        rm -f "$TMP_DIR/deb"/data.tar.* "$TMP_DIR/deb"/control.tar.* "$TMP_DIR/deb/debian-binary"
    fi
    NEW_BUILD="$TMP_DIR/deb/opt/google/chrome"
}

resolve_cft() {
    need python3
    fetch -o "$TMP_DIR/cft.json" "$CFT_VERSIONS_URL"
    { read -r AVAILABLE_VERSION; read -r CFT_URL; } < <(python3 - "$TMP_DIR/cft.json" <<'PY'
import json, sys
stable = json.load(open(sys.argv[1]))["channels"]["Stable"]
url = [d["url"] for d in stable["downloads"]["chrome"] if d["platform"] == "linux64"][0]
print(stable["version"])
print(url)
PY
)
    [ -n "$AVAILABLE_VERSION" ] && [ -n "$CFT_URL" ] \
        || { echo "Could not read the Chrome for Testing version feed." >&2; exit 1; }

    # The download feed has no checksums; GCS object metadata does. Same
    # server as the file, so this is an integrity check, not authentication.
    fetch -o "$TMP_DIR/cft-meta.json" "$CFT_METADATA_BASE/${AVAILABLE_VERSION}%2Flinux64%2Fchrome-linux64.zip"
    { read -r CFT_SIZE; read -r CFT_MD5_B64; } < <(python3 - "$TMP_DIR/cft-meta.json" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
print(meta["size"])
print(meta["md5Hash"])
PY
)
    [ -n "$CFT_SIZE" ] && [ -n "$CFT_MD5_B64" ] \
        || { echo "Could not read GCS object metadata for the download." >&2; exit 1; }
}

fetch_cft() {
    need unzip
    [ "$MODE" = stage ] || echo "Downloading Chrome for Testing $AVAILABLE_VERSION (about 190 MB)..."
    fetch_big -o "$TMP_DIR/cft.zip" "$CFT_URL"

    GOT_SIZE="$(stat -c %s "$TMP_DIR/cft.zip")"
    GOT_MD5="$(md5sum "$TMP_DIR/cft.zip" | cut -d' ' -f1)"
    WANT_MD5="$(printf '%s' "$CFT_MD5_B64" | base64 -d | od -An -vtx1 | tr -d ' \n')"
    if [ "$GOT_SIZE" != "$CFT_SIZE" ] || [ "$GOT_MD5" != "$WANT_MD5" ]; then
        echo "Downloaded archive does not match the published size/MD5. Not installing." >&2
        echo "  size: got $GOT_SIZE, want $CFT_SIZE" >&2
        echo "  md5:  got $GOT_MD5, want $WANT_MD5" >&2
        exit 1
    fi
    ARTIFACT_SHA256="$(sha256sum "$TMP_DIR/cft.zip" | cut -d' ' -f1)"

    unzip -q "$TMP_DIR/cft.zip" -d "$TMP_DIR"
    NEW_BUILD="$TMP_DIR/chrome-linux64"
}

resolve_snapshot() {
    if [ -n "${ICLOUD_APP_CHROMIUM_REVISION:-}" ]; then
        AVAILABLE_VERSION="$ICLOUD_APP_CHROMIUM_REVISION"
    else
        AVAILABLE_VERSION="$(fetch "$SNAPSHOT_BASE/LAST_CHANGE")"
    fi
    # The revision is interpolated into a URL path. Without this check, a
    # value like "../../some-bucket/x" would silently redirect the download.
    if ! printf '%s' "$AVAILABLE_VERSION" | grep -Eq '^[0-9]+$'; then
        echo "Invalid Chromium revision: $AVAILABLE_VERSION (digits only)" >&2
        exit 1
    fi
}

fetch_snapshot() {
    need unzip
    [ "$MODE" = stage ] || echo "Downloading Chromium r$AVAILABLE_VERSION (about 230 MB)..."
    if ! fetch_big -o "$TMP_DIR/chrome-linux.zip" "$SNAPSHOT_BASE/$AVAILABLE_VERSION/chrome-linux.zip"; then
        echo >&2
        echo "Revision $AVAILABLE_VERSION is no longer available." >&2
        echo "Snapshots are eventually pruned; retry without ICLOUD_APP_CHROMIUM_REVISION set." >&2
        exit 1
    fi
    # The snapshot archive publishes no signatures or checksums at all, so
    # there is nothing to verify against; this digest is a record, not proof.
    ARTIFACT_SHA256="$(sha256sum "$TMP_DIR/chrome-linux.zip" | cut -d' ' -f1)"
    unzip -q "$TMP_DIR/chrome-linux.zip" -d "$TMP_DIR"
    NEW_BUILD="$TMP_DIR/chrome-linux"
}

resolve_build() {
    case "$SOURCE" in
        chrome)            resolve_chrome ;;
        cft)               resolve_cft ;;
        chromium-snapshot) resolve_snapshot ;;
    esac
}

fetch_build() {
    case "$SOURCE" in
        chrome)            fetch_chrome ;;
        cft)               fetch_cft ;;
        chromium-snapshot) fetch_snapshot ;;
    esac
    if [ ! -x "$NEW_BUILD/chrome" ]; then
        echo "Downloaded archive does not contain a browser build." >&2
        exit 1
    fi
}

source_label() {
    case "$1" in
        chrome)            echo "Google Chrome stable, GPG-verified apt repository" ;;
        cft)               echo "Chrome for Testing stable, integrity-checked" ;;
        chromium-snapshot) echo "pure Chromium trunk snapshot, unverified" ;;
        *)                 echo "unknown" ;;
    esac
}

write_info() {
    printf 'source=%s\nversion=%s\nsha256=%s\ndate=%s\n' \
        "$SOURCE" "$AVAILABLE_VERSION" "$ARTIFACT_SHA256" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$1"
}

# ---------------------------------------------------------------------------
# --check
# ---------------------------------------------------------------------------
if [ "$MODE" = check ]; then
    resolve_build
    echo "Source:    $SOURCE ($(source_label "$SOURCE"))"
    if [ -x "$INSTALL_DIR/chrome" ]; then
        echo "Installed: ${INSTALLED_VERSION:-unknown} (source: ${INSTALLED_SOURCE:-unrecorded, pre-2.1 install})"
    else
        echo "Installed: nothing"
    fi
    echo "Available: $AVAILABLE_VERSION"
    STAGED_VERSION="$(info_get "$STAGE_INFO" version)"
    [ -n "$STAGED_VERSION" ] && [ -x "$STAGE_DIR/chrome" ] \
        && echo "Staged:    $STAGED_VERSION (will be applied on the next launch)"
    if [ "$AVAILABLE_VERSION" = "$INSTALLED_VERSION" ] && [ "$SOURCE" = "${INSTALLED_SOURCE:-}" ]; then
        echo "Up to date."
    elif [ -x "$INSTALL_DIR/chrome" ]; then
        echo "Update available. It installs itself on launch, or run: $0 --force"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# --stage: run in the background by the launcher. Never prompts, never touches
# the running install; stderr only.
# ---------------------------------------------------------------------------
if [ "$MODE" = stage ]; then
    # Nothing installed means the launcher already told the user what to run.
    [ -x "$INSTALL_DIR/chrome" ] || exit 0

    # One update at a time. A lock left by a crash goes stale after an hour.
    if ! mkdir "$LOCK_DIR" 2>/dev/null; then
        LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK_DIR" 2>/dev/null || date +%s) ))
        [ "$LOCK_AGE" -gt 3600 ] || exit 0
        rmdir "$LOCK_DIR" 2>/dev/null || true
        mkdir "$LOCK_DIR" 2>/dev/null || exit 0
    fi
    HAVE_LOCK=1

    resolve_build
    touch "$CHECK_STAMP"

    if [ "$AVAILABLE_VERSION" = "$INSTALLED_VERSION" ] && [ "$SOURCE" = "${INSTALLED_SOURCE:-}" ]; then
        # Up to date; drop any staged build that has become pointless.
        rm -rf "$STAGE_DIR"; rm -f "$STAGE_INFO"
        exit 0
    fi
    if [ "$(info_get "$STAGE_INFO" version)" = "$AVAILABLE_VERSION" ] \
        && [ "$(info_get "$STAGE_INFO" source)" = "$SOURCE" ] \
        && [ -x "$STAGE_DIR/chrome" ]; then
        exit 0  # already staged, waiting for the next launch
    fi

    fetch_build
    rm -rf "$STAGE_DIR"
    mv "$NEW_BUILD" "$STAGE_DIR"
    write_info "$STAGE_INFO"
    echo "icloud-app: browser update $AVAILABLE_VERSION downloaded and verified; it will be applied on the next launch" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# install / --force
# ---------------------------------------------------------------------------
if [ -x "$INSTALL_DIR/chrome" ] && [ "$MODE" = install ]; then
    echo "A browser is already installed: $INSTALL_DIR/chrome"
    "$INSTALL_DIR/chrome" --version 2>/dev/null
    echo "Version:   ${INSTALLED_VERSION:-unknown} (source: ${INSTALLED_SOURCE:-unrecorded})"
    echo "Re-run with --force to reinstall the current available build,"
    echo "or with --check to see whether one is newer. Updates otherwise"
    echo "install themselves when you use the app."
    exit 0
fi

resolve_build
echo "Source: $SOURCE ($(source_label "$SOURCE"))"
fetch_build

# Refuse to touch a directory that is not ours. Without this, a typo in
# ICLOUD_APP_CHROMIUM_DIR would move and then delete whatever it points at.
if [ -e "$INSTALL_DIR" ] && [ ! -x "$INSTALL_DIR/chrome" ]; then
    echo "Refusing to replace $INSTALL_DIR: it exists but holds no browser build." >&2
    echo "Move it aside yourself, or set ICLOUD_APP_CHROMIUM_DIR elsewhere." >&2
    exit 1
fi

PREVIOUS=""
if [ -d "$INSTALL_DIR" ]; then
    PREVIOUS="$INSTALL_DIR.previous"
    rm -rf "$PREVIOUS"
    mv "$INSTALL_DIR" "$PREVIOUS"
fi
mv "$NEW_BUILD" "$INSTALL_DIR"

if [ ! -x "$INSTALL_DIR/chrome" ]; then
    echo "Install failed: no executable at $INSTALL_DIR/chrome" >&2
    [ -n "$PREVIOUS" ] && mv "$PREVIOUS" "$INSTALL_DIR"
    exit 1
fi
[ -n "$PREVIOUS" ] && rm -rf "$PREVIOUS"

# A build staged before this install is stale now, whatever it was.
rm -rf "$STAGE_DIR"; rm -f "$STAGE_INFO"
write_info "$BUILD_INFO"
touch "$CHECK_STAMP"

echo
echo "Installed: $("$INSTALL_DIR/chrome" --version 2>/dev/null | head -1)"
echo "Version:   $AVAILABLE_VERSION"
echo "SHA-256:   $ARTIFACT_SHA256"
echo "Location:  $INSTALL_DIR"
