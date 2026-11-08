#!/usr/bin/env bash
# ── install-hypr-config.sh ───────────────────────────────────────────────────
# Installs the bundled Hyprland config (hypr/) into ~/.config/hypr.
#
#   ./scripts/install-hypr-config.sh            install (backs up any existing config)
#   ./scripts/install-hypr-config.sh --print    list what it would write, touch nothing
#   ./scripts/install-hypr-config.sh --force    skip the "already have a config" prompt
#
# ── What it is ──────────────────────────────────────────────────────────────
# The maintainer's own Hyprland setup, generic where it has to be: the monitor
# line applies a default to every output (EDIT hardware.lua for your screens),
# and every path to this repo is filled in from where the repo actually lives.
# The bar/border/blur numbers live in hypr/blend.lua, the one file Hyprland and
# the shell share.
#
# ── Safety ──────────────────────────────────────────────────────────────────
# If ~/.config/hypr already has a hyprland.lua or hyprland.conf, the whole
# directory is copied to ~/.config/hypr.bak.<timestamp> before anything is
# written, and a stray hyprland.conf is moved aside (Hyprland 0.56 loads Lua by
# extension, and a leftover .conf next to it is a coin flip).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SRC="$REPO_DIR/hypr"
DEST="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"

[ -d "$SRC" ] || { echo "install-hypr-config.sh: $SRC missing — is the repo complete?" >&2; exit 1; }

FORCE=0
for arg in "$@"; do
    case "$arg" in
        --print)
            echo "Would write, with @QUICKSHELL_DIR@ -> $REPO_DIR :"
            (cd "$SRC" && find . -type f | sed 's|^\./|  '"$DEST"'/|')
            exit 0 ;;
        --force) FORCE=1 ;;
        -h|--help) sed -n '2,25p' "$(readlink -f "$0")"; exit 0 ;;
        *) echo "install-hypr-config.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

HAD_CONFIG=0
[ -e "$DEST/hyprland.lua" ] || [ -e "$DEST/hyprland.conf" ] && HAD_CONFIG=1

if [ "$HAD_CONFIG" = 1 ] && [ "$FORCE" = 0 ]; then
    echo "$DEST already has a Hyprland config."
    echo "It will be copied to $DEST.bak.<timestamp> and then replaced."
    read -rp "Continue? [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]] || { echo "Nothing changed."; exit 0; }
fi

if [ "$HAD_CONFIG" = 1 ]; then
    BAK="$DEST.bak.$(date +%s)"
    cp -a "$DEST" "$BAK"
    echo "Backed up  $DEST  ->  $BAK"
fi

mkdir -p "$DEST/scripts"

# Copy every file, substituting the repo path. `@QUICKSHELL_DIR@` only appears in
# text files here, so a blanket sed is safe.
while IFS= read -r rel; do
    mkdir -p "$DEST/$(dirname "$rel")"
    sed "s|@QUICKSHELL_DIR@|$REPO_DIR|g" "$SRC/$rel" > "$DEST/$rel"
done < <(cd "$SRC" && find . -type f | sed 's|^\./||')

chmod +x "$DEST/scripts/"*.sh "$DEST/scripts/"*.py 2>/dev/null || true

# ── Monitors ────────────────────────────────────────────────────────────────
# The file we just wrote applies one generic line to every output. If Hyprland
# is running, replace that with the machine's real outputs, modes and positions
# straight from `hyprctl monitors`. Fails soft — the generic line stays — when
# hyprctl isn't reachable (installing from a TTY or another session).
if command -v hyprctl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    if python3 "$REPO_DIR/scripts/hypr-monitors.py" "$DEST/hardware.lua"; then
        MONITORS_DONE=1
    fi
fi

# A leftover hyprland.conf next to hyprland.lua is ambiguous — move it aside.
if [ -e "$DEST/hyprland.conf" ]; then
    mv "$DEST/hyprland.conf" "$DEST/hyprland.conf.disabled"
    echo "Moved  hyprland.conf  ->  hyprland.conf.disabled  (Lua config is now active)"
fi

echo
echo "Installed the Hyprland config to $DEST"
echo
if [ "${MONITORS_DONE:-0}" = 1 ]; then
    echo "  1. Monitors were auto-detected into  $DEST/hardware.lua  — adjust only"
    echo "     if a screen is placed or scaled wrong."
else
    echo "  1. EDIT  $DEST/hardware.lua  — set your monitor(s)."
fi
echo "  2. Check it:   Hyprland --verify-config -c $DEST/hyprland.lua"
echo "  3. Reload:     hyprctl reload      (or log out and back in)"
echo
echo "Optional bits are commented out in autostart.lua / hardware.lua (awww, hyprpm"
echo "plugins, dynamic cursors) — turn them on once those are installed."
