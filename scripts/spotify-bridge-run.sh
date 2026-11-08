#!/usr/bin/env bash
# ── spotify-bridge-run.sh ──────────────────────────────────────────────────────
# The detached runner behind SpotifyBridge.qml's `Config.spotifyBridgeDetached`
# mode. Same shape as update-run.sh, scaled down to what a long-lived HTTP
# listener actually needs: no PTY, no FIFO, no phases — just a real lock (so a
# second launch against an already-running listener is a no-op, never a second
# bind) and a log file (so a NEW shell can pick up where an old one left off).
#
# Usage: spotify-bridge-run.sh <lockfile> <logfile> <bridge.py> [python args...]
#
# ── Why this can't just skip die_with_parent() and stay a normal Process ──────
# That was tried in spirit already, before die_with_parent() existed at all — see
# its docstring in spotify-bridge.py. An unsupervised listener left running past
# its shell holds the port forever, and the next shell reports `bind failed` with
# nothing left playing. The flock below is what makes "runs forever" safe: it is
# a kernel fact that only ever admits ONE running instance, so there is never a
# stale listener to clean up and never a port fight between an old one and a new
# one — only ever a single listener, for as long as the machine is up.
#
# ── Protocol with the QML side, and why it matches update-run.sh's ────────────
# Output goes to a LOG FILE, not a pipe: a pipe has exactly one reader, which is
# what makes REATTACHMENT possible. Quickshell tails it with `-F`; if that tailer
# dies (a reload), the listener does not notice or care, and a fresh tail on the
# next shell start picks the stream back up rather than losing the playhead.
# ─────────────────────────────────────────────────────────────────────────────

set -u

LOCKFILE="${1:?lockfile}"; LOGFILE="${2:?logfile}"; SCRIPT="${3:?bridge.py}"
shift 3

mkdir -p "$(dirname "$LOCKFILE")" "$(dirname "$LOGFILE")"

# ── A REAL lock, not a PID write ───────────────────────────────────────────────
# Held by the kernel against an open fd, so it is released automatically the
# instant this process dies — by exit, by SIGKILL, or by the machine rebooting.
# There is no PID to go stale and nothing to probe for liveness: if the lock can
# be taken, no listener is running. That's a fact, not an inference — same
# reasoning as update-run.sh's own lock, and the same bug class (two processes
# both believing they own the port) it exists to rule out here too.
exec 9>>"$LOCKFILE"
if ! flock -n 9; then
    # Someone already holds it. Not an error — the honest answer to "start the
    # bridge" while it's already running is to do nothing and let the caller's
    # own reattach (tailing the log) pick up whatever it's already saying.
    exit 0
fi

# Safe to truncate now: the lock proves nobody else can be writing to it.
: > "$LOGFILE"

# Stdout AND stderr both land here — the bridge's own JSON lines (ready/error/
# anchor) are what the shell's _ingest() parses, and an unparseable line (a rare
# Python traceback, not a normal failure mode — see spotify-bridge.py's own
# `emit()` for how it reports ITS OWN errors as JSON) just logs a warning there
# instead of a crash. Foreground, not `exec`'d: this bash stays alive holding fd
# 9 — and therefore the lock — for exactly as long as the listener runs, and
# exits (releasing it) the moment python3 does, for whatever reason.
python3 "$SCRIPT" --standalone "$@" >> "$LOGFILE" 2>&1
