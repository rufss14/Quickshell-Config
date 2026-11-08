# ── themes/discord/lib.sh ─────────────────────────────────────────────────────
# Sourced, never run: which Discord clients can wear the shell's theme, and the
# palette in the shape pywal-midnight.py reads. One copy, shared by
# scripts/theme-setup.sh (installs the theme) and scripts/apps-lib.sh (recolours it
# on every palette change), so the two can never disagree about where a client is.
#
# A "client" is a Vencord-family config directory — Vencord patched into any
# Discord build, Vesktop, Equicord's Equibop, and their Flatpaks. Each keeps its
# themes in <dir>/themes and its enabled list in <dir>/settings/settings.json.
#
# The theme is Quicktest (vencord/quicktest.theme.css, ours, copied by setup). Midnight
# is what earlier versions installed; a client that has only that is still recoloured,
# but setup no longer fetches it.

QUICKTEST_CSS="${SHELL_DIR:?}/vencord/quicktest.theme.css"
QUICKTEST_PY="${SHELL_DIR:?}/scripts/themes/discord/quicktest-theme.py"
MIDNIGHT_PY="${SHELL_DIR:?}/scripts/themes/discord/pywal-midnight.py"

# discord_script <theme.css>: the script that writes the palette into that theme.
discord_script() {
    if [[ "${1##*/}" == quicktest.theme.css ]]; then printf '%s\n' "$QUICKTEST_PY"
    else printf '%s\n' "$MIDNIGHT_PY"; fi
}

# discord_clients: "<label>:<config dir>" per client present on this machine.
discord_clients() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" entry
    for entry in \
        "Vencord:$cfg/Vencord" \
        "Vesktop:$cfg/vesktop" \
        "Equibop:$cfg/equibop" \
        "Discord Flatpak:$HOME/.var/app/com.discordapp.Discord/config/Vencord" \
        "Vesktop Flatpak:$HOME/.var/app/dev.vencord.Vesktop/config/vesktop" \
    ; do
        [[ -d "${entry#*:}" ]] && printf '%s\n' "$entry"
    done
}

# pywal-midnight.py looks for `colors` as a LIST, `palette` as a list, or color0..15 at
# the TOP level — and pywal's colors.json is none of those (`colors` is an object), so
# handed it raw, every accent fell back to the foreground grey. It gets a copy with
# color0..15 lifted to the top level as well (and so takes color4, its default slot).
# discord_palette <pywal colors.json> <out>
discord_palette() {
    python3 -c 'import json, sys
d = json.load(open(sys.argv[1]))
c = d.get("colors")
if isinstance(c, dict):
    d.update({k: v for k, v in c.items() if k.startswith("color") and k not in d})
json.dump(d, open(sys.argv[2], "w"))' "$1" "$2"
}
