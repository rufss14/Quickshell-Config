pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import ".."

// ── KeyboardPage — Devices › Keyboard ─────────────────────────────────────────
// The configured xkb layouts and key repeat, applied live through Hyprland.
//
// ── Layouts are a list, not a choice ──────────────────────────────────────────
// kb_layout reads "us,pt" on this machine, and the bar's keyboard pill cycles between
// them. A page where clicking a layout makes it THE layout would quietly delete
// Portuguese the first time you clicked "us" to confirm what you already had. So:
// what you have (removable), and the catalogue you add from.
//
// All state lives in the Keyboard service — including, since the overhaul, the
// physical keyboard, which the service was already reading from `hyprctl -j devices`
// and discarding while this page ran the same query again.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Re-read the device list on open: a keyboard plugged in since startup should show.
    Component.onCompleted: { Keyboard.refresh(); Keyboard.loadCatalogue(); HyprConfig.acquire() }
    Component.onDestruction: HyprConfig.release()

    // Mouse & touchpad live in hardware.lua (HyprConfig): written to disk, applied by
    // the shared HyprApplyBar's reload — the same flow as Desktop › Tuning.
    function ptr(name) { return HyprConfig.pointer[name] ? HyprConfig.pointer[name].value : undefined }
    function setLine(key, type, v) {
        const d = HyprConfig.input[key]
        if (d && d.line) HyprConfig.setValue(d.file, d.line, key, type, v)
    }

    property string search: ""

    // The catalogue stays page-local: nothing else wants every xkb layout in existence,
    // and it's ~250 entries that would otherwise sit in a singleton forever. Read from
    // base.lst rather than `localectl list-x11-keymap-layouts`, which prints only codes —
    // "af / al / am" is only usable by someone who already knows the answer.
    readonly property var catalogue: Keyboard.catalogue   // [{ code, name }], sorted by name
    readonly property var nameOf: Keyboard.nameOf         // code → name, for the chips

    readonly property var filtered: {
        const s = root.search.trim().toLowerCase()
        const pool = root.catalogue.filter(l => Keyboard.layouts.indexOf(l.code) === -1)
        return s === "" ? pool
             : pool.filter(l => l.code.toLowerCase().includes(s)
                             || l.name.toLowerCase().includes(s))
    }

    // A fixed window inside the scrolling page — a GridView reports no implicit height.
    readonly property int cellHeight:  34
    readonly property int visibleRows: 7


    // "razer-razer-huntsman-mini" → "Razer Huntsman Mini". Consecutive duplicate words
    // collapsed because vendor prefixes double up in evdev names.
    function prettyName(n) {
        const out = []
        for (const w of String(n).split(/[-_]+/).filter(w => w !== ""))
            if (out.length === 0 || out[out.length - 1].toLowerCase() !== w.toLowerCase())
                out.push(w[0].toUpperCase() + w.slice(1))
        return out.join(" ")
    }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰌌"
        title:     Translation.tr("Keyboard")
        titleTail: Keyboard.layout
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  (Keyboard.layouts.length > 0 ? Keyboard.layouts.join(", ") + "  ·  " : "")
                 + Keyboard.repeatRate + "/s after " + Keyboard.repeatDelay + "ms"


        banner: UndoBar { id: undoBar }

        // ══ Configured ════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰥻"
            title:    Translation.tr("Your layouts")
            subtitle: "Typing in " + Keyboard.layout
            help:     Translation.tr("The bar's keyboard pill cycles these, in this order. To reorder, remove one and add it back — it goes to the end. Applied with hyprctl, so a Hyprland restart brings back what your config says.")
            accent:   Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: Keyboard.layouts

                    Rectangle {
                        id: chip
                        required property string modelData

                        // The last layout can't be removed — Hyprland won't accept a
                        // keyboard with none, and the service refuses it anyway.
                        readonly property bool removable: Keyboard.layouts.length > 1

                        implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: Tokens.pillHeight
                        radius: Tokens.radiusSm
                        color:        Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.40)

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm

                            StyledText {
                                text:  chip.modelData
                                color: Colors.of(QsWindow.window).primary
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                visible: (root.nameOf[chip.modelData] || "") !== ""
                                text: root.nameOf[chip.modelData] || ""
                                variant: "caption"
                                emphasis: "dim"
                            }
                            MaterialIcon {
                                visible: chip.removable
                                glyph:    "󰅖"
                                color:   removeHover.hovered ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                                variant: "caption"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   {
                                    onTapped: {
                                        const code = chip.modelData
                                        Keyboard.removeLayout(code)
                                        // Re-adding puts it at the END of the list, which
                                        // the card already explains — so the undo says so
                                        // rather than pretending the order survived.
                                        undoBar.show("Removed " + code + " — undo adds it back at the end",
                                                     function () { Keyboard.addLayout(code) })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider {}

            // The keyboard these settings actually reach — a line of this card rather
            // than a card of its own.
            RowLayout {
                visible: Keyboard.mainKeyboard !== null
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                MaterialIcon { glyph: "󰌌"; variant: "body"; color: Colors.of(QsWindow.window).primary }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: Keyboard.mainKeyboard ? root.prettyName(Keyboard.mainKeyboard.name) : ""
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        // Keyboard.layout, not the device record's keymap: the layout
                        // follows the live `activelayout` event, the record is a snapshot.
                        text: Keyboard.inputDeviceCount > 1
                               ? (Keyboard.inputDeviceCount - 1) + " other input devices follow these layouts"
                               : "The only keyboard"
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ══ Repeat ════════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰔛"
            title:    Translation.tr("Key repeat")
            help:     Translation.tr("What a held-down key does: how soon it starts repeating, and how fast.")
            accent:   Colors.of(QsWindow.window).primary

            // SliderRow: whole numbers you land on, with a stepper.
            SliderRow {
                label: Translation.tr("Repeat rate")
                labelWidth:  100
                numberWidth: 46
                from:  10
                to:    100
                value: Keyboard.repeatRate
                readout: Keyboard.repeatRate + "/s"
                onCommit: function (v) { Keyboard.setRepeat(Math.round(v), Keyboard.repeatDelay) }
            }
            SliderRow {
                label: Translation.tr("Repeat delay")
                labelWidth:  100
                numberWidth: 46
                from:  150
                to:    1000
                value: Keyboard.repeatDelay
                readout: Keyboard.repeatDelay + "ms"
                onCommit: function (v) { Keyboard.setRepeat(Keyboard.repeatRate, Math.round(v)) }
            }

            // Feel it, don't imagine it: hold a key here and what comes out IS the
            // rate and delay above. Nothing consumes the text.
            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("Hold a key here to feel it")
            }
        }

        // Saved-but-not-applied mouse/touchpad edits (the page's banner is the layout
        // UndoBar, so this sits in the flow, as on Desktop › Window manager).
        HyprApplyBar {}

        // ══ Mouse ═════════════════════════════════════════════════════════════
        Section {
            span:     3
            symbol:   "mouse"
            title:    Translation.tr("Mouse")
            help:     Translation.tr("Applies to every pointer. Saved to hardware.lua; Reload in the bar above applies it.")
            accent:   Colors.of(QsWindow.window).primary

            SliderRow {
                label: Translation.tr("Speed")
                labelWidth: 100
                numberWidth: 52
                from: -1; to: 1; step: 0.05
                value: HyprConfig.input.sensitivity ? Number(HyprConfig.input.sensitivity.value) : 0
                readout: value.toFixed(2)
                help: Translation.tr("Hyprland's sensitivity: 0 is the device's own speed.")
                onCommit: function (v) { root.setLine("sensitivity", "float", Math.round(v * 100) / 100) }
            }
            SettingRow {
                label: Translation.tr("Acceleration")
                help:  Translation.tr("Adaptive speeds up with faster movement; Flat keeps it 1:1 (what most players want).")
                ChipRow {
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "adaptive", label: "Adaptive" }, { value: "flat", label: "Flat" }]
                    current: root.ptr("accel_profile") ?? "adaptive"
                    onPicked: function (v) { HyprConfig.setInput("accel_profile", v) }
                }
            }
            SliderRow {
                label: Translation.tr("Scroll speed")
                labelWidth: 100
                numberWidth: 52
                from: 0.25; to: 3; step: 0.05
                value: root.ptr("mouse_scroll_factor") ?? 1
                readout: value.toFixed(2) + "×"
                onCommit: function (v) { HyprConfig.setInput("mouse_scroll_factor", Math.round(v * 100) / 100) }
            }
            SettingRow {
                label: Translation.tr("Left-handed")
                help:  Translation.tr("Swaps the primary and secondary buttons.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.ptr("left_handed") === true
                    onToggled: HyprConfig.setInput("left_handed", !checked)
                }
            }
        }

        // ══ Touchpad ══════════════════════════════════════════════════════════
        Section {
            span:     3
            symbol:   "laptop"
            title:    Translation.tr("Touchpad")
            help:     Translation.tr("Laptop touchpads. Saved to hardware.lua; Reload in the bar above applies it.")
            accent:   Colors.of(QsWindow.window).primary

            SettingRow {
                label: Translation.tr("Natural scrolling")
                help:  Translation.tr("Content follows your fingers, like a phone.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: HyprConfig.input.natural_scroll ? HyprConfig.input.natural_scroll.value === true : false
                    onToggled: root.setLine("natural_scroll", "bool", !checked)
                }
            }
            SettingRow {
                label: Translation.tr("Tap to click")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.ptr("tap_to_click") !== false
                    onToggled: HyprConfig.setInput("tap_to_click", !checked)
                }
            }
            SettingRow {
                label: Translation.tr("Tap and drag")
                help:  Translation.tr("Tap, then keep the finger down to drag.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.ptr("tap_and_drag") !== false
                    onToggled: HyprConfig.setInput("tap_and_drag", !checked)
                }
            }
            SettingRow {
                label: Translation.tr("Ignore while typing")
                help:  Translation.tr("The touchpad pauses briefly after a key press, so a palm doesn't move the cursor.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.ptr("disable_while_typing") !== false
                    onToggled: HyprConfig.setInput("disable_while_typing", !checked)
                }
            }
            SettingRow {
                label: Translation.tr("Two-finger right-click")
                help:  Translation.tr("Click with two fingers for a right-click and three for a middle-click, instead of by where you press.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.ptr("clickfinger_behavior") === true
                    onToggled: HyprConfig.setInput("clickfinger_behavior", !checked)
                }
            }
            SliderRow {
                label: Translation.tr("Scroll speed")
                labelWidth: 100
                numberWidth: 52
                from: 0.25; to: 3; step: 0.05
                value: root.ptr("touchpad_scroll_factor") ?? 1
                readout: value.toFixed(2) + "×"
                onCommit: function (v) { HyprConfig.setInput("touchpad_scroll_factor", Math.round(v * 100) / 100) }
            }
        }

        // ══ Catalogue ═════════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰜄"
            title:    Translation.tr("Add a layout")
            subtitle: root.catalogue.length + " available"
            accent:   Colors.of(QsWindow.window).primary

            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                placeholder: Translation.tr("Search…")
                onEdited: function (v) { root.search = v }
            }

            // Two columns: ~250 entries in one is a scroll marathon, and the rows are
            // short enough that half the width was empty anyway.
            //
            // Plain Item around the GridView: Scrollbar reparents itself to the
            // flickable's parent and anchors across it, so that parent must not be a
            // Layout (the Section body is one).
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.cellHeight * root.visibleRows

            GridView {
                id: catView
                anchors.fill: parent
                clip: true
                cellWidth: Math.floor(catView.width / 2)
                cellHeight: root.cellHeight
                model: root.filtered
                boundsBehavior: Flickable.StopAtBounds

                delegate: Item {
                    id: layoutCell
                    required property var modelData
                    width:  catView.cellWidth
                    height: catView.cellHeight

                    Rectangle {
                        anchors.fill: parent
                        anchors.rightMargin:  Tokens.spacingSm
                        anchors.bottomMargin: Tokens.borderWidth * 2
                        radius: Tokens.radiusSm
                        color: rowHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin:  Tokens.spacingMd
                            anchors.rightMargin: Tokens.spacingMd
                            spacing: Tokens.spacingSm

                            StyledText {
                                Layout.fillWidth: true
                                text:    layoutCell.modelData.name
                                variant: "body"
                                elide:   Text.ElideRight
                            }
                            StyledText {
                                text:     layoutCell.modelData.code
                                variant:  "caption"
                                emphasis: "dim"
                                font.family: Tokens.fontMono
                            }
                            MaterialIcon {
                                visible: rowHover.hovered
                                glyph:    "󰐕"
                                color:   Colors.of(QsWindow.window).primary
                                variant: "body"
                            }
                        }

                        HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { onTapped: Keyboard.addLayout(layoutCell.modelData.code) }
                    }
                }
            }

            Scrollbar { flickable: catView }
            }
        }
    }
}
