#!/usr/bin/env bash
# ── doctor.sh ─────────────────────────────────────────────────────────────────
# One plain-text report to paste into a bug report: what this shell is, what it runs
# on, which packages it wants are missing, how it is running, and its latest warnings.
# Reads only; changes nothing. Settings › About's "Copy diagnostics" runs it and puts
# what it prints on the clipboard (SysInfo.copyDiagnostics).
#
#   bash scripts/doctor.sh           print the report
#
# Made to be pasted in public, so the home directory becomes ~, and the user and host
# names become <user> and <host>, everywhere in it (the log lines too). The board,
# BIOS and boot details from specs.sh are left out: nothing a bug needs, and they
# identify the machine. Every line degrades to "—" rather than failing.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")
DEPS="$SCRIPT_DIR/install-dependencies.sh"

report() {
    declare -A S=()
    local k v
    while IFS='=' read -r k v; do [ -n "$k" ] && S[$k]=$v; done < <(bash "$SCRIPT_DIR/specs.sh" 2>/dev/null)
    f() { printf '%s' "${S[$1]:-—}"; }

    echo "## Quicktest diagnostics"
    echo
    echo "### Shell"
    local ver commit
    ver=$(grep -oP 'readonly property string version: "\K[^"]+' "$REPO_DIR/config/Config.qml" 2>/dev/null)
    echo "- Quicktest ${ver:-—}"
    if commit=$(git -C "$REPO_DIR" describe --always --dirty 2>/dev/null); then
        echo "- git: $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null) @ $commit"
    else
        echo "- not a git checkout (an installed release)"
    fi
    echo "- Quickshell $(f QS_VERSION) ($(f QS_PACKAGER))"
    echo "- Qt $(pacman -Q qt6-base 2>/dev/null | cut -d' ' -f2 || echo —)"
    echo "- folder: $REPO_DIR"

    echo
    echo "### System"
    echo "- $(f DISTRO), kernel $(f KERNEL)"
    echo "- $(f WM_NAME) $(f WM_VERSION) ($(f WM_SESSION)), plugins: $(f WM_PLUGINS)"
    [ -n "${S[WM_LIB_MISMATCH]:-}" ] && echo "- library mismatch: ${S[WM_LIB_MISMATCH]}"
    echo "- Wayland $(f WL_VERSION), portal: $(f WL_PORTAL), XWayland: $(f WL_XWAYLAND)"
    echo "- CPU: $(f CPU) ($(f CORES)), RAM: $(f RAM)"
    echo "- GPU: $(f GPU), driver: $(f DRIVER)"
    echo "- last upgrade: $(f LAST_UPGRADE)"

    echo
    echo "### Packages"
    # pacman -T prints the ones that aren't satisfied (provides count), nothing when all are.
    local -a want; local miss
    read -ra want <<<"$(bash "$DEPS" --official 2>/dev/null)"
    miss=$( ((${#want[@]})) && pacman -T "${want[@]}" 2>/dev/null | tr '\n' ' ')
    echo "- required, missing: ${miss:-none}"
    read -ra want <<<"$(bash "$DEPS" --aur 2>/dev/null)"
    miss=$( ((${#want[@]})) && pacman -T "${want[@]}" 2>/dev/null | tr '\n' ' ')
    echo "- AUR, missing: ${miss:-none}"
    # "key=pkg,pkg key=pkg …": a feature pack is optional, so list only the ones with gaps.
    local packs="" pair key pkgs
    for pair in $(bash "$DEPS" --packs 2>/dev/null); do
        key=${pair%%=*}; pkgs=${pair#*=}
        miss=$(pacman -T ${pkgs//,/ } 2>/dev/null | tr '\n' ' ')
        [ -n "$miss" ] && packs+="  - $key: ${miss% }"$'\n'
    done
    if [ -n "$packs" ]; then printf -- '- optional packs with something missing:\n%s' "$packs"
    else echo "- optional packs: all installed"; fi

    echo
    echo "### Running"
    local pid
    pid=$(pgrep -nx 'qs|quickshell' 2>/dev/null)
    if [ -n "$pid" ]; then
        echo "- shell running (pid $pid), up $(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
        if tr '\0' '\n' <"/proc/$pid/environ" 2>/dev/null | grep -qx 'QS_SAFE=1'; then
            echo "- SAFE MODE: it crashed twice while starting (scripts/shell-run.sh)"
        fi
        if pgrep -f -- "$SCRIPT_DIR/shell-run.sh" >/dev/null 2>&1; then
            echo "- started through shell-run.sh (restarts after a startup crash)"
        else
            echo "- not started through shell-run.sh"
        fi
    else
        echo "- shell NOT running"
    fi
    local wal="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
    [ -s "$wal" ] && echo "- palette: colors.json present" || echo "- palette: no colors.json (monochrome fallback)"

    echo
    echo "### Latest warnings"
    # The running instance's own log, warnings and worse (console.log / info dropped), colour
    # codes stripped, each distinct line once with its count: the 25 most recently seen.
    local log=""
    if [ -n "$pid" ]; then
        log=$(timeout 5 qs log --pid "$pid" -r '*.debug=false;*.info=false' 2>/dev/null \
            | sed -E 's/\x1b\[[0-9;]*m//g; s/^ +//' | tac \
            | awk 'NF { if (!($0 in n)) o[++k] = $0; n[$0]++ }
                   END { for (i = (k < 25 ? k : 25); i >= 1; i--)
                             print o[i] (n[o[i]] > 1 ? "  (x" n[o[i]] ")" : "") }')
    fi
    if [ -n "$log" ]; then
        echo '```'
        printf '%s\n' "$log"
        echo '```'
    else
        echo "- none read"
    fi
}

redact() {
    local text host user
    text=$(cat)
    text=${text//"$HOME"/\~}
    host=$(hostnamectl hostname 2>/dev/null || hostname 2>/dev/null || true)
    user=${USER:-$(id -un 2>/dev/null)}
    # Whole words only, and not names so short they'd eat ordinary text ("a", "pc").
    # User and host names are [A-Za-z0-9._-], so they need no regex escaping beyond '.'.
    [ ${#user} -ge 3 ] && text=$(printf '%s' "$text" | sed -E "s/\\b${user//./\\.}\\b/<user>/g")
    [ ${#host} -ge 3 ] && text=$(printf '%s' "$text" | sed -E "s/\\b${host//./\\.}\\b/<host>/g")
    printf '%s\n' "$text"
}

report | redact
