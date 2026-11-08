import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── BarIconPill ───────────────────────────────────────────────────────────────
// A bar module that is just an icon and a click: the shape/mode toggles, palette,
// wallpaper, notifications, idle, night light, gamemode, overview, settings.
//
// ── Why it exists ─────────────────────────────────────────────────────────────
// Every one of those was an inline `IconButton` in Bar.qml's module registry, and
// every one of them repeated the same four lines — `container: false`,
// `squareMode: Config.barShape`, `spacing: Config.groupSpacing(id)`, and the
// `Config.moduleAccent(id, Colors.primary)` lookup — under a copy of the same
// four-line comment explaining the first of them. Ten copies of a paragraph is a
// paragraph nobody updates.
//
// What's left at each call site is the part that is genuinely per-module: the id,
// the glyph, what `active` means, and what a click does.
//
// ── One id, not one lookup per property ───────────────────────────────────────
// `moduleId` is the id as it appears in `Config.layout`, and it is what the two
// per-module settings are keyed on. Passing it once means a new per-module
// preference lands in this file and every icon module has it — rather than being
// retrofitted into ten call sites, which is exactly how `groupSpacing` ended up
// honoured by seven modules and silently ignored by the rest.
//
// ── Don't redeclare. Assign. ──────────────────────────────────────────────────
// `accent`, `squareMode`, `container` and `spacing` are all IconButton's own.
// Declaring any of them here would shadow the base property and then be assigned
// too — `Property value set multiple times`, a hard load failure that cascades
// all the way to a bar that doesn't exist. `PrivacyPill` paid for that one and
// carries the note. `moduleId` and `baseAccent` are new names, and
// that is the whole reason they are safe.
// ─────────────────────────────────────────────────────────────────────────────
IconButton {
    id: root

    // The module's id in Config.layout ("palette", "idle", "privacy", …).
    property string moduleId: ""

    // The accent this module wears until the user recolours it in the module
    // inspector. `primary` covers every icon module in the bar; the pills that
    // subclass this for a different role (none do today) set their own, which is
    // where that knowledge belongs — Bar.qml was passing it in for a widget that
    // already knew the answer.
    property color baseAccent: Colors.of(QsWindow.window).primary

    accent:     Config.moduleAccent(root.moduleId, root.baseAccent)
    squareMode: Config.barShape

    // No pill of its own: the enclosing BarGroup already draws one around every
    // module in it, so a second box here just doubles the outline. See BarGroup.qml
    // and IconButton.container.
    container:  false

    // The group's spacing override (module inspector). -1 is Config's "unset"
    // sentinel and leaves IconButton's own padding alone, so an untouched config
    // is unchanged — see IconButton.spacing.
    spacing:    Config.groupSpacing(root.moduleId)
}
