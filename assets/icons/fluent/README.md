# Fluent System Icons

Third-party icon set, kept in its own subfolder (rather than loose in `assets/icons/`)
so the provenance stays visible at a glance — same reasoning as `assets/logos/README.md`.

Source: [`microsoft/fluentui-system-icons`](https://github.com/microsoft/fluentui-system-icons),
MIT licensed. Pulled straight from Microsoft's repo rather than copied out of a
dotfiles config that vendors them (end-4's `dots-hyprland` does, and is where the idea
came from) — same designs, no dependency on how a GPL-3.0 repo redistributes someone
else's MIT assets.

All **filled** style at 20px, not regular/outline: the outline cut (~1.5px stroke on a
20px canvas) read as thin and washed-out at bar-icon sizes next to the shell's other,
bolder assets — asked for thicker after the first pass shipped outline.

`headphones.svg` / `headphones-sound-wave.svg` (VolumePill) replaced the `speaker-0/1/2/
mute` set — Fluent's headphones family has no muted/low/medium/high run, only a plain
glyph and a sound-wave one, so `Audio.iconName()` collapsed to two states (see its
comment). Mute is still legible: `VolumePill` tints the icon danger-red when muted,
same as before.

**Wifi, Bluetooth and Mic are NOT here any more** — moved to `assets/icons/` as plain
Material Symbols (`Net.iconPath()`, `Bt.iconPath`, `PrivacyPill`'s `icon:`), matching
Settings/Overview/Wallpaper/Bell, after a couple of rounds of Fluent alternatives
(regular, then filled, then different icons within the family) still didn't land.
Fluent stays for what wasn't complained about: battery, media transport, the weather
set, the lyrics checkmark/dismiss badge, the context-menu chevron, and headphones above.

**There's no ethernet icon here either — nor anywhere in `assets/icons/`.** It went
through Fluent's `Network Adapter` (an ethernet PORT icon, not the NIC-card its name
suggests), then Material's "cable", and landed back on the plain Nerd Font glyph
(`Net.glyph()`, `"󰈀"`) `WifiPill` used before this whole migration — asked back to how
it was before any of this started. `Net.iconPath()` has no wired branch any more;
`WifiPill` checks `Net.wiredConnected` itself and reaches for `glyph()` instead.

Every file is a single `<path>`, recoloured from upstream's baked `#212121` to
`#e3e3e3` — matching every other SVG in `assets/icons/` — before being committed here.
Not load-bearing any more (`TintedIcon` and `IconButton` mask these by alpha now, see
their own comments — the source fill color never reaches the rendered output either
way), but kept for consistency with the sibling assets and so a file opened on its own
doesn't read as a stray near-black glyph.

Replaces the Nerd Font glyphs the bar used to render its own icons with — see the
files under `modules/bar/` for the code side of that migration.
