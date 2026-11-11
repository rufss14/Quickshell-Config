#!/usr/bin/env bash
# ── shell-run.sh ──────────────────────────────────────────────────────────────
# Starts the shell and starts it again if it crashes at launch. Hyprland's autostart
# and reload-quickshell.sh both run this, with the same environment (shell-env.sh).
#
# Quickshell restarts ITSELF after a crash (its crash handler re-execs the same pid),
# except when it crashed within 10 s of launching: then it gives up and exits 255 so it
# can't crash-loop. Those startup crashes are the ones that leave you with no bar, no
# notifications and no lock-before-sleep, so this is the part that handles them:
#
#   exit 255, or killed by SEGV/ABRT/BUS/FPE/ILL   a crash: start again
#   anything else (0, TERM, KILL, INT, HUP, 1)       meant: a reload, a logout, `qs kill`,
#                                                    a bad argument. Stop.
#
# Two crashes within CRASH_WINDOW seconds → the next start is SAFE MODE (QS_SAFE=1,
# read by services/SafeMode.qml: no native blob plugin, ambient effects resting). Two
# more in safe mode → stop, with a notification saying where the crash reports are.
#
#   scripts/shell-run.sh            what autostart.lua and ALT+Q run
#   QS_SAFE=1 scripts/shell-run.sh  start straight in safe mode
# ─────────────────────────────────────────────────────────────────────────────
set -u
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/shell-env.sh"

QS_BIN="${QS_BIN:-qs}"
CRASH_WINDOW="${QS_CRASH_WINDOW:-120}"
CRASHES_TO_SAFE=2
CRASH_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/crashes"

# Notifications go out once the shell is back (it IS the notification server), so a
# notify-send fired before it is up would wait on nobody. Backgrounded and bounded.
notify_later() {   # notify_later URGENCY TITLE BODY
    ( sleep 6; timeout 10 notify-send --app-name=Quickshell --urgency="$1" "$2" "$3" ) >/dev/null 2>&1 &
}

is_crash() {
    case "$1" in
        255|132|134|135|136|139) return 0 ;;
        *) return 1 ;;
    esac
}

crashes=()
export QS_SAFE="${QS_SAFE:-0}"
while :; do
    "$QS_BIN" -p "$REPO_DIR"
    rc=$?
    is_crash "$rc" || exit "$rc"

    now=$(date +%s)
    kept=()
    for t in "${crashes[@]}"; do (( now - t < CRASH_WINDOW )) && kept+=("$t"); done
    crashes=("${kept[@]}" "$now")
    echo "shell-run: the shell crashed (exit $rc), ${#crashes[@]} in ${CRASH_WINDOW}s, safe=$QS_SAFE" >&2

    if (( ${#crashes[@]} >= CRASHES_TO_SAFE )); then
        if [ "$QS_SAFE" = 1 ]; then
            # Nothing is running to show a notification now; the next login or a manual
            # start does. It is in the log either way.
            echo "shell-run: still crashing in safe mode; not restarting. Crash reports: $CRASH_DIR" >&2
            timeout 5 notify-send --app-name=Quickshell --urgency=critical "The shell keeps crashing" \
                "It crashed in safe mode too, so it was not restarted. Crash reports: $CRASH_DIR" 2>/dev/null
            exit 1
        fi
        QS_SAFE=1
        crashes=()
        notify_later critical "Safe mode" \
            "The shell crashed twice while starting, so it's running without the blob plugin and ambient effects. Reload (ALT+Q) to leave safe mode. Crash reports: $CRASH_DIR"
    else
        notify_later normal "The shell restarted" "It crashed while starting (exit $rc). Crash reports: $CRASH_DIR"
    fi
    sleep 1
done
