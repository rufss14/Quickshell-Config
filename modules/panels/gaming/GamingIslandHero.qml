pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── GamingIslandHero ── part of GamingPanel.qml (island form); `panel` is the GamingPanel. ──────────────────────
// The game mode page's loud card on an island, upright in the left column (the other pages' recipe), in place of
// the Play page's hero, tiles and gauges (2026-11-15):
//
//   top     the mode as a shape (a plain disc off, a nine-petal cookie that turns slowly while on, two rings sent
//           off it as it turns on; a burst in the warning tone when it is on but did not tune), its name, its line
//   middle  the number: this session while on, the last one while off; under it the week as seven blocky
//           columns, today in the accent, with today and the week written beside
//   lower   what the machine is doing: GPU, CPU, VRAM, RAM as four short blocky bars with their figures;
//           swapping, said only when it is happening
//   foot    the one button: Turn on / Turn off
//
// The running game's picture (Steam's header) sits behind the top of the card while it is on and fades into it.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool stalled: hero.panel._stalled
    readonly property color ink: hero.palette.fgOnPrimaryContainer
    readonly property color inkDim: hero.palette.alpha(hero.palette.fgOnPrimaryContainer, 0.72)
    readonly property color tone: hero.stalled ? hero.palette.warning : hero.palette.primary

    radius: Tokens.radiusXl
    color: hero.stalled ? hero.palette.mix(hero.palette.primaryContainer, hero.palette.warning, 0.24)
                        : hero.palette.primaryContainer
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    // ── The game's picture, behind the top ────────────────────────────────────
    ClippingRectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height * 0.5
        topLeftRadius: hero.radius
        topRightRadius: hero.radius
        color: "transparent"
        opacity: Gamemode.active && art.status === Image.Ready ? 0.55 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.slow } }
        Image {
            id: art
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize.width: 640
            source: Gamemode.gameArt !== "" ? "file://" + Gamemode.gameArt : ""
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: hero.palette.alpha(hero.color, 0.2) }
                GradientStop { position: 1.0; color: hero.color }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm

        // ── The mode ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingLg
                implicitHeight: implicitWidth
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: ring
                        required property int index
                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: Tokens.borderWidth * 2
                        border.color: hero.tone
                        opacity: 0
                        SequentialAnimation {
                            id: ringAnim
                            PauseAnimation { duration: ring.index * Motion.respond * 2 }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.7; duration: Motion.ripple; easing.type: Motion.travel }
                                NumberAnimation { target: ring; property: "opacity"; from: 0.55; to: 0; duration: Motion.ripple }
                            }
                        }
                        Connections {
                            target: Gamemode
                            function onActiveChanged() { if (Gamemode.active && Config.motionEnabled) ringAnim.restart() }
                        }
                    }
                }
                Item {
                    anchors.fill: parent
                    RotationAnimator on rotation {
                        running: Gamemode.active && Motion.ambientOn
                        from: 0; to: 360
                        duration: Motion.glide * 40
                        loops: Animation.Infinite
                    }
                    MorphShape {
                        anchors.fill: parent
                        shape: hero.stalled ? "burst" : Gamemode.active ? "cookie9" : "circle"
                        spec: Motion.springSpatialFast
                        fillColor: Gamemode.active || hero.stalled ? hero.tone : hero.palette.alpha(hero.ink, 0.14)
                        Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: Gamemode.active ? "sports_esports" : "videogame_asset_off"
                    fill: Gamemode.active ? 1 : 0
                    color: Gamemode.active || hero.stalled ? hero.palette.fgOnPrimary : hero.ink
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: hero.panel._heroTitle
                    variant: "title"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: hero.panel._heroLine
                    variant: "caption"
                    color: hero.inkDim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ── The number ────────────────────────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            text: Gamemode.active ? (hero.panel._elapsed === "just started" ? Translation.tr("< 1 m") : hero.panel._elapsed)
                : Gamemode.lastSeconds >= 60 ? Gamemode.duration(Gamemode.lastSeconds) : Translation.tr("Off")
            font.pixelSize: Tokens.fontDisplay * 1.6
            font.weight: Font.Bold
            font.features: ({ tnum: 1 })
            color: hero.ink
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: -Tokens.spacingXs
            text: Gamemode.active ? Translation.tr("this session")
                : Gamemode.lastSeconds >= 60 ? Translation.tr("last session") : Translation.tr("no session yet")
            variant: "caption"
            color: hero.inkDim
        }

        // ── The week ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingXs
            spacing: Tokens.spacingMd
            Row {
                id: week
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingSm
                spacing: Tokens.spacingXs
                readonly property real peak: Math.max(60, Gamemode.weekDays.reduce((m, d) => Math.max(m, d.seconds), 0))
                readonly property real colW: (week.width - week.spacing * 6) / 7
                Repeater {
                    model: Gamemode.weekDays
                    delegate: Item {
                        id: day
                        required property var modelData
                        width: week.colW
                        height: week.height
                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            height: Math.max(Tokens.spacingXs * 2, day.modelData.seconds / week.peak * day.height)
                            radius: Math.max(1, Math.round(Math.min(width, height) * 0.3))
                            color: day.modelData.today ? hero.tone : hero.palette.alpha(hero.ink, 0.22)
                            Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                        }
                    }
                }
            }
            ColumnLayout {
                Layout.fillHeight: false
                spacing: 0
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: Gamemode.weekSeconds >= 60 ? Gamemode.duration(Gamemode.weekSeconds) : Translation.tr("0 m")
                    variant: "label"
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: hero.ink
                }
                StyledText {
                    Layout.alignment: Qt.AlignRight
                    text: Translation.tr("%1 today").arg(Gamemode.todaySeconds >= 60 ? Gamemode.duration(Gamemode.todaySeconds) : Translation.tr("0 m"))
                    variant: "micro"
                    color: hero.inkDim
                }
            }
        }

        // ── The machine ───────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingXs
            columns: 2
            columnSpacing: Tokens.spacingMd
            rowSpacing: Tokens.spacingXs
            uniformCellWidths: true
            Repeater {
                model: [
                    { t: "GPU",  f: SysInfo.gpu,          v: Math.round(SysInfo.gpu * 100) + "%" + (SysInfo.hasGpuTemp ? " · " + SysInfo.gpuTemp + "°" : ""), show: SysInfo.hasGpu },
                    { t: "CPU",  f: SysInfo.cpu,          v: Math.round(SysInfo.cpu * 100) + "%" + (SysInfo.hasCpuTemp ? " · " + SysInfo.cpuTemp + "°" : ""), show: true },
                    { t: "VRAM", f: SysInfo.vramFraction, v: SysInfo.vramUsed.toFixed(1) + " / " + SysInfo.vramTotal.toFixed(0) + " GB", show: SysInfo.hasGpu && SysInfo.vramTotal > 0 },
                    { t: "RAM",  f: SysInfo.memFraction,  v: SysInfo.memUsed.toFixed(1) + " / " + SysInfo.memTotal.toFixed(0) + " GB", show: true }
                ]
                delegate: ColumnLayout {
                    id: gauge
                    required property var modelData
                    readonly property color fillTone: gauge.modelData.f > 0.9 ? hero.palette.danger
                        : gauge.modelData.f > 0.8 ? hero.palette.warning : hero.tone
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: gauge.modelData.show
                    spacing: 2
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            text: gauge.modelData.t
                            variant: "micro"
                            font.weight: Font.DemiBold
                            color: hero.inkDim
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: gauge.modelData.v
                            variant: "micro"
                            font.features: ({ tnum: 1 })
                            color: hero.ink
                        }
                    }
                    Item {
                        id: track
                        Layout.fillWidth: true
                        implicitHeight: Tokens.spacingSm
                        readonly property real r: Math.max(1, Math.round(track.height * 0.3))
                        Rectangle {
                            anchors.fill: parent
                            radius: track.r
                            color: hero.palette.alpha(hero.ink, 0.14)
                        }
                        Rectangle {
                            width: Math.max(track.height, track.width * Math.min(1, Math.max(0, gauge.modelData.f)))
                            height: track.height
                            radius: track.r
                            color: gauge.fillTone
                            Behavior on width { NumberAnimation { duration: Math.min(SysInfo.interval, Motion.settle); easing.type: Motion.travel } }
                        }
                    }
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: SysInfo.swapTotal > 0 && SysInfo.swapUsed > 0.1
            spacing: Tokens.spacingXs
            MaterialIcon { name: "warning"; fill: 1; color: hero.palette.warning; font.pixelSize: Tokens.iconSm }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Swapping %1 GB, expect stutter").arg(SysInfo.swapUsed.toFixed(1))
                variant: "micro"
                font.weight: Font.DemiBold
                color: hero.ink
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        // ── The button ────────────────────────────────────────────────────────
        ChipButton {
            Layout.fillWidth: true
            solid: !Gamemode.active
            tonal: Gamemode.active
            tint: Gamemode.active ? hero.ink : hero.palette.primary
            symbol: "power_settings_new"
            label: Gamemode.active ? Translation.tr("Turn off") : Translation.tr("Turn on")
            onActivated: Gamemode.toggle()
        }
    }
}
