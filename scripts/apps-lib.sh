# ── apps-lib.sh ───────────────────────────────────────────────────────────────
# Sourced, never run (by wave-lib.sh, so by both theming scripts): how each app the
# wave reaches one by one is recoloured — Discord, Firefox-family browsers, Spotify.
# One copy, used by reload-theme.sh's fan-out, its `--app`, and the staging below.
#
# The caller defines step/skip/have and sets CACHE, LOG, STAGE.
#
# ── Staged, so the frozen moment is short ────────────────────────────────────
# The wave holds its front frozen while these apps repaint under its curtain, and
# their scripts used to run IN that moment: Discord's ~0.3–1.4s, Spotify's ~0.4–0.7s
# (`spicetify refresh`), on top of what the app itself then takes. Measured: the
# screen sat still for 1–2s before the front moved.
#
# Now the slow part runs BEFORE the freeze (commit_stage → stage_apps), from the
# palette about to be committed, into private files nothing watches; under the curtain
# only the cheap, instant last step happens (publish_*): one rename for Discord, one
# POST for Spotify. The app's own work (Vencord's 300ms debounce, Spotify's sheet
# fetch) then starts the moment the curtain is up, not seconds later.
#
#   stage_apps            starts every app's prep in the background (markers below)
#   publish_<app>         `--app <app>` and the fan-out: show the staged result
#   recolor_<app>         the fan-out's whole step: publish if staged, else the old way
#
# $STAGE/apps/<app>.pending exists while a prep runs, <app>.ready once it's done.
# Everything in $STAGE/apps belongs to the newest commit: stage_apps clears it first,
# under the stage lock, before the shell is told anything.

APPS_DIR="$STAGE/apps"
# Not every caller sets it (workspace-apps.sh doesn't); the shipped theme scripts need it.
SHELL_DIR="${SHELL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── The palette the preps read: their own copy ───────────────────────────────
# stage_apps starts the preps in the BACKGROUND and commit_stage carries straight on —
# and the commit ends by moving $STAGE/out to $STAGE/committed. With a wave, the freeze
# in between gave the preps time to read $STAGE/out/colors.json first, by luck. Without
# one (the album scheme's system-wide run: reload-theme.sh with no shell watching) the
# commit landed within milliseconds, every prep found no file, and Vencord's script —
# which treats a missing palette as "use my defaults" — staged its built-in theme. The
# fan-out then published it faithfully: Discord reloaded on every track, into the same
# default colours every time. Spotify's prep waited 10s for the same file and gave up.
#
# So stage_apps snapshots the palette into $APPS_DIR first and the preps read that; the
# commit can't take it away. workspace-apps.sh calls the preps without stage_apps, from a
# private stage whose out/ nothing moves — the fallback covers it.
apps_palette() {
    if [[ -s "$APPS_DIR/colors.json" ]]; then printf '%s\n' "$APPS_DIR/colors.json"
    else printf '%s\n' "$STAGE/out/colors.json"; fi
}

# ── Discord: Quicktest (or Midnight), recoloured by the script that fits the file ────
# Which clients exist, which script writes a theme's palette, and the palette reshaped
# for the older one, are themes/discord/lib.sh — shared with theme-setup.sh, which
# installs the theme. A client takes part once its themes/quicktest.theme.css exists
# (setup put it there); one that still has only Midnight keeps being recoloured.
# shellcheck source=themes/discord/lib.sh
source "$SHELL_DIR/scripts/themes/discord/lib.sh"

# discord_themes: "<label>:<theme.css>" per client, Quicktest in preference to Midnight.
discord_themes() {
    local entry dir
    while IFS= read -r entry; do
        [[ -n "$entry" ]] || continue
        dir="${entry#*:}/themes"
        if [[ -f "$dir/quicktest.theme.css" ]]; then printf '%s:%s\n' "${entry%%:*}" "$dir/quicktest.theme.css"
        elif [[ -f "$dir/midnight.theme.css" ]]; then printf '%s:%s\n' "${entry%%:*}" "$dir/midnight.theme.css"
        fi
    done < <(discord_clients)
}

# The script appends `/* pywal */` three times per variable on EVERY run and never
# removes the old ones: after ~2,700 changes the theme was 6 MB of comments (22 KB of
# CSS), which Discord re-parsed on every change and the script rewrote with ~100
# regex passes (280ms vs 49ms clean). Collapsed here, on the staged copy. Lossless:
# the marker stays, once.
collapse_pywal_comments() {
    sed -E -i 's#( /\* pywal \*/)+# /* pywal */#g' "$1"
}

