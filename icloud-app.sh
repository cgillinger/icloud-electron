#!/usr/bin/env bash
# Opens an iCloud service in its own window.
#
# The window is a Chromium app-mode window: no tabs, no address bar, one
# service per window, session kept between launches. Because it is a complete
# browser rather than an embedded engine, everything works - including
# "Sign in with iPhone", which needs the WebAuthn code that lives in the
# browser layer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

CHROMIUM_DIR="${ICLOUD_APP_CHROMIUM_DIR:-$DATA_HOME/icloud-app/chromium}"
PROFILE="${ICLOUD_APP_PROFILE:-$CONFIG_HOME/icloud-app/profile}"

VALID_SERVICES="photos iclouddrive contacts notes mail calendar reminders pages numbers keynote fmf find"

usage() {
    echo "Usage: $(basename "$0") <service> <title>" >&2
    echo "Example: $(basename "$0") photos Photos" >&2
    echo "Valid services: $VALID_SERVICES" >&2
}

if [ $# -lt 2 ]; then
    usage
    exit 1
fi

SERVICE="$1"
TITLE="$2"

# Exact match on a whole token. A substring test would accept "photos mail",
# which passes validation but is not a service.
SERVICE_OK=0
for known in $VALID_SERVICES; do
    [ "$known" = "$SERVICE" ] && SERVICE_OK=1 && break
done
if [ "$SERVICE_OK" -ne 1 ]; then
    echo "Unknown service: \"$SERVICE\"" >&2
    usage
    exit 1
fi

# The bundled browser is the only supported one, so the app behaves the same
# everywhere. ICLOUD_APP_BROWSER exists as an escape hatch.
BROWSER="${ICLOUD_APP_BROWSER:-$CHROMIUM_DIR/chrome}"
if [ -n "${ICLOUD_APP_BROWSER:-}" ]; then
    # Say so out loud: this variable decides which binary receives the
    # Apple ID password.
    echo "icloud-app: using browser from ICLOUD_APP_BROWSER: $BROWSER" >&2
fi

# A browser update staged by an earlier launch is swapped in now, before the
# browser starts. Fast, local-only, and skipped while a window is still open -
# a running browser cannot have its files replaced underneath it.
GET_CHROMIUM="$SCRIPT_DIR/tools/get-chromium.sh"
if [ -z "${ICLOUD_APP_BROWSER:-}" ] && [ -x "$GET_CHROMIUM" ]; then
    "$GET_CHROMIUM" --apply-staged >/dev/null || true
fi

if [ ! -x "$BROWSER" ]; then
    cat >&2 <<EOF
The browser this app runs on is not installed yet.

Run this once:

    $SCRIPT_DIR/tools/get-chromium.sh

It downloads Chromium (about 230 MB) into
$CHROMIUM_DIR
EOF
    exit 1
fi

# Look for a newer browser at most once per ICLOUD_APP_UPDATE_INTERVAL
# seconds (default 24 h; 0 disables). The check runs in the background so it
# never delays the window: anything it finds is downloaded, verified and
# staged beside the install, then swapped in by a later launch. It never
# prompts and logs to stderr only.
UPDATE_INTERVAL="${ICLOUD_APP_UPDATE_INTERVAL:-86400}"
if [ -z "${ICLOUD_APP_BROWSER:-}" ] && [ -x "$GET_CHROMIUM" ] \
        && printf '%s' "$UPDATE_INTERVAL" | grep -Eq '^[0-9]+$' \
        && [ "$UPDATE_INTERVAL" -gt 0 ]; then
    STAMP="$(dirname "$CHROMIUM_DIR")/.update-check"
    [ -f "$STAMP" ] || STAMP="$(dirname "$CHROMIUM_DIR")/chromium-build.txt"
    LAST_CHECK="$(stat -c %Y "$STAMP" 2>/dev/null || echo 0)"
    if [ $(( $(date +%s) - LAST_CHECK )) -ge "$UPDATE_INTERVAL" ]; then
        ( "$GET_CHROMIUM" --stage >/dev/null & )
    fi
fi

# 0700: Chromium creates its own subdirectories this way, and the launcher
# should not weaken that with an inherited umask.
(umask 077; mkdir -p "$PROFILE")

# Seed the profile once so the browser's own password manager and autofill
# stay off. This app is for signing in to Apple, not for storing that password
# in a profile it created.
PREFS_DIR="$PROFILE/Default"
if [ ! -e "$PREFS_DIR/Preferences" ]; then
    (umask 077; mkdir -p "$PREFS_DIR")
    cat > "$PREFS_DIR/Preferences" <<'PREFS'
{"credentials_enable_service":false,"credentials_enable_autosignin":false,
 "autofill":{"credit_card_enabled":false,"profile_enabled":false},
 "browser":{"check_default_browser":false},
 "profile":{"password_manager_enabled":false}}
PREFS
fi

# Show what changed, once, after an update. Never blocks the app launch.
#
# The changelog gets its own throwaway profile on purpose. Sharing the main one
# would make Chromium's single-instance lock merge the two launches, which
# silently drops the second window's size - and the page is a local file that
# needs no cookies anyway.
if command -v node >/dev/null 2>&1 && [ -f "$SCRIPT_DIR/tools/show-changelog.js" ]; then
    CHANGELOG_PAGE="$(ICLOUD_APP_PROFILE="$PROFILE" ICLOUD_APP_ROOT="$SCRIPT_DIR" \
        node "$SCRIPT_DIR/tools/show-changelog.js" 2>/dev/null || true)"
    if [ -n "$CHANGELOG_PAGE" ] && [ -f "$CHANGELOG_PAGE" ]; then
        # Opened after the main window on purpose. The main window is started
        # last and maximised, so a changelog that appears first ends up buried
        # underneath it.
        (
            sleep "${ICLOUD_APP_CHANGELOG_DELAY:-3}"
            "$BROWSER" \
                --app="file://$CHANGELOG_PAGE" \
                --user-data-dir="$(dirname "$PROFILE")/changelog-profile" \
                --no-first-run --no-default-browser-check \
                --window-size="${ICLOUD_APP_CHANGELOG_SIZE:-560,660}" \
                --class="icloud-changelog" \
                >/dev/null 2>&1 &

            # Centre it once it appears. The size Chromium is given is in
            # scale-independent units, so the real pixel size is only known
            # after the window exists - hence measuring rather than computing.
            # Optional: without wmctrl the window simply opens where the window
            # manager puts it.
            if command -v wmctrl >/dev/null 2>&1; then
                for _ in $(seq 1 40); do
                    WIN_LINE="$(wmctrl -lGx 2>/dev/null | grep -F 'icloud-changelog' | head -1 || true)"
                    [ -n "$WIN_LINE" ] && break
                    sleep 0.25
                done
                if [ -n "${WIN_LINE:-}" ]; then
                    read -r AREA_X AREA_Y AREA_W AREA_H <<<"$(wmctrl -d | awk '
                        $2 == "*" { for (i = 1; i <= NF; i++) if ($i == "WA:") {
                            split($(i+1), o, ","); split($(i+2), s, "x");
                            print o[1], o[2], s[1], s[2]; exit } }')"
                    # wmctrl -lGx columns: id desktop x y width height class ...
                    WIN_ID="$(echo "$WIN_LINE" | awk '{print $1}')"
                    WIN_W="$(echo "$WIN_LINE" | awk '{print $5}')"
                    WIN_H="$(echo "$WIN_LINE" | awk '{print $6}')"
                    # Values come from another process; keep them out of
                    # arithmetic unless they really are plain integers.
                    if printf '%s\n' "${AREA_X:-}" "${AREA_Y:-}" "${AREA_W:-}" \
                           "${AREA_H:-}" "$WIN_W" "$WIN_H" \
                       | grep -Evq '^[0-9]+$'; then
                        WIN_W=""
                    fi
                    if [ -n "${AREA_W:-}" ] && [ -n "$WIN_W" ]; then
                        wmctrl -i -r "$WIN_ID" -e \
                            "0,$((AREA_X + (AREA_W - WIN_W) / 2)),$((AREA_Y + (AREA_H - WIN_H) / 2)),-1,-1" \
                            2>/dev/null || true
                    fi
                fi
            fi
        ) &
        disown 2>/dev/null || true
    fi
fi

# --class makes the desktop environment group the window under its own icon
# rather than lumping every service together.
#
# ICLOUD_APP_WINDOW: "maximized" (default), "fullscreen" for a borderless
# screen filling window, or an explicit "<width>,<height>".
case "${ICLOUD_APP_WINDOW:-maximized}" in
    maximized)  WINDOW_ARGS=(--start-maximized) ;;
    fullscreen) WINDOW_ARGS=(--start-fullscreen) ;;
    *)          WINDOW_ARGS=(--window-size="${ICLOUD_APP_WINDOW}") ;;
esac

exec "$BROWSER" \
    --app="https://www.icloud.com/$SERVICE" \
    --user-data-dir="$PROFILE" \
    --no-first-run \
    --no-default-browser-check \
    "${WINDOW_ARGS[@]}" \
    --class="icloud-$SERVICE" \
    --window-name="iCloud $TITLE" \
    >/dev/null 2>&1
