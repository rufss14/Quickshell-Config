#!/usr/bin/env bash
# ── profile-main.sh ───────────────────────────────────────────────────────────
# Where is the shell's main (GUI) thread spending its time? Samples its stack N times
# with eu-stack and prints which functions it was in most often.
#
#     sudo bash scripts/profile-main.sh           40 samples, ~0.2s apart
#     sudo bash scripts/profile-main.sh 100       more samples
#
# Needs root ONLY because kernel.yama.ptrace_scope=1 forbids attaching to a process that
# is not your child, and the live shell is not. It reads, it does not change anything:
# each sample pauses the shell for a few tens of ms, so the desktop stutters while it runs.
# Symbols come from debuginfod (DEBUGINFOD_URLS is set by Arch's profile.d); the FIRST run
# downloads debug info for Qt and Quickshell and is slow — later runs are fast.
#
# Read the result as: "leaf" = the function the thread was executing, "inclusive" = any
# function on the stack. A QML-heavy load shows up as QV4::/QQmlBinding frames in
# inclusive; a render/layout load as QQuickItem/QSG frames; a wakeup storm as
# QEventDispatcher/eventfd/poll leaves.
# ─────────────────────────────────────────────────────────────────────────────
set -u
n=${1:-40}
pid=$(pgrep -x quickshell | head -1)
[ -n "$pid" ] || pid=$(pgrep -x qs | head -1)
[ -n "$pid" ] || { echo "profile-main: no running shell" >&2; exit 2; }
command -v eu-stack >/dev/null || { echo "profile-main: eu-stack missing (pacman -S elfutils)" >&2; exit 2; }

out=$(mktemp -d)
echo "sampling pid $pid, $n samples → $out"
for i in $(seq "$n"); do
    eu-stack -1 -n 40 -p "$pid" >"$out/s$i.txt" 2>/dev/null
    sleep 0.2
done

# "#12  0x00007f… QV4::Moth::VME::exec" → "QV4::Moth::VME::exec"
frames() { sed -nE 's/^#[0-9]+[[:space:]]+0x[0-9a-f]+[[:space:]]+//p' "$@" | sed -E 's/ \(.*//; s/ \+0x.*//'; }

echo; echo "── leaf (what it was executing) ──"
for f in "$out"/s*.txt; do frames "$f" | head -1; done | sort | uniq -c | sort -rn | head -15
echo; echo "── inclusive (anywhere on the stack, % of samples) ──"
for f in "$out"/s*.txt; do frames "$f" | sort -u; done | sort | uniq -c | sort -rn | head -40 \
    | awk -v n="$n" '{c=$1; $1=""; printf "%4d%%  %s\n", c*100/n, $0}'
echo; echo "raw samples kept in $out"
