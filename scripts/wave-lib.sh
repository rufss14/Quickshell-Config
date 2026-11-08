# ── wave-lib.sh ───────────────────────────────────────────────────────────────
# Sourced, never run: the half of a theming run's WAVE that apply-wallpaper.sh and
# reload-theme.sh share (services/WallWave.qml — see the header of
# apply-wallpaper.sh for the protocol). One copy, because two copies of "how the
# palette is committed" is exactly how the halves of this pipeline drifted before.
#
# The caller sets CACHE, WAL_CACHE, LOG and SHELL_DIR first, and defines step/skip/
# have (apps-lib.sh uses them). This defines:
#   STAGE          where a run builds its palette — nothing watches it
#   WAVE           1 when the shell is watching (QS_WAVE=1), else 0
#   wave <word>    prints WAVE=<word>
#   nap_ms <ms>    sleeps, only in a wave
#   wait_frozen    waits for the shell's word that every snapshot is taken
#   wait_landed    waits for the shell to say the water has landed (LAND_MS at most)
#   stage_lock / stage_unlock    one run at a time through the stage
#   stage_palette  the run's whole palette + every template, into $STAGE/out
#                  (scripts/stage-palette.py — one process)
#   write_gtk4_css / write_gtk3_css <colors.sh>   GTK's gtk.css, by rename (commit_stage; steps 6/6b)
#   gtk3_refresh   make running GTK apps re-read it (commit_stage; step 7 as the fallback)
#   commit_stage   the apps' prep (apps-lib.sh), WAVE=ready, the freeze, then the
#                  ONE atomic swap; exports PREPARED_AT (ns) for the fan-out's "done
#                  with the wave" check
#   install_templates   the committed run's rendered templates into the live cache

STAGE="$CACHE/wal-stage"
KITTY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/kitty"

# ── Pacing, from the shell ───────────────────────────────────────────────────
# Milliseconds, and validated as such: they come from the environment, and a
# malformed one must mean "don't wait", not a `sleep` error mid-run.
WAVE=0
[[ "${QS_WAVE:-}" == 1 ]] && WAVE=1
FREEZE_MS="${QS_WAVE_FREEZE_MS:-0}"; [[ "$FREEZE_MS" =~ ^[0-9]{1,5}$ ]] || FREEZE_MS=0
LAND_MS="${QS_WAVE_LAND_MS:-0}";     [[ "$LAND_MS"   =~ ^[0-9]{1,5}$ ]] || LAND_MS=0

wave() { echo "WAVE=$1"; }

# How each app the wave reaches one by one is recoloured, and staged ahead of it.
# shellcheck source=apps-lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/apps-lib.sh"

# Milliseconds since this script started, for the log: every step says what it cost.
_T0="${EPOCHREALTIME/./}"
elapsed_ms() { echo $(( (${EPOCHREALTIME/./} - _T0) / 1000 )); }

nap_ms() {
    [[ "$WAVE" == 1 && "$1" -gt 0 ]] || return 0
    sleep "$(( $1 / 1000 )).$(printf '%03d' $(( $1 % 1000 )))"
}

# ── Waiting for the water to land ────────────────────────────────────────────
# The shell creates QS_WAVE_LANDED when this change's spread has finished
# (ThemeRunner, on WallWave.landed). The spread can be held while a slow app
# repaints under the curtain (Contagion), so a fixed sleep would either be the worst
# case every time or let the wallpaper daemon and the fan-out go ahead of the front.
# LAND_MS is only the timeout. The path comes from the environment and is `rm`'d,
# so it must be the shell's own naming, nothing else.
LANDED="${QS_WAVE_LANDED:-}"
[[ "$LANDED" =~ ^/[^[:cntrl:]]*/quickshell-quicktest-wave-[0-9]+\.landed$ ]] || LANDED=""
[[ -n "$LANDED" ]] && rm -f -- "$LANDED"     # a stale one from an earlier session's token

