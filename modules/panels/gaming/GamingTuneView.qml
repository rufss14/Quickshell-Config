pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/gamemodewatch.js" as Watch

// ── GamingTuneView ── part of GamingPanel.qml; `panel` is the GamingPanel it belongs to. ──
ColumnLayout {
    id: tunePage
    required property var panel
    readonly property int idx: 2
    width: panel.pagesBox.width
    x: (tunePage.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(tunePage.idx - panel.pg.value) * 1.4)
    visible: tunePage.opacity > 0.01
    spacing: Tokens.spacingSm

    // ── CPU governor — a direct pick, not a gamemode hold ─────────
    // The user reaching for the same `cpugovctl` helper gamemoded itself uses, directly and
    // persistently (services/Gamemode.qml has the polkit story) — nothing reverts it, because
    // nothing promised to. Locked while a session holds the governor: a manual click would
    // fight gamemoded's own restore when it ends. Only offered where the helper exists; the
    // readout stays on any box with cpufreq regardless.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: govCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: govCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd
                ShapeBox {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.iconXl + Tokens.spacingSm
                    implicitHeight: implicitWidth
                    fallback: "rounded"
                    fillColor: Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                    strokeColor: "transparent"
                    MaterialIcon { anchors.centerIn: parent; name: "speed"; fill: 1; color: panel.accent; font.pixelSize: Tokens.iconMd }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText { text: "CPU governor"; variant: "body"; font.weight: Font.Medium }
                    StyledText {
                        Layout.fillWidth: true
                        text: Gamemode.active ? "Held by game mode until it ends"
                            : (panel._govAbout[Gamemode.cpuGovernor] ?? "How the CPU picks its clock speed")
                        variant: "caption"; emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                StyledText {
                    visible: Gamemode.cpuGovernor !== ""
                    text: Gamemode.cpuGovernor
                    variant: "label"
                    color: Gamemode.cpuGovernor === "performance" ? Colors.of(QsWindow.window).success : panel.accent
                }
            }
            SegmentSwitch {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: implicitHeight
                visible: Gamemode.toolsAvailable && Gamemode.governorChoices.length > 0
                accent: panel.accent
                model: Gamemode.governorChoices
                current: Gamemode.cpuGovernor
                enabled: !Gamemode.active
                opacity: Gamemode.active ? 0.45 : 1.0
                onPicked: function (value) { Gamemode.setGovernor(value) }
            }
            StyledText {
                Layout.fillWidth: true
                visible: !Gamemode.toolsAvailable
                text: Translation.tr("Install gamemode for governor control.")
                variant: "caption"; emphasis: "dim"
            }
        }
    }

    // ── Frame cap — the HUD's FPS widget, here too ────────────────
    // One `fps_limit=` line in MangoHud.conf (Gamemode.setMangohudFps). Needs a preset first: a
    // config holding only fps_limit would replace MangoHud's default readout with an empty one.
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: capCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: capCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd
                ShapeBox {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: Tokens.iconXl + Tokens.spacingSm
                    implicitHeight: implicitWidth
                    fallback: "rounded"
                    fillColor: Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                    strokeColor: "transparent"
                    MaterialIcon { anchors.centerIn: parent; name: "timer"; fill: 1; color: panel.accent; font.pixelSize: Tokens.iconMd }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0
                    StyledText { text: "Frame cap"; variant: "body"; font.weight: Font.Medium }
                    StyledText {
                        Layout.fillWidth: true
                        text: !capSwitch.ok ? (Gamemode.mangohudAvailable ? "Pick an overlay preset below first — the cap lives in its config"
                                                                          : "Install mangohud for a frame cap")
                            : capSwitch.cap === 0 ? "Games draw as fast as they can"
                            : "Capped at " + capSwitch.cap + " fps — less heat, steadier frames"
                        variant: "caption"; emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                StyledText {
                    visible: capSwitch.ok
                    text: capSwitch.cap === 0 ? "∞" : capSwitch.cap + " fps"
                    variant: "label"
                    color: panel.accent
                }
            }
            SegmentSwitch {
                id: capSwitch
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: implicitHeight
                readonly property int cap: Math.max(0, Gamemode.mangohudFps)
                readonly property bool ok: Gamemode.mangohudConfigured
                accent: panel.accent
                // A cap the config already holds (a 144, say) gets its own segment.
                model: {
                    const p = [0, 30, 60, 120]
                    if (capSwitch.cap > 0 && p.indexOf(capSwitch.cap) < 0) { p.push(capSwitch.cap); p.sort((a, b) => a - b) }
                    return p.map(n => ({ value: n, label: n === 0 ? "∞" : String(n) }))
                }
                current: capSwitch.cap
                enabled: capSwitch.ok
                opacity: capSwitch.ok ? 1.0 : 0.45
                onPicked: function (value) { Gamemode.setMangohudFps(value) }
            }
        }
    }

    // ── MangoHud overlay preset, with a preview ───────────────────
    // Chips, not a switch: a hand-written config carries no preset marker, and then none of
    // them should look chosen. The stage shows what the overlay will draw — the real preset's
    // lines (scripts/generate-mangohud-config), with YOUR machine's live numbers, the frame cap as
    // the frame rate, and a frame-time graph that ticks. Pointing at a chip previews it before you
    // pick; the colours are the palette's, an approximation of the config's wal colours.
    Rectangle {
        id: hudCard
        Layout.fillWidth: true
        visible: Gamemode.mangohudAvailable
        implicitHeight: hudRow.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        property string hoverKey: ""
        readonly property string previewKey: hudCard.hoverKey !== "" ? hudCard.hoverKey
                                           : Gamemode.mangohudPreset !== "" ? Gamemode.mangohudPreset : "full"
        property int phase: 0
        readonly property color cFps: Colors.of(QsWindow.window).success
        readonly property color cGpu: panel.accent
        readonly property color cCpu: Colors.of(QsWindow.window).info
        readonly property color cMem: Colors.of(QsWindow.window).warning
        readonly property int fps: Gamemode.mangohudFps > 0 ? Gamemode.mangohudFps : 144
        // Each line is a list of [text, colour] runs; "graph" is the frame-time graph.
        readonly property var lines: {
            const k = hudCard.previewKey
            if (k === "off") return []
            const gpu = Math.round(SysInfo.gpu * 100) + "%" + (SysInfo.hasGpuTemp ? "  " + SysInfo.gpuTemp + "°C" : "")
            const cpu = Math.round(SysInfo.cpu * 100) + "%" + (SysInfo.hasCpuTemp ? "  " + SysInfo.cpuTemp + "°C" : "")
            const fg = Colors.of(QsWindow.window).fg
            const fpsLine = [["FPS ", hudCard.cFps], [String(hudCard.fps), fg], ["  " + (1000 / hudCard.fps).toFixed(1) + " ms", Colors.of(QsWindow.window).fgMuted]]
            const gpuLine = [["GPU ", hudCard.cGpu], [gpu, fg]]
            const cpuLine = [["CPU ", hudCard.cCpu], [cpu, fg]]
            const vram = [["VRAM ", hudCard.cMem], [SysInfo.vramUsed.toFixed(1) + "G", fg]]
            const ram = [["RAM ", hudCard.cMem], [SysInfo.memUsed.toFixed(1) + "G", fg]]
            if (k === "fps")     return [fpsLine, "graph"]
            if (k === "compact") return [fpsLine, "graph", gpuLine, cpuLine, vram.concat([["  ", fg]], ram)]
            return [fpsLine, "graph", gpuLine, vram, cpuLine, ram,
                    [["SWAP ", hudCard.cMem], [SysInfo.swapUsed.toFixed(1) + "G", fg]]]
        }
        Timer {
            interval: 140
            repeat: true
            running: panel.page === "tune" && hudCard.visible && hudCard.previewKey !== "off" && Config.motionEnabled
            onTriggered: hudCard.phase++
        }

        RowLayout {
            id: hudRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingLg

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    ShapeBox {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Tokens.iconXl + Tokens.spacingSm
                        implicitHeight: implicitWidth
                        fallback: "rounded"
                        fillColor: Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                        strokeColor: "transparent"
                        MaterialIcon { anchors.centerIn: parent; name: "equalizer"; fill: 1; color: panel.accent; font.pixelSize: Tokens.iconMd }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText { text: "MangoHud overlay"; variant: "body"; font.weight: Font.Medium }
                        StyledText {
                            Layout.fillWidth: true
                            text: panel._overlayAbout[hudCard.previewKey] ?? ""
                            variant: "caption"; emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: [
                            { key: "full",    label: "Full",    symbol: "tune" },
                            { key: "compact", label: "Compact", symbol: "speed" },
                            { key: "fps",     label: "FPS",     symbol: "timer" },
                            { key: "off",     label: "Off",     symbol: "visibility_off" },
                        ]
                        delegate: ChipButton {
                            id: presetChip
                            required property var modelData
                            symbol: modelData.symbol
                            label: modelData.label
                            on: Gamemode.mangohudPreset === modelData.key
                            solid: on
                            tint: panel.accent
                            onActivated: Gamemode.setMangohudPreset(modelData.key)
                            HoverHandler {
                                onHoveredChanged: {
                                    if (hovered) hudCard.hoverKey = presetChip.modelData.key
                                    else if (hudCard.hoverKey === presetChip.modelData.key) hudCard.hoverKey = ""
                                }
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("In a game: Shift_R + F12 toggles it · Shift_L + F4 reloads the config")
                    variant: "caption"; emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }

            // ── The stage: a game-ish backdrop with the overlay drawn on it ──────────
            Rectangle {
                id: stage
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.sideCardUnit * 4.6
                Layout.preferredHeight: Tokens.sideCardUnit * 3.1
                radius: Tokens.radiusSm
                clip: true
                gradient: Gradient {
                    GradientStop { position: 0; color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surface, panel.accent, 0.30) }
                    GradientStop { position: 1; color: Colors.of(QsWindow.window).surface }
                }
                MorphShape {
                    x: stage.width * 0.52; y: stage.height * 0.38
                    width: stage.height * 0.9; height: width
                    shape: "cookie9"
                    fillColor: Colors.of(QsWindow.window).alpha(panel.accent, 0.16)
                }
                StyledText {
                    anchors.centerIn: parent
                    text: Translation.tr("No overlay")
                    variant: "caption"; emphasis: "dim"
                    opacity: hudCard.previewKey === "off" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                }

                // MangoHud's own look: a translucent dark plate (background_alpha 0.4), corners
                // rounded. It grows and shrinks to its lines on the house curve.
                Rectangle {
                    x: Tokens.spacingSm; y: Tokens.spacingSm
                    width: overlayCol.implicitWidth + Tokens.spacingMd * 2
                    height: overlayCol.implicitHeight + Tokens.spacingMd * 2
                    radius: Tokens.radiusSm
                    clip: true
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.5)
                    opacity: hudCard.previewKey === "off" ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    Behavior on width  { NumberAnimation { duration: Motion.spatial; easing.type: Motion.expressive } }
                    Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Motion.expressive } }

                    Column {
                        id: overlayCol
                        x: Tokens.spacingMd; y: Tokens.spacingMd
                        spacing: 1

                        Repeater {
                            model: hudCard.lines
                            delegate: Item {
                                id: ln
                                required property var modelData
                                readonly property bool isGraph: ln.modelData === "graph"
                                width: ln.isGraph ? graphRow.implicitWidth : runRow.implicitWidth
                                height: ln.isGraph ? Tokens.spacingLg : runRow.implicitHeight

                                Row {
                                    id: runRow
                                    visible: !ln.isGraph
                                    Repeater {
                                        model: ln.isGraph ? [] : ln.modelData
                                        delegate: StyledText {
                                            required property var modelData
                                            text: modelData[0]
                                            color: modelData[1]
                                            font.family: Tokens.fontMono
                                            font.pixelSize: Tokens.fontMicro
                                            font.weight: Font.DemiBold
                                        }
                                    }
                                }
                                // Frame time: bars that wander around the target, one step per tick.
                                Row {
                                    id: graphRow
                                    visible: ln.isGraph
                                    anchors.bottom: parent.bottom
                                    spacing: 1
                                    Repeater {
                                        model: ln.isGraph ? 20 : 0
                                        delegate: Rectangle {
                                            required property int index
                                            width: 3
                                            height: Math.round(Tokens.spacingSm + Tokens.spacingXs * 2
                                                    * (0.5 + 0.5 * Math.sin((index + hudCard.phase) * 0.9) * Math.cos((index + hudCard.phase) * 0.37)))
                                            // Guarded: a delegate is unparented while the panel tears down,
                                            // and `parent.bottom` then threw once per bar (20 × 3 per close).
                                            anchors.bottom: parent ? parent.bottom : undefined
                                            radius: 1
                                            color: hudCard.cFps
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
