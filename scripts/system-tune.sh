#!/usr/bin/env bash
# ── system-tune.sh — opt-in system tuning for games and desktop latency ──────────
#
#   sudo scripts/system-tune.sh            apply every item below (idempotent)
#   sudo scripts/system-tune.sh revert     undo exactly what apply did
#        scripts/system-tune.sh status     show each item's state (no root needed)
#
# NOT part of the shell's install, and nothing in this config needs it. Every item is
# a SYSTEM change someone should choose, so it lives here — one reviewable script —
# instead of anywhere the shell could run it by itself. Arch only (pacman, GRUB).
# Items are independent: one failing is reported and the rest still run.
#
# ── What it does ─────────────────────────────────────────────────────────────────
#  1. sysctl   /etc/sysctl.d/90-quicktest-tune.conf
#       vm.dirty_bytes 256 MiB / vm.dirty_background_bytes 64 MiB — instead of 20% /
#         10% of RAM. On 24 GB that let ~4.7 GB of writes pile up before a forced
#         flush, which a Steam download or a shader-cache burst then paid for as a
#         multi-second writeback stall. Small and steady flushes instead. (The same
#         values CachyOS ships.)
#       kernel.nmi_watchdog 0 — a periodic NMI on every CPU that also holds a perf
#         counter. The soft-lockup watchdog stays on.
#  2. lib32-gamemode — so `gamemoderun` works for 32-bit games and launchers
#       instead of an LD_PRELOAD "wrong ELF class" error. Needs [multilib].
#  3. sched_ext: scx_lavd, via scx_loader in "Gaming" mode
#       (--performance --pinned-slice-us 500, scx_loader's own gaming preset).
#       LAVD is the latency-criticality scheduler built for the Steam Deck; it tends
#       to help 1% lows under background load. The kernel ejects a misbehaving BPF
#       scheduler by itself and falls back to its own, and `revert` stops it.
#  4. GRUB menu 5s → 1s — /etc/default/grub AND the two `set timeout=` lines in
#       grub.cfg, edited in place rather than regenerating a grub.cfg this script has
#       never seen. Esc still stops the countdown.
#  5. The GPU half of the Game Mode profile — /etc/gamemode.ini [gpu], which
#       gamemoded refuses from a user-writable file. See scripts/gamemode-profile.py.
#
# ── What it deliberately does NOT do ─────────────────────────────────────────────
#  · NVMe I/O scheduler. linux-zen already puts kyber on multi-queue devices, and on
#    a fast NVMe kyber costs next to nothing while holding reads to a latency target
#    under heavy writes — which is what a game streaming assets during a download
#    wants. `none` would be a trade, not a win.
#  · mitigations=off. A real few percent in syscall-heavy loads, and a security
#    decision this script has no business making for anyone.
#  · irqbalance / ananicy. Single-socket desktop; LAVD already does the job ananicy's
#    renicing approximates.
# ─────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYSCTL_FILE=/etc/sysctl.d/90-quicktest-tune.conf
SCX_CONF=/etc/scx_loader/config.toml
STATE_DIR=/var/lib/quicktest-tune
GRUB_DEFAULT=/etc/default/grub
GRUB_CFG=/boot/grub/grub.cfg
TAG="written by quicktest scripts/system-tune.sh"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
skip() { printf '  \033[2m· %s\033[0m\n' "$*"; }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$*"; FAILED=1; }
FAILED=0

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "system-tune.sh: '$1' changes system files — run it with sudo." >&2
        exit 1
    fi
}

# The invoking user's session bus, for asking THEIR gamemoded to re-read its config.
# Root has no session bus of its own (and gdbus would try to autolaunch one).
as_user_refresh_gamemode() {
    [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ] || return 0
    local uid; uid="$(id -u "$SUDO_USER")" || return 0
    runuser -u "$SUDO_USER" -- env DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
        gdbus call --session --dest com.feralinteractive.GameMode \
        --object-path /com/feralinteractive/GameMode \
        --method com.feralinteractive.GameMode.RefreshConfig >/dev/null 2>&1 || true
}

