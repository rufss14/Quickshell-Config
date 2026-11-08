pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── OverviewSessions ──────────────────────────────────────────────────────────
// The overview's Sessions card, hanging under the header's Sessions chip: save what's open
// now under a name, and each saved one with what it holds — restore (it closes the overview
// and starts each app on its workspace, one by one: WorkspaceSessions) or forget it (twice).
// (It lived at the end of a strip of chips under the grid until 2026-10-20, when the strip
// went: the user's call.)
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    property bool shown: false
    property string armed: ""
    onShownChanged: root.armed = ""

    elevation: Tokens.elevationPopup
    cornerRadius: Tokens.radiusCard
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: sessCol.implicitHeight + Tokens.spacingMd * 2
    visible: opacity > 0.01
    opacity: root.shown ? 1 : 0
    SpringValue { id: pop; target: root.shown ? 1 : 0.94; spec: Motion.springSpatial; epsilon: 0.001 }
    scale: pop.value
    transformOrigin: Item.Top
    Behavior on opacity { NumberAnimation { duration: root.shown ? Motion.standard : Motion.fast } }

    Column {
        id: sessCol
        x: Tokens.spacingMd
        y: Tokens.spacingMd
        width: root.width - Tokens.spacingMd * 2
        spacing: Tokens.spacingSm

        InputField {
            width: parent.width
            icon: "save"
            placeholder: Translation.tr("Save what's open as…")
            onAccepted: value => { if (WorkspaceSessions.save(value)) clear() }
        }
        StyledText {
            visible: WorkspaceSessions.sessions.length === 0
            width: parent.width
            text: Translation.tr("Nothing saved yet. Name what's open now — \"Work\", \"Gaming\" — and start it all back later, each app on its workspace.")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.Wrap
        }
        Repeater {
            model: WorkspaceSessions.sessions

            Rectangle {
                id: sess
                required property var modelData
                required property int index
                width: sessCol.width
                height: Tokens.sideCardUnit * 0.85
                radius: Tokens.radiusSm
                color: sessRowHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06) : "transparent"
                PopIn { id: sessPop; active: root.shown; index: sess.index }
                opacity: sessPop.opacity
                HoverHandler { id: sessRowHover }

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacingSm
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: sess.modelData.name
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    // Its apps' icons, a few.
                    Repeater {
                        model: sess.modelData.apps.slice(0, 6)
                        Image {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property string path: Icons.pathForAppId(modelData.appClass || modelData.entry)
                            visible: path !== ""
                            source: path
                            width: Tokens.iconSm
                            height: Tokens.iconSm
                            sourceSize: Qt.size(Tokens.iconSm, Tokens.iconSm)
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Translation.tr("%1 apps").arg(sess.modelData.apps.length)
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
                Row {
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Tokens.spacingXs
                    ChipButton {
                        symbol: "play_arrow"
                        label: Translation.tr("Restore")
                        solid: true
                        enabled: WorkspaceSessions.restoring === ""
                        onActivated: {
                            UiState.overviewOpen = false
                            WorkspaceSessions.restore(sess.modelData.name)
                        }
                    }
                    ChipButton {
                        symbol: "delete"
                        label: root.armed === sess.modelData.name ? Translation.tr("Forget?") : ""
                        on: root.armed === sess.modelData.name
                        tint: Colors.of(QsWindow.window).danger
                        onActivated: {
                            if (root.armed === sess.modelData.name) { WorkspaceSessions.remove(sess.modelData.name); root.armed = "" }
                            else root.armed = sess.modelData.name
                        }
                    }
                }
            }
        }
    }
}
