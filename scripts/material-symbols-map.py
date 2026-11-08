#!/usr/bin/env python3
"""Map this shell's Nerd Font glyphs onto Material Symbols ligature names.

    python3 scripts/material-symbols-map.py --report     every occurrence + confidence
    python3 scripts/material-symbols-map.py --residue    ONLY the ones nothing resolved
    python3 scripts/material-symbols-map.py --emit       write assets/fonts/* + services/icons.js
    python3 scripts/material-symbols-map.py --rewrite modules/bar/widgets/WifiPill.qml

── Why this is generated and not hand-written ────────────────────────────────
The shell had 685 glyph occurrences across 75 files, 250 of them distinct, and
every one is in Nerd Font's Material Design Icons block (U+F0xxx). The Nerd Font
carries the ORIGINAL MDI name for each of those in its own cmap — U+F0156 is
`md-close` — and MDI and Material Symbols are both Google icon sets, so most
names are already identical or differ predictably. That makes this a derivation
with a small hand-maintained exception table, not 250 judgement calls.

── The two things it refuses to guess ────────────────────────────────────────
1. Every proposed name is checked against the ligature table of the INSTALLED
   Material Symbols font. A plausible-looking name the font does not have would
   render as the literal English word in the middle of the bar, and it would do
   so only on machines that have the font — i.e. not necessarily yours.
2. `--rewrite` only touches lines it resolved with confidence. Anything
   unresolved is left exactly as it was and printed, rather than being rewritten
   to a guess.

── --emit builds the shell's OWN icon fonts ─────────────────────────────────
The shell draws no icon from an installed font. A pacman upgrade of the Nerd Font
(3.5.0) once shifted every glyph ID under the running shell and scrambled every
icon; an upgrade of the AUR Material Symbols build could rename or drop a
ligature just as silently. So --emit cuts two small fonts out of the installed
ones and commits them to assets/fonts/:

  QuicktestSymbols.ttf  every Material Symbols name the tree uses, FILL + wght + opsz
                        kept as live axes (the fill animation, optical sizing), GRAD pinned
  QuicktestGlyphs.otf   every Nerd Font codepoint the tree spells — brand marks,
                        the About page's Codicons, and the MDI glyphs still drawn
                        as glyphs

Both get a family name of their own, so an installed font can never shadow them,
and services/icons.js is written in the same run with the codepoints read out of
the very file it ships next to. The installed fonts are a BUILD input only: the
person who runs this needs them; nobody who installs the shell does.

── Paths ────────────────────────────────────────────────────────────────────
The repo is found from __file__ and the fonts from fontconfig. Nothing here
knows where anyone's home directory is: this config is published, and
scripts/test-discord-*.py once hardcoded one author's path and broke for
everybody else.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Directories that are not ours to rewrite.
SKIP_DIRS = {"config/settings"}

# Nerd Font's Material Design Icons block.
PUA_LO, PUA_HI = 0xF0000, 0xF0FFF

# ── The bundled fonts ─────────────────────────────────────────────────────────
FONT_DIR       = REPO / "assets" / "fonts"
SYMBOLS_FONT   = FONT_DIR / "QuicktestSymbols.ttf"
GLYPHS_FONT    = FONT_DIR / "QuicktestGlyphs.otf"
SYMBOLS_FAMILY = "Quicktest Symbols"
GLYPHS_FAMILY  = "Quicktest Glyphs"

# Pinned rather than kept as live axes: nothing varies GRAD, and pinning it is part of what
# takes the cut from ~840 KB toward ~230 KB. FILL, wght AND opsz stay live: FILL is the
# outline->solid animation, wght is Tokens.symbolWeight (+ symbolFillBoost with the fill), and
# opsz (20-48) is the font's own optical sizing, set per icon from its pixel size by
# MaterialIcon. (opsz was pinned at 24 until 2026-10-10, which drew a 14px and a 40px icon
# with the same stroke; expect the cut to grow by roughly a third for the extra axis.)
PINNED_AXES = {"GRAD": 0}

# What an unknown name draws: a visible "no such icon", never blank.
UNKNOWN_SYMBOL = "help"

# Any Private Use Area codepoint — where every icon font keeps its icons. Wider
# than PUA_LO..PUA_HI: the About page's Codicons and Font Awesome marks live in
# the BMP area, and those are drawn as glyphs too.
def is_pua(cp: int) -> bool:
    return 0xE000 <= cp <= 0xF8FF or 0xF0000 <= cp <= 0xFFFFD or 0x100000 <= cp <= 0x10FFFD

# `\u{F0214}` and `\uF005` — the escape forms. scan() reads raw characters only,
# so escaped glyphs were invisible to it; the glyph font must not miss them.
ESCAPE_RE = re.compile(r"\\u\{([0-9A-Fa-f]{4,6})\}|\\u([0-9A-Fa-f]{4})")
# A quoted lowercase identifier: every string that COULD be an icon name.
LITERAL_RE = re.compile(r"""["']([a-z][a-z0-9_]*)["']""")

# A glyph literal being assigned to a property, e.g.  glyph: "6"
# Captures the property name so `glyph:` (mechanical) can be told apart from
# `text:` (structural — a StyledText has to become a MaterialIcon, which is an
# element-type change and not this script's business).
ASSIGN_RE = re.compile(r'(\w+)\s*:\s*(.*)$')


# ── MDI → Material Symbols, where the two sets disagree ───────────────────────
# Only entries where the name genuinely differs. Anything resolvable by an exact
# match or by dropping a trailing `_outline` must NOT be listed here — a
# redundant alias is a second source of truth that can drift from the font.
ALIASES = {
    # Different word for the same thing
    "magnify":              "search",
    "plus":                 "add",
    "minus":                "remove",
    "console":              "terminal",
    "bell":                 "notifications",
    "bell_off":             "notifications_off",
    "pencil":               "edit",
    "cog":                  "settings",
    "trash_can":            "delete",
    "information":          "info",
    "alert":                "warning",
    "alert_circle":         "error",
    "magnify_plus":         "zoom_in",
    "magnify_minus":        "zoom_out",
    "dots_vertical":        "more_vert",
    "dots_horizontal":      "more_horiz",
    "restart":              "restart_alt",

    # MDI names a level, Symbols names a direction
    "volume_high":          "volume_up",
    "volume_medium":        "volume_down",
    "volume_low":           "volume_down",
    "volume_variant_off":   "volume_off",

    # Domain words
    "gamepad_variant":      "sports_esports",
    "weather_night":        "bedtime",
    "weather_sunny":        "sunny",
    "microphone":           "mic",
    "microphone_off":       "mic_off",
    "harddisk":             "hard_drive",
    "chip":                 "memory",
}

# Filled in by hand from `--residue`, highest occurrence count first. Lives in
# this file rather than in a side-car so there is one source of truth and it
# shows up in `git diff`.
#
# Every entry here was checked against the installed font's ligature table before
# being written down — none of these are guesses at names that sound plausible.
MANUAL: dict[str, str] = {
    "access_point_network":      "router",
    "alarm_plus":                "alarm_add",
    "alert_outline":             "warning",
    "application":               "apps",
    "backburger":                "menu_open",
    "battery":                   "battery_full",
    "battery_10":                "battery_1_bar",
    "battery_40":                "battery_3_bar",
    "battery_charging":          "battery_charging_full",
    "bluetooth_connect":         "bluetooth_connected",
    "bluetooth_off":             "bluetooth_disabled",
    "bluetooth_settings":        "settings_bluetooth",
    "broom":                     "cleaning_services",
    "calculator":                "calculate",
    "caps_lock":                 "keyboard_capslock",
    "checkbox_blank_outline":    "check_box_outline_blank",
    "checkbox_marked":           "check_box",
    "chevron_down":              "keyboard_arrow_down",
    "chevron_left":              "keyboard_arrow_left",
    "chevron_right":             "keyboard_arrow_right",
    "chevron_up":                "keyboard_arrow_up",
    "clipboard_text":            "content_paste",
    "clock_outline":             "schedule",
    "close_circle":              "cancel",
    "close_circle_outline":      "cancel",
    "coffee_off":                "no_drinks",
    "content_save":              "save",
    "earth":                     "public",
    "eye":                       "visibility",
    "eye_off":                   "visibility_off",
    "folder_move":               "drive_file_move",
    "google_controller":         "sports_esports",
    "google_controller_off":     "videogame_asset_off",
    "help_circle":               "help",
    "image_filter_center_focus": "center_focus_strong",
    "import":                    "download",
    "information_outline":       "info",
    "key_variant":               "key",
    "lead_pencil":               "edit",
    "link_variant":              "link",
    "music":                     "music_note",
    "network":                   "lan",
    "package_variant_closed":    "inventory_2",
    "phone_bluetooth":           "bluetooth_audio",
    "play":                      "play_arrow",
    "playlist_music_outline":    "queue_music",
    "reload":                    "refresh",
    "repeat_once":               "repeat_one",
    "run_fast":                  "directions_run",
    "server":                    "dns",
    "text_box":                  "description",
    "timer_sand":                "hourglass_empty",
    "trash_can_outline":         "delete",
    "video":                     "videocam",
    "view_dashboard":            "dashboard",
    "view_dashboard_outline":    "dashboard",
    "wall_sconce_round_variant": "light",
    "weather_cloudy":            "cloud",
    "weather_lightning":         "thunderstorm",
    "weather_partly_cloudy":     "partly_cloudy_day",
    "weather_pouring":           "rainy",
    "weather_rainy":             "rainy",
    "weather_sunset":            "wb_twilight",
    "weather_sunset_down":       "wb_twilight",
    "wifi_strength_4":           "wifi",
    "wifi_strength_off":         "wifi_off",
    "window_maximize":           "fullscreen",

    # ── The long tail: one occurrence each ────────────────────────────────
    "ab_testing":                  "science",
    "animation_play_outline":      "animation",
    "arrow_down":                  "arrow_downward",
    "arrow_up":                    "arrow_upward",
    "blur":                        "blur_on",
    "bookmark_multiple_outline":   "bookmarks",
    "calendar_text_outline":       "event_note",
    "cellphone":                   "smartphone",
    "checkbox_blank_circle":       "circle",
    "cpu_64_bit":                  "memory",
    "cursor_default_outline":      "mouse",
    "cursor_move":                 "open_with",
    "drag_variant":                "drag_indicator",
    "expansion_card":              "developer_board",
    "eye_outline":                 "visibility",
    "file_document_edit":          "edit_document",
    "file_find":                   "find_in_page",
    "folder_image":                "folder",
    "folder_multiple":             "folder_copy",
    "format_font":                 "text_fields",
    "format_text":                 "title",
    "forwardburger":               "menu",
    "monitor_speaker":             "speaker",
    "pin_off":                     "push_pin",
    "play_box_outline":            "smart_display",
    "plus_box_outline":            "add_box",
    "power_socket_au":             "power",
    "progress_clock":              "pending",
    "record":                      "fiber_manual_record",
    "rename_box":                  "drive_file_rename_outline",
    "shape_outline":               "category",
    "shield_key_outline":          "vpn_key",
    "speedometer":                 "speed",
    "sticker_emoji":               "emoji_emotions",
    "television_box":              "tv",
    "test_tube":                   "science",
    "text_long":                   "notes",
    "vector_rectangle":            "rectangle",
    "video_input_hdmi":            "settings_input_hdmi",
    "video_outline":               "videocam",
    "white_balance_sunny":         "light_mode",
    "wifi_strength_off_outline":   "wifi_off",
    "calendar":                    "calendar_month",
    "chart_bar":                   "bar_chart",
    "checkbox_multiple_marked_outline": "checklist",
    "clipboard_outline":           "content_paste",
    "note_text":                   "sticky_note_2",
    "weather_fog":                 "foggy",
    "weather_night_partly_cloudy": "partly_cloudy_night",
    "wifi_strength_1":             "network_wifi_1_bar",
    "wifi_strength_2":             "network_wifi_2_bar",
    "wifi_strength_3":             "network_wifi_3_bar",
    "wifi_strength_alert_outline": "signal_wifi_bad",

    # The 2026-10-03 residue pass: the last unresolved names, picked by what the
    # call site MEANS (a phone cell, a Motion card, a disk-activity ring), not by how
    # the MDI name sounds. Each one checked against the installed font.
    "headphones_off":            "headset_off",
    "headphones_settings":       "headphones",
    "printer_alert":             "print_error",
    "cellphone_arrow_down":      "download",
    "cellphone_off":             "mobile_off",
    "cellphone_link":            "phonelink",
    "cellphone_sound":           "ring_volume",
    "bell_ring":                 "notifications_active",
    "ethernet":                  "lan",
    "ethernet_cable_off":        "cable",
    "stove":                     "animation",
    "crosshairs_gps":            "my_location",
    "eyedropper":                "colorize",
    "view_grid":                 "grid_view",
    "calendar_text":             "event_note",
    "export":                    "ios_share",
    "sale":                      "sell",
    "message_reply_text":        "quickreply",
    "file_video_outline":        "video_file",
    "cursor_pointer":            "arrow_selector_tool",
    "cursor_default_click":      "ads_click",
    "arrow_split_vertical":      "vertical_split",
    "swap_horizontal":           "swap_horiz",
    "swap_vertical":             "swap_vert",
    "account_voice":             "record_voice_over",
    "puzzle":                    "extension",
    "file_swap":                 "swap_calls",
    "database_sync":             "sync_alt",

    # MDI `power` is the IEC on/off button; Material Symbols `power` is a PLUG.
    # An exact match would resolve and be silently wrong, which is why MANUAL
    # outranks it.
    "power":                     "power_settings_new",
}

# ── Icons that have NO Material Symbols equivalent, and never will ────────────
# Material Symbols is Google's UI icon set. It does not contain third-party
# brand marks, and it has no letter-in-a-box glyphs. These stay on the Nerd Font
# permanently — they are not a migration backlog.
#
# Keeping them separate from UNMATCHED is the whole point: `--residue` is a
# worklist, and a worklist that never empties stops being read. A site using one
# of these keeps its `glyph:` property, which IconButton still supports.
NO_SYMBOL = {
    "discord",      # brand mark
    "spotify",      # brand mark
    "steam",        # brand mark
    "arch",         # distro logo
    "alpha_b_box",  # a letter B in a box; Symbols has no alphabet glyphs
    "firefox",      # brand mark
    "google_chrome",# brand mark
    "vlc",          # brand mark
}

# ── Material Symbols names with no Nerd Font glyph anywhere in the tree ────────
# Names a call site spells as Material Symbols from the start — the clock panel's
# weather icons, wind arrow, event states. Until the icons were bundled this was the
# Nerd Font FALLBACK for each (Symbols name -> MDI name); there is no fallback path
# any more, so only the KEYS are read now: each is forced into the bundled font even
# if it never appears as a string literal. The MDI values are kept as the record of
# what each name used to fall back to.
SYMBOL_ONLY = {
    "clear_night":          "weather_night",
    "rainy_light":          "weather_rainy",
    "rainy_heavy":          "weather_pouring",
    "weather_hail":         "weather_hail",
    "navigation":           "navigation",
    "humidity_percentage":  "water_percent",
    "umbrella":             "umbrella",
    # This Nerd Font has no face_mask; smog is the air-quality mark it does have.
    "masks":                "smog",
    "local_florist":        "flower",
    "location_off":         "map_marker_off",
    "event_busy":           "calendar_remove",
    "event_available":      "calendar_check",
    # The clock panel's calendar page.
    "rss_feed":             "rss",
    "arrow_back":           "arrow_left",
    "location_on":          "map_marker",
    "chevron_left":         "chevron_left",
    "chevron_right":        "chevron_right",
    # Special dates: national / regional / observance. No party_popper in this
    # Nerd Font; firework is the nearest mark it has.
    "celebration":          "firework",
    "flag":                 "flag",
    "star":                 "star",
    # The Calendar page: reminders, day facts, quick times, events.
    "notifications_active": "bell_ring",
    # The names the newer panels (clip editor, Bluetooth, launcher, phone) spell
    # directly. Without a Nerd Font glyph here, each is a help-circle on a machine that
    # lacks the AUR font; test-icons.js `coverage` is what found them.
    "folder_open":          "folder_open",
    "first_page":           "page_first",
    "last_page":            "page_last",
    "photo_camera":         "camera",
    "volume_off":           "volume_off",
    "hourglass_top":        "timer_sand",
    "file_export":          "file_export",
    "more_horiz":           "dots_horizontal",
    "verified_user":        "shield_check",
    "upload_file":          "file_upload",
    "link_off":             "link_off",
    "bluetooth_searching":  "bluetooth_connect",
    "add_link":             "link_plus",
    "keep":                 "pin",
    "keyboard_return":      "keyboard_return",
    "casino":               "dice_multiple",
    "language":             "web",
    "auto_awesome":         "creation",
    "memory_alt":           "memory",
    "thermostat":           "thermometer",
    "import_export":        "swap_vertical",
    "preview":              "eye",
    "crop_free":            "crop_free",
    "video_library":        "filmstrip_box",
    "call_split":           "call_split",
    "block":                "block_helper",
    "radio_button_unchecked":"checkbox_blank_circle_outline",
    "check_circle":         "check_circle",
    "task_alt":             "check_circle_outline",
    "snooze":               "alarm_snooze",
    "calendar_view_week":   "calendar_week",
    "today":                "calendar_today",
    "hourglass_bottom":     "timer_sand",
    "dark_mode":            "weather_night",
    "nights_stay":          "weather_night",
    "wb_sunny":             "weather_sunny",
    "event":                "calendar",
    "add_alert":            "bell_plus",
    # The Bar page's arrange-mode button: four-way move arrows.
    "drag_pan":             "cursor_move",
}

CONFIDENCE_ORDER = ["exact", "outline", "alias", "manual", "no-symbol", "UNMATCHED"]


# ── Font access ───────────────────────────────────────────────────────────────
def _fc_match(family: str) -> Path | None:
    try:
        out = subprocess.run(
            ["fc-match", "-f", "%{file}", family],
            capture_output=True, text=True, timeout=20,
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None
    p = Path(out) if out else None
    return p if p and p.exists() else None


def nerd_font_names(font_path: Path) -> dict[int, str]:
    """codepoint -> MDI name, from the Nerd Font's own cmap ('md-close' -> 'close').

    U+F0000–U+F0FFF *is* the Material Design Icons block in a Nerd Font, so every
    glyph in it is an MDI name and the `md-` prefix does not need to be required.
    Requiring it silently dropped U+F0388, which this font names `music-note`
    rather than `md-music_note` — it landed in the residue looking like an
    unknown glyph instead of the exact match it is. Hyphens are normalised to
    underscores for the same reason.
    """
    from fontTools.ttLib import TTFont

    cmap = TTFont(str(font_path), lazy=True).getBestCmap()
    out = {}
    for cp, glyph in cmap.items():
        if PUA_LO <= cp <= PUA_HI:
            name = glyph[3:] if glyph.startswith("md-") else glyph
            out[cp] = name.replace("-", "_")
    return out


def symbols_ligatures(font_path: Path) -> set[str]:
    """Every ligature name the Material Symbols font actually defines."""
    return set(symbols_ligature_glyphs(font_path))


def symbols_ligature_glyphs(font_path: Path) -> dict[str, str]:
    """Ligature name -> the glyph it produces, for every name the font defines.

    Not always a glyph of the same name: `clear_night` and `nights_stay` are aliases
    that land on another icon's glyph, which is why --emit resolves through this
    rather than looking the name up in the glyph order.

    The package ships only the .ttf files — no codepoints listing — so the names
    come out of GSUB. Two things make that less obvious than it sounds:

      * the ligature lookups are wrapped in ExtensionSubst (LookupType 7), so the
        real LigatureSubst is one level down in .ExtSubTable;
      * the components resolve to UPPERCASE codepoints, because the font maps
        both cases of each letter to one glyph and the reverse cmap keeps
        whichever it saw first. The names are lowercased on the way out.

    The features are `rlig`/`rclt` rather than `liga`, which is why no Qt
    font-feature setting is needed at the call site: rlig is a REQUIRED feature
    and HarfBuzz applies it by default.
    """
    from fontTools.ttLib import TTFont

    font = TTFont(str(font_path), lazy=True)
    if "GSUB" not in font:
        return {}

    rev: dict[str, int] = {}
    for cp, glyph in font.getBestCmap().items():
        rev.setdefault(glyph, cp)

    names: dict[str, str] = {}
    for lookup in font["GSUB"].table.LookupList.Lookup:
        for sub in lookup.SubTable:
            if sub.__class__.__name__ == "ExtensionSubst":
                sub = sub.ExtSubTable
                if hasattr(sub, "ensureDecompiled"):
                    sub.ensureDecompiled()
            ligatures = getattr(sub, "ligatures", None)
            if not ligatures:
                continue
            for first, entries in ligatures.items():
                for lig in entries:
                    try:
                        word = "".join(chr(rev[c]) for c in [first] + list(lig.Component))
                    except KeyError:
                        continue
                    names.setdefault(word.lower(), lig.LigGlyph)
    return names


def _tree_texts():
    """(relative path, text) for every .qml and .js the shell runs — not icons.js."""
    for path in sorted(REPO.rglob("*")):
        if path.suffix not in (".qml", ".js") or "node_modules" in path.parts:
            continue
        rel = path.relative_to(REPO).as_posix()
        if rel == "services/icons.js" or any(rel.startswith(skip) for skip in SKIP_DIRS):
            continue
        try:
            yield rel, path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue


def tree_codepoints() -> set[int]:
    """Every PUA codepoint the tree spells — raw OR escaped, .qml AND .js.

    A superset on purpose: a glyph in a comment costs a few hundred bytes, a glyph
    missed costs a blank (or a system-font) icon. What goes in QuicktestGlyphs."""
    out: set[int] = set()
    for _, text in _tree_texts():
        out.update(ord(c) for c in text if is_pua(ord(c)))
        for braced, bare in ESCAPE_RE.findall(text):
            cp = int(braced or bare, 16)
            if is_pua(cp):
                out.add(cp)
    return out


def tree_literal_names(valid: set[str]) -> set[str]:
    """Every quoted string in the tree that is also a Material Symbols name.

    The registry alone (icons.js, `symbol:`, `MaterialIcon { name: }`) misses names
    that travel as data — `LauncherAction { icon: "…" }`, SettingsIndex's `icon:`,
    the weather table — which the full installed font used to render regardless.
    A cut font would draw each as a help-circle. Taking every literal that happens
    to be a valid name over-includes (`"left"`, `"start"`) by ~100 small icons, and
    that is the cheap side of the trade."""
    out: set[str] = set()
    for _, text in _tree_texts():
        out.update(n for n in LITERAL_RE.findall(text) if n in valid)
    return out


def _rename(font, family: str) -> None:
    """Give a cut font a family of its own.

    Both so an installed copy of the source can never be picked in its place (two
    faces with one family name and Qt chooses — that ambiguity is the dependency
    this exists to remove), and because the OFL asks a modified font not to keep
    the original's name."""
    name = font["name"]
    style = name.getDebugName(2) or "Regular"
    ps = family.replace(" ", "") + "-" + style.replace(" ", "")
    # Typographic family/style and the variations PostScript prefix: dropped, so
    # nameID 1 is the only family a reader can find.
    for nid in (16, 17, 21, 22, 25):
        name.removeNames(nameID=nid)
    for nid, val in ((1, family), (3, ps + ";quicktest"),
                     (4, family if style == "Regular" else f"{family} {style}"), (6, ps)):
        name.removeNames(nameID=nid)
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)
    if "CFF " in font:
        font["CFF "].cff.fontNames = [ps]


def cut_font(src: Path, unicodes: set[int], family: str, dest: Path,
             pin: dict[str, float] | None = None) -> None:
    """Subset `src` to `unicodes`, optionally pin variable axes, rename, save."""
    from fontTools import subset
    from fontTools.ttLib import TTFont

    font = TTFont(str(src))
    opts = subset.Options()
    # Every layout feature, so `rvrn` survives: it is how Material Symbols swaps an
    # outline glyph for its `.fill` twin along the FILL axis. The letters are not
    # kept, so the ligature lookups (rlig) drop out on their own — icons.js hands
    # MaterialIcon the CODEPOINT, which needs no shaping feature at all.
    opts.layout_features = ["*"]
    opts.notdef_outline = True
    sub = subset.Subsetter(opts)
    sub.populate(unicodes=sorted(unicodes))
    sub.subset(font)
    if pin:
        from fontTools.varLib.instancer import instantiateVariableFont
        instantiateVariableFont(font, pin, inplace=True)
    _rename(font, family)
    dest.parent.mkdir(parents=True, exist_ok=True)
    font.save(str(dest))


def _sha(path: Path) -> str:
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()[:16]


# ── Resolution ────────────────────────────────────────────────────────────────
def resolve(mdi: str, valid: set[str] | None) -> tuple[str | None, str]:
    """MDI name -> (Material Symbols name, which rule fired)."""
    def ok(name: str) -> bool:
        return valid is None or name in valid

    # Checked first: these are a decision, not a failure to resolve.
    if mdi in NO_SYMBOL:
        return None, "no-symbol"
    if mdi in MANUAL:
        return MANUAL[mdi], "manual"
    if ok(mdi):
        return mdi, "exact"

    # Symbols has no separate outline NAMES — it has a FILL axis, so
    # `palette_outline` is `palette` drawn at fill 0. This resolves a large
    # fraction of the MDI set on its own.
    stripped = re.sub(r"[-_]outline$", "", mdi)
    if stripped != mdi and ok(stripped):
        return stripped, "outline"

    if mdi in ALIASES and ok(ALIASES[mdi]):
        return ALIASES[mdi], "alias"

    # An alias whose target the font lacks is worse than no alias: report it.
    if mdi in ALIASES:
        return None, "UNMATCHED"

    return None, "UNMATCHED"


# ── Scanning ──────────────────────────────────────────────────────────────────
def qml_files() -> list[Path]:
    out = []
    for path in sorted(REPO.rglob("*.qml")):
        rel = path.relative_to(REPO).as_posix()
        if any(rel.startswith(skip) for skip in SKIP_DIRS):
            continue
        out.append(path)
    return out


def scan() -> list[dict]:
    """Every PUA glyph occurrence, with the property it is assigned to."""
    hits = []
    for path in qml_files():
        try:
            lines = path.read_text(encoding="utf-8").split("\n")
        except (OSError, UnicodeDecodeError):
            continue
        for n, line in enumerate(lines, 1):
            chars = [c for c in line if PUA_LO <= ord(c) <= PUA_HI]
            if not chars:
                continue
            m = ASSIGN_RE.search(line.strip())
            prop = m.group(1) if m else "?"
            for c in chars:
                hits.append({
                    "file": path.relative_to(REPO).as_posix(),
                    "line": n,
                    "prop": prop,
                    "cp": ord(c),
                    "char": c,
                })
    return hits


def annotate(hits, mdi_names, valid):
    for h in hits:
        mdi = mdi_names.get(h["cp"])
        h["mdi"] = mdi
        if mdi is None:
            h["symbol"], h["confidence"] = None, "UNMATCHED"
        else:
            h["symbol"], h["confidence"] = resolve(mdi, valid)
    return hits


# ── Output modes ──────────────────────────────────────────────────────────────
def cmd_report(hits) -> int:
    by_conf = Counter(h["confidence"] for h in hits)
    for h in sorted(hits, key=lambda x: (x["file"], x["line"])):
        print(f"{h['file']}:{h['line']}  {h['prop']:<14} U+{h['cp']:05X}  "
              f"{(h['mdi'] or '?'):<26} -> {(h['symbol'] or '—'):<26} [{h['confidence']}]")
    print()
    for conf in CONFIDENCE_ORDER:
        if by_conf.get(conf):
            print(f"  {conf:<12} {by_conf[conf]}")
    print(f"  {'TOTAL':<12} {len(hits)}")
    return 0


def cmd_residue(hits) -> int:
    """The hand-mapping worklist: unresolved names, biggest win first."""
    groups = defaultdict(list)
    for h in hits:
        if h["confidence"] == "UNMATCHED":
            groups[h["mdi"] or f"U+{h['cp']:05X}"].append(h)

    if not groups:
        print("Residue is empty — every glyph resolved.")
        return 0

    print(f"{len(groups)} unresolved name(s), {sum(len(v) for v in groups.values())} occurrence(s).")
    print("Add entries to MANUAL in this script, then re-run.\n")
    for mdi, entries in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        print(f"  {mdi}   ({len(entries)}x)  U+{entries[0]['cp']:05X}  {entries[0]['char']}")
        for e in entries[:6]:
            print(f"      {e['file']}:{e['line']}  ({e['prop']})")
        if len(entries) > 6:
            print(f"      … and {len(entries) - 6} more")
    return 1


def cmd_emit(hits, sym_path: Path, nerd_path: Path) -> int:
    """Cut assets/fonts/* out of the installed fonts and write services/icons.js.

    One run, one artifact: icons.js holds codepoints read from the very font file
    written beside it, and stamps that file's hash so test-icons.js can tell if the
    two ever drift apart (a map that points into a different font draws the WRONG
    icon, silently — the exact failure bundling exists to end).
    """
    from fontTools.ttLib import TTFont

    ligs = symbols_ligature_glyphs(sym_path)
    if not ligs:
        print(f"error: {sym_path} has no ligature table — is it Material Symbols?", file=sys.stderr)
        return 2
    valid = set(ligs)
    existing = REPO / "services" / "icons.js"
    old = existing.read_text(encoding="utf-8") if existing.exists() else ""

    # ── Which names go in ─────────────────────────────────────────────────────
    # The committed map's keys (the record — a migrated call site spells the NAME,
    # so its glyph is no longer in the tree for scan() to find), what scan()
    # resolves today, SYMBOL_ONLY, every literal that is a name, and the
    # unknown-name mark.
    names = set(re.findall(r'^\s*"(\w+)": "\\u\{[0-9A-Fa-f]+\}",$', old, re.M))
    names |= {h["symbol"] for h in hits if h["symbol"]}
    names |= set(SYMBOL_ONLY) | tree_literal_names(valid) | {UNKNOWN_SYMBOL}

    # ── The other direction: Nerd Font codepoint -> Symbols name ──────────────
    # So a call site can keep handing MaterialIcon the glyph it always had (`glyph:
    # "\u{F0349}"`, a ternary of two, a field of a service's table) and still get the
    # Material icon. Carried forward from the committed map, plus today's scan.
    rev: dict[int, str] = {}
    blk = re.search(r"var NAME = \{(.*?)\n\}", old, re.S)
    if blk:
        for hexcp, nm in re.findall(r'"([0-9A-Fa-f]+)": "(\w+)",', blk.group(1)):
            rev[int(hexcp, 16)] = nm
    for h in hits:
        if h["symbol"]:
            rev[h["cp"]] = h["symbol"]
    names |= set(rev.values())

    missing = sorted(n for n in names if n not in valid)
    for n in missing:
        print(f"warning: '{n}' is not a Material Symbols name in {sym_path.name} — skipped",
              file=sys.stderr)
    names -= set(missing)

    src_cmap: dict[str, int] = {}
    for cp, glyph in TTFont(str(sym_path), lazy=True).getBestCmap().items():
        src_cmap.setdefault(glyph, cp)
    cp_of: dict[str, int] = {}
    for n in sorted(names):
        cp = src_cmap.get(ligs[n])
        if cp is None:
            print(f"warning: '{n}' -> glyph {ligs[n]} has no codepoint — skipped", file=sys.stderr)
            continue
        cp_of[n] = cp

    # ── The two fonts ─────────────────────────────────────────────────────────
    glyph_cps = tree_codepoints()
    nerd_cmap = TTFont(str(nerd_path), lazy=True).getBestCmap()
    absent = sorted(cp for cp in glyph_cps if cp not in nerd_cmap)
    for cp in absent:
        print(f"note: U+{cp:04X} is spelled in the tree but not in {nerd_path.name} — "
              f"left out of the glyph font", file=sys.stderr)
    glyph_cps -= set(absent)

    cut_font(sym_path, set(cp_of.values()), SYMBOLS_FAMILY, SYMBOLS_FONT, PINNED_AXES)
    cut_font(nerd_path, glyph_cps, GLYPHS_FAMILY, GLYPHS_FONT)

    # ── icons.js ──────────────────────────────────────────────────────────────
    sym_body = "\n".join(f'    "{n}": "\\u{{{cp:X}}}",' for n, cp in sorted(cp_of.items()))
    rev_body = "\n".join(f'    "{cp:X}": "{nm}",' for cp, nm in sorted(rev.items()) if nm in cp_of)
    glyph_list = " ".join(f"{cp:X}" for cp in sorted(glyph_cps))
    version = lambda p: TTFont(str(p), lazy=True)["name"].getDebugName(5)
    sources = f"{sym_path.name} ({version(sym_path)}), {nerd_path.name} ({version(nerd_path)})"

    out = ICONS_JS.format(sources=sources, sym_sha=_sha(SYMBOLS_FONT),
                          glyph_sha=_sha(GLYPHS_FONT), sym_body=sym_body,
                          rev_body=rev_body, glyph_list=glyph_list)
    existing.write_text(out, encoding="utf-8")
    for f in (SYMBOLS_FONT, GLYPHS_FONT):
        print(f"wrote {f.relative_to(REPO)}  ({f.stat().st_size // 1024} KB)")
    print(f"wrote {existing.relative_to(REPO)}  ({len(cp_of)} symbols, {len(glyph_cps)} glyphs)")
    return 1 if missing else 0


ICONS_JS = """.pragma library

// ── icons.js ──────────────────────────────────────────────────────────────────
// GENERATED by scripts/material-symbols-map.py — do not hand-edit.
// Regenerate with:  python3 scripts/material-symbols-map.py --emit
// (which rewrites assets/fonts/ in the same run — the two are one artifact).
//
// ── The icons are the shell's own, not the system's ──────────────────────────
// Every icon is drawn from a font in assets/fonts/, loaded by Tokens:
//
//   Quicktest Symbols   the Material Symbols this tree names (SYMBOL below)
//   Quicktest Glyphs    every Nerd Font codepoint this tree spells (GLYPHS) —
//                       brand marks, Codicons, MDI glyphs still drawn as glyphs
//
// No icon font has to be installed, and no package upgrade can change one: a
// Nerd Font release once shifted every glyph ID under the running shell and drew
// every icon as a different icon. The codepoints below were read out of the cut
// fonts' sources in the same run that wrote them; BUILD is their hash, checked by
// scripts/test-icons.js, so a map that drifted from its font fails a test instead
// of drawing the wrong icon.
//
// Built from: {sources}
// ─────────────────────────────────────────────────────────────────────────────
var BUILD = {{ symbols: "{sym_sha}", glyphs: "{glyph_sha}" }}

// Material Symbols name -> its codepoint in Quicktest Symbols.
var SYMBOL = {{
{sym_body}
}}

// The character for a name, or "" for an unknown one — never undefined, so a
// caller's `||` fallback works rather than rendering the string "undefined".
function symbol(name) {{
    return SYMBOL[name] || ""
}}

// ── The glyph this shell used to spell -> its Symbols name ────────────────────
// Keyed by uppercase hex codepoint. Brand marks (Discord, Steam, Arch…) are
// deliberately ABSENT: Material Symbols has no such icons; they draw from
// Quicktest Glyphs as they are.
var NAME = {{
{rev_body}
}}

// The Symbols name for ONE glyph character, or "" — for a string that is anything
// but a single mapped glyph (a word, an emoji, a brand mark), so the caller can fall
// back to drawing it as it is.
function nameOf(ch) {{
    if (!ch) return ""
    const cp = ch.codePointAt(0)
    if (ch.length !== (cp > 0xFFFF ? 2 : 1)) return ""
    return NAME[cp.toString(16).toUpperCase()] || ""
}}

// Every codepoint Quicktest Glyphs carries, space-separated hex.
var GLYPHS = "{glyph_list}"

// True when `text` starts with an icon codepoint (Private Use Area) — i.e. it wants
// Quicktest Glyphs, not the prose face. Only the first character is looked at: an
// icon is one character, and a label that happens to start with one is drawn
// whole in the glyph face, with Qt's per-character fallback for the rest.
function isGlyph(text) {{
    if (!text) return false
    const cp = String(text).codePointAt(0)
    return (cp >= 0xE000 && cp <= 0xF8FF) || (cp >= 0xF0000 && cp <= 0x10FFFD)
}}
"""


def cmd_rewrite(hits, targets: list[str]) -> int:
    """Swap resolved `glyph: "<pua>"` literals for `symbol: "<name>"`, in place.

    Only `glyph:` and `trailingGlyph:` are mechanical. A `text:` site is a
    StyledText that has to become a MaterialIcon — an element-type change — and
    is listed for hand editing instead of being half-rewritten here.
    """
    MECHANICAL = {"glyph", "trailingGlyph"}
    wanted = {Path(t).resolve().relative_to(REPO).as_posix() for t in targets}

    by_file = defaultdict(list)
    for h in hits:
        if h["file"] in wanted:
            by_file[h["file"]].append(h)

    if not by_file:
        print("No glyphs found in the named file(s).")
        return 0

    total, skipped, structural = 0, [], []
    for rel, entries in sorted(by_file.items()):
        path = REPO / rel
        text = path.read_text(encoding="utf-8")
        for h in entries:
            if h["prop"] not in MECHANICAL:
                structural.append(h)
                continue
            if not h["symbol"]:
                skipped.append(h)
                continue
            text = text.replace(h["char"], h["symbol"])
            total += 1
        # Only the property NAME changes once every literal in it has become a word.
        text = re.sub(r"\bglyph(\s*:)", r"symbol\1", text)
        text = re.sub(r"\btrailingGlyph(\s*:)", r"trailingSymbol\1", text)
        path.write_text(text, encoding="utf-8")
        print(f"rewrote {rel}")

    print(f"\n  {total} glyph literal(s) replaced")
    if skipped:
        print(f"  {len(skipped)} left alone (unresolved):")
        for h in skipped:
            print(f"      {h['file']}:{h['line']}  {h['mdi']}")
    if structural:
        print(f"  {len(structural)} need HAND editing (not a string swap — the element "
              f"type changes to MaterialIcon):")
        for h in structural:
            print(f"      {h['file']}:{h['line']}  ({h['prop']})  {h['mdi']}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--report",  action="store_true")
    g.add_argument("--residue", action="store_true")
    g.add_argument("--emit",    action="store_true")
    g.add_argument("--rewrite", nargs="+", metavar="FILE")
    ap.add_argument("--nerd-font", help="override the Nerd Font file")
    ap.add_argument("--symbols-font", help="override the Material Symbols file")
    args = ap.parse_args()

    nerd = Path(args.nerd_font) if args.nerd_font else _fc_match("CodeNewRoman Nerd Font")
    if not nerd:
        print("error: could not locate the Nerd Font (try --nerd-font)", file=sys.stderr)
        return 2

    sym_path = Path(args.symbols_font) if args.symbols_font else _fc_match("Material Symbols Rounded")
    valid = None
    if sym_path and "Symbols" in sym_path.name:
        valid = symbols_ligatures(sym_path)
        if not valid:
            valid = None
    if valid is None:
        # --emit cuts the bundled font OUT of it, so there it is a hard requirement
        # (the AUR ttf-material-symbols-variable-git, or Google's
        # MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf from
        # github.com/google/material-design-icons, via --symbols-font). The report
        # modes still work without it, loudly.
        if args.emit:
            print("error: --emit needs the full Material Symbols Rounded font "
                  "(try --symbols-font)", file=sys.stderr)
            return 2
        print("warning: Material Symbols font not found; proposals will NOT be "
              "validated against it.", file=sys.stderr)

    mdi_names = nerd_font_names(nerd)
    hits = annotate(scan(), mdi_names, valid)

    if args.report:
        return cmd_report(hits)
    if args.residue:
        return cmd_residue(hits)
    if args.emit:
        return cmd_emit(hits, sym_path, nerd)
    return cmd_rewrite(hits, args.rewrite)


if __name__ == "__main__":
    sys.exit(main())
