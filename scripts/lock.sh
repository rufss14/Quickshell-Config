#!/usr/bin/env bash
# ── lock.sh ───────────────────────────────────────────────────────────────────
# Lock the session: the shell's own lock screen, or hyprlock when the shell can't.
# What the SUPER+L bind runs (hypr/binds.lua, scripts/templates/quicktest-hypr.lua).
#
# ── Why a fallback at all ─────────────────────────────────────────────────────
# The lock screen lives inside the shell. A shell that has crashed, hung, or is
# halfway through a restart answers no IPC — and a lock key that silently does
# nothing is worse than no lock key, because you walk away believing it worked.
#
# The shell counts only once it reports `locked (secure)` (the compositor confirmed
# the lock surfaces are up). `qs ipc call lock lock` exits 0 as soon as the call is
# delivered, which says nothing about whether the lock then appeared.
#
# hyprlock is Hyprland's own locker (a core dependency for exactly this). If it is
# missing too, a critical notification says the session is NOT locked.
#
# Not covered: lock-before-sleep needs the shell (services/Lock.qml holds the logind
# inhibitor); a dead shell holds none, so a suspend then happens unlocked.
# ─────────────────────────────────────────────────────────────────────────────
set -u
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if timeout 2 qs ipc -p "$repo" call lock lock >/dev/null 2>&1; then
    for _ in $(seq 15); do
        case "$(timeout 1 qs ipc -p "$repo" call lock status 2>/dev/null)" in
            "locked (secure)"*) exit 0 ;;
        esac
        sleep 0.1
    done
fi

if command -v hyprlock >/dev/null 2>&1; then
    hyprlock && exit 0
fi

notify-send --app-name=Quickshell --urgency=critical "The session is NOT locked" \
    "The shell's lock screen didn't come up and hyprlock couldn't run."
exit 1
