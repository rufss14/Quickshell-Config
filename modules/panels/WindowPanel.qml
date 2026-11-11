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
// The window the focused-window module names, and what you can do to it. In the shell's Material 3
// Expressive panel shape:
//
//   Header  (Settings › Modules › Focused window hides it) the title
//   Hero    the window itself: its app's icon on a shape, its app, its title, and under them the ten
//           workspaces as one strip (the one it is on filled; tap another to send it there)
//   Tiles   float, fullscreen, pin, centre, focus, close (closing asks twice: it can lose unsaved work)
//
// Which window: the one services/ActiveWindow says the module's screen is about. The sidebar's panel opens on
// `UiState.sidePanelScreen`, a bar's on `UiState.activeScreen` (both set by whoever opened it), falling back
// to the focused monitor. All actions go through ActiveWindow, addressed by window, so they never act on
// whatever happens to have focus by the time you click.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingXl
    readonly property color accent: Colors.of(QsWindow.window).primary
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
        spacing: Tokens.spacingSm

        PanelHeader {
            Layout.fillHeight: false
            visible: Config.panelHeader("window")
            symbol:    "select_all"
            title:     Translation.tr("Focused")
            titleTail: Translation.tr("window")
            accent:    root.accent
            subtitle:  root.win ? (root.win.name || root.win.appId || "") : Translation.tr("This workspace is empty")
        }

        PanelHero {
            id: hero
            visible: root.win !== null
            symbol: "select_all"
            iconSource: root.win && root.win.icon ? root.win.icon : ""
            shape: "squircle"
            active: true
            turning: false
            accent: root.accent
            title: root.win ? (root.win.name || root.win.appId || Translation.tr("Window")) : ""
            line: root.win ? root.win.title : ""

            // ── Where it lives: ten workspaces as one strip ───────────────────
            footer: Rectangle {
                id: strip
                Layout.fillWidth: true
                implicitHeight: Tokens.iconXl + Tokens.spacingSm
                radius: height / 2
                color: Colors.of(QsWindow.window).alpha(hero.ink, 0.10)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingXs
                    spacing: 0
                    Repeater {
                        model: 10
                        delegate: Rectangle {
                            id: ws
                            required property int index
                            readonly property int num: ws.index + 1
                            readonly property bool here: !!root.win && root.win.workspace === ws.num

                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: height / 2
                            color: ws.here ? root.accent
                                 : Colors.of(QsWindow.window).alpha(hero.ink, wsHover.hovered ? 0.14 : 0)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            StyledText {
                                anchors.centerIn: parent
                                text: ws.num
                                variant: "caption"
                                font.weight: ws.here ? Font.DemiBold : Font.Medium
                                color: ws.here ? Colors.of(QsWindow.window).fgOnPrimary : hero.ink
                            }
                            HelpTip { text: ws.here ? "" : Translation.tr("Send to workspace %1").arg(ws.num) }
                            HoverHandler { id: wsHover; cursorShape: ws.here ? Qt.ArrowCursor : Qt.PointingHandCursor }
                            TapHandler {
                                enabled: !ws.here
                                onTapped: ActiveWindow.toWorkspace(root.win.address, ws.num)
                            }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: Translation.tr("Workspace %1").arg(ws.num)
                            Accessible.checked: ws.here
                            Accessible.onPressAction: if (!ws.here && root.win) ActiveWindow.toWorkspace(root.win.address, ws.num)
                        }
                    }
                }
            }
        }

        PanelEmpty {
            visible: root.win === null
            quiet: true
            symbol: "select_all"
            shape: "squircle"
            title: Translation.tr("No window")
            text: Translation.tr("This workspace is empty. Focus a window and its controls show up here.")
        }

        // ── What to do to it ──────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.win !== null
            columns: 3
            columnSpacing: Tokens.spacingSm
            rowSpacing: Tokens.spacingSm
            uniformCellWidths: true

            Action {
                symbol: "open_with"
                label:  root.win && root.win.floating ? Translation.tr("Tile") : Translation.tr("Float")
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
                label:  root.win && root.win.pinned ? Translation.tr("Unpin") : Translation.tr("Pin")
                on:     !!(root.win && root.win.pinned)
                enabled: !!(root.win && root.win.floating)
                help:   Translation.tr("Pin is for floating windows")
                onHit:  ActiveWindow.togglePin(root.win.address)
            }
            Action {
                symbol: "center_focus_strong"
                label:  Translation.tr("Centre")
                enabled: !!(root.win && root.win.floating)
                help:   Translation.tr("Centre is for floating windows")
                onHit:  ActiveWindow.center(root.win.address)
            }
            Action {
                symbol: "my_location"
                label:  Translation.tr("Focus")
                onHit:  ActiveWindow.focus(root.win.address)
            }
            Action {
                symbol: "close"
                label:  closeLatch.armed ? Translation.tr("Sure?") : Translation.tr("Close")
                danger: true
                on:     closeLatch.armed
                onHit:  closeLatch.trigger()
            }
        }
    }

    // ── Action: one tonal tile, an icon on a shape over a word ───────────────
    component Action: Item {
        id: act
        property string symbol: ""
        property string label: ""
        property string help: ""
        property bool on: false
        property bool danger: false
        signal hit()

        readonly property color tint: act.danger ? Colors.of(QsWindow.window).danger : root.accent

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: actCol.implicitHeight + Tokens.spacingMd * 2
        opacity: act.enabled ? 1 : 0.45
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        SpringValue { id: actPress; target: actTap.pressed ? 1 : 0; spec: Motion.springSpatialFast }
        scale: 1 - actPress.value * 0.05

        Accessible.role: Accessible.Button
        Accessible.name: act.label
        Accessible.onPressAction: if (act.enabled) act.hit()

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusCard
            color: act.on ? Colors.of(QsWindow.window).alpha(act.tint, actHover.hovered ? 0.30 : 0.22)
                          : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, actHover.hovered ? 0.10 : 0.06)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        Column {
            id: actCol
            anchors.centerIn: parent
            spacing: Tokens.spacingXs
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Tokens.iconXl + Tokens.spacingSm
                height: width
                MorphShape {
                    anchors.fill: parent
                    shape: act.on ? "cookie7" : "circle"
                    fillColor: act.on ? act.tint : Colors.of(QsWindow.window).surfaceHigh
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: act.symbol
                    fill: act.on ? 1 : 0
                    color: act.on ? Colors.of(QsWindow.window).fgOnPrimary
                         : act.danger && actHover.hovered ? act.tint : Colors.of(QsWindow.window).fgMuted
                    font.pixelSize: Tokens.iconLg
                }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: act.label
                variant: "caption"
                font.weight: Font.Medium
            }
        }

        HelpTip { text: act.enabled ? "" : act.help }
        HoverHandler { id: actHover; cursorShape: act.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { id: actTap; enabled: act.enabled; onTapped: act.hit() }
    }
}
