#!/usr/bin/env bash
# Writes the live pywal palette into every Zen profile's chrome/userChrome.css.
#
# Called by reload-theme.sh (step "zen"). Two modes, picked by whether Pywalfox is installed:
#
#   live    Zen repaints a RUNNING window, no restart. See "Live mode" below.
#   static  Colours are literals, so they only change when Zen restarts (userChrome.css is
#           read once, at startup — a Firefox limitation).
#
# Profiles come from profiles.ini, never a literal directory name: the old version of
# this script hardcoded one profile's random-looking prefix, which does not exist on any
# other machine (nor, after a profile was recreated, on the author's), so it wrote to a
# directory that wasn't there and the browser was never themed at all.
#
# ── Live mode ────────────────────────────────────────────────────────────────
# Pywalfox pushes the palette to a running browser through the WebExtension theme API
# (`pywalfox update`, called by apps-lib.sh recolor_browser), which sets CSS variables
# on the window root: --lwt-accent-color, --toolbar-background-color, … Two things stood
# between that and Zen's own surfaces, both measured against the installed build:
#
#   1. Zen ships `zen.theme.disable-lightweight = true`, and its theme consumer then
#      substitutes the DEFAULT theme for whatever was applied (omni.ja, the
#      LightweightThemeConsumer). So Pywalfox's theme never reached the window at all,
#      and any CSS reading those variables saw nothing. Fixed by user.js below; read at
#      startup, so the first time it needs one restart.
#   2. This file pinned literals with !important. A literal can't follow a theme. Zen's
#      own variables and rules now point AT the theme variables with var(); the literal
#      in each var() is only what shows before a theme has been applied.
#
# Names matter: this Zen has no `--toolbar-bgcolor` (older Firefox's name; 0 hits in its
# omni.ja) — the variable is `--toolbar-background-color`. A var() on a name that doesn't
# exist silently falls back to its literal, which looks exactly like "live reload doesn't
# work". Check a name against the installed omni.ja before using it.

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}"
COLORS="$CACHE/wal/colors"