# The same for the freeze: the shell creates QS_WAVE_FROZEN once every window's snapshot is
# drawn and covering (WallWave.snapped), and this waits for exactly that — not a fixed
# FREEZE_MS, which was a guess at "three frames" with margin on top. FREEZE_MS is now only the
# BASE of the timeout (three times it); no flag (an older shell, a bad path) falls back to the
# old fixed sleep. Path validated like LANDED: it is `rm`'d.
FROZEN="${QS_WAVE_FROZEN:-}"
[[ "$FROZEN" =~ ^/[^[:cntrl:]]*/quickshell-quicktest-wave-[0-9]+\.frozen$ ]] || FROZEN=""
[[ -n "$FROZEN" ]] && rm -f -- "$FROZEN"

wait_frozen() {
    [[ "$WAVE" == 1 ]] || return 0
    if [[ -z "$FROZEN" ]]; then nap_ms "$FREEZE_MS"; return 0; fi
    local waited=0 cap=$(( FREEZE_MS * 3 ))
    while [[ ! -e "$FROZEN" && "$waited" -lt "$cap" ]]; do
        sleep 0.01
        waited=$(( waited + 10 ))
    done
    rm -f -- "$FROZEN"
}

wait_landed() {
    [[ "$WAVE" == 1 ]] || return 0
    if [[ -z "$LANDED" ]]; then nap_ms "$LAND_MS"; return 0; fi
    local waited=0
    while [[ ! -e "$LANDED" && "$waited" -lt "$LAND_MS" ]]; do
        sleep 0.04
        waited=$(( waited + 40 ))
    done
    rm -f -- "$LANDED"
}

# ── The stage's lock ─────────────────────────────────────────────────────────
# A wallpaper and a scheme can be applied at once (two runners), and both build
# their palette in $STAGE; interleaved, the commit would be half of each. Held from
# the stage's first write to the commit. A lock that can't be had in 15s is waited
# out, not failed on: racing, the old behaviour, beats no colours at all.
stage_lock() {
    mkdir -p "$STAGE"
    exec 8>"$STAGE/.lock"
    flock -w 15 8 || echo "stage lock: still held after 15s — going ahead" >> "$LOG"
}
stage_unlock() { flock -u 8 2>/dev/null || true; }

# ── The palette ──────────────────────────────────────────────────────────────
# stage_palette <stage-palette.py args…>: $STAGE/out/colors.json and every template,
# from one process (see that script for why, and for how it stays `wal -i`'s exact
# palette). PYWAL_CACHE_DIR is the stage, whose schemes/ is the live cache, so a
# picture extracted before — by any run, or the prefetch — is found at once.
# Returns the script's code: 0 staged, 10 every slot held, else failed.
stage_palette() {
    mkdir -p "$WAL_CACHE/schemes"
    if [[ ! -L "$STAGE/schemes" ]]; then
        rm -rf -- "${STAGE:?}/schemes"
        ln -s "$WAL_CACHE/schemes" "$STAGE/schemes"
    fi
    rm -rf -- "${STAGE:?}/out"
    local t=$(elapsed_ms) rc
    PYWAL_CACHE_DIR="$STAGE" python3 "$SHELL_DIR/scripts/stage-palette.py" --out "$STAGE/out" "$@" 2>>"$LOG"
    rc=$?
    echo "--- [palette] stage-palette.py → $rc ($(( $(elapsed_ms) - t )) ms)" >> "$LOG"
    return "$rc"
}

