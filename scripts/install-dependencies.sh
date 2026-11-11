#!/usr/bin/env bash
# InstalDependencies.sh
# Installs the system dependencies needed by this quickshell config on Arch Linux.
# Third-party app integrations (Spicetify, Vencord, Vesktop, Zen Browser, GTK4 apps)
# are intentionally NOT installed here since they're optional and user-specific.

set -euo pipefail

# ── The package lists, in one place ──────────────────────────────────────────
# The rationale for the less-obvious entries is in the big comment block below,
# kept beside the official list it explains. These arrays are the single source
# of truth: the install commands further down spend them, and `--official` /
# `--aur` print them so the Setup page in the shell can run the same set without
# duplicating the names in QML.
OFFICIAL_PKGS=(
    hyprland qt6-base qt6-declarative qt6-wayland qt6-svg qt6-5compat
    pipewire pipewire-pulse wireplumber networkmanager libnotify
    # NOT rtkit. With PipeWire 1.6.10, libpipewire's
    # module-rt in every client logs "clamping rt.time.soft from 18446744073709551615 to 0
    # because of RTKit" and sets RLIMIT_RTTIME to 0/0 (rtkit itself reports 200000). rtkit
    # then makes the client's data thread realtime, and the kernel SIGKILLs the process on
    # its first tick: no log line, no coredump. The shell loads module-rt too, so every
    # child inherits the 0 hard limit. Seen killing cava (exit 137 in a loop) and every
    # Wallpaper Engine scene that plays sound. Don't add it back until a PipeWire client
    # started with rtkit running shows a non-zero "Max realtime timeout" in /proc/PID/limits.
    # zenity: the file dialog behind "Add wallpapers" and the look export/import. Without it
    # those buttons disable themselves with a reason (Look.blocker()).
    zenity
    brightnessctl cava pacman-contrib
    python python-pillow util-linux procps-ng inotify-tools xdg-utils glib2 dbus
    qt6ct xdg-desktop-portal-hyprland
    # hyprlock: scripts/lock.sh locks with it when the shell itself doesn't answer (crashed,
    # hung, mid-restart). Small, Hyprland's own, and a lock key that silently fails is worse
    # than none.
    hyprlock
    hyprsunset
    # base-devel: makepkg, for the AUR helper and every AUR package (pywal16). The blob
    # plugin's own toolchain (cmake, qt6-shadertools) is PACK_PKGS[blob], below.
    base-devel
    wl-clipboard curl polkit iproute2 bluez python-dbus python-gobject imagemagick jq lua54
    # vulkaninfo: the GPU's product name for the sidebar stats card (hw-names.sh);
    # without it the card falls back to lspci's chip-family string.
    vulkan-tools pciutils
    # slurp picks a region: Lens, the snip tool, a region recording. (The recorder itself
    # is PACK_PKGS[clips].)
    slurp
    # The launcher's `:` emoji picker draws its grid in a colour emoji font; without one every
    # cell is an empty square. Optional at runtime: services/Emoji.blocker() says so and the
    # mode shows that instead. (The list itself, services/emoji.json, is bundled.)
    noto-fonts-emoji
    # The sidebar's colour picker (services/ColorPicker) picks the pixel with it.
    # Optional at runtime: without it the module's tile says so and can't be put on.
    hyprpicker
    # GTK3 apps in the shell's colours: the generated gtk.css speaks libadwaita's colour
    # names, which only adw-gtk3 reads in GTK3 (theme-setup.sh selects it).
    adw-gtk-theme
    # The shell's own updater (scripts/shell-update.sh): `ssh-keygen -Y verify` checks
    # a release's signature, and the release is a .tar.xz. Neither is in `base`.
    openssh xz
    # The shell itself, from [extra]. A -git build from the AUR satisfies it too: install_official
    # skips anything `pacman -T` already finds, so it never offers to replace quickshell-git.
    quickshell
)
AUR_PKGS=(
    python-pywal16
)

