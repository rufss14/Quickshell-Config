#!/usr/bin/env bash
# ── theme-setup.sh ────────────────────────────────────────────────────────────
# Makes other apps follow the shell's palette: the one-time setup behind the
# welcome panel's "Theme your apps" rows and Settings → Setup. The per-change
# recolouring itself is the theming pipeline's (reload-theme.sh / apps-lib.sh);
# this only puts each app in the state that pipeline expects.
#
#   theme-setup.sh status            one line per target:  id|state|sudo|detail
#   theme-setup.sh <target>...       set those up:  gtk qt discord spotify steam  (or all)
#   theme-setup.sh spicetify         just install Spicetify (no root)
#
# state:  ready    nothing to do
#         todo     setup can do it            (sudo=1: it installs a package / fixes
#         blocked  the user has to act first   permissions, and reads a password)
#         absent   the app isn't installed — not a problem, nothing to theme
#
# The password, when a step needs root, arrives as ONE line on stdin (Setup's
# runner writes it, the same shape as every other Setup job) and is read only if
# a step actually needs it.
#
# ── Third-party themes are downloaded, never bundled ─────────────────────────
# Simply Dark (ejalxndr, no licence file) is another person's work, fetched from
# its own repo at a PINNED commit: a later upstream change can't break a setup that
# worked, and nothing of theirs is redistributed with the shell. Bump a pin by
# changing its commit below and re-running setup. Discord's theme (Quicktest) and
# Spotify's (QuickSpice) are ours, so they are copied from the repo instead, and the
# recolour scripts that map the palette onto them are ours too: scripts/themes/.
#
# ── Compatibility ─────────────────────────────────────────────────────────────
# Detect, don't assume: every Vencord-family Discord client (themes/discord/lib.sh),
# Spicetify wherever `spicetify` says Spotify and its own files live, the GTK theme by
# its directory rather than its package, the Qt platform theme from the environment
# Hyprland actually started us with. Steam only natively — Millennium can't patch the
# Flatpak, and the status line says so instead of failing.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SHELL_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}"
WAL_COLORS="${XDG_CACHE_HOME:-$HOME/.cache}/wal/colors.json"
# services/DiscordTheme.qml's own cache of Settings → Type & Shape, resolved — written there so a
# copy here can push the CURRENT values immediately instead of leaving a just-reset theme file
# showing the repo defaults until the shell's own launch/change push catches up.
DISCORD_SHAPE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell-quicktest/discord-shape.json"
[[ -d "$HOME/.spicetify" ]] && PATH="$PATH:$HOME/.spicetify"

# Pinned upstreams. GH_RAW / GH_CODELOAD exist for scripts/test-theme-setup.sh.
GH_RAW="${GH_RAW:-https://raw.githubusercontent.com}"
GH_CODELOAD="${GH_CODELOAD:-https://codeload.github.com}"
SIMPLY_DARK_URL="$GH_CODELOAD/ejalxndr/simply-dark/tar.gz/5163dcbca3cbde75e6aad29af0c6025612ba8607"

# shellcheck source=themes/discord/lib.sh
source "$SHELL_DIR/scripts/themes/discord/lib.sh"

have() { command -v "$1" >/dev/null 2>&1; }
pkg()  { pacman -Qq "$1" >/dev/null 2>&1; }
line() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4"; }
say()  { printf '%s\n' "$*"; }
fetch() { curl -fsSL --max-time 60 -o "$2" "$1"; }   # fetch <url> <out>

# ── Root, read once and only when needed ─────────────────────────────────────
PW="" PW_READ=0
password() {
    if [[ "$PW_READ" = 0 ]]; then IFS= read -r PW || true; PW_READ=1; fi
    [[ -n "$PW" ]] || { say "This step needs your password."; return 1; }
}
# SETUP_ELEVATE=pkexec (set by the setup panel when it uses the system's authentication dialog instead of
# a typed password): root steps run through pkexec and no password is read. Anything else: the password on stdin.
ELEVATE="${SETUP_ELEVATE:-sudo}"
as_root() {
    if [[ "$ELEVATE" = pkexec ]]; then pkexec "$@"; else password && printf '%s\n' "$PW" | sudo -S -p '' "$@"; fi
}
aur_install() {   # aur_install <pkg>: yay/paru as you, only pacman elevated
    local h; if have yay; then h=yay; elif have paru; then h=paru; else
        say "$1 is in the AUR — install yay or paru first."; return 1; fi
    local sudoargs=(--sudoloop)
    if [[ "$ELEVATE" = pkexec ]]; then sudoargs=(--sudo pkexec)
    else password && printf '%s\n' "$PW" | sudo -S -v -p '' || return 1; fi
    if [[ "$h" = yay ]]; then
        yay --answerdiff None --answerclean None --answeredit None "${sudoargs[@]}" -S --needed --noconfirm "$1"
    else
        paru --skipreview "${sudoargs[@]}" -S --needed --noconfirm "$1"
    fi
}

