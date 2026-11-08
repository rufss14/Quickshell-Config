#!/usr/bin/env bash
# ── lyrics-open.sh ─────────────────────────────────────────────────────────────
# Opens the shell's standalone Lyrics window. This is what the desktop entry's
# Exec points at — see settings-open.sh, which this mirrors exactly and for the
# same reason: a launcher throws away a failed Exec's stderr, so a plain
# `qs ipc call` here would make the Lyrics entry do NOTHING AT ALL, with nothing
# on screen saying why, whenever the shell isn't running.
#
# The path is derived from this script's own location, never a literal — this
# config is published and installs elsewhere.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

fail() {
    if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Quickshell" -u critical "Lyrics unavailable" "$1"
    fi
    echo "lyrics-open: $1" >&2
    exit 1
}

command -v qs >/dev/null 2>&1 || fail "Quickshell (qs) is not installed or not on PATH."

qs ipc -p "$REPO_DIR" call lyricswindow open 2>/dev/null && exit 0

fail "The Quickshell desktop shell isn't running, so there is nothing to open."
