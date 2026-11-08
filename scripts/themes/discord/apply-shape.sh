#!/usr/bin/env bash
# ── apply-shape.sh ────────────────────────────────────────────────────────────
# Settings → Type & Shape into every Vencord-family client's Quicktest theme.
#
#     apply-shape.sh '<json>'      the resolved values (see quicktest-theme.py DEFAULT_SHAPE)
#
# Run by services/DiscordTheme.qml, which passes what Tokens/Motion resolved to. A client that
# doesn't have the theme is skipped, so this is a no-op on a machine without Discord or without
# Quicktest. Which clients exist is lib.sh's, shared with theme-setup.sh and apps-lib.sh.
# ─────────────────────────────────────────────────────────────────────────────
set -u
[[ -n "${1:-}" ]] || { echo "usage: apply-shape.sh '<json>'" >&2; exit 2; }
SHELL_DIR="$(cd "$(dirname "$(readlink -f "$0")")/../../.." && pwd)"
# shellcheck source=lib.sh
source "$SHELL_DIR/scripts/themes/discord/lib.sh"

rc=0
while IFS= read -r entry; do
    css="${entry#*:}/themes/quicktest.theme.css"
    [[ -f "$css" ]] || continue
    python3 "$QUICKTEST_PY" --css "$css" --shape "$1" || rc=$?
done < <(discord_clients)
exit "$rc"
