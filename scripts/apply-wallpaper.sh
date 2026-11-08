#!/usr/bin/env bash
# ── apply-wallpaper.sh ────────────────────────────────────────────────────────
# Sets the wallpaper and repaints every themed application from it.
#
# This replaces a ~110-line bash string that was CONCATENATED IN QML, with Python
# heredocs embedded inside it. That form was unreadable, impossible to test on its
# own, and interpolated the filename straight into shell with single quotes — so a
# wallpaper called "Bob's desk.png" broke it. Here the path is "$1", quoted once,
# and never re-parsed.
#
# ── Progress protocol ────────────────────────────────────────────────────────
# Every step prints one line to stdout:
#
#     STEP=<id>|<status>|<human text>        status: run | ok | skip | fail
#
# The panel parses these to show live progress. Full command output goes to the
# log file, not stdout, so the protocol can't be corrupted by a chatty tool.
#
# ── The wave ─────────────────────────────────────────────────────────────────
# Run by the shell (QS_WAVE=1, set by services/ThemeRunner), a change arrives as
# ONE wave from the bottom middle of the screen: the new picture spreading like
# water, the new colours eating the old look off the shell on the same front
# (services/WallWave.qml). This script paces it with three more lines:
#
#     WAVE=ready   the palette is computed — privately, in $STAGE, never in the
#                  file the shell watches — and about to be committed. The shell
#                  snapshots its look; this waits for the shell to say every one is taken
#                  (QS_WAVE_FROZEN; QS_WAVE_FREEZE_MS is only the base of its timeout).
#     WAVE=go      the palette is committed, ONCE, atomically. The shell recolours
#                  under its snapshots and spreads — once the apps recolouring
#                  under its curtain are done. This then waits for the shell to say
#                  the water has landed (QS_WAVE_LANDED; QS_WAVE_LAND_MS at most),
#                  so that neither the wallpaper daemon nor the fourteen apps below
#                  can change anything ahead of the front or stutter it.
#     WAVE=done    the real wallpaper is in place under the water.
#
# colors.json used to be rewritten four or five times per run (pywal, the black
# point, light mode, the override merge, the export), and the shell recoloured on
# every one — half-finished palettes included. Now it changes exactly once, at
# `go`, and the templates follow after the animation. Without QS_WAVE (run by
# hand, or animations off) nothing waits: the picture is set first with awww's
# own transition, as it always was.
#
# ── Every step is non-fatal ──────────────────────────────────────────────────
# One missing program must not stop the wallpaper from being applied. Each step
# reports fail and the run continues — the old version chained everything with
# `&&` plus `|| true`, which meant a genuine failure was indistinguishable from
# success and got reported as "applied!" regardless.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

# ── Flags ─────────────────────────────────────────────────────────────────────
# --palette-only  colours from an image WITHOUT making it the wallpaper. Used by
#                 the Wallpaper Engine integration (the scene renders itself; the
#                 palette follows its preview) and by the theme-mode switch (same
#                 picture, new palette). Must not touch the actual wallpaper and
#                 must not record the image as "current" — current_wallpaper_name
#                 names the STATIC wallpaper, and writing a preview.jpg into it
#                 would make the images tab lie about what's applied.
# --light         derive a LIGHT palette (pywal's -l): pale background, dark
#                 text. The shell's whole light mode is this one flag.
# --no-theme      set the picture and NOTHING else — no extraction, no reload,
#                 no app repaints. The palette on disk stays exactly as it is.
# --output NAME   set the picture on ONE monitor (awww's --outputs). The palette
#                 is still derived globally — the shell has one palette, and it
#                 follows whichever wallpaper was applied last.
# --export PATH   where to keep the stable COPY of whatever is current, for tools
#                 outside the shell (fastfetch and friends) that want to point at
#                 "the wallpaper" without knowing which file it is. Was hardcoded
#                 to $HOME/wallpapers/pywallpaper.jpg, which assumed the author's
#                 own layout; the shell passes Config.wallExportPath now. Omitted
#                 or empty means don't write the copy.
PALETTE_ONLY=0
LIGHT=0
NO_THEME=0
OUTPUTS=""
EXPORT=""
# --palette-key NAME  the identity for the per-wallpaper palette store (step 1c).
#                     Defaults to the wallpaper's basename; scenes pass their own
#                     key ("scene_<id>") because every workshop preview is called
#                     preview.* and basenames would all collide.
PALETTE_KEY=""
# --no-daemon  the shell renders the wallpaper itself (Config.wallShellRender) —
#              modules/desktop/WallpaperView draws $WALL and pans it. Skip the
#              awww step; everything else (palette, record_current) is unchanged.
NO_DAEMON=0
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --palette-only) PALETTE_ONLY=1 ;;
        --light)        LIGHT=1 ;;
        --no-theme)     NO_THEME=1 ;;
        --no-daemon)    NO_DAEMON=1 ;;
        --output)       OUTPUTS="${2:-}"; shift ;;
        --export)       EXPORT="${2:-}"; shift ;;
        --palette-key)  PALETTE_KEY="${2:-}"; shift ;;
        *) echo "STEP=args|fail|Unknown flag $1"; exit 2 ;;
    esac
    shift
