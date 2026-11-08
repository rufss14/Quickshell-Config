#!/usr/bin/env bash
# ── update-run.sh ─────────────────────────────────────────────────────────────
# The detached runner behind services/Updates.qml. Everything privileged that the
# shell's updater does — pacman, the AUR helper, flatpak, the Vencord installer —
# runs HERE, in its own session, reparented to init, so that nothing Quickshell
# does (reload, crash, `pkill quickshell`) can reach a live pacman transaction.
#
# ── Why this is a file in the repo, not a heredoc in QML ──────────────────────
# It used to be a string in Updates.qml written to ~/.cache/…/run.sh on every
# Quickshell start. That rewrote the script file WHILE a detached job was still
# executing it — bash reads a script incrementally by byte offset, so rewriting it
# underneath a running interpreter is a real (if usually silent) hazard. It also
# made the most safety-critical code in the shell the least reviewable. It is a
# normal, readable file now, resolved through Quickshell.shellPath().
#
# ── Modes ─────────────────────────────────────────────────────────────────────
#   run    <jobdir> <lockfile> <log> <fifo> <label> <command> <seq>
#   cancel <lockfile>
#
# ── Protocol with the QML side ────────────────────────────────────────────────
# Output goes to a LOG FILE, never a pipe, because a pipe has exactly one reader
# and that is what makes REATTACHMENT possible: Quickshell watches with
# `tail -n +1 -F`, which is disposable. If the tailer dies (a reload), the job
# does not notice, and a fresh tail picks the whole run back up from the top.
#
# For the same reason, completion is a sentinel LINE in the log
# (`__QS_DONE__ <code>`) rather than a process exit status — whichever tail is
# watching when it appears reports it, first run or resumed run alike.
# `__QS_LABEL__ <text>` is the same idea for the run's human-readable name, which
# otherwise has nowhere to live across a Quickshell restart.
#
# `__QS_RUN__ <seq>` is the FIRST line a fresh run writes, right after truncating
# the log. The QML side starts its `tail -F` the instant it fires the launcher —
# before this runner has acquired the lock and truncated — so the tail streams
# the PREVIOUS run's whole log first, trailing `__QS_DONE__` and all. Without a
# marker, that stale completion was parsed as THIS run finishing: "it says it
# updated when it didn't", and the credential got wiped so the real sudo prompt
# then asked a second time. The QML ignores everything the tail emits until it
# sees `__QS_RUN__` carrying the seq it launched with.
#
# Both sentinels are written with a FORCED leading newline. A prompt is printed
# with no trailing newline (that is how one is detected at all), so without it a
# sentinel written straight after a prompt would glue onto the prompt's line and
# fail to match at line-start.
#
# Stdin arrives through a FIFO, so the sudo password never touches a command
# line where `ps` would show it to every process on the machine. The job holds
# its own read end open read-WRITE for its whole life (`exec 3<>`), so the FIFO
# never sees EOF between answers, and anything — including a process spawned
# after a reattach — can open the same path to write one.
# ─────────────────────────────────────────────────────────────────────────────

set -u

MODE="${1:-}"
shift || true

# ── Kill a process tree, deepest first ────────────────────────────────────────
# MEASURED, and the reason cancellation never used to work: the job does NOT
# share one process group. `python -m pty.spawn` calls setsid() in its child, so
# a real run spans four separate PGIDs (wrapper / pty child / sudo / pacman). The
# old `kill -TERM -$PGID` reached the wrapper and nothing else, leaving yay and
# pacman alive and unreachable — which is how two upgrades ended up running at
# once against one pacman database.
#
# Root-owned children (sudo, pacman) cannot be signalled by us at all, and that
# is FINE and in fact safer: killing the user-owned side closes the PTY master,
# pacman's read returns EOF at whatever prompt it is sitting on, and it exits
# through its own cleanup path instead of being SIGTERMed mid-transaction. A
# pacman killed by signal is exactly what strands /var/lib/pacman/db.lck.
kill_tree() {
    local pid=$1 child
    for child in $(pgrep -P "$pid" 2>/dev/null); do
        kill_tree "$child"
    done
    kill -TERM "$pid" 2>/dev/null || true
}

# ══ cancel ════════════════════════════════════════════════════════════════════
if [ "$MODE" = cancel ]; then
    LOCKFILE="${1:-}"
    [ -n "$LOCKFILE" ] && [ -f "$LOCKFILE" ] || exit 0
    PID=$(cat "$LOCKFILE" 2>/dev/null)
    [ -n "$PID" ] || exit 0
    kill_tree "$PID"
    exit 0
fi

if [ "$MODE" != run ]; then
    echo "usage: update-run.sh run <jobdir> <lock> <log> <fifo> <label> <cmd>" >&2
    echo "       update-run.sh cancel <lock>" >&2
    exit 64
fi

# ══ run ═══════════════════════════════════════════════════════════════════════
JOBDIR="${1:?jobdir}"; LOCKFILE="${2:?lockfile}"; LOG="${3:?log}"
FIFO="${4:?fifo}";     LABEL="${5:-}";           CMD="${6:?cmd}"
SEQ="${7:-0}"

mkdir -p "$JOBDIR"

# ── A REAL lock ───────────────────────────────────────────────────────────────
# The old lock was `printf $$ > lockfile` — a write, not an acquisition. It never
# refused anything; a second job simply overwrote the first job's PID and both
# ran. That is the single root cause behind every symptom this file exists to
# fix: two concurrent `pacman -Syu` fighting over db.lck, a truncated log, and a
# shared stdin FIFO delivering the user's password to whichever job won the race.
#
# flock is held by the KERNEL against an open file descriptor, so it is released
# automatically when this process dies — normally, by SIGKILL, or by the machine
# rebooting. There is no stale lock to detect and no PID to probe for liveness:
# if the lock can be taken, no run is in progress. That is a fact, not a guess.
#
# Opened with >> rather than > deliberately: `>` truncates AT OPEN, which would
# erase the running job's PID before we discover we cannot have the lock.
exec 9>>"$LOCKFILE"
if ! flock -n 9; then
    # Someone is already updating. Not an error — the honest answer to "update
    # everything" while an update is running is to do nothing.
    exit 75
fi

# Safe to rewrite now: nobody else can be holding this.
printf '%s' "$$" > "$LOCKFILE"

# Everything below happens under the lock, so recreating the FIFO and truncating
# the log cannot disturb another run — there cannot be one. Note the EXIT trap
# does NOT delete these: a previous version did, and deleted the live FIFO out
# from under a concurrent job, permanently orphaning it (its fd 3 pointed at a
# deleted inode, so no answer could ever reach it again).
rm -f "$FIFO"
mkfifo "$FIFO"
: > "$LOG"

# First line of a fresh run — see the protocol notes up top. Everything the QML
# tail streamed before this is the previous run's log and is discarded there.
printf '__QS_RUN__ %s\n' "$SEQ" >> "$LOG"

# ── sudo keepalive — INSIDE the PTY, and that is the whole point ──────────────
# The credential cache (15 minutes by default) can expire during a long AUR
# build, after which the helper's own inner sudo re-prompts — on a PTY the user
# is no longer being asked about, which is one of the ways a run used to wedge
# silently. Refreshing it on a timer removes the whole class of problem.
#
# `sudo -n -v` is non-interactive: it fails harmlessly and silently until the
# real `sudo -v` inside the job has established the credential, then keeps it
# fresh. It covers pacman, the helper and the Vencord installer alike, which is
# why it is here rather than delegated to `yay --sudoloop`.
#
# ── Why it moved out of this script and into the job ──────────────────────────
# It used to run HERE, as a background subshell of the runner, and it could not
# work: sudo's `tty_tickets` is on by default and keys the credential per
# TERMINAL. This script is detached with setsid and has no controlling tty, so
# `sudo -n -v` here refreshed a ticket for "no tty" — while the job runs inside
# the PTY below and uses that pty's ticket. Two different records; the one being
# kept warm was the one nobody was using. The keepalive was a no-op that read as
# a working feature, which is worse than not having it: the comment above claimed
# the class of problem was gone.
#
# Prefixed onto the job's own command instead, so it is a child of the PTY'd bash
# and shares its controlling terminal. That is correct under BOTH sudo
# configurations — same tty when tty_tickets is on, same global ticket when it is
# off — so nothing here depends on how the user's sudoers is written.
#
# fd 9 is still closed in the subshell: it is the flock fd, inherited all the way
# down, and a leaked keepalive holding it would block every future run.
#
# `while sleep 45` sleeps BEFORE the first refresh on purpose. Refreshing
# immediately would put a second sudo on the tty in the same instant the real
# `sudo -v` is about to prompt on it, for no benefit — there is no credential to
# keep alive yet.
KEEPALIVE_PREAMBLE=$(cat <<'PREAMBLE'
( exec 9>&-; while sleep 45; do sudo -n -v 2>/dev/null || true; done ) &
__qs_keepalive=$!
trap 'kill "$__qs_keepalive" 2>/dev/null' EXIT
PREAMBLE
)

# ── Completion ────────────────────────────────────────────────────────────────
# MEASURED: `$?` inside an EXIT trap does not reliably reflect "killed by
# signal" — a script group-killed while blocked in a foreground command reports
# the trap's own `$?` as 0, not 128+signal. So completion is tracked with an
# explicit flag: the normal path sets DONE before writing the real exit code, and
# the trap writes a fixed "terminated" code only if that never happened.
DONE=0
cleanup() {
    [ "$DONE" = 0 ] && printf '\n__QS_DONE__ 143\n' >> "$LOG"
    return 0
}
trap cleanup EXIT

printf '\n__QS_LABEL__ %s\n' "$LABEL" >> "$LOG"

exec 3<>"$FIFO"

# `python -m pty.spawn` gives a genuine PTY and writes with os.write — unbuffered,
# without the `script` command's buffering. A PTY is what makes pacman print its
# progress and prompts at all rather than switching to pipe-mode output.
#
# The keepalive is prepended rather than passed separately so it starts inside
# this bash, on this pty — see the block above. It goes BEFORE the caller's
# command, which is what puts it in place before the first `sudo -v`; the
# caller's own `set -e` starts where the caller wrote it and is unaffected.
python3 -c 'import pty,sys,os; sys.exit(os.waitstatus_to_exitcode(pty.spawn(sys.argv[1:])))' \
    bash -c "$KEEPALIVE_PREAMBLE
$CMD" <&3 >>"$LOG" 2>&1
CODE=$?

DONE=1
printf '\n__QS_DONE__ %s\n' "$CODE" >> "$LOG"
