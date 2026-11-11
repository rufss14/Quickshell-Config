#!/bin/bash
# Safe QuickShell reload
QS_BIN="quickshell"

# Repo root derived from this script's own location, never a literal — this config
# is published and installs wherever someone clones it, not necessarily
# ~/.config/quicktest. Same rule as install-desktop-entry.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# QML_IMPORT_PATH (Blobs plugin) + QSG_RHI_BACKEND=vulkan (openssl shader-cache
# segfault workaround). The one copy, shared with ~/.config/hypr/autostart.lua so
# a reloaded shell and a booted one start identically — see the file for why.
# shellcheck disable=SC1091
source "$SCRIPT_DIR/shell-env.sh"

# Refuse while a privileged update (pacman/yay/flatpak/Vencord) is running. This
# script's pkill runs OUTSIDE Quickshell entirely, so a QML-side guard can't see it —
# and killing pacman mid-transaction has corrupted files before.
#
# The lock is held with flock by scripts/update-run.sh, so `flock -n -s` failing is
# proof a run is live. The previous check read a PID out of the file and probed it with
# `kill -0`, which was checking a file that nothing ever actually locked — and could not
# distinguish a live run from a recycled PID. `-s` (shared) is used so this test cannot
# truncate or disturb the lock file it is reading.
LOCK="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-update.lock"
if [ -f "$LOCK" ] && ! flock -n -s "$LOCK" true; then
  notify-send --app-name="Quickshell" --urgency=critical \
    "Reload blocked" "An update is installing — wait for it to finish (or cancel it) before reloading."
  exit 1
fi

(
# small delay so this script survives QS dying
sleep 0.3

# The running shell's exit — its entrance played backwards (state/Intro.qml) — before
# it is killed, so a reload reads as leave-then-arrive instead of vanish-then-pop. It
# answers with the exit's length in ms; waiting that long lets it finish. Bounded on
# both sides: a hung shell, or an older one with no `intro` target, answers nothing
# within the timeout and the reload simply goes on; the wait is capped at a second.
ms=$(timeout 1 "$QS_BIN" ipc -p "$REPO_DIR" call intro leave 2>/dev/null | tr -dc '0-9')
if [ -n "$ms" ] && [ "$ms" -gt 0 ]; then
  [ "$ms" -gt 1000 ] && ms=1000
  sleep "$(awk -v m="$ms" 'BEGIN { printf "%.3f", m / 1000 }')"
fi
# kill running instances.
#
# The wrapper first (scripts/shell-run.sh), so one caught between two crash restarts
# can't start a second shell beside the one launched below. Killing it leaves its shell
# running; that is killed next.
#
# Match BOTH names. pkill/pgrep compare against `comm`, not the command line, unless
# given -f — and the binary is installed twice, as `qs` and as `quickshell`. An older
# autostart line, a manual start or a smoke run may use either, so match both.
# -x so these are exact `comm` matches rather than substrings.
pkill -TERM -f -- "$SCRIPT_DIR/shell-run.sh" 2>/dev/null
pkill -TERM -x 'qs|quickshell' 2>/dev/null
# wait until fully gone
for i in {1..40}; do
pgrep -x 'qs|quickshell' >/dev/null || break
sleep 0.1
done
# force kill if stubborn
pkill -9 -x 'qs|quickshell' 2>/dev/null
# brief pause to avoid race conditions
sleep 0.2
# restart detached from terminal + QS process tree
#
# stdout/stderr go to a log file, not /dev/null — Quickshell's own console.warn/
# console.error (the update runner's password-prompt diagnostic among them) were
# unreachable after a reload, which is the one moment they'd actually be needed.
# Truncated per reload, same reasoning as update-run.sh's own log: it should hold
# THIS session's output, not an ever-growing history.
QS_LOG="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/quickshell.log"
mkdir -p "$(dirname "$QS_LOG")"
# Through shell-run.sh, as at boot: it restarts the shell after a startup crash (and
# falls back to safe mode), and a reload never carries an old QS_SAFE along.
setsid env -u QS_SAFE "$SCRIPT_DIR/shell-run.sh" >"$QS_LOG" 2>&1 &
) & disown
exit 0