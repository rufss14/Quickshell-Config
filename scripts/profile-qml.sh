#!/usr/bin/env bash
# ── profile-qml.sh ────────────────────────────────────────────────────────────
# WHICH QML handler or binding is the main thread busy in? Attaches gdb for ~30s, interrupts
# the shell's GUI thread many times, and at each stop asks the QML engine for its own
# JavaScript stack — so the answer is "expression for onTriggered  modules/x/Y.qml:123", not
# a C++ frame. scripts/profile-main.sh says WHICH KIND of work; this says WHOSE.
#
#     sudo bash scripts/profile-qml.sh           60 samples
#     sudo bash scripts/profile-qml.sh 120
#
# Root only because kernel.yama.ptrace_scope=1 forbids attaching to a process that is not your
# child. The shell stutters while it runs (it is stopped 60 times for a few ms each), and a
# sample is skipped when the thread is inside the allocator or a lock (calling into the
# process from there could deadlock it). SIGINT is set to "stop, don't pass" so the shell never
# receives it. The call into the shell runs Qt's own debugger hook (qt_v4StackTraceForEngine).
#
# Needs: gdb. Debug info for libc, QtCore and QtQml comes from debuginfod; it is cached in YOUR
# ~/.cache/debuginfod_client (reused under sudo), so only the first run downloads.
# ─────────────────────────────────────────────────────────────────────────────
set -u
n=${1:-60}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pid=$(pgrep -x quickshell | head -1)
[ -n "$pid" ] || pid=$(pgrep -x qs | head -1)
[ -n "$pid" ] || { echo "profile-qml: no running shell" >&2; exit 2; }
command -v gdb >/dev/null || { echo "profile-qml: gdb missing (pacman -S gdb)" >&2; exit 2; }

# Under sudo HOME is root's: point at the invoking user's cache so nothing is re-downloaded.
user=${SUDO_USER:-$(id -un)}
uhome=$(getent passwd "$user" | cut -d: -f6)
export DEBUGINFOD_URLS=${DEBUGINFOD_URLS:-https://debuginfod.archlinux.org}
export DEBUGINFOD_CACHE_PATH="$uhome/.cache/debuginfod_client"

out=$(mktemp)
echo "sampling pid $pid, $n samples (first run downloads debug info — be patient)…"
QSP_PID=$pid QSP_SAMPLES=$n timeout 900 gdb -batch -q -iex "set debuginfod enabled on" \
    -x "$here/profile-qml.py" >"$out" 2>&1
sed -n '/=== QSP RESULT ===/,$p' "$out"
grep -q '=== QSP RESULT ===' "$out" || { echo "profile-qml: no result — gdb output:"; tail -20 "$out"; }
echo; echo "(full gdb log: $out)"
