#!/usr/bin/env bash
# Keep the Claude Code presence daemon alive across Quickshell reloads.
#
#   claude-presence-run.sh run    <dir>   hold the lock and exec the daemon
#   claude-presence-run.sh stop   <dir>   stop whatever holds the lock
#   claude-presence-run.sh status <dir>   print "running", or nothing
#
# ── Why the daemon is not a Quickshell child ──────────────────────────────────
# It was, and every shell reload dropped the presence off your profile for as long as
# the shell took to come back — plus Discord's own rate limit meant the reconnect could
# not immediately re-publish, so a reload cost several seconds of blank profile. The
# presence has nothing to do with the shell's lifetime: it describes a TERMINAL, which
# is still sitting there while the bar is being rebuilt.
#
# So the daemon is `setsid`-detached and reparented to init, exactly like
# scripts/update-run.sh. The shell starts it, tells it things through a file, reads its
# state from another file, and can die and come back without the daemon noticing.
#
# ── The lock is flock, and it has to stay that way ────────────────────────────
# Same rule as update-run.sh, arrived at the same painful way. flock is held by the
# KERNEL against an open descriptor, so it is released when the holder dies — normally,
# by SIGKILL, or by the machine losing power. There is no stale lock to detect.
#
# That is what makes `run` IDEMPOTENT, which is the property the whole design leans on:
# the shell can call it on every startup without checking anything first, and a second
# invocation simply exits 75 because it cannot take the lock. There is no "is it already
# running" race to lose, because the question is never asked — it is answered by whether
# the lock could be taken.
#
# The PID written into the lock file is INFORMATIONAL, for `stop` to aim at. It is
# written after the lock is acquired and is never what decides whether a daemon is
# running. A PID file used as a lock is what update-run.sh's header calls the single
# root cause behind every symptom it exists to fix; this does not repeat it.
set -euo pipefail

CMD="${1:?run|stop|status}"
DIR="${2:?state dir}"

LOCK="$DIR/presence.lock"
STATE="$DIR/state.json"
OPTIONS="$DIR/options.json"
LOG="$DIR/daemon.log"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="$HERE/claude-presence.py"

mkdir -p "$DIR"

case "$CMD" in
run)
    # Opened with >> rather than >: `>` truncates AT OPEN, which would erase the
    # running daemon's PID before we find out we cannot have the lock.
    exec 9>>"$LOCK"
    if ! flock -n 9; then
        exit 75          # already running. Not an error — this is the idempotent path.
    fi
    printf '%s' "$$" > "$LOCK"

    # The log is truncated per start rather than appended forever: it is a diagnostic
    # for the CURRENT daemon, and an unbounded file nobody rotates is a slow leak.
    : > "$LOG"

    # exec, so the daemon INHERITS this shell's process — and with it fd 9, keeping the
    # lock held for exactly as long as the daemon lives. A backgrounded child would
    # instead let this script exit and drop the lock immediately, making `run` succeed
    # every time and cheerfully start a tenth daemon.
    exec python3 "$DAEMON" --state-file "$STATE" --options-file "$OPTIONS" >>"$LOG" 2>&1
    ;;

stop)
    [ -f "$LOCK" ] || exit 0
    # If the shared lock can be taken, nobody holds the exclusive one, so there is
    # nothing running and nothing to signal. A kernel fact, not an inference from a PID.
    if flock -n -s "$LOCK" true 2>/dev/null; then
        exit 0
    fi
    PID="$(cat "$LOCK" 2>/dev/null || true)"
    case "$PID" in
        ''|*[!0-9]*) exit 0 ;;
    esac
    # TERM, not KILL: the daemon clears the presence from your profile on the way out.
    # Killed outright it cannot, and Discord keeps showing the activity for minutes.
    kill -TERM "$PID" 2>/dev/null || true

    for _ in $(seq 1 30); do
        flock -n -s "$LOCK" true 2>/dev/null && exit 0
        sleep 0.1
    done
    kill -KILL "$PID" 2>/dev/null || true
    ;;

status)
    [ -f "$LOCK" ] || exit 0
    flock -n -s "$LOCK" true 2>/dev/null || echo running
    ;;

*)
    echo "usage: $0 run|stop|status <dir>" >&2
    exit 2
    ;;
esac