# ── 1. sysctl ────────────────────────────────────────────────────────────────────
sysctl_apply() {
    cat > "$SYSCTL_FILE" <<EOF
# $TAG — \`system-tune.sh revert\` removes it.
# Writeback in small, steady flushes instead of a multi-GB burst (see the script).
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
# The NMI watchdog: a periodic NMI per CPU, plus a held perf counter.
kernel.nmi_watchdog = 0
EOF
    if sysctl -q -p "$SYSCTL_FILE"; then ok "sysctl: dirty writeback capped, NMI watchdog off"
    else bad "sysctl: $SYSCTL_FILE written but not applied — it will apply at boot"; fi
}
sysctl_revert() {
    if [ -f "$SYSCTL_FILE" ]; then
        rm -f "$SYSCTL_FILE"
        # Kernel defaults first (dirty_bytes and dirty_ratio are two views of one knob:
        # writing the ratio zeroes the bytes), then every remaining sysctl.d file again
        # so anything else the system sets still wins.
        sysctl -q -w vm.dirty_ratio=20 vm.dirty_background_ratio=10 kernel.nmi_watchdog=1
        sysctl -q --system
        ok "sysctl: back to defaults"
    else skip "sysctl: nothing to revert"; fi
}

# ── 2. lib32-gamemode ────────────────────────────────────────────────────────────
lib32_apply() {
    if ! pacman-conf --repo-list 2>/dev/null | grep -qx multilib; then
        skip "lib32-gamemode: [multilib] is not enabled"; return
    fi
    if pacman -S --needed --noconfirm lib32-gamemode >/dev/null; then ok "lib32-gamemode installed"
    else bad "lib32-gamemode: pacman failed (is another pacman running?)"; fi
}

# ── 3. sched_ext / scx_lavd ──────────────────────────────────────────────────────
scx_apply() {
    if [ ! -d /sys/kernel/sched_ext ]; then
        skip "sched_ext: this kernel has no sched_ext support"; return
    fi
    if ! pacman -S --needed --noconfirm scx-scheds scx-tools >/dev/null; then
        bad "sched_ext: pacman failed (is another pacman running?)"; return
    fi
    mkdir -p "$(dirname "$SCX_CONF")"
    cat > "$SCX_CONF" <<EOF
# $TAG — \`system-tune.sh revert\` removes it.
default_sched = "scx_lavd"
default_mode = "Gaming"
EOF
    systemctl enable scx_loader.service >/dev/null 2>&1
    systemctl restart scx_loader.service
    local i state="" ops=""
    for i in 1 2 3 4 5 6 7 8 9 10; do
        state="$(cat /sys/kernel/sched_ext/state 2>/dev/null)"
        ops="$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null)"
        [ "$state" = enabled ] && break
        sleep 0.5
    done
    if [ "$state" = enabled ]; then ok "sched_ext: $ops running (scx_loader, Gaming mode, starts at boot)"
    else bad "sched_ext: scx_loader enabled but the scheduler is '$state' — see: journalctl -u scx_loader"; fi
}
scx_revert() {
    if systemctl is-enabled scx_loader.service >/dev/null 2>&1 || [ -f "$SCX_CONF" ]; then
        systemctl disable --now scx_loader.service >/dev/null 2>&1
        if [ -f "$SCX_CONF" ] && grep -qF "$TAG" "$SCX_CONF"; then
            rm -f "$SCX_CONF"; rmdir "$(dirname "$SCX_CONF")" 2>/dev/null
        fi
        ok "sched_ext: stopped — the kernel's own scheduler is back (packages kept;"\
" 'pacman -Rs scx-tools scx-scheds' to remove)"
    else skip "sched_ext: nothing to revert"; fi
}