prep_discord() {
    local entry label css staged pal="$APPS_DIR/discord-palette.json"
    mkdir -p "$APPS_DIR"
    discord_palette "$(apps_palette)" "$pal" || return 1
    while IFS= read -r entry; do
        label="${entry%%:*}" css="${entry#*:}"
        staged="$APPS_DIR/discord-${label// /_}.css"
        if cp -f "$css" "$staged" \
           && python3 "$(discord_script "$css")" --css "$staged" --colors "$pal" \
           && collapse_pywal_comments "$staged"; then
            printf '%s\n' "$css" > "$staged.dest"
        else
            rm -f "$staged" "$staged.dest"
        fi
    done < <(discord_themes)
}

# Into place by rename, beside the target (same filesystem, so atomic): Vencord
# watches the themes DIRECTORY (fs.watch on it, 300ms debounce — patcher.js), so it
# sees a rename, and never reads a half-written theme.
publish_discord() {
    local staged dest label n=0
    for staged in "$APPS_DIR"/discord-*.css; do
        [[ -f "$staged" && -f "$staged.dest" ]] || continue
        dest="$(cat "$staged.dest")"
        label="${staged##*/discord-}"; label="${label%.css}"; label="${label//_/ }"
        echo "STEP=discord-${label// /_}|run|Recolouring Discord ($label)"
        if cp -f "$staged" "$dest.qs-new" 2>>"$LOG" && mv -f "$dest.qs-new" "$dest" 2>>"$LOG"; then
            echo "STEP=discord-${label// /_}|ok|Recolouring Discord ($label)"
        else
            rm -f "$dest.qs-new"
            echo "STEP=discord-${label// /_}|fail|Recolouring Discord ($label)"
        fi
        rm -f "$staged" "$staged.dest"
        n=$((n + 1))
    done
    (( n > 0 ))
}

recolor_discord_now() {
    local entry label css pal="$STAGE/discord-palette.json"
    mkdir -p "$STAGE"
    # Same reshaped copy as prep_discord; if it can't be made, the script's own default.
    local colors=()
    discord_palette "$WAL_CACHE/colors.json" "$pal" 2>>"$LOG" && colors=(--colors "$pal")
    while IFS= read -r entry; do
        label="${entry%%:*}" css="${entry#*:}"
        step "discord-${label// /_}" "Recolouring Discord ($label)" -- python3 "$(discord_script "$css")" --css "$css" "${colors[@]}"
    done < <(discord_themes)
}

# ── Firefox-family browsers (Zen, Firefox, LibreWolf): Pywalfox, live ─────────
recolor_browser() {
    if have pywalfox; then
        step firefox "Recolouring Firefox pages" -- pywalfox update
    else
        skip firefox "pywalfox not installed"
    fi
    recolor_darkreader
}

# Dark Reader has no external API, so its page colours go through a patched copy that asks a
# native-messaging host for the palette (scripts/darkreader-live.py, docs/darkreader.md).
# The host only exists while Zen runs with that copy installed: otherwise there is nothing
# to push to, and the step says why instead of failing.
DR_LIVE="$SHELL_DIR/scripts/darkreader-live.py"
recolor_darkreader() {
    if python3 "$DR_LIVE" probe >/dev/null 2>&1; then
        step darkreader "Recolouring Dark Reader" -- python3 "$DR_LIVE" push
    else
        skip darkreader "patched Dark Reader isn't running (python3 scripts/darkreader-live.py install)"
    fi
}

