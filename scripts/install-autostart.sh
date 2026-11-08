#!/usr/bin/env bash
# ── install-autostart.sh ──────────────────────────────────────────────────────
# Wires this shell into Hyprland's autostart, portably — the actual autostart line
# lives in your own ~/.config/hypr config (outside this repo), and until this
# script existed, setting it up meant hand-writing the right syntax and guessing
# the correct repo path yourself.
#
# The path is derived from THIS SCRIPT's own location, never a literal — same rule
# as install-desktop-entry.sh and reload-quickshell.sh. This config is published and
# installs wherever someone clones it, not necessarily ~/.config/quicktest — and it
# has to work on a Hyprland setup that looks nothing like the repo author's own.
#
# ── Two config styles, detected the same way Hyprland itself picks one ────────
# Hyprland 0.56 selects its config format by FILE EXTENSION: a Lua config manager
# (hyprland.lua) or the classic hyprlang (hyprland.conf) — never both, and never a
# flag. This repo's own author happens to run Lua, but most Hyprland installs are
# still hyprlang, and this script has no business assuming its own maintainer's
# setup is everyone's. It looks for whichever of the two files is actually there
# and writes that syntax; if neither exists, it prints both rather than guessing.
#
#   ./scripts/install-autostart.sh              install (creates the file, or
#                                                inserts into an existing one)
#   ./scripts/install-autostart.sh --print      show both forms, write nothing
#   ./scripts/install-autostart.sh --uninstall  remove exactly the line this
#                                                script would have inserted
#
# ── Never touches a file it can't confidently understand ──────────────────────
# Lua: it only inserts into an EXISTING hyprland.lua-style autostart file when it
# finds the exact `hl.on("hyprland.start", function()` opening line this repo's
# own copy uses. Hyprland's Lua config can be structured any way its owner likes,
# and guessing at an unfamiliar one risks corrupting a file you didn't write — if
# that anchor isn't found, it prints the line for you to place by hand instead.
# hyprlang has no such scoping to get wrong (`exec-once` is a bare top-level
# directive), so it's appended directly to hyprland.conf.
# A timestamped backup is made before any write, either way.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HYPR_DIR="$CONFIG_HOME/hypr"

LAUNCH_CMD="bash -c 'source $REPO_DIR/scripts/shell-env.sh && exec qs -p $REPO_DIR'"

# Lua form: double-quoted Lua string, single-quoted inner bash -c body — matches
# this repo's own committed autostart.lua. $REPO_DIR came from readlink -f above,
# never user-typed, so it can't break either quoting layer.
LUA_FILE="$HYPR_DIR/autostart.lua"
LUA_ANCHOR='hl.on("hyprland.start", function()'
LUA_LINE="    hl.exec_cmd(\"$LAUNCH_CMD\")"

# hyprlang form: a bare top-level directive, safe to append anywhere in the file.
CONF_FILE="$HYPR_DIR/hyprland.conf"
CONF_LINE="exec-once = $LAUNCH_CMD"

if [ "${1:-}" = "--print" ]; then
    echo "Lua (hyprland.lua), inside your hl.on(\"hyprland.start\", function() ... end):"
    echo "$LUA_LINE"
    echo
    echo "hyprlang (hyprland.conf), anywhere at the top level:"
    echo "$CONF_LINE"
    exit 0
fi

# ── Which style is actually in use ──────────────────────────────────────────────
# hyprland.lua existing is what makes Hyprland load Lua at all, so its presence is
# the authoritative signal — checked first for that reason, not preference.
STYLE=""
if [ -f "$HYPR_DIR/hyprland.lua" ]; then
    STYLE="lua"
elif [ -f "$CONF_FILE" ]; then
    STYLE="conf"
fi

if [ "${1:-}" = "--uninstall" ]; then
    removed=0
    if [ -f "$LUA_FILE" ] && grep -qF "$REPO_DIR/scripts/shell-env.sh" "$LUA_FILE"; then
        cp "$LUA_FILE" "$LUA_FILE.bak.$(date +%s)"
        grep -vF "$REPO_DIR/scripts/shell-env.sh" "$LUA_FILE" > "$LUA_FILE.tmp" \
            && mv "$LUA_FILE.tmp" "$LUA_FILE"
        echo "Removed the line from $LUA_FILE (backup kept alongside it)."
        removed=1
    fi
    if [ -f "$CONF_FILE" ] && grep -qF "$REPO_DIR/scripts/shell-env.sh" "$CONF_FILE"; then
        cp "$CONF_FILE" "$CONF_FILE.bak.$(date +%s)"
        grep -vF "$REPO_DIR/scripts/shell-env.sh" "$CONF_FILE" > "$CONF_FILE.tmp" \
            && mv "$CONF_FILE.tmp" "$CONF_FILE"
        echo "Removed the line from $CONF_FILE (backup kept alongside it)."
        removed=1
    fi
    [ "$removed" = 0 ] && echo "Nothing to remove — no autostart file references this repo."
    exit 0