# ── 4. GRUB timeout ──────────────────────────────────────────────────────────────
grub_apply() {
    if [ ! -f "$GRUB_DEFAULT" ] || [ ! -f "$GRUB_CFG" ]; then skip "GRUB: not in use"; return; fi
    local cur; cur="$(sed -n 's/^GRUB_TIMEOUT=\([0-9]\+\)$/\1/p' "$GRUB_DEFAULT" | head -1)"
    if [ -z "$cur" ]; then skip "GRUB: no plain GRUB_TIMEOUT line to change"; return; fi
    if [ "$cur" = 1 ]; then skip "GRUB: already 1s"; return; fi
    mkdir -p "$STATE_DIR"
    [ -f "$STATE_DIR/grub_timeout" ] || echo "$cur" > "$STATE_DIR/grub_timeout"
    sed -i "s/^GRUB_TIMEOUT=$cur$/GRUB_TIMEOUT=1/" "$GRUB_DEFAULT"
    sed -i "s/^\(\s*\)set timeout=$cur$/\1set timeout=1/" "$GRUB_CFG"
    if grep -q '^\s*set timeout=1$' "$GRUB_CFG"; then ok "GRUB: menu timeout ${cur}s → 1s"
    else bad "GRUB: /etc/default/grub set, but grub.cfg had no 'set timeout=$cur' line"; fi
}
grub_revert() {
    if [ ! -f "$STATE_DIR/grub_timeout" ]; then skip "GRUB: nothing to revert"; return; fi
    local prev; prev="$(cat "$STATE_DIR/grub_timeout")"
    sed -i "s/^GRUB_TIMEOUT=1$/GRUB_TIMEOUT=$prev/" "$GRUB_DEFAULT"
    sed -i "s/^\(\s*\)set timeout=1$/\1set timeout=$prev/" "$GRUB_CFG"
    rm -f "$STATE_DIR/grub_timeout"; rmdir "$STATE_DIR" 2>/dev/null
    ok "GRUB: menu timeout back to ${prev}s"
}

# ── 5. Game Mode profile, GPU half ───────────────────────────────────────────────
gpu_apply() {
    python3 "$REPO/scripts/gamemode-profile.py" install --system
    case $? in
        0) as_user_refresh_gamemode; ok "Game Mode: GPU held at full clocks during games (/etc/gamemode.ini)" ;;
        3) skip "Game Mode GPU profile: no amdgpu card with DPM control" ;;
        *) bad "Game Mode GPU profile: gamemode-profile.py failed" ;;
    esac
}
gpu_revert() {
    if python3 "$REPO/scripts/gamemode-profile.py" remove --system; then
        as_user_refresh_gamemode; ok "Game Mode: GPU half removed"
    else bad "Game Mode GPU profile: gamemode-profile.py remove failed"; fi
}

# ── status ───────────────────────────────────────────────────────────────────────
status() {
    echo "sysctl:        dirty_bytes=$(sysctl -n vm.dirty_bytes) dirty_background_bytes=$(sysctl -n vm.dirty_background_bytes)" \
         "nmi_watchdog=$(sysctl -n kernel.nmi_watchdog)  $( [ -f "$SYSCTL_FILE" ] && echo '(tuned)' || echo '(default)')"
    echo "lib32-gamemode: $(pacman -Q lib32-gamemode 2>/dev/null || echo 'not installed')"
    echo "sched_ext:     state=$(cat /sys/kernel/sched_ext/state 2>/dev/null || echo n/a)" \
         "ops=$(cat /sys/kernel/sched_ext/root/ops 2>/dev/null || echo none)" \
         "loader=$(systemctl is-enabled scx_loader.service 2>/dev/null || true)"
    echo "GRUB:          $(grep -E '^GRUB_TIMEOUT=' "$GRUB_DEFAULT" 2>/dev/null || echo 'n/a')"
    echo "gamemode GPU:  $(grep -A5 'quicktest:gamemode' /etc/gamemode.ini 2>/dev/null | grep -E '^amd_performance_level' || echo 'not set up')"
}

case "${1:-apply}" in
    apply)
        need_root apply
        echo "Applying (each item is independent):"
        sysctl_apply; lib32_apply; scx_apply; grub_apply; gpu_apply
        ;;
    revert)
        need_root revert
        echo "Reverting:"
        gpu_revert; grub_revert; scx_revert; sysctl_revert
        skip "lib32-gamemode kept (a library; 'pacman -Rs lib32-gamemode' to remove)"
        ;;
    status) status ;;
    *) echo "usage: system-tune.sh [apply|revert|status]" >&2; exit 2 ;;
esac
exit "$FAILED"
