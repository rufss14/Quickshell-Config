#!/bin/bash
# ~/.config/dunst/dunst-wal.sh
# Reads pywal colors and rewrites dunstrc colors, then reloads dunst.
# Called automatically after wal runs via wallpaperApplier.

COLORS="$HOME/.cache/wal/colors.json"
DUNSTRC="$HOME/.config/dunst/dunstrc"

if [ ! -f "$COLORS" ]; then
    echo "[dunst-wal] colors.json not found, skipping"
    exit 1
fi

# Parse colors from JSON using awk (no jq dependency)
bg=$(awk -F'"' '/"background"/{print $4; exit}' "$COLORS")
fg=$(awk -F'"' '/"color7"/{print $4}' "$COLORS" | head -1)
dim=$(awk -F'"' '/"color8"/{print $4}' "$COLORS" | head -1)
accent=$(awk -F'"' '/"color2"/{print $4}' "$COLORS" | head -1)
border=$(awk -F'"' '/"color1"/{print $4}' "$COLORS" | head -1)

# Strip leading #
bg="${bg#\#}"
fg="${fg#\#}"
dim="${dim#\#}"
accent="${accent#\#}"
border="${border#\#}"

# Rewrite dunstrc with new colors
sed -i \
    -e "s/background  = \"#[0-9a-fA-F]\{6\}[0-9a-fA-F]\{0,2\}\"/background  = \"#${bg}f5\"/" \
    -e "s/foreground  = \"#[0-9a-fA-F]\{6\}[0-9a-fA-F]\{0,2\}\"/foreground  = \"#${fg}\"/" \
    -e "s/frame_color = \"#[0-9a-fA-F]\{6\}[0-9a-fA-F]\{2\}\"/frame_color = \"#${border}66\"/" \
    "$DUNSTRC"

# Also update the format accent color (title color)
sed -i \
    -e "s/color=\"#[0-9a-fA-F]\{6\}\">\%s<\/span>/color=\"#${accent}\">\%s<\/span>/g" \
    "$DUNSTRC"

# Urgency-specific frame colors
sed -i \
    "/\[urgency_low\]/,/\[urgency/ s/frame_color = \"#[0-9a-fA-F]\{8\}\"/frame_color = \"#${border}33\"/" \
    "$DUNSTRC"
sed -i \
    "/\[urgency_critical\]/,$ s/frame_color = \"#[0-9a-fA-F]\{8\}\"/frame_color = \"#${border}aa\"/" \
    "$DUNSTRC"

echo "[dunst-wal] Colors updated: bg=#${bg} fg=#${fg} accent=#${accent} border=#${border}"

# Reload dunst if running
if pgrep -x dunst > /dev/null; then
    dunstctl reload
    echo "[dunst-wal] dunst reloaded"
else
    echo "[dunst-wal] dunst not running, skipping reload"
fi
