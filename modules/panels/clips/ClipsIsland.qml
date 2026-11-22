pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/clips.js" as ClipsJs

// ── ClipsIsland ── ClipsPanel's form on an island (2026-11-15); `panel` is the ClipsPanel it belongs to. ─────
// The wallpaper and colour pages' recipe, no title row:
//
//   left    the loud card is the replay buffer: a big ring of how much it holds with the time in it, the switch,
//           and the thing you do, Clip it, as the one loud pill, with the lengths it can cut under it.
//           Under it the recording card: the record disc, the running time, limit / pause / region.
//   right   what is wrong (only when something is), what it captures (the screen, the profile as option cards,
//           the sound as two lit tools), the library's weight against the disk, and the latest clips as a
//           scrolling gallery of pictures on canvases, the tools under the pointer.
//
// Every number, line and action is the panel's or Clips' (ClipsPanel keeps the keys, the clocks and the
// latest list); this only lays them out.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Item {
    id: page
    required property var panel

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Left: clip it, record ═════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: page.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            Rectangle {
                id: hero
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Tokens.radiusXl
                color: page.pal.primaryContainer
                readonly property color ink: page.pal.fgOnPrimaryContainer
                readonly property color inkDim: page.pal.alpha(page.pal.fgOnPrimaryContainer, 0.72)
                PopIn { id: heroPop; active: true; index: 0 }
                opacity: heroPop.opacity
                scale: heroPop.scale

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingSm

                    // The name and the switch, then what it is doing.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Clipping")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        Toggle {
                            checked: Clips.clipping
                            enabled: page.panel.blocked === ""
                            accessibleName: Translation.tr("Clipping")
                            onToggled: Clips.toggleClipping()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        variant: "caption"
                        color: hero.inkDim
                        text: Clips.buffering ? Translation.tr("Holding %1 of %2").arg(ClockFmt.clock(page.panel.heldSecs)).arg(ClockFmt.clock(Clips.bufferSeconds))
                            : Clips.clipping  ? (Clips.gaveUp ? Translation.tr("Stopped. It kept failing") : Translation.tr("Starting…"))
                            :                   Translation.tr("Keeps the last %1").arg(ClipsJs.span(Clips.bufferSeconds))
                    }

                    // The buffer, as a big ring in the middle of the card: how much of its length it holds, the
                    // time it holds in it (or Off). As large as the card leaves room for.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        RadialGauge {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height, Tokens.iconXl * 5)
                            height: width
                            thickness: Tokens.spacingMd
                            wavy: Clips.buffering && Motion.ambientOn
                            value: page.panel.bufferFill
                            accent: Clips.buffering ? page.pal.primary : page.pal.alpha(hero.ink, 0.22)
                            sampleInterval: 1000
                            StyledText {
                                anchors.centerIn: parent
                                text: Clips.buffering ? ClockFmt.clock(page.panel.heldSecs) : Translation.tr("Off")
                                font.pixelSize: Tokens.fontDisplay
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                color: hero.ink
                            }
                        }
                    }

                    // Settings changed while it runs: they apply when the recorder restarts (the buffer goes).
                    ChipButton {
                        visible: Clips.stale
                        symbol: "restart_alt"
                        label: Translation.tr("Apply settings")
                        tonal: true
                        tint: hero.ink
                        onActivated: Clips.restartBuffer()
                    }

                    // The thing you do: the whole buffer. While a delayed save waits: now, or never mind.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        ChipButton {
                            Layout.fillWidth: true
                            solid: true
                            symbol: "content_cut"
                            label: Clips.aheadWaiting ? Translation.tr("Saving in %1 s").arg(Math.ceil(page.panel.aheadLeft)) : Translation.tr("Clip it")
                            enabled: page.panel.canClip || Clips.aheadWaiting
                            onActivated: Clips.aheadWaiting ? Clips.saveAheadNow() : Clips.clipIt(0)
                        }
                        ChipButton {
                            visible: Clips.aheadWaiting
                            symbol: "close"
                            tint: hero.ink
                            Accessible.name: Translation.tr("Don't save")
                            onActivated: Clips.cancelAhead()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Clips.aheadWaiting ? Translation.tr("Still recording what happens next")
                            : Config.clipsAhead > 0 ? Translation.tr("Alt+F10 · waits %1 s first").arg(Config.clipsAhead)
                            : Translation.tr("Alt+F10 · the whole buffer")
                        variant: "micro"
                        color: hero.inkDim
                        elide: Text.ElideRight
                    }
                    // The lengths it can cut, and "keep recording after" as one cycling chip.
                    Flow {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingXs
                        ChipButton {
                            symbol: "timer"
                            label: Config.clipsAhead > 0 ? "+" + Config.clipsAhead + "s" : ""
                            on: Config.clipsAhead > 0
                            tonal: true
                            tint: hero.ink
                            Accessible.name: Translation.tr("Keep recording after the press")
                            onActivated: page.panel.cycleAhead()
                        }
                        Repeater {
                            model: page.panel.lengths
                            delegate: ChipButton {
                                required property int modelData
                                label: ClipsJs.span(modelData)
                                tonal: true
                                tint: hero.ink
                                enabled: page.panel.canClip
                                onActivated: Clips.clipIt(modelData)
                            }
                        }
                    }
                }
            }

            // ── Record ─────────────────────────────────────────────────────────
            ClipsPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingLg * 2
                popIndex: 1
                tone: Clips.recording ? page.pal.alpha(page.pal.danger, 0.14) : page.pal.section

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    CookieButton {
                        Layout.preferredWidth: Tokens.iconXl * 2
                        Layout.preferredHeight: Tokens.iconXl * 2
                        name: Clips.recording ? "stop" : "fiber_manual_record"
                        primary: Clips.recording
                        tint: page.pal.danger
                        enabled: page.panel.blocked === ""
                        Accessible.name: Clips.recording ? Translation.tr("Stop recording") : Translation.tr("Record")
                        onActivated: Clips.toggleRecord()
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: !Clips.recording ? Translation.tr("Record")
                                : Clips.paused     ? Translation.tr("Paused")
                                :                    ClockFmt.clock(page.panel.recordSecs)
                            variant: Clips.recording && !Clips.paused ? "title" : "label"
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            color: Clips.recording ? page.pal.danger : page.pal.fg
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: Clips.recording ? (Clips.paused ? Translation.tr("Resume to carry on")
                                                     : page.panel.limitLine !== "" ? page.panel.limitLine : Translation.tr("Alt+F9 stops it"))
                                                  : (Clips.limit.id !== "off" ? Translation.tr("Stops after %1").arg(Clips.limit.label) : Translation.tr("Alt+F9"))
                            variant: "micro"
                            emphasis: "dim"
                        }
                    }
                    ChipButton {
                        symbol: "schedule"
                        on: Clips.limit.id !== "off"
                        tint: page.panel.accent
                        Accessible.name: Translation.tr("Stop after")
                        onActivated: page.panel.cycleLimit()
                        HoverTip { text: Clips.limit.id !== "off" ? Translation.tr("Stops after %1").arg(Clips.limit.label) : Translation.tr("No limit"); alignEnd: true }
                    }
                    ChipButton {
                        visible: Clips.mode === "record"
                        symbol: Clips.paused ? "play_arrow" : "pause"
                        on: Clips.paused
                        tint: page.pal.danger
                        Accessible.name: Clips.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                        onActivated: Clips.pause()
                    }
                    ChipButton {
                        visible: !Clips.recording
                        symbol: "crop"
                        tint: page.panel.accent
                        enabled: page.panel.blocked === "" && Clips.hasSlurp
                        Accessible.name: Translation.tr("Record a region")
                        onActivated: { page.panel.stepAside(); Clips.recordRegion() }
                        HoverTip { text: Clips.hasSlurp ? Translation.tr("Record a region") : Translation.tr("Needs slurp"); alignEnd: true }
                    }
                }
            }
        }

        // ══ Right: what is wrong, what it captures, the library ══════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // What is wrong, and what would fix it: only while there is something to say.
            ClipsPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: page.panel.noteText !== ""
                Layout.preferredHeight: warnRow.implicitHeight + Tokens.spacingMd * 2
                tone: page.pal.alpha(page.panel.noteColor, 0.14)

                RowLayout {
                    id: warnRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: "warning"
                        fill: 1
                        color: page.panel.noteColor
                    }
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        variant: "caption"
                        color: page.panel.noteColor
                        text: page.panel.noteText
                    }
                    ChipButton {
                        visible: page.panel.issue !== null && Clips.fixLabel(page.panel.issue.fix) !== ""
                        label: page.panel.issue ? Clips.fixLabel(page.panel.issue.fix) : ""
                        tint: page.panel.noteColor
                        onActivated: page.panel.runFix(page.panel.issue.fix)
                    }
                }
            }

            // ── Capture ────────────────────────────────────────────────────────
            ClipsPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: capCol.implicitHeight + Tokens.spacingMd * 2
                popIndex: 2

                ColumnLayout {
                    id: capCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MorphShape {
                            Layout.preferredWidth: Tokens.iconXl
                            Layout.preferredHeight: Tokens.iconXl
                            shape: "squircle"
                            fillColor: page.pal.plate
                            turns: false
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "monitor"
                                color: page.pal.fg
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Clips.targetLabel
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: ClipsJs.summary(Clips.opts)
                                variant: "micro"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                        LitTool {
                            symbol: Config.clipsMic ? "mic" : "mic_off"
                            lit: Config.clipsMic
                            tip: Config.clipsMic ? Translation.tr("Microphone recorded") : Translation.tr("Microphone not recorded")
                            onActivated: Config.clipsMic = !Config.clipsMic
                        }
                        LitTool {
                            symbol: Config.clipsDesktopAudio ? "volume_up" : "volume_off"
                            lit: Config.clipsDesktopAudio
                            tip: Config.clipsDesktopAudio ? Translation.tr("Desktop sound recorded") : Translation.tr("Desktop sound not recorded")
                            onActivated: Config.clipsDesktopAudio = !Config.clipsDesktopAudio
                        }
                        LitTool {
                            symbol: "edit"
                            enabled: page.panel.blocked === ""
                            tip: Translation.tr("What to capture")
                            onActivated: page.panel.openTargets()
                        }
                    }
                    // The profile: one press sets fps, quality, buffer length and sound. On while the settings are
                    // exactly that profile; none on means they were tuned by hand.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: Clips.presets
                            delegate: OptionCard {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                label: modelData.label
                                symbol: ({ game: "sports_esports", tutorial: "mic", light: "speed", max: "bolt" })[modelData.id] ?? "videocam"
                                shape: ["cookie9", "clover", "sunny", "squircle"][index % 4]
                                on: Clips.preset !== null && Clips.preset.id === modelData.id
                                onActivated: Clips.applyPreset(modelData.id)
                            }
                        }
                    }
                }
            }

            // ── Library: its weight, the disk, the latest as a gallery ─────────
            ClipsPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                popIndex: 3

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            text: String(Clips.clips.length)
                            font.pixelSize: Tokens.fontDisplay
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("clips · %1").arg(ClipsJs.bytesText(Clips.libraryBytes))
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: page.panel.diskFreeBytes > 0 ? Translation.tr("%1 free on the disk").arg(ClipsJs.bytesText(page.panel.diskFreeBytes)) : ""
                                variant: "micro"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                        // The clean-up only shows when the limits in Settings › Clips name something to trash.
                        ChipButton {
                            visible: Clips.prunePreview.count > 0 && !page.confirmPrune
                            symbol: "cleaning_services"
                            label: Translation.tr("Free %1").arg(ClipsJs.bytesText(Clips.prunePreview.bytes))
                            tonal: true
                            onActivated: page.confirmPrune = true
                        }
                        ChipButton {
                            visible: page.confirmPrune
                            label: Translation.tr("Keep")
                            tonal: true
                            onActivated: page.confirmPrune = false
                        }
                        ChipButton {
                            visible: page.confirmPrune
                            symbol: "delete"
                            label: Translation.tr("Trash %1").arg(Clips.prunePreview.count)
                            solid: true
                            tint: page.pal.danger
                            onActivated: { Clips.prune(); page.confirmPrune = false }
                        }
                        ChipButton {
                            symbol: "folder_open"
                            tonal: true
                            Accessible.name: Translation.tr("Open the folder")
                            onActivated: Clips.openFolder()
                        }
                        ChipButton {
                            symbol: "movie"
                            label: Translation.tr("Library")
                            solid: true
                            onActivated: page.panel.openLibrary()
                        }
                    }
                    Meter {
                        Layout.fillWidth: true
                        value: page.panel.libraryShare
                        accent: page.pal.primary
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        StyledText {
                            anchors.centerIn: parent
                            visible: page.panel.latestList.length === 0
                            text: Translation.tr("Nothing saved yet")
                            variant: "caption"
                            emphasis: "dim"
                        }

                        GridView {
                            id: grid
                            anchors.fill: parent
                            visible: page.panel.latestList.length > 0
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: page.panel.latestList
                            readonly property int cols: 3
                            cellWidth: Math.floor(grid.width / grid.cols)
                            cellHeight: Math.round((grid.cellWidth - Tokens.spacingSm) * 9 / 16) + Tokens.spacingSm + Tokens.fontCaption + Tokens.spacingSm

                            delegate: Item {
                                id: cell
                                required property var modelData
                                required property int index
                                readonly property var shown: ClipsJs.prettyName(cell.modelData.name, cell.modelData.ext, cell.modelData.mtime)
                                readonly property bool fresh: cell.modelData.mtime > page.panel._seenAt
                                width: grid.cellWidth
                                height: grid.cellHeight

                                PopIn { id: cellPop; active: true; index: cell.index; cap: 6; delay: Motion.stagger * 4 }
                                opacity: cellPop.opacity

                                HoverHandler { id: cellHover }
                                SpringValue {
                                    id: lean
                                    target: cellHover.hovered ? 1.03 : 1
                                    spec: Motion.springSpatialFast
                                    epsilon: 0.002
                                }

                                // The picture on its canvas.
                                Rectangle {
                                    id: canvas
                                    x: Tokens.spacingXs
                                    width: cell.width - Tokens.spacingSm
                                    height: Math.round(canvas.width * 9 / 16)
                                    radius: Tokens.radiusCard
                                    color: page.pal.plate
                                    border.width: Tokens.borderWidth
                                    border.color: cell.fresh ? page.pal.primary : page.pal.outline
                                    scale: lean.value * cellPop.scale

                                    ClipThumb {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.borderWidth
                                        entry: cell.modelData
                                        decodeWidth: 240
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { page.panel.stepAside(); Clips.playClip(cell.modelData.path) }
                                        Accessible.role: Accessible.Button
                                        Accessible.name: Translation.tr("Play %1").arg(cell.shown.title)
                                    }
                                    // Edit and copy: a capsule at the corner, under the pointer.
                                    Rectangle {
                                        anchors.top: parent.top
                                        anchors.right: parent.right
                                        anchors.margins: Tokens.spacingXs
                                        width: tools.implicitWidth + Tokens.spacingXs * 2
                                        height: tools.implicitHeight + Tokens.spacingXs * 2
                                        radius: height / 2
                                        color: page.pal.alpha(page.pal.surface, 0.9)
                                        opacity: cellHover.hovered ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                        Row {
                                            id: tools
                                            anchors.centerIn: parent
                                            spacing: Tokens.spacingXs
                                            CardTool {
                                                symbol: "content_cut"
                                                name: Translation.tr("Edit")
                                                onActivated: { page.panel.stepAside(); Clips.editClip(cell.modelData.path) }
                                            }
                                            CardTool {
                                                symbol: "content_copy"
                                                name: Translation.tr("Copy")
                                                onActivated: Clips.copyClip(cell.modelData.path)
                                            }
                                        }
                                    }
                                }
                                StyledText {
                                    anchors.top: canvas.bottom
                                    anchors.topMargin: Tokens.spacingXs
                                    x: Tokens.spacingXs
                                    width: canvas.width
                                    text: cell.shown.title
                                    variant: "caption"
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    property bool confirmPrune: false
}
