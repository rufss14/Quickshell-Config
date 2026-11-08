#!/usr/bin/env bash
# ── reload-theme.sh ───────────────────────────────────────────────────────────
# Takes whatever is currently in ~/.cache/wal/colors.json, merges the user's
# overrides into it, and pushes the result to every themed application.
#
# ── Why this is its own script ───────────────────────────────────────────────
# There were TWO copies of this sequence: one in apply-wallpaper.sh and one built
# as a bash string inside ColorSchemePanel.qml. They had already drifted — the
# QML copy still ran `pkill zen` and `pkill nautilus`, still called swaync, never
# generated GTK3 css, and reported success unconditionally. Changing the
# wallpaper and changing the colour scheme are different actions that must end
# with the SAME work, so that work lives in one file.
#
# Callers:
#   · apply-wallpaper.sh   — after setting the wallpaper and extracting a palette
#   · ColorScheme service  — after writing an edited palette or an override
#
# Emits the same protocol as apply-wallpaper.sh:
#   STEP=<id>|<status>|<human text>      status: run | ok | skip | fail
#   RESTART=<process>|<label>            an app that must restart to repaint
#   WAVE=ready | go | done               the change's wave — see apply-wallpaper.sh
#
#   --committed   apply-wallpaper.sh has already merged your edits and committed
#                 the palette (and played the wave); only fan it out.
#   --app NAME [--staged]
#                 recolour ONE app, now: `discord`, `browser`, `spotify` or `steam`.
#                 services/Contagion.qml calls this while the app's windows are under
#                 the wave's curtain. With --staged it only SHOWS what the run staged
#                 before the freeze (apps-lib.sh) — exit 0 — or exits 3 when nothing is
#                 staged (the palette may not even be committed yet). Without, it shows
#                 the staged result or recolours from the committed palette. The
#                 fan-out runs the same functions and skips an app this already did
#                 (the stamps), so there is one copy of how each app is reached.
#   --palette FILE
#                 stage FILE (a {special, colors} palette, the shape the colours panel
#                 saves) in place of the live colors.json, and commit that. A scheme
#                 applied WITHOUT the lock: it becomes the live palette but is not
#                 written to the overrides file, so the next wallpaper replaces it.
#   --probe       print `APPS=<the ones above this machine can reach>` and nothing
#                 else: the wave holds its spread for an app it is recolouring,
#                 and must never hold it for one it can't (no Pywalfox, no
#                 Vencord script, no Spicetify recolour).
# Run on its own (a scheme, a pinned colour), this is the change: your edits are
# merged into a private copy and committed ONCE, so the shell recolours on one
# front from the bottom middle instead of snapping, and the apps follow after it.
#
# Every step is non-fatal: one missing program must not stop the rest.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

COMMITTED=0
APP=""
STAGED_ONLY=0
PROBE=0
PALETTE=""
case "${1:-}" in
    --palette)   PALETTE="${2:-}" ;;
    --committed) COMMITTED=1 ;;
    --app)       APP="${2:-}"; [[ "${3:-}" == "--staged" ]] && STAGED_ONLY=1 ;;
    --probe)     PROBE=1 ;;
esac

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG="$CACHE/quicktest-theme.log"
SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Through $CACHE like the LOG above, not a literal ~/.cache — apply-wallpaper.sh
# resolves the same directory the same way, and pywal itself honours XDG_CACHE_HOME,
# so a machine that sets it had this script looking in a directory pywal never wrote.
WAL_CACHE="$CACHE/wal"
# The wave's shared half: STAGE, the pacing, the stage's lock, the one commit.
# shellcheck source=wave-lib.sh
source "$SHELL_DIR/scripts/wave-lib.sh"

[[ "$PROBE" == 1 ]] || { echo "=== $(date -Is) reload-theme${APP:+ --app $APP} ==="; } >> "$LOG"

