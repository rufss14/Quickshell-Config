import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules

// ── IslandPill ────────────────────────────────────────────────────────────────
// The live handle: what the island shows at rest when something is going on (Rules.subject), drawn inside the small
// lobe that hangs from the bar's underside where the handle line was. The dock grows this same lobe into the card.
//   record  a pulsing dot in the danger tone, the time, and a stop square (a click on the pill stops it)
//   timer   an hourglass and the time left (the pomodoro's phase when one runs)
//   song    the cover on a circle, the title, and four bars that move with the music (MusicPulse's bands)
// Width follows the content; the dock reads `implicitWidth` / `implicitHeight`.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // "record" | "timer" | "song". The dock keeps it set through its own fade, so the pill never empties as it goes.
    property string subject: ""
    // Whether it is on screen: the bars listen only then.
    property bool live: true

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color accent: Config.moduleAccent("visualizer", root.palette.primary)
    readonly property var player: MusicPulse.player
    readonly property int padX: Tokens.spacingLg
    readonly property int lead: Tokens.iconLg + Tokens.spacingXs

    implicitWidth: row.implicitWidth + root.padX * 2
    implicitHeight: Tokens.iconXl + Tokens.spacingSm

    // The seconds tick only while a recording's time is on screen (a timer keeps its own).
    property bool _secs: false
    readonly property bool wantSeconds: root.live && root.subject === "record"
    // The bars hear the music only while they show it.
    property bool _pulse: false
    readonly property bool wantPulse: root.live && root.subject === "song"
    // Acquire and release in pairs, whichever way the wants change (and once at creation).
    function _sync() {
        if (root.wantSeconds !== root._secs) {
            if (root.wantSeconds) Clock.acquireSeconds(); else Clock.releaseSeconds()
            root._secs = root.wantSeconds
        }
        if (root.wantPulse !== root._pulse) {
            if (root.wantPulse) MusicPulse.acquire(); else MusicPulse.release()
            root._pulse = root.wantPulse
        }
    }
    onWantSecondsChanged: root._sync()
    onWantPulseChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: {
        if (root._secs) Clock.releaseSeconds()
        if (root._pulse) MusicPulse.release()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        // ── The lead: a dot, an hourglass or the cover ────────────────────────
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.lead
            height: root.lead

            Rectangle {
                anchors.centerIn: parent
                visible: root.subject === "record"
                width: Tokens.spacingMd + Tokens.spacingXs
                height: width
                radius: width / 2
                color: root.palette.danger
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: root.live && root.subject === "record"
                    NumberAnimation { to: 0.35; duration: Motion.pulse * 2; easing.type: Motion.inOut }
                    NumberAnimation { to: 1;    duration: Motion.pulse * 2; easing.type: Motion.inOut }
                }
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: root.subject === "timer"
                name: Timers.pomoOn ? "timer" : "hourglass_top"
                fill: 1
                font.pixelSize: Tokens.iconMd
                color: root.palette.primary
            }
            ClippingRectangle {
                anchors.fill: parent
                visible: root.subject === "song"
                radius: width / 2
                color: root.palette.primaryContainer
                Image {
                    anchors.fill: parent
                    source: root.subject === "song" ? (root.player?.trackArtUrl ?? "") : ""
                    sourceSize: Qt.size(root.lead * 2, root.lead * 2)
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                }
            }
        }

        // ── The words ─────────────────────────────────────────────────────────
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.subject === "timer" && Timers.pomoOn
            text: Translation.tr(Timers.pomoLabel)
            variant: "caption"
            emphasis: "dim"
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, Tokens.spacingXl * 11)
            text: root.subject === "record" ? Rules.elapsed((Clock.now.getTime() - Clips.recordSince) / 1000)
                : root.subject === "timer" ? Rules.elapsed(Timers.timerRemain)
                : (root.player?.trackTitle || Translation.tr("Unknown"))
            variant: "label"
            font.weight: Font.DemiBold
            font.features: ({ tnum: 1 })
            elide: Text.ElideRight
        }

        // ── The tail: a stop square, or the bars ──────────────────────────────
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.subject === "record"
            width: Tokens.spacingMd + Tokens.spacingXs
            height: width
            radius: Tokens.radiusXs
            color: root.palette.fgMuted
        }
        Row {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.subject === "song"
            spacing: Tokens.spacingXs
            height: Tokens.iconMd
            Repeater {
                model: 4
                delegate: Rectangle {
                    id: bar
                    required property int index
                    // Bass, mid, high, then the whole level; a floor so a quiet passage still shows four bars.
                    readonly property real band: !root._pulse ? 0
                        : bar.index === 0 ? MusicPulse.bass : bar.index === 1 ? MusicPulse.mid
                        : bar.index === 2 ? MusicPulse.high : MusicPulse.level
                    anchors.bottom: parent.bottom
                    width: Tokens.spacingSm
                    height: Math.max(width, parent.height * Math.min(1, 0.2 + 0.8 * bar.band))
                    radius: width / 2
                    color: root.accent
                }
            }
        }
    }
}
