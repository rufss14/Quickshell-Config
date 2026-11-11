#!/usr/bin/env bash
# ── test-theme-setup.sh ───────────────────────────────────────────────────────
# Runs the REAL scripts/theme-setup.sh against fake machines: a throwaway HOME, a
# PATH of stand-ins (pacman, sudo, gsettings, spicetify, steam, flatpak, pgrep…) and
# a file:// mirror for the pinned downloads. Checks what each status line says on
# each kind of machine, and that setup does what it claims without losing anything
# the user already had (other Discord themes, Millennium settings).
#
#     bash scripts/test-theme-setup.sh
#
# Safe to run: everything lives in a mktemp dir; no network, no root, nothing of
# yours is read or written.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
# No stdin, as in Setup's runner (it writes the password, if any, then closes it): a
# step that wants a password then fails instead of waiting on a terminal forever.
exec </dev/null
HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
check() { if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else fail=$((fail+1)); printf '  FAIL  %s\n          got  %s\n          want %s\n' "$1" "$2" "$3"; fi; }

# ── A PATH with only what the script may use, so this machine's real apps can't leak in
SYS="$T/sys"; mkdir -p "$SYS"
for t in bash sh python3 curl tar gzip sed grep awk mktemp mv cp mkdir rm rmdir readlink dirname \
         head tail tr cat chmod uname printf env ls touch basename sort cut wc gcc pkg-config; do
    p="$(command -v "$t" 2>/dev/null)" && ln -s "$p" "$SYS/$t"
done

# ── The mirror the pinned URLs resolve into
M="$T/mirror"
mkdir -p "$M/kuska1/Material-Theme/tar.gz" "$T/mat/Material-Theme-x"
printf '{"name":"Material"}\n' > "$T/mat/Material-Theme-x/skin.json"
tar -czf "$M/kuska1/Material-Theme/tar.gz/f91b4e9cbc5436f149e6b293391a9a96ab47fbe9" -C "$T/mat" Material-Theme-x

# fresh <name>: a new empty machine; sets H (home) and B (its stand-in bin dir)
fresh() {
    H="$T/$1"; B="$H/.fakebin"; rm -rf "$H"; mkdir -p "$H/.cache/wal" "$H/.cache/quickshell-quicktest" "$B"
    # DiscordTheme.qml's own cache of the resolved Settings → Type & Shape — a distinctive font
    # here proves discord_setup() pushed it, the same way the palette check below proves colours.
    cat > "$H/.cache/quickshell-quicktest/discord-shape.json" <<'JSON'
{"spacing":{"xs":2,"sm":4,"md":8,"lg":12,"xl":16,"xxl":24},
 "radius":{"xs":4,"sm":8,"pill":12,"card":16,"xl":24},
 "font":"Test Pushed Font","mono":"Test Pushed Font Mono",
 "motion":{"respond":100,"fast":120,"standard":150,"emphasized":340,"exit":200,"slow":400,"ripple":500,"spring-fast":322,"spring":371},
 "shadow":{"card":{"y":3,"blur":10.8,"spread":-1.4},"popup":{"y":6,"blur":17.6,"spread":-2.2}},
 "icon":"default"}
JSON
    cat > "$H/.cache/wal/colors.json" <<'JSON'
{"special":{"background":"#101018","foreground":"#e0e0f0","cursor":"#e0e0f0"},
 "colors":{"color0":"#101018","color1":"#7a5af8","color2":"#5af87a","color3":"#f85a7a","color4":"#5a7af8",
 "color5":"#c05af8","color6":"#5af8e0","color7":"#e0e0f0","color8":"#404050","color9":"#7a5af8",
 "color10":"#5af87a","color11":"#f85a7a","color12":"#5a7af8","color13":"#c05af8","color14":"#5af8e0","color15":"#ffffff"}}
JSON
    : > "$H/.pkgs"
    # Stand-ins. pacman knows the packages listed in ~/.pkgs; -S adds to it.
    cat > "$B/pacman" <<EOF
#!/bin/sh
case "\$1" in
  -Qq) grep -qx "\$2" "$H/.pkgs" ;;
  -S)  shift; for a; do case "\$a" in -*) ;; *) echo "\$a" >> "$H/.pkgs" ;; esac; done ;;
  *) exit 1 ;;
esac
EOF
    # sudo: the password must be "secret"; -v just validates.
    cat > "$B/sudo" <<'EOF'