done

WALL="${1:-}"
[[ -z "$WALL" ]] && { echo "STEP=args|fail|No wallpaper given"; exit 2; }
[[ -r "$WALL" ]] || { echo "STEP=args|fail|Cannot read $WALL"; exit 2; }

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
LOG="$CACHE/quicktest-wallpaper.log"
SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAL_CACHE="$CACHE/wal"
# The wave's shared half: STAGE (where this run's palette is built — nothing
# watches it, so it can be written as often as the steps below need), the pacing
# from the shell, the stage's lock and the one commit.
# shellcheck source=wave-lib.sh
source "$SHELL_DIR/scripts/wave-lib.sh"

# ── record_current ───────────────────────────────────────────────────────────
# Marks $WALL as the active wallpaper: the name for the shell to read back, and
# the optional stable copy for tools outside it.
#
# This was written out three times — once in the no-theme early exit, once in the
# palette-failure path, once at the end — which is why the export path had to be
# corrected in three places and why one of them could drift.
#
# The copy is skipped when its directory doesn't exist rather than created: the
# target is somewhere the USER nominated for other tools to read, and silently
# manufacturing a directory tree for a path someone typo'd is worse than not
# writing it. A fresh install with no ~/wallpapers therefore writes nothing here
# and reports nothing wrong, because nothing is.
record_current() {
    if [[ -n "$EXPORT" ]]; then
        if [[ -d "$(dirname "$EXPORT")" ]]; then
            cp "$WALL" "$EXPORT" 2>>"$LOG" || true
        else
            echo "skip export: $(dirname "$EXPORT") does not exist" >> "$LOG"
        fi
    fi
    basename "$WALL" > "$CACHE/current_wallpaper_name" 2>>"$LOG" || true
}

: > "$LOG"
{ echo "=== $(date -Is) ==="; echo "wallpaper: $WALL"; } >> "$LOG"

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

# ── The picture ──────────────────────────────────────────────────────────────
# set_wall <awww transition args...> — hands the picture to awww, or says why not.
# Skipped entirely in palette-only mode: the caller's scene IS the wallpaper, and
# painting a still behind it is wasted work that could also flash through during
# the scene's restart.
set_wall() {
    if [[ "$PALETTE_ONLY" == 1 ]]; then
        skip wallpaper "Scene renderer owns the picture"
    elif [[ "$NO_DAEMON" == 1 ]]; then
        skip wallpaper "Shell renders the wallpaper"
    elif have awww; then
        if [[ -n "$OUTPUTS" ]]; then
            step wallpaper "Setting wallpaper on $OUTPUTS" -- \
                awww img "$WALL" --outputs "$OUTPUTS" "$@"
        else
            step wallpaper "Setting wallpaper" -- awww img "$WALL" "$@"
        fi
    else
        skip wallpaper "awww not installed"
    fi
}