# ── step <id> <human text> -- <command...> ───────────────────────────────────
# Runs a command, reports it, and never aborts the script.
step() {
    local id="$1" text="$2" t="${EPOCHREALTIME/./}"; shift 3   # past id, text and --
    echo "STEP=$id|run|$text"
    echo "--- [$id] $*" >> "$LOG"
    if "$@" >> "$LOG" 2>&1; then
        echo "--- [$id] ok, $(( (${EPOCHREALTIME/./} - t) / 1000 )) ms" >> "$LOG"
        echo "STEP=$id|ok|$text"
        return 0
    fi
    echo "--- [$id] FAILED, $(( (${EPOCHREALTIME/./} - t) / 1000 )) ms" >> "$LOG"
    echo "STEP=$id|fail|$text"
    return 1
}

skip() { echo "STEP=$1|skip|$2"; echo "--- [$1] skipped: $2" >> "$LOG"; }

have() { command -v "$1" >/dev/null 2>&1; }

# ── Loading pywal's colors.sh needs `set +u` ─────────────────────────────────
# colors.sh ends with an FZF block that expands "$FZF_DEFAULT_OPTS" without a
# default. Under `set -u` that is a FATAL error, not a warning: bash exits 127 on
# the spot.
#
# That killed this script at step 6 on the first real run — the wallpaper and
# palette were applied, then every app-recolouring step AND the bookkeeping that
# records the current wallpaper silently never happened, and the whole run
# reported failure. One `set -u` interaction, six broken symptoms.
#
# `set -u` is kept for the rest of the script, where it catches real mistakes;
# it is only relaxed across the one file we don't control.
load_palette() {
    [[ -f "$WAL_CACHE/colors.sh" ]] || return 1
    set +u
    # shellcheck disable=SC1091
    source "$WAL_CACHE/colors.sh"
    set -u
    [[ -n "${color1:-}" ]]
}

# ── The apps a wave's front can reach one by one ─────────────────────────────
# discord / browser / spotify: scripts/apps-lib.sh (sourced by wave-lib.sh above),
# shared with the staging that runs before every commit.

# ── Done with the wave already? ──────────────────────────────────────────────
# `--app` stamps the moment it recoloured an app ($STAGE/.app-<name>, ns). The
# fan-out skips an app stamped since THIS run staged its apps (PREPARED_AT, exported
# by wave-lib.sh's commit_stage — before the freeze, since a staged app is shown as
# soon as the curtain is up): it already has this palette, and doing it twice isn't
# free — Spotify re-fetches its stylesheets, visibly, a second after the wave.
recoloured_since_commit() {
    local f="$STAGE/.app-$1" at
    [[ -n "${PREPARED_AT:-}" && -r "$f" ]] || return 1
    at="$(cat "$f" 2>/dev/null)"
    [[ "$at" =~ ^[0-9]+$ ]] && (( at >= PREPARED_AT ))
}
unless_done() {   # unless_done <app> <step id> <recolor function>
    if recoloured_since_commit "$1"; then skip "$2" "recoloured with the wave"; else "$3"; fi
}

if [[ "$PROBE" == 1 ]]; then
    reachable=()
    for a in discord browser spotify steam; do can_recolor "$a" && reachable+=("$a"); done
    echo "APPS=${reachable[*]}"
    exit 0
fi

if [[ -n "$APP" ]]; then
    case "$APP" in
        discord|browser|spotify|steam) ;;
        *) echo "STEP=args|fail|Unknown app $APP"; exit 2 ;;
    esac
    mkdir -p "$STAGE"
    if [[ "$STAGED_ONLY" == 1 ]]; then
        case "$APP" in
            discord) staged discord && publish_discord || exit 3 ;;
            spotify) staged spotify && publish_spotify || exit 3 ;;
            *) exit 3 ;;
        esac
        consume "$APP"
    else
        "recolor_$APP"
    fi
    date +%s%N > "$STAGE/.app-$APP" 2>/dev/null
    exit 0
fi

