import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/island.js" as Rules
import "../../services/weather.js" as W

// ── WeatherHourly ─────────────────────────────────────────────────────────────
// The hero's hours: the temperature as a curve scaled to its own range, its high and low named, and five hours'
// names under it. Press and drag along it and the time follows:
// a marker runs down the curve, and `scrubbed(index)` says which hour, so the page
// shows that hour's weather. The hour stays where you let go; the page puts it back to now. `hours` is
// Weather.hours' shape; `selected` is the hour on show (-1 for none).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    property var    hours: []
    property string title: ""
    property int    selected: -1
    property color  ink: Colors.of(QsWindow.window).fg
    property color  inkDim: Colors.of(QsWindow.window).fgMuted
    signal scrubbed(int index)

    readonly property var span: Rules.spanOf(root.hours.map(function (h) { return h.tempC }), 0.22)
    // The hours the curve peaks and bottoms out at, named on it so the range needs no caption.
    readonly property int hiIdx: root.span.norm.length > 1 ? root.span.norm.indexOf(Math.max.apply(null, root.span.norm)) : -1
    readonly property int loIdx: root.span.norm.length > 1 ? root.span.norm.indexOf(Math.min.apply(null, root.span.norm)) : -1
    readonly property int n: root.hours.length
    readonly property bool picked: root.selected >= 0 && root.selected < root.n
    readonly property real barW: Math.max(Tokens.borderWidth * 2, Math.min(Tokens.spacingSm, plot.width / Math.max(1, root.n) * 0.6))
    function xOf(i) { return root.n > 1 ? i / (root.n - 1) * plot.width : plot.width / 2 }
    function hourText(i) { const h = root.hours[i]; return h ? (h.hour < 10 ? "0" : "") + h.hour + ":00" : "" }

    // The marker follows the pointer on a spring, so a fast drag is smooth and a click glides there.
    SpringValue {
        id: head
        target: root.picked ? root.xOf(root.selected) : 0
        spec: Motion.springSpatialFast
        epsilon: 0.1
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            StyledText {
                Layout.fillWidth: true
                text: root.picked ? root.hourText(root.selected) : root.title
                variant: "caption"
                color: root.inkDim
                elide: Text.ElideRight
            }
            StyledText {
                visible: root.picked
                text: root.picked ? Weather.temp(root.hours[root.selected].tempC) + "°" : ""
                variant: "caption"
                font.weight: Font.Bold
                font.features: ({ tnum: 1 })
                color: root.ink
            }
        }

        // The curve and the hours' names share one x: sample i at i / (n - 1) of the width.
        Item {
            id: plot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: root.barW / 2
            Layout.rightMargin: root.barW / 2

            Sparkline {
                id: curve
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                values: root.span.norm
                capacity: Math.max(2, root.span.norm.length)
                accent: root.ink
            }

            // The marker: a line down the curve and a dot on it.
            Rectangle {
                visible: root.picked
                x: head.value - width / 2
                y: curve.y
                width: Tokens.borderWidth * 2
                height: curve.height
                radius: width / 2
                color: root.palette.alpha(root.ink, 0.4)
            }
            Rectangle {
                visible: root.picked
                readonly property real v: root.picked && root.selected < root.span.norm.length ? root.span.norm[root.selected] : 0
                width: Tokens.spacingMd + 2
                height: width
                radius: width / 2
                x: head.value - width / 2
                y: curve.y + curve.height * (1 - v) - height / 2
                color: root.ink
            }

            // The high and the low, each a dot on the curve with its number over it; they step aside for the marker.
            Repeater {
                model: root.hiIdx >= 0 && root.loIdx !== root.hiIdx ? [root.hiIdx, root.loIdx] : []
                delegate: Item {
                    id: ext
                    required property int modelData
                    readonly property real v: root.span.norm[ext.modelData] ?? 0
                    opacity: root.picked && Math.abs(ext.modelData - root.selected) < 4 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    Rectangle {
                        id: extDot
                        width: Tokens.spacingMd
                        height: width
                        radius: width / 2
                        x: root.xOf(ext.modelData) - width / 2
                        y: curve.y + curve.height * (1 - ext.v) - height / 2
                        color: root.ink
                    }
                    StyledText {
                        text: Weather.temp(root.hours[ext.modelData].tempC) + "°"
                        variant: "caption"
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: root.ink
                        x: Math.max(0, Math.min(plot.width - width, root.xOf(ext.modelData) - width / 2))
                        y: extDot.y - height - Tokens.spacingXs
                    }
                }
            }

            // Hold and drag anywhere on it: the hour under the pointer.
            MouseArea {
                anchors.fill: parent
                enabled: root.n > 1
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                function pick(x) { root.scrubbed(Math.max(0, Math.min(root.n - 1, Math.round(x / plot.width * (root.n - 1))))) }
                onPressed: function (e) { pick(e.x) }
                onPositionChanged: function (e) { if (pressed) pick(e.x) }
            }
        }

        // Five hours' names under it.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.fontMicro + Tokens.spacingXs
            Layout.leftMargin: root.barW / 2
            Layout.rightMargin: root.barW / 2
            Repeater {
                model: root.n > 1 ? [0, 0.25, 0.5, 0.75, 1] : []
                delegate: StyledText {
                    required property real modelData
                    readonly property int at: Math.round(modelData * (root.n - 1))
                    text: root.hourText(at)
                    variant: "micro"
                    color: root.inkDim
                    font.features: ({ tnum: 1 })
                    x: Math.max(0, Math.min(parent.width - width, root.xOf(at) - width / 2))
                }
            }
        }
    }
}