# ── GTK4 / libadwaita colours ─────────────────────────────────────────────────
# write_gtk4_css <colors.sh>: ~/.config/gtk-4.0/gtk.css from a palette, written by RENAME and
# not at all when it would be byte-identical.
#
# One copy, called twice: commit_stage writes it WITH the commit and reload-theme.sh step 6b
# is the fallback. It has to be the commit: an open GTK4 app with the live module loaded
# (scripts/gtk-live) repaints the moment this file changes, and the fan-out runs after the
# wave — so written there, Nautilus changed visibly AFTER the front had passed it (reported:
# "slow, and it didn't go with the wave"). At the commit the shell's curtain is up over every
# window, so the app repaints underneath it and the front reveals it already recoloured, like
# the borders and the terminals.
#
# By rename because that same app reloads on the change, and a `cat >` truncates first: it
# would read an empty sheet — libadwaita's default colours for a frame. Resolved through a
# legacy symlink first, so the rename replaces what the link points at and leaves the link
# (and anything still watching it) alone. colors.sh is sourced in a subshell: it ends with an
# unguarded $FZF_DEFAULT_OPTS, fatal under `set -u` (see load_palette in reload-theme.sh), and
# it sets bare colorN variables nobody else wants.
#
# ── Every surface on `background`, never color0 ──────────────────────────────
# The shell (PaletteRoles `base`), kitty, Discord and qt6ct's Window all stand on pywal's
# special.background. These sheets used color0 — the darkest ramp slot, which pywal and
# stage-palette.py keep apart from the background on purpose (a lifted ramp end) — so every
# GTK4 window, and GTK3's header bars, cards, popovers and sidebars, sat on a visibly
# different ground from everything around them (2026-10-06: #2F231D in GTK against
# #251912 everywhere else). headerbar_backdrop_color too: it is the header bar's ground while
# the window is UNFOCUSED, and was color1 — every inactive GTK4 window wore an accent-coloured
# title bar. The *_fg_color, accent and status slots are unchanged.
write_gtk4_css() {
    local sh="$1" target tmp
    target="$(readlink -f "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/gtk.css")"
    tmp="$target.tmp"
    mkdir -p "$(dirname "$target")" || return 1
    (
        set +u
        # shellcheck disable=SC1090
        source "$sh" || exit 1
        [[ -n "${color1:-}" && -n "${background:-}" ]] || exit 1
        cat <<CSS
/* Generated by quicktest apply-wallpaper.sh — edits will be overwritten. */
@define-color accent_color $color1;
@define-color accent_bg_color $color1;
@define-color accent_fg_color $color0;
@define-color destructive_color $color3;
@define-color destructive_bg_color $color3;
@define-color destructive_fg_color $color0;
@define-color success_color $color2;
@define-color success_bg_color $color2;
@define-color success_fg_color $color0;
@define-color warning_color $color3;
@define-color warning_bg_color $color3;
@define-color warning_fg_color $color0;
@define-color error_color $color3;
@define-color error_bg_color $color3;
@define-color error_fg_color $color0;
@define-color window_bg_color $background;
@define-color window_fg_color $color7;
@define-color view_bg_color $background;
@define-color view_fg_color $color7;
@define-color headerbar_bg_color $background;
@define-color headerbar_fg_color $color7;
@define-color headerbar_border_color $color8;
@define-color headerbar_backdrop_color $background;
@define-color headerbar_shade_color $color8;
@define-color card_bg_color $background;
@define-color card_fg_color $color7;
@define-color card_shade_color $color8;
@define-color dialog_bg_color $background;
@define-color dialog_fg_color $color7;
@define-color popover_bg_color $background;
@define-color popover_fg_color $color7;
@define-color shade_color $color8;
@define-color scrollbar_outline_color $color1;
@define-color sidebar_bg_color $background;
@define-color sidebar_fg_color $color7;
@define-color sidebar_backdrop_color $background;
@define-color sidebar_shade_color $color8;
CSS
    ) > "$tmp" || { rm -f "$tmp"; return 1; }
    if cmp -s "$tmp" "$target"; then rm -f "$tmp"; return 0; fi
    mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    GTK_CSS_CHANGED=1
}

