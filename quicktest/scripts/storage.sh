#!/usr/bin/env bash
# ── storage.sh ────────────────────────────────────────────────────────────────
# Disk usage and reclaimable space for the settings Storage page, as KEY=value
# lines on stdout. Same contract as specs.sh: one process for the whole page,
# every field degrades to nothing rather than failing the run.
#
# ── This script is READ-ONLY ─────────────────────────────────────────────────
# Nothing here deletes anything. Every reclaim figure comes from a dry run or a
# listing; the actual removals are separate commands the user presses a button
# for, built in the QML service so they're visible in one place rather than
# hidden in a shell script that also does the reporting.
#
# ── What is deliberately NOT measured here ───────────────────────────────────
# Anything under /home. `du` on the home directory takes over two minutes on
# this machine (1.6T spinning disk) and would make merely opening the tab spin
# up the drive. Home lives behind an explicit scan button — see SCAN_ROOTS in
# Storage.qml.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

emit() { printf '%s=%s\n' "$1" "${2:-}"; }

# ── du: ALLOCATED size, not apparent ─────────────────────────────────────────
# `du -sb` is apparent size (the sum of st_size), and that is the wrong question
# here. This page answers "how much disk space do I get back", which is blocks
# actually occupied. The two genuinely differ on real data, measured on this
# machine:
#
#   /var/log/journal    apparent 1.36 GiB   allocated 1.24 GiB   (sparse files)
#   /var/lib/flatpak    apparent 5.93 GiB   allocated 6.17 GiB   (block overhead)
#
# So apparent size overstates the journal by 126 MB and understates flatpak by
# 253 MB. It also disagreed with journalctl's own "1.2G", which was the clue.
# `--block-size=1` keeps byte precision while reporting allocation.
duB() { du -s --block-size=1 "$@" 2>/dev/null | awk '{s+=$1} END{printf "%.0f", s+0}'; }

# ── Filesystems ──────────────────────────────────────────────────────────────
# -B1 gives exact bytes, so the formatting decisions (GiB vs GB, decimals) stay
# in QML where the label is written, instead of being baked in by df's own
# rounding. -x drops the virtual filesystems: tmpfs "usage" is RAM, and showing
# it beside real disks invites the reader to add them together.
#
# The mount point is the LAST field and may contain spaces, so it's taken as the
# rest of the line rather than as $7.
#
# ROTA (1 = spinning, 0 = solid state) is looked up per device: it's the
# difference between "this scan is instant" and "this scan takes two minutes",
# and it's why the page treats the two disks differently.
declare -A rota_map
while read -r name rota; do
    rota_map["/dev/$name"]="$rota"
done < <(lsblk -ndo NAME,ROTA 2>/dev/null)

df -B1 -T -x tmpfs -x devtmpfs -x efivarfs -x overlay -x squashfs 2>/dev/null \
| tail -n +2 \
| while read -r dev fstype size used avail _pct mount; do
    # Partitions inherit their parent disk's ROTA — lsblk -nd lists whole disks
    # only, so /dev/sda2 has to resolve through /dev/sda.
    parent="${dev%%[0-9]*}"
    rota="${rota_map[$dev]:-${rota_map[$parent]:-0}}"
    emit FS "$dev|$fstype|$size|$used|$avail|$mount|$rota"
done

# ── Reclaimable ──────────────────────────────────────────────────────────────
# Format: RECLAIM=id|label|bytes|known|detail
#
# `known` is 1 when the byte figure came from an actual dry run and 0 when it
# could not be determined in advance. That distinction is load-bearing: flatpak
# has no dry-run mode at all (both --dry-run and --no-act are rejected), so
# claiming a number for it would be inventing one. A page that says "unknown" is
# more use than a page that guesses.

# paccache prints "==> finished dry run: N candidates (disk space saved: X GiB)".
# The unit varies with the size (MiB below a gigabyte), so both the number and
# the unit are parsed rather than assuming GiB.
paccache_bytes() {
    local out unit num
    out=$(paccache -d "$@" 2>&1 | grep -o 'disk space saved: .*)' | head -1)
    [[ -z "$out" ]] && { printf '0'; return; }
    num=$(printf '%s' "$out" | grep -oP '[\d.]+' | head -1)
    unit=$(printf '%s' "$out" | grep -oP '(KiB|MiB|GiB|TiB)' | head -1)
    awk -v n="$num" -v u="${unit:-MiB}" 'BEGIN{
        m = (u=="KiB") ? 1024 : (u=="MiB") ? 1048576 : (u=="GiB") ? 1073741824 : 1099511627776
        printf "%.0f", n * m
    }'
}
paccache_count() {
    paccache -d "$@" 2>&1 | grep -oP '\d+(?= candidates)' | head -1
}

