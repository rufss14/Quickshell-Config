#!/usr/bin/env bash
# ── specs.sh ──────────────────────────────────────────────────────────────────
# Machine specs for the settings About page, as KEY=value lines on stdout.
#
# One process for the whole page. The alternative — a Process per field — would be
# ten shells to fill one static panel, and QML would have to reassemble them anyway.
#
# Displays are NOT here: the shell already has every monitor, live, from Hyprland
# via the Hypr service. Shelling out for something we're already subscribed to
# would be a second source of truth that goes stale the moment you unplug a screen.
#
# Every field degrades to an empty value rather than failing: this page is
# informational, and a missing GPU line is not a reason to show nothing at all.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

emit() { printf '%s=%s\n' "$1" "${2:-}"; }

# ── System ───────────────────────────────────────────────────────────────────
emit HOST   "$(hostnamectl hostname 2>/dev/null || hostname 2>/dev/null)"
emit DISTRO "$(. /etc/os-release 2>/dev/null && printf '%s' "${PRETTY_NAME:-}")"
emit KERNEL "$(uname -r)"

# ── Distro logo ──────────────────────────────────────────────────────────────
# os-release declares LOGO= (an icon NAME, per the freedesktop spec — "archlinux-logo"
# here). Resolving it rather than hardcoding a path is what makes this page work on a
# machine that isn't this one; the About page just gets a file or an empty string.
#
# Searched widest-first: pixmaps holds the classic distro logos, hicolor is where a
# theme-installed one lands. SVG before PNG — this gets drawn at 96px and a 48px PNG
# upscales to mush.
logo_name=$(. /etc/os-release 2>/dev/null && printf '%s' "${LOGO:-}")
if [[ -n "$logo_name" ]]; then
    for candidate in \
        "/usr/share/pixmaps/${logo_name}.svg" \
        "/usr/share/icons/hicolor/scalable/apps/${logo_name}.svg" \
        "/usr/share/pixmaps/${logo_name}.png" \
        "/usr/share/icons/hicolor/256x256/apps/${logo_name}.png"
    do
        [[ -r "$candidate" ]] && { emit LOGO "$candidate"; break; }
    done
fi

# ── Compositor ───────────────────────────────────────────────────────────────
# `hyprctl version` in one shot, parsed here rather than in QML — same reason as
# everything else in this file: one process for the page.
#
# It needs HYPRLAND_INSTANCE_SIGNATURE from the environment, which is there because
# the shell is a Hyprland client. Off Hyprland every field below comes out empty and
# the About page hides the card, which is the correct outcome rather than a failure.
#
# NOT taken from the Hypr service: that's a live subscription to monitors and
# workspaces, and the compositor's build info is static for the life of the session.
# Adding a version query to an event-driven service would be a Process for a constant.
if command -v hyprctl >/dev/null 2>&1; then
    hypr_ver=$(hyprctl version 2>/dev/null)
    if [[ -n "$hypr_ver" ]]; then
        emit WM_NAME    "Hyprland"
        emit WM_SESSION "${XDG_SESSION_TYPE:-}"

        # "Hyprland 0.55.4 built from branch v0.55.4 at commit abc123... clean (msg)."
        head_line=$(printf '%s' "$hypr_ver" | head -1)
        emit WM_VERSION "$(printf '%s' "$head_line" | sed -n 's/^Hyprland \([^ ]*\) .*/\1/p')"
        emit WM_BRANCH  "$(printf '%s' "$head_line" | sed -n 's/.*from branch \(.*\) at commit.*/\1/p')"
        # Short commit: the full 40 chars is noise on a panel, and the first 8 is what
        # you'd paste into a bug report anyway.
        emit WM_COMMIT  "$(printf '%s' "$head_line" | sed -n 's/.*at commit \([0-9a-f]\{8\}\).*/\1/p')"
        # "clean" or "dirty" — whether the build had uncommitted changes. Worth showing:
        # it's the difference between "0.55.4" and "0.55.4 plus whatever was in my tree".
        emit WM_DIRTY   "$(printf '%s' "$head_line" | grep -oE ' (clean|dirty) ' | tr -d ' ')"

        emit WM_DATE    "$(printf '%s' "$hypr_ver" | sed -n 's/^Date: //p' | head -1)"
        emit WM_COMMITS "$(printf '%s' "$hypr_ver" | sed -n 's/^Tag: .*commits: \([0-9]*\).*/\1/p' | head -1)"

        # Libraries: "Name: built against X, system has Y".
        # Reported as "system has", because that's the one actually loaded — but a
        # DIVERGENCE is called out separately. This machine really does run Aquamarine
        # 0.12.1 against a Hyprland built for 0.12.0, and a mismatched compositor
        # backend is precisely the thing you want named on an About page when something
        # is behaving oddly, rather than buried in a version string nobody reads.
        libs=$(printf '%s' "$hypr_ver" | sed -n \
            's/^\([A-Za-z]*\): built against \([^,]*\), system has \(.*\)$/\1 \3/p' \
            | paste -sd'|' - | tr '|' '\n' | paste -sd',' - | sed 's/,/  ·  /g')
        emit WM_LIBS "$libs"

        mism=$(printf '%s' "$hypr_ver" | awk -F'[:,] *' \
            '/built against/ { split($0, a, "built against "); split(a[2], b, ", system has ");
                               gsub(/^[ \t]+|[ \t]+$/, "", b[1]); gsub(/^[ \t]+|[ \t]+$/, "", b[2]);
                               if (b[1] != b[2]) { split($0, n, ":"); printf "%s (built %s, running %s) ", n[1], b[1], b[2] } }')
        emit WM_LIB_MISMATCH "$(printf '%s' "$mism" | sed 's/[[:space:]]*$//')"

        # Third-party plugins change the compositor's behaviour, so "which are loaded"
        # belongs next to "which version is it".
        if plugins=$(hyprctl plugin list 2>/dev/null); then
            emit WM_PLUGINS "$(printf '%s' "$plugins" | sed -n 's/^Plugin \([^ ]*\) by .*/\1/p' \
                | paste -sd',' - | sed 's/,/, /g')"
        fi
    fi