# ── Feature packs: official-repo packages one feature needs ──────────────────
# Not in OFFICIAL_PKGS, so a plain install isn't a gaming rig and a
# screen recorder whether you want them or not. Each key is a Setup step
# (services/setupplan.js: ticked for clips/gamemode/blob, unticked for the rest),
# installed with `--pack <key>`. Every feature here disables itself with a reason
# when its pack is missing — the portability rule in CLAUDE.md — so skipping one
# costs that feature, never a broken click.
#
#   clips        services/Clips: gpu-screen-recorder records, ffmpeg/ffprobe cut thumbnails
#                and exports (scripts/clips-lib.py), Qt Multimedia + its FFmpeg backend play
#                a clip in the editor (state/Media probes it; without it the editor still
#                cuts). Sound effects do NOT need it: they play through pw-play.
#   gamemode     services/Gamemode holds a `gamemoderun` session; the Gaming panel wires up
#                MangoHud. 32-bit builds are added below when [multilib] is on.
#   blob         the toolchain scripts/build-blobs-plugin.sh compiles the Quicktest.Blobs
#                plugin with. The blob step installs this pack, then builds.
#   ddc          external-monitor brightness over DDC/CI (services/Brightness). Laptop
#                panels use brightnessctl (core); without ddcutil a desktop monitor just
#                has no slider.
#   beatsync     numpy for scripts/music-pulse.py (services/MusicPulse), the wallpaper's
#                beat clock. Without it the effects fall back to cava, slower to the beat.
#   discordkeys  keystroke injection for the Discord card's screen-share/camera buttons
#                (no RPC command exists). BOTH: an XWayland client needs xdotool, a native
#                Wayland one (Vesktop) needs wtype; Discord.pressBlocker() says which.
#   depth        uv builds the depth clock's private Python 3.13 env
#                (scripts/wallpaper-depth-setup.sh; onnxruntime's wheels trail the system
#                Python). Installed by that feature when it is switched on, not by Setup.
#
# Not installed by anything any more, and why:
#   flatpak      only ever used behind `command -v flatpak` (updates, storage, the app
#                list) — useful if you already have it, pointless to install for that.
#   reflector    was installed but never enabled (enabling rewrites a system file). A stale
#                mirror makes updates fail with "404"; updatelog.js failureHint names it.
declare -A PACK_PKGS=(
    [clips]="gpu-screen-recorder ffmpeg qt6-multimedia qt6-multimedia-ffmpeg"
    [gamemode]="gamemode mangohud"
    [blob]="cmake qt6-shadertools"
    [ddc]="ddcutil"
    [beatsync]="python-numpy"
    [discordkeys]="xdotool wtype"
    [depth]="uv"
)
# What a plain `install-dependencies.sh` (setup.sh) installs on top of the core: the
# packs Setup ticks by default, so the CLI and the wizard agree.
DEFAULT_PACKS=(clips gamemode blob)

# ── Developer-only: a JS runtime for the .js test suites ─────────────────────
# NOT installed by default and deliberately not in OFFICIAL_PKGS — the shell itself
# never runs JavaScript outside QML, so this is ~50MB nobody who only wants a desktop
# should be made to install.
#
# It matters anyway, because without it eleven test suites cannot be run BY ANYONE,
# including the ones CLAUDE.md leans on as the guard behind real logic:
# test-calc.js (the launcher's expression parser), test-blend.js (the geometry this
# shell shares with the Hyprland config), test-spicylyrics.js / test-objpack.js (the
# dictionary decoder the lyrics bridge depends on). The Python suites have no such gap
# because python is already a hard dependency.
#
# The headers say `bun scripts/test-calc.js (or: node scripts/test-calc.js)`, and bun
# is AUR-only. `nodejs` is in [extra], runs the same ES-module files unmodified, and is
# the smaller ask — so that is what is named here.
#
#   ./scripts/install-dependencies.sh --dev-install    # installs it
#   ./scripts/install-dependencies.sh --dev            # just prints the list
DEV_PKGS=(
    nodejs
    # Only for regenerating the bundled icon fonts (scripts/material-symbols-map.py
    # --emit cuts assets/fonts/ with fontTools). Using the shell never needs it.
    python-fonttools
)