#!/bin/sh
IFS= read -r pw; [ "$pw" = secret ] || { echo "Sorry, try again." >&2; exit 1; }
while [ $# -gt 0 ]; do case "$1" in -S) shift ;; -p) shift 2 ;; -v) exit 0 ;; *) break ;; esac; done
exec "$@"
EOF
    cat > "$B/gsettings" <<EOF
#!/bin/sh
f="$H/.gsettings-\$3"
d=Adwaita; [ "\$3" = color-scheme ] && d=default
case "\$1" in get) [ -f "\$f" ] && echo "'\$(cat "\$f")'" || echo "'\$d'" ;; set) echo "\$4" > "\$f" ;; esac
EOF
    printf '#!/bin/sh\nexit 1\n' > "$B/flatpak"
    printf '#!/bin/sh\n[ -f "%s/.steam-running" ]\n' "$H" > "$B/pgrep"
    chmod +x "$B"/*
}
# XDG_DATA_DIRS at a dir that doesn't exist: this machine's own /usr/share/themes (adw-gtk3
# is often installed there) must not make a bare machine look themed.
run() { env -i HOME="$H" PATH="$B:$SYS" XDG_DATA_DIRS="$H/no-system-data" GH_RAW="file://$M" GH_CODELOAD="file://$M" MILLENNIUM_LIB="$H/no-millennium" \
        ${QTENV:+QT_QPA_PLATFORMTHEME=$QTENV} bash "$HERE/theme-setup.sh" "$@"; }
st() { run status | grep "^$1|" | cut -d'|' -f2-3; }   # state|sudo
app() { printf '#!/bin/sh\nexit 0\n' > "$B/$1"; chmod +x "$B/$1"; }

# ══ A bare machine ══
fresh bare
check "bare: gtk"     "$(st gtk)"     "todo|1"
check "bare: qt"      "$(st qt)"      "todo|1"
check "bare: discord" "$(st discord)" "absent|0"
check "bare: spotify" "$(st spotify)" "absent|0"
check "bare: steam"   "$(st steam)"   "absent|0"

# ══ GTK ══
fresh gtk; mkdir -p "$H/.local/share/themes/adw-gtk3"
check "gtk: theme present, not selected" "$(st gtk)" "todo|0"
run gtk >/dev/null 2>&1
check "gtk: switched to the dark variant"  "$(cat "$H/.gsettings-gtk-theme")" "adw-gtk3-dark"
check "gtk: default scheme becomes dark"   "$(cat "$H/.gsettings-color-scheme")" "prefer-dark"
check "gtk: ready"                         "$(st gtk)" "ready|0"
fresh gtk2
echo "Sorry" | run gtk >/dev/null 2>&1; check "gtk: wrong password fails" "$?" "1"
check "gtk: wrong password installs nothing" "$(grep -c adw-gtk-theme "$H/.pkgs")" "0"

# ══ Qt ══
fresh qt; echo qt6ct >> "$H/.pkgs"
check "qt: palette not pointed yet" "$(st qt)" "todo|0"
QTENV=kde; check "qt: someone else's platform theme" "$(st qt)" "blocked|0"; QTENV=
mkdir -p "$H/.config/hypr"; echo '-- mine' > "$H/.config/hypr/quicktest.lua"
run qt >/dev/null 2>&1
check "qt: palette written"       "$(grep -c '^custom_palette=true' "$H/.config/qt6ct/qt6ct.conf")" "1"
check "qt: env added to quicktest.lua" "$(grep -c 'QT_QPA_PLATFORMTHEME' "$H/.config/hypr/quicktest.lua")" "1"
check "qt: ready (after re-login)" "$(st qt)" "ready|0"
run qt >/dev/null 2>&1
check "qt: second run doesn't duplicate" "$(grep -c 'QT_QPA_PLATFORMTHEME' "$H/.config/hypr/quicktest.lua")" "1"
QTENV=qt6ct; check "qt: live env" "$(st qt)" "ready|0"; QTENV=

# ══ Discord ══ (Quicktest is copied from the repo, not fetched; Midnight is migrated away from)
fresh dc; app discord
check "discord: no Vencord" "$(st discord)" "blocked|0"
mkdir -p "$H/.config/Vencord/settings" "$H/.config/Vencord/themes" "$H/.config/vesktop"
echo '{"enabledThemes":["midnight.theme.css","Other.theme.css"],"useQuickCss":true}' > "$H/.config/Vencord/settings/settings.json"
echo '/* the old one */' > "$H/.config/Vencord/themes/midnight.theme.css"
check "discord: two clients to theme" "$(st discord)" "todo|0"
# A client with only Midnight keeps being recoloured; one with Quicktest uses that.
dthemes() ( export HOME="$H" XDG_CONFIG_HOME="$H/.config" SHELL_DIR="$HERE/.."; STAGE="$T/stage"; LOG=/dev/null
            source "$HERE/apps-lib.sh"; discord_themes | sed "s#$H/##" | tr '\n' ' ' )