# ── 4. User overrides, and the one commit ────────────────────────────────────
# MUST run after anything else that writes colors.json, or saved edits get
# clobbered the moment a matching wallpaper is reapplied. That ordering is what
# made overrides look like they weren't persisting.
#
# The live palette with your edits laid over it, rendered in a private stage
# (scripts/stage-palette.py) and swapped in with one rename, between WAVE=ready (the
# shell snapshots its look) and WAVE=go (the new colours spread across it). Then the
# wait: nothing below may stutter the animation.
OVERRIDES="$SHELL_DIR/theming/pywal-overrides.json"
if [[ "$COMMITTED" == 1 ]]; then
    :   # merged into apply-wallpaper.sh's stage before its commit
elif [[ -n "$PALETTE" && -f "$PALETTE" && -f "$WAL_CACHE/colors.json" ]]; then
    # Held colours still go over the top (stage-palette skips a missing file), so this
    # is only ever "temporary" when nothing is held — which is when the panel asks.
    stage_lock
    stage_palette --from "$WAL_CACHE/colors.json" --saved "$PALETTE" --overrides "$OVERRIDES" && commit_stage
    stage_unlock
    wave go
    wait_landed
    wave done
elif [[ -f "$OVERRIDES" && -f "$WAL_CACHE/colors.json" ]]; then
    stage_lock
    stage_palette --from "$WAL_CACHE/colors.json" --overrides "$OVERRIDES" && commit_stage
    stage_unlock
    wave go
    wait_landed
    wave done
else
    skip overrides "no overrides file"
    wave go
    wave done
fi

# ── 5–11. Fan the palette out — all at once ──────────────────────────────────
# Every step below reads the committed palette and writes its own app's file; none
# depends on another. They used to run one after another: ~1.4s after the wave had
# landed (measured 2026-10-01), during which the shell — one theming job at a time —
# couldn't start the next change. Now each runs in the background (bg) and the script
# waits for them all: about as long as the slowest, the GTK flip (0.25s by design).
# STEP lines are single short writes, so parallel steps never interleave mid-line.
bg() { "$@" & }
FAN_T0=$(elapsed_ms)


# ── 5. The templates ─────────────────────────────────────────────────────────
# Installed from what the commit already rendered (install_templates) — or, when this
# run committed nothing (no overrides file, or a palette someone set by hand), rendered
# here the old way. Everything after reads them, so this goes first, alone.
wal_env() {
    # What `wal --theme` did besides rendering: the colours to every open terminal
    # (escape sequences) and pywal's own reloads (xrdb, kitty, sway, waybar, …).
    python3 -c 'import sys
from pywal import theme, sequences, reload
c = theme.file(sys.argv[1])
sequences.send(c)
reload.env()' "$WAL_CACHE/colors.json"
}
if install_templates; then
    echo "STEP=export|ok|Rebuilding colour files"
    bg step terminals "Recolouring open terminals" -- wal_env
else
    step export "Rebuilding colour files" -- wal --theme "$WAL_CACHE/colors.json"
fi

# ── 6. GTK3 ──────────────────────────────────────────────────────────────────
# Had no wiring at all before this and its gtk.css had been STALE SINCE 20 JUNE
# — a month of GTK3 apps wearing an old palette while everything else updated.
# Generated here from the live palette, written directly (no template file).
# Written by write_gtk3_css (wave-lib.sh), which commit_stage already ran WITH the commit; here
# it is normally a byte-compare with nothing to do, and the fallback for a run with no commit.
if [[ -f "$WAL_CACHE/colors.sh" ]]; then
    step gtk3 "Theming GTK3 apps" -- write_gtk3_css "$WAL_CACHE/colors.sh"
else
    skip gtk3 "palette not readable"
fi

