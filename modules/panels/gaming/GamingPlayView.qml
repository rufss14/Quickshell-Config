pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/gamemodewatch.js" as Watch

// ── GamingPlayView ── part of GamingPanel.qml; `panel` is the GamingPanel it belongs to. ──
ColumnLayout {
    id: playPage
    required property var panel
    readonly property int idx: 0
    width: panel.pagesBox.width
    x: (playPage.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(playPage.idx - panel.pg.value) * 1.4)
    visible: playPage.opacity > 0.01
    spacing: Tokens.spacingSm

    // ── Hero: the mode itself ─────────────────────────────────────
    Rectangle {
        id: hero
        Layout.fillWidth: true
        implicitHeight: heroRow.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusXl
        color: panel._stalled ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer,
                                                               Colors.of(QsWindow.window).warning, 0.26)
             : Gamemode.active ? Colors.of(QsWindow.window).primaryContainer
             :                   Colors.of(QsWindow.window).section
        Behavior on color { ColorAnimation { duration: Motion.standard } }

        readonly property color ink: panel._stalled || !Gamemode.active ? Colors.of(QsWindow.window).fg
                                                                        : Colors.of(QsWindow.window).fgOnPrimaryContainer

        // The running game's picture (Steam's own header, from its library cache), under the
        // row: it fills the right of the hero and fades into the hero colour on its left, so the
        // text stays on plain colour. Only while the mode is on and a picture exists.
        ClippingRectangle {
            id: artClip
            anchors.fill: parent
            radius: hero.radius
            color: "transparent"
            opacity: Gamemode.active && art.status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.slow } }

            Image {
                id: art
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * 0.66
                fillMode: Image.PreserveAspectCrop
                horizontalAlignment: Image.AlignLeft
                sourceSize.width: 720
                source: Gamemode.gameArt !== "" ? "file://" + Gamemode.gameArt : ""
            }
            Rectangle {
                anchors.fill: art
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: hero.color }
                    GradientStop { position: 0.75; color: Colors.of(QsWindow.window).alpha(hero.color, 0) }
                }
            }
        }

        RowLayout {
            id: heroRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingLg

            // The mode as a shape: a plain disc at rest, a nine-petal cookie while it is on. It morphs on
            // the spring (MorphShape). Turning it on sends two rings off the shape, and while it is on the
            // cookie turns, slowly: a RotationAnimator runs on the render thread (no repaint of the
            // outline) and stops with the mode.
            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingMd
                Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingMd

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
                        border.color: panel.accent
                        opacity: 0
                        SequentialAnimation {
                            id: ringAnim
                            PauseAnimation { duration: ring.index * Motion.respond * 2 }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.6; duration: Motion.ripple; easing.type: Motion.travel }
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
                        running: Gamemode.active && Config.motionEnabled
                        from: 0; to: 360
                        duration: Motion.glide * 40
                        loops: Animation.Infinite
                    }
                    MorphShape {
                        anchors.fill: parent
                        shape: panel._stalled ? "burst" : Gamemode.active ? "cookie9" : "circle"
                        fillColor: panel._stalled ? Colors.of(QsWindow.window).warning
                                 : Gamemode.active ? panel.accent
                                 :                   Colors.of(QsWindow.window).surfaceHigh
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: Gamemode.active ? "sports_esports" : "videogame_asset_off"
                    fill: Gamemode.active ? 1 : 0
                    font.pixelSize: Tokens.iconXl
                    color: Gamemode.active ? Colors.of(QsWindow.window).fgOnPrimary
                                           : Colors.of(QsWindow.window).fgMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: panel._heroTitle
                    variant: "headline"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: panel._heroLine
                    variant: "label"
                    color: hero.ink
                    elide: Text.ElideRight
                }
            }

            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                capsule: true
                variant: Gamemode.active ? "normal" : "primary"
                accent: panel.accent
                symbol: "power_settings_new"
                label: Gamemode.active ? "Turn off" : "Turn on"
                onActivated: Gamemode.toggle()
            }
        }
    }

    // ── Three stat tiles: this session, today, this week ──────────
    // Game-mode time, from the service's own log (per-GAME time is Screen time's job). The session
    // tile takes the container colour while the mode is on, like the hero; the week tile is a bar
    // chart whose bars grow on the house curve when the page opens or a minute is credited.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 1
            implicitHeight: sessionCol.implicitHeight + panel.cardPad * 2
            radius: Tokens.radiusCard
            color: Gamemode.active ? Colors.of(QsWindow.window).primaryContainer
                                   : Colors.of(QsWindow.window).section
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            ColumnLayout {
                id: sessionCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: panel.cardPad
                spacing: 0
                StyledText {
                    text: Gamemode.active ? (panel._elapsed === "just started" ? "< 1 m" : panel._elapsed)
                        : Gamemode.lastSeconds >= 60 ? Gamemode.duration(Gamemode.lastSeconds) : "—"
                    variant: "headline"; font.weight: Font.DemiBold
                    color: Gamemode.active ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                           : Colors.of(QsWindow.window).fg
                }
                StyledText {
                    text: Gamemode.active ? "this session" : "last session"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 1
            implicitHeight: todayCol.implicitHeight + panel.cardPad * 2
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            ColumnLayout {
                id: todayCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: panel.cardPad
                spacing: 0
                StyledText {
                    text: Gamemode.todaySeconds >= 60 ? Gamemode.duration(Gamemode.todaySeconds) : "0 m"
                    variant: "headline"; font.weight: Font.DemiBold
                }
                StyledText { text: "today"; variant: "caption"; emphasis: "dim" }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredWidth: 1.6
            implicitHeight: weekRow.implicitHeight + panel.cardPad * 2
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            RowLayout {
                id: weekRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: panel.cardPad
                spacing: Tokens.spacingMd

                ColumnLayout {
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    StyledText {
                        text: Gamemode.weekSeconds >= 60 ? Gamemode.duration(Gamemode.weekSeconds) : "0 m"
                        variant: "headline"; font.weight: Font.DemiBold
                    }
                    StyledText { text: "this week"; variant: "caption"; emphasis: "dim" }
                }
                // Seven bars, oldest left, today in the accent. Scaled to the busiest day; an empty
                // day is a stub, so the row still reads as seven days.
                Row {
                    id: bars
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingXs
                    readonly property real peak: Math.max(60, Gamemode.weekDays.reduce((m, d) => Math.max(m, d.seconds), 0))
                    readonly property real barW: (width - spacing * 6) / 7
                    readonly property real maxH: Tokens.iconXl + Tokens.spacingSm

                    Repeater {
                        model: Gamemode.weekDays
                        delegate: Item {
                            id: bar
                            required property var modelData
                            width: bars.barW
                            height: bars.maxH
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(Tokens.spacingXs, bar.modelData.seconds / bars.peak * bars.maxH)
                                radius: Math.min(width, height) / 2
                                color: bar.modelData.today ? panel.accent
                                     : Colors.of(QsWindow.window).alpha(panel.accent, 0.35)
                                Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Motion.expressive } }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Live: the rings and the bars ──────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: liveRow.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        RowLayout {
            id: liveRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingXl

            // GPU and CPU: one wavy ring each, the percentage in the hole, the temperature under it.
            // Both wear the accent — the ring's identity is its label, not a second colour.
            Repeater {
                model: ["gpu", "cpu"]
                delegate: ColumnLayout {
                    id: gauge
                    required property string modelData
                    readonly property bool isGpu: gauge.modelData === "gpu"
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    visible: gauge.isGpu ? SysInfo.hasGpu : true
                    spacing: Tokens.spacingXs

                    RadialGauge {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth:  Tokens.iconXl * 2 + Tokens.spacingLg
                        implicitHeight: Tokens.iconXl * 2 + Tokens.spacingLg
                        thickness: Tokens.spacingMd
                        wavy: true
                        value: gauge.isGpu ? SysInfo.gpu : SysInfo.cpu
                        accent: panel.accent
                        sampleInterval: SysInfo.interval

                        StyledText {
                            anchors.centerIn: parent
                            text: Math.round((gauge.isGpu ? SysInfo.gpu : SysInfo.cpu) * 100) + "%"
                            variant: "label"
                            font.bold: true
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: (gauge.isGpu ? "GPU" : "CPU")
                              + (gauge.isGpu ? (SysInfo.hasGpuTemp ? " · " + SysInfo.gpuTemp + "°C" : "")
                                             : (SysInfo.hasCpuTemp ? " · " + SysInfo.cpuTemp + "°C" : ""))
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
            }

            // VRAM | system RAM — RAM is on the strip because on an 8 GB box it is the first thing
            // that throttles a game. Static key list; each row reads SysInfo itself, so a live
            // value never rebuilds it.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingMd

                Repeater {
                    model: ["vram", "ram"]
                    delegate: ColumnLayout {
                        id: mRow
                        required property string modelData

                        readonly property bool isVram: mRow.modelData === "vram"
                        readonly property real used:  isVram ? SysInfo.vramUsed  : SysInfo.memUsed
                        readonly property real total: isVram ? SysInfo.vramTotal : SysInfo.memTotal
                        readonly property real frac:  isVram ? SysInfo.vramFraction : SysInfo.memFraction

                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: mRow.isVram ? (SysInfo.hasGpu && SysInfo.vramTotal > 0) : true
                        spacing: Tokens.spacingXs

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            StyledText {
                                Layout.fillWidth: true
                                text: mRow.isVram ? "VRAM" : "RAM"
                                variant: "caption"; emphasis: "dim"
                            }
                            StyledText {
                                text: mRow.used.toFixed(1) + " / " + mRow.total.toFixed(0) + " GB"
                                variant: "caption"
                                color: mRow.frac > 0.9 ? Colors.of(QsWindow.window).danger
                                                       : Colors.of(QsWindow.window).fg
                            }
                        }
                        Meter {
                            Layout.fillWidth: true
                            implicitHeight: Tokens.spacingMd
                            value: mRow.frac
                            accent: mRow.frac > 0.9 ? Colors.of(QsWindow.window).danger
                                  : mRow.frac > 0.8 ? Colors.of(QsWindow.window).warning
                                  :                    panel.accent
                            fillDuration: Math.min(SysInfo.interval, Motion.settle)
                        }
                    }
                }

                // Swapping — only ever shown when it's actually a problem. A gauge for this would sit at
                // "0.0 GB" the entire time it's not needed and say nothing useful the other 99% of the time.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: SysInfo.swapTotal > 0 && SysInfo.swapUsed > 0.1
                    spacing: Tokens.spacingSm
                    MaterialIcon { name: "warning"; fill: 1; color: Colors.of(QsWindow.window).warning; variant: "caption" }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Swapping — " + SysInfo.swapUsed.toFixed(1) + " GB in use, expect stutter"
                        variant: "caption"
                        color: Colors.of(QsWindow.window).warning
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Memory: what to close first ───────────────────────────────
    // Only when RAM is getting full and something big is open — on a box short of memory that is what
    // throttles a game first. Close asks the window politely (the app may ask to save); nothing is killed.
    Rectangle {
        id: hogCard
        readonly property var rows: Gamemode.hogs.filter(h => h.rssMb >= 400).slice(0, 3)
        Layout.fillWidth: true
        visible: SysInfo.memFraction > 0.5 && hogCard.rows.length > 0
        implicitHeight: hogCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: hogCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Free up memory")
                    variant: "caption"; emphasis: "dim"
                }
                StyledText {
                    text: "RAM " + Math.round(SysInfo.memFraction * 100) + "% used"
                    variant: "caption"
                    color: SysInfo.memFraction > 0.8 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                }
            }

            Repeater {
                model: hogCard.rows
                delegate: RowLayout {
                    id: hogRow
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    MaterialIcon {
                        name: "memory"
                        color: Colors.of(QsWindow.window).fgMuted
                        variant: "body"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: hogRow.modelData.class
                            variant: "body"
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: hogRow.modelData.title
                            variant: "caption"; emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                    StyledText {
                        text: hogRow.modelData.rssMb >= 1024 ? (hogRow.modelData.rssMb / 1024).toFixed(1) + " GB"
                                                             : Math.round(hogRow.modelData.rssMb) + " MB"
                        variant: "label"
                    }
                    ChipButton {
                        symbol: "close"
                        label: Translation.tr("Close")
                        tint: panel.accent
                        onActivated: Gamemode.closeHog(hogRow.modelData)
                    }
                }
            }
        }
    }
}
