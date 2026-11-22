pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "../../../config"
import "../../../components"
import "../../../services"

// ── MediaSourcePill ───────────────────────────────────────────────────────────
// Which player the page is showing, as a pill at the foot of the card with the player's own icon. With one player
// it just says so. With more than one it is the control that picks: pressed, it unfolds the players in place (the
// card above gives way; no popup), each row with what it is playing, and the choice is held until another is
// made. "Automatic" is the way back: whichever is playing, Spotify first (MediaPosition.prefer).
//
//   players   the MPRIS players (Mpris.players.values)
//   current   the one on show
//   pinned    the identity held ("" = automatic)
//   picked(identity)   a row was pressed ("" = automatic)
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    property var    players: []
    property var    current: null
    property string pinned: ""
    property color  accent: root.palette.primary
    signal picked(string identity)

    readonly property bool several: root.players.length > 1
    property bool open: false
    onSeveralChanged: if (!root.several) root.open = false

    readonly property real pillH: Tokens.iconXl
    readonly property real rowH: Tokens.iconXl + Tokens.spacingXs
    // Automatic + one row per player.
    readonly property real listH: (root.players.length + 1) * root.rowH + Tokens.spacingXs

    SpringValue { id: unfold; target: root.open ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }

    implicitHeight: root.pillH + unfold.value * root.listH

    // The player's own icon, or a note when the theme has none (an empty url would be a warning).
    component PlayerIcon: Item {
        id: pi
        property var player: null
        property int px: Tokens.iconMd
        readonly property string path: Icons.pathForAppId(pi.player?.desktopEntry ?? "")
        implicitWidth: pi.px
        implicitHeight: pi.px
        Image {
            anchors.fill: parent
            visible: pi.path !== ""
            source: pi.path
            sourceSize: Qt.size(pi.px * 2, pi.px * 2)
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
        MaterialIcon {
            anchors.centerIn: parent
            visible: pi.path === ""
            name: "music_note"
            font.pixelSize: pi.px
            color: root.palette.fgMuted
        }
    }

    // ── The players, unfolded above the pill ──────────────────────────────────
    Item {
        id: drawer
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: unfold.value * root.listH
        visible: unfold.value > 0.005
        clip: true

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Tokens.spacingXs
            spacing: 0
            opacity: unfold.value

            // Automatic.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowH
                radius: height / 2
                color: root.pinned === "" ? root.palette.primaryContainer : (autoTap.pressed ? root.palette.plate : "transparent")
                StateLayer { anchors.fill: parent; radius: parent.radius; hovered: autoHover.hovered; layerColor: root.palette.fg }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingMd
                    MaterialIcon {
                        name: "auto_awesome"
                        fill: root.pinned === "" ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: root.pinned === "" ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Automatic")
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: root.pinned === "" ? root.palette.fgOnPrimaryContainer : root.palette.fg
                    }
                    StyledText {
                        text: Translation.tr("Spotify first")
                        variant: "micro"
                        color: root.pinned === "" ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
                    }
                }
                HoverHandler { id: autoHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { id: autoTap; onTapped: { root.picked(""); root.open = false } }
                Accessible.role: Accessible.RadioButton
                Accessible.name: Translation.tr("Automatic")
                Accessible.checked: root.pinned === ""
                Accessible.onPressAction: { root.picked(""); root.open = false }
            }

            Repeater {
                model: root.players
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    readonly property bool shown: row.modelData === root.current
                    readonly property bool held: root.pinned !== "" && row.modelData.identity === root.pinned
                    readonly property bool live: row.modelData.playbackState === MprisPlaybackState.Playing
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.rowH
                    radius: height / 2
                    color: row.held ? root.palette.primaryContainer : (rowTap.pressed ? root.palette.plate : "transparent")
                    StateLayer { anchors.fill: parent; radius: parent.radius; hovered: rowHover.hovered; layerColor: root.palette.fg }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingMd
                        PlayerIcon { player: row.modelData }
                        StyledText {
                            text: row.modelData.identity || row.modelData.desktopEntry
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: row.held ? root.palette.fgOnPrimaryContainer : root.palette.fg
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.trackTitle || ""
                            variant: "micro"
                            color: row.held ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
                            elide: Text.ElideRight
                        }
                        // Playing now: a lit dot. On show: a tick.
                        Rectangle {
                            visible: row.live
                            Layout.preferredWidth: Tokens.spacingSm
                            Layout.preferredHeight: Tokens.spacingSm
                            radius: width / 2
                            color: root.accent
                        }
                        MaterialIcon {
                            visible: row.shown
                            name: "check"
                            font.pixelSize: Tokens.iconMd
                            color: row.held ? root.palette.fgOnPrimaryContainer : root.accent
                        }
                    }
                    HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: rowTap; onTapped: { root.picked(row.modelData.identity); root.open = false } }
                    Accessible.role: Accessible.RadioButton
                    Accessible.name: row.modelData.identity
                    Accessible.checked: row.held
                    Accessible.onPressAction: { root.picked(row.modelData.identity); root.open = false }
                }
            }
        }
    }

    // ── The pill ──────────────────────────────────────────────────────────────
    Rectangle {
        id: pill
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.pillH
        radius: height / 2
        color: root.open ? root.palette.primaryContainer : root.palette.plate
        Behavior on color { ColorAnimation { duration: Motion.standard } }
        StateLayer { anchors.fill: parent; radius: parent.radius; hovered: root.several && pillHover.hovered; layerColor: root.open ? root.palette.fgOnPrimaryContainer : root.palette.fg }

        RowLayout {
            anchors.centerIn: parent
            width: Math.min(implicitWidth, parent.width - Tokens.spacingLg * 2)
            spacing: Tokens.spacingSm
            PlayerIcon { player: root.current }
            StyledText {
                Layout.fillWidth: true
                text: root.current?.identity ?? ""
                variant: "label"
                color: root.open ? root.palette.fgOnPrimaryContainer : root.palette.fg
                elide: Text.ElideRight
            }
            MaterialIcon {
                visible: root.pinned !== ""
                name: "push_pin"
                fill: 1
                font.pixelSize: Tokens.iconSm
                color: root.open ? root.palette.fgOnPrimaryContainer : root.accent
            }
            MaterialIcon {
                visible: root.several
                name: "keyboard_arrow_up"
                font.pixelSize: Tokens.iconMd
                color: root.open ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                rotation: 180 * (1 - unfold.value)
            }
        }

        HoverHandler { id: pillHover; enabled: root.several; cursorShape: Qt.PointingHandCursor }
        TapHandler { enabled: root.several; onTapped: root.open = !root.open }
        Accessible.role: root.several ? Accessible.Button : Accessible.StaticText
        Accessible.name: root.several ? Translation.tr("Choose the player") : (root.current?.identity ?? "")
        Accessible.onPressAction: if (root.several) root.open = !root.open
    }
}