# ── 6b. GTK4 / libadwaita ────────────────────────────────────────────────────
# Used to be "needs nothing: ~/.config/gtk-4.0/gtk.css is a SYMLINK to the
# pywal template output" — true on the machine that comment was written on,
# and nowhere else. That symlink pointed at ~/.cache/wal/gtk4.css, which only
# existed because a CUSTOM pywal template
# (~/.config/wal/templates/gtk4.css) sat outside this repo entirely, on that
# one machine. A fresh clone had no template, so `wal --theme` in step 5 never
# produced the file, the symlink's target never existed, and every GTK4 /
# libadwaita app (Nautilus, Mission Center, most Flatpaks) silently never got
# themed — while the maintainer's own machine looked fine, because the
# template had been sitting there since before this pipeline existed.
#
# Fixed the same way GTK3 just was above: written directly from the live
# palette, no template file and no symlink to depend on. If gtk.css here is
# STILL a symlink from an older setup, this simply overwrites through it —
# same bytes either way, and it stops mattering once this has run once.
#
# Now one function, write_gtk4_css (wave-lib.sh). commit_stage already wrote it WITH the
# commit — under the wave's curtain, which is when an open GTK4 app should repaint — so here
# it is normally a byte-compare that finds nothing to do. It stays as the fallback for a run
# with no commit of its own (a hand-run, the legacy path).
if [[ -f "$WAL_CACHE/colors.sh" ]]; then
    step gtk4 "Theming GTK4/libadwaita apps" -- write_gtk4_css "$WAL_CACHE/colors.sh"
else
    skip gtk4 "palette not readable"
fi

# ── 7. Make running GTK apps re-read it, WITHOUT killing them ────────────────
# GTK does not watch gtk.css, so a running app keeps its old colours. The old
# version solved that by `pkill nautilus` and `pkill zen` — killing the user's
# file manager and BROWSER as a side effect of changing wallpaper.
#
# Changing the gtk-theme GSettings key makes every running GTK app reload its
# theme and user CSS in place. Setting the same value emits no change signal, so
# it has to flip to another installed theme and back. Verified on this machine:
# Adwaita -> Adwaita-dark -> Adwaita, value restored exactly.
# Already done at the commit (it stamps .app-gtk3), unless this run had none.
if have gsettings; then bg unless_done gtk3 gtkreload gtk3_refresh; else skip gtkreload "gsettings not available"; fi

# ── 7b. Qt6 ──────────────────────────────────────────────────────────────────
# GTK is handled above; Qt is a completely separate mechanism (a QPalette of 21
# positional roles, not CSS), so it gets its own step rather than being bolted onto
# the GTK one.
#
# The visible beneficiary is `hyprland-share-picker` — the dialog Discord opens when
# you share your screen, which was rendering in default Fusion light against an
# otherwise fully themed desktop.
#
# Only reaches apps whose QT_QPA_PLATFORMTHEME is `qt6ct`; see
# ~/.config/environment.d/10-qt-theme.conf. Nothing needs restarting: the picker is
# spawned fresh on every share, so it picks up a new palette on next use.
if [[ -x "$SHELL_DIR/scripts/generate-qt6ct-colors" ]]; then
    bg step qt6 "Recolouring Qt apps" -- python3 "$SHELL_DIR/scripts/generate-qt6ct-colors"
else
    skip qt6 "generate-qt6ct-colors not found"
fi

# ── 7c. MangoHud ─────────────────────────────────────────────────────────────
# The in-game FPS/frametime overlay. Same surgical discipline as qt6ct — the
# script owns two marked regions in MangoHud.conf and leaves the rest (position,
# keybinds, font) alone. No RESTART line: MangoHud doesn't watch the file, a
# running game repaints on its own reload keybind, and that's expected.
if [[ -x "$SHELL_DIR/scripts/generate-mangohud-config" ]]; then
    bg step mangohud "Recolouring MangoHud" -- python3 "$SHELL_DIR/scripts/generate-mangohud-config"
else
    skip mangohud "generate-mangohud-config not found"
fi

# ── 8. Compositor ────────────────────────────────────────────────────────────
# Only where this repo's Hyprland config is installed (its wal-reload.sh is there).
# The REPO's copy runs, with --live: palette.lua is written for the next start and the
# three colours it feeds are set at runtime — no `hyprctl reload` (see that script).
if [[ -x "$HOME/.config/hypr/scripts/wal-reload.sh" ]]; then
    bg step hyprland "Recolouring Hyprland" -- \
        env QS_OVERRIDES="$OVERRIDES" bash "$SHELL_DIR/hypr/scripts/wal-reload.sh" --live
else
    skip hyprland "wal-reload.sh not found"
fi

