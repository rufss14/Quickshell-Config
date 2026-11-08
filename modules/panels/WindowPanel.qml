pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── WindowPanel ───────────────────────────────────────────────────────────────
// The window the focused-window module names, and what you can do to it: send it to
// another workspace, float it, fullscreen it, pin it on every workspace, centre it, or
// close it (closing asks twice — it can lose unsaved work).
//
// Which window: the one services/ActiveWindow says the module's screen is about — the
// sidebar's panel opens on `UiState.sidePanelScreen`, a bar's on `UiState.activeScreen`
// (both set by whoever opened it), falling back to the focused monitor. All actions go
// through ActiveWindow, addressed by window, so they never act on whatever happens to
// have focus by the time you click.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property var screen: UiState.sidePanel === "window" && UiState.sidePanelScreen
                                  ? UiState.sidePanelScreen : UiState.activeScreen
    readonly property string monitorName: root.screen ? root.screen.name
                                        : (Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "")
    readonly property var win: ActiveWindow.byMonitor[root.monitorName] ?? null

    ArmLatch {
        id: closeLatch
        onConfirmed: if (root.win) ActiveWindow.close(root.win.address)
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph:     "\u{F01C4}"                                   // 󰇄 window
            icon:      root.win && root.win.icon ? root.win.icon : ""
            iconSize:  Qt.size(22, 22)
            title:     root.win ? (root.win.name || root.win.appId || "Window") : "No window"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  root.win ? root.win.title : "This workspace is empty"
        }

        // ── Where it lives ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.win !== null
            spacing: Tokens.spacingSm

            StyledText {
                text: Translation.tr("Workspace")
                variant: "caption"
                emphasis: "dim"
            }
            Repeater {
                model: 10
                delegate: Rectangle {
                    id: ws
                    required property int index
                    readonly property int num: ws.index + 1
                    readonly property bool here: root.win && root.win.workspace === ws.num

                    Layout.fillWidth: true
                    implicitHeight: 28
                    radius: Tokens.radiusSm
                    color: ws.here ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.85)
                         : wsHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                         : "transparent"
                    border.width: ws.here ? 0 : Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outline
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    StyledText {
                        anchors.centerIn: parent
                        text: ws.num
                        variant: "caption"
                        font.weight: ws.here ? Font.DemiBold : Font.Normal
                        color: ws.here ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                    }
                    HoverHandler { id: wsHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        enabled: !ws.here
                        onTapped: ActiveWindow.toWorkspace(root.win.address, ws.num)
                    }
                }
            }
        }

        // ── What to do to it ──────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.win !== null
            columns: 3
            columnSpacing: Tokens.spacingSm
            rowSpacing: Tokens.spacingSm

            Action {
                symbol: "open_with"
                label:  root.win && root.win.floating ? "Tile" : "Float"
                on:     !!(root.win && root.win.floating)
                onHit:  ActiveWindow.toggleFloating(root.win.address)
            }
            Action {
                symbol: "fullscreen"
                label:  Translation.tr("Fullscreen")
                on:     !!(root.win && root.win.fullscreen)
                onHit:  ActiveWindow.toggleFullscreen(root.win.address)
            }
            Action {
                symbol: "push_pin"
                label:  root.win && root.win.pinned ? "Unpin" : "Pin"
                on:     !!(root.win && root.win.pinned)
                enabled: !!(root.win && root.win.floating)
                onHit:  ActiveWindow.togglePin(root.win.address)
            }
            Action {
                symbol: "center_focus_strong"
                label:  Translation.tr("Centre")
                enabled: !!(root.win && root.win.floating)
                onHit:  ActiveWindow.center(root.win.address)
            }
            Action {
                symbol: "my_location"
                label:  Translation.tr("Focus")
                onHit:  ActiveWindow.focus(root.win.address)
            }
            Action {
                symbol: "close"
                label:  closeLatch.armed ? "Sure?" : "Close"
                danger: true
                on:     closeLatch.armed
                onHit:  closeLatch.trigger()
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.win !== null && !root.win.floating
            text: Translation.tr("Pin and Centre are for floating windows")
            variant: "caption"
            emphasis: "dim"
        }
    }

    // ── Action — one square button: an icon over a word ───────────────────────
    component Action: Rectangle {
        id: act
        property string symbol: ""
        property string label: ""
        property bool on: false
        property bool danger: false
        signal hit()

        readonly property color tint: act.danger ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus

        Layout.fillWidth: true
        implicitHeight: 58
        radius: Tokens.radiusPill
        opacity: act.enabled ? 1 : 0.4
        color: act.on ? Colors.of(QsWindow.window).alpha(act.tint, 0.22)
             : actHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
        border.width: Tokens.borderWidth
        border.color: act.on ? Colors.of(QsWindow.window).alpha(act.tint, 0.5) : Colors.of(QsWindow.window).outline
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        scale: actTap.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingXs
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: act.symbol
                fill: act.on ? 1 : 0
                color: act.on || actHover.hovered ? act.tint : Colors.of(QsWindow.window).fgMuted
                font.pixelSize: Tokens.iconLg
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: act.label
                variant: "caption"
                color: act.on ? act.tint : Colors.of(QsWindow.window).fg
            }
        }

        HoverHandler { id: actHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: actTap; onTapped: act.hit() }
    }
}
