pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/gamemodewatch.js" as Watch

// ── GamingHistoryView ── part of GamingPanel.qml; `panel` is the GamingPanel it belongs to. ──
ColumnLayout {
    id: historyPage
    required property var panel
    readonly property int idx: 3
    width: panel.pagesBox.width
    x: (historyPage.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(historyPage.idx - panel.pg.value) * 1.4)
    visible: historyPage.opacity > 0.01
    spacing: Tokens.spacingSm

    // The sessions the mode ran for a minute or more (services/Gamemode `sessions`, newest first),
    // the latest six; each with its game's picture where Steam has one. Clear is two taps.
    Rectangle {
        id: histCard
        readonly property var rows: Gamemode.sessions.slice(0, 6)
        Layout.fillWidth: true
        implicitHeight: histCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: histCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                StyledText {
                    Layout.fillWidth: true
                    text: Gamemode.sessions.length === 0 ? "Recent sessions"
                        : "Recent sessions · " + Gamemode.sessions.length + " kept"
                    variant: "caption"; emphasis: "dim"
                }
                ChipButton {
                    id: clearChip
                    visible: Gamemode.sessions.length > 0
                    symbol: "close"
                    label: clearChip.armed ? "Sure?" : "Clear"
                    on: clearChip.armed
                    tint: Colors.of(QsWindow.window).danger
                    property bool armed: false
                    onActivated: {
                        if (clearChip.armed) { Gamemode.clearSessions(); clearChip.armed = false }
                        else { clearChip.armed = true; disarm.restart() }
                    }
                    Timer { id: disarm; interval: 2500; onTriggered: clearChip.armed = false }
                }
            }

            // Nothing yet: a quiet disc and a sentence, not an empty box.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: histCard.rows.length === 0
                spacing: Tokens.spacingSm
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.iconXl * 2
                    Layout.preferredHeight: Tokens.iconXl * 2
                    MorphShape {
                        anchors.fill: parent
                        shape: "cookie9"
                        fillColor: Colors.of(QsWindow.window).surfaceHigh
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "history"
                        color: Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconXl
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("No sessions yet")
                    variant: "body"; font.weight: Font.Medium
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Each time game mode runs for a minute or more, it is written down here.")
                    variant: "caption"; emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            Repeater {
                model: histCard.rows
                delegate: RowLayout {
                    id: hrow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    Component.onCompleted: if (hrow.modelData.appId !== "") Gamemode.requestArt(hrow.modelData.appId)

                    // The game's header, cropped to a thumbnail; a controller on a plain plate until
                    // there is one (a non-Steam game never has one).
                    ClippingRectangle {
                        id: thumb
                        readonly property string path: Gamemode.artPaths[hrow.modelData.appId] || hrow.modelData.art
                        Layout.alignment: Qt.AlignVCenter
                        Layout.preferredWidth: Tokens.sideCardUnit * 1.5
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingSm
                        radius: Tokens.radiusSm
                        color: Colors.of(QsWindow.window).alpha(panel.accent, 0.16)
                        Image {
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 240
                            source: thumb.path !== "" ? "file://" + thumb.path : ""
                            opacity: status === Image.Ready ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: thumb.path === ""
                            name: "sports_esports"
                            fill: 1
                            color: panel.accent
                            font.pixelSize: Tokens.iconMd
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: hrow.modelData.game !== "" ? hrow.modelData.game
                                : hrow.modelData.auto ? "A game" : "Game mode"
                            variant: "body"; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Watch.whenLabel(hrow.modelData.start, Date.now())
                            variant: "caption"; emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        text: Gamemode.duration(hrow.modelData.seconds)
                        variant: "label"; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitHeight: Tokens.iconMd + Tokens.spacingSm
                        implicitWidth: how.implicitWidth + Tokens.spacingLg * 2
                        radius: height / 2
                        color: hrow.modelData.auto ? Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                                                   : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                        StyledText {
                            id: how
                            anchors.centerIn: parent
                            text: hrow.modelData.auto ? "Followed" : "By hand"
                            variant: "caption"
                            color: hrow.modelData.auto ? panel.accent : Colors.of(QsWindow.window).fgMuted
                        }
                    }
                }
            }
        }
    }
}
