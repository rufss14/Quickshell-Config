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
    function setLine(key, type, v) { HyprConfig.setInputLine(key, type, v) }
    // A switch's state with the default Hyprland applies while the key is absent from the file.
    function flag(name, dflt) { return dflt ? root.ptr(name) !== false : root.ptr(name) === true }
    function toggle(name, dflt) { HyprConfig.setInput(name, !root.flag(name, dflt)) }
    // Natural scrolling as it is in effect: the touchpad table's own key, or, where a config
    // sets it only at the top of `input = {}`, that one (Hyprland applies it to touchpads too).
    readonly property bool naturalScroll: {
        const p = HyprConfig.pointer.touchpad_natural_scroll
        if (p && p.present) return p.value === true
        const g = HyprConfig.input.natural_scroll
        return !!g && g.value === true
    }

    // A control for a line the user's hardware.lua doesn't have is disabled with a
    // reason, not left to do nothing: the by-line setter has nowhere to write. The
    // table setters (setInput) insert a missing key, so their rows need no such guard.
    readonly property bool haveSensitivity:  HyprConfig.loaded && HyprConfig.hasInput("sensitivity")
    readonly property string notInConfig: Translation.tr("Not in your Hyprland config")

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
    readonly property int visibleRows: 6
    // Two short segments in a row's control slot.
    readonly property int accelWidth: Tokens.fieldHeight * 6


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

        grouped:   true
        glyph:     "󰌌"
        title:     Translation.tr("Keyboard")
        titleTail: Keyboard.layout
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  (Keyboard.layouts.length > 0 ? Keyboard.layouts.join(", ") + "  ·  " : "")
                 + Keyboard.repeatRate + "/s after " + Keyboard.repeatDelay + "ms"


        // Fixed above the scroll, so "saved, reload to apply" cannot scroll out of sight. The
        // apply strip (layout, mouse and touchpad edits) is empty, and so absent, until needed.
        banner: [
            UndoBar { id: undoBar },
            HyprApplyBar {
                visible: HyprConfig.pendingApply || HyprConfig.canUndo || HyprConfig.lastError !== ""
            }
        ]

        // ══ Configured ════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "keyboard"
            title:    Translation.tr("Your layouts")
            subtitle: Translation.tr("Typing in %1").arg(Keyboard.layout)
            help:     Translation.tr("The bar's keyboard pill cycles these, in this order. To reorder, remove one and add it back, and it goes to the end. Saved to hardware.lua and applied now, so a Hyprland restart keeps them.")

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: Keyboard.layouts

                    Rectangle {
                        id: chip
                        required property string modelData

                        // The last layout can't be removed: Hyprland won't accept a keyboard
                        // with none, and the service refuses it anyway. Nor can any while
                        // hardware.lua has no kb_layout line to save to.
                        readonly property bool removable: Keyboard.layouts.length > 1 && Keyboard.layoutsEditable

                        implicitWidth:  chipRow.implicitWidth + Tokens.spacingMd * 2
                        implicitHeight: Tokens.pillHeight
                        // A capsule in the primary container's tone: tone alone, no outline.
                        radius: height / 2
                        color:  Colors.of(QsWindow.window).primaryContainer

                        RowLayout {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm

                            StyledText {
                                text:  chip.modelData
                                color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                                variant: "body"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                visible: (root.nameOf[chip.modelData] || "") !== ""
                                text: root.nameOf[chip.modelData] || ""
                                variant: "caption"
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)
                            }
                            MaterialIcon {
                                visible: chip.removable
                                glyph:    "󰅖"
                                color:   removeHover.hovered ? Colors.of(QsWindow.window).danger
                                                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)
                                variant: "caption"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   {
                                    onTapped: {
                                        const code = chip.modelData
                                        if (!Keyboard.removeLayout(code)) return
                                        // Re-adding puts it at the END of the list, which
                                        // the card already explains, so the undo says so
                                        // rather than pretending the order survived.
                                        undoBar.show(Translation.tr("Removed %1. Undo adds it back at the end.").arg(code),
                                                     function () { Keyboard.addLayout(code) })
                                    }
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: HyprConfig.loaded && !Keyboard.layoutsEditable
                text: Translation.tr("Not in your Hyprland config. Add a kb_layout line to hardware.lua to edit layouts here.")
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: "dim"
            }

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
                               ? Translation.tr("%1 other input devices follow these layouts").arg(Keyboard.inputDeviceCount - 1)
                               : Translation.tr("The only keyboard")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ══ Mouse ═════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "mouse"
            title:    Translation.tr("Mouse")
            help:     Translation.tr("Applies to every pointer. Saved to hardware.lua; Reload in the bar above applies it.")

            SliderRow {
                enabled: root.haveSensitivity
                label: Translation.tr("Speed")
                labelWidth: 100
                numberWidth: 52
                from: -1; to: 1; step: 0.05
                value: HyprConfig.input.sensitivity ? Number(HyprConfig.input.sensitivity.value) : 0
                readout: value.toFixed(2)
                help: Translation.tr("Hyprland's sensitivity: 0 is the device's own speed.")
                onCommit: function (v) { root.setLine("sensitivity", "float", Math.round(v * 100) / 100) }
            }
            StyledText {
                Layout.fillWidth: true
                visible: HyprConfig.loaded && !root.haveSensitivity
                text: root.notInConfig
                variant: "caption"
                emphasis: "dim"
            }
            SettingRow {
                label:  Translation.tr("Acceleration")
                detail: (root.ptr("accel_profile") ?? "adaptive") === "flat" ? Translation.tr("The pointer moves 1:1 with your hand")
                                                                              : Translation.tr("Speeds up the faster you move")
                help:   Translation.tr("Adaptive speeds up with faster movement; Flat keeps it 1:1 (what most players want).")

                TabStrip {
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.accelWidth
                    connected: true
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "adaptive", label: Translation.tr("Adaptive") }, { value: "flat", label: Translation.tr("Flat") }]
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
                rowTap: true
                label:  Translation.tr("Left-handed")
                detail: root.flag("left_handed", false) ? Translation.tr("Buttons swapped") : ""
                help:   Translation.tr("Swaps the primary and secondary buttons.")
                onTapped: root.toggle("left_handed", false)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.flag("left_handed", false)
                    onToggled: root.toggle("left_handed", false)
                }
            }
        }

        // ══ Repeat ════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "timer"
            title:    Translation.tr("Key repeat")
            help:     Translation.tr("What a held-down key does: how soon it starts repeating, and how fast.")

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

        // ══ Touchpad ══════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "laptop"
            title:    Translation.tr("Touchpad")
            help:     Translation.tr("Laptop touchpads. Saved to hardware.lua; Reload in the bar above applies it.")

            // The touchpad table's own key, not the first natural_scroll in the file:
            // a mouse table may carry one too.
            SettingRow {
                rowTap: true
                label:  Translation.tr("Natural scrolling")
                help:   Translation.tr("Content follows your fingers, like a phone.")
                onTapped: HyprConfig.setInput("touchpad_natural_scroll", !root.naturalScroll)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.naturalScroll
                    onToggled: HyprConfig.setInput("touchpad_natural_scroll", !root.naturalScroll)
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Tap to click")
                onTapped: root.toggle("tap_to_click", true)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.flag("tap_to_click", true)
                    onToggled: root.toggle("tap_to_click", true)
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Tap and drag")
                help:   Translation.tr("Tap, then keep the finger down to drag.")
                onTapped: root.toggle("tap_and_drag", true)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.flag("tap_and_drag", true)
                    onToggled: root.toggle("tap_and_drag", true)
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Ignore while typing")
                help:   Translation.tr("The touchpad pauses briefly after a key press, so a palm doesn't move the cursor.")
                onTapped: root.toggle("disable_while_typing", true)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.flag("disable_while_typing", true)
                    onToggled: root.toggle("disable_while_typing", true)
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("Two-finger right-click")
                help:   Translation.tr("Click with two fingers for a right-click and three for a middle-click, instead of by where you press.")
                onTapped: root.toggle("clickfinger_behavior", false)

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: root.flag("clickfinger_behavior", false)
                    onToggled: root.toggle("clickfinger_behavior", false)
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
            grouped:  true
            symbol:   "add"
            title:    Translation.tr("Add a layout")
            subtitle: Keyboard.layoutsEditable || !HyprConfig.loaded
                ? Translation.tr("%1 available").arg(root.catalogue.length)
                : root.notInConfig

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
                                visible: rowHover.hovered && Keyboard.layoutsEditable
                                glyph:    "󰐕"
                                color:   Colors.of(QsWindow.window).primary
                                variant: "body"
                            }
                        }

                        HoverHandler { id: rowHover; enabled: Keyboard.layoutsEditable; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { enabled: Keyboard.layoutsEditable; onTapped: Keyboard.addLayout(layoutCell.modelData.code) }
                    }
                }
            }

            Scrollbar { flickable: catView }
            }
        }
    }
}
