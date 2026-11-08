pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../state"
import "../../../desktop/widgets"
import "../../../desktop/widgets/toggles.js" as Toggles
import "../.."

// ── WidgetsDesktopSection ── part of WidgetsPage.qml; `page` is the WidgetsPage it belongs to. ──
Section {
    id: hero
    required property var page
    span:    3
    visible: page.viewMode === "desktop" && !page.adding
    symbol:  "computer"
    title:   Translation.tr("Your desktop")
    subtitle: page.selected ? (DesktopWidgets.info(page.selected.type)?.label ?? "Widget")
                            : "Click a widget to change it  ·  drag it to move it"
    accent:  Colors.of(QsWindow.window).primary

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: 232
        spacing: Tokens.spacingLg

        // ── The screen, small ─────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: Math.min(400, Math.round(hero.width * 0.5))
            Layout.maximumWidth:   400
            Layout.fillHeight: true
            spacing: Tokens.spacingSm

            DesktopMap {
                id: map
                Layout.fillWidth: true
                Layout.preferredHeight: width * map.sh / map.sw
                screenName: page.mapScreen
                selectedId: page.selectedId
                onPicked: function (id) { page.selectedId = id }

                // Nothing placed on this screen yet.
                StyledText {
                    anchors.centerIn: parent
                    visible: DesktopWidgets.forScreen(page.mapScreen).length === 0
                    text: "Nothing on " + page.mapScreen + " yet"
                    variant: "caption"
                    color: Colors.of(QsWindow.window).fg
                }
            }

            // Which screen, on a multi-monitor setup.
            TabStrip {
                Layout.fillWidth: true
                visible: Quickshell.screens.length > 1
                accent: Colors.of(QsWindow.window).primary
                model: Quickshell.screens.map(s => ({ value: s.name, label: s.name, icon: "monitor" }))
                current: page.mapScreen
                onPicked: function (v) { page.mapScreen = v; page.selectedId = -1; page.layoutScreen = v }
            }
            Item { Layout.fillHeight: true }
        }

        // ── Beside it: the picked widget's settings, or the ones to pick ──
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Nothing picked: the widgets on this screen, as chips.
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: Tokens.spacingMd
                opacity: page.selected ? 0 : 1
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                StyledText {
                    text: Translation.tr("On this screen")
                    variant: "caption"
                    emphasis: "dim"
                }
                ChipRow {
                    Layout.fillHeight: false
                    accent: Colors.of(QsWindow.window).primary
                    model: DesktopWidgets.forScreen(page.mapScreen).map(w => ({
                        value: w.id, label: DesktopWidgets.info(w.type)?.label ?? w.type }))
                    current: page.selectedId
                    onPicked: function (v) { page.selectedId = v }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Pick one here or on the map to change its size and options, or drag it on the map to move it.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            // Picked: name, the things you do TO it, then its settings.
            ColumnLayout {
                id: pickedPane
                anchors.fill: parent
                spacing: Tokens.spacingMd
                opacity: page.selected ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        text: page.selected ? page.selected.screen + " · " + page.selected.size : ""
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                    ChipTray {
                        ChipButton {
                            id: cardScreenBtn
                            visible: Quickshell.screens.length > 1
                            symbol: "monitor"
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: page.openScreenMenu(cardScreenBtn, page.selectedId, page.selected.screen)
                        }
                        ChipButton {
                            symbol: "delete"
                            tint: Colors.of(QsWindow.window).danger
                            onActivated: {
                                const keep = page.selected
                                const name = DesktopWidgets.info(keep.type)?.label ?? keep.type
                                page.selectedId = -1
                                DesktopWidgets.remove(keep.id)
                                page.undoBar.show("Removed " + name,
                                             function () { DesktopWidgets.restoreWidget(keep) })
                            }
                        }
                        ChipButton {
                            symbol: "close"
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: page.selectedId = -1
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: setFlick
                        anchors.fill: parent
                        contentHeight: setCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: setCol
                            width: setFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
                            spacing: Tokens.spacingMd

                // ── Size ──────────────────────────────────────
                TabStrip {
                    Layout.fillWidth: true
                    visible: model.length > 1
                    accent: Colors.of(QsWindow.window).primary
                    model: (page.selected
                        ? (DesktopWidgets.info(page.selected.type)?.sizes ?? [])
                        : []).map(s => ({
                            value: s,
                            label: s.charAt(0).toUpperCase() + s.slice(1) }))
                    current: page.selected ? page.selected.size : ""
                    onPicked: function (v) { DesktopWidgets.setSize(page.selectedId, v) }
                }

                // ── Type-specific ─────────────────────────────
                // Rendered from the selected type rather than
                // always-present-but-disabled: a greyed "Show seconds"
                // under a calendar is noise.

                // Clock
                SettingRow {
                    visible: page.selected && page.selected.type === "clock"
                    label: "24-hour clock"
                    Toggle {
                        accent: Colors.of(QsWindow.window).primary
                        checked: !!page.selected && page.selected.opts.hour24 !== false
                        onToggled: DesktopWidgets.setOpt(page.selectedId, "hour24",
                                    !(page.selected.opts.hour24 !== false))
                    }
                }
                SettingRow {
                    visible: page.selected && page.selected.type === "clock"
                    label: Translation.tr("Show seconds")
                    Toggle {
                        accent: Colors.of(QsWindow.window).primary
                        checked: !!page.selected && page.selected.opts.seconds === true
                        onToggled: DesktopWidgets.setOpt(page.selectedId, "seconds",
                                    !(page.selected.opts.seconds === true))
                    }
                }

                // Timer
                SettingRow {
                    visible: page.selected && page.selected.type === "timer"
                    label: Translation.tr("Stopwatch")
                    Toggle {
                        accent: Colors.of(QsWindow.window).primary
                        checked: !!page.selected && page.selected.opts.stopwatch === true
                        onToggled: DesktopWidgets.setOpt(page.selectedId, "stopwatch",
                                    !(page.selected.opts.stopwatch === true))
                    }
                }

                // Photo frame
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "photo"
                    spacing: Tokens.spacingSm

                    readonly property string src:
                        page.selected ? (page.selected.opts.source ?? "library") : "library"

                    // What this frame shows. Each frame has its own (several can be placed).
                    StyledText { text: "Shows"; variant: "caption"; emphasis: "dim" }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "library", label: "Wallpapers"  },
                            { value: "folder",  label: "A folder"    },
                            { value: "image",   label: "One picture" }
                        ]
                        current: parent.src
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "source", v) }
                    }
                    // The folder or picture, and the button that opens the browser.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: parent.src !== "library"
                        spacing: Tokens.spacingSm
                        readonly property string stored: !page.selected ? ""
                            : parent.src === "folder" ? (page.selected.opts.folder ?? "")
                            : (page.selected.opts.image ?? "")
                        StyledText {
                            Layout.fillWidth: true
                            text: parent.stored !== "" ? parent.stored
                                : parent.parent.src === "folder" ? "No folder yet" : "No picture yet"
                            variant: "caption"
                            emphasis: parent.stored !== "" ? "normal" : "dim"
                            elide: Text.ElideMiddle
                        }
                        PanelButton {
                            capsule: true
                            variant: "ghost"
                            symbol: parent.parent.src === "folder" ? "folder" : "image"
                            label: Translation.tr("Choose…")
                            onActivated: {
                                page.photoPicker.folders = parent.parent.src === "folder"
                                page.photoPicker.title = page.photoPicker.folders ? "Choose a folder" : "Choose a picture"
                                page.photoPicker.current = DesktopWidgets.expandPath(parent.stored)
                                page.photoPicker.show(DesktopWidgets.expandPath(parent.stored))
                            }
                        }
                    }
                    // The frame's outline: the tile's own rounded rectangle, or a shape.
                    StyledText { text: "Frame"; variant: "caption"; emphasis: "dim" }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "rect",     label: "Rounded"  },
                            { value: "cookie9",  label: "Cookie"   },
                            { value: "clover",   label: "Clover"   },
                            { value: "sunny",    label: "Sunny"    },
                            { value: "squircle", label: "Squircle" },
                            { value: "circle",   label: "Circle"   },
                            { value: "burst",    label: "Burst"    }
                        ]
                        current: page.selected ? (page.selected.opts.shape ?? "rect") : "rect"
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "shape", v) }
                    }

                    Fader {
                        label: Translation.tr("Change every")
                        accent: Colors.of(QsWindow.window).primary
                        from: 10; to: 300; step: 5
                        value: page.selected ? (page.selected.opts.seconds ?? 30) : 30
                        readout: (page.selected ? (page.selected.opts.seconds ?? 30) : 30) + "s"
                        onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "seconds", Math.round(v)) }
                    }
                    SettingRow {
                        label: Translation.tr("Slow zoom")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.pan !== false
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "pan",
                                        !(page.selected.opts.pan !== false))
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Shuffle")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.shuffle === true
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "shuffle",
                                        !(page.selected.opts.shuffle === true))
                        }
                    }

                    StyledText { text: "Appearance"; variant: "caption"; emphasis: "dim"; Layout.topMargin: Tokens.spacingSm }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "solid",       label: "Solid"       },
                            { value: "transparent", label: "Transparent" },
                            { value: "glass",       label: "Glass"       },
                            { value: "blur",        label: "Blur"        }
                        ]
                        current: page.selected ? (page.selected.opts.bgMode ?? "solid") : "solid"
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "bgMode", v) }
                    }
                    SettingRow {
                        label: Translation.tr("Background opacity")
                        Fader {
                            from: 0; to: 1; step: 0.05
                            value: page.selected ? (page.selected.opts.bgOpacity ?? 1.0) : 1.0
                            readout: Math.round((page.selected ? (page.selected.opts.bgOpacity ?? 1.0) : 1.0) * 100) + "%"
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "bgOpacity", v) }
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Shape rotation")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.shapeRot === true
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "shapeRot",
                                        !(page.selected.opts.shapeRot === true))
                        }
                    }

                    StyledText { text: "Image"; variant: "caption"; emphasis: "dim"; Layout.topMargin: Tokens.spacingSm }
                    SettingRow {
                        label: Translation.tr("Brightness")
                        Fader {
                            from: 0.5; to: 1.5; step: 0.05
                            value: page.selected ? (page.selected.opts.brightness ?? 1.0) : 1.0
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "brightness", v) }
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Saturation")
                        Fader {
                            from: 0; to: 2; step: 0.05
                            value: page.selected ? (page.selected.opts.saturation ?? 1.0) : 1.0
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "saturation", v) }
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Blur")
                        Fader {
                            from: 0; to: 1; step: 0.05
                            value: page.selected ? (page.selected.opts.imgBlur ?? 0) : 0
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "imgBlur", v) }
                        }
                    }

                    StyledText { text: "Motion"; variant: "caption"; emphasis: "dim"; Layout.topMargin: Tokens.spacingSm }
                    SettingRow {
                        label: Translation.tr("Pan strength")
                        Fader {
                            from: 0.2; to: 1.5; step: 0.1
                            value: page.selected ? (page.selected.opts.panStr ?? 1.0) : 1.0
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "panStr", v) }
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Fade speed")
                        Fader {
                            from: 100; to: 1000; step: 50
                            value: page.selected ? (page.selected.opts.fadeMs ?? 300) : 300
                            readout: (page.selected ? (page.selected.opts.fadeMs ?? 300) : 300) + "ms"
                            onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "fadeMs", Math.round(v)) }
                        }
                    }
                }

                // Quick toggles: which switches, in this order (up to eight; small
                // and medium show the first four).
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "toggles"
                    spacing: Tokens.spacingXs

                    readonly property var picked: page.selected ? (page.selected.opts.toggles ?? []) : []

                    StyledText { text: "Toggles (the first four show at small and medium)"; variant: "caption"; emphasis: "dim" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: Toggles.ORDER
                            ToggleChip {
                                required property string modelData
                                symbol: Toggles.TABLE[modelData].on
                                label: Toggles.TABLE[modelData].label
                                active: parent.parent.picked.indexOf(modelData) >= 0
                                onToggled: {
                                    const cur = parent.parent.picked
                                    DesktopWidgets.setOpt(page.selectedId, "toggles",
                                        active ? cur.filter(t => t !== modelData)
                                               : cur.concat(modelData).slice(0, 8))
                                }
                            }
                        }
                    }
                }

                // Smart stack: its cards, whether it surfaces what matters, its turn.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "stack"
                    spacing: Tokens.spacingSm

                    readonly property var cards: page.selected ? (page.selected.opts.cards ?? []) : []
                    // What can be a card at this size: not typed widgets (a card has
                    // no record to save into), not another stack.
                    readonly property var candidates: !page.selected ? [] : DesktopWidgets.catalogue
                        .filter(c => c.type !== "stack" && c.editable !== true
                                     && (c.sizes ?? []).indexOf(page.selected.size) >= 0)

                    StyledText { text: "Cards, in order"; variant: "caption"; emphasis: "dim" }
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: parent.parent.candidates
                            ToggleChip {
                                required property var modelData
                                glyph: modelData.glyph
                                label: modelData.label
                                active: parent.parent.cards.indexOf(modelData.type) >= 0
                                onToggled: {
                                    const cur = parent.parent.cards
                                    DesktopWidgets.setOpt(page.selectedId, "cards",
                                        active ? cur.filter(t => t !== modelData.type)
                                               : cur.concat(modelData.type))
                                }
                            }
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Bring forward what matters")
                        detail: Translation.tr("A running timer, or the music while something plays")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.smart !== false
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "smart",
                                        !(page.selected.opts.smart !== false))
                        }
                    }
                    Fader {
                        label: Translation.tr("Turn on its own every")
                        accent: Colors.of(QsWindow.window).primary
                        from: 0; to: 120; step: 5
                        value: page.selected ? (page.selected.opts.rotate ?? 0) : 0
                        readout: (page.selected ? (page.selected.opts.rotate ?? 0) : 0) === 0
                                 ? "Off" : (page.selected.opts.rotate ?? 0) + "s"
                        onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "rotate", Math.round(v)) }
                    }
                }

                // Disk
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "disk"
                    spacing: Tokens.spacingXs

                    StyledText { text: "Mount point"; variant: "caption"; emphasis: "dim" }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        placeholder: "/"
                        seed: page.selected ? (page.selected.opts.mount ?? "/") : "/"
                        onCommitted: function (t) {
                            DesktopWidgets.setOpt(page.selectedId, "mount",
                                t.trim() === "" ? "/" : t.trim())
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A path from System › Storage — “/” or “/home”.")
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                // Countdown
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "countdown"
                    spacing: Tokens.spacingXs

                    StyledText { text: "What for"; variant: "caption"; emphasis: "dim" }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        Layout.fillWidth: true
                        placeholder: Translation.tr("Holiday")
                        seed: page.selected ? (page.selected.opts.label ?? "") : ""
                        onCommitted: function (t) {
                            DesktopWidgets.setOpt(page.selectedId, "label", t.trim())
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingXs
                        text: "Date"; variant: "caption"; emphasis: "dim"
                    }
                    InputField {
                        cornerRadius: implicitHeight / 2
                        id: cdDate
                        Layout.fillWidth: true
                        placeholder: "2026-12-25"
                        seed: page.selected ? (page.selected.opts.date ?? "") : ""
                        readonly property bool valid:
                            cdDate.text === "" || /^\d{4}-\d{2}-\d{2}$/.test(cdDate.text)
                        invalid: !cdDate.valid
                        onCommitted: function (t) {
                            if (/^\d{4}-\d{2}-\d{2}$/.test(t.trim()) || t.trim() === "")
                                DesktopWidgets.setOpt(page.selectedId, "date", t.trim())
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Year-month-day, like 2026-12-25.")
                        variant: "caption"
                        color: cdDate.valid ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).danger
                        wrapMode: Text.WordWrap
                    }
                }

                // World clock
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "worldclock"
                    spacing: Tokens.spacingXs

                    SettingRow {
                        label: "24-hour clock"
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.hour24 !== false
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "hour24",
                                        !(page.selected.opts.hour24 !== false))
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingXs
                        text: "Cities"; variant: "caption"; emphasis: "dim"
                    }
                    Repeater {
                        model: page.selected && page.selected.type === "worldclock"
                               ? (page.selected.opts.zones ?? []) : []
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
                                    DesktopWidgets.setZone(page.selectedId, zoneEdit.index, "label", t.trim())
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
                                        DesktopWidgets.setZone(page.selectedId, zoneEdit.index, "offset", n)
                                }
                            }
                            PanelButton {
                                capsule: true
                                variant: "ghost"
                                symbol: "close"
                                onActivated: DesktopWidgets.removeZone(page.selectedId, zoneEdit.index)
                            }
                        }
                    }
                    PanelButton {
                        capsule: true
                        Layout.fillWidth: true
                        variant: "ghost"
                        symbol: "add"
                        label: Translation.tr("Add city")
                        onActivated: DesktopWidgets.addZone(page.selectedId, "New city", 0)
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Offsets are hours from UTC — one crossing a ")
                            + "daylight-saving change needs editing twice a year."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                // System monitor
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "sysmon"
                    spacing: Tokens.spacingXs

                    StyledText { text: "Default metric"; variant: "caption"; emphasis: "dim" }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "cpu",    label: "CPU"    },
                            { value: "memory", label: "Memory" },
                            { value: "temp",   label: "Temp"   }
                        ]
                        current: page.selected ? (page.selected.opts.metric ?? "cpu") : "cpu"
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "metric", v) }
                    }
                }

                // Visualizer
                ColumnLayout {
                    id: vizOpts
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected && page.selected.type === "visualizer"
                    spacing: Tokens.spacingXs

                    // The widget's own default: a cookie at small, bars wider.
                    readonly property string vizStyle:
                        page.selected ? (page.selected.opts.style
                                         ?? (page.selected.size === "small" ? "cookie" : "bars")) : "bars"
                    // "Grow from centre" only means anything for bars and
                    // wave — dots is already its own shape.
                    readonly property bool showCenter:
                        vizOpts.vizStyle === "bars" || vizOpts.vizStyle === "wave"

                    StyledText { text: "Style"; variant: "caption"; emphasis: "dim" }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "cookie", label: "Cookie" },
                            { value: "bars", label: "Bars"     },
                            { value: "wave", label: "Waveform" },
                            { value: "dots", label: "Dots"     }
                        ]
                        current: vizOpts.vizStyle
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "style", v) }
                    }

                    SettingRow {
                        label: Translation.tr("Mirrored spectrum")
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && (page.selected.opts.mirrored ?? true)
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "mirrored",
                                        !(page.selected.opts.mirrored ?? true))
                        }
                    }
                    SettingRow {
                        visible: vizOpts.showCenter
                        label: Translation.tr("Grow from centre")
                        detail: Translation.tr("Bars extend both ways from the middle, like the bar pill")
                        wrapDetail: true
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && page.selected.opts.centered === true
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "centered",
                                        !(page.selected.opts.centered === true))
                        }
                    }
                }

                // Clipboard
                Fader {
                    visible: page.selected && page.selected.type === "clipboard"
                    label: Translation.tr("Rows to show")
                    accent: Colors.of(QsWindow.window).primary
                    from: 2; to: 12
                    value: page.selected
                           ? (page.selected.opts.rows ?? (page.selected.size === "large" ? 8 : 4))
                           : 4
                    readout: (page.selected
                              ? (page.selected.opts.rows ?? (page.selected.size === "large" ? 8 : 4))
                              : 4).toString()
                    onCommit: function (v) { DesktopWidgets.setOpt(page.selectedId, "rows", Math.round(v)) }
                }

                // Now playing / Lyrics — pin a player
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: page.selected
                             && (page.selected.type === "nowplaying"
                                 || page.selected.type === "lyrics")
                    spacing: Tokens.spacingXs

                    StyledText { text: "Pin a player"; variant: "caption"; emphasis: "dim" }
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
                        model: [{ value: "", label: "Auto" }].concat(
                            Mpris.players.values.map(p => ({ value: p.identity, label: p.identity })))
                        current: page.selected ? (page.selected.opts.player ?? "") : ""
                        onPicked: function (v) {
                            DesktopWidgets.setOpt(page.selectedId, "player", v === "" ? undefined : v)
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingXs
                        text: "Colours"; variant: "caption"; emphasis: "dim"
                    }
                    ChipRow {
                        Layout.fillHeight: false
                        accent: Colors.of(QsWindow.window).primary
                        model: [
                            { value: "album",     label: "Album"     },
                            { value: "wallpaper", label: "Wallpaper" }
                        ]
                        current: page.selected
                            ? ((page.selected.opts.colors ?? "album") === "wallpaper" ? "wallpaper" : "album")
                            : "album"
                        onPicked: function (v) { DesktopWidgets.setOpt(page.selectedId, "colors", v) }
                    }
                    // Lyrics only: the card's two optional dressings.
                    SettingRow {
                        visible: !!page.selected && page.selected.type === "lyrics"
                        label: Translation.tr("Track card")
                        detail: Translation.tr("What's playing, shown when a song starts and when you hover; plus how far through it is")
                        wrapDetail: true
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && (page.selected.opts.track ?? true)
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "track",
                                        !(page.selected.opts.track ?? true))
                        }
                    }
                    SettingRow {
                        visible: !!page.selected && page.selected.type === "lyrics"
                        label: Translation.tr("Soft edges")
                        detail: Translation.tr("Lines fade out at the top and bottom instead of being cut")
                        wrapDetail: true
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && (page.selected.opts.fade ?? true)
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "fade",
                                        !(page.selected.opts.fade ?? true))
                        }
                    }
                    SettingRow {
                        label: Translation.tr("Tile frame")
                        detail: Translation.tr("The widget's own fill and outline, around the card")
                        wrapDetail: true
                        Toggle {
                            accent: Colors.of(QsWindow.window).primary
                            checked: !!page.selected && !DesktopWidgets.isBare(page.selected)
                            onToggled: DesktopWidgets.setOpt(page.selectedId, "bare",
                                        !DesktopWidgets.isBare(page.selected))
                        }
                    }
                }
                        }
                    }
                    Scrollbar { flickable: setFlick }
                }
            }
        }
    }
}
