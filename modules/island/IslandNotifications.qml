import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../notifications"

// ── IslandNotifications ───────────────────────────────────────────────────────
// The notification history as an island page: on the left the loud card (how many are waiting, Do Not
// Disturb's switch, clear everything: asked twice); on the right the history itself
// (NotificationCentre in its compact form: its own tools, search, groups and undo), filling its card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    ArmLatch {
        id: clearLatch
        onConfirmed: Notifications.clearHistory()
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                id: bell
                Layout.fillWidth: true
                Layout.fillHeight: true
                hero: !Notifications.quiet
                order: 0
                clip: true

                MorphShape {
                    width: bell.height * 0.8
                    height: width
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -width * 0.25
                    anchors.topMargin: -width * 0.22
                    shape: Notifications.quiet ? "circle" : "burst"
                    turns: false
                    fillColor: root.palette.alpha(bell.ink, 0.10)
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs

                    StyledText {
                        text: Translation.tr("Notifications").toUpperCase()
                        variant: "caption"
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: bell.inkDim
                    }
                    IslandBadge {
                        Layout.topMargin: Tokens.spacingSm
                        size: Tokens.iconXl * 2 + Tokens.spacingSm
                        filled: !Notifications.quiet
                        shape: Notifications.quiet ? "circle" : Notifications.unseen > 0 ? "burst" : "cookie9"
                        symbol: Notifications.quiet ? "" : Notifications.unseen > 0 ? "" : "notifications"
                        text: Notifications.quiet ? "" : Notifications.unseen > 0 ? String(Math.min(99, Notifications.unseen)) : ""
                        textPx: Tokens.fontHeadline
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: Notifications.quiet
                            name: "bedtime"
                            fill: 1
                            font.pixelSize: Tokens.iconXl
                            color: bell.ink
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacingSm
                        text: Notifications.quiet ? Translation.tr("Quiet")
                            : Notifications.unseen > 0 ? Translation.tr("%1 new").arg(Notifications.unseen)
                            : Notifications.count > 0 ? Translation.tr("All seen") : Translation.tr("Nothing yet")
                        variant: "headline"
                        font.weight: Font.DemiBold
                        color: bell.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Notifications.quietHeldExternally ? Translation.tr("Held quiet while something asks for it")
                            : Notifications.quiet ? Translation.tr("Notifications are kept, not shown")
                            : Translation.tr("%1 kept").arg(Notifications.count)
                        variant: "caption"
                        color: bell.inkDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    // Quiet for a while: the three lengths the service knows. A pill of the card's own ink,
                    // so it reads on the accent container and on the plain plate alike.
                    StyledText {
                        text: Translation.tr("Quiet for")
                        variant: "caption"
                        color: bell.inkDim
                    }
                    Flow {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.bottomMargin: Tokens.spacingSm
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: [
                                { label: Translation.tr("30 min"), minutes: 30 },
                                { label: Translation.tr("1 hour"), minutes: 60 },
                                { label: Translation.tr("Till morning"), minutes: 0 }
                            ]

                            Rectangle {
                                id: lengthPill
                                required property var modelData
                                implicitWidth: lengthText.implicitWidth + Tokens.spacingLg * 2
                                implicitHeight: lengthText.implicitHeight + Tokens.spacingSm * 2
                                radius: height / 2
                                color: root.palette.alpha(bell.ink, lengthArea.pressed ? 0.24 : lengthArea.containsMouse ? 0.18 : 0.10)
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                StyledText {
                                    id: lengthText
                                    anchors.centerIn: parent
                                    text: lengthPill.modelData.label
                                    variant: "caption"
                                    font.weight: Font.DemiBold
                                    color: bell.ink
                                }
                                MouseArea {
                                    id: lengthArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: lengthPill.modelData.minutes > 0
                                        ? Notifications.dndFor(lengthPill.modelData.minutes)
                                        : Notifications.dndUntilMorning()
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: Translation.tr("Quiet for %1").arg(lengthPill.modelData.label)
                                Accessible.onPressAction: lengthArea.clicked(null)
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Do Not Disturb")
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: bell.ink
                        }
                        Toggle {
                            accessibleName: Translation.tr("Do Not Disturb")
                            checked: Notifications.dnd
                            accent: root.palette.primary
                            onToggled: Notifications.toggleDnd()
                        }
                    }
                }
            }

            IslandTile {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingSm
                order: 1
                row: true
                enabled: Notifications.count > 0
                danger: true
                on: clearLatch.armed
                symbol: "delete"
                label: clearLatch.armed ? Translation.tr("Sure?") : Translation.tr("Clear all")
                sub: clearLatch.armed ? Translation.tr("Click again to clear") : Translation.tr("Empties the history")
                onClicked: clearLatch.trigger()
            }
        }

        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: true
            order: 1
            clip: true

            NotificationCentre {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                compact: true
                island: true
                fill: true
            }
        }
    }
}