if command -v paccache >/dev/null 2>&1; then
    # Keep the 2 most recent versions of installed packages. Two rather than one
    # so a downgrade is still possible after cleaning — that's paccache's own
    # default and the reason it isn't -k0.
    b=$(paccache_bytes -k2); c=$(paccache_count -k2)
    emit RECLAIM "paccache|Old package versions|$b|1|${c:-0} superseded packages, keeping the 2 newest of each"

    # Cached packages for software that is no longer installed. Separate from the
    # above because it is pure dead weight — there is nothing left to downgrade.
    b=$(paccache_bytes -u -k0); c=$(paccache_count -u -k0)
    emit RECLAIM "paccache-uninstalled|Cache for removed programs|$b|1|${c:-0} packages you no longer have installed"
fi

# Orphans: installed as dependencies, now depended on by nothing. The size is the
# sum of their own Installed Size fields. LC_ALL=C because that field name is
# translated, and a localised pacman would silently sum nothing.
if command -v pacman >/dev/null 2>&1; then
    read -r ocount obytes < <(LC_ALL=C pacman -Qtdi 2>/dev/null | awk -F': *' '
        /^Installed Size/ {
            c++; v=$2; n=v+0
            if (v ~ /KiB/) n *= 1024
            else if (v ~ /MiB/) n *= 1048576
            else if (v ~ /GiB/) n *= 1073741824
            else n *= 1024                      # pacman omits no unit in practice; KiB is its floor
            s += n
        }
        END { printf "%d %.0f", c+0, s+0 }')
    [[ "${ocount:-0}" -gt 0 ]] && \
        emit RECLAIM "orphans|Orphaned packages|$obytes|1|$ocount packages installed as dependencies that nothing needs any more"
fi

# systemd journal. --disk-usage reports a rounded human figure, so the exact
# number comes from the directories themselves.
if command -v journalctl >/dev/null 2>&1; then
    jb=$(duB /var/log/journal /run/log/journal)
    # Vacuuming to 200M is what's actually reclaimed, not the whole figure — the
    # journal is how you diagnose the last crash, and emptying it entirely trades
    # a diagnostic for a gigabyte.
    if [[ "${jb:-0}" -gt 209715200 ]]; then
        # "Old system logs", not "System logs": /var/log appears in the directory list
        # under that exact name, and two rows with one label reads as a duplicate.
        emit RECLAIM "journal|Old system logs|$(( jb - 209715200 ))|1|Trims the journal to 200 MB, keeping the most recent entries"
    fi
fi

# Coredumps: crash dumps of programs that already died. Useful only if someone is
# actively debugging that crash.
if [[ -d /var/lib/systemd/coredump ]]; then
    cb=$(duB /var/lib/systemd/coredump)
    cc=$(find /var/lib/systemd/coredump -type f 2>/dev/null | wc -l)
    [[ "${cb:-0}" -gt 1048576 ]] && \
        emit RECLAIM "coredumps|Crash dumps|$cb|1|$cc dumps from programs that have already crashed"
fi

# Flatpak runtimes nothing installed still uses.
#
# NO dry run exists — `flatpak uninstall --unused` accepts neither --dry-run nor
# --no-act (checked against this version's --help). So the size is genuinely
# unknown until it runs, and this is emitted with known=0 rather than with a
# fabricated number.
if command -v flatpak >/dev/null 2>&1; then
    if [[ -n "$(flatpak list --runtime 2>/dev/null)" ]]; then
        emit RECLAIM "flatpak|Unused Flatpak runtimes|0|0|Runtimes kept for apps you have since removed. Flatpak can't report the size until it runs."
    fi
fi

# ── Known large directories ──────────────────────────────────────────────────
# Format: DIR=label|bytes|path|owner
#
# `owner` is "system" or "you". The distinction drives whether the page offers a
# button: system caches regenerate on their own, whereas the things under your
# home directory are yours, and this page reports them without offering to
# delete them.
#
# Only cheap paths here — all on the SSD. Home is scanned on demand.
dirsize() {
    [[ -e "$2" ]] || return
    local b; b=$(duB "$2")
    [[ "${b:-0}" -gt 0 ]] && emit DIR "$1|$b|$2|${3:-system}"
}

#
# These are emitted LAST because they're the slow part — /usr and /opt add ~3s to a
# script that is otherwise 1.3s. The QML side parses lines as they arrive and paints
# progressively, so the disks and the reclaim list are on screen before these land.
#
# /usr and /opt are here for the composition chart rather than for cleanup: without
# them the breakdown of the root filesystem is ~16 GB of unexplained "Other", which
# tells the reader nothing. Neither is remotely cleanable — /usr IS the operating
# system — so they carry owner "os" and the UI never offers an action for them.
dirsize "Package cache"     /var/cache/pacman/pkg
dirsize "Flatpak"           /var/lib/flatpak
dirsize "System logs"       /var/log
dirsize "Programs"          /usr                   os
dirsize "Extra programs"    /opt                   os
