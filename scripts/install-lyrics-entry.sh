#!/usr/bin/env bash
# ── install-lyrics-entry.sh ────────────────────────────────────────────────────
# Installs a Lyrics desktop entry, so the standalone lyrics window can be
# launched the way every other application is: by typing its name. Mirrors
# install-desktop-entry.sh (the Settings entry) exactly — see that script's
# header for why this is generated rather than shipped, and why it isn't run
# automatically at startup.
#
#   ./scripts/install-lyrics-entry.sh              install (or refresh)
#   ./scripts/install-lyrics-entry.sh --uninstall  remove it again
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"

DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
APP_DIR="$DATA_HOME/applications"
ENTRY="$APP_DIR/quickshell-lyrics.desktop"

OPENER="$SCRIPT_DIR/lyrics-open.sh"

refresh_db() {
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

# Icon is a THEME NAME, not a bundled file — same reasoning as the Settings
# entry's `preferences-system`: this resolves whatever icon theme is installed
# rather than shipping a picture that clashes with it. `audio-x-generic` is a
# standard mimetype icon present in every major theme (Adwaita, Breeze, Papirus).
#
# StartupNotify=false: the window is created by the already-running shell, not
# by the process the launcher spawned, so it never carries the startup-
# notification id the launcher handed out and the handshake can never complete.
cat > "$ENTRY" <<EOF
[Desktop Entry]
Type=Application
Name=Lyrics
GenericName=Synced Lyrics
Comment=Live, time-synced lyrics for whatever is playing, in their own resizable window
Exec=$OPENER
Icon=audio-x-generic
Terminal=false
StartupNotify=false
Categories=AudioVideo;Audio;
Keywords=quickshell;shell;lyrics;music;spotify;karaoke;
EOF

chmod 644 "$ENTRY"
refresh_db

echo "Installed $ENTRY"
echo "  Exec: $OPENER"
echo
echo "Type \"Lyrics\" in the launcher. If it doesn't appear straight away, the"
echo "launcher may be holding a cached list — reopening it is enough."
