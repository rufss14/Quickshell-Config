import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── KaraokeJoin ───────────────────────────────────────────────────────────────
// What the media panel shows when Karaoke is switched on part-way through a song, and while it restarts
// one. Two things, one over the other:
//
//   THE WARNING   "Joined mid-song — this run won't be ranked." A score is for a whole song sung from its
//                 start, so a run that began late can't earn one (karaoke.js startedFromStart). Two ways
//                 out: sing along anyway (for fun, unranked), or RESTART from the beginning — which
//                 pauses the song at 0:00, counts 3, 2, 1, and plays (Karaoke.restartWithCountdown).
//   THE COUNTDOWN a big numeral per second with a ring that runs down, then GO!
//
// Both sit in a FitCard / are sized off the panel, so they resize with it and never spill past an edge.
// Every colour is a palette role; every duration a Motion token or a multiple of one. The panel builds
// this only while it is on screen (so the countdown's first beat is not spent on a hidden panel).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary
    readonly property var pal: Colors.of(QsWindow.window)

    readonly property bool counting: Karaoke.countdown > 0 || Karaoke.countdownGo

    // The entrance, once, when the warning arrives.
    property real inT: 0
    Component.onCompleted: enter.restart()
    NumberAnimation { id: enter; target: root; property: "inT"; from: 0; to: 1; duration: Motion.slow; easing.type: Motion.travel }

    // ══ Backdrop ══════════════════════════════════════════════════════════════
    Rectangle {
        anchors.fill: parent
        color: root.pal.alpha(root.pal.surface, root.counting ? 0.82 : 0.9)
        opacity: root.inT
        Behavior on color { ColorAnimation { duration: Motion.standard } }
        MouseArea { anchors.fill: parent }
    }

    // ══ The warning ═══════════════════════════════════════════════════════════
    FitCard {
        id: warn
        idealWidth: 440
        offsetY: (1 - root.inT) * Tokens.spacingXl
        opacity: root.counting ? 0 : root.inT
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        ColumnLayout {
            width: warn.innerWidth
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd
                Rectangle {
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    radius: Tokens.radiusPill
                    color: root.pal.alpha(root.pal.warning, 0.16)
                    border.width: Tokens.borderChrome
                    border.color: root.pal.alpha(root.pal.warning, 0.7)
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "warning"
                        fill: 1
                        font.pixelSize: Tokens.iconXl
                        color: root.pal.warning
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 2
                    StyledText { text: "Joined mid-song"; font.bold: true }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("This run won't be ranked")
                        variant: "caption"
                        color: root.pal.warning
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                variant: "caption"
                emphasis: "dim"
                text: Translation.tr("A score is for a whole song, sung from its start. You can still sing along for fun, ")
                    + "or restart it from the beginning and go for a rank."
            }

            StyledText {
                Layout.fillWidth: true
                visible: !Karaoke.canRestart
                wrapMode: Text.Wrap
                variant: "caption"
                color: root.pal.warning
                text: Translation.tr("This player can't be restarted from here — seek to the start yourself.")
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Item { Layout.fillWidth: true }
                PanelButton {
                    label: Translation.tr("Sing anyway")
                    variant: "ghost"
                    accent: root.accent
                    onActivated: Karaoke.dismissJoinNotice()
                }
                PanelButton {
                    label: Translation.tr("Restart  ·  3s countdown")
                    symbol: "replay"
                    variant: "primary"
                    accent: root.accent
                    enabled: Karaoke.canRestart
                    onActivated: Karaoke.restartWithCountdown()
                }
            }
        }
    }

    // ══ The countdown ═════════════════════════════════════════════════════════
    Item {
        id: count
        anchors.fill: parent
        visible: root.counting
        // Sized off the panel, so it resizes with it.
        readonly property real unit: Math.min(root.width, root.height)

        readonly property string label: Karaoke.countdown > 0 ? String(Karaoke.countdown) : "GO!"
        readonly property color ink: Karaoke.countdown > 0 ? root.pal.primary : root.pal.success

        // Each beat re-triggers: the numeral drops in large and settles, the ring runs the second down.
        property real pop: 1
        property real ring: 0
        Connections {
            target: Karaoke
            function onCountdownChanged() { beat.restart() }
            function onCountdownGoChanged() { if (Karaoke.countdownGo) beat.restart() }
        }
        ParallelAnimation {
            id: beat
            NumberAnimation { target: count; property: "pop"; from: 0; to: 1; duration: Motion.slow * 1.4; easing.type: Motion.overshoot; easing.overshoot: 2.2 }
            // 950 ms, not a Motion token: it is paced to Karaoke's one-second countdown tick (a beat
            // slightly short of it, so the ring is spent just as the next numeral lands).
            NumberAnimation { target: count; property: "ring"; from: 0; to: 1; duration: Karaoke.countdown > 0 ? 950 : Motion.glide; easing.type: Easing.Linear }
        }

        // The ring: a full circle that runs down over the second, drawn as a shrinking one.
        Rectangle {
            anchors.centerIn: parent
            width: count.unit * 0.62
            height: width
            radius: width / 2
            color: "transparent"
            border.width: Math.max(3, Math.round(count.unit * 0.012))
            border.color: count.ink
            scale: Karaoke.countdown > 0 ? 1.05 - 0.35 * count.ring : 1 + 0.9 * count.ring
            opacity: Karaoke.countdown > 0 ? 0.25 + 0.55 * (1 - count.ring) : 0.8 * (1 - count.ring)
        }

        Text {
            anchors.centerIn: parent
            text: count.label
            color: count.ink
            font.family: Tokens.fontFamily
            font.bold: true
            font.pixelSize: Math.round(count.unit * (Karaoke.countdown > 0 ? 0.36 : 0.26))
            scale: 2.2 - 1.2 * count.pop
            opacity: Math.min(1, count.pop * 3)
            // GO! drifts up and away as it goes.
            anchors.verticalCenterOffset: Karaoke.countdown > 0 ? 0 : -Math.round(count.unit * 0.12 * count.ring)
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Math.round(count.unit * 0.1)
            visible: Karaoke.countdown > 0
            text: "GET READY"
            color: root.pal.fgMuted
            font.family: Tokens.fontFamily
            font.bold: true
            font.letterSpacing: 4
            font.pixelSize: Math.max(Tokens.fontMicro, Math.round(count.unit * 0.035))
        }
    }
}
