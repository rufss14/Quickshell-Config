pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── VoiceBoardView ── part of VoicePanel.qml: its third face, "Board". ─────────────────────────────────
// Who you have been in calls with the most, from services/CallLog (kept until you forget it):
//
//   the top person  on a hero card — their picture inside a cookie that turns slowly, how long you have been
//                   together, how many calls, when you were last, and "in the call now" while they are
//   the rest        ranked rows: rank on a shape, picture, name, "3 calls · yesterday", time together and a bar
//                   against the leader's. The one you are in a call with has a live dot
//   the footer      how many people and how much time; and a switch to see the hidden ones
//
// Discord's RPC has no friends list, so this ranks everyone who shared a call. The eye on a row hides that person
// from the board (still recorded, so they don't come back); with the hidden ones shown, a row can be restored or
// deleted for good (two taps). Everything on it springs in when the face comes up.
//
// The rows are stable: the id list is replaced only when the ORDER changes, and a row reads its numbers live —
// the log moves every 30 seconds during a call, and a model rebuilt from it would replay every entrance each time.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
Flickable {
    id: view

    // Whether this face is the one on show (VoicePanel): the entrances replay each time it comes up.
    property bool shown: false
    property real room: 100000

    readonly property color accent: Colors.of(QsWindow.window).primary
    readonly property int cardPad: Tokens.spacingMd + Tokens.spacingXs

    height: Math.min(boardCol.implicitHeight, view.room)
    contentHeight: boardCol.implicitHeight
    clip: true
    interactive: boardCol.implicitHeight > view.height
    boundsBehavior: Flickable.StopAtBounds

    property bool showHidden: false
    readonly property var rows: view.showHidden ? CallLog.boardAll : CallLog.board
    readonly property var lead: CallLog.board.length > 0 ? CallLog.board[0] : null
    // Everyone under the leader, as ids (see the header on why).
    readonly property var wanted: view.rows.filter(r => !view.lead || r.id !== view.lead.id).slice(0, 12).map(r => r.id)
    property var ids: []
    function sync() { if (JSON.stringify(view.wanted) !== JSON.stringify(view.ids)) view.ids = view.wanted }
    onWantedChanged: view.sync()
    Component.onCompleted: view.sync()

    readonly property real topSeconds: view.lead ? Math.max(1, (CallLog.people[view.lead.id]?.seconds ?? view.lead.seconds)) : 1

    ColumnLayout {
        id: boardCol
        width: view.width
        spacing: Tokens.spacingSm

        // ── Nobody yet ────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: view.lead === null
            spacing: Tokens.spacingSm
            Item {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: Tokens.spacingLg
                Layout.preferredWidth: Tokens.iconXl * 2
                Layout.preferredHeight: Tokens.iconXl * 2
                MorphShape { anchors.fill: parent; shape: "cookie9"; fillColor: Colors.of(QsWindow.window).surfaceHigh }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "group"
                    color: Colors.of(QsWindow.window).fgMuted
                    font.pixelSize: Tokens.iconXl
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Config.callLog ? Translation.tr("Nobody on the board yet") : Translation.tr("The call log is off")
                variant: "body"; font.weight: Font.Medium
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacingLg
                horizontalAlignment: Text.AlignHCenter
                text: Config.callLog ? Translation.tr("Time you spend in a call with someone is counted here, until you forget it.")
                                     : Translation.tr("Turn it on in Settings › Discord › Call log.")
                variant: "caption"; emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── The leader ────────────────────────────────────────────────────────
        Rectangle {
            id: hero
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: view.lead !== null
            implicitHeight: heroRow.implicitHeight + view.cardPad * 2
            radius: Tokens.radiusXl
            color: Colors.of(QsWindow.window).primaryContainer

            readonly property var rec: view.lead ? (CallLog.people[view.lead.id] ?? view.lead) : null
            readonly property bool here: view.lead ? CallLog.isHere(view.lead.id) : false

            SpringReveal { id: pop; when: view.shown; spec: Motion.springSpatial }
            opacity: Math.min(1, pop.value)
            scale: 0.94 + 0.06 * Math.min(1.1, pop.value)

            RowLayout {
                id: heroRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: view.cardPad
                spacing: Tokens.spacingLg

                // Their picture in a cookie that turns slowly (a RotationAnimator: render thread); a star on its edge.
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingLg
                    Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingLg
                    Item {
                        anchors.fill: parent
                        RotationAnimator on rotation {
                            running: view.shown && Motion.ambientOn
                            from: 0; to: 360
                            duration: Motion.glide * 40
                            loops: Animation.Infinite
                        }
                        MorphShape { anchors.fill: parent; shape: "cookie12"; fillColor: view.accent }
                    }
                    Avatar {
                        anchors.centerIn: parent
                        width: parent.width - Tokens.spacingLg * 1.5
                        height: width
                        source: hero.rec ? hero.rec.avatar : ""
                        name: hero.rec ? hero.rec.name : ""
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        width: Tokens.iconLg + Tokens.spacingXs
                        height: width
                        radius: width / 2
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "star"
                            fill: 1
                            color: Colors.of(QsWindow.window).primaryContainer
                            font.pixelSize: Tokens.iconMd
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1
                    StyledText {
                        text: Translation.tr("Most time together")
                        variant: "caption"
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        opacity: 0.72
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: hero.rec ? (hero.rec.name || Translation.tr("Someone")) : ""
                        variant: "headline"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: hero.rec ? (CallLog.duration(hero.rec.seconds) || Translation.tr("just started"))
                                         + " · " + (hero.rec.calls === 1 ? Translation.tr("1 call") : Translation.tr("%1 calls").arg(hero.rec.calls)) : ""
                        variant: "label"
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        Rectangle {
                            visible: hero.here
                            Layout.preferredWidth: Tokens.spacingMd
                            Layout.preferredHeight: Tokens.spacingMd
                            radius: width / 2
                            color: Colors.of(QsWindow.window).success
                        }
                        StyledText {
                            text: hero.here ? Translation.tr("In the call now") : (hero.rec ? Translation.tr("Last: %1").arg(CallLog.ago(hero.rec.last)) : "")
                            variant: "caption"
                            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                            opacity: 0.72
                        }
                    }
                }
            }
        }

        // ── The rest ──────────────────────────────────────────────────────────
        Repeater {
            model: view.ids
            delegate: Rectangle {
                id: row
                required property int index
                required property string modelData
                readonly property var rec: CallLog.people[row.modelData] ?? ({ name: "", avatar: "", seconds: 0, calls: 0, last: 0, hidden: false })
                // Visible people above this row, plus the leader and itself: a hidden one shown dimmed doesn't take a place.
                readonly property int rank: 2 + view.ids.slice(0, row.index).filter(id => !(CallLog.people[id]?.hidden ?? false)).length
                readonly property bool here: CallLog.isHere(row.modelData)
                readonly property bool dim: row.rec.hidden

                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: rowCol.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).section

                SpringReveal { id: rise; when: view.shown; delay: 80 + row.index * Motion.stagger * 2; spec: Motion.springSpatial }
                opacity: Math.min(1, rise.value) * (row.dim ? 0.55 : 1)
                transform: Translate { y: (1 - rise.value) * Tokens.spacingLg }

                ArmLatch { id: gone; onConfirmed: CallLog.forget(row.modelData) }

                ColumnLayout {
                    id: rowCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingSm
                    spacing: Tokens.spacingXs

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        // The rank, on a shape: the podium (2, 3) a hexagon in the accent, the rest a plain disc.
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: Tokens.iconLg + Tokens.spacingSm
                            Layout.preferredHeight: Tokens.iconLg + Tokens.spacingSm
                            MorphShape {
                                anchors.fill: parent
                                shape: !row.dim && row.rank <= 3 ? "hexagon" : "circle"
                                fillColor: !row.dim && row.rank <= 3 ? Colors.of(QsWindow.window).alpha(view.accent, 0.35)
                                                         : Colors.of(QsWindow.window).surfaceHigh
                            }
                            StyledText {
                                anchors.centerIn: parent
                                text: row.dim ? "" : row.rank
                                variant: "caption"
                                font.weight: Font.DemiBold
                            }
                        }
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: Tokens.iconXl
                            Layout.preferredHeight: Tokens.iconXl
                            Avatar { anchors.fill: parent; source: row.rec.avatar; name: row.rec.name }
                            Rectangle {
                                visible: row.here
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                width: Tokens.spacingMd + Tokens.spacingXs
                                height: width
                                radius: width / 2
                                color: Colors.of(QsWindow.window).success
                                border.width: Tokens.borderWidth * 2
                                border.color: Colors.of(QsWindow.window).section
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: row.rec.name || Translation.tr("Someone")
                                variant: "label"
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: (row.rec.calls === 1 ? Translation.tr("1 call") : Translation.tr("%1 calls").arg(row.rec.calls))
                                      + (row.here ? " · " + Translation.tr("in the call now") : row.rec.last > 0 ? " · " + CallLog.ago(row.rec.last) : "")
                                variant: "caption"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignVCenter
                            text: CallLog.duration(row.rec.seconds) || "—"
                            variant: "label"
                            font.family: Tokens.fontMono
                            font.weight: Font.DemiBold
                        }
                        // Hide from the board; with the hidden shown: restore, or delete for good (two taps).
                        PanelButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: !row.dim
                            variant: "ghost"
                            symbol: "visibility_off"
                            onActivated: CallLog.hide(row.modelData, true)
                        }
                        PanelButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: row.dim
                            variant: "ghost"
                            symbol: "undo"
                            onActivated: CallLog.hide(row.modelData, false)
                        }
                        PanelButton {
                            Layout.alignment: Qt.AlignVCenter
                            visible: row.dim
                            variant: gone.armed ? "primary" : "ghost"
                            accent: Colors.of(QsWindow.window).danger
                            symbol: "delete"
                            onActivated: gone.trigger()
                        }
                    }

                    // Against the leader's time.
                    Meter {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        value: row.rec.seconds / view.topSeconds
                        accent: view.accent
                    }
                }
            }
        }

        // ── Footer ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: Tokens.spacingSm
            visible: view.lead !== null || CallLog.hiddenCount > 0
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: CallLog.board.length === 1 ? Translation.tr("1 person · %1 together").arg(CallLog.duration(CallLog.totalSeconds) || "—")
                    : Translation.tr("%1 people · %2 together").arg(CallLog.board.length).arg(CallLog.duration(CallLog.totalSeconds) || "—")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            ChipButton {
                visible: CallLog.hiddenCount > 0
                symbol: "visibility_off"
                label: Translation.tr("%1 hidden").arg(CallLog.hiddenCount)
                on: view.showHidden
                tint: view.accent
                onActivated: view.showHidden = !view.showHidden
            }
        }
    }
}
