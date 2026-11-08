#!/usr/bin/env bash
# ── smoke-headless.sh ─────────────────────────────────────────────────────────
# scripts/smoke.sh, inside a sealed sandbox under a headless sway, so it can run in CI
# (no display, no GPU) and on a desktop with a live shell without touching it.
#
#     bash scripts/smoke-headless.sh              exits non-zero on any smoke failure
#     bash scripts/smoke-headless.sh --keep       leave the sandbox dir behind to read
#     bash scripts/smoke-headless.sh --shots DIR  also screenshot every panel/page into DIR
#
# It LAUNCHES QUICKSHELL (and sway). The checks themselves are smoke.sh's, unchanged:
# this file only builds the room it runs in.
#
# ── What the sandbox cuts off, and why each one ──────────────────────────────
#   HOME + every XDG dir   a temp dir. The shell writes config.json to XDG_STATE_HOME on
#                          start and theme runs write GTK/Qt files under XDG_CONFIG_HOME;
#                          pointed at the real ones it would overwrite the live config.
#   XDG_RUNTIME_DIR        a temp dir: its own Wayland socket, its own `qs ipc` sockets,
#                          and no path to Hyprland's ($XDG_RUNTIME_DIR/hypr), pipewire's
#                          or the live shell's.
#   HYPRLAND_INSTANCE_SIGNATURE, WAYLAND_DISPLAY, DISPLAY, SWAYSOCK   unset, so nothing
#                          can dispatch into the real compositor or open on the real screen.
#   session bus            private (dbus-run-session): no clash over the notification
#                          server, no live MPRIS players. And with NO service directories,
#                          so nothing is D-Bus-activated: on the stock session config the
#                          first run started its own gamemoded, openrazer-daemon (which
#                          opens the real Razer devices) and portals.
#   system bus             pointed at nothing. Otherwise the throwaway would register a
#                          second polkit agent and Bluetooth pairing agent (BlueZ hands
#                          the DEFAULT agent to the newest) and take a logind inhibitor.
#                          A CI container has no system bus either, so this matches it.
#
# Not cut off: the network (weather etc. just fetch), and port 47821 (the Spotify
# bridge, loopback TCP) — with a live shell running, smoke.sh's `--alongside` is passed
# and its `bind failed` is a warning, as documented there.
#
# ── Rendering ────────────────────────────────────────────────────────────────
# sway's headless backend with the pixman renderer needs no GPU. Quickshell keeps
# QSG_RHI_BACKEND=vulkan (the OpenSSL workaround, docs/launch-environment.md); on a
# machine without a GPU that runs on Mesa's lavapipe (package vulkan-swrast).
#
# What a pass means: what smoke.sh says, minus Hyprland. Nothing Hyprland-specific
# (workspaces, focused monitor, dispatch) has anything to talk to here, so this proves
# "every file loads and the overview's delegates build", not "it works under Hyprland".
# ─────────────────────────────────────────────────────────────────────────────
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
repo=$PWD

keep=0; shots=""
while [ $# -gt 0 ]; do
    case $1 in
        --keep) keep=1 ;;
        --shots) shots=$(realpath -m "${2:?--shots needs a directory}"); shift ;;
        *) echo "smoke-headless: unknown option $1" >&2; exit 2 ;;
    esac
    shift
done
for t in sway quickshell dbus-run-session; do
    command -v "$t" >/dev/null || { echo "smoke-headless: $t not installed" >&2; exit 2; }
done

# A live shell is visible through the process table even from inside the sandbox, so
# decide --alongside out here, where it means what it says.
alongside=""
{ pgrep -x qs || pgrep -x quickshell; } >/dev/null && alongside="--alongside"

sandbox=$(mktemp -d --suffix=.qs-smoke)
cleanup() {
    # sway outlives dbus-run-session (it's backgrounded inside it), so it's killed by pid,
    # here, on every exit path — Ctrl+C included.
    [ -f "$sandbox/sway.pid" ] && kill "$(cat "$sandbox/sway.pid")" 2>/dev/null
    if [ "$keep" = 1 ]; then echo "smoke-headless: sandbox kept at $sandbox"
    else rm -rf "$sandbox"; fi
}
trap cleanup EXIT

export HOME="$sandbox/home"
export XDG_CONFIG_HOME="$HOME/.config" XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state" XDG_DATA_HOME="$HOME/.local/share"
export XDG_RUNTIME_DIR="$sandbox/run"
export DBUS_SYSTEM_BUS_ADDRESS="unix:path=$sandbox/no-system-bus"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"
unset HYPRLAND_INSTANCE_SIGNATURE WAYLAND_DISPLAY DISPLAY SWAYSOCK DBUS_SESSION_BUS_ADDRESS