# ── Optional third-party integrations — a name table, not an install list ────
# None of these are installed by any flag below. Each is a deliberate per-user
# opt-in run one at a time from Settings → Setup's wizard (services/Setup.qml),
# same as Spicetify already was per this file's own header comment. But the
# PACKAGE NAME still only belongs in one place — hardcoding
# "spicetify-cli" / "linux-wallpaperengine" / "python-argostranslate" directly
# in the wizard's QML which is exactly the duplication OFFICIAL_PKGS/AUR_PKGS above exist to
# avoid. `--optional` prints this table so Setup.qml can resolve a key to a
# package name instead of carrying its own copy that a rename would miss.
declare -A OPTIONAL_PKGS=(
    [spicetify]="spicetify-cli"
    [wallpaperengine]="linux-wallpaperengine"
    [argostranslate]="python-argostranslate"
    # Native half of Pywalfox: repaints a RUNNING Zen/Firefox (apps-lib.sh
    # recolor_browser). The browser extension is a separate manual install.
    [pywalfox]="python-pywalfox"
    # `songrec listen` for the Now-Playing panel's "what is this song?" buttons
    # (services/SongRec). In the AUR on some setups — Setup's install uses the helper.
    [songrec]="songrec"
    # Holds a still of the Material Wallpaper on screen while the shell is not running
    # (services/MaterialFallback, scripts/material-fallback.sh). Without it that option says so
    # and is off; the live wallpaper is unaffected.
    [awww]="awww"
    # Karaoke's WORD matching (services/Karaoke, scripts/karaoke.py): speech recognition for what
    # you sing, set against the lyric line. Without both pieces the module still runs, judging
    # timing alone, and its card says what's missing. python-vosk is in [extra]; the model is a
    # data package in the AUR (installs to /usr/share/vosk-models/small-en-us, one of the places
    # the module looks). Other languages — Portuguese, Spanish, French, German, Italian, Dutch, Russian —
    # are fetched one at a time by `scripts/karaoke-model.sh <language>` (to $XDG_DATA_HOME/quicktest/
    # vosk-<code>), or any model from alphacephei.com/vosk/models can be pointed at by Config.karaokeModelDir.
    [vosk]="python-vosk"
    [voskmodel]="vosk-model-small-en-us"
)