# ── Spotify, through Spicetify ───────────────────────────────────────────────
# The shipped pwspice.py writes QuickZiro's color.ini (theme-setup.sh installs QuickZiro and
# the bridge), `spicetify refresh -s -n` bakes it into the app's files, and the running app
# is told through the shell's Spicetify extension (spicetify/Extensions/quickshell-bridge.js):
# a POST to the bridge's /restyle; it swaps the sheets and reports `restyled`, which is
# what the wave waits for. The staged path runs the first two steps from the STAGED
# palette before the freeze; only the POST is left for under the curtain.
#
# It used to call the maintainer's own ~/.config/spicetify/recolor.sh and pwspice.py, so
# on any other machine Spotify was silently skipped. Spicetify's own installer puts it in
# ~/.spicetify, which isn't on every login shell's PATH — added here so it's found.
[[ -d "$HOME/.spicetify" && ":$PATH:" != *":$HOME/.spicetify:"* ]] && PATH="$PATH:$HOME/.spicetify"
SPOTIFY_PWSPICE="$SHELL_DIR/scripts/themes/spotify/pwspice.py"
SPOTIFY_THEME_ROOT="${XDG_CONFIG_HOME:-$HOME/.config}/spicetify/Themes"
SPOTIFY_THEME="$SPOTIFY_THEME_ROOT/QuickZiro"; SPOTIFY_STYLE=ziro
SPOTIFY_BRIDGE="http://127.0.0.1:${QS_SPOTIFY_BRIDGE_PORT:-47821}"
[[ "${QS_SPOTIFY_BRIDGE_PORT:-47821}" =~ ^[0-9]{1,5}$ ]] || SPOTIFY_BRIDGE="http://127.0.0.1:47821"
spotify_listening() {
    curl -s -m 1 "$SPOTIFY_BRIDGE/" 2>/dev/null | grep -q '"listening":true'
}
# Follows whichever theme Spicetify has active (QuickZiro, or QuickSpice on a machine set up
# before it was dropped), so switching the theme needs no change here; anything else, or
# nothing, is QuickZiro. pwspice.py knows two slot layouts: Ziro's user.css wants finished
# colours, QuickSpice's derived them.
spotify_themed() {
    have spicetify || return 1
    local t; t="$(spicetify config current_theme 2>/dev/null | head -1 | tr -d '[:space:]')"
    case "$t" in QuickZiro|QuickSpice) ;; *) t=QuickZiro ;; esac
    SPOTIFY_THEME="$SPOTIFY_THEME_ROOT/$t"
    [[ "$t" = QuickZiro ]] && SPOTIFY_STYLE=ziro || SPOTIFY_STYLE=spice
    [[ -d "$SPOTIFY_THEME" ]]
}
# spotify_bake <palette>: color.ini from the palette, then into Spotify's files.
spotify_bake() {
    python3 "$SPOTIFY_PWSPICE" -w "$1" -o "$SPOTIFY_THEME/color.ini" --style "$SPOTIFY_STYLE" --wait-for-wal 0 \
        && spicetify refresh -s -n
}
prep_spotify() {
    spotify_themed && spotify_listening || return 1
    spotify_bake "$(apps_palette)"
}
publish_spotify() {
    step spotify-live "Repainting Spotify" -- curl -sS -m 2 -X POST "$SPOTIFY_BRIDGE/restyle"
}
recolor_spotify_now() {
    if spotify_themed; then
        step spotify "Recolouring Spotify" -- spotify_bake "$WAL_CACHE/colors.json" \
            && { spotify_listening && publish_spotify || true; }
    else
        skip spotify "Spotify isn't themed (Settings → Setup → Theme your apps)"
    fi
}

# ── Staging and waiting for it ────────────────────────────────────────────────
# Each prep runs in the background with the stage lock's fd closed (a copy held open
# would keep the lock after stage_unlock) and its output in the log, never on stdout
# (the runner's pipe would stay open until it finished).
stage_apps() {
    rm -rf -- "$APPS_DIR"
    mkdir -p "$APPS_DIR"
    # Before any prep starts — see apps_palette. commit_stage has already checked it's there.
    cp -f -- "$STAGE/out/colors.json" "$APPS_DIR/colors.json" 2>>"$LOG"
    PREPARED_AT="$(date +%s%N)"
    export PREPARED_AT
    local app
    for app in discord spotify; do
        : > "$APPS_DIR/$app.pending"
        ( if "prep_$app"; then mv -f "$APPS_DIR/$app.pending" "$APPS_DIR/$app.ready"
          else rm -f "$APPS_DIR/$app.pending"; fi ) >>"$LOG" 2>&1 8>&- &
    done
}

# staged <app>: true once the app's staged result is ready (waiting out a prep still
# running, 3s at most); false when there is none.
staged() {
    local waited=0
    while [[ -e "$APPS_DIR/$1.pending" && "$waited" -lt 3000 ]]; do
        sleep 0.02
        waited=$(( waited + 20 ))
    done
    [[ -e "$APPS_DIR/$1.ready" ]]
}
consume() { rm -f "$APPS_DIR/$1.ready"; }

# The fan-out's step for each: the staged result if there is one, else the old way.
recolor_discord() {
    staged discord && publish_discord || recolor_discord_now
    consume discord
}
recolor_spotify() {
    if staged spotify; then consume spotify; publish_spotify; else recolor_spotify_now; fi
}

can_recolor() {
    case "$1" in
        discord) [[ -n "$(discord_themes)" ]] ;;
        browser) have pywalfox ;;
        # Live only through the extension: without it the wave would wait on a
        # Spotify that can't answer (it still gets the theme on disk, for next launch).
        spotify) spotify_themed && spotify_listening ;;
        *) return 1 ;;
    esac
}
