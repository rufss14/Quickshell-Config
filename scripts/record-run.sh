#!/usr/bin/env bash
# ── record-run.sh ─────────────────────────────────────────────────────────────
# The detached runner behind services/Recorder.qml. It holds the screen-recorder
# backend open for the whole capture and is the only thing that ever signals it.
#
# ── Why detached, like update-run.sh ─────────────────────────────────────────
# A recording is a long-lived job whose output is worthless if it is interrupted
# badly. Reloading the shell (ALT+Q), a crash, or a plain `pkill quickshell` must
# not reach a live capture — so the real job runs under `setsid`, reparented to
# init, in its own session, and Quickshell only ever talks to it through files.
#
# ── The protocol with the QML side is a STATE FILE, not a pipe ───────────────
# A pipe has exactly one reader, which is precisely what breaks across a reload.
# The runner writes a small JSON document that services/Recorder.qml watches with
# a FileView; whatever Quickshell is alive at the time reads it, first run or
# after a reload alike. The file is written to a temp path and renamed, because a
# FileView watching a half-written document parses garbage and reports the
# recording as gone.
#
# ── STOP IS SIGINT, AND THAT IS THE WHOLE POINT ──────────────────────────────
# wf-recorder finalises the container on SIGINT: it flushes the encoder, writes
# the moov atom / index, and exits 0. On SIGTERM it dies where it stands and
# leaves a file no player will open — the frames are all there and the container
# says nothing about them. So `stop` sends INT and WAITS. SIGTERM exists here
# only as a last resort after the grace period, and reaching it means the capture
# was already lost; it is not the normal path.
#
# This is the same instinct as update-run.sh's cancellation: end the child
# through its own cleanup path rather than killing it mid-write.
#
# ── Modes ─────────────────────────────────────────────────────────────────────
#   start <statedir> <outfile> <backend> [backend args…]
#   stop  <statedir>
#
# `start` is meant to be launched detached and returns only when the recording
# is over. `stop` is a short-lived call from the UI.
# ─────────────────────────────────────────────────────────────────────────────

set -u

MODE="${1:-}"
shift || true

STATEDIR="${1:-}"
shift || true

[ -n "$STATEDIR" ] || { echo "record-run: no state directory" >&2; exit 2; }
mkdir -p "$STATEDIR" || exit 2

STATE="$STATEDIR/state.json"
LOG="$STATEDIR/record.log"
LOCK="$STATEDIR/record.lock"

# ── Atomic state write ────────────────────────────────────────────────────────
# Same reason apply-wallpaper.sh writes its palette through a temp file: the
# reader is a file watcher, and a watcher that fires on a partial write sees a
# truncated document. Rename is atomic within one filesystem, so a reader either
# gets the whole old document or the whole new one.
write_state() {
    local tmp
    tmp="$(mktemp "$STATEDIR/.state.XXXXXX")" || return 1
    printf '%s\n' "$1" > "$tmp"
    mv -f "$tmp" "$STATE"
}

# JSON string escaping, for paths and error text that can contain anything.
esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g'; }

idle_state()  { write_state '{"state":"idle"}'; }

error_state() {
    write_state "{\"state\":\"error\",\"message\":\"$(esc "$1")\"}"
}