[[ -r "$COLORS" ]] || { echo "no palette at $COLORS" >&2; exit 1; }
mapfile -t c < "$COLORS"
(( ${#c[@]} >= 16 )) || { echo "palette has ${#c[@]} colours, need 16" >&2; exit 1; }

# Same roles the GTK4 step uses (reload-theme.sh): background = color0, text = color7,
# accent = color1, surface/border = color8.
bg=${c[0]} fg=${c[7]} accent=${c[1]} surface=${c[8]}

# Without Pywalfox nothing would ever change the theme variables, so a var() would sit on
# its fallback forever: write the static set instead.
if command -v pywalfox >/dev/null 2>&1; then live=1; else live=0; fi
if (( live )); then
    bgv="var(--lwt-accent-color, $bg)"          fgv="var(--lwt-text-color, $fg)"
    fieldv="var(--toolbar-field-background-color, $surface)"
    borderv="var(--toolbar-field-border-color, $surface)"
    accentv="var(--toolbarbutton-icon-fill, $accent)"
    tbv="var(--toolbar-background-color, $bg)"  tbtextv="var(--toolbar-text-color, $fg)"
else
    bgv=$bg fgv=$fg fieldv=$surface borderv=$surface accentv=$accent tbv=$bg tbtextv=$fg
fi

# Every profile Zen knows about, from the regular config dir and the legacy ~/.zen one.
# Only [ProfileN] sections: the [InstallXXXX] ones repeat a Default= path and would
# otherwise be written twice.
profiles=()
for root in "${XDG_CONFIG_HOME:-$HOME/.config}/zen" "$HOME/.zen"; do
    [[ -f "$root/profiles.ini" ]] || continue
    while IFS='|' read -r rel path; do
        [[ -n "$path" ]] || continue
        [[ "$rel" == 0 ]] && profiles+=("$path") || profiles+=("$root/$path")
    done < <(awk -F= '
        function flush() { if (path != "") print rel "|" path; path = ""; rel = 1 }
        /^\[/ { flush(); inprof = ($0 ~ /^\[Profile[0-9]+\]/); next }
        inprof && $1 == "IsRelative" { rel = $2 }
        inprof && $1 == "Path"       { path = substr($0, 6) }
        END { flush() }' "$root/profiles.ini")
done

# The Firefox theme variables themselves — only pinned when nothing else will set them.
# Both generations of names: older Firefox/Zen builds read the first, current ones the second.
static_theme_vars() {
cat <<EOF

  --toolbar-bgcolor:                      $bg !important;
  --toolbar-color:                        $fg !important;
  --arrowpanel-background:                $bg !important;
  --arrowpanel-color:                     $fg !important;
  --arrowpanel-border-color:              $surface !important;
  --toolbar-background-color:             $bg !important;
  --toolbar-text-color:                   $fg !important;
  --panel-background-color:               $bg !important;
  --panel-text-color:                     $fg !important;
  --panel-border-color:                   $surface !important;

  --lwt-accent-color:                     $bg !important;
  --lwt-text-color:                       $fg !important;
  --toolbarbutton-icon-fill:              $accent !important;
  --tab-selected-bgcolor:                 $surface !important;
  --tab-selected-textcolor:               $fg !important;

  --urlbar-box-bgcolor:                   $surface !important;
  --urlbar-box-text-color:                $fg !important;
  --urlbar-box-focus-bgcolor:             $surface !important;
  --toolbar-field-background-color:       $surface !important;
  --toolbar-field-color:                  $fg !important;
  --toolbar-field-text-color:             $fg !important;
  --toolbar-field-focus-background-color: $surface !important;
  --toolbar-field-focus-color:            $fg !important;
  --toolbar-field-border-color:           $surface !important;
EOF
}

render() {
    local mode="static"; (( live )) && mode="live (Pywalfox owns the theme variables)"
cat <<EOF
/* Generated by quicktest scripts/update-zen-colors.sh — do not edit.
   Regenerated on every wallpaper/scheme change.
   Mode: $mode */
:root {
  --zen-primary-color:                    $accentv !important;
  --zen-colors-primary:                   $accentv !important;
  --zen-colors-secondary:                 $fieldv !important;
  --zen-colors-tertiary:                  $tbv !important;
  --zen-colors-border:                    $borderv !important;
  --zen-branding-dark:                    $bgv !important;
  --zen-branding-paper:                   $fgv !important;
  --zen-main-browser-background:          $bgv !important;
  --zen-main-browser-background-toolbar:  $bgv !important;
  --zen-navigator-toolbox-background:     $bgv !important;
  --zen-themed-toolbar-bg-transparent:    $bgv !important;
$( (( live )) || static_theme_vars )
}

.zen-toolbar-background,
#zen-main-app-wrapper,
#navigator-toolbox,
#titlebar {
  background: $bgv !important;
}

.zen-browser-generic-background::after,
.zen-browser-generic-background::before {
  background: $bgv !important;
}

/* Sidebar / workspace strip */
#zen-sidebar-box,
#zen-workspaces-button {
  background: $bgv !important;
  color: $fgv !important;
}

findbar, .findbar-container {
  background: $tbv !important;
  color: $tbtextv !important;
}
EOF
}

# set_pref <user.js> <key> <value>: make user.js say exactly `key = value`, touching no other
# line — user.js is the user's own file.
set_pref() {
    local f="$1" key="$2" val="$3"
    grep -qsF "user_pref(\"$key\", $val);" "$f" && return 0
    { grep -vsF "user_pref(\"$key\"," "$f" || true; echo "user_pref(\"$key\", $val);"; } > "$f.tmp" \
        && mv -f "$f.tmp" "$f"
}

(( ${#profiles[@]} )) || { echo "no Zen profile found" >&2; exit 1; }

css="$(render)"
rc=0
for dir in "${profiles[@]}"; do
    [[ -d "$dir" ]] || continue
    mkdir -p "$dir/chrome"
    # Rename into place so a Zen starting mid-write never reads half a file.
    if printf '%s\n' "$css" > "$dir/chrome/.userChrome.css.tmp" \
       && mv -f "$dir/chrome/.userChrome.css.tmp" "$dir/chrome/userChrome.css"; then
        echo "wrote $dir/chrome/userChrome.css (live=$live)"
    else
        echo "could not write $dir/chrome/userChrome.css" >&2; rc=1
    fi
    # userChrome.css is ignored unless this pref is on.
    set_pref "$dir/user.js" toolkit.legacyUserProfileCustomizations.stylesheets true
    # Live mode only: let Zen apply a browser theme at all (see the header). Left alone in
    # static mode — nothing there needs it, and it is the user's preference to own.
    (( live )) && set_pref "$dir/user.js" zen.theme.disable-lightweight false
done
exit "$rc"