# ══ GTK ══════════════════════════════════════════════════════════════════════
# The pipeline writes ~/.config/gtk-3.0/gtk.css and gtk-4.0/gtk.css on every change, in
# libadwaita's colour names (window_bg_color, accent_color…). GTK4/libadwaita apps read
# those natively; in GTK3 only adw-gtk3 does — under plain Adwaita, GTK3 apps ignored the
# palette entirely. So: adw-gtk3, light or dark to match the colour scheme. Plus the
# optional live module (gtk-live/) so OPEN GTK4 apps repaint too.
adw_present() {
    # The system dirs come from XDG_DATA_DIRS (a distro that installs elsewhere, or a
    # test standing in for a bare machine), not a literal /usr/share.
    local d dirs; IFS=: read -ra dirs <<<"${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    for d in "${dirs[@]/%//themes}" "$DATA/themes" "$HOME/.themes"; do
        [[ -d "$d/adw-gtk3" ]] && return 0; done; return 1
}
gtk_module() { [[ -f "$DATA/quicktest/gio-modules/libgiolivetheme.so" ]]; }
gtk_status() {
    have gsettings || { line gtk blocked 0 "gsettings is missing (glib2)"; return; }
    local t; t="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null | tr -d "'")"
    if [[ "$t" == adw-gtk3* ]] && adw_present; then
        gtk_module && line gtk ready 0 "adw-gtk3, open apps repaint live" \
                   || line gtk ready 0 "adw-gtk3 (GTK4 apps repaint when reopened)"
    elif adw_present; then line gtk todo 0 "Switches GTK apps to adw-gtk3, which reads the palette"
    else line gtk todo 1 "Installs adw-gtk3, which reads the palette"; fi
}
gtk_setup() {
    have gsettings || { say "gsettings is missing (glib2)."; return 1; }
    if ! adw_present; then
        say "Installing adw-gtk-theme…"
        as_root pacman -S --needed --noconfirm adw-gtk-theme || return 1
    fi
    local scheme name=adw-gtk3-dark
    scheme="$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)"
    [[ "$scheme" == *light* ]] && name=adw-gtk3
    [[ "$scheme" == *default* || -z "$scheme" ]] \
        && gsettings set org.gnome.desktop.interface color-scheme prefer-dark
    gsettings set org.gnome.desktop.interface gtk-theme "$name" || return 1
    say "GTK theme: $name"
    # Optional and non-fatal: without it GTK4 apps repaint when reopened, as before.
    if ! gtk_module; then
        bash "$SHELL_DIR/scripts/gtk-live/build.sh" \
            && say "Built the live-repaint module (applies to apps started after your next login)." \
            || say "Skipped the live-repaint module (needs base-devel); GTK4 apps repaint when reopened."
    fi
}

# ══ Qt ═══════════════════════════════════════════════════════════════════════
# generate-qt6ct-colors writes qt6ct's palette on every change — but a Qt app only reads
# qt6ct when QT_QPA_PLATFORMTHEME=qt6ct is in ITS environment, i.e. set where Hyprland
# starts. The bundled config's env.lua sets it; quicktest.lua (the minimal wiring) gets it
# appended here; a config of the user's own gets the exact line to add.
QT_LINE_LUA='hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")'
qt_hypr_sets() { grep -rqs 'QT_QPA_PLATFORMTHEME' "$CFG/hypr" 2>/dev/null; }
qt_status() {
    if ! pkg qt6ct && ! have qt6ct; then line qt todo 1 "Installs qt6ct, which hands Qt apps the palette"; return; fi
    local conf="$CFG/qt6ct/qt6ct.conf" env="${QT_QPA_PLATFORMTHEME:-}"
    if [[ -n "$env" && "$env" != qt6ct ]]; then
        line qt blocked 0 "QT_QPA_PLATFORMTHEME is \"$env\" — the shell themes Qt through qt6ct"; return
    fi
    if ! grep -qs '^custom_palette=true' "$conf"; then line qt todo 0 "Points qt6ct at the shell's palette"; return; fi
    if [[ "$env" = qt6ct ]]; then line qt ready 0 "qt6ct, following the palette"; return; fi
    if qt_hypr_sets; then line qt ready 0 "Set up — log out and back in for Qt apps to pick it up"; return; fi
    if [[ -f "$CFG/hypr/quicktest.lua" ]]; then line qt todo 0 "Adds the Qt theme variable to quicktest.lua"; return; fi
    line qt blocked 0 "Add to your Hyprland config: env = QT_QPA_PLATFORMTHEME,qt6ct"
}
qt_setup() {
    if ! pkg qt6ct && ! have qt6ct; then
        say "Installing qt6ct…"; as_root pacman -S --needed --noconfirm qt6ct || return 1
    fi
    python3 "$SHELL_DIR/scripts/generate-qt6ct-colors" || return 1
    if [[ "${QT_QPA_PLATFORMTHEME:-}" != qt6ct ]] && ! qt_hypr_sets; then
        if [[ -f "$CFG/hypr/quicktest.lua" ]]; then
            printf '\n-- Qt apps read the shell palette through qt6ct (Settings → Setup).\n%s\n' \
                "$QT_LINE_LUA" >> "$CFG/hypr/quicktest.lua"
            say "Added the Qt theme variable to quicktest.lua — log out and back in for Qt apps."
        else
            say "Add this to your Hyprland config, then log out and back in:"
            say "  env = QT_QPA_PLATFORMTHEME,qt6ct        (hyprland.conf)"
            say "  $QT_LINE_LUA   (hyprland.lua)"
        fi
    fi
}

# ══ Discord — Quicktest, recoloured by scripts/themes/discord/quicktest-theme.py ══
# Quicktest is ours (vencord/quicktest.theme.css, drawn from the shell's own tokens), so it is
# copied from the repo rather than fetched. Two blocks inside it are rewritten while the shell runs (the palette,
# on every colour change; Type & Shape, by services/DiscordTheme.qml), so "current" means identical OUTSIDE them.
# A re-copy resets Type & Shape to the defaults until the shell next starts or the settings change (it pushes at launch). Enabling it un-enables Midnight
# (what earlier versions installed): the two would fight over the same tokens. The old file is
# left on disk, and a client that still has only Midnight keeps being recoloured (apps-lib.sh).
discord_installed() {
    have discord || have discord-canary || have discord-ptb || have vesktop || have equibop \
        || flatpak info com.discordapp.Discord >/dev/null 2>&1 \
        || flatpak info dev.vencord.Vesktop >/dev/null 2>&1
}
quicktest_body() { sed '/qs-palette:begin/,/qs-palette:end/d;/qs-shape:begin/,/qs-shape:end/d' "$1"; }   # the theme without its generated blocks
discord_themed() {   # discord_themed <config dir>: Quicktest is there, current, and enabled
    [[ -f "$1/themes/quicktest.theme.css" ]] \
        && [[ "$(quicktest_body "$1/themes/quicktest.theme.css")" == "$(quicktest_body "$QUICKTEST_CSS")" ]] \
        && python3 -c 'import json, sys
try: d = json.load(open(sys.argv[1]))
except Exception: sys.exit(1)
t = d.get("enabledThemes") or []
sys.exit(0 if "quicktest.theme.css" in t and "midnight.theme.css" not in t else 1)' "$1/settings/settings.json"
}
discord_status() {
    local clients; clients="$(discord_clients)"
    if [[ -z "$clients" ]]; then
        discord_installed \
            && line discord blocked 0 "Patch Discord with Vencord first (update panel → Update Discord), or use Vesktop" \
            || line discord absent 0 "Discord isn't installed"
        return
    fi
    local entry names="" todo=0
    while IFS= read -r entry; do
        names+="${names:+, }${entry%%:*}"
        discord_themed "${entry#*:}" || todo=1
    done <<< "$clients"
    [[ "$todo" = 0 ]] && line discord ready 0 "Quicktest, following the palette ($names)" \
                      || line discord todo 0 "Installs the Quicktest theme ($names)"
}
discord_setup() {
    local clients entry label dir
    clients="$(discord_clients)"
    [[ -n "$clients" ]] || { say "No Vencord or Vesktop found — patch Discord with Vencord first."; return 1; }
    while IFS= read -r entry; do
        label="${entry%%:*}" dir="${entry#*:}"
        mkdir -p "$dir/themes" "$dir/settings"
        # Beside the target, then renamed in: Vencord watches the directory and must never read half a theme.
        cp -f "$QUICKTEST_CSS" "$dir/themes/quicktest.theme.css.qs-new" \
            && mv -f "$dir/themes/quicktest.theme.css.qs-new" "$dir/themes/quicktest.theme.css" \
            || { say "Couldn't copy the theme into $dir/themes."; return 1; }
        # Enable it, keeping every other setting and theme the user has.
        python3 -c 'import json, os, sys
p = sys.argv[1]
try: d = json.load(open(p))
except Exception: d = {}
t = [x for x in (d.get("enabledThemes") or []) if x != "midnight.theme.css"]
if "quicktest.theme.css" not in t: t.append("quicktest.theme.css")
d["enabledThemes"] = t
tmp = p + ".qs-new"
json.dump(d, open(tmp, "w"), indent=4); os.replace(tmp, p)' "$dir/settings/settings.json" || return 1
        [[ -s "$WAL_COLORS" ]] \
            && python3 "$QUICKTEST_PY" --css "$dir/themes/quicktest.theme.css" --colors "$WAL_COLORS" >/dev/null
        [[ -s "$DISCORD_SHAPE" ]] \
            && python3 "$QUICKTEST_PY" --css "$dir/themes/quicktest.theme.css" --shape "$(<"$DISCORD_SHAPE")" >/dev/null
        say "$label: Quicktest enabled."
    done <<< "$clients"
    say "Restart Discord to load the theme; after that it follows every colour change live."
}

# ══ Spotify — Spicetify + QuickSpice, recoloured by scripts/themes/spotify/pwspice.py ══
# QuickSpice is ours (spicetify/Themes/QuickSpice, drawn from the shell's own tokens), so it
# is copied from the repo rather than fetched. user.css and theme.js are the theme and are
# refreshed whenever they differ; color.ini holds the palette pwspice.py writes, so an
# existing one is kept.
spotify_installed() {
    have spotify || have spotify-launcher || flatpak info com.spotify.Client >/dev/null 2>&1
}
spicetify_cfg() { spicetify config "$1" 2>/dev/null | head -1 | tr -d '[:space:]'; }
spotify_writable() {
    local p; p="$(spicetify config spotify_path 2>/dev/null | head -1)"
    [[ -n "$p" && -w "$p" && -w "$p/Apps" ]]
}
spotify_prefs() {
    local p; p="$(spicetify config prefs_path 2>/dev/null | head -1)"
    [[ -n "$p" && -f "$p" ]]
}
spotify_status() {
    spotify_installed || { line spotify absent 0 "Spotify isn't installed"; return; }
    have spicetify || { line spotify todo 0 "Installs Spicetify and the QuickSpice theme"; return; }
    spotify_prefs || { line spotify blocked 0 "Open Spotify once and sign in, then set this up"; return; }
    local w=0; spotify_writable || w=1
    local td; td="$(spicetify path userdata 2>/dev/null)/Themes/QuickSpice"
    if [[ "$(spicetify_cfg current_theme)" = QuickSpice && "$(spicetify_cfg color_scheme)" = Pywal ]] \
       && [[ -d "$td" ]] && spotify_theme_current "$td" \
       && spicetify config extensions 2>/dev/null | grep -q 'quickshell-bridge.js'; then
        line spotify ready 0 "QuickSpice, following the palette"
    else
        line spotify todo "$w" "Applies the QuickSpice theme and the shell's bridge extension"
    fi
}
# The installed copy still matches the repo's. Bash comparison, not cmp: setup runs on a
# PATH of what it needs, and a stale theme should read as "to do", not "ready".
spotify_theme_current() {
    local f
    for f in user.css theme.js; do
        [[ -f "$1/$f" && "$(<"$1/$f")" == "$(<"$SHELL_DIR/spicetify/Themes/QuickSpice/$f")" ]] || return 1
    done
}
spicetify_install() {
    have spicetify && return 0
    say "Installing Spicetify (into ~/.spicetify, no root)…"
    local arch tag tmp
    case "$(uname -m)" in x86_64) arch=amd64 ;; aarch64|arm64) arch=arm64 ;; *)
        say "No Spicetify build for $(uname -m)."; return 1 ;; esac
    tag="$(curl -fsSL --max-time 20 https://api.github.com/repos/spicetify/cli/releases/latest \
           | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')" || { say "Couldn't reach GitHub."; return 1; }
    tmp="$(mktemp -d)"
    fetch "https://github.com/spicetify/cli/releases/download/$tag/spicetify-${tag#v}-linux-$arch.tar.gz" "$tmp/s.tgz" \
        && mkdir -p "$HOME/.spicetify" && tar -xzf "$tmp/s.tgz" -C "$HOME/.spicetify" \
        && chmod +x "$HOME/.spicetify/spicetify"
    local rc=$?; rm -rf "$tmp"
    [[ "$rc" = 0 ]] || { say "Spicetify download failed."; return 1; }
    PATH="$PATH:$HOME/.spicetify"
    say "Spicetify $tag installed. The shell finds it in ~/.spicetify; for a terminal, add it to your PATH."
}
spotify_setup() {
    spotify_installed || { say "Spotify isn't installed."; return 1; }
    spicetify_install || return 1
    spotify_prefs || { say "Open Spotify once and sign in, then run this again."; return 1; }
    if ! spotify_writable; then
        local p; p="$(spicetify config spotify_path 2>/dev/null | head -1)"
        say "Letting Spicetify write to $p (Spicetify's documented step)…"
        as_root chmod a+wr "$p" && as_root chmod -R a+wr "$p/Apps" || return 1
    fi
    local ud; ud="$(spicetify path userdata 2>/dev/null)"
    [[ -n "$ud" ]] || { say "spicetify path userdata returned nothing."; return 1; }
    local src="$SHELL_DIR/spicetify/Themes/QuickSpice"
    mkdir -p "$ud/Themes/QuickSpice" "$ud/Extensions"
    cp -f "$src/user.css" "$src/theme.js" "$ud/Themes/QuickSpice/" || return 1
    [[ -f "$ud/Themes/QuickSpice/color.ini" ]] || cp "$src/color.ini" "$ud/Themes/QuickSpice/" || return 1
    cp -f "$SHELL_DIR/spicetify/Extensions/quickshell-bridge.js" "$ud/Extensions/" || return 1
    spicetify config current_theme QuickSpice color_scheme Pywal inject_css 1 inject_theme_js 1 replace_colors 1 >/dev/null || return 1
    spicetify config extensions 2>/dev/null | grep -q 'quickshell-bridge.js' \
        || spicetify config extensions quickshell-bridge.js >/dev/null || return 1
    [[ -s "$WAL_COLORS" ]] && python3 "$SHELL_DIR/scripts/themes/spotify/pwspice.py" \
        -w "$WAL_COLORS" -o "$ud/Themes/QuickSpice/color.ini" --wait-for-wal 0 >/dev/null
    # First apply needs a backup of the stock client; later ones don't.
    if grep -A2 '^\[Backup\]' "$ud/config-xpui.ini" 2>/dev/null | grep -qE '^version *= *[^ ]'; then
        spicetify apply || return 1
    else
        spicetify backup apply || return 1
    fi
    say "Spotify now wears QuickSpice in the shell's colours."
}

