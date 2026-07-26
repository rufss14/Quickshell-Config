pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── TimerWidget ───────────────────────────────────────────────────────────────
// The countdown and stopwatch from the overview's timer card, on the desktop.
//
// Backed by the Timers service, which anchors everything to absolute epoch timestamps
// rather than accumulating ticks — so a timer survives a reload, and one that would
// have finished while the machine was off comes back FINISHED rather than resuming.
// This tile is a view over that; it owns no timing of its own.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    readonly property bool stopwatch: root.opts.stopwatch === true

    function _clock(secs) {
        const s = Math.max(0, Math.floor(secs))
        const h = Math.floor(s / 3600)
        const m = Math.floor((s % 3600) / 60)
        const r = s % 60
        const pad = n => (n < 10 ? "0" : "") + n
        return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(r)
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingSm

        StyledText {
            Layout.fillWidth: true
            text: root.stopwatch ? "Stopwatch" : "Timer"
            variant: "caption"
            emphasis: "dim"
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.stopwatch ? root._clock(Timers.swElapsed / 1000)
                                 : root._clock(Timers.timerRemain)
            font.family: Tokens.fontMono
            font.pixelSize: 40
            font.weight: Font.DemiBold
            color: (!root.stopwatch && Timers.timerDone) ? Colors.danger : Colors.fg
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 18
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacingLg

            Ctl {
                glyph: root.stopwatch
                       ? (Timers.swRunning ? "󰏤" : "󰐊")
                       : (Timers.timerRunning ? "󰏤" : "󰐊")
                onTapped: {
                    if (root.stopwatch) Timers.swRunning ? Timers.pauseStopwatch()
                                                         : Timers.startStopwatch()
                    else                Timers.timerRunning ? Timers.stopTimer()
                                                            : Timers.startTimer()
                }
            }
            Ctl {
                glyph: "󰜉"
                onTapped: {
                    if (root.stopwatch) Timers.resetStopwatch()
                    else                Timers.stopTimer()
                }
            }
            // Flips the tile between its two faces. Persisted in opts, so it reopens
            // showing whichever you were using.
            Ctl {
                glyph: "󰓦"
                onTapped: DesktopWidgets.setOpt(root.widgetId, "stopwatch", !root.stopwatch)
            }
        }
    }

    component Ctl: StyledText {
        id: c
        property string glyph: ""
        signal tapped()
        text: c.glyph
        font.pixelSize: 20
        color: cm.containsMouse ? root.accent : Colors.fgMuted
        MouseArea {
            id: cm
            anchors.fill: parent
            anchors.margins: -5
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: c.tapped()
        }
    }
}