fi

if [ -z "$STYLE" ]; then
    echo "Couldn't find $HYPR_DIR/hyprland.lua or $CONF_FILE, so there's nothing to tell"
    echo "which config style you're on. Check which of the two files your Hyprland"
    echo "actually loads (its log says \"Config is lua\" or defaults to hyprlang),"
    echo "then add the matching line yourself:"
    echo
    "$0" --print
    exit 1
fi

mkdir -p "$HYPR_DIR" || { echo "Could not create $HYPR_DIR" >&2; exit 1; }

# ── A looser check, before inserting anything ──────────────────────────────────
# The exact-path check only catches a line written the way THIS script writes it.
# A hand-written line pointing at the same shell but spelled with `~` or $HOME
# instead of the resolved path (exactly what this repo's own committed
# autostart.lua has) would sail past an exact match and get a SECOND launch
# inserted alongside the first — two live instances fighting over the
# notification server's port. Looking for the SHAPE of a Quickshell autostart
# line at all, regardless of how the path is spelled, catches that and asks
# rather than risking the duplicate.
_already_present() {
    local f="$1"
    [ -f "$f" ] && grep -qE 'exec qs -p|shell-env\.sh' "$f"
}
_exactly_this_repo() {
    local f="$1"
    [ -f "$f" ] && grep -qF "$REPO_DIR/scripts/shell-env.sh" "$f"
}

if [ "$STYLE" = "lua" ]; then
    if _exactly_this_repo "$LUA_FILE"; then
        echo "Already installed — $LUA_FILE already starts this repo's shell."
        exit 0
    fi
    if _already_present "$LUA_FILE"; then
        echo "$LUA_FILE already has what looks like a Quickshell autostart line, just"
        echo "not spelled with this repo's resolved path — inserting another would start"
        echo "a second instance alongside it. Have a look yourself; the line this script"
        echo "would otherwise add is:"
        echo
        echo "$LUA_LINE"
        exit 1
    fi

    if [ ! -f "$LUA_FILE" ]; then
        cat > "$LUA_FILE" <<EOF
-- ══════════════════════════════════════════════
--  autostart.lua — one-time setup once Hyprland is up
--
--  Keep every hl.exec_cmd inside the hyprland.start callback, never at file
--  scope (it would run before the compositor is ready).
-- ══════════════════════════════════════════════

$LUA_ANCHOR
$LUA_LINE
end)
EOF
        echo "Created $LUA_FILE with the shell's autostart line."
        exit 0
    fi

    if ! grep -qF "$LUA_ANCHOR" "$LUA_FILE"; then
        echo "$LUA_FILE exists but doesn't have the hyprland.start block this script"
        echo "recognizes, so nothing was written (better than guessing wrong on a file"
        echo "someone else's config already lives in). Add this line yourself, inside"
        echo "your own hl.on(\"hyprland.start\", function() ... end) block:"
        echo
        echo "$LUA_LINE"
        exit 1
    fi

    cp "$LUA_FILE" "$LUA_FILE.bak.$(date +%s)"
    awk -v anchor="$LUA_ANCHOR" -v line="$LUA_LINE" '
        { print }
        index($0, anchor) { print line }
    ' "$LUA_FILE" > "$LUA_FILE.tmp" && mv "$LUA_FILE.tmp" "$LUA_FILE"
    echo "Inserted the autostart line into $LUA_FILE (backup kept alongside it)."
    exit 0
fi

# STYLE = conf (classic hyprlang)
if _exactly_this_repo "$CONF_FILE"; then
    echo "Already installed — $CONF_FILE already starts this repo's shell."
    exit 0
fi
if _already_present "$CONF_FILE"; then
    echo "$CONF_FILE already has what looks like a Quickshell autostart line, just"
    echo "not spelled with this repo's resolved path — appending another would start"
    echo "a second instance alongside it. Have a look yourself; the line this script"
    echo "would otherwise add is:"
    echo
    echo "$CONF_LINE"
    exit 1
fi

cp "$CONF_FILE" "$CONF_FILE.bak.$(date +%s)"
{
    echo ""
    echo "# Quickshell (rufss14/Quickshell-Config) autostart"
    echo "$CONF_LINE"
} >> "$CONF_FILE"
echo "Appended the autostart line to $CONF_FILE (backup kept alongside it)."
