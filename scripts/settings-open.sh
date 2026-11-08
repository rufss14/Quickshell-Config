#!/usr/bin/env bash
# ── settings-open.sh ──────────────────────────────────────────────────────────
# Opens the shell's Settings. This is what the desktop entry's Exec points at.
#
# ── Why a wrapper instead of putting the ipc call straight in Exec ────────────
# `qs ipc` against a shell that isn't running exits non-zero and prints to stderr —
# and a launcher throws stderr away. So the plain form would produce a Settings
# entry that, whenever the shell was down, did NOTHING AT ALL with nothing on
# screen saying why. That is the same failure mode the rest of this config treats
# as a bug rather than an edge case (Discord.pressBlocker, WallpaperEngine.blocker):
# a control that can't work says so instead of silently no-oping.
#
# The path is derived from this script's own location, never a literal — this
# config is published and installs elsewhere. Same rule as the Python scripts.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# The page to open on, if one was named: `settings-open.sh NightLightPage.qml`.
PAGE="${1:-}"

fail() {
    # notify-send is optional. If it isn't here, stderr is all that's left — which
    # a launcher discards, but a terminal run still shows.
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Quickshell" -u critical "Settings unavailable" "$1"
    fi
    echo "settings-open: $1" >&2
    exit 1
}

command -v qs >/dev/null 2>&1 || fail "Quickshell (qs) is not installed or not on PATH."

if [ -n "$PAGE" ]; then
    qs ipc -p "$REPO_DIR" call settings page "$PAGE" 2>/dev/null && exit 0
else
    qs ipc -p "$REPO_DIR" call settings open 2>/dev/null && exit 0
fi

# Reaching here means the call itself failed. By far the likeliest cause is that
# no instance is running; say that rather than dumping an ipc error nobody can act on.
fail "The Quickshell desktop shell isn't running, so there is nothing to configure."
