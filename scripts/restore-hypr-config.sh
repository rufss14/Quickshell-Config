#!/usr/bin/env bash
# ── restore-hypr-config.sh ────────────────────────────────────────────────────
# The way back from the Hyprland setup step. install-hypr-config.sh copies ~/.config/hypr to
# ~/.config/hypr.bak.<time> before it replaces anything, and install-hypr-minimal.sh copies an existing
# quicktest.lua to quicktest.lua.bak.<time>; this puts one of them back.
#
#   restore-hypr-config.sh --list               one line per backup, newest first:  kind|path|epoch
#                                                (kind: dir = a whole config, file = a quicktest.lua)
#   restore-hypr-config.sh --restore [PATH]     put a whole-config backup back (default: the newest)
#   restore-hypr-config.sh --restore-minimal    put the newest quicktest.lua backup back, or — if there is none —
#                                                set quicktest.lua aside
#
# ── Restoring is itself undoable ──────────────────────────────────────────────
# What is there now is MOVED to ~/.config/hypr.before-restore.<time> (or quicktest.lua.before-restore.<time>),
# never deleted, so a restore you regret is one `mv` from being undone. PATH must be exactly one of the
# hypr.bak.<digits> directories next to the config — nothing else is ever restored from.
#
# After removing quicktest.lua, a `require("quicktest")` line in your own hyprland.lua would fail to load; the
# script says so, because it will not edit that file for you.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DIR="$CFG/hypr"
NOW="$(date +%s)"

list() {
    local f
    # Newest first: the epoch is the suffix after the last dot.
    for f in "$CFG"/hypr.bak.*; do
        [ -d "$f" ] && [[ "${f##*.}" =~ ^[0-9]+$ ]] && echo "dir|$f|${f##*.}"
    done
    for f in "$DIR"/quicktest.lua.bak.*; do
        [ -f "$f" ] && [[ "${f##*.}" =~ ^[0-9]+$ ]] && echo "file|$f|${f##*.}"
    done
    # A loop's status is its last test's, and "no such backup" is not a failure (set -e, pipefail).
    return 0
}
sorted() { list | sort -t'|' -k3,3nr; }

# Move something out of the way under a name that is free (two restores in one second must not collide).
aside() {
    local dest="$1.before-restore.$NOW" n=0
    while [ -e "$dest" ]; do n=$((n + 1)); dest="$1.before-restore.$NOW-$n"; done
    mv "$1" "$dest"
    echo "Set aside  $1  ->  $dest"
}

case "${1:-}" in
--list)
    sorted
    ;;
--restore)
    src="${2:-}"
    if [ -z "$src" ]; then
        src="$(sorted | awk -F'|' '$1=="dir"{print $2; exit}')"
        [ -n "$src" ] || { echo "restore-hypr-config.sh: there is no backup of a whole config to restore" >&2; exit 1; }
    fi
    # Exactly <config>/hypr.bak.<digits> — no other path, and no `..` to walk out of it.
    [[ "$src" =~ ^"$CFG"/hypr\.bak\.[0-9]+$ && -d "$src" ]] \
        || { echo "restore-hypr-config.sh: '$src' is not one of the hypr.bak.<time> backups" >&2; exit 2; }
    [ -e "$DIR" ] && aside "$DIR"
    cp -a "$src" "$DIR"
    echo "Restored   $src  ->  $DIR"
    echo "Reload Hyprland (hyprctl reload) to use it."
    ;;
--restore-minimal)
    mini="$DIR/quicktest.lua"
    bak="$(sorted | awk -F'|' '$1=="file"{print $2; exit}')"
    [ -e "$mini" ] && aside "$mini"
    if [ -n "$bak" ]; then
        cp -a "$bak" "$mini"
        echo "Restored   $bak  ->  $mini"
    else
        echo "There was no earlier quicktest.lua, so it is simply gone."
        echo "If your own hyprland.lua has the line  require(\"quicktest\")  remove it, or Hyprland will fail to load that file."
    fi
    ;;
-h|--help|"")
    sed -n '2,22p' "$(readlink -f "$0")"
    ;;
*)
    echo "restore-hypr-config.sh: unknown argument '$1'" >&2
    exit 2
    ;;
esac
