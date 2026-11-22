import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandUser ────────────────────────────────────────────────────────────────
// Who and what this is, in one row: your picture (your Discord one when the shell knows it, else the lock screen's, else your initial) with the distribution's mark on
// a hexagon at its corner, a greeting for the hour over your name, and two pills — the notifications waiting (a bell, crossed while do-not-disturb is on) and how long the machine has been up. The picture and the mark are the ones the lock screen and About already find
// (`Lock.facePath`, `SysInfo.spec.LOGO`); nothing here probes anything but the uptime.
// ─────────────────────────────────────────────────────────────────────────────
IslandPlate {
    id: root

    Component.onCompleted: {
        Session.probe()
        if (!SysInfo.spec.LOGO) SysInfo.loadSpec()
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        Item {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: Tokens.iconXl * 2
            Layout.preferredHeight: Layout.preferredWidth

            Avatar {
                anchors.fill: parent
                // The picture you wear on Discord when it is known (Discord.meAvatar: live, else the last one seen),
                // else the lock screen's, else your initial.
                source: Discord.meAvatar !== "" ? Discord.meAvatar
                      : Lock.facePath !== "" ? "file://" + Lock.facePath : ""
                name: Session.userName
            }
            IslandBadge {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: -Tokens.spacingMd
                anchors.topMargin: -Tokens.spacingMd
                size: Tokens.iconLg + Tokens.spacingSm
                shape: "hexagon"
                symbol: String(SysInfo.spec.LOGO ?? "") === "" ? "computer" : ""
                Loader {
                    anchors.centerIn: parent
                    active: String(SysInfo.spec.LOGO ?? "") !== ""
                    sourceComponent: Image {
                        source: "file://" + SysInfo.spec.LOGO
                        sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
                        width: Tokens.iconMd
                        height: Tokens.iconMd
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignVCenter
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr(Rules.greeting(Clock.now.getHours()))
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Session.userName
                variant: "title"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: 2
            delegate: Rectangle {
                id: chip
                required property int index
                readonly property string text: chip.index === 0 ? "" + Notifications.count
                    : (Session.uptimeText(Clock.now) !== "" ? Translation.tr("up %1").arg(Session.uptimeText(Clock.now)) : "")
                Layout.alignment: Qt.AlignVCenter
                visible: chip.text !== ""
                implicitWidth: chipRow.implicitWidth + Tokens.spacingMd * 2
                implicitHeight: chipRow.implicitHeight + Tokens.spacingMd
                radius: height / 2
                color: chip.index === 0 ? root.palette.plate : root.palette.primaryContainer
                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs
                    MaterialIcon {
                        name: chip.index === 0 ? (Notifications.dnd ? "notifications_off" : "notifications") : "timer"
                        fill: 1
                        font.pixelSize: Tokens.iconMd
                        color: chip.index === 0 ? root.palette.fgMuted : root.palette.fgOnPrimaryContainer
                    }
                    StyledText {
                        text: chip.text
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: chip.index === 0 ? root.palette.fg : root.palette.fgOnPrimaryContainer
                    }
                }
            }
        }
    }
}
