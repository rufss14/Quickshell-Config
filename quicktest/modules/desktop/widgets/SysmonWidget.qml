pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── SysmonWidget ──────────────────────────────────────────────────────────────
// CPU, memory and temperature. Assembled from parts that already exist — SysInfo for
// the numbers, RadialGauge and Sparkline from the About page — rather than a second
// implementation of /proc parsing.
//
// Refcounted: SysInfo only polls while something is watching, so a desktop without this
// tile costs nothing.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { SysInfo.acquire(); root._held = true }
        else if (!root.active && root._held) { SysInfo.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) SysInfo.release()

    // ── What the small face shows ─────────────────────────────────────────────
    // One ring at 168px, and a tap walks to the next metric — otherwise memory and
    // temperature are simply not reachable on a small tile. Medium and large already
    // show all of them at once, so there the tap does nothing.
    //
    // Transient: the tile comes back on CPU, which is the one you glance at.
    readonly property var metrics: ["cpu", "memory", "temp"]
    property int metricIdx: 0
    readonly property string metric: root.metrics[root.metricIdx % root.metrics.length]

    function tileTap() {
        if (root.size !== "small") return
        root.metricIdx = (root.metricIdx + 1) % root.metrics.length
    }

    readonly property bool tempKnown: SysInfo.hasCpuTemp
    // 0..1 for the ring. Temperature is scaled against 100°C — a DISPLAY scale, not a
    // limit or a throttle point; it is there so the ring has somewhere to travel, and
    // the number beside it is the truth.
    readonly property real gaugeValue:
        root.metric === "cpu"    ? SysInfo.cpu
      : root.metric === "memory" ? SysInfo.memFraction
      : (root.tempKnown ? Math.max(0, Math.min(1, SysInfo.cpuTemp / 100)) : 0)

    readonly property string gaugeReadout:
        root.metric === "cpu"    ? Math.round(SysInfo.cpu * 100) + "%"
      : root.metric === "memory" ? Math.round(SysInfo.memFraction * 100) + "%"
      : (root.tempKnown ? SysInfo.cpuTemp + "°C" : "—")

    readonly property string gaugeLabel:
        root.metric === "cpu" ? "CPU" : root.metric === "memory" ? "MEMORY" : "CPU TEMP"

    // Small is ONE number. Three gauges at 168px would be three unreadable rings.
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "small"
        spacing: 0
        Item { Layout.fillHeight: true }
        // RadialGauge draws the ring only — it has no label or centre-text of its
        // own, so the readout is a child, the way AboutPage's gauge tiles do it.
        RadialGauge {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 96; implicitHeight: 96
            value: root.gaugeValue
            accent: root.accent

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.gaugeReadout
                    variant: "title"
                    font.bold: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.gaugeLabel
                    variant: "caption"
                    emphasis: "dim"
                    font.letterSpacing: 1
                }
            }
        }
        Item { Layout.fillHeight: true }
    }

    RowLayout {
        anchors.fill: parent
        visible: root.size !== "small"
        spacing: Tokens.spacingMd

        RadialGauge {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 92; implicitHeight: 92
            value: SysInfo.cpu
            accent: root.accent

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Math.round(SysInfo.cpu * 100) + "%"
                    variant: "title"
                    font.bold: true
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: "CPU"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

            // `memUsed` is GIGABYTES, not a fraction — memFraction is the ratio.
            Stat {
                label: "Memory"
                value: Math.round(SysInfo.memFraction * 100) + "%"
            }
            Stat {
                label: "CPU temp"
                value: SysInfo.hasCpuTemp ? SysInfo.cpuTemp + "°C" : "—"
            }
            Stat {
                label: "GPU temp"
                value: SysInfo.hasGpuTemp ? SysInfo.gpuTemp + "°C" : "—"
            }

            Sparkline {
                Layout.fillWidth: true
                Layout.preferredHeight: 26
                visible: root.size === "large"
                values: SysInfo.history
                accent: root.accent
                curved: true
            }
        }
    }

    component Stat: RowLayout {
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        StyledText { Layout.fillWidth: true; text: parent.label; variant: "caption"; emphasis: "dim" }
        StyledText { text: parent.value; variant: "caption"; color: Colors.fg }
    }
}
