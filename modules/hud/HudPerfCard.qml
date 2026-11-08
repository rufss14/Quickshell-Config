pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H

// ── HudPerfCard ───────────────────────────────────────────────────────────────
// Performance, under the workspaces: CPU, GPU and memory as three RINGS — the desktop
// Sysmon's language (RadialGauge, the figure rolling in the hole), the name and the
// temperature (or the memory in GB) under each — and, on the ring's track, a small dot at
// the last minute's PEAK, so a spike that has passed still shows where it reached. Beside
// them, the game-side levers in a column: MangoHud's frame cap and Game mode.
// (2026-10-20, third version, the user's pick: three meter rows over sparklines "still"
// didn't look right; before that, three 72px gauges and a shared trace were twice the size.)
// The readouts are SysStats.readout, the same as the sidebar's and the stats panel's, so
// the three can't disagree. Holds SysInfo while it exists (the cards are built only while
// the overview is open).
// ─────────────────────────────────────────────────────────────────────────────
HudCard {
    id: root
    wid: "stats"

    Component.onCompleted: SysInfo.acquire()
    Component.onDestruction: SysInfo.release()

    readonly property var keys: SysInfo.hasGpu ? ["cpu", "gpu", "ram"] : ["cpu", "ram"]

    // ── The card says it in a sentence ────────────────────────────────────────
    // "VRAM 2.8 / 12 GB · disk 0%" was for someone who already reads those. The status line is the verdict now (hud.js
    // perfVerdict: fine / warm / busy / hot / memory), coloured by how much it matters; the figures it used to carry are
    // on hover (each ring's tip) and in the rings' captions.
    readonly property var verdict: H.perfVerdict({
        cpu: SysStats.readout("cpu").ratio,
        gpu: SysInfo.hasGpu ? SysStats.readout("gpu").ratio : 0,
        ram: SysStats.readout("ram").ratio,
        cpuTemp: SysInfo.hasCpuTemp ? SysInfo.cpuTemp : -1,
        gpuTemp: SysInfo.hasGpuTemp ? SysInfo.gpuTemp : -1,
        swap: SysInfo.swapUsed
    })
    statusLevel: root.verdict.level
    status: Translation.tr(root.verdict.text) + (SysInfo.swapUsed >= 0.5 ? " · " + Translation.tr("swap in use") : "")

    // The rings share what the column leaves; never taller than the body less their caption.
    readonly property real colW: Tokens.sideCardUnit * 4
    readonly property real captionH: Tokens.fontLabel + Tokens.spacingSm
    readonly property real ringSize: Math.floor(Math.max(Tokens.sideCardUnit,
        Math.min(root.bodyHeight - root.captionH - Tokens.spacingXs,
                 (root.width - Tokens.spacingLg * 3 - root.colW - Tokens.spacingMd * (root.keys.length - 1)) / root.keys.length)))

    // ── The rings ─────────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        implicitWidth: rings.implicitWidth

        Row {
            id: rings
            anchors.centerIn: parent
            spacing: Tokens.spacingMd

            Repeater {
                model: root.keys

                Column {
                    id: metric
                    required property string modelData
                    required property int index
                    readonly property var r: SysStats.readout(metric.modelData)
                    readonly property color tone: metric.modelData === "gpu" ? root.pal.primary
                                                : metric.modelData === "ram" ? root.pal.fg : root.accent
                    readonly property string side: metric.modelData === "cpu" && SysInfo.hasCpuTemp ? SysInfo.cpuTemp + "°"
                        : metric.modelData === "gpu" && SysInfo.hasGpuTemp ? SysInfo.gpuTemp + "°"
                        : metric.modelData === "ram" && SysInfo.memTotal > 0
                            ? Math.round(SysInfo.memUsed) + "/" + Math.round(SysInfo.memTotal) + " GB" : ""
                    // The last minute's highest, for the peak dot.
                    readonly property real peak: {
                        const h = metric.r.history ?? []
                        let m = 0
                        for (let i = 0; i < h.length; i++) if (h[i] > m) m = h[i]
                        return Math.max(0, Math.min(1, m))
                    }

                    spacing: Tokens.spacingXs

                    // Each ring arrives a beat after the one before (its own PopIn — the
                    // card's is the card's), sweeping up from empty.
                    PopIn { id: ringPop; active: root.running; index: metric.index; delay: Motion.fast }
                    opacity: ringPop.opacity
                    scale: ringPop.scale

                    RadialGauge {
                        id: gauge
                        width: root.ringSize
                        height: root.ringSize
                        thickness: Math.max(5, Math.round(root.ringSize * 0.09))
                        // Empty until the ring has popped in, then the gauge's own ease sweeps it
                        // up — a flip, not a value following the spring, which its Behavior would chase.
                        value: ringPop.arrive > 0.3 ? metric.r.ratio : 0
                        accent: metric.tone
                        sampleInterval: SysInfo.interval

                        // The detail that used to crowd the status line, one hover away: the part's name and facts.
                        HoverTip {
                            text: [metric.r.name].concat((metric.r.rows ?? []).map(x => x.text)).filter(t => t).join("\n")
                        }

                        Row {
                            anchors.centerIn: parent
                            RollText {
                                anchors.bottom: parent.bottom
                                text: metric.r.short
                                pixelSize: Math.round(Math.min(Tokens.fontHeadline, root.ringSize * 0.24))
                                weight: Font.Bold
                                family: Tokens.fontMono
                            }
                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                                text: "%"
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }

                        // The peak: a dot on the track where the last minute reached.
                        Item {
                            anchors.fill: parent
                            visible: metric.peak > metric.r.ratio + 0.03
                            rotation: 360 * metric.peak
                            Behavior on rotation { NumberAnimation { duration: Motion.settle; easing.type: Motion.travel } }
                            Rectangle {
                                x: (parent.width - width) / 2
                                y: (gauge.thickness - height) / 2
                                width: Math.max(4, gauge.thickness * 0.6)
                                height: width
                                radius: width / 2
                                color: metric.tone
                                opacity: 0.7
                            }
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: root.captionH
                        spacing: Tokens.spacingXs
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: metric.modelData === "ram" ? Translation.tr("RAM") : metric.r.label
                            variant: "caption"
                            emphasis: "muted"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: metric.side !== ""
                            text: metric.side
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                    }
                }
            }
        }
    }

    // ── Frame cap and Game mode ───────────────────────────────────────────────
    // "No cap set" (no fps_limit line, -1) and "Uncapped" (fps_limit=0) both run free, so
    // both light ∞; a cap that isn't a preset gets a segment of its own rather than
    // lighting the wrong one. Gamemode owns MangoHud.conf (services/mangohud.js); without
    // a MangoHud config the switch is off and the status line says where to make one.
    ColumnLayout {
        id: fps
        // A layout's fillWidth defaults to TRUE, and with it this column took the whole
        // row and pushed the rings out of the card (2026-10-20's screenshot).
        Layout.preferredWidth: root.colW
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        readonly property bool ok: Gamemode.mangohudConfigured
        readonly property int cap: Math.max(0, Gamemode.mangohudFps)
        readonly property var presets: {
            // Four segments fit the column with their numbers; a 144 (or any other cap the config holds) gets its own below.
            const p = [30, 60, 120]
            if (fps.cap > 0 && p.indexOf(fps.cap) < 0) p.push(fps.cap)
            p.sort((a, b) => a - b)
            p.push(0)
            return p
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            MaterialIcon {
                name: "speed"
                color: fps.ok ? root.accent : root.pal.fgMuted
                font.pixelSize: Tokens.iconSm
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Max FPS")
                variant: "caption"
                emphasis: "muted"
                font.weight: Font.DemiBold
                // What it is, and — when it can't be used — why, one hover away instead of a status line.
                HoverTip {
                    text: fps.ok
                        ? Translation.tr("Stops games drawing more frames per second than you pick, which saves power and heat. ∞ leaves them free.")
                        : Translation.tr("Needs a MangoHud preset: pick one in Settings › Gaming first.")
                }
            }
        }
        SegmentSwitch {
            Layout.fillWidth: true
            accent: root.accent
            model: fps.presets.map(n => ({ value: n, label: n === 0 ? "∞" : String(n) }))
            current: fps.cap
            enabled: fps.ok
            opacity: fps.ok ? 1 : 0.45
            onPicked: function (value) { Gamemode.setMangohudFps(value) }
        }
        ChipButton {
            Layout.fillWidth: true
            symbol: "bolt"
            label: Gamemode.active ? Translation.tr("Game mode on") : Translation.tr("Game mode")
            on: Gamemode.active
            tint: root.accent
            enabled: Gamemode.toolsAvailable
            onActivated: Gamemode.toggle()
            HoverTip {
                text: Translation.tr("One switch for playing: stops the screen blanking and notifications, puts the CPU on performance and pauses effects nobody can see.")
            }
        }
    }
}
