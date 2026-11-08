#!/usr/bin/env bash
# ── material-fallback.sh ──────────────────────────────────────────────────────
# Keeps a still of the Material Wallpaper on screen while the shell is NOT running (services/
# MaterialFallback drives it). The shell draws the live one itself; this is what is under it,
# held by awww — a daemon of its own that outlives the shell.
#
#     material-fallback.sh set OUTPUT PNG    show PNG on the monitor OUTPUT, starting the daemon if need be
#     material-fallback.sh clear             let it go — only a daemon THIS script started
#
# `set` prints "started" when it had to start the daemon: that daemon's surface sits ABOVE a shell
# window that mapped before it (same layer, mapped later), so the shell remaps its own.
# Exit: 0 done · 1 awww refused · 2 no such file · 3 awww is not installed.
#
#     bash scripts/test-material-fallback.sh
# ─────────────────────────────────────────────────────────────────────────────
set -u

STATE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-quicktest/material"
MARK="$STATE/daemon-started-by-shell"
have() { command -v "$1" >/dev/null 2>&1; }

case "${1:-}" in
    set)
        out="${2:-}"; png="${3:-}"
        have awww && have awww-daemon || { echo "awww is not installed"; exit 3; }
        [[ -n "$out" && -f "$png" ]] || { echo "no such file: $png"; exit 2; }
        started=0
        if ! awww query >/dev/null 2>&1; then
            mkdir -p "$STATE"
            # Its own session: it must not die with the shell's process group.
            setsid -f awww-daemon >/dev/null 2>&1
            : > "$MARK"
            started=1
            for _ in $(seq 40); do awww query >/dev/null 2>&1 && break; sleep 0.1; done
        fi
        # No transition: it is replacing a still with the same still, re-tinted.
        awww img "$png" --outputs "$out" --transition-type none >/dev/null 2>&1 || exit 1
        (( started )) && echo started
        exit 0
        ;;
    clear)
        # A daemon the user runs for themselves is none of ours to kill.
        if [[ -f "$MARK" ]]; then
            awww kill >/dev/null 2>&1 || pkill -x awww-daemon >/dev/null 2>&1
            rm -f "$MARK"
        fi
        exit 0
        ;;
    *)
        echo "usage: $0 set OUTPUT PNG | clear" >&2
        exit 64
        ;;
esac
