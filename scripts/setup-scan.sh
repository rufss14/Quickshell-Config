#!/usr/bin/env bash
# ── setup-scan.sh ─────────────────────────────────────────────────────────────
# What this machine is, for the setup plan (services/Setup.qml → services/setupplan.js `parseScan`).
# READ-ONLY: it changes nothing and needs no password. Prints `key=value` lines, one fact each; a fact
# it cannot find is simply left out (the reader has a default for every one).
#
#   setup-scan.sh                  everything below
#
#   distro         /etc/os-release ID
#   arch           1 when pacman exists
#   network        1 / 0 — can archlinux.org be resolved (a 2s check); left out when it can't be asked
#   pacmanLock     1 when /var/lib/pacman/db.lck exists
#   pacmanRunning  1 when a pacman is running now
#   diskMiB        free space where packages go (/)
#   sudo           1 when `sudo` exists
#   polkitAgent    1 when a polkit authentication agent is running (the shell's own is the reader's to add)
#   quickshell / hyprland / qt   versions, "0.3.2"
#   gpu, vulkan, nvidiaProprietary   from install-dependencies.sh --vulkan (one source for the driver choice)
#   aurHelper      yay | paru | none
#   blobInstalled  1 when the Morph plugin's files are in the system Qt dir (whether it LOADS is the shell's to say)
#
# Tested by hand against this machine; the reader (setupplan.js) is tested by scripts/test-setupplan.js.
# ─────────────────────────────────────────────────────────────────────────────
set -u
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# shellcheck disable=SC1091
[ -r /etc/os-release ] && . /etc/os-release
echo "distro=${ID:-}"

if command -v pacman >/dev/null 2>&1; then echo "arch=1"; else echo "arch=0"; fi

# A name lookup, not a download: quick, and it fails the way a dead network fails.
if command -v getent >/dev/null 2>&1; then
    if timeout 2 getent hosts archlinux.org >/dev/null 2>&1; then echo "network=1"; else echo "network=0"; fi
fi

[ -e /var/lib/pacman/db.lck ] && echo "pacmanLock=1" || echo "pacmanLock=0"
pgrep -x pacman >/dev/null 2>&1 && echo "pacmanRunning=1" || echo "pacmanRunning=0"

d=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}')
[ -n "${d:-}" ] && echo "diskMiB=$d"

command -v sudo >/dev/null 2>&1 && echo "sudo=1" || echo "sudo=0"

# `comm` is cut to 15 characters by the kernel, hence the prefixes.
if ps -eo comm= 2>/dev/null | grep -qE '^(hyprpolkitagent|polkit-gnome-au|polkit-kde-auth|lxqt-policykit|xfce-polkit|polkit-mate-aut)'; then
    echo "polkitAgent=1"
else
    echo "polkitAgent=0"
fi

v=$(quickshell --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); [ -n "$v" ] && echo "quickshell=$v"
v=$(hyprctl version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 | tr -d v); [ -n "$v" ] && echo "hyprland=$v"
v=$(pacman -Q qt6-base 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); [ -n "$v" ] && echo "qt=$v"

# The driver choice lives in install-dependencies.sh, so the plan and the install cannot disagree about it.
bash "$HERE/install-dependencies.sh" --vulkan 2>/dev/null

if   command -v paru >/dev/null 2>&1; then echo "aurHelper=paru"
elif command -v yay  >/dev/null 2>&1; then echo "aurHelper=yay"
else echo "aurHelper=none"; fi

[ -e /usr/lib/qt6/qml/Quicktest/Blobs/qmldir ] && echo "blobInstalled=1" || echo "blobInstalled=0"