# write_gtk3_css <colors.sh>: the same for GTK3 (~/.config/gtk-3.0/gtk.css), same reasons. A
# GTK3 app doesn't watch the file; it re-reads it when the gtk-theme key changes, which is
# gtk3_refresh below. Sets GTK_CSS_CHANGED=1 when it replaced the file, so a caller can skip the
# refresh when the palette didn't change.
write_gtk3_css() {
    local sh="$1" target tmp
    target="$(readlink -f "${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/gtk.css")"
    tmp="$target.tmp"
    mkdir -p "$(dirname "$target")" || return 1
    (
        set +u
        # shellcheck disable=SC1090
        source "$sh" || exit 1
        [[ -n "${color1:-}" && -n "${background:-}" ]] || exit 1
        cat <<CSS
/* Generated by quicktest apply-wallpaper.sh — edits will be overwritten. */
@define-color accent_color $color1;
@define-color accent_bg_color $color1;
@define-color accent_fg_color $color0;
@define-color destructive_color $color3;
@define-color destructive_bg_color $color3;
@define-color destructive_fg_color $color0;
@define-color success_color $color2;
@define-color success_bg_color $color2;
@define-color success_fg_color $color0;
@define-color warning_color $color3;
@define-color warning_bg_color $color3;
@define-color warning_fg_color $color0;
@define-color error_color $color3;
@define-color error_bg_color $color3;
@define-color error_fg_color $color0;
@define-color window_bg_color $background;
@define-color window_fg_color $foreground;
@define-color view_bg_color $background;
@define-color view_fg_color $foreground;
@define-color headerbar_bg_color $background;
@define-color headerbar_fg_color $foreground;
@define-color popover_bg_color $background;
@define-color popover_fg_color $foreground;
@define-color card_bg_color $background;
@define-color card_fg_color $foreground;
@define-color sidebar_bg_color $background;
@define-color sidebar_fg_color $foreground;
CSS
    ) > "$tmp" || { rm -f "$tmp"; return 1; }
    if cmp -s "$tmp" "$target"; then rm -f "$tmp"; return 0; fi
    mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
    GTK_CSS_CHANGED=1
}

# gtk3_refresh: make every running GTK app re-read its gtk.css, WITHOUT killing it. Runs WITH
# the commit, in the background (it sleeps 0.25s between its two writes), for the same reason
# as the sheets: GTK3 apps repaint when the key changes, and from the fan-out that was after
# the wave. It stamps $STAGE/.app-gtk3 so the fan-out's own call (reload-theme.sh step 7,
# `unless_done`) skips — flipping twice would repaint every GTK3 app a second time.
gtk3_refresh() {
    # ── Two ways this used to leave GTK on Adwaita-dark for good ──────────────
    # The refresh sets the key to another theme and back, remembering the value it read first. Run twice at
    # once — two colour changes close together, the commit's background call and the fan-out's — the second
    # read the FIRST one's temporary "Adwaita-dark" as the user's theme and "restored" it, so adw-gtk3 was gone
    # and Settings › Setup then (truthfully) said GTK was not set up. A run killed between the two writes did
    # the same. So: one refresh at a time (flock), and the real value is written down BEFORE the toggle and
    # removed after it — a record still there at the start means a toggle never finished, and is the value to
    # put back, whatever the key says now.
    local lock="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/quicktest-gtk-refresh.lock"
    local real="${XDG_STATE_HOME:-$HOME/.local/state}/quicktest-gtk-theme-real"
    mkdir -p "$(dirname "$real")" 2>/dev/null || true
    (
        have flock && { exec 9>"$lock" && flock 9; }
        local theme alt
        theme=$(gsettings get org.gnome.desktop.interface gtk-theme | tr -d "'")
        if [[ -s "$real" ]]; then theme="$(<"$real")"; fi
        [[ -n "$theme" ]] || exit 0
        printf '%s\n' "$theme" > "$real"
        alt="Adwaita-dark"; [[ "$theme" == "$alt" ]] && alt="Adwaita"
        echo "STEP=gtkreload|run|Refreshing open GTK apps"
        if gsettings set org.gnome.desktop.interface gtk-theme "$alt" >> "$LOG" 2>&1 \
           && sleep 0.25 \
           && gsettings set org.gnome.desktop.interface gtk-theme "$theme" >> "$LOG" 2>&1
        then
            rm -f "$real"
            date +%s%N > "$STAGE/.app-gtk3"
            echo "STEP=gtkreload|ok|Refreshing open GTK apps"
        else
            # Restore no matter what, or a failed toggle leaves the wrong theme set.
            gsettings set org.gnome.desktop.interface gtk-theme "$theme" >> "$LOG" 2>&1 && rm -f "$real"
            echo "STEP=gtkreload|fail|Refreshing open GTK apps"
        fi
    )
}

# ── The one commit ───────────────────────────────────────────────────────────
# $STAGE/out/colors.json becomes the live palette in a single rename, so the shell —
# which watches colors.json — can only ever read the old palette or the new one,
# whole. WAVE=ready comes first: the shell snapshots its look, and this waits
# FREEZE_MS so the palette changes under the snapshots, not in front of them.
#
# Before that, the apps' slow halves start (stage_apps): by the time the shell's
# curtain is up and asks for them, Discord's theme and Spotify's files are ready to
# show. The terminals' theme goes with the commit itself: each kitty window reloads it
# the instant the front reaches that window (services/Contagion.qml signals its
# process), so the file must hold the new colours by `go`. The rest of the rendered
# templates wait in $STAGE/committed for the fan-out (install_templates) — after the
# wave, so nothing that watches one can change ahead of the front.
commit_stage() {
    local out="$STAGE/out"
    [[ -s "$out/colors.json" ]] || { echo "STEP=commit|fail|Applying the new colours"; return 1; }
    stage_apps

    wave ready
    wait_frozen

    echo "STEP=commit|run|Applying the new colours"
    if cp -f "$out/colors.json" "$WAL_CACHE/.colors.json.new" 2>>"$LOG" \
       && mv -f "$WAL_CACHE/.colors.json.new" "$WAL_CACHE/colors.json" 2>>"$LOG"; then
        if [[ -d "$KITTY_DIR" && -s "$out/colors-kitty.conf" ]]; then
            cp -f "$out/colors-kitty.conf" "$KITTY_DIR/.current-theme.conf.new" 2>>"$LOG" \
                && mv -f "$KITTY_DIR/.current-theme.conf.new" "$KITTY_DIR/current-theme.conf" 2>>"$LOG" \
                || rm -f "$KITTY_DIR/.current-theme.conf.new"
        fi
        # GTK's stylesheets go with the commit as well — see write_gtk4_css for why. GTK4 apps
        # with the live module repaint on the write; GTK3 apps on gtk3_refresh, started only when
        # the sheet really changed (the same wallpaper twice has nothing to repaint).
        if [[ -s "$out/colors.sh" ]]; then
            write_gtk4_css "$out/colors.sh" 2>>"$LOG"
            GTK_CSS_CHANGED=0
            write_gtk3_css "$out/colors.sh" 2>>"$LOG"
            (( GTK_CSS_CHANGED )) && have gsettings && gtk3_refresh &
        fi
        # pywal's own note of the current picture, when this run extracted one.
        [[ -f "$out/wal" ]] && cp -f "$out/wal" "$WAL_CACHE/wal" 2>>"$LOG"
        rm -rf -- "${STAGE:?}/committed"
        mv -f "$out" "$STAGE/committed"
        COMMITTED_AT="$(date +%s%N)"
        export COMMITTED_AT
        echo "--- [commit] at $(elapsed_ms) ms" >> "$LOG"
        echo "STEP=commit|ok|Applying the new colours"
        return 0
    fi
    rm -f "$WAL_CACHE/.colors.json.new"
    echo "STEP=commit|fail|Applying the new colours"
    return 1
}

# ── The rest of the templates, after the wave ────────────────────────────────
# What `wal --theme` used to re-render here (126ms, after every change) was already
# rendered from the same document: copy it in, each file by rename. Under the stage
# lock, so a run committing meanwhile can't swap the set mid-copy (the newest
# committed set is the live palette anyway). False when there is no set — the caller
# renders the old way.
install_templates() {
    local src="$STAGE/committed" tmp="$WAL_CACHE/.qs-install" f rel
    stage_lock
    # Only the set that IS the live palette — not one left from an earlier run when
    # this run committed nothing, nor one someone's hand-run `wal` has since replaced.
    if ! cmp -s "$src/colors.json" "$WAL_CACHE/colors.json"; then stage_unlock; return 1; fi
    # Two processes, not two per file (~64 files: 240ms → ~10ms): one copy into a
    # scratch dir beside the targets, then one `mv` that renames each file into place
    # — still atomic per file. A template set with subdirectories (a user template in
    # a folder) can't be renamed over its existing folder, so that falls back to the
    # per-file copy.
    rm -rf -- "$tmp"
    mkdir -p "$tmp"
    cp -a "$src"/. "$tmp"/ 2>>"$LOG"
    rm -rf -- "$tmp/colors.json" "$tmp/wal" "$tmp/schemes"
    if [[ -z "$(find "$tmp" -mindepth 1 -type d -print -quit)" ]]; then
        mv -f -- "$tmp"/* "$WAL_CACHE"/ 2>>"$LOG"
    else
        while IFS= read -r -d '' f; do
            rel="${f#"$tmp"/}"
            mkdir -p "$WAL_CACHE/$(dirname "$rel")"
            mv -f "$f" "$WAL_CACHE/$rel"
        done < <(find "$tmp" -type f -print0)
    fi
    rm -rf -- "$tmp"
    stage_unlock
    return 0
}
