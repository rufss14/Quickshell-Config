pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/displays.js" as D

// ── DisplaysPage ──────────────────────────────────────────────────────────────
// Arrange the screens, and pick each one's mode, scale, rotation and VRR.
//
// Edits happen on a COPY (`edited`) of what Hyprland reports; nothing reaches the
// compositor until Apply. Then the Displays service writes hardware.lua, reloads, and
// asks "keep these?" for 15 s — reverting on its own if nobody answers, because a mode
// the screen can't show is a screen you can't click on. All the writing, reloading and
// reverting is the service's; the geometry is displays.js (tested).
//
// The map works in Hyprland's LOGICAL pixels (scale and rotation applied), drawn to fit.
// Drag a screen: where it lands snaps flush against a neighbour (D.snapPosition).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var edited: []
    property string selected: ""

    readonly property var sel: root.edited.find(m => m.name === root.selected) ?? null
    readonly property bool dirty: Displays.loaded && D.changed(Displays.monitors, root.edited)

    Component.onCompleted: Displays.refresh()
    Connections {
        target: Displays
        function onMonitorsChanged() { if (!Displays.pending) root.reset() }
    }

    function reset() {
        root.edited = Displays.monitors.map(m => Object.assign({}, m))
        if (!root.edited.some(m => m.name === root.selected))
            root.selected = root.edited.length > 0 ? root.edited[0].name : ""
    }
    function patch(name, fields) {
        root.edited = root.edited.map(m => m.name === name ? Object.assign({}, m, fields) : m)
    }
    function modeKey(m) { return m.width + "x" + m.height + "@" + Math.round(m.refresh) }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰍹"
        title:     Translation.tr("Displays")
        titleTail: ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  Displays.pending ? "Keep these settings? Reverting in " + Displays.secondsLeft + " s"
                 : root.edited.length + (root.edited.length === 1 ? " screen" : " screens")
                   + (Displays.editable ? "" : "  ·  your own Hyprland config: copy the lines")

        actions: ChipTray {
            ChipButton {
                visible: root.dirty && !Displays.pending
                label:  Translation.tr("Undo edits")
                symbol: "undo"
                onActivated: root.reset()
            }
            ChipButton {
                visible: !Displays.pending
                enabled: root.dirty && !Displays.busy
                label:  Displays.editable ? "Apply" : "Copy lines"
                symbol: Displays.editable ? "check" : "content_copy"
                solid:  true
                onActivated: Displays.editable ? Displays.apply(root.edited) : Displays.copyLines(root.edited)
            }
        }

        // ══ Keep or revert ════════════════════════════════════════════════════
        Section {
            span:    3
            visible: Displays.pending
            glyph:   "󰔟"
            title:   Translation.tr("Keep these settings?")
            subtitle: "Going back to the previous layout in " + Displays.secondsLeft + " s"
            accent:  Colors.of(QsWindow.window).warning
            actions: ChipTray {
                ChipButton { label: "Revert"; symbol: "undo"; onActivated: Displays.revert() }
                ChipButton { label: "Keep"; symbol: "check"; solid: true; onActivated: Displays.keep() }
            }
        }

        Section {
            span:    3
            visible: Displays.lastError !== ""
            glyph:   "󰀪"
            title:   Translation.tr("Couldn't apply")
            subtitle: Displays.lastError
            accent:  Colors.of(QsWindow.window).danger
        }

        // ══ The map ═══════════════════════════════════════════════════════════
        Section {
            span:     3
            symbol:   "dashboard"
            title:    Translation.tr("Arrangement")
            subtitle: Translation.tr("Drag a screen to move it; click one to edit it below")
            accent:   Colors.of(QsWindow.window).primary

            Item {
                id: map
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 220

                readonly property var on: root.edited.filter(m => !m.disabled)
                readonly property var bounds: {
                    if (map.on.length === 0) return { x: 0, y: 0, w: 1, h: 1 }
                    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity
                    for (const m of map.on) {
                        const l = D.logical(m)
                        x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y)
                        x1 = Math.max(x1, m.x + l.w); y1 = Math.max(y1, m.y + l.h)
                    }
                    return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 }
                }
                // Room around the layout so a screen can be dragged to any side.
                readonly property real k: Math.min(map.width / (map.bounds.w * 1.6), map.height / (map.bounds.h * 1.6))
                readonly property real ox: (map.width - map.bounds.w * map.k) / 2 - map.bounds.x * map.k
                readonly property real oy: (map.height - map.bounds.h * map.k) / 2 - map.bounds.y * map.k

                Repeater {
                    model: map.on
                    delegate: Item {
                        id: cell
                        required property var modelData
                        readonly property var size: D.logical(cell.modelData)
                        readonly property bool picked: cell.modelData.name === root.selected

                        x: map.ox + cell.modelData.x * map.k
                        y: map.oy + cell.modelData.y * map.k
                        width: cell.size.w * map.k
                        height: cell.size.h * map.k

                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radiusSm
                            color: cell.picked ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).surfaceHigh
                            border.width: cell.picked ? 2 : 1
                            border.color: cell.picked ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).outline
                            opacity: mover.moving ? 0.35 : 1
                        }
                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 0
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: cell.modelData.name
                                variant: "label"
                                color: cell.picked ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fg
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: cell.modelData.width + "×" + cell.modelData.height
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }

                        // The ghost is what's dragged, so the cell keeps its binding to the
                        // model and lands where the snap puts it.
                        Rectangle {
                            id: ghost
                            parent: map
                            visible: mover.moving
                            width: cell.width; height: cell.height
                            radius: Tokens.radiusSm
                            color: "transparent"
                            border.width: 2
                            border.color: Colors.of(QsWindow.window).primary
                        }
                        MouseArea {
                            id: mover
                            anchors.fill: parent
                            enabled: !Displays.pending
                            cursorShape: Qt.OpenHandCursor
                            property bool moving: false
                            drag.target: ghost
                            drag.threshold: 4
                            onPressed: { ghost.x = cell.x; ghost.y = cell.y; root.selected = cell.modelData.name }
                            onPositionChanged: if (mover.drag.active) mover.moving = true
                            onReleased: {
                                if (!mover.moving) return
                                mover.moving = false
                                const lx = Math.round((ghost.x - map.ox) / map.k)
                                const ly = Math.round((ghost.y - map.oy) / map.k)
                                const p = D.snapPosition(root.edited, cell.modelData.name, lx, ly, 64)
                                root.patch(cell.modelData.name, { x: p.x, y: p.y })
                            }
                        }
                    }
                }
            }
        }

        // ══ The selected screen ═══════════════════════════════════════════════
        Section {
            span:     3
            visible:  root.sel !== null
            symbol:   "monitor"
            title:    root.sel ? root.sel.name : ""
            subtitle: root.sel ? root.sel.desc : ""
            accent:   Colors.of(QsWindow.window).primary

            // Every screen, including one that's off (it isn't on the map then).
            ChipRow {
                visible: root.edited.length > 1
                accent: Colors.of(QsWindow.window).primary
                model: root.edited.map(m => ({ value: m.name, label: m.name + (m.disabled ? " (off)" : "") }))
                current: root.selected
                onPicked: function (v) { root.selected = v }
            }

            SettingRow {
                label: Translation.tr("On")
                help:  Translation.tr("Turn a screen off without unplugging it. At least one has to stay on.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    enabled: !Displays.pending
                    checked: root.sel ? !root.sel.disabled : false
                    onToggled: if (root.sel) root.patch(root.sel.name, { disabled: !root.sel.disabled })
                }
            }

            StyledText { text: "Resolution and refresh rate"; variant: "caption"; emphasis: "dim"; visible: root.sel !== null && !root.sel.disabled }
            ChipRow {
                Layout.fillWidth: true
                visible: root.sel !== null && !root.sel.disabled
                enabled: !Displays.pending
                accent: Colors.of(QsWindow.window).primary
                model: root.sel ? root.sel.modes.map(m => ({ value: root.modeKey(m), label: m.label })) : []
                current: root.sel ? root.modeKey(root.sel) : ""
                onPicked: function (v) {
                    const m = root.sel.modes.find(x => root.modeKey(x) === v)
                    if (m) root.patch(root.sel.name, { width: m.width, height: m.height, refresh: m.refresh })
                }
            }

            StyledText { text: "Scale"; variant: "caption"; emphasis: "dim"; visible: root.sel !== null && !root.sel.disabled }
            ChipRow {
                visible: root.sel !== null && !root.sel.disabled
                enabled: !Displays.pending
                accent: Colors.of(QsWindow.window).primary
                model: [1, 1.25, 1.5, 1.75, 2].map(s => ({ value: s, label: Math.round(s * 100) + "%" }))
                current: root.sel ? root.sel.scale : 1
                onPicked: function (v) { root.patch(root.sel.name, { scale: v }) }
            }

            StyledText { text: "Rotation"; variant: "caption"; emphasis: "dim"; visible: root.sel !== null && !root.sel.disabled }
            ChipRow {
                visible: root.sel !== null && !root.sel.disabled
                enabled: !Displays.pending
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: 0, label: "Normal" }, { value: 1, label: "90°" },
                        { value: 2, label: "180°" }, { value: 3, label: "270°" }]
                current: root.sel ? (root.sel.transform & 3) : 0
                onPicked: function (v) { root.patch(root.sel.name, { transform: v }) }
            }

            SettingRow {
                visible: root.sel !== null && !root.sel.disabled
                label: Translation.tr("Variable refresh rate")
                help:  Translation.tr("Adaptive sync (FreeSync / G-Sync compatible). Only on screens that support it.")
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    enabled: !Displays.pending
                    checked: root.sel ? root.sel.vrr : false
                    onToggled: root.patch(root.sel.name, { vrr: !root.sel.vrr })
                }
            }
        }
    }
}
