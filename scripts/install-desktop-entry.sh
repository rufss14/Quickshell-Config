#!/usr/bin/env bash
# ── install-desktop-entry.sh ──────────────────────────────────────────────────
# Installs a Settings desktop entry, so the shell's own settings can be launched
# the way every other application is: by typing its name.
#
# ── Why this is a script and not a shipped file ───────────────────────────────
# A .desktop Exec line has to be an ABSOLUTE path, and this config is published —
# it is installed to whatever directory its owner cloned it into. A shipped file
# would therefore have to bake in one machine's home directory, which is exactly
# what the portability rule forbids. So the entry is GENERATED, with the repo path
# derived from this script's own location.
#
# ── Why it is not written automatically at startup ────────────────────────────
# It writes outside the shell's own directory, into the user's data dir. Same
# caution as the fastfetch wallpaper sync being off by default: putting files in
# someone's $XDG_DATA_HOME is a thing to be ASKED for, not a side effect of
# starting a desktop shell.
#
#   ./scripts/install-desktop-entry.sh              install (or refresh)
#   ./scripts/install-desktop-entry.sh --uninstall  remove it again
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

# XDG first, with the spec's own default as the fallback — never a bare $HOME path.
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/applications"
ENTRY="$APP_DIR/quickshell-settings.desktop"

OPENER="$SCRIPT_DIR/settings-open.sh"

refresh_db() {
    # Optional: most launchers read the directory directly, and the shell's own
    # launcher uses Quickshell's DesktopEntries, which watches it. This only helps
    # the ones that keep a cache.
    command -v update-desktop-database >/dev/null 2>&1 \
        && update-desktop-database "$APP_DIR" >/dev/null 2>&1
    return 0
}

if [ "${1:-}" = "--uninstall" ]; then
    if [ -e "$ENTRY" ]; then
        rm -f "$ENTRY" && echo "Removed $ENTRY"
        refresh_db
    else
        echo "Nothing to remove — $ENTRY does not exist."
    fi
    exit 0
fi

[ -f "$OPENER" ] || { echo "Missing $OPENER — is the repo complete?" >&2; exit 1; }
chmod +x "$OPENER" 2>/dev/null

mkdir -p "$APP_DIR" || { echo "Could not create $APP_DIR" >&2; exit 1; }

# ── The entry ────────────────────────────────────────────────────────────────
# Icon is a THEME NAME, not a bundled file: `preferences-system` is in every
# freedesktop icon theme, so it resolves whatever the user has installed rather
# than shipping a picture that clashes with their theme.
#
# StartupNotify=false even though this DOES open a window. The window is created by
# the already-running shell, not by the process the launcher spawned, so it never
# carries the startup-notification id the launcher handed out — the handshake can
# never complete. Left true, the compositor shows a spinner until it times out, while
# the window it is waiting for is already on screen.
#
# Actions let a launcher offer the common destinations directly; launchers that
# don't support them simply ignore the group.
cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=Settings
GenericName=Desktop Shell Settings
Comment=Bar, wallpaper, sound, network and system settings for the Quickshell desktop
Exec=$OPENER
Icon=preferences-system
Terminal=false
StartupNotify=false
Categories=Settings;DesktopSettings;
Keywords=quickshell;shell;bar;wallpaper;appearance;theme;sound;network;
Actions=Wallpaper;Bar;Sound;

[Desktop Action Wallpaper]
Name=Wallpaper
Exec=$OPENER WallpaperPage.qml

[Desktop Action Bar]
Name=Bar
Exec=$OPENER BarPage.qml

[Desktop Action Sound]
Name=Sound
Exec=$OPENER SoundPage.qml
EOF

chmod 644 "$ENTRY"
refresh_db

echo "Installed $ENTRY"
echo "  Exec: $OPENER"
echo
echo "Type \"Settings\" in the launcher. If it doesn't appear straight away, the"
echo "launcher may be holding a cached list — reopening it is enough."