# ── Vulkan ICD — not optional for this shell ─────────────────────────────────
# shell.qml pins `QSG_RHI_BACKEND=vulkan` (a `//@ pragma DefaultEnv`) to dodge an
# OpenSSL 3.6.4 segfault in Qt's OpenGL program-binary cache. With no Vulkan
# driver installed Quickshell does not fall back — it crashes on launch with
# "Failed to create Vulkan instance: -9" and no QML warning. `vulkan-icd-loader`
# (a qt6-base dep) is only the loader; the ICD itself is GPU-specific and nothing
# in the lists above pulls one. Picked from `lspci`; Mesa's ICDs coinstall
# cleanly, so if detection comes up empty we install all three rather than guess.
# The GPU is read from sysfs (vendor ids), not lspci: on a fresh machine pciutils is installed by this very
# transaction, so lspci may not exist yet when the list is built. lspci is the fallback.
#   0x1002 AMD   0x8086 Intel   0x10de NVIDIA
detect_gpus() {
    local v seen=()
    for v in /sys/class/drm/card*/device/vendor; do
        [ -r "$v" ] || continue
        case "$(cat "$v")" in
            0x1002) seen+=(AMD) ;;
            0x8086) seen+=(Intel) ;;
            0x10de) seen+=(NVIDIA) ;;
        esac
    done
    if [ "${#seen[@]}" -eq 0 ] && command -v lspci >/dev/null 2>&1; then
        local g; g=$(lspci -nn 2>/dev/null | grep -iE 'vga|3d compatible|display controller' || true)
        grep -qiE 'amd|ati' <<<"$g" && seen+=(AMD)
        grep -qi  'intel'   <<<"$g" && seen+=(Intel)
        grep -qi  'nvidia'  <<<"$g" && seen+=(NVIDIA)
    fi
    ((${#seen[@]})) && printf '%s\n' "${seen[@]}" | sort -u
    return 0
}
# NVIDIA's proprietary driver ships its own Vulkan ICD; adding nouveau's beside it is noise at best.
nvidia_proprietary() { pacman -Qq nvidia-utils nvidia-open-utils nvidia-580xx-utils nvidia-470xx-utils >/dev/null 2>&1; }
detect_vulkan_pkgs() {
    local icds=() g
    while IFS= read -r g; do
        case "$g" in
            AMD)    icds+=(vulkan-radeon) ;;
            Intel)  icds+=(vulkan-intel) ;;
            NVIDIA) nvidia_proprietary || icds+=(vulkan-nouveau) ;;
        esac
    done < <(detect_gpus)
    # Nothing found (a VM, a container): the software rasteriser works anywhere, so the shell starts at all.
    if [ "${#icds[@]}" -eq 0 ] && ! nvidia_proprietary; then icds=(vulkan-swrast); fi
    ((${#icds[@]})) && printf '%s\n' "${icds[@]}"
    return 0
}
mapfile -t VULKAN_PKGS < <(detect_vulkan_pkgs)
OFFICIAL_PKGS+=("${VULKAN_PKGS[@]}")

# ── 32-bit MangoHud and gamemode — only if [multilib] is on ─────────────────
# services/Gamemode.qml holds a `gamemoderun` session and the Gaming panel wires
# up MangoHud; both are pointless without the packages. `mangohud` and `gamemode`
# (64-bit) are PACK_PKGS[gamemode]; this adds their lib32 builds to that pack — needed for
# 32-bit games, launchers and older Proton titles; without lib32-gamemode,
# `gamemoderun` on a 32-bit binary is an LD_PRELOAD "wrong ELF class" error and no
# Game Mode — live in [multilib], so adding them blindly would abort this whole
# `set -e` script on a system that hasn't enabled it. Same guard shape as
# detect_vulkan_pkgs.
if pacman-conf --repo-list 2>/dev/null | grep -qx multilib; then
    PACK_PKGS[gamemode]+=" lib32-mangohud lib32-gamemode"
fi

# ── The text font ───────────────────────────────────────────────────────────
# otf-codenewroman-nerd is the shell's TEXT font. It needs no version pin, although 3.5.0 reinserted glyphs
# mid-font and shifted every glyph id: the icons come from the shell's own fonts (assets/fonts,
# config/Tokens.qml), no installed icon font is read, so any version will do. Installed from the repository only when it is missing; one that is already
# there (pinned or not) is left alone, so this never downgrades or upgrades a font under a running shell.
FONT_PKG="otf-codenewroman-nerd"

# `pacman` directly when already root (the shell's Setup page runs this under
# pkexec), `sudo pacman` otherwise.
SUDO=(); [ "$(id -u)" -eq 0 ] || SUDO=(sudo)

install_font() {
    if pacman -Qq "$FONT_PKG" >/dev/null 2>&1; then
        echo "$FONT_PKG is installed ($(pacman -Q "$FONT_PKG" | awk '{print $2}'))"
        return 0
    fi
    echo "--- Installing the text font ($FONT_PKG) ---"
    "${SUDO[@]}" pacman -S --needed --noconfirm "$FONT_PKG"
}

# ── Installing the official set without one bad name taking it all down ─────
# One transaction is fastest and is tried first. If it fails for a reason that is about the PACKAGES (a name
# that moved, a conflict) the rest are installed one at a time and the ones that would not are listed at
# the end — the shell then runs with what it has, and the setup says which feature wants the missing one.
# A failure that is about the MACHINE (a database lock, no network) is not retried 60 times: it stops at once.
# Installs the packages given as arguments.
install_official() {
    local out rc=0
    # Only what isn't satisfied already. `pacman -T` resolves provides (quickshell-git provides
    # quickshell); `--needed` alone doesn't, and would try to swap the -git build for the repo one.
    local -a want
    mapfile -t want < <(pacman -T "$@" 2>/dev/null)
    [ "${#want[@]}" -eq 0 ] && return 0
    set -- "${want[@]}"
    out=$("${SUDO[@]}" pacman -S --needed --noconfirm "$@" 2>&1) || rc=$?
    printf '%s\n' "$out"
    [ "$rc" -eq 0 ] && return 0
    if grep -qiE 'unable to lock database|could not resolve host|failed retrieving file|connection timed out|no space left' <<<"$out"; then
        return "$rc"
    fi
    echo "--- The one-shot install failed: trying the packages one at a time ---"
    local failed=() p
    for p in "$@"; do
        "${SUDO[@]}" pacman -S --needed --noconfirm "$p" >/dev/null 2>&1 || failed+=("$p")
    done
    if [ "${#failed[@]}" -gt 0 ]; then
        echo "NOT INSTALLED: ${failed[*]}" >&2
        return 1
    fi
    return 0
}

# One pack's packages, installed with the same one-shot-then-one-by-one retry as the core.
install_pack() {
    local key=$1
    [ -n "${PACK_PKGS[$key]:-}" ] || { echo "unknown pack '$key' — expected one of: ${!PACK_PKGS[*]}" >&2; return 2; }
    local -a pkgs; read -ra pkgs <<<"${PACK_PKGS[$key]}"
    install_official "${pkgs[@]}"
}

case "${1:-}" in
    --official) printf '%s\n' "${OFFICIAL_PKGS[*]}"; exit 0 ;;
    # "key=pkg,pkg key=pkg …" on one line, for Setup's probe (services/Setup.qml). Never installs.
    --packs)
        for k in "${!PACK_PKGS[@]}"; do v=${PACK_PKGS[$k]}; printf '%s=%s ' "$k" "${v// /,}"; done
        echo
        exit 0 ;;
    # Install one feature pack. Like --core, assumes it is already privileged when run by
    # the shell (pkexec / sudo -S); SUDO resolves to empty as root.
    --pack)
        install_pack "${2:-}"
        exit $? ;;
    # What this machine's graphics will get, for the setup scan: "gpu=AMD" and "vulkan=vulkan-radeon".
    --vulkan)
        g=$(detect_gpus | head -1)
        printf 'gpu=%s\nvulkan=%s\n' "$g" "${VULKAN_PKGS[*]}"
        printf 'nvidiaProprietary=%s\n' "$(nvidia_proprietary && echo 1 || echo 0)"
        exit 0 ;;
    --aur)      printf '%s\n' "${AUR_PKGS[*]}";      exit 0 ;;
    --dev)      printf '%s\n' "${DEV_PKGS[*]}";      exit 0 ;;
    # "key=pkg key=pkg …" on one line — Setup.qml splits on whitespace then "=",
    # same shape as --official's space-separated line. Never installs anything.
    --optional)
        for k in "${!OPTIONAL_PKGS[@]}"; do printf '%s=%s ' "$k" "${OPTIONAL_PKGS[$k]}"; done
        echo
        exit 0 ;;
    # The non-AUR essentials in one shot, for the shell's Setup page. Assumes it
    # is already privileged (pkexec) — SUDO above resolves to empty as root.
    --core)
        rc=0
        install_official "${OFFICIAL_PKGS[@]}" || rc=$?
        install_font || rc=$?
        exit "$rc" ;;
    # Opt-in, never part of a normal run: see DEV_PKGS above.
    --dev-install)
        "${SUDO[@]}" pacman -S --needed --noconfirm "${DEV_PKGS[@]}"
        exit $? ;;
