#!/usr/bin/env bash
# ── install-hypr-minimal.sh ───────────────────────────────────────────────────
# Writes ONE file — ~/.config/hypr/quicktest.lua — instead of the full hypr/
# bundle. For someone who already has their own Hyprland config and just wants
# this shell reachable, not the maintainer's monitors/animations/game rules too.
#
#   ./scripts/install-hypr-minimal.sh            write it (backs up any existing one)
#   ./scripts/install-hypr-minimal.sh --print    show what would be written, touch nothing
#   ./scripts/install-hypr-minimal.sh --force    skip the "already have one" prompt
#
# ── What it does NOT touch ────────────────────────────────────────────────────
# Nothing else in ~/.config/hypr. It does not add the require() line to your
# hyprland.lua for you — that's one line, in a file this script has no business
# rewriting blindly (see install-autostart.sh's own reasoning for the same
# call). It prints the line; you place it.
#
# Needs Hyprland's Lua config (hyprland.lua) — hl.bind()/hl.layer_rule() are
# part of that, not hyprlang.
#
# See scripts/templates/quicktest-hypr.lua for exactly what ships.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SRC="$REPO_DIR/scripts/templates/quicktest-hypr.lua"
DEST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
DEST="$DEST_DIR/quicktest.lua"

[ -f "$SRC" ] || { echo "install-hypr-minimal.sh: $SRC missing — is the repo complete?" >&2; exit 1; }

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --print)
            echo "Would write $DEST, with @QUICKSHELL_DIR@ -> $REPO_DIR"
            exit 0 ;;
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,20p' "$(readlink -f "$0")"; exit 0 ;;
        *) echo "install-hypr-minimal.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

if [ -e "$DEST" ] && [ "$FORCE" = 0 ]; then
    echo "$DEST already exists."
    echo "It will be backed up alongside itself and then replaced."
    read -rp "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] || { echo "Nothing changed."; exit 0; }
fi

mkdir -p "$DEST_DIR"

if [ -e "$DEST" ]; then
    BAK="$DEST.bak.$(date +%s)"
    cp -a "$DEST" "$BAK"
    echo "Backed up  $DEST  ->  $BAK"
fi

sed "s|@QUICKSHELL_DIR@|$REPO_DIR|g" "$SRC" > "$DEST"

echo
echo "Wrote $DEST"
echo
echo "Add this line near the top of your own $DEST_DIR/hyprland.lua:"
echo
echo "    require(\"quicktest\")"
echo
echo "Then:  Hyprland --verify-config -c $DEST_DIR/hyprland.lua"
echo "       hyprctl reload      (or log out and back in)"
