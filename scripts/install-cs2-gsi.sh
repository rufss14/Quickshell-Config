#!/usr/bin/env bash
# ── install-cs2-gsi.sh ────────────────────────────────────────────────────────
# Turn on Counter-Strike 2's Game State Integration feed so scripts/cs2-presence.py
# can see the match you're in.
#
#   ./scripts/install-cs2-gsi.sh                 install (default port 3000)
#   ./scripts/install-cs2-gsi.sh --port 3555     install on a different port
#   ./scripts/install-cs2-gsi.sh --print         show what would be written
#   ./scripts/install-cs2-gsi.sh --uninstall     remove it again
#   ./scripts/install-cs2-gsi.sh --dir <cfgdir>  point at a cfg dir by hand
#
# ── What it writes, and where ────────────────────────────────────────────────
# Two files:
#   <CS2>/game/csgo/cfg/gamestate_integration_quickshell.cfg   read by the GAME
#   $XDG_CONFIG_HOME/quicktest/cs2-gsi.json                    read by the DAEMON
# The second just tells the daemon which port and token the first one uses, so the
# two can't drift. A random token is generated on install and checked on every POST
# — the endpoint is loopback-only, but that stops another local process spoofing
# game state onto your Discord profile.
#
# ── Finding CS2 ─────────────────────────────────────────────────────────────
# Steam's own steamapps/libraryfolders.vdf lists every library; CS2's folder is still
# called "Counter-Strike Global Offensive" (appid 730 never changed). Each candidate
# library is checked for that folder and the first hit wins. `--dir` overrides the
# search for an install this can't find (a non-standard Steam, Flatpak, a second PC's
# drive mounted in).
#
# GSI is an official, read-only, VAC-safe feature — the same feed every CS scoreboard
# overlay uses. This script only ever adds one .cfg and can remove exactly it again;
# it never touches autoexec, video settings or anything else in the cfg directory.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
# Outside the repo (scripts/qspaths.py): a 0700 dir under XDG_STATE_HOME. The old place
# is removed on install/uninstall so the two can't disagree.
DAEMON_CFG="${XDG_STATE_HOME:-$HOME/.local/state}/quicktest/secrets/cs2-gsi.json"
LEGACY_CFG="$CONFIG_HOME/quicktest/cs2-gsi.json"

CFG_NAME="gamestate_integration_quickshell.cfg"
PORT=3000
CFG_DIR=""
ACTION="install"

while [ $# -gt 0 ]; do
    case "$1" in
        --port)      PORT="${2:?--port needs a number}"; shift 2 ;;
        --dir)       CFG_DIR="${2:?--dir needs a path}"; shift 2 ;;
        --print)     ACTION="print"; shift ;;
        --uninstall) ACTION="uninstall"; shift ;;
        -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

case "$PORT" in
    ''|*[!0-9]*) echo "port must be a number, got: $PORT" >&2; exit 2 ;;
esac

# ── Locate CS2's cfg directory ───────────────────────────────────────────────
find_cfg_dir() {
    [ -n "$CFG_DIR" ] && { printf '%s\n' "$CFG_DIR"; return; }

    local rel="steamapps/common/Counter-Strike Global Offensive/game/csgo/cfg"
    local libs=() vdf line p

    for vdf in \
        "$HOME/.local/share/Steam/steamapps/libraryfolders.vdf" \
        "$HOME/.steam/steam/steamapps/libraryfolders.vdf" \
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf"
    do
        [ -f "$vdf" ] || continue
        while IFS= read -r line; do
            libs+=("$line")
        done < <(grep -oE '"path"[[:space:]]+"[^"]+"' "$vdf" | sed -E 's/.*"path"[[:space:]]+"([^"]+)".*/\1/')
    done
    libs+=("$HOME/.local/share/Steam" "$HOME/.steam/steam" \
           "$HOME/.var/app/com.valvesoftware.Steam/data/Steam")

    for p in "${libs[@]}"; do
        if [ -d "$p/$rel" ]; then
            printf '%s\n' "$p/$rel"
            return
        fi
    done
    return 1
}

# ── The .cfg body (VDF). Port is substituted; token is the caller's ──────────
cfg_body() {
    local token="$1"
    cat <<EOF
"Quickshell CS2 Presence"
{
	"uri"		"http://127.0.0.1:$PORT"
	"timeout"	"5.0"
	"buffer"	"0.1"
	"throttle"	"0.5"
	"heartbeat"	"15.0"
	"auth"
	{
		"token"		"$token"
	}
	"data"
	{
		"provider"			"1"
		"map"				"1"
		"round"				"1"
		"player_id"			"1"
		"player_state"		"1"
		"player_match_stats"	"1"
	}
}
EOF
}

if [ "$ACTION" = "print" ]; then
    echo "# $CFG_NAME  (in CS2's game/csgo/cfg/):"
    cfg_body "<generated-on-install>"
    echo
    echo "# $DAEMON_CFG:"
    echo "{\"port\": $PORT, \"token\": \"<generated-on-install>\"}"
    exit 0
fi

DIR="$(find_cfg_dir)" || {
    echo "Couldn't find Counter-Strike 2. Looked through your Steam libraries for" >&2
    echo "  steamapps/common/Counter-Strike Global Offensive/game/csgo/cfg" >&2
    echo "Pass the cfg directory yourself:  $0 --dir /path/to/.../csgo/cfg" >&2
    exit 1
}
TARGET="$DIR/$CFG_NAME"

if [ "$ACTION" = "uninstall" ]; then
    removed=0
    if [ -f "$TARGET" ]; then
        rm -f "$TARGET" && { echo "Removed $TARGET"; removed=1; }
    fi
    rm -f "$LEGACY_CFG"
    if [ -f "$DAEMON_CFG" ]; then
        rm -f "$DAEMON_CFG" && { echo "Removed $DAEMON_CFG"; removed=1; }
    fi
    [ "$removed" = 0 ] && echo "Nothing to remove."
    echo "Restart CS2 for it to stop sending the feed."
    exit 0
fi

# ── Install ─────────────────────────────────────────────────────────────────
# A fresh token every install. The daemon re-reads cs2-gsi.json on its poll tick, so
# it picks the new one up without a restart; CS2 only reads the .cfg at startup.
TOKEN="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)"

[ -f "$TARGET" ] && cp "$TARGET" "$TARGET.bak.$(date +%s)"
cfg_body "$TOKEN" > "$TARGET" || { echo "Could not write $TARGET" >&2; exit 2; }

mkdir -p -m 700 "$(dirname "$DAEMON_CFG")"
rm -f "$LEGACY_CFG"
umask 077
printf '{"port": %s, "token": "%s"}\n' "$PORT" "$TOKEN" > "$DAEMON_CFG" \
    || { echo "Could not write $DAEMON_CFG" >&2; exit 2; }

echo "Wrote $TARGET"
echo "Wrote $DAEMON_CFG  (port $PORT)"
echo
echo "Restart CS2 if it's running — it reads the .cfg only at launch."
echo "Then enable \"Counter-Strike 2 presence\" in the shell's Discord settings."
