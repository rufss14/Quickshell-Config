#!/usr/bin/env bash
# overview-shots.sh [outdir] — photograph every state of the overview, for a design review.
#
# Drives the RUNNING shell: opens the overview, puts it in each named state through
# `qs ipc … call overviewdebug go <state>` (modules/overview/Overview.qml: view state only — it never
# moves, closes or sends a window), and grabs the focused monitor with grim after each one settles.
# Closes the overview and restores the feed page it found.
#
#   scripts/overview-shots.sh                 # → $XDG_RUNTIME_DIR/overview-shots/NN-state.png
#   scripts/overview-shots.sh ~/shots         # → ~/shots/...
#   STATES="idle pick" scripts/overview-shots.sh   # only some
#
# Needs: quickshell (qs), grim, hyprctl, jq. The shell must already be running this config.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
out=${1:-${XDG_RUNTIME_DIR:-/tmp}/overview-shots}
settle=${SETTLE:-1.3}
for t in qs grim hyprctl jq; do command -v "$t" >/dev/null || { echo "missing: $t" >&2; exit 1; }; done

ipc() { qs ipc -c "$here" call "$@" 2>&1; }
mon=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')
[ -n "$mon" ] || { echo "no focused monitor" >&2; exit 1; }
mkdir -p "$out"

# name[:arg] in the order they are shot. Feed pages 0-2 = What's changed, Ask, News.
STATES=${STATES:-"idle search:fire pick more space bulk all ctrl sessions help full feed:0 feed:1 feed:2 peek"}

ipc overview open >/dev/null
sleep 2.2
status=$(ipc overviewdebug status)
echo "$status"
case "$status" in *shown=true*) ;; *) echo "overview did not open on $mon (is the shell running this config?)" >&2; exit 1 ;; esac
feed0=$(sed -n 's/.*feed=\([0-9]*\).*/\1/p' <<<"$status")
more0=$(sed -n 's/.*more=\(true\|false\).*/\1/p' <<<"$status")

n=0
for spec in $STATES; do
    name=${spec%%:*}; arg=""; [ "$spec" != "$name" ] && arg=${spec#*:}
    n=$((n + 1))
    printf '%-10s ' "$spec"
    ipc overviewdebug go "$name" "${arg:--}"
    sleep "$settle"
    f=$(printf '%s/%02d-%s%s.png' "$out" "$n" "$name" "${arg:+-$arg}")
    grim -o "$mon" "$f" && echo "   $f"
done

ipc overviewdebug go idle - >/dev/null
[ -n "$feed0" ] && ipc overviewdebug go feed "$feed0" >/dev/null
# The fold is a kept setting: put back what was found (calm unless it was full).
[ "$more0" = "true" ] && ipc overviewdebug go full - >/dev/null || ipc overviewdebug go calm - >/dev/null
ipc overview close >/dev/null
echo "done: $n shots in $out"
