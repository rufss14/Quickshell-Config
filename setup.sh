#!/usr/bin/env bash
# ── setup.sh ─── the one setup command for this shell on a fresh Arch machine.
#   ./setup.sh              packages, then ask about the optional extras
#   ./setup.sh --packages   packages only
#   ./setup.sh --yes        yes to every prompt
# Safe to re-run; every step is idempotent. Settings → Setup mirrors all of this.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SCRIPTS="$REPO_DIR/scripts"

PACKAGES_ONLY=0; ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --packages) PACKAGES_ONLY=1 ;;
        --yes|-y)   ASSUME_YES=1 ;;
        -h|--help)  sed -n '2,6p' "$(readlink -f "$0")"; exit 0 ;;
        *) echo "setup.sh: unknown argument '$arg'" >&2; exit 2 ;;
    esac
done

command -v pacman >/dev/null || { echo "setup.sh needs Arch Linux (pacman)." >&2; exit 1; }

B=$'\033[1m'; DIM=$'\033[2m'; CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'
YEL=$'\033[1;33m'; R=$'\033[0m'

step() { printf '\n%s▸ %s%s\n' "$CYAN" "$1" "$R"; }
note() { printf '%s%s%s\n' "$DIM" "$1" "$R"; }
ask()  {
    [ "$ASSUME_YES" = 1 ] && return 0
    local r; read -rp "$YEL$1$R ${DIM}[y/N]${R} " r
    [[ "$r" =~ ^[Yy] ]]
}

LAUNCH="\"$SCRIPTS/shell-run.sh\""

printf '%sQuickshell setup%s  %s%s%s\n' "$B" "$R" "$DIM" "$REPO_DIR" "$R"

step "Packages"
bash "$SCRIPTS/install-dependencies.sh"

# ── Versions this config was last checked against ──────────────────────────────
# Quickshell and Hyprland both change under you between releases (Hyprland's Lua config
# especially), so say so rather than let a mismatch show up as a broken bar. Warn only:
# a newer one very likely works, and refusing would be worse than the warning.
check_version() {   # check_version NAME ACTUAL TESTED-PREFIX
    local name=$1 have=$2 want=$3
    if [ -z "$have" ]; then note "$name: not found (the package step may have skipped it)"
    elif [[ "$have" == "$want"* ]]; then note "$name $have"
    else printf '%s%s %s — this config was last checked on %sx; expect rough edges%s\n' "$YEL" "$name" "$have" "$want" "$R"; fi
}
step "Versions"
check_version Quickshell "$(quickshell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" "0.3."
check_version Hyprland   "$(hyprctl version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v)" "0.56."
check_version Qt         "$(pacman -Q qt6-base 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)" "6.11."

if [ "$PACKAGES_ONLY" = 0 ]; then
    step "Blob plugin"
    note "Bar/panel metaball fusion. Installs into the system Qt dir (needs root)."
    ask "Build it?" && { bash "$SCRIPTS/build-blobs-plugin.sh" || note "skipped — the shell runs without it"; }

    step "Hyprland config"
    note "Monitors, keybinds, rules, shared blend.lua. Your config is backed up first."
    if ask "Install the bundled config?"; then
        bash "$SCRIPTS/install-hypr-config.sh" || note "skipped"
    elif ask "Just add the autostart line to your own config?"; then
        bash "$SCRIPTS/install-autostart.sh" || note "skipped"
    fi
fi

step "Done"
printf '%sLaunch:%s  %s\n' "$GREEN" "$R" "$LAUNCH"
note "Spotify, Discord and animated wallpapers: Settings → Setup, in the shell."