# Once the water has covered the screen (the shell says so — wave-lib.sh
# wait_landed): switch the real wallpaper under it, instantly, and say so. Only in
# a wave — without one the picture was set at step 1.
land() {
    wait_landed
    [[ "$WAVE" == 1 ]] && set_wall --transition-type none
    wave done
}

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

# ── 0. Animated preview → still frame ────────────────────────────────────────
# pywal can't read a GIF directly, and 16 of the workshop scenes here preview as
# one. The first frame is what the tile shows, so it's the honest colour source.
#
# ── The frame is the PALETTE's source, not the wallpaper ─────────────────────
# This used to do `WALL="$FRAME"`, overwriting the one variable that means "the
# wallpaper the user picked". Everything downstream then saw the extracted PNG
# instead, so applying a GIF as a real wallpaper:
#   · handed awww the still frame — an animated wallpaper that didn't animate;
#   · copied that frame to the export path; and
#   · recorded "scene-frame.png" as the current wallpaper name, which no library
#     entry matches, so the gallery's "applied" mark went blank and the greeter
#     export could not resolve it either.
#
# It survived unnoticed because the only caller that passes a GIF is the Wallpaper
# Engine palette path, which is --palette-only and so skips all three. The split is
# still the correct shape: PALETTE_SRC is what colours are read from, WALL stays
# what was actually chosen.
PALETTE_SRC="$WALL"
if [[ "$WALL" == *.gif || "$WALL" == *.GIF ]]; then
    if have magick; then
        FRAME="$WAL_CACHE/scene-frame.png"
        mkdir -p "$WAL_CACHE"
        if step frame "Extracting a still frame" -- magick "${WALL}[0]" "$FRAME"; then
            PALETTE_SRC="$FRAME"
        fi
    else
        skip frame "imagemagick not installed — colours from a GIF need it"
    fi
fi

# ── 1. The wallpaper itself ──────────────────────────────────────────────────
# Without a wave: FIRST, so the picture changes immediately and the colour work
# happens behind an already-updated desktop. In a wave the shell's water carries
# the picture across the screen instead, and awww switches under it once it has
# landed (see land()) — set now, it would change ahead of the water.
if [[ "$WAVE" == 0 ]]; then
    set_wall --transition-type right --transition-fps 144 --transition-duration 0.5
fi

# ── 1a. Theming disabled entirely? ───────────────────────────────────────────
# The user's master switch: the picture changes, the colours don't. Recorded as
# current like any other apply — it IS the wallpaper — then done. In a wave only the
# water moves: nothing is frozen, because nothing is about to change under it.
if [[ "$NO_THEME" == 1 ]]; then
    echo "STEP=palette|skip|Theming from wallpaper is off"
    wave go
    if [[ "$PALETTE_ONLY" != 1 ]]; then
        record_current
    fi
    land
    echo "STEP=done|ok|Wallpaper changed"
    echo "=== finished (no theme) $(date -Is) ===" >> "$LOG"
    exit 0
fi

# ── 1b–5. The palette, in one process ──────────────────────────────────────────
# scripts/stage-palette.py does, in order and exactly as these steps once did inline:
#   1b  every slot held by your scheme? Then extracting is pure waste — the merge would
#       overwrite all 18 a moment later — so this becomes "just change the picture"
#       (exit 10). Only a COMPLETE set skips: a partial one must still regenerate, or
#       the unpinned slots would keep the previous wallpaper's colours forever.
#   1c  a palette SAVED for this wallpaper (theming/wallpaper-palettes/<key>.json,
#       from the colours panel) replaces extraction and the corrections below.
#   2   extraction — `wal -i <src> -n -s -t -e [-l]`'s own calls, so its own cache:
#       a picture seen before (or prefetched by the shell) costs nothing to re-read.
#   3   the Arch logo's black point (a special case inherited from the previous
#       version, keyed on the filename; skipped in light mode and for saved palettes).
#   3b  light-mode contrast repair (pywal's -l leaves pale accents on a pale page).
#   4   your held colours, LAST, so saved edits are never clobbered by a reapply.
#   5   every template rendered once from the final palette.
# It used to be five processes rendering every template twice: ~310ms on a cached
# palette before the shell could start the wave. Now ~115ms. All into the stage —
# nothing watches it — and then the ONE commit.
OVERRIDES="$SHELL_DIR/theming/pywal-overrides.json"
if ! have wal; then
    skip palette "pywal not installed"
    wave go
    echo "STEP=done|fail|pywal missing — nothing else can run"
    exit 1