case "$MODE" in
# ─────────────────────────────────────────────────────────────────────────────
start)
    OUT="${1:-}";     shift || true
    BACKEND="${1:-}"; shift || true

    [ -n "$OUT" ] && [ -n "$BACKEND" ] || {
        echo "record-run: start needs an output file and a backend" >&2; exit 2; }

    # ── The lock is flock, for the reason the updater's is ───────────────────
    # Kernel-held and released on crash or reboot, so there is no stale-lock
    # logic to get wrong. A second start while a capture is live must refuse
    # rather than spawn a second backend fighting for the same output file.
    exec 9>>"$LOCK" || exit 2
    if ! flock -n 9; then
        echo "record-run: a recording is already running" >&2
        exit 3
    fi

    command -v "$BACKEND" >/dev/null 2>&1 || {
        error_state "$BACKEND is not installed"; exit 4; }

    mkdir -p "$(dirname "$OUT")" || { error_state "cannot create the output directory"; exit 5; }

    : > "$LOG"

    # ── `set -m` IS LOAD-BEARING. DO NOT REMOVE IT. ─────────────────────────
    # POSIX: a non-interactive shell starts a background (`&`) child with SIGINT
    # and SIGQUIT set to IGNORED, and a process that inherits a signal as ignored
    # CANNOT install a handler for it. So without job control the backend never
    # receives the stop signal at all — `stop` would send INT, nothing would
    # happen, the ten-second grace period would expire, and every single
    # recording would end by escalation to SIGTERM with an unplayable file.
    #
    # That failure is completely silent: the capture looks fine, the pill goes
    # back to idle, and the damage only shows up later when the video will not
    # open. Job control restores the default dispositions (and gives the child
    # its own process group, which is why `stop` can signal it cleanly).
    # Measured, not assumed — scripts/test-record-run.py pins it.
    set -m

    # The backend's own stderr is the only account of why a capture failed
    # (a bad geometry, a missing audio device, no DRM permission), so it goes to
    # a file the error state can quote rather than /dev/null.
    "$BACKEND" "$@" >>"$LOG" 2>&1 &
    CHILD=$!
    set +m

    write_state "{\"state\":\"recording\",\"file\":\"$(esc "$OUT")\",\"pid\":$CHILD,\"backend\":\"$(esc "$BACKEND")\",\"startedAt\":$(date +%s)}"

    # ── Forward a signal aimed at US to the child, as INT ────────────────────
    # `stop` signals the child directly, but a shutdown or a stray kill aimed at
    # this wrapper would otherwise orphan a running encoder holding the output
    # file open. Translating to INT means even that path finalises the file.
    trap 'kill -INT "$CHILD" 2>/dev/null' INT TERM HUP

    wait "$CHILD"; CODE=$?
    # 130 is INT — the normal, deliberate end of a recording, not a failure.
    [ "$CODE" -eq 130 ] && CODE=0

    if [ "$CODE" -ne 0 ] || [ ! -s "$OUT" ]; then
        # A zero-byte output with a zero exit is still a failed capture; report
        # the backend's last words rather than a bare code nobody can act on.
        TAIL="$(tail -n 3 "$LOG" 2>/dev/null | tr '\n' ' ')"
        error_state "${TAIL:-the recorder exited with $CODE}"
        exit "$CODE"
    fi

    write_state "{\"state\":\"done\",\"file\":\"$(esc "$OUT")\",\"endedAt\":$(date +%s)}"
    ;;

# ─────────────────────────────────────────────────────────────────────────────
stop)
    # Read the pid out of the state document rather than tracking it in QML: the
    # shell may have reloaded since the capture started, and the state file is
    # the only thing that survived that.
    [ -f "$STATE" ] || { idle_state; exit 0; }
    PID="$(sed -n 's/.*"pid":\([0-9]*\).*/\1/p' "$STATE")"
    [ -n "$PID" ] || { idle_state; exit 0; }

    kill -0 "$PID" 2>/dev/null || { idle_state; exit 0; }

    # INT, then WAIT. Finalising a large capture is not instant — the encoder has
    # to flush and write its index — and a stop that returns before that has
    # happened would let the UI report a file that is still being written.
    kill -INT "$PID" 2>/dev/null || true

    for _ in $(seq 1 100); do          # up to ~10s
        kill -0 "$PID" 2>/dev/null || exit 0
        sleep 0.1
    done

    # Only here, and it means the file is already compromised.
    echo "record-run: $PID ignored SIGINT for 10s, escalating" >&2
    kill -TERM "$PID" 2>/dev/null || true
    ;;

*)
    echo "record-run: unknown mode '${MODE}'" >&2
    exit 2
    ;;
esac