check "discord: a Midnight-only client is still recoloured" "$(dthemes)" "Vencord:.config/Vencord/themes/midnight.theme.css "
run discord >/dev/null 2>&1
check "discord: quicktest copied" "$(test -s "$H/.config/vesktop/themes/quicktest.theme.css" && echo y)" "y"
check "discord: quicktest copied (patched client)" "$(test -s "$H/.config/Vencord/themes/quicktest.theme.css" && echo y)" "y"
check "discord: midnight swapped out, other themes kept" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["enabledThemes"])' "$H/.config/Vencord/settings/settings.json")" "['Other.theme.css', 'quicktest.theme.css']"
check "discord: midnight's file left alone" "$(cat "$H/.config/Vencord/themes/midnight.theme.css")" "/* the old one */"
check "discord: other settings kept" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["useQuickCss"])' "$H/.config/Vencord/settings/settings.json")" "True"
check "discord: recoloured from the palette" "$(grep -c -e '--qs-base: #101018' -e '--qs-focus: #5a7af8' "$H/.config/Vencord/themes/quicktest.theme.css")" "2"
check "discord: Type & Shape pushed from the cache, not left at repo defaults" "$(grep -c -- '--qs-font: "Test Pushed Font"' "$H/.config/Vencord/themes/quicktest.theme.css")" "1"
check "discord: no stray temp files" "$(ls "$H/.config/Vencord/themes" "$H/.config/Vencord/settings" | grep -c 'qs-new')" "0"
check "discord: ready" "$(st discord)" "ready|0"
check "discord: quicktest now wins over midnight" "$(dthemes)" "Vencord:.config/Vencord/themes/quicktest.theme.css Vesktop:.config/vesktop/themes/quicktest.theme.css "
# A new palette rewrites only the block: still current, so still ready.
python3 "$HERE/themes/discord/quicktest-theme.py" --css "$H/.config/vesktop/themes/quicktest.theme.css" --colors "$H/.cache/wal/colors.json" >/dev/null
check "discord: a recoloured theme is still 'ready'" "$(st discord)" "ready|0"
echo '/* edited */' >> "$H/.config/vesktop/themes/quicktest.theme.css"
check "discord: a theme that differs from the repo's is 'todo'" "$(st discord)" "todo|0"

# ══ Spotify ══ (a stand-in spicetify that keeps its config in a file)
fresh sp; app spotify
check "spotify: no spicetify yet" "$(st spotify)" "todo|0"
mkdir -p "$H/.spicetify" "$H/opt/spotify/Apps" "$H/.config/spotify"; : > "$H/.config/spotify/prefs"
cat > "$H/.spicetify/spicetify" <<EOF
#!/bin/sh
c="$H/.config/spicetify/config-xpui.ini"; mkdir -p "\$(dirname "\$c")"; touch "\$c"
get() { case "\$1" in spotify_path) echo "$H/opt/spotify" ;; prefs_path) echo "$H/.config/spotify/prefs" ;;
        *) sed -n "s/^\$1 *= *//p" "\$c" | head -1 ;; esac; }
