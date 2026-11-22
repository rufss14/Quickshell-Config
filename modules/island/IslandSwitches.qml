pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/island.js" as Rules
import "../desktop/widgets/toggles.js" as Toggles
import "../../services/deskmenu.js" as Menus

// ── IslandSwitches ────────────────────────────────────────────────────────────
// The Dashboard's switches (Config.islandSwitches, up to six, in your order) as Material 3 Expressive toggle buttons:
// off, a round tonal button; on, it fills with the accent and its corners SPRING in toward a square (the M3E toggle's
// shape change), its icon flipping to the on form. The icons are toggles.js's, which are the bar's and the sidebar's
// own. No caption and no tooltips (the user's call): the icon is the name. A press squashes the button. Right-click opens the switch's settings page where
// it has one (Rules.switchPage). State, blockers and actions are ShellActions'; a switch whose tool is missing is
// dimmed. The card is as tall as its rows (`implicitHeight`); the page gives the rest to the player.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    signal settingsOpened()

    readonly property var switches: Menus.known(Config.islandSwitches, Toggles.TABLE).slice(0, 6)
    readonly property int columns: root.switches.length <= 3 ? Math.max(1, root.switches.length) : 3
    function isMomentary(id) { return Toggles.ACTIONS.indexOf(id) >= 0 }
    function isOn(id) { return !root.isMomentary(id) && ShellActions.switchOn(id) }
    readonly property int rows: Math.ceil(root.switches.length / root.columns)
    readonly property int side: Tokens.iconXl + Tokens.spacingMd

    implicitHeight: root.rows * root.side + (root.rows - 1) * Tokens.spacingSm + Tokens.spacingMd * 2

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingSm

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: root.columns
            rowSpacing: Tokens.spacingSm
            columnSpacing: Tokens.spacingSm

            Repeater {
                model: root.switches
                delegate: Item {
                    id: sw
                    required property string modelData
                    readonly property var meta: Toggles.TABLE[sw.modelData]
                    readonly property bool lit: root.isOn(sw.modelData)
                    readonly property string why: ShellActions.blockerOf(sw.modelData)
                    readonly property string page: Rules.switchPage(sw.modelData)

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: root.side
                    opacity: sw.why !== "" ? 0.45 : 1

                    Accessible.role: root.isMomentary(sw.modelData) ? Accessible.Button : Accessible.CheckBox
                    Accessible.name: Translation.tr(sw.meta.label)
                    Accessible.checkable: !root.isMomentary(sw.modelData)
                    Accessible.checked: sw.lit
                    Accessible.onPressAction: ShellActions.switchFlip(sw.modelData)

                    // Round when off, its corners sprung in when on: the shape is the state.
                    SpringValue {
                        id: corner
                        target: sw.lit ? Tokens.radiusPill : Math.min(face.width, face.height) / 2
                        spec: Motion.springSpatialFast
                        epsilon: 0.1
                    }
                    SpringValue {
                        id: squash
                        target: press.pressed ? 0.9 : press.containsMouse && sw.why === "" ? 1.04 : 1
                        spec: Motion.springSpatialFast
                        epsilon: 0.002
                    }

                    Rectangle {
                        id: face
                        anchors.fill: parent
                        radius: corner.value
                        scale: squash.value
                        color: sw.lit ? root.palette.primary : root.palette.plate
                        Behavior on color { ColorAnimation { duration: Motion.standard } }

                        StateLayer {
                            anchors.fill: parent
                            radius: face.radius
                            hovered: press.containsMouse && sw.why === ""
                            layerColor: sw.lit ? root.palette.fgOnPrimary : root.palette.fg
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: sw.lit ? sw.meta.on : sw.meta.off
                            fill: sw.lit ? 1 : 0
                            font.pixelSize: Tokens.iconLg
                            color: sw.lit ? root.palette.fgOnPrimary : root.palette.fg
                            Behavior on fill { NumberAnimation { duration: Motion.standard } }
                        }
                    }

                    MouseArea {
                        id: press
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: sw.why === "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: function (e) {
                            if (e.button === Qt.RightButton) {
                                if (sw.page === "") return
                                UiState.openSettingsTo(sw.page)
                                root.settingsOpened()
                            } else ShellActions.switchFlip(sw.modelData)
                        }
                    }
                }
            }
        }
    }
}