fi

WP_KEY="${PALETTE_KEY:-$(basename "$WALL")}"
WP_PALETTE="$SHELL_DIR/theming/wallpaper-palettes/$WP_KEY.json"
STAGE_ARGS=(--from "$WAL_CACHE/colors.json" --image "$PALETTE_SRC" --overrides "$OVERRIDES" --held-exit)
[[ "$LIGHT" == 1 ]] && STAGE_ARGS+=(--light)
[[ "$(basename "$WALL")" == "Arch.png" ]] && STAGE_ARGS+=(--blackpoint)
[[ -f "$WP_PALETTE" ]] && STAGE_ARGS+=(--saved "$WP_PALETTE")

stage_lock
stage_palette "${STAGE_ARGS[@]}"
case $? in
    0)  commit_stage ;;
    10) stage_unlock
        echo "STEP=palette|skip|Colours held by your scheme"
        wave go
        [[ "$PALETTE_ONLY" != 1 ]] && record_current
        land
        echo "STEP=done|ok|Wallpaper changed"
        echo "=== finished (colours held) $(date -Is) ===" >> "$LOG"
        exit 0 ;;
    # No palette: nothing new to commit, so the old colours stay (and are pushed out
    # again below, as they always were) — only the water moves.
    *)  ;;
esac
stage_unlock
wave go

# ── 6. Record what's current ─────────────────────────────────────────────────
# Read by fastfetch and by the panel to show which wallpaper is active. Written the
# moment the picture is decided rather than at the very end: the shell renderer
# draws it, and with the wave running its water already carries it. Not in
# palette-only mode — see the flag's comment at the top.
if [[ "$PALETTE_ONLY" != 1 ]]; then
    record_current
fi

land

# ── 7. Tell the DESKTOP which mode this is ───────────────────────────────────
# GTK4/libadwaita apps pick light or dark from the color-scheme preference, not
# from the palette — a light palette under `prefer-dark` still renders every
# dialog dark, which is half of "light mode doesn't look right". The reload
# script's theme-flip trick reaches GTK3; this reaches the rest.
if have gsettings; then
    if [[ "$LIGHT" == 1 ]]; then
        step gtkmode "Switching apps to light mode" -- \
            gsettings set org.gnome.desktop.interface color-scheme prefer-light
    else
        step gtkmode "Switching apps to dark mode" -- \
            gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    fi
else
    skip gtkmode "gsettings not installed"
fi

# ── 8-15. Push the palette everywhere ────────────────────────────────────────
# Shared with the colour-scheme editor — see scripts/reload-theme.sh. Its stdout
# IS the step protocol, so it is passed straight through rather than captured.
# --committed: the palette is already merged and live; it only fans it out.
# Under `nice`: this runs AFTER the wave has landed, in parallel (GTK flip, kitty, wal_env,
# templates, the apps' residue), and the shell is drawing the hand-over at the same time. Nothing
# here is on the critical path any more, so it yields to the shell when the CPU is contended
# (Discord and Spotify alone were ~2.5 cores at idle) — the same reason the prefetch and the
# cursor regeneration are niced. The wave's own app recolour (reload-theme.sh --app …, under the
# curtain) is a separate invocation and is NOT niced: the front is waiting for it.
nice -n 10 bash "$SHELL_DIR/scripts/reload-theme.sh" --committed

echo "STEP=done|ok|Wallpaper applied"
echo "=== finished $(date -Is) ===" >> "$LOG"

# Explicit rather than inherited from whatever the last line happened to return. This
# script was fine by luck; reload-theme.sh was not — its final `pgrep` for an app that
# wasn't running became the exit code and made every clean run report "finished with
# errors". Step failures travel in the STEP protocol, not in $?.
exit 0