case "\$1 \${2:-}" in
  "path userdata") echo "$H/.config/spicetify" ;;
  "backup apply") printf '[Backup]\nversion = 1.2\n' >> "\$c"; echo applied >> "$H/.spicetify/log" ;;
  "apply ") echo applied >> "$H/.spicetify/log" ;;
  config*) shift
     if [ \$# -eq 1 ]; then get "\$1"; exit 0; fi
     while [ \$# -ge 2 ]; do
       if [ "\$1" = extensions ]; then e="\$(get extensions)"; v="\${e:+\$e|}\$2"; else v="\$2"; fi
       grep -v "^\$1 *=" "\$c" > "\$c.n"; echo "\$1 = \$v" >> "\$c.n"; mv "\$c.n" "\$c"; shift 2; done ;;
esac
EOF
chmod +x "$H/.spicetify/spicetify"
check "spotify: needs the theme" "$(st spotify)" "todo|0"
run spotify >/dev/null 2>&1
check "spotify: QuickZiro installed" "$(test -s "$H/.config/spicetify/Themes/QuickZiro/user.css" && test -s "$H/.config/spicetify/Themes/QuickZiro/LICENSE" && echo y)" "y"
check "spotify: pywal scheme written" "$(grep -c '^\[Pywal\]' "$H/.config/spicetify/Themes/QuickZiro/color.ini")" "1"
check "spotify: first apply made a backup" "$(grep -c '^\[Backup\]' "$H/.config/spicetify/config-xpui.ini")" "1"
check "spotify: bridge extension copied" "$(test -f "$H/.config/spicetify/Extensions/quickshell-bridge.js" && echo y)" "y"
check "spotify: ready" "$(st spotify)" "ready|0"
chmod a-w "$H/opt/spotify"; rm -rf "$H/.config/spicetify/Themes"
check "spotify: read-only client needs root" "$(st spotify)" "todo|1"
chmod u+w "$H/opt/spotify"

# ══ Steam ══
fresh steam; app steam
check "steam: no Steam dir yet" "$(st steam)" "absent|0"
mkdir -p "$H/.local/share/Steam"
check "steam: no Millennium, no AUR helper" "$(st steam)" "blocked|0"
app yay; check "steam: Millennium to install" "$(st steam)" "todo|1"
echo millennium-bin >> "$H/.pkgs"
check "steam: Millennium never started" "$(st steam)" "blocked|0"
mkdir -p "$H/.config/millennium"
echo '{"themes":{"activeTheme":"other","allowedScripts":true},"general":{"x":1}}' > "$H/.config/millennium/config.json"
check "steam: theme to install" "$(st steam)" "todo|0"
touch "$H/.steam-running"; run steam >/dev/null 2>&1
check "steam: refuses while Steam runs" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["themes"]["activeTheme"])' "$H/.config/millennium/config.json")" "other"
rm -f "$H/.steam-running"; run steam >/dev/null 2>&1
check "steam: Material downloaded" "$(test -f "$H/.local/share/Steam/millennium/themes/Material-Theme/skin.json" && echo y)" "y"
check "steam: activated" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["themes"]["activeTheme"])' "$H/.config/millennium/config.json")" "Material-Theme"
check "steam: Matugen colour source" "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["themes"]["conditions"]["Material-Theme"]["Color"])' "$H/.config/millennium/config.json")" "Matugen"
check "steam: other settings kept" "$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["general"]["x"], d["themes"]["allowedScripts"])' "$H/.config/millennium/config.json")" "1 True"
check "steam: ready" "$(st steam)" "ready|0"
# a user who already has Material set up their way keeps their settings and their copy
python3 -c 'import json,sys;p=sys.argv[1];d=json.load(open(p));d["themes"]["conditions"]["Material-Theme"]["Font"]="Roboto";d["themes"]["conditions"]["Material-Theme"]["Color"]="Blue";json.dump(d,open(p,"w"))' "$H/.config/millennium/config.json"
check "steam: other colour source needs setup" "$(st steam)" "todo|0"
echo mine > "$H/.local/share/Steam/millennium/themes/Material-Theme/mine"; run steam >/dev/null 2>&1
check "steam: own copy kept" "$(cat "$H/.local/share/Steam/millennium/themes/Material-Theme/mine")" "mine"
check "steam: own settings kept" "$(python3 -c 'import json,sys;c=json.load(open(sys.argv[1]))["themes"]["conditions"]["Material-Theme"];print(c["Font"],c["Color"])' "$H/.config/millennium/config.json")" "Roboto Matugen"
rm -rf "$H/.local/share/Steam"; flatpak_ok() { printf '#!/bin/sh\n[ "$1" = info ] && [ "$2" = com.valvesoftware.Steam ]\n' > "$B/flatpak"; chmod +x "$B/flatpak"; }
flatpak_ok; rm -f "$B/steam"
check "steam: Flatpak only" "$(st steam)" "blocked|0"

# ══ all: only the todo targets run ══
fresh all; mkdir -p "$H/.local/share/themes/adw-gtk3"
run all >/dev/null 2>&1
check "all: gtk set up" "$(st gtk)" "ready|0"
check "all: absent apps untouched" "$(ls "$H/.config" 2>/dev/null | grep -c Vencord)" "0"

echo "$pass passed, $fail failed"
[[ "$fail" = 0 ]]
