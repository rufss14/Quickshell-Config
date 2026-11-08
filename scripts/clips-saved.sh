#!/bin/sh
# gpu-screen-recorder's -sc hook (scripts/clips-run.py adds it): the recorder runs
# this with the saved file and its type ("replay", "regular", "screenshot") once the
# file is written. CLIPS_RUNDIR is set by the runner, in the recorder's environment.
[ -n "$CLIPS_RUNDIR" ] || exit 0
exec python3 "$(dirname "$(readlink -f "$0")")/clips-run.py" saved "$CLIPS_RUNDIR" "$1" "$2"
