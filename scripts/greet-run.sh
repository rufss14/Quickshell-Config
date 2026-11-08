#!/bin/sh
# greet-run.sh — run the greeter, and GUARANTEE the compositor follows it down.
#
# Launched by /etc/greetd/greet-session.lua as the greeter session's only command.
#
# ── Why this is a script and not one inline exec_cmd ─────────────────────────
# It used to be `qs … ; hyprctl dispatch exit` inline in the Lua config, and that is
# where five seconds of every single login were going.
#
# greetd does not start your session until the greeter's SESSION ends — not until the
# greeter process ends, the whole session, which here means Hyprland. It waits for
# that with a five-second timeout and then force-kills. Measured, repeatedly, to the
# millisecond: 5.005s, 5.01s, 5.048s. That is not a slow shutdown, that is a timeout
# being paid in full because nothing was bringing the compositor down.
#
# Quickshell exits correctly now (SIGTERM, ~104ms, measured). The compositor did not
# follow it, so `hyprctl dispatch exit` was not doing its job — and inline there was
# no way to find out why, because the greeter's whole /run/user/961 is destroyed by
# the login succeeding.
#
# So: every step is timestamped into a log that outlives the session, and there is a
# backstop that does not depend on hyprctl working at all.

LOG=/var/lib/greeter/greet.log
SHELL_QML=/var/lib/greeter/shell/greet.qml

: > "$LOG" 2>/dev/null || LOG=/dev/null

T0=$(date +%s%N)
stamp() {
    printf '[wrapper +%sms] %s\n' "$(( ($(date +%s%N) - T0) / 1000000 ))" "$1" >> "$LOG"
}

# The two facts that decide whether hyprctl can possibly work, recorded BEFORE we need
# them. hyprctl finds its socket through HYPRLAND_INSTANCE_SIGNATURE; if the Lua
# config's exec_cmd does not propagate that the way hyprlang's exec-once did, hyprctl
# is a no-op and this line is the proof.
stamp "start  HIS=${HYPRLAND_INSTANCE_SIGNATURE:-UNSET}  hyprctl=$(command -v hyprctl 2>/dev/null || echo MISSING)"

qs -p "$SHELL_QML" >> "$LOG" 2>&1
stamp "qs exited rc=$?"

# ── The polite way first ─────────────────────────────────────────────────────
# If HIS is unset or the socket is unreachable, hyprctl fails and says so, and rc tells
# us not to spend any grace period waiting for something that was never accepted.
hyprctl_ok=0
if command -v hyprctl >/dev/null 2>&1; then
    # The Lua spelling. greet-session.lua is a Lua config, and under the Lua config
    # manager the legacy bare word `exit` is not a dispatcher — the request is rejected,
    # the compositor stays up, and everything falls to the backstop below.
    out=$(hyprctl dispatch 'hl.dsp.exit()' 2>&1)
    rc=$?
    stamp "hyprctl dispatch hl.dsp.exit() rc=$rc out=[$out]"
    [ "$rc" -eq 0 ] && hyprctl_ok=1
else
    stamp "hyprctl not found — going straight to the backstop"
fi

# ── The backstop ─────────────────────────────────────────────────────────────
# GUARDED ON GREETD_SOCK, and that guard is not optional. This script must never run
# outside a real greeter session: scripts/greet-preview.lua runs the greeter NESTED
# inside your own desktop, and an unguarded `pkill -x Hyprland` there would kill the
# compositor you are sitting in front of. greetd sets GREETD_SOCK for the session it
# starts and nothing else does, so its presence is the one honest test for "am I the
# login screen". The -u restricts the kill to our own uid on top of that.
#
# Reaching this point at all means Hyprland outlived hyprctl — if the dispatch had
# worked the compositor would already be gone, and this script with it.
if [ -z "${GREETD_SOCK:-}" ]; then
    stamp "not under greetd (preview) — leaving the compositor alone"
    exit 0
fi

# A grace period only makes sense if the dispatch was actually ACCEPTED. When hyprctl
# has already told us it failed, waiting is pure added latency on every login — the
# exact mistake that made this five seconds in the first place.
if [ "$hyprctl_ok" -eq 1 ]; then
    i=0
    while [ "$i" -lt 5 ]; do
        pgrep -x Hyprland >/dev/null 2>&1 || { stamp "compositor gone"; exit 0; }
        i=$((i + 1))
        sleep 0.1
    done
    stamp "accepted but still up after 500ms — SIGTERM"
else
    stamp "dispatch did not take — SIGTERM immediately"
fi

pkill -TERM -u "$(id -u)" -x Hyprland
stamp "pkill rc=$?"
