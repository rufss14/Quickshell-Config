#!/usr/bin/env bash
# ── packages.sh ──────────────────────────────────────────────────────────────
# Explicitly-installed packages for the Storage page's Packages tab, as
# PKG=id|display|version|bytes|source|description lines on stdout. Same
# contract as storage.sh: read-only, degrade to nothing rather than fail,
# KEY=value|pipe.
#
# ── id vs display ─────────────────────────────────────────────────────────────
# The same string for pacman (a package name IS its own readable label), but
# NOT for flatpak: `org.kde.krita` is what `flatpak uninstall` needs and
# `Krita` is what a human wants to read in a list. Two fields rather than
# picking one and living with it being wrong for one source.
#
# ── This script is READ-ONLY ─────────────────────────────────────────────────
# Nothing here removes anything — see Storage.qml's uninstallPackages(), which
# is the one place package removal actually happens, for the same reason
# storage.sh's own header gives: everything capable of deleting something
# belongs in one file, not split between here and the QML.
#
# ── Only EXPLICIT packages, on both sides ─────────────────────────────────────
# `pacman -Qe` — packages installed directly, not pulled in as someone else's
# dependency. A full `-Q` listing runs into the thousands and is mostly
# dependency noise that isn't safe to remove individually; explicit is the
# list a person can actually recognise and make a call on. Packages installed
# ONLY as dependencies and now unneeded are "orphans" — already handled as
# their own reclaimer in Storage.qml, not duplicated here.
#
# `flatpak list --app` is the same idea applied to flatpak: on its own,
# `flatpak list` mixes in runtimes and extensions (org.freedesktop.Platform,
# codec/plugin bundles, …) — flatpak's equivalent of pacman dependencies, and
# just as unsafe to remove one at a time from a casual browse list.
#
# ── source: official vs aur vs flatpak ────────────────────────────────────────
# `pacman -Qm` lists "foreign" packages — installed but not present in any
# configured sync repo. That's the standard way to detect an AUR (or otherwise
# manually built) package; pacman itself has no concept of "AUR", only
# "did this come from a repo I know about".
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# ── System-critical packages are hidden, not just locked ─────────────────────
# The kernel, its headers, microcode and the base/base-devel groups are
# technically "explicit" (pacstrap installs them that way), but removing one
# through a casual browse-and-delete list is a different kind of mistake than
# removing an app — it can leave the system unbootable, not just missing a
# program. Storage.qml's other reclaimers only ever touch things that rebuild
# themselves; this list keeps that spirit by not offering these at all, rather
# than showing them "Locked" and trusting the two-step confirm to be enough.
# Same idea as Updates.qml's `rebootPackages` regex, applied here as an
# exclusion instead of a warning.
critical_re='^(linux|linux-lts|linux-zen|linux-hardened|linux-rt)(-headers)?$'
critical_re+='|^linux-firmware$'
critical_re+='|^(amd-ucode|intel-ucode)$'
critical_re+='|^(base|base-devel)$'

declare -A foreign
while read -r name _; do
    [[ -n "$name" ]] && foreign["$name"]=1
done < <(pacman -Qm 2>/dev/null)

# ── Parse `pacman -Qei` blocks ────────────────────────────────────────────────
# One block per package, fields as "Label           : value", blank line
# between packages. Not a tty, so pacman does not wrap long lines — same
# assumption storage.sh's own `-Qtdi` orphan parse already relies on.
#
# Emitted with \x1f (unit separator) between fields rather than the final `|`
# delimiter, since a package Description can itself contain a literal `|`.
LC_ALL=C pacman -Qei 2>/dev/null | awk -F': *' '
    function flush() {
        if (name != "") printf "%s\x1f%s\x1f%.0f\x1f%s\n", name, ver, bytes, desc
        name = ""; ver = ""; bytes = 0; desc = ""
    }
    /^Name/           { flush(); name = $2 }
    /^Version/        { ver = $2 }
    /^Description/    { desc = $2 }
    /^Installed Size/ {
        v = $2; n = v + 0
        if (v ~ /KiB/)      n *= 1024
        else if (v ~ /MiB/) n *= 1048576
        else if (v ~ /GiB/) n *= 1073741824
        else                n *= 1024      # pacman omits no unit in practice, floor is KiB
        bytes = n
    }
    /^$/ { flush() }
    END  { flush() }
' | while IFS=$'\x1f' read -r name ver bytes desc; do
    [[ -z "$name" ]] && continue
    [[ "$name" =~ $critical_re ]] && continue
    src="official"
    [[ -n "${foreign[$name]:-}" ]] && src="aur"
    # The final delimiter IS `|` — strip any that survived in the description
    # rather than let it desync the QML side's split.
    desc="${desc//|/\/}"
    printf 'PKG=%s|%s|%s|%.0f|%s|%s\n' "$name" "$name" "$ver" "$bytes" "$src" "$desc"
done

# ── Flatpak apps ──────────────────────────────────────────────────────────────
# `size` only ever comes back human-formatted ("86.6 MB") — flatpak has no raw-
# byte column — so it's parsed back the same way paccache's dry-run output
# already is in storage.sh. GLib's g_format_size() (what flatpak uses) is
# decimal (1000-based), not binary, so that's the base used here.
#
# The description column here is the app ID itself, not a real description —
# flatpak doesn't hand one over on the command line without a slow per-app
# `flatpak info` call. Showing the ID on hover (where a pacman row shows its
# actual description) is still useful: it's the exact string `flatpak
# uninstall` acts on, visible without cluttering the row.
if command -v flatpak >/dev/null 2>&1; then
    flatpak list --app --columns=application,name,version,size 2>/dev/null \
    | while IFS=$'\t' read -r appid dispname ver size; do
        [[ -z "$appid" ]] && continue
        num=$(printf '%s' "$size" | grep -oP '[\d.]+' | head -1)
        unit=$(printf '%s' "$size" | grep -oiP '(KB|MB|GB|TB)' | head -1)
        bytes=$(awk -v n="${num:-0}" -v u="${unit:-}" 'BEGIN{
            u = tolower(u)
            m = (u=="kb") ? 1000 : (u=="mb") ? 1000000 : (u=="gb") ? 1000000000 \
              : (u=="tb") ? 1000000000000 : 1
            printf "%.0f", n * m
        }')
        dispname="${dispname//|/\/}"
        [[ -z "$dispname" ]] && dispname="$appid"
        printf 'PKG=%s|%s|%s|%.0f|flatpak|%s\n' "$appid" "$dispname" "${ver:-}" "$bytes" "$appid"
    done
fi
