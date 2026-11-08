#!/usr/bin/env bash
# ── bisect-idle.sh ────────────────────────────────────────────────────────────
# Which helper process is keeping the shell's GUI thread busy? Freezes one at a time
# (SIGSTOP, ~4s each) and prints the main thread's CPU before, during and after.
#
#     bash scripts/bisect-idle.sh
#
# What you will SEE: the Wallpaper Engine scene stops moving for a few seconds, then the
# audio visualiser does. Nothing is killed; every process is continued again on exit,
# including on Ctrl-C or a closed terminal. No root needed (same user).
#
# Reading it: if the main thread drops a lot while X is frozen, X's output is what the
# shell is spending its time handling. If nothing moves, neither is the driver.
# ─────────────────────────────────────────────────────────────────────────────
set -u
qs_pid=$(pgrep -x quickshell | head -1)
[ -n "$qs_pid" ] || qs_pid=$(pgrep -x qs | head -1)
[ -n "$qs_pid" ] || { echo "bisect-idle: no running shell" >&2; exit 2; }

wpe=$(pgrep -f '[l]inux-wallpaperengine' | tr '\n' ' ')
cava=$(pgrep -x cava | tr '\n' ' ')
stopped=""
trap 'kill -CONT $stopped 2>/dev/null' EXIT INT TERM HUP

# Main-thread CPU %, the last of three 2-second samples (the first is since-start noise).
cpu() { top -H -b -n 3 -d 2 -p "$qs_pid" | awk -v p="$qs_pid" '$1==p {v=$9} END {print v "%"}'; }

freeze() {   # freeze <label> <pids…>
    local label=$1; shift
    [ -n "$*" ] || { echo "$label: not running, skipped"; return; }
    stopped="$*"; kill -STOP $stopped; sleep 1
    echo "$label frozen:  $(cpu)"
    kill -CONT $stopped; stopped=""; sleep 1
}

echo "shell pid $qs_pid"
echo "baseline:               $(cpu)"
freeze "Wallpaper Engine" $wpe
freeze "cava (visualiser)" $cava
echo "after (all resumed):    $(cpu)"