# ── 9. Terminals ─────────────────────────────────────────────────────────────
# SIGUSR1 makes kitty re-read its config in place. No restart, no lost session.
# In a wave each kitty window already reloaded as the front reached it (the theme
# was written at the commit — scripts/wave-lib.sh); this is the net for any window
# it missed or that opened since. Re-reading the same colours changes nothing.
kitty_reload() {
    if cp "$WAL_CACHE/colors-kitty.conf" "$KITTY_DIR/current-theme.conf" 2>>"$LOG"; then
        pkill -USR1 kitty 2>/dev/null
        echo "STEP=kitty|ok|Recolouring terminals"
    else
        echo "STEP=kitty|fail|Recolouring terminals"
    fi
    pkill -USR1 alacritty 2>/dev/null
    return 0
}
if [[ -f "$WAL_CACHE/colors-kitty.conf" ]] && [[ -d "$KITTY_DIR" ]]; then
    bg kitty_reload
else
    skip kitty "kitty config not found"
fi

# ── 10. Everything else that reads the palette ───────────────────────────────
# (dunst used to be recoloured here; the shell's own notification daemon replaced it
# and dunst is gone from the system, so the step and dunst-wal.sh went with it.)

# cava keeps its gradient in its own config, so the two colours are substituted in
# and the process is signalled to reload.
cava_reload() {
    if sed -i "s/^gradient_color_1 = .*/gradient_color_1 = '$color2'/;
               s/^gradient_color_2 = .*/gradient_color_2 = '$color3'/" \
              "$HOME/.config/cava/config" 2>>"$LOG"; then
        pkill -USR2 cava 2>/dev/null
        echo "STEP=cava|ok|Recolouring visualiser"
    else
        echo "STEP=cava|fail|Recolouring visualiser"
    fi
    return 0
}
if [[ -f "$HOME/.config/cava/config" ]] && load_palette; then
    bg cava_reload
else
    skip cava "cava config not found"
fi