fi

# ── Machine ──────────────────────────────────────────────────────────────────
# DMI, from sysfs rather than dmidecode — dmidecode needs root, these files don't.
# (product_name and the UUIDs next to them are root-only; board_* and bios_* are
# world-readable, which is exactly the subset worth showing.)
emit BOARD "$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | sed 's/ *INC\.$//I;s/ *COMPUTER$//I') \
$(cat /sys/class/dmi/id/board_name 2>/dev/null)"
emit BIOS  "$(cat /sys/class/dmi/id/bios_version 2>/dev/null)"

# Package count and when the system last took a full upgrade. Arch-specific, like the
# Wayland versions below; empty elsewhere.
if command -v pacman >/dev/null 2>&1; then
    emit PACKAGES "$(pacman -Q 2>/dev/null | wc -l)"
    # The pacman log's last "full system upgrade" line, which is what people mean by
    # "when did I last update" — not the newest package mtime, which any single -S
    # would move.
    if [[ -r /var/log/pacman.log ]]; then
        last_up=$(grep 'starting full system upgrade' /var/log/pacman.log 2>/dev/null \
                  | tail -1 | cut -c2-11)
        [[ -n "$last_up" ]] && emit LAST_UPGRADE "$last_up"
    fi
fi

# systemd's own boot breakdown. Reported as the total plus the slowest stage, because
# "47s" invites "why" and the answer is usually one stage carrying it.
if command -v systemd-analyze >/dev/null 2>&1; then
    boot=$(systemd-analyze 2>/dev/null | head -1)
    emit BOOT "$(printf '%s' "$boot" | sed -n 's/.*= \(.*\)$/\1/p' | sed 's/[[:space:]]*$//')"
    emit BOOT_DETAIL "$(printf '%s' "$boot" \
        | grep -oE '[0-9.]+s \((firmware|loader|kernel|userspace)\)' \
        | sed 's/\([0-9.]*\)s (\(.*\))/\2 \1s/' | paste -sd',' - | sed 's/,/  ·  /g')"
fi

# ── Shell ────────────────────────────────────────────────────────────────────
# The thing you are looking at. `quickshell --version` prints
# "Quickshell 0.3.0 (revision , distributed by Arch Linux)" — the revision is blank on
# a packaged build, so only the version and packager are worth pulling out.
if command -v quickshell >/dev/null 2>&1; then
    qs=$(quickshell --version 2>&1 | head -1)
    emit QS_VERSION "$(printf '%s' "$qs" | sed -n 's/^Quickshell \([^ ]*\).*/\1/p')"
    emit QS_PACKAGER "$(printf '%s' "$qs" | sed -n 's/.*distributed by \(.*\))$/\1/p')"
fi

