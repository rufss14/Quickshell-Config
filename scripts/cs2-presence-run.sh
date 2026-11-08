#!/usr/bin/env bash
# Keep the Counter-Strike 2 presence daemon alive across Quickshell reloads.
#
#   cs2-presence-run.sh run    <dir>   hold the lock and exec the daemon
#   cs2-presence-run.sh stop   <dir>   stop whatever holds the lock
#   cs2-presence-run.sh status <dir>   print "running", or nothing
#
# This is scripts/claude-presence-run.sh with the names changed, and for every reason
# that file's header gives: the daemon is `setsid`-detached and reparented to init so a
# shell reload never drops the presence, the lock is `flock` so `run` is idempotent and
# there is no stale-lock case, and `stop` sends TERM not KILL so the daemon gets to
# clear the card from your profile on the way out. Read that header for the full why.
set -euo pipefail

CMD="${1:?run|stop|status}"
DIR="${2:?state dir}"

LOCK="$DIR/presence.lock"
STATE="$DIR/state.json"
OPTIONS="$DIR/options.json"
LOG="$DIR/daemon.log"

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="$HERE/cs2-presence.py"

mkdir -p "$DIR"

case "$CMD" in
run)
    exec 9>>"$LOCK"
    if ! flock -n 9; then
        exit 75          # already running. Not an error — this is the idempotent path.
    fi
    printf '%s' "$$" > "$LOCK"
    : > "$LOG"
    exec python3 "$DAEMON" --state-file "$STATE" --options-file "$OPTIONS" >>"$LOG" 2>&1
    ;;

stop)
    [ -f "$LOCK" ] || exit 0
    if flock -n -s "$LOCK" true 2>/dev/null; then
        exit 0
    fi
    PID="$(cat "$LOCK" 2>/dev/null || true)"
    case "$PID" in
        ''|*[!0-9]*) exit 0 ;;
    esac
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