# ── Steam (Millennium / simply-dark) ─────────────────────────────────────────
# The theme's colour inputs live in Millennium's config.json (`themes.themeColors`,
# what "Settings -> Themes -> Edit colors" writes), injected as a :root block that
# cascades OVER the theme's own colors.css. So that block is what has to follow the
# palette, or Steam keeps whatever was baked in last, no matter how many times wal
# regenerates its files -- the "manual intervention" this replaces.
#
# The stock theme does NOT read the pywal names (--color0..15): its inputs are its own
# greys (--color-dark, --grey, --white, ...). This step used to bake the pywal names and
# so recoloured nothing on a theme installed from the Millennium store; steam-colors.py
# maps the theme's own variables onto the palette (and still writes the pywal names, for
# a local copy whose colors.css does read them). scripts/test-steam-colors.py guards it.
#
# Only touches the block if simply-dark is the ACTIVE theme, so switching to a
# different Millennium theme later doesn't leave this silently overwriting
# colors that belong to something else. Config is backed up first, same
# discipline as hypr-config.py -- the newest five, since this runs on every change.
#
# A running Steam doesn't repaint from this: Millennium injects the block when a window
# loads (the restart prompt below covers it).
MILLENNIUM_CFG="$HOME/.config/millennium/config.json"
steam_recolor() {
    local active bak="$HOME/.config/millennium/.bak"
    active=$(python3 -c "
import json, sys
try:
    print(json.load(open(sys.argv[1])).get('themes', {}).get('activeTheme', ''))
except Exception:
    pass
" "$MILLENNIUM_CFG" 2>>"$LOG")
    if [[ "$active" != "simply-dark" ]]; then
        skip steam "simply-dark isn't the active Millennium theme"
        return 0
    fi
    mkdir -p "$bak"
    cp "$MILLENNIUM_CFG" "$bak/config.json.$(date +%Y%m%d%H%M%S)" 2>>"$LOG"
    ls -1t "$bak"/config.json.* 2>/dev/null | tail -n +6 | xargs -r rm -f --
    step steam "Recolouring Steam" -- python3 "$SHELL_DIR/scripts/steam-colors.py" \
        "$MILLENNIUM_CFG" "$WAL_CACHE/colors.json"
}
if [[ -f "$MILLENNIUM_CFG" ]] && load_palette; then
    bg steam_recolor
else
    skip steam "Millennium config not found"
fi

bg unless_done spotify spotify recolor_spotify
bg unless_done discord discord recolor_discord
bg unless_done browser firefox recolor_browser
# Steam's debug-port flag is consumed at every start; a theme run puts it back for the next one
# (opt-in, see steam-live.py). Then the live push, unless Contagion already did it under the curtain.
( python3 "$STEAM_LIVE" flag >/dev/null 2>&1 & )
bg unless_done steam steamlive recolor_steam
# Steam's own blues/greens/tinted greys are recoloured from a scan of its stylesheets (steam-accent.py);
# redo it only when they changed — a Steam update — or there has been none yet. After the wave, in the
# background: the check is one cheap read, a real scan a few seconds.
( python3 "$STEAM_LIVE" scan --if-needed >/dev/null 2>&1 & )

# ── 11. Zen browser chrome ───────────────────────────────────────────────────
# Writes userChrome.css only. It is NOT applied to a running Zen and the browser
# is NOT killed — the old version ran `pkill zen`, destroying the session and
# every open tab as a side effect of picking a wallpaper.
#
# userChrome.css is only read at startup; that's a Firefox limitation, not
# something this script can work around. The panel offers an explicit "Restart
# Zen" button so it is always the user's decision.
if [[ -x "$SHELL_DIR/scripts/update-zen-colors.sh" ]]; then
    bg step zen "Preparing Zen colours" -- bash "$SHELL_DIR/scripts/update-zen-colors.sh"
else
    skip zen "update-zen-colors.sh not found"
fi

# ── Which running apps still need a restart ──────────────────────────────────
# Emitted as `RESTART=<process>|<label>`, one per app, and only for apps actually
# running right now — a prompt to restart something you don't have open is noise.
#
# Two different reasons land in the same list:
#
#   · Zen reads userChrome.css only at startup. Firefox limitation.
#   · Nautilus and Mission Center are libadwaita, which does not follow the
#     gtk-theme key — so the toggle in step 7 reaches GTK3 apps but not these.
#     That is why the original pipeline resorted to killing Nautilus outright.
#   · Steam/Millennium bakes colours into config.json (see the steam step
#     above); whether an already-open window repaints from that write alone is
#     unverified, so it gets the same "ask, don't assume" prompt as the rest.
#
# The shell shows ONE prompt for whatever is in this list, rather than naming a
# single app as though it were the only one that mattered. One `ps` read for all four
# (four `pgrep`s were ~70ms), while the steps above are still running.
RUNNING="$(ps -eo comm= 2>/dev/null)"
# An app with the live GTK4 module loaded (scripts/gtk-live) repaints by itself when gtk.css
# changes, so asking for a restart would be noise. /proc/<pid>/maps is the proof, not the
# install: an app started before the module was built, or without GIO_EXTRA_MODULES in its
# environment, doesn't have it, and every instance has to.
repaints_itself() {
    local pid found=1
    for pid in $(pgrep -x -- "$1"); do
        grep -qs libgiolivetheme "/proc/$pid/maps" || return 1
        found=0
    done
    return "$found"
}
restart_if_running() {
    grep -qx -- "$1" <<<"$RUNNING" || return 0
    repaints_itself "$1" || echo "RESTART=$1|$2"
    return 0
}
restart_if_running zen-bin       "Zen"
restart_if_running nautilus      "Files"
restart_if_running missioncenter "Mission Center"
restart_if_running steam         "Steam"

wait
echo "--- [fan-out] $(( $(elapsed_ms) - FAN_T0 )) ms, run total $(elapsed_ms) ms" >> "$LOG"

# Explicit, so the exit status is a deliberate statement about the run rather than whatever
# the last command happened to return. Individual step failures are reported through the
# STEP protocol and counted by the caller; they do not need to be smuggled out in $?.
echo "=== finished $(date -Is) ===" >> "$LOG"
exit 0