printf 'output HEADLESS-1 resolution 1920x1080\n' >"$sandbox/sway.conf"

# Software Vulkan for the shell, when it's there. A real GPU's driver can't present to the
# pixman-rendered headless output (no dmabuf), so with only that installed Quickshell logs
# "scenegraph is not functional": QML still loads and evaluates (what the checks look
# at) but nothing renders. Mesa's lavapipe (vulkan-swrast, what CI installs) presents
# through shared memory.
lvp=$(ls /usr/share/vulkan/icd.d/lvp_icd*.json 2>/dev/null | head -1)
if [ -n "$lvp" ]; then
    export VK_DRIVER_FILES="$lvp" VK_ICD_FILENAMES="$lvp"
else
    echo "smoke-headless: no lavapipe (package vulkan-swrast) — the sandbox won't render; QML is still checked" >&2
fi

# Two pictures in the default wallpaper library (Wallpaper.libraryDir), so the gallery
# builds real tiles — otherwise every per-tile binding goes unexercised. The repo's own
# previews: no download, nothing personal.
mkdir -p "$HOME/wallpapers/walls"
cp "$repo/assets/previews/TopBarPreview.png" "$repo/assets/previews/MorphPreview.png" "$HOME/wallpapers/walls/" 2>/dev/null

# Seeded state, so the dock's buttons get built (the dock settings page's preview strip):
# one pinned app — a desktop entry that exists in any container, ours, whose Exec does
# nothing — and the Downloads/Trash tail switched on. Written where Quickshell.statePath
# will look: by-shell/<md5 of the absolute shell.qml path> (Quickshell's shellId), before
# the shell starts, because config.json is read once at load.
mkdir -p "$XDG_DATA_HOME/applications"
printf '[Desktop Entry]\nType=Application\nName=Smoke Test\nExec=true\nIcon=application-x-executable\n' \
    >"$XDG_DATA_HOME/applications/qs-smoke.desktop"
state_dir="$XDG_STATE_HOME/quickshell/by-shell/$(printf '%s' "$repo/shell.qml" | md5sum | cut -c1-32)"
mkdir -p "$state_dir"
printf '["qs-smoke"]\n' >"$state_dir/pins.json"
printf '{"dockShowTrash": true, "dockShowDownloads": true}\n' >"$state_dir/config.json"

# The stock session.conf minus <standard_session_servicedirs/> and its includes: a bus
# nothing can be activated on. A name the shell asks for just isn't there.
cat >"$sandbox/session.conf" <<CONF
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:dir=$XDG_RUNTIME_DIR</listen>
  <auth>EXTERNAL</auth>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF

# Everything from here on shares one private session bus.
exec_inside=$(cat <<'EOF'
set -u
# --no-new-privs: Arch's sway carries cap_sys_nice and makes itself SCHED_RR. Where
# RLIMIT_RTTIME is 0 (some sandboxed shells) the kernel then SIGKILLs it within seconds
# ("Killed", no log line). Without the file capability it stays a normal process.
WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 \
    setpriv --no-new-privs sway -c "$SANDBOX/sway.conf" >"$SANDBOX/sway.log" 2>&1 &
echo $! >"$SANDBOX/sway.pid"
for _ in $(seq 40); do
    sock=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' ! -name '*.lock' -printf '%f\n' | head -1)
    [ -n "$sock" ] && break
    sleep 0.25
done
if [ -z "${sock:-}" ]; then
    echo "smoke-headless: sway never opened a Wayland socket — its log:" >&2
    sed 's/^/    /' "$SANDBOX/sway.log" >&2
    exit 2
fi
export WAYLAND_DISPLAY="$sock" QT_QPA_PLATFORM=wayland
bash "$REPO/scripts/smoke.sh" $ALONGSIDE
EOF
)
# Lowest CPU priority, and lavapipe capped at 4 threads: software rendering otherwise takes
# every core, and on a desktop whose PipeWire isn't realtime (no rtkit) the live audio
# crackles for the whole run.
export LP_NUM_THREADS=4
QS_SMOKE_SHOTS="$shots" SANDBOX="$sandbox" REPO="$repo" ALONGSIDE="$alongside" \
    nice -n 19 dbus-run-session --config-file="$sandbox/session.conf" -- bash -c "$exec_inside"
exit $?