# ── Display server ───────────────────────────────────────────────────────────
# Wayland is the layer everything above depends on and the layer nothing reports —
# the compositor names itself, the toolkit names itself, and the protocol in between
# is invisible until something doesn't work.
#
# Versions come from pacman because there is no runtime "wayland --version": the
# protocol is a library, not a process. That makes these three lines Arch-specific,
# which is the same bargain the rest of this file already takes (nproc, lspci); on a
# distro without pacman they come out empty and the card hides those rows.
if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
    emit WL_DISPLAY "$WAYLAND_DISPLAY"

    if command -v pacman >/dev/null 2>&1; then
        emit WL_VERSION   "$(pacman -Q wayland 2>/dev/null | awk '{print $2}')"
        emit WL_PROTOCOLS "$(pacman -Q wayland-protocols 2>/dev/null | awk '{print $2}')"
    fi

    # XWayland is the compatibility shim: X11 clients get a fake X server that
    # translates to Wayland. Reported with a LIVE CLIENT COUNT rather than just
    # "installed", because "is anything actually still on X11" is the question you'd
    # open this page to answer — and the answer here is yes, two of five.
    if xw_pid=$(pgrep -x Xwayland 2>/dev/null | head -1); then
        xw_ver=""
        command -v pacman >/dev/null 2>&1 && \
            xw_ver=$(pacman -Q xorg-xwayland 2>/dev/null | awk '{print $2}')
        xw_clients=$(hyprctl clients -j 2>/dev/null \
            | grep -c '"xwayland": true' 2>/dev/null || printf '0')
        emit WL_XWAYLAND "${xw_ver:-running}"
        emit WL_XCLIENTS "$xw_clients"
    fi

    # Which portal backend answers screenshare/file-picker requests. A wrong or missing
    # portal is the usual cause of "screen sharing shows a black window on Wayland".
    portal_conf=/usr/share/xdg-desktop-portal/hyprland-portals.conf
    [[ -r "$portal_conf" ]] && \
        emit WL_PORTAL "$(sed -n 's/^default=//p' "$portal_conf" | head -1 | tr ';' ' ')"
fi

# Uptime from /proc rather than parsing `uptime`, whose output format is a moving
# target across locales ("up 2 days, 3:14" / "up 1 min" / "up 3:14").
if [[ -r /proc/uptime ]]; then
    read -r up _ < /proc/uptime
    secs=${up%.*}
    d=$(( secs / 86400 )); h=$(( (secs % 86400) / 3600 )); m=$(( (secs % 3600) / 60 ))
    if   (( d > 0 )); then emit UPTIME "${d}d ${h}h"
    elif (( h > 0 )); then emit UPTIME "${h}h ${m}m"
    else                   emit UPTIME "${m}m"
    fi
fi

# ── Processor ────────────────────────────────────────────────────────────────
# /proc/cpuinfo's "model name" is the same string lscpu prints, without the
# 200ms lscpu takes to enumerate every topology detail we don't want.
emit CPU   "$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)"
emit CORES "$(nproc 2>/dev/null)"

# ── Graphics ─────────────────────────────────────────────────────────────────
# lspci's VGA/3D line is the device name; the "Kernel driver in use" line that
# follows it (-k) is the driver. One lspci call, parsed once.
gpu_block=$(lspci -k 2>/dev/null | grep -A3 -E 'VGA compatible controller|3D controller' | head -8)
emit GPU    "$(printf '%s' "$gpu_block" | sed -n '1s/.*: //p' | sed 's/ (rev .*)//')"
emit DRIVER "$(printf '%s' "$gpu_block" | sed -n 's/.*Kernel driver in use: //p' | head -1)"

# glxinfo is the only portable-ish source for VRAM, and it costs ~150ms because it
# spins up a GL context. Worth it once, on a page you open deliberately.
if command -v glxinfo >/dev/null 2>&1; then
    vram=$(glxinfo -B 2>/dev/null | sed -n 's/.*Video memory: \([0-9]*\)MB.*/\1/p' | head -1)
    [[ -n "$vram" ]] && emit VRAM "$(( vram / 1024 )) GB"
fi

# ── Memory ───────────────────────────────────────────────────────────────────
# MemTotal is in kB. Reported as "used / total" because "how much do I have" and
# "how much is left" are the same question when you open this page.
if [[ -r /proc/meminfo ]]; then
    total_kb=$(sed -n 's/^MemTotal:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)
    avail_kb=$(sed -n 's/^MemAvailable:[[:space:]]*\([0-9]*\).*/\1/p' /proc/meminfo)
    if [[ -n "$total_kb" && -n "$avail_kb" ]]; then
        emit RAM "$(awk -v t="$total_kb" -v a="$avail_kb" \
            'BEGIN { printf "%.1f GB used of %.1f GB", (t-a)/1048576, t/1048576 }')"
    fi
fi
