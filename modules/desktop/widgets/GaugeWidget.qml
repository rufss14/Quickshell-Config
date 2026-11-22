pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── GaugeWidget ───────────────────────────────────────────────────────────────
// One number as one picture: CPU, memory, GPU, CPU temperature or the battery, shown as a glass in
// your shape that fills with water (GaugeFace) or as the shell's wavy ring, with the reading
// beside it. Tap to walk to the next metric this machine can read.
//
// The numbers come from SysInfo (refcounted: it polls only while a tile watches, so a desktop
// without this tile pays nothing) and the battery from SysStats. A metric the machine has no
// reading for is said so, not drawn as zero (the blocker contract).
//
// Options (`opts`): metric (cpu | memory | gpu | temp | battery), style (water | ring), shape (a
// MorphShape name; pentagon by default, the glass).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var palette: Colors.of(QsWindow.window)

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { SysInfo.acquire(); root._held = true }
        else if (!root.active && root._held) { SysInfo.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) SysInfo.release()

    // ── Which metric ──────────────────────────────────────────────────────────
    readonly property var metrics: ["cpu", "memory", "gpu", "temp", "battery"]
    // The tapped-to one wins over the saved one until the next reload (a walk, not a setting).
    property string walked: ""
    readonly property string metric: root.walked !== "" ? root.walked : (root.opts.metric ?? "cpu")

    // Why a metric can't be read here, or "".
    function why(m) {
        if (m === "gpu")     return SysInfo.hasGpu ? "" : "No GPU reading"
        if (m === "temp")    return SysInfo.hasCpuTemp ? "" : "No temperature sensor"
        if (m === "battery") return SysStats.hasBattery ? "" : "No battery"
        return ""
    }
    function tileTap() {
        let i = root.metrics.indexOf(root.metric)
        for (let n = 0; n < root.metrics.length; n++) {
            i = (i + 1) % root.metrics.length
            if (root.why(root.metrics[i]) === "") { root.walked = root.metrics[i]; return }
        }
    }

    function valueOf(m) {
        switch (m) {
        case "memory":  return SysInfo.memFraction
        case "gpu":     return SysInfo.gpu
        // Scaled against 100°C: a display scale so the water has somewhere to rise, not a limit.
        case "temp":    return Math.max(0, Math.min(1, SysInfo.cpuTemp / 100))
        case "battery": return Math.max(0, Math.min(1, SysStats.battery?.percentage ?? 0))
        default:        return SysInfo.cpu
        }
    }
    function readoutOf(m) {
        return m === "temp" ? SysInfo.cpuTemp + "°C" : Math.round(root.valueOf(m) * 100) + "%"
    }
    function labelOf(m) {
        switch (m) {
        case "memory":  return Translation.tr("Memory")
        case "gpu":     return Translation.tr("GPU")
        case "temp":    return Translation.tr("CPU temperature")
        case "battery": return Translation.tr("Battery")
        default:        return Translation.tr("CPU")
        }
    }

    readonly property string blocked: root.why(root.metric)
    readonly property bool wide: root.size !== "small"

    WidgetEmpty {
        visible: root.blocked !== ""
        icon: "speed"
        text: Translation.tr(root.blocked)
    }

    GridLayout {
        anchors.fill: parent
        visible: root.blocked === ""
        columns: root.wide ? 2 : 1
        columnSpacing: Tokens.spacingXl
        rowSpacing: Tokens.spacingSm

        GaugeFace {
            Layout.alignment: Qt.AlignCenter
            // The face is square: as tall as the tile allows on a wide one, a bit over half on a small one
            // (the number sits under it).
            readonly property real side: root.wide ? Math.min(root.height, root.width * 0.5)
                                                   : Math.min(root.width, root.height * 0.64)
            Layout.preferredWidth: side
            Layout.preferredHeight: side
            value: root.valueOf(root.metric)
            shape: root.opts.shape ?? "pentagon"
            water: (root.opts.style ?? "water") === "water"
            accent: root.accent
            running: root.active
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: root.wide ? Qt.AlignVCenter : Qt.AlignHCenter
            spacing: 0

            StyledText {
                Layout.alignment: root.wide ? Qt.AlignLeft : Qt.AlignHCenter
                text: root.readoutOf(root.metric)
                variant: root.wide ? "display" : "headline"
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.alignment: root.wide ? Qt.AlignLeft : Qt.AlignHCenter
                text: root.labelOf(root.metric)
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
