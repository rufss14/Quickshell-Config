#!/usr/bin/env bash
# ── workspace-apps.sh ─────────────────────────────────────────────────────────
# Restyle Discord and/or Spotify from a GIVEN palette — a workspace's own (services/
# WorkspaceTheme), not the committed one — through the very functions the wave uses
# (scripts/apps-lib.sh): Vencord's script on a private copy of its theme, swapped in
# by rename; Spicetify's pwspice + refresh, then the bridge's /restyle. No wave, no
# commit, nothing else touched.
#
#     workspace-apps.sh PALETTE [discord] [spotify]
#
# PALETTE must be a colors.json this shell made (the ws-palettes cache or the live
# one). Every step is non-fatal; STEP lines on stdout, the detail in the log.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

PALETTE="${1:-}"
shift || true
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG="$CACHE/quicktest-workspace-apps.log"
ROOT="$CACHE/quickshell-quicktest/ws-palettes"
STAGE="$CACHE/quickshell-quicktest/ws-apps"

real="$(realpath -e -- "$PALETTE" 2>/dev/null)" || { echo "STEP=args|fail|No palette"; exit 2; }
case "$real" in
    "$(realpath -m -- "$ROOT")"/*|"$(realpath -m -- "$CACHE/wal/colors.json")") ;;
    *) echo "STEP=args|fail|Not a palette this shell made"; exit 2 ;;
esac

step() {
    local id="$1" text="$2"; shift 3
    echo "STEP=$id|run|$text"
    if "$@" >>"$LOG" 2>&1; then echo "STEP=$id|ok|$text"; return 0; fi
    echo "STEP=$id|fail|$text"; return 1
}
skip() { echo "STEP=$1|skip|$2"; }
have() { command -v "$1" >/dev/null 2>&1; }

: > "$LOG"
# apps-lib.sh reads the palette from $STAGE/out/colors.json and stages into $STAGE/apps.
rm -rf -- "${STAGE:?}"
mkdir -p "$STAGE/out" "$STAGE/apps"
cp -f -- "$real" "$STAGE/out/colors.json"
# shellcheck source=apps-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/apps-lib.sh"

for app in "$@"; do
    case "$app" in
        discord) if prep_discord >>"$LOG" 2>&1; then publish_discord || skip discord "No Vencord theme"
                 else skip discord "Vencord's script failed"; fi ;;
        spotify) if prep_spotify >>"$LOG" 2>&1; then publish_spotify
                 else skip spotify "Spicetify isn't listening"; fi ;;
        *) echo "STEP=args|fail|Unknown app $app" ;;
    esac
done
exit 0
