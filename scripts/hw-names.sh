#!/usr/bin/env bash
# ── hw-names.sh ───────────────────────────────────────────────────────────────
# The hardware names the sidebar's stats card shows ("GPU — AMD Radeon RX 6700
# XT"), as KEY=value lines. Run once by services/SysStats; the names don't change
# while the machine is up. RAW strings only — tidying them is sysstats.js
# (cleanCpuName, gpuName), where it's tested.
#
#   CPU=<model name>             from /proc/cpuinfo
#   VK=<deviceType>|<deviceName> one per Vulkan device (vulkaninfo, if installed):
#                                the marketing name, which lspci doesn't have
#   PCI=<lspci display line>     the fallback: names the chip family only
#   HOMEDISK=<disk>              the whole disk under $HOME (through partitions,
#                                LUKS and LVM — lsblk's inverse tree)
#   MODEL_<disk>=<model>         each whole disk's model, from sysfs
#
# Every field degrades to absent rather than failing.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

emit() { printf '%s=%s\n' "$1" "${2:-}"; }

emit CPU "$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo 2>/dev/null | head -1)"

if command -v vulkaninfo >/dev/null 2>&1; then
    vulkaninfo --summary 2>/dev/null \
        | awk -F'= ' '/^[[:space:]]*deviceType/ { t = $2 }
                      /^[[:space:]]*deviceName/ { print "VK=" t "|" $2 }'
fi

if command -v lspci >/dev/null 2>&1; then
    emit PCI "$(lspci 2>/dev/null | grep -E 'VGA|3D controller|Display controller' | head -1 \
                | sed 's/^[^:]*:[^:]*: //; s/ (rev .*)//')"
fi

home_src=$(findmnt -no SOURCE -T "${HOME:-/}" 2>/dev/null | sed 's/\[.*//' | head -1)
if [[ -n "$home_src" ]]; then
    emit HOMEDISK "$(lsblk -snro NAME,TYPE "$home_src" 2>/dev/null | awk '$2 == "disk" { print $1; exit }')"
fi

for d in /sys/block/*; do
    name=${d##*/}
    model=$(sed 's/[[:space:]]*$//' "$d/device/model" 2>/dev/null)
    [[ -n "$model" ]] && emit "MODEL_$name" "$model"
done
exit 0
