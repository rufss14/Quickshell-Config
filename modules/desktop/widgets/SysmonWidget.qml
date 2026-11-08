pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── SysmonWidget ──────────────────────────────────────────────────────────────
// CPU, memory and temperature. Assembled from parts that already exist — SysInfo for
// the numbers, RadialGauge and Sparkline from the About page — rather than a second
// implementation of /proc parsing.
//
// ── The ring tracks, it doesn't lurch ────────────────────────────────────────
// SysInfo polls once a second. Left to the default eased Behaviour, the ring would
// sit still for five-sixths of a second and then twitch — which reads as a clock,
// not a monitor. `sampleInterval` makes it travel linearly across the whole poll
// instead; the per-core strip eases on `Motion.track` for the same reason.
//
// Refcounted: SysInfo only polls while something is watching, so a desktop without this
// tile costs nothing.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { SysInfo.acquire(); root._held = true }
        else if (!root.active && root._held) { SysInfo.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   { root._sync(); root.shownMetric = root.metric }
    Component.onDestruction: if (root._held) SysInfo.release()

    // ── What the small face shows ─────────────────────────────────────────────
    // One ring at 168px, and a tap walks to the next metric — otherwise memory and
    // temperature are simply not reachable on a small tile. Medium and large already
    // show all of them at once, so there the tap opens the full System page.
    //
    // The CYCLE is still transient — tapping through metrics doesn't get written
    // anywhere, and a reload always starts from the seed below. `opts.metric` is a
    // separate, persisted thing: which metric that seed IS. Absent (`??`) means "cpu".
    readonly property var metrics: ["cpu", "memory", "temp"]
    property int metricIdx: Math.max(0, root.metrics.indexOf(root.opts.metric ?? "cpu"))
    readonly property string metric: root.metrics[root.metricIdx % root.metrics.length]

    function tileTap() {
        if (root.size === "small")
            root.metricIdx = (root.metricIdx + 1) % root.metrics.length
        else
            UiState.openSettingsTo("AboutPage.qml")
    }

    readonly property bool tempKnown: SysInfo.hasCpuTemp
    // 0..1 for the ring. Temperature is scaled against 100°C — a DISPLAY scale, not a
    // limit or a throttle point; it is there so the ring has somewhere to travel, and
    // the number beside it is the truth.
    readonly property real gaugeValue:
        root.metric === "cpu"    ? SysInfo.cpu
      : root.metric === "memory" ? SysInfo.memFraction
      : (root.tempKnown ? Math.max(0, Math.min(1, SysInfo.cpuTemp / 100)) : 0)

    // ── The reading, per metric ───────────────────────────────────────────────
    // Functions of the metric, not of `metric`, so the face can keep showing the OLD
    // metric's reading while it fades out (below) and still follow its live value.
    function readoutOf(m) {
        return m === "cpu"    ? Math.round(SysInfo.cpu * 100) + "%"
             : m === "memory" ? Math.round(SysInfo.memFraction * 100) + "%"
             : (root.tempKnown ? SysInfo.cpuTemp + "°C" : "—")
    }
    function labelOf(m) {
        return m === "cpu" ? "CPU" : m === "memory" ? "MEMORY" : "CPU TEMP"
    }

    // ── Changing metric is a swap, not a rewrite ──────────────────────────────
    // Tapping from CPU to memory used to hand the same figure a new string: its digits
    // rolled one by one into a different number while the label cut from "CPU" to
    // "MEMORY" — two kinds of motion for one change. Now the whole reading (figure and
    // label together) shrinks and lifts away, and the next one grows in from below, while
    // the ring sweeps to its new value underneath. Digit-rolling is kept for what it is
    // right for: the SAME metric ticking over.
    //
    // `shownMetric` is the held copy that makes the fade-out possible (SwapFade).
    property string shownMetric: ""

    // ══ SMALL — one metric, big ═══════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "small"
        spacing: Tokens.spacingXs

        Item { Layout.fillHeight: true }

        RadialGauge {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 104; implicitHeight: 104
            thickness: 10
            value: root.gaugeValue
            accent: root.accent
            // Settles into each sample and rests — a live readout, not a UI move.
            sampleInterval: SysInfo.interval
            // Material 3 Expressive's wavy indicator (still at rest; see RadialGauge).
            wavy: true

            // The hero: a tonal disc whose SHAPE is the metric — a cookie for the CPU, a
            // squircle (a chip of memory) for memory, a sun for heat. A tap morphs it as the
            // reading swaps, so the change of metric is something you see happen, not just
            // a word that changes under the number.
            MorphShape {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXs
                shape: root.shownMetric === "memory" ? "squircle"
                     : root.shownMetric === "temp"   ? "sunny" : "cookie9"
                spec: Motion.springSpatialFast
                fillColor: Colors.of(QsWindow.window).primaryContainer
            }

            ColumnLayout {
                id: face
                anchors.centerIn: parent
                spacing: -2

                SwapFade {
                    target: face
                    key: root.metric
                    shownKey: root.shownMetric
                    travel: Tokens.spacingMd
                    dip: 0.82
                    onSwapped: root.shownMetric = root.metric
                }

                // Rolls a digit at a time while the metric stays the same.
                RollText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.readoutOf(root.shownMetric)
                    pixelSize: Tokens.fontDisplay
                    weight: Font.Bold
                    color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.labelOf(root.shownMetric)
                    variant: "caption"
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)
                    font.letterSpacing: 1
                }
            }
        }

        // Which metric a tap will show next: the current one stretches into a pill, the
        // others rest as dots. The width springs, so a tap reads as the pill sliding on.
        Row {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacingSm
            spacing: Tokens.spacingXs

            Repeater {
                model: root.metrics.length

                Rectangle {
                    id: pip
                    required property int index
                    readonly property bool current: pip.index === root.metricIdx % root.metrics.length
                    SpringValue {
                        id: pipW
                        spec: Motion.springSpatialFast
                        epsilon: 0.05
                        target: pip.current ? Tokens.spacingXl : Tokens.spacingSm
                    }
                    width:  pipW.value
                    height: Tokens.spacingSm
                    radius: height / 2
                    color: pip.current ? root.accent
                                       : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.25)

                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    // ══ MEDIUM / LARGE — the CPU ring, a stat list, and the trace ═════════════
    ColumnLayout {
        anchors.fill: parent
        visible: root.size !== "small"
        spacing: Tokens.spacingSm

        WidgetHeader {
            glyph:  "󰍛"
            title:  Translation.tr("System")
            accent: root.accent

            MaterialIcon {
                glyph: "\u{F03CC}"   // open-in-new — the tap opens the System page
                variant: "caption"
                emphasis: "dim"
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingLg

            RadialGauge {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 88; implicitHeight: 88
                thickness: 10
                value: SysInfo.cpu
                accent: root.accent
                sampleInterval: SysInfo.interval
                wavy: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: -2
                    RollText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Math.round(SysInfo.cpu * 100) + "%"
                        pixelSize: Tokens.fontHeadline
                        weight: Font.Bold
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
                    label: Translation.tr("Memory")
                    value: Math.round(SysInfo.memFraction * 100) + "%"
                }
                Stat {
                    label: Translation.tr("CPU temp")
                    value: SysInfo.hasCpuTemp ? SysInfo.cpuTemp + "°C" : "—"
                }
                Stat {
                    label: SysInfo.hasGpu ? "GPU" : "GPU temp"
                    value: SysInfo.hasGpu
                           ? Math.round(SysInfo.gpu * 100) + "%"
                           : (SysInfo.hasGpuTemp ? SysInfo.gpuTemp + "°C" : "—")
                }
            }
        }

        // ── The last minute ──────────────────────────────────────────────────
        Sparkline {
            Layout.fillWidth: true
            Layout.preferredHeight: 26
            visible: root.size === "large"
            values: SysInfo.history
            accent: root.accent
            curved: true
        }

        // ── Per-core CPU, large only ─────────────────────────────────────────
        // One bar per logical core — the aggregate percentage hides whether the
        // load is one pinned thread or spread across everything.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: 22
            visible: root.size === "large" && (SysInfo.cores?.length ?? 0) > 0
            spacing: 3

            Repeater {
                model: SysInfo.cores ?? []
                Rectangle {
                    id: coreCell
                    required property var modelData
                    readonly property real lvl: Math.max(0, Math.min(1, coreCell.modelData))
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.09)

                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        // A visible sliver even at idle, so the strip reads as N cores
                        // rather than an empty bar with a couple of spikes.
                        height: Math.max(2, parent.height * coreCell.lvl)
                        radius: 2
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.accent, 0.95) }
                            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.accent, 0.40) }
                        }
                        Behavior on height {
                            NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve }
                        }
                    }
                }
            }
        }
    }

    // One reading as a soft pill: the name quiet on the left, the figure on the right.
    component Stat: Rectangle {
        id: stat
        property string label: ""
        property string value: ""
        Layout.fillWidth: true
        implicitHeight: statRow.implicitHeight + Tokens.spacingSm * 2
        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
        color: Colors.of(QsWindow.window).surfaceHigh

        RowLayout {
            id: statRow
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            StyledText { Layout.fillWidth: true; text: stat.label; variant: "caption"; emphasis: "dim" }
            // A reading that ticks over rolls, as the ring's figure does, instead of cutting.
            RollText {
                text: stat.value
                pixelSize: Tokens.fontCaption
                weight: Font.Bold
            }
        }
    }
}
