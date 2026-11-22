pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../desktop/widgets"
import "../../../desktop/widgets/toggles.js" as Toggles
import "../.."

// ── WidgetsOptionsSection ── the picked widget's own options, every type but the photo frame.
// Rendered from the picked type rather than always present and disabled: a greyed "Show seconds"
// under a calendar is noise. Each option is a direct child gated on the type, so one row is one segment.
// The photo frame has enough of its own to be two groups (WidgetsPhotoSection, WidgetsPhotoLookSection).
// Part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to.
Section {
    id: opts
    required property var page

    readonly property var    sel: page.selected
    readonly property string kind: opts.sel ? opts.sel.type : ""
    readonly property bool   hasOptions: ["clock", "timer", "toggles", "stack", "disk", "countdown",
                                          "worldclock", "sysmon", "gauge", "visualizer", "clipboard",
                                          "nowplaying", "lyrics"].indexOf(opts.kind) >= 0

    // Two or three exclusive values in a row's control slot (a slot is a plain Item: size by implicitWidth).
    readonly property int choiceWidth: Tokens.fieldHeight * 10

    // A boolean option: `defOn` is what an unset option means (default-on options read `!== false`).
    function isOn(key, defOn) {
        return !!opts.sel && (defOn ? opts.sel.opts[key] !== false : opts.sel.opts[key] === true)
    }
    function flip(key, defOn) {
        DesktopWidgets.setOpt(opts.page.selectedId, key, !opts.isOn(key, defOn))
    }
    function val(key, fallback) { return opts.sel ? (opts.sel.opts[key] ?? fallback) : fallback }
    function put(key, v) { DesktopWidgets.setOpt(opts.page.selectedId, key, v) }

    // What a visualizer draws when nothing is chosen: a cookie at small, bars wider.
    readonly property string vizStyle:
        opts.sel ? (opts.sel.opts.style ?? (opts.sel.size === "small" ? "cookie" : "bars")) : "bars"
    // "Grow from centre" only means anything for bars and wave: dots is already its own shape.
    readonly property bool vizCenter: opts.vizStyle === "bars" || opts.vizStyle === "wave"

    grouped:  true
    visible:  opts.hasOptions
    symbol:   "tune"
    title:    Translation.tr("Options")
    subtitle: opts.sel ? (DesktopWidgets.info(opts.sel.type)?.label ?? "") : ""

    // ── Clock ───────────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "clock"
        rowTap: true
        label: Translation.tr("24-hour clock")
        onTapped: opts.flip("hour24", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("hour24", true); onToggled: opts.flip("hour24", true) }
    }
    SettingRow {
        visible: opts.kind === "clock"
        rowTap: true
        label: Translation.tr("Show seconds")
        onTapped: opts.flip("seconds", false)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("seconds", false); onToggled: opts.flip("seconds", false) }
    }

    // ── Timer ───────────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "timer"
        rowTap: true
        label: Translation.tr("Stopwatch")
        onTapped: opts.flip("stopwatch", false)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("stopwatch", false); onToggled: opts.flip("stopwatch", false) }
    }

    // ── Quick toggles ───────────────────────────────────────────────────────
    // Which switches, in this order (up to eight; small and medium show the first four).
    ColumnLayout {
        id: togglesPick
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: opts.kind === "toggles"
        spacing: Tokens.spacingSm

        readonly property var picked: opts.val("toggles", [])

        StyledText {
            text: Translation.tr("Toggles (the first four show at small and medium)")
            variant: "caption"
            emphasis: "dim"
        }
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacingXs
            Repeater {
                model: Toggles.ORDER
                ToggleChip {
                    required property string modelData
                    symbol: Toggles.TABLE[modelData].on
                    label: Toggles.TABLE[modelData].label
                    active: togglesPick.picked.indexOf(modelData) >= 0
                    onToggled: {
                        const cur = togglesPick.picked
                        opts.put("toggles", active ? cur.filter(t => t !== modelData)
                                                   : cur.concat(modelData).slice(0, 8))
                    }
                }
            }
        }
    }

    // ── Smart stack ─────────────────────────────────────────────────────────
    // Its cards, whether it surfaces what matters, its turn.
    ColumnLayout {
        id: stackPick
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: opts.kind === "stack"
        spacing: Tokens.spacingSm

        readonly property var cards: opts.val("cards", [])
        // What can be a card at this size: not typed widgets (a card has no record to save into), not another stack.
        readonly property var candidates: !opts.sel ? [] : DesktopWidgets.catalogue
            .filter(c => c.type !== "stack" && c.editable !== true
                         && (c.sizes ?? []).indexOf(opts.sel.size) >= 0)

        StyledText { text: Translation.tr("Cards, in order"); variant: "caption"; emphasis: "dim" }
        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacingXs
            Repeater {
                model: stackPick.candidates
                ToggleChip {
                    required property var modelData
                    glyph: modelData.glyph
                    label: modelData.label
                    active: stackPick.cards.indexOf(modelData.type) >= 0
                    onToggled: {
                        const cur = stackPick.cards
                        opts.put("cards", active ? cur.filter(t => t !== modelData.type)
                                                 : cur.concat(modelData.type))
                    }
                }
            }
        }
    }
    SettingRow {
        visible: opts.kind === "stack"
        rowTap: true
        label: Translation.tr("Bring forward what matters")
        detail: Translation.tr("A running timer, or the music while something plays")
        onTapped: opts.flip("smart", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("smart", true); onToggled: opts.flip("smart", true) }
    }
    Fader {
        visible: opts.kind === "stack"
        label: Translation.tr("Turn on its own every")
        accent: Colors.of(QsWindow.window).primary
        from: 0; to: 120; step: 5
        value: opts.val("rotate", 0)
        readout: opts.val("rotate", 0) === 0 ? Translation.tr("Off") : opts.val("rotate", 0) + "s"
        onCommit: function (v) { opts.put("rotate", Math.round(v)) }
    }

    // ── Disk ────────────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "disk"
        label: Translation.tr("Mount point")
        detail: Translation.tr("A path from System › Storage: “/” or “/home”.")

        InputField {
            cornerRadius: implicitHeight / 2
            width: Tokens.fieldHeight * 6
            placeholder: "/"
            seed: opts.val("mount", "/")
            onCommitted: function (t) { opts.put("mount", t.trim() === "" ? "/" : t.trim()) }
        }
    }

    // ── Countdown ───────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "countdown"
        label: Translation.tr("What for")

        InputField {
            cornerRadius: implicitHeight / 2
            width: Tokens.fieldHeight * 6
            placeholder: Translation.tr("Holiday")
            seed: opts.val("label", "")
            onCommitted: function (t) { opts.put("label", t.trim()) }
        }
    }
    SettingRow {
        visible: opts.kind === "countdown"
        label: Translation.tr("Date")
        detail: cdDate.valid ? Translation.tr("Year-month-day, like 2026-12-25.")
                             : Translation.tr("Not a date yet. Year-month-day, like 2026-12-25.")

        InputField {
            id: cdDate
            cornerRadius: implicitHeight / 2
            width: Tokens.fieldHeight * 6
            placeholder: "2026-12-25"
            seed: opts.val("date", "")
            readonly property bool valid: cdDate.text === "" || /^\d{4}-\d{2}-\d{2}$/.test(cdDate.text)
            invalid: !cdDate.valid
            onCommitted: function (t) {
                if (/^\d{4}-\d{2}-\d{2}$/.test(t.trim()) || t.trim() === "") opts.put("date", t.trim())
            }
        }
    }

    // ── World clock ─────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "worldclock"
        rowTap: true
        label: Translation.tr("24-hour clock")
        onTapped: opts.flip("hour24", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("hour24", true); onToggled: opts.flip("hour24", true) }
    }
    SettingRow {
        visible: opts.kind === "worldclock"
        label: Translation.tr("Cities")
        detail: Translation.tr("Offsets are hours from UTC. A city that changes for daylight saving needs editing twice a year.")
        wrapDetail: true

        PanelButton {
            capsule: true
            variant: "ghost"
            symbol: "add"
            label: Translation.tr("Add city")
            onActivated: DesktopWidgets.addZone(opts.page.selectedId, "New city", 0)
        }
    }
    Repeater {
        model: opts.kind === "worldclock" ? opts.val("zones", []) : []
        RowLayout {
            id: zoneEdit
            required property int index
            required property var modelData
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("City")
                seed: zoneEdit.modelData.label ?? ""
                onCommitted: function (t) {
                    DesktopWidgets.setZone(opts.page.selectedId, zoneEdit.index, "label", t.trim())
                }
            }
            InputField {
                cornerRadius: implicitHeight / 2
                Layout.preferredWidth: 58
                placeholder: "+0"
                seed: {
                    const o = zoneEdit.modelData.offset ?? 0
                    return (o >= 0 ? "+" : "") + o
                }
                // Validated at the boundary: real UTC offsets only.
                onCommitted: function (t) {
                    const n = parseFloat(t)
                    if (!isNaN(n) && n >= -12 && n <= 14)
                        DesktopWidgets.setZone(opts.page.selectedId, zoneEdit.index, "offset", n)
                }
            }
            PanelButton {
                capsule: true
                variant: "ghost"
                symbol: "close"
                onActivated: DesktopWidgets.removeZone(opts.page.selectedId, zoneEdit.index)
            }
        }
    }

    // ── System monitor ──────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "sysmon"
        label: Translation.tr("Default metric")

        TabStrip {
            connected: true
            implicitWidth: opts.choiceWidth
            model: [
                { value: "cpu",    label: Translation.tr("CPU")    },
                { value: "memory", label: Translation.tr("Memory") },
                { value: "temp",   label: Translation.tr("Temp")   }
            ]
            current: opts.val("metric", "cpu")
            onPicked: function (v) { opts.put("metric", v) }
        }
    }

    // ── Gauge ───────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: opts.kind === "gauge"
        spacing: Tokens.spacingSm

        StyledText { text: Translation.tr("Reads"); variant: "caption"; emphasis: "dim" }
        ChipRow {
            Layout.fillHeight: false
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "cpu",     label: Translation.tr("CPU")     },
                { value: "memory",  label: Translation.tr("Memory")  },
                { value: "gpu",     label: Translation.tr("GPU")     },
                { value: "temp",    label: Translation.tr("Temp")    },
                { value: "battery", label: Translation.tr("Battery") }
            ]
            current: opts.val("metric", "cpu")
            onPicked: function (v) { opts.put("metric", v) }
        }
    }
    SettingRow {
        visible: opts.kind === "gauge"
        label: Translation.tr("Look")

        TabStrip {
            connected: true
            implicitWidth: opts.choiceWidth
            model: [
                { value: "water", label: Translation.tr("Water") },
                { value: "ring",  label: Translation.tr("Ring")  }
            ]
            current: opts.val("style", "water")
            onPicked: function (v) { opts.put("style", v) }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: opts.kind === "gauge"
        spacing: Tokens.spacingSm

        StyledText { text: Translation.tr("Shape"); variant: "caption"; emphasis: "dim" }
        ChipRow {
            Layout.fillHeight: false
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "pentagon", label: Translation.tr("Pentagon") },
                { value: "cookie9",  label: Translation.tr("Cookie")   },
                { value: "sunny",    label: Translation.tr("Sunny")    },
                { value: "clover",   label: Translation.tr("Clover")   },
                { value: "squircle", label: Translation.tr("Squircle") },
                { value: "hexagon",  label: Translation.tr("Hexagon")  },
                { value: "circle",   label: Translation.tr("Circle")   }
            ]
            current: opts.val("shape", "pentagon")
            onPicked: function (v) { opts.put("shape", v) }
        }
    }

    // ── Visualizer ──────────────────────────────────────────────────────────
    SettingRow {
        visible: opts.kind === "visualizer"
        label: Translation.tr("Style")

        TabStrip {
            connected: true
            implicitWidth: opts.choiceWidth * 1.6
            model: [
                { value: "cookie", label: Translation.tr("Cookie")   },
                { value: "bars",   label: Translation.tr("Bars")     },
                { value: "wave",   label: Translation.tr("Waveform") },
                { value: "dots",   label: Translation.tr("Dots")     }
            ]
            current: opts.vizStyle
            onPicked: function (v) { opts.put("style", v) }
        }
    }
    SettingRow {
        visible: opts.kind === "visualizer"
        rowTap: true
        label: Translation.tr("Mirrored spectrum")
        onTapped: opts.flip("mirrored", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("mirrored", true); onToggled: opts.flip("mirrored", true) }
    }
    SettingRow {
        visible: opts.kind === "visualizer" && opts.vizCenter
        rowTap: true
        label: Translation.tr("Grow from centre")
        detail: Translation.tr("Bars extend both ways from the middle, like the bar pill")
        wrapDetail: true
        onTapped: opts.flip("centered", false)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("centered", false); onToggled: opts.flip("centered", false) }
    }

    // ── Clipboard ───────────────────────────────────────────────────────────
    Fader {
        visible: opts.kind === "clipboard"
        label: Translation.tr("Rows to show")
        accent: Colors.of(QsWindow.window).primary
        from: 2; to: 12
        value: opts.sel ? (opts.sel.opts.rows ?? (opts.sel.size === "large" ? 8 : 4)) : 4
        readout: (opts.sel ? (opts.sel.opts.rows ?? (opts.sel.size === "large" ? 8 : 4)) : 4).toString()
        onCommit: function (v) { opts.put("rows", Math.round(v)) }
    }

    // ── Now playing and Lyrics ──────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: opts.kind === "nowplaying" || opts.kind === "lyrics"
        spacing: Tokens.spacingSm

        StyledText { text: Translation.tr("Pin a player"); variant: "caption"; emphasis: "dim" }
        StyledText {
            Layout.fillWidth: true
            visible: Mpris.players.values.length === 0
            text: Translation.tr("Nothing is playing, so there's nothing to pin to.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
        ChipRow {
            Layout.fillHeight: false
            visible: Mpris.players.values.length > 0
            accent: Colors.of(QsWindow.window).primary
            model: [{ value: "", label: Translation.tr("Auto") }].concat(
                Mpris.players.values.map(p => ({ value: p.identity, label: p.identity })))
            current: opts.val("player", "")
            onPicked: function (v) { opts.put("player", v === "" ? undefined : v) }
        }
    }
    SettingRow {
        visible: opts.kind === "nowplaying" || opts.kind === "lyrics"
        label: Translation.tr("Colours")

        TabStrip {
            connected: true
            implicitWidth: opts.choiceWidth
            model: [
                { value: "album",     label: Translation.tr("Album")     },
                { value: "wallpaper", label: Translation.tr("Wallpaper") }
            ]
            current: opts.val("colors", "album") === "wallpaper" ? "wallpaper" : "album"
            onPicked: function (v) { opts.put("colors", v) }
        }
    }
    // Lyrics only: the card's two optional dressings.
    SettingRow {
        visible: opts.kind === "lyrics"
        rowTap: true
        label: Translation.tr("Track card")
        detail: Translation.tr("What's playing, shown when a song starts and when you hover; plus how far through it is")
        wrapDetail: true
        onTapped: opts.flip("track", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("track", true); onToggled: opts.flip("track", true) }
    }
    SettingRow {
        visible: opts.kind === "lyrics"
        rowTap: true
        label: Translation.tr("Soft edges")
        detail: Translation.tr("Lines fade out at the top and bottom instead of being cut")
        wrapDetail: true
        onTapped: opts.flip("fade", true)
        Toggle { accent: Colors.of(QsWindow.window).primary; checked: opts.isOn("fade", true); onToggled: opts.flip("fade", true) }
    }
    SettingRow {
        visible: opts.kind === "nowplaying" || opts.kind === "lyrics"
        rowTap: true
        label: Translation.tr("Tile frame")
        detail: Translation.tr("The widget's own fill and outline, around the card")
        wrapDetail: true
        onTapped: opts.put("bare", !DesktopWidgets.isBare(opts.sel))
        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: !!opts.sel && !DesktopWidgets.isBare(opts.sel)
            onToggled: opts.put("bare", !DesktopWidgets.isBare(opts.sel))
        }
    }
}