esac

echo "=== Quickshell config dependency installer ==="

# ── Ensure yay is available (needed for pywal16) ─────────────────────────────
if ! command -v yay &>/dev/null; then
    echo "yay not found — installing it first..."
    sudo pacman -S --needed --noconfirm git base-devel
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    (cd "$tmpdir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

# ── Official repo packages ───────────────────────────────────────────────────
#
# Several of these are less obvious than the rest:
#
#   qt6ct                        scripts/generate-qt6ct-colors writes a palette here so
#                                Qt6 apps follow the wallpaper. Most visibly the screen
#                                share picker. NOT interchangeable with qt5ct — qt5ct
#                                cannot theme a Qt6 binary, which is why the picker sat
#                                in default Fusion light while the rest of the desktop
#                                was themed.
#   xdg-desktop-portal-hyprland  provides that picker; screen sharing has nothing to
#                                open without it.
#   hyprsunset                   the night-light backend (services/NightLight.qml). Hyprland's
#                                own, so it is the one installed here; gammastep is supported
#                                as an alternative for non-Hyprland wlroots compositors but is
#                                not pulled in. With neither, the night-light control disables
#                                itself with a reason rather than failing on click.
#   hyprpm                       OPTIONAL, not installed by any flag: builds and loads the
#                                hypr-dynamic-cursors plugin (Settings › Cursor › Motion
#                                effects — the pointer tilts and stretches as it moves). It
#                                compiles third-party C++ against the installed Hyprland, so it
#                                is a deliberate per-user opt-in: the settings page prints the
#                                `hyprpm add` commands, and says what is missing rather than
#                                failing when it is absent. hyprpm needs cmake, git, meson and
#                                ninja, which is why it is not pulled in by default.
#   gpu-screen-recorder          the clips pill's recorder (services/Clips): a replay buffer
#                                and recordings, hardware-encoded. Its gsr-kms-server needs
#                                cap_sys_admin to capture a monitor directly; the package sets
#                                it on install (`getcap /usr/bin/gsr-kms-server`). Without the
#                                recorder the pill's controls disable themselves with a reason.
#   python-dbus / python-gobject scripts/bt-helper.py (services/BtBridge): the Bluetooth
#                                pairing agent, signal strength and file sending — the
#                                BlueZ/obexd D-Bus APIs Quickshell.Bluetooth doesn't expose.
#                                Without them the helper reports it can't run and the
#                                panel says so; pairing a device that needs a code fails.
#   bluez-obex                   OPTIONAL, not installed by any flag: obexd, for SENDING
#                                files to a phone (the Bluetooth panel's drop zone, the
#                                screenshot toast's Send). D-Bus activated, so installing
#                                it is the whole setup. Without it the send card says what
#                                is missing instead of failing.
#   tesseract (+ tesseract-data-<lang>)
#                                OPTIONAL, not installed by any flag: the sidebar's Lens
#                                reads a screen region's text with it (scripts/lens.py;
#                                grim + slurp take the region). eng is the default
#                                language; Config.lensOcrLangs picks others. Without it
#                                the Lens tile says so and can't be put on.
#   python                       the system updater runs pacman/yay through a real PTY
#                                (`pty.spawn`) so their progress output and any prompt
#                                behave as they do in a terminal. Also the Discord RPC and
#                                credential scripts. NOT optional — without it
#                                scripts/update-run.sh cannot start a run at all.
#   python-pillow                reads album covers: scripts/album-colors.py quantises the
#                                artwork for the media cards' colours and for the
#                                album-cover colour scheme (Settings → Wallpaper → Album
#                                colours), which repalettes the whole shell per track.
#                                Was an UNDECLARED dependency until that landed — the
#                                script imports PIL inside a try so a missing Pillow is a
#                                clean {"ok": false}, and the cards then silently wear the
#                                pywal palette. Correct behaviour, and it meant nothing
#                                ever reported the package was absent.
#   util-linux / procps-ng       named explicitly even though `base` already requires
#                                both, because scripts/update-run.sh depends on specific
#                                binaries from them and that is not guessable from the
#                                package names: `flock` (the single-instance update lock —
#                                see CLAUDE.md; a PID file is NOT an acceptable
#                                substitute), `setsid` (detaching the run so a Quickshell
#                                reload cannot kill pacman), and `pgrep` (cancelling walks
#                                the process tree, because a run spans four process
#                                groups). Installing them is a no-op on any real Arch
#                                system; the point is that the dependency is written down.
#   xdg-utils / glib2            named for the same reason as util-linux above: both are
#                                already pulled in transitively (xdg-utils by qt6-base,
#                                glib2 by flatpak and ddcutil), but the shell calls their
#                                binaries DIRECTLY and a transitive guarantee is not a
#                                declaration. `xdg-open` opens a wallpaper's Steam
#                                Workshop page — the only route to unsubscribing, since
#                                that has no local API — and `gio trash` is how deleting
#                                a wallpaper works. Deleting the user's own pictures uses
#                                the trash, never rm; without gio the ✕ silently does
#                                nothing. The dock uses gio too: `gio open` for its
#                                Downloads/pinned files, `gio trash` for files dropped on
#                                its Trash, `gio info` to learn a pinned file's icon.
#   dbus                         `dbus-monitor` — how the dock hears apps' own badge
#                                counts and progress bars (the Unity LauncherEntry
#                                signal); the shell can't subscribe to an arbitrary D-Bus
#                                signal itself. Always installed with systemd; named
#                                because the binary is called directly.
#   base-devel / cmake /         the Quicktest.Blobs QML plugin (plugin/, built by
#     qt6-shadertools             scripts/build-blobs-plugin.sh) — the metaball fusion of
#                                the bar and its panels. Optional: absent, the shell
#                                degrades to the plain QML morph. Pulled in here so blob
#                                works after a normal setup rather than needing a separate
#                                "go install a C++ toolchain" step. base-devel is already
#                                required to build pywal16 from the AUR.
#   xdotool / wtype              keystroke injection for the Discord card's screen share
#                                and camera buttons, which have no RPC command and can
#                                only be reached by pressing Discord's own keybind.
#                                BOTH, because which one works depends on your client:
#                                an XWayland Discord (the official client) needs
#                                xdotool's XTEST, a native Wayland one (Vesktop) needs
#                                wtype. Using the wrong one exits 0 and delivers the
#                                keystroke nowhere, so the shell probes for both and
#                                picks by the window.
#   wl-clipboard                 clipboard history (services/Clipboard.qml, scripts/clip-store.py).
#                                `wl-paste --watch` speaks wlr-data-control — the protocol
#                                for a client that never has focus — which Quickshell's
#                                own clipboardText does not; `wl-copy` writes entries back
#                                from a file (never argv). Missing, the `--watch` loop exits
#                                repeatedly and history is silently OFF. Was assumed
#                                installed and never declared.
#   curl                         every HTTP fetch: Weather.qml, the Arch news feed in
#                                Updates.qml, ClaudePresence.qml, SpeedTest.qml. Not pulled
#                                in by `base` (pacman links libcurl, not the binary).
#   polkit                       `pkexec` — the privileged path for the update runner's
#                                pacman transaction and for installing the blobs plugin.
#                                Usually present on a desktop but never guaranteed, and the
#                                shell calls the binary directly.
#   iproute2                     `ss -tinp` in services/NetApps.qml — per-application
#                                network usage. The binary is not guessable from any
#                                package the shell already pulls.
#   bluez                        the BlueZ D-Bus service behind `Quickshell.Bluetooth`
#                                (services/Bt.qml → the bar pill and
#                                settings page). No daemon = an empty adapter list, not an
#                                error. bluez-utils / bluetoothctl are NOT needed — the
#                                shell talks D-Bus, not the CLI.
#   imagemagick                  OPTIONAL: `magick` in scripts/apply-wallpaper.sh extracts
#                                a still frame from an animated wallpaper so pywal can read
#                                colours off a GIF. Absent, that one step skips with a note
#                                and the GIF's palette just isn't used.
#   gamemode                     services/Gamemode.qml holds a `gamemoderun sleep
#                                infinity` child while the shell's game mode is on, so
#                                the system gamemoded applies the CPU governor / GPU
#                                performance level / renice from /etc/gamemode.ini and
#                                reverts them when the mode goes off. Absent, game mode
#                                still does its shell-side work (idle + quiet holds,
#                                wallpaper) and the pill's subtitle says the rest is
#                                unavailable — it does not fail.
#   mangohud                     the in-game FPS/frametime overlay. scripts/generate-
#                                mangohud-config themes it from the wallpaper (a step in
#                                reload-theme.sh) and the Gaming panel switches presets.
#                                lib32-mangohud is added just above IFF [multilib] is on.
#   jq / lua54                   hypr/scripts/wal-reload.sh — the step that recolours
#                                Hyprland after every wallpaper / colour-scheme change.
#                                It `jq`-merges pywal's colors.json with the shell's
#                                overrides into hypr/palette.lua, and reads the role→wal
#                                index map out of blend.lua with `lua5.4`. The script is
#                                `set -e`, so a missing jq aborts it before palette.lua is
#                                written or `hyprctl reload` runs — Hyprland silently keeps
#                                its old borders/shadows while every other app recolours.
#                                lua54 provides the `lua5.4` binary (the `lua` package's
#                                /usr/bin/lua is not what the script calls).
echo
echo "--- Installing official repo packages ---"
install_official "${OFFICIAL_PKGS[@]}" || echo "Some packages did not install (listed above) — the rest did; carrying on." >&2

install_font

echo
echo "--- Installing the default feature packs: ${DEFAULT_PACKS[*]} ---"
for k in "${DEFAULT_PACKS[@]}"; do
    install_pack "$k" || echo "The $k pack did not fully install — that feature will say what's missing." >&2
done

# ── AUR packages ──────────────────────────────────────────────────────────────
# ── If quickshell ever fails with "symbol lookup error: ... undefined symbol:
#    _Z...QUntypedPropertyBinding..., version Qt_6_PRIVATE_API" ──────────────
# Only a -git build from the AUR does this: it links Qt's private ABI as it was at
# BUILD time, and a `pacman -Syu` that bumps qt6-base doesn't rebuild it. Fix:
# rebuild it (`yay -S quickshell-git`). The [extra] package is rebuilt by Arch with
# each Qt bump, so a normal install never sees this.
echo
echo "--- Installing AUR packages via yay ---"
yay -S --needed --noconfirm "${AUR_PKGS[@]}"

echo
echo "=== Done ==="
echo
echo "Everything else — Spotify lyrics, the Discord panel, animated wallpapers,"
echo "the greeter — is optional and set up from Settings → Setup in the shell."
echo "More feature packs (external-monitor brightness, beat sync, Discord keys):"
echo "  ./scripts/install-dependencies.sh --pack ddc|beatsync|discordkeys"
echo
echo "Hacking on this config? The scripts/test-*.js suites need a JS runtime,"
echo "which is deliberately not installed above:"
echo "  ./scripts/install-dependencies.sh --dev-install"

# ── Lyrics bridge (OPTIONAL) ──────────────────────────────────────────────────
# Syllable-level lyrics and Spotify's own playhead, via a Spicetify extension living
# inside the Spotify client. Not installed here — Spicetify is a third-party client
# modifier and that choice is the user's.
#
#   sudo pacman -S spicetify-cli        # then, once:
#   spicetify config extensions quickshell-bridge.js && spicetify apply
#
# The extension ships with this config at
# ~/.config/spicetify/Extensions/quickshell-bridge.js and talks to
# scripts/spotify-bridge.py over loopback. WITHOUT it everything still works: lyrics come
# from NetEase/LRCLIB and the playhead from MPRIS, just coarser. The card's tick/cross
# says which path is live, and
#   qs ipc -c ~/.config/quicktest call spotify lyrics
# names the stage if it is not.
#
# It exists because the lyrics API authenticates with a live Spotify access token, which
# only exists inside the client. Nothing outside it can obtain one without scraping.

# ── Lyrics translation (OPTIONAL) ─────────────────────────────────────────────
# For the translate button on the media card. NOTHING here is required — the fallback
# backend uses python3, which this shell already depends on, so the button works out of
# the box and this section is purely an upgrade path.
#
#   argos-translate (AUR) — runs the model LOCALLY. Nothing leaves the machine, no key,
#   works offline. Weaker on idiom, which lyrics are full of. Takes precedence
#   automatically once present.
#     yay -S argos-translate
#     argospm update && argospm install translate-ja_en    # one per pair you want
#
# WITHOUT it, translation goes to Google's public translate endpoint: each line of the
# track is sent there. No account and nothing identifying the listener travels with it,
# and it only happens while the translate button is on — which is off by default, because
# this config is published and that is not a thing a stranger should enable unknowingly.

# ── Lyrics romanization (OPTIONAL) ────────────────────────────────────────────
# For the "abc" button on the media panel, which appears only on a song written in another
# script. NOTHING here is required: Google's public endpoint answers first (each lyric line that
# has non-Latin letters is sent there, only while the button is on — off by default, for the
# reason translation is), and a local library below is the fallback, or the only source when
# the panel's "Allow Google" is off.
#
#   python-pykakasi   (extra)   Japanese → Hepburn romaji     sudo pacman -S python-pykakasi
#   python-unidecode  (extra)   Cyrillic, Greek, Thai; rough for Arabic and Hebrew (no vowels)
#   Chinese (pypinyin) and Korean (korean-romanizer) have no package in the sync database here;
#     the AUR names are `python-pypinyin` / `python-korean-romanizer` if they exist — UNVERIFIED —
#     otherwise `pip install --user pypinyin korean-romanizer`. Without them those two scripts
#     are romanized by Google only.