# ══ Steam — Millennium + Simply Dark, recoloured by scripts/steam-colors.py ═════
steam_root() {
    local d; for d in "$DATA/Steam" "$HOME/.steam/steam"; do
        [[ -d "$d" ]] && { readlink -f "$d"; return 0; }; done; return 1
}
# The directory too: Millennium's own installer script puts it there without a package.
MILLENNIUM_LIB="${MILLENNIUM_LIB:-/usr/lib/millennium}"
millennium_present() { pkg millennium-bin || pkg millennium || [[ -d "$MILLENNIUM_LIB" ]]; }
MILLENNIUM_CFG="$CFG/millennium/config.json"
steam_active_theme() {
    python3 -c 'import json, sys
try: print(json.load(open(sys.argv[1])).get("themes", {}).get("activeTheme", ""))
except Exception: pass' "$MILLENNIUM_CFG" 2>/dev/null
}
steam_status() {
    if ! have steam || ! steam_root >/dev/null; then
        flatpak info com.valvesoftware.Steam >/dev/null 2>&1 \
            && line steam blocked 0 "Flatpak Steam can't be themed — Millennium needs the native package" \
            || line steam absent 0 "Steam isn't installed"
        return
    fi
    if ! millennium_present; then
        { have yay || have paru; } && line steam todo 1 "Installs Millennium (AUR) and the Simply Dark theme" \
                                    || line steam blocked 0 "Millennium is in the AUR — install yay or paru first"
        return
    fi
    [[ -f "$MILLENNIUM_CFG" ]] || { line steam blocked 0 "Start Steam once so Millennium finishes installing"; return; }
    local root; root="$(steam_root)"
    if [[ -d "$root/millennium/themes/simply-dark" && "$(steam_active_theme)" = simply-dark ]]; then
        line steam ready 0 "Simply Dark, following the palette"
    else
        line steam todo 0 "Installs the Simply Dark theme"
    fi
}
steam_setup() {
    have steam && steam_root >/dev/null || { say "Native Steam isn't installed."; return 1; }
    if ! millennium_present; then
        say "Installing Millennium…"; aur_install millennium-bin || return 1
    fi
    local root dir tmp; root="$(steam_root)"; dir="$root/millennium/themes/simply-dark"
    if [[ ! -d "$dir" ]]; then
        say "Downloading Simply Dark…"
        tmp="$(mktemp -d)"
        if fetch "$SIMPLY_DARK_URL" "$tmp/t.tgz" && mkdir -p "$dir" \
           && tar -xzf "$tmp/t.tgz" -C "$dir" --strip-components=1; then rm -rf "$tmp"
        else rm -rf "$tmp" "$dir"; say "Download failed."; return 1; fi
    fi
    [[ -f "$MILLENNIUM_CFG" ]] || { say "Start Steam once so Millennium finishes installing, then run this again."; return 1; }
    # Millennium keeps its config in memory and writes it back, so an edit made while
    # Steam runs is lost on exit.
    if pgrep -x steam >/dev/null 2>&1; then
        say "Close Steam, then run this again — Millennium would undo the theme switch on exit."; return 1
    fi
    python3 -c 'import json, os, sys
p = sys.argv[1]; d = json.load(open(p))
d.setdefault("themes", {})["activeTheme"] = "simply-dark"
tmp = p + ".qs-new"; json.dump(d, open(tmp, "w"), indent=4); os.replace(tmp, p)' "$MILLENNIUM_CFG" || return 1
    [[ -s "$WAL_COLORS" ]] && python3 "$SHELL_DIR/scripts/steam-colors.py" "$MILLENNIUM_CFG" "$WAL_COLORS" >/dev/null
    say "Steam will open in Simply Dark, in the shell's colours."
}

# ══ Dispatch ═════════════════════════════════════════════════════════════════
TARGETS=(gtk qt discord spotify steam)
cmd="${1:-status}"
case "$cmd" in
    status)
        for t in "${TARGETS[@]}"; do "${t}_status"; done ;;
    spicetify)
        spicetify_install ;;
    all)
        rc=0
        for t in "${TARGETS[@]}"; do
            st="$("${t}_status")"; IFS='|' read -r _ state _ _ <<< "$st"
            [[ "$state" = todo ]] || continue
            say "== ${t} =="
            "${t}_setup" || rc=1
        done
        exit "$rc" ;;
    gtk|qt|discord|spotify|steam)
        rc=0
        for t in "$@"; do
            case "$t" in gtk|qt|discord|spotify|steam) "${t}_setup" || rc=1 ;;
                *) say "unknown target: $t"; rc=64 ;; esac
        done
        exit "$rc" ;;
    *)
        sed -n '2,24p' "$(readlink -f "$0")"; exit 64 ;;
esac
