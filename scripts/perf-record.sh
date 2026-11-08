#!/usr/bin/env bash
# ── perf-record.sh ────────────────────────────────────────────────────────────
# A C++-level profile of a THROWAWAY shell: where do the GUI thread, the render threads and the
# garbage collector spend their time? Sampled by the kernel, so unlike scripts/profile-qml.sh it never
# stops the shell (gdb stops skewed it: it put ~70% on a path that costs ~4 points in an A/B).
#
#     bash scripts/perf-record.sh              30 s after a 15 s settle
#     bash scripts/perf-record.sh 60 20        60 s after 20 s
#
# The shell is started as perf's own child (so no root and no ptrace_scope change), with a scratch
# XDG_STATE_HOME holding a copy of your live config.json, exactly as scripts/bench_lib.py does.
# Its windows appear over the desktop while it runs.
#
# Needs `perf` (Arch: pacman -S perf). Without it this says so and stops. Quickshell and Qt are stripped
# of local symbols but export their API, so the report names Qt/QML functions (QV4::, QQuick…, QSG…), not
# every private helper; it is not line-level — for "which QML expression" use profile-qml.sh.
# Output: a text report of the heaviest symbols by self time, per thread, and the perf.data to dig into
# (`perf report -i FILE`, or `perf script | stackcollapse-perf.pl | flamegraph.pl` if you have those).
# ─────────────────────────────────────────────────────────────────────────────
set -u
dur=${1:-30}
warm=${2:-15}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(dirname "$here")

command -v perf >/dev/null || { echo "perf-record: perf is not installed (Arch: sudo pacman -S perf)" >&2; exit 2; }
command -v quickshell >/dev/null || { echo "perf-record: quickshell not found" >&2; exit 2; }
# Samples of our own user-space code need paranoid <= 2 (the default on Arch is 2, or 3 on some kernels).
par=$(cat /proc/sys/kernel/perf_event_paranoid 2>/dev/null || echo 2)
[ "$par" -le 2 ] || { echo "perf-record: kernel.perf_event_paranoid=$par forbids profiling even your own processes (sudo sysctl kernel.perf_event_paranoid=2)" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/qs-perf-XXXXXX")
out="$work/perf.data"
# The live config, copied into the throwaway's state dir (the dir is named after the shell's id, which only
# the shell knows: bench_lib.Throwaway does that dance — reuse it to get the state dir ready, then exec).
state=$(python3 - "$here" "$work" <<'PY'
import sys, os
sys.path.insert(0, sys.argv[1])
import bench_lib as B, json
st = os.path.join(sys.argv[2], "state")
cfg = B.live_config()
if cfg:
    # a start-and-stop puts the config where the real run reads it (see bench_lib.Throwaway)
    with B.Throwaway(state=st, config=cfg):
        pass
print(st)
PY
)

echo "perf-record: ${warm}s settle + ${dur}s sampling → $out" >&2
XDG_STATE_HOME="$state" perf record -q -e cycles:u -F 499 -g -o "$out" -- \
    bash -c 'source "$1/scripts/shell-env.sh"; exec timeout -s TERM "$2" quickshell -p "$1"' _ "$repo" "$((warm + dur))" \
    >"$work/shell.log" 2>&1 &
wait

echo
echo "── heaviest symbols by self time, whole run (settle included — perf has no clock to cut it) ──"
perf report -i "$out" --no-children --sort comm,sym --stdio 2>/dev/null | grep -v '^#' | grep -v '^$' | head -45
echo
echo "perf data: $out   (shell log: $work/shell.log)"
