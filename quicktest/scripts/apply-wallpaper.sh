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
PALETTE_ONLY=0
LIGHT=0
NO_THEME=0
OUTPUTS=""
while [[ "${1:-}" == --* ]]; do
    case "$1" in
        --palette-only) PALETTE_ONLY=1 ;;
        --light)        LIGHT=1 ;;
        --no-theme)     NO_THEME=1 ;;
        --output)       OUTPUTS="${2:-}"; shift ;;
        *) echo "STEP=args|fail|Unknown flag $1"; exit 2 ;;
    esac
    shift
done

WALL="${1:-}"
[[ -z "$WALL" ]] && { echo "STEP=args|fail|No wallpaper given"; exit 2; }
[[ -r "$WALL" ]] || { echo "STEP=args|fail|Cannot read $WALL"; exit 2; }

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/quicktest-wallpaper.log"
SHELL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAL_CACHE="$HOME/.cache/wal"

: > "$LOG"
{ echo "=== $(date -Is) ==="; echo "wallpaper: $WALL"; } >> "$LOG"

# ── step <id> <human text> -- <command...> ───────────────────────────────────
# Runs a command, reports it, and never aborts the script.
step() {
    local id="$1" text="$2"; shift 3      # shift past id, text and the -- separator
    echo "STEP=$id|run|$text"
    echo "--- [$id] $*" >> "$LOG"
    if "$@" >> "$LOG" 2>&1; then
        echo "STEP=$id|ok|$text"
        return 0
    fi
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

# ── 0. Animated preview → still frame ────────────────────────────────────────
# pywal can't read a GIF directly, and 16 of the workshop scenes here preview as
# one. The first frame is what the tile shows, so it's the honest colour source.
if [[ "$WALL" == *.gif || "$WALL" == *.GIF ]]; then
    if have magick; then
        FRAME="$WAL_CACHE/scene-frame.png"
        mkdir -p "$WAL_CACHE"
        if step frame "Extracting a still frame" -- magick "${WALL}[0]" "$FRAME"; then
            WALL="$FRAME"
        fi
    else
        skip frame "imagemagick not installed — colours from a GIF need it"
    fi
fi

# ── 1. The wallpaper itself ──────────────────────────────────────────────────
# Done FIRST so the picture changes immediately and the colour work happens
# behind an already-updated desktop. Skipped entirely in palette-only mode: the
# caller's scene IS the wallpaper, and painting a still behind it is wasted work
# that could also flash through during the scene's restart.
if [[ "$PALETTE_ONLY" == 1 ]]; then
    skip wallpaper "Scene renderer owns the picture"
elif have awww; then
    if [[ -n "$OUTPUTS" ]]; then
        step wallpaper "Setting wallpaper on $OUTPUTS" -- \
            awww img "$WALL" --outputs "$OUTPUTS" \
                --transition-type right --transition-fps 144 --transition-duration 0.5
    else
        step wallpaper "Setting wallpaper" -- \
            awww img "$WALL" --transition-type right --transition-fps 144 --transition-duration 0.5
    fi
else
    skip wallpaper "awww not installed"
fi

# ── 1a. Theming disabled entirely? ───────────────────────────────────────────
# The user's master switch: the picture changes, the colours don't. Recorded as
# current like any other apply — it IS the wallpaper — then done.
if [[ "$NO_THEME" == 1 ]]; then
    echo "STEP=palette|skip|Theming from wallpaper is off"
    if [[ "$PALETTE_ONLY" != 1 ]]; then
        cp "$WALL" "$HOME/wallpapers/pywallpaper.jpg" 2>>"$LOG" || true
        basename "$WALL" > "$HOME/.cache/current_wallpaper_name" 2>>"$LOG" || true
    fi
    echo "STEP=done|ok|Wallpaper changed"
    echo "=== finished (no theme) $(date -Is) ===" >> "$LOG"
    exit 0
fi

# ── 1b. Is the palette entirely yours? ──────────────────────────────
# If the overrides file pins EVERY slot — which is what applying a colour scheme
# does — then extracting colours from this image is pure waste: the merge in
# reload-theme.sh would overwrite all 18 of them a moment later. Worse than waste:
# it repaints fourteen applications for a result you cannot see, and makes
# changing wallpaper feel slow.
#
# So a complete override set turns this into "just change the picture".
#
# ── Only when COMPLETE, deliberately ────────────────────────────────
# A PARTIAL set (a few pinned slots) must still regenerate, or the unpinned slots
# would keep the PREVIOUS wallpaper's colours forever and the palette would
# quietly stop matching anything. "Some colours are held" and "the whole palette
# is held" are different situations, and only the second one can skip.
OVERRIDES="$SHELL_DIR/theming/pywal-overrides.json"
palette_fully_held() {
    [[ -f "$OVERRIDES" ]] || return 1
    python3 - "$OVERRIDES" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    sys.exit(1)
have = set(d.get("special", {})) | set(d.get("colors", {}))
need = {"background", "foreground"} | {"color%d" % i for i in range(16)}
sys.exit(0 if need <= have else 1)
PYEOF
}

if palette_fully_held; then
    echo "STEP=palette|skip|Colours held by your scheme"
    if [[ "$PALETTE_ONLY" != 1 ]]; then
        cp "$WALL" "$HOME/wallpapers/pywallpaper.jpg" 2>>"$LOG" || true
        basename "$WALL" > "$HOME/.cache/current_wallpaper_name" 2>>"$LOG" || true
    fi
    echo "STEP=done|ok|Wallpaper changed"
    echo "=== finished (colours held) $(date -Is) ===" >> "$LOG"
    exit 0
fi

# ── 2. Extract the palette ───────────────────────────────────────────────────
if have wal; then
    if [[ "$LIGHT" == 1 ]]; then
        step palette "Extracting colours (light)" -- wal -i "$WALL" -n -l
    else
        step palette "Extracting colours" -- wal -i "$WALL" -n
    fi
else
    skip palette "pywal not installed"
    echo "STEP=done|fail|pywal missing — nothing else can run"
    exit 1
fi

# ── 3. Per-wallpaper corrections ─────────────────────────────────────────────
# One wallpaper (the Arch logo) extracts to a near-black that pywal lifts to a
# dark grey, which looks washed out against the logo's true black. This forces it
# back down.
#
# It is a SPECIAL CASE keyed on the filename, inherited from the previous
# version. Left working rather than quietly dropped, but it belongs in a data
# file keyed by basename if a second wallpaper ever needs one.
# Skipped in light mode: forcing background to pure black is precisely the
# opposite of what -l just produced.
if [[ "$(basename "$WALL")" == "Arch.png" && "$LIGHT" != 1 ]]; then
    step patch "Correcting black point" -- python3 - "$WAL_CACHE/colors.json" <<'PY'
import json, sys
p = sys.argv[1]
d = json.load(open(p))
d["special"]["background"] = "#000000"
d["colors"]["color0"] = "#000000"
d["colors"]["color8"] = "#444444"
json.dump(d, open(p, "w"), indent=4)
PY
fi


# ── 3b. Light-mode contrast repair ───────────────────────────────────────────
# pywal's -l keeps the wallpaper's accent colours at whatever lightness they
# came in at, which against a pale background means pale-on-pale — grey text,
# invisible accents, the whole "cursed" light mode. Deterministic fix in HLS:
# accents are capped at 45% lightness with a saturation floor so they read as
# COLOURS on white; foreground is forced genuinely dark rather than pywal's
# soft grey; color8 (the muted tone) stays visible instead of vanishing.
if [[ "$LIGHT" == 1 ]]; then
    step lightfix "Repairing light-mode contrast" -- python3 - "$WAL_CACHE/colors.json" <<'PY'
import json, sys, colorsys
p = sys.argv[1]
d = json.load(open(p))
def rgb(h):
    h = h.lstrip('#'); return tuple(int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
def hexs(r, g, b):
    return '#%02x%02x%02x' % tuple(min(255, round(x * 255)) for x in (r, g, b))
def fix(h, max_l, min_s):
    r, g, b = rgb(h)
    hh, l, s = colorsys.rgb_to_hls(r, g, b)
    return hexs(*colorsys.hls_to_rgb(hh, min(l, max_l), max(s, min_s)))
def raise_l(h, min_l):
    r, g, b = rgb(h)
    hh, l, s = colorsys.rgb_to_hls(r, g, b)
    return hexs(*colorsys.hls_to_rgb(hh, max(l, min_l), s))
for i in list(range(1, 7)) + list(range(9, 15)):
    k = "color%d" % i
    if k in d["colors"]:
        d["colors"][k] = fix(d["colors"][k], 0.45, 0.35)
# The background must read as PAPER, not as a slightly-lifted wallpaper tone —
# a mid-grey "light" background is most of what made light mode look wrong.
d["special"]["background"] = raise_l(d["special"]["background"], 0.90)
d["colors"]["color0"] = d["special"]["background"]
d["special"]["foreground"] = fix(d["special"]["foreground"], 0.16, 0.0)
d["colors"]["color7"]  = d["special"]["foreground"]
d["colors"]["color15"] = fix(d["colors"].get("color15", d["special"]["foreground"]), 0.25, 0.0)
if "color8" in d["colors"]:
    d["colors"]["color8"] = fix(d["colors"]["color8"], 0.55, 0.0)
# Atomic replace, not truncate-and-write: the shell WATCHES this file, and a
# read during the write window is how "colors.json is not valid JSON" got into
# the log. os.replace is atomic on the same filesystem, so a reader sees the
# old document or the new one, never half of either.
import os, tempfile
fd, tmp = tempfile.mkstemp(dir=os.path.dirname(p), suffix=".tmp")
with os.fdopen(fd, "w") as f:
    json.dump(d, f, indent=4)
os.replace(tmp, p)
PY
fi

# ── 3c. Tell the DESKTOP which mode this is ──────────────────────────────────
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

# ── 4-11. Push the palette everywhere ────────────────────────────────────────
# Shared with the colour-scheme editor — see scripts/reload-theme.sh. Its stdout
# IS the step protocol, so it is passed straight through rather than captured.
bash "$SHELL_DIR/scripts/reload-theme.sh"

# ── 12. Record what's current ────────────────────────────────────────────────
# Read by fastfetch and by the panel to show which wallpaper is active. Not in
# palette-only mode — see the flag's comment at the top.
if [[ "$PALETTE_ONLY" != 1 ]]; then
    cp "$WALL" "$HOME/wallpapers/pywallpaper.jpg" 2>>"$LOG" || true
    basename "$WALL" > "$HOME/.cache/current_wallpaper_name" 2>>"$LOG" || true
fi

echo "STEP=done|ok|Wallpaper applied"
echo "=== finished $(date -Is) ===" >> "$LOG"

# Explicit rather than inherited from whatever the last line happened to return. This
# script was fine by luck; reload-theme.sh was not — its final `pgrep` for an app that
# wasn't running became the exit code and made every clean run report "finished with
# errors". Step failures travel in the STEP protocol, not in $?.
exit 0
