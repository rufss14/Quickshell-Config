pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clips.js" as ClipsJs
import "../../services/clockfmt.js" as ClockFmt

// ── ClipsPanel ────────────────────────────────────────────────────────────────
// Clip it and record it, beside the sidebar's clips button (SidePanelDock).
//
//   Clipping   the replay buffer: a ring that fills as it holds, its switch, "clip it" — the
//              whole buffer, or the last 10s / 30s / 1 min… (the lengths the recorder can
//              cut on a signal; clips.js saveLengths) — optionally after N more seconds
//   Recording  start / stop, a dragged region, pause, a limit, and the running time
//   Capture    what the buffer records and how: target, a profile preset, mic and desktop sound
//   Library    its weight against the free disk, and a clean-up that only trashes what the
//              limits in Settings › Clips name
//   Latest     the newest clips, a row of up to six: click plays, hover edits or copies
//
// Keys while it is open (SidePanelDock hands them over): C clip it, 1–6 a length, R record,
// P pause, L library.
//
// Everything real is services/Clips; this shows it and calls it. The look is the media / colours
// / clock panels': a ChipTray header, flat `section` cards, a CookieButton for the two things you
// do, one accent (danger while recording), each card arriving on a spring (PopIn).
//
// What it keeps cheap: the latest row is rebuilt only when what it SHOWS changes (listSig), not on
// every index refresh; the health probe runs only while the panel is open; nothing here polls.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the latest clips give way.
    property real maxHeight: Infinity

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property int pad: Tokens.spacingXl
    // The wallpaper panel's size (620×394), in the sidebar's own unit — a floor for the
    // height, so it only grows if the content needs more.
    implicitWidth: Tokens.sideCardUnit * 13
    implicitHeight: Math.min(root.maxHeight, Math.max(Tokens.sideCardUnit * 8, col.implicitHeight + root.pad * 2))

    readonly property string blocked: Clips.blocker()
    readonly property string warnText: root.blocked !== "" ? root.blocked : Clips.lastError
    // What is wrong, in words (Clips.diagnosis, worst first); the recorder's own words when it has no
    // explanation. A warning (a low disk) is not an error: the card takes the warning tone.
    readonly property var issue: Clips.topIssue
    readonly property string noteText: root.issue ? root.issue.text : root.warnText
    readonly property bool noteIsWarning: root.issue !== null && root.issue.level === "warn"
    readonly property color noteColor: root.noteIsWarning ? root.pal.warning : root.pal.danger
    function openTargets() {
        if (UiState.sidePanel === "clips")
            UiState.openSidePanel("clipsTarget", UiState.sidePanelFrom, UiState.sidePanelScreen)
        else UiState.openSettingsTo("ClipsPage.qml")
    }
    function runFix(fix) {
        if (fix === "target") root.openTargets()
        else if (fix === "folder") UiState.openSettingsTo("ClipsPage.qml")
        else Clips.applyFix(fix)
    }
    function openLibrary() { UiState.closeSidePanel(); Clips.openGallery() }

    // The ways to keep recording after a clip, cycled by one chip.
    readonly property var aheadSteps: [0, 10, 20, 30]
    function cycleAhead() {
        const i = root.aheadSteps.indexOf(Config.clipsAhead)
        Config.clipsAhead = root.aheadSteps[(i + 1) % root.aheadSteps.length]
    }
    function cycleLimit() {
        const ids = ClipsJs.RECORD_LIMITS.map(l => l.id)
        Config.clipsRecordLimit = ids[(ids.indexOf(Config.clipsRecordLimit) + 1) % ids.length]
    }
    // Seconds left of the wait, and of a recording's limit.
    readonly property real aheadLeft: Clips.ahead ? Math.max(0, Clips.ahead.delay - (root.nowMs - Clips.ahead.at) / 1000) : 0
    readonly property string limitLine: {
        if (!Clips.recording || Clips.limit.id === "off") return ""
        if (Clips.limit.seconds > 0)
            return Translation.tr("Stops in") + " " + ClockFmt.clock(Math.max(0, Clips.limit.seconds - root.recordSecs))
        return Translation.tr("Stops at") + " " + Clips.limit.label
    }
    // One accent for the whole panel; a recording turns it to the warning colour.
    readonly property color accent: Clips.recording ? root.pal.danger : root.pal.focus

    // The lengths the recorder can cut on a signal. Recomputed only when the buffer length changes.
    readonly property var lengths: ClipsJs.saveLengths(Clips.bufferSeconds)
    readonly property bool canClip: Clips.buffering && !Clips.aheadWaiting

    // Keys: the dock calls this for a key nothing in the panel took (never with a modifier held).
    function handleKey(event) {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        const k = event.key
        if (k === Qt.Key_C) { if (root.canClip) Clips.clipIt(0); return true }
        if (k >= Qt.Key_1 && k <= Qt.Key_6) {
            const n = root.lengths[k - Qt.Key_1]
            if (n !== undefined && root.canClip) Clips.clipIt(n)
            return true
        }
        if (k === Qt.Key_R) { if (root.blocked === "") Clips.toggleRecord(); return true }
        if (k === Qt.Key_P) { Clips.pause(); return true }
        if (k === Qt.Key_L) { root.openLibrary(); return true }
        return false
    }

    // ── A clock only while something is counting ──────────────────────────────
    property bool _clockHeld: false
    function _syncClock() {
        if (Clips.busy === root._clockHeld) return
        if (Clips.busy) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._clockHeld = Clips.busy
    }
    Connections { target: Clips; function onBusyChanged() { root._syncClock() } }

    // Clips saved after the panel was last open wear a dot; opening it again clears them.
    property real _seenAt: 0
    Component.onCompleted: {
        root._seenAt = Config.clipsSeenAt
        root._syncClock()
        root._syncLatest()
        Clips.acquireHealth()
    }
    Component.onDestruction: {
        if (root._clockHeld) Clock.releaseSeconds()
        Clips.releaseHealth()
        Config.clipsSeenAt = Date.now()
    }

    readonly property real nowMs: Clock.now.getTime()
    // How full the buffer is, 0..1: nothing when it starts, its length once it has
    // run that long.
    readonly property real bufferFill: !Clips.buffering || Clips.since <= 0 ? 0
        : Math.max(0, Math.min(1, (root.nowMs - Clips.since) / 1000 / Clips.bufferSeconds))
    readonly property real heldSecs: Clips.buffering
        ? Math.min(Clips.bufferSeconds, Math.max(0, (root.nowMs - Clips.since) / 1000)) : 0
    readonly property real recordSecs: Clips.recording && Clips.recordSince > 0
        ? Math.max(0, (root.nowMs - Clips.recordSince) / 1000) : 0

    readonly property string stateLine:
          root.blocked !== ""      ? Translation.tr("Unavailable")
        : Clips.mode === "record"  ? (Clips.paused ? Translation.tr("Recording paused") : Translation.tr("Recording")) + " · " + ClockFmt.clock(root.recordSecs)
        : Clips.buffering          ? (Clips.recording ? Translation.tr("Clipping and recording") + " · " + ClockFmt.clock(root.recordSecs)
                                                      : Translation.tr("Clipping") + " · " + Translation.tr("holding") + " " + ClockFmt.clock(root.heldSecs))
        : Clips.clipping           ? (Clips.gaveUp ? Translation.tr("Clipping stopped — it kept failing") : Translation.tr("Clipping is starting…"))
        :                            Translation.tr("Clipping off")

    // ── The latest row ────────────────────────────────────────────────────────
    // How many there is room for, and the list it shows — replaced only when the entries it draws
    // differ (listSig), so a refresh that changes nothing visible rebuilds nothing.
    readonly property int latestCount: root.maxHeight < Tokens.sideCardUnit * 8 ? 3 : 6
    property var latestList: []
    property string _latestSig: "\u0000"
    function _syncLatest() {
        const sig = ClipsJs.listSig(Clips.clips, root.latestCount)
        if (sig === root._latestSig) return
        root._latestSig = sig
        root.latestList = Clips.clips.slice(0, root.latestCount)
    }
    onLatestCountChanged: root._syncLatest()
    Connections { target: Clips; function onClipsChanged() { root._syncLatest() } }

    // Library weight against the room left: one ratio, as a Meter.
    readonly property real diskFreeBytes: Clips.health.diskFreeMiB * 1048576
    readonly property real libraryShare: Clips.libraryBytes + root.diskFreeBytes > 0
        ? Clips.libraryBytes / (Clips.libraryBytes + root.diskFreeBytes) : 0
    ArmLatch {
        id: pruneLatch
        onConfirmed: Clips.prune()
    }

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph: Clips.recording ? "\u{F044A}"                            // 󰑊 record
                 : Clips.buffering ? "\u{F0459}"                            // 󰑙 replay
                 :                   "\u{F0567}"                            // 󰕧 video
            title:     Translation.tr("Clips")
            titleTail: Translation.tr("& recording")
            accent:    root.accent
            subtitle:  root.stateLine

            ChipTray {
                ChipButton {
                    symbol: "movie"
                    tint:   root.accent
                    onActivated: root.openLibrary()
                }
                ChipButton {
                    symbol: "folder_open"
                    tint:   root.accent
                    onActivated: Clips.openFolder()
                }
                ChipButton {
                    symbol: "settings"
                    tint:   root.accent
                    onActivated: UiState.openSettingsTo("ClipsPage.qml")
                }
            }
        }

        // ── What is wrong, and what would fix it ──────────────────────────────
        // A flat card in the danger tone (the warning tone for a low disk). Wrapped — an explanation
        // is a sentence. The fix, where the service can name one, is a chip.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.noteText !== ""
            implicitHeight: warnRow.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusCard
            color: root.pal.alpha(root.noteColor, 0.12)

            RowLayout {
                id: warnRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                MaterialIcon {
                    Layout.alignment: Qt.AlignTop
                    name: "warning"
                    fill: 1
                    variant: "caption"
                    color: root.noteColor
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    variant: "caption"
                    color: root.noteColor
                    text: root.noteText
                }
                ChipTray {
                    Layout.alignment: Qt.AlignTop
                    groupShown: root.issue !== null && Clips.fixLabel(root.issue.fix) !== ""
                    ChipButton {
                        label: root.issue ? Clips.fixLabel(root.issue.fix) : ""
                        tint: root.noteColor
                        onActivated: root.runFix(root.issue.fix)
                    }
                }
            }
        }

        // ══ Two columns ═══════════════════════════════════════════════════════
        // Left: what you DO (clip, record). Right: where it goes, and what it costs.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            ColumnLayout {
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // ══ Clipping ══════════════════════════════════════════════════
                Tile {
                    popIndex: 0
                    // A faint wash of the accent while the buffer runs.
                    tone: Clips.buffering ? root.pal.alpha(root.pal.focus, 0.07) : "transparent"

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingMd

                        // The buffer, as a ring: how much of its length it holds.
                        RadialGauge {
                            Layout.preferredWidth: Tokens.iconXl * 2.5
                            Layout.preferredHeight: Tokens.iconXl * 2.5
                            thickness: Tokens.spacingSm
                            value: root.bufferFill
                            accent: Clips.buffering ? root.pal.primary : root.pal.fgFaint
                            sampleInterval: 1000
                            StyledText {
                                anchors.centerIn: parent
                                text: Clips.buffering ? ClockFmt.clock(root.heldSecs) : Translation.tr("Off")
                                variant: "label"
                                font.weight: Font.DemiBold
                                emphasis: Clips.buffering ? "normal" : "dim"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingXs

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingSm
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Clipping")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                }
                                Toggle {
                                    checked: Clips.clipping
                                    enabled: root.blocked === ""
                                    onToggled: Clips.toggleClipping()
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: "dim"
                                text: Clips.buffering ? Translation.tr("Holding") + " " + ClockFmt.clock(root.heldSecs) + " " + Translation.tr("of") + " " + ClockFmt.clock(Clips.bufferSeconds)
                                                        + (Clips.health.ramMiB > 0 ? "  ·  " + Clips.health.ramMiB + " MB" : "")
                                    : Clips.clipping  ? (Clips.gaveUp ? Translation.tr("Stopped — it kept failing") : Translation.tr("Starting…"))
                                    :                   Translation.tr("Keeps the last") + " " + ClipsJs.span(Clips.bufferSeconds)
                            }
                        }
                    }

                    // Settings changed while it runs: they apply when the recorder restarts (the buffer goes).
                    ChipTray {
                        groupShown: Clips.stale
                        ChipButton {
                            symbol: "restart_alt"
                            label: Translation.tr("Apply settings")
                            tint: root.pal.warning
                            on: true
                            onActivated: Clips.restartBuffer()
                        }
                    }

                    // The thing you do: clip it. The whole buffer, or the lengths it can cut.
                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingMd

                        CookieButton {
                            Layout.preferredWidth: Tokens.iconXl * 2
                            Layout.preferredHeight: Tokens.iconXl * 2
                            name: "content_cut"
                            primary: true
                            tint: root.pal.focus
                            enabled: root.canClip
                            onActivated: Clips.clipIt(0)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Clips.aheadWaiting ? Translation.tr("Saving in") + " " + Math.ceil(root.aheadLeft) + "s…" : Translation.tr("Clip it")
                                variant: "label"
                                font.weight: Font.DemiBold
                                emphasis: Clips.buffering ? "normal" : "dim"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Clips.aheadWaiting ? Translation.tr("Still recording what happens next")
                                    : Config.clipsAhead > 0 ? Translation.tr("Alt+F10 saves at once · this waits") + " " + Config.clipsAhead + "s"
                                    :                          Translation.tr("Alt+F10 · the whole buffer")
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                        // While it waits: don't wait any more, or never mind.
                        ChipTray {
                            groupShown: Clips.aheadWaiting
                            ChipButton {
                                label: Translation.tr("Now")
                                tint: root.pal.focus
                                onActivated: Clips.saveAheadNow()
                            }
                            ChipButton {
                                symbol: "close"
                                tint: root.pal.focus
                                onActivated: Clips.cancelAhead()
                            }
                        }
                    }
                    // The lengths it can cut (shorter than the buffer), one tray.
                    ChipTray {
                        // "Keep recording after": off, 10s, 20s, 30s — one chip that cycles. Lit while it is on.
                        ChipButton {
                            symbol: "timer"
                            label: Config.clipsAhead > 0 ? "+" + Config.clipsAhead + "s" : ""
                            on: Config.clipsAhead > 0
                            tint: root.pal.focus
                            onActivated: root.cycleAhead()
                        }
                        Repeater {
                            model: root.lengths
                            delegate: ChipButton {
                                required property int modelData
                                label: ClipsJs.span(modelData)
                                tint: root.pal.focus
                                enabled: root.canClip
                                onActivated: Clips.clipIt(modelData)
                            }
                        }
                    }
                }

                // ══ Recording ═════════════════════════════════════════════════
                Tile {
                    popIndex: 1
                    tone: Clips.recording ? root.pal.alpha(root.pal.danger, 0.09) : "transparent"

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingMd

                        CookieButton {
                            Layout.preferredWidth: Tokens.iconXl * 2
                            Layout.preferredHeight: Tokens.iconXl * 2
                            // Record, then stop: the icon swaps through the cookie's own squash.
                            name: Clips.recording ? "stop" : "fiber_manual_record"
                            primary: Clips.recording
                            tint: root.pal.danger
                            enabled: root.blocked === ""
                            onActivated: Clips.toggleRecord()
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            RowLayout {
                                Layout.fillHeight: false
                                spacing: Tokens.spacingSm
                                // A dot that breathes while it records — a channel (Motion.pulse), so it
                                // keeps saying "recording" with motion off.
                                Rectangle {
                                    visible: Clips.recording
                                    Layout.alignment: Qt.AlignVCenter
                                    implicitWidth: Tokens.spacingMd
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: root.pal.danger
                                    SequentialAnimation on opacity {
                                        running: Clips.recording && !Clips.paused
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: Motion.pulse; easing.type: Motion.ambient }
                                        NumberAnimation { to: 1.0;  duration: Motion.pulse; easing.type: Motion.ambient }
                                    }
                                }
                                StyledText {
                                    text: !Clips.recording ? Translation.tr("Record")
                                        : Clips.paused     ? Translation.tr("Paused")
                                        :                    ClockFmt.clock(root.recordSecs)
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    color: Clips.recording ? root.pal.danger : root.pal.fg
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: Clips.recording ? (Clips.paused ? Translation.tr("Resume to carry on")
                                                         : root.limitLine !== "" ? root.limitLine : Translation.tr("Alt+F9 stops it"))
                                                      : (Clips.limit.id !== "off" ? Translation.tr("Stops after") + " " + Clips.limit.label : Translation.tr("Alt+F9 · starts now"))
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }

                        ChipTray {
                            // Stop after…: off, 5/10/30 min, 1/2/4 GB — one chip that cycles; lit while a limit is set.
                            ChipButton {
                                symbol: "schedule"
                                label: Clips.limit.id !== "off" ? Clips.limit.label : ""
                                on: Clips.limit.id !== "off"
                                tint: root.accent
                                onActivated: root.cycleLimit()
                            }
                            ChipButton {
                                visible: Clips.mode === "record"
                                symbol: Clips.paused ? "play_arrow" : "pause"
                                on: Clips.paused
                                tint: root.pal.danger
                                onActivated: Clips.pause()
                            }
                            ChipButton {
                                visible: !Clips.recording
                                symbol: "crop"
                                tint: root.accent
                                enabled: root.blocked === "" && Clips.hasSlurp
                                onActivated: { UiState.closeSidePanel(); Clips.recordRegion() }
                            }
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.preferredWidth: 1
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                // ══ Capture ═══════════════════════════════════════════════════
                Tile {
                    popIndex: 2

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: "monitor"
                            color: root.accent
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
                                text: Translation.tr("Capture")
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                        ChipTray {
                            ChipButton {
                                symbol: "edit"
                                tint: root.accent
                                enabled: root.blocked === ""
                                // The target picker is a sidebar panel; opened from the
                                // bar's pill, the same choice is on the Clips page.
                                onActivated: root.openTargets()
                            }
                        }
                    }
                    // The profile: one click sets fps, quality, buffer length and audio. Lit while the settings are
                    // exactly that preset; none lit means they were tuned by hand.
                    Flow {
                        width: parent.width
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: Clips.presets
                            delegate: ChipButton {
                                required property var modelData
                                label: modelData.label
                                labelVariant: "caption"
                                on: Clips.preset !== null && Clips.preset.id === modelData.id
                                tint: root.accent
                                onActivated: Clips.applyPreset(modelData.id)
                            }
                        }
                    }
                    // How it is recorded: the video as a line, the sound as two switches. A change waits for
                    // "Apply settings" when the buffer is running.
                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingSm
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.iconXl
                            radius: height / 2
                            color: root.pal.surfaceContainer
                            RowLayout {
                                id: pillRow
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.spacingMd
                                anchors.rightMargin: Tokens.spacingMd
                                spacing: Tokens.spacingSm
                                MaterialIcon {
                                    name: "videocam"
                                    variant: "caption"
                                    color: root.accent
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: ClipsJs.summary(Clips.opts)
                                    variant: "caption"
                                    color: root.pal.fgMuted
                                }
                            }
                        }
                        ChipTray {
                            ChipButton {
                                symbol: Config.clipsMic ? "mic" : "mic_off"
                                on: Config.clipsMic
                                tint: root.accent
                                onActivated: Config.clipsMic = !Config.clipsMic
                            }
                            ChipButton {
                                symbol: Config.clipsDesktopAudio ? "volume_up" : "volume_off"
                                on: Config.clipsDesktopAudio
                                tint: root.accent
                                onActivated: Config.clipsDesktopAudio = !Config.clipsDesktopAudio
                            }
                        }
                    }
                }

                // ══ Library ═══════════════════════════════════════════════════
                // What the clips weigh against what the disk has left. The clean-up chip shows only when the
                // limits in Settings › Clips name something to trash, and takes two taps.
                Tile {
                    popIndex: 3

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: "hard_drive"
                            color: root.accent
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: ClipsJs.bytesText(Clips.libraryBytes) + " · " + Clips.clips.length + " "
                                      + (Clips.clips.length === 1 ? Translation.tr("clip") : Translation.tr("clips"))
                                variant: "label"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                text: root.diskFreeBytes > 0 ? ClipsJs.bytesText(root.diskFreeBytes) + " " + Translation.tr("free on the disk")
                                                             : Translation.tr("Library")
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                        ChipTray {
                            groupShown: Clips.prunePreview.count > 0
                            ChipButton {
                                symbol: "cleaning_services"
                                label: pruneLatch.armed ? Translation.tr("Trash") + " " + Clips.prunePreview.count + "?"
                                                        : Translation.tr("Free") + " " + ClipsJs.bytesText(Clips.prunePreview.bytes)
                                on: pruneLatch.armed
                                tint: root.pal.warning
                                onActivated: pruneLatch.trigger()
                            }
                        }
                    }
                    Meter {
                        width: parent.width
                        value: root.libraryShare
                        accent: root.accent
                    }
                }
            }
        }

        // ══ Latest ════════════════════════════════════════════════════════════
        // Up to six in a row, thumbnail over name. A dot marks what was saved since the panel was last open.
        Tile {
            popIndex: 4

            RowLayout {
                width: parent.width
                spacing: Tokens.spacingSm
                MaterialIcon {
                    name: "history"
                    color: root.accent
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Latest")
                    variant: "label"
                    font.weight: Font.DemiBold
                }
                // The library, one labelled tap away (also Alt+F8, L, and "Clips library" in the launcher).
                ChipTray {
                    ChipButton {
                        symbol: "movie"
                        label: Translation.tr("Library")
                        on: true
                        tint: root.accent
                        onActivated: root.openLibrary()
                    }
                }
            }

            // Nothing yet.
            ColumnLayout {
                width: parent.width
                visible: root.latestList.length === 0
                spacing: Tokens.spacingXs
                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "movie"
                    font.pixelSize: Tokens.iconXl
                    color: root.pal.fgFaint
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Nothing saved yet")
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            Row {
                id: latestRow
                width: parent.width
                visible: root.latestList.length > 0
                spacing: Tokens.spacingSm
                // A card is one sixth of the row (one third on a short edge) whether or not there are that many,
                // so two clips do not stretch to fill it.
                readonly property real cardW: Math.floor((latestRow.width - latestRow.spacing * (root.latestCount - 1)) / root.latestCount)

                Repeater {
                    model: root.latestList
                    delegate: Item {
                        id: clipRow
                        required property var modelData
                        required property int index
                        readonly property var shown: ClipsJs.prettyName(clipRow.modelData.name, clipRow.modelData.ext, clipRow.modelData.mtime)
                        readonly property string context: ClipsJs.contextLine(Clips.contextOf(clipRow.modelData.path))
                        readonly property bool fresh: clipRow.modelData.mtime > root._seenAt
                        width: latestRow.cardW
                        height: thumb.height + names.implicitHeight + Tokens.spacingXs

                        // Each thumbnail arrives on a spring, a beat after the one before it.
                        PopIn { id: pop; active: true; index: clipRow.index; delay: Motion.stagger * 6 }
                        opacity: pop.opacity
                        scale:   pop.scale

                        // A handler, not the MouseArea's containsMouse: that goes false the
                        // moment the pointer is over a chip, which would hide it.
                        HoverHandler { id: rowHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { UiState.closeSidePanel(); Clips.playClip(clipRow.modelData.path) }
                        }
                        ClipThumb {
                            id: thumb
                            width: clipRow.width
                            height: Math.round(thumb.width * 9 / 16)
                            entry: clipRow.modelData
                            decodeWidth: 180

                            // A play disc over the frame, under the pointer.
                            Rectangle {
                                anchors.centerIn: parent
                                width: Tokens.iconXl
                                height: width
                                radius: width / 2
                                color: root.pal.alpha(root.pal.shadow, 0.55)
                                opacity: rowHover.hovered ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "play_arrow"
                                    fill: 1
                                    variant: "label"
                                    color: root.pal.fg
                                }
                            }
                            // New since the panel was last open.
                            Rectangle {
                                visible: clipRow.fresh && !rowHover.hovered
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.margins: Tokens.spacingSm
                                width: Tokens.spacingMd
                                height: width
                                radius: width / 2
                                color: root.accent
                            }
                        }
                        // Edit and copy ride the thumbnail's corner, shown on hover.
                        ChipTray {
                            anchors.top: thumb.top
                            anchors.right: thumb.right
                            anchors.margins: Tokens.spacingXs
                            opacity: rowHover.hovered ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            ChipButton {
                                symbol: "content_cut"
                                tint: root.accent
                                onActivated: { UiState.closeSidePanel(); Clips.editClip(clipRow.modelData.path) }
                            }
                            ChipButton {
                                symbol: "content_copy"
                                tint: root.accent
                                onActivated: Clips.copyClip(clipRow.modelData.path)
                            }
                        }
                        Column {
                            id: names
                            anchors.top: thumb.bottom
                            anchors.topMargin: Tokens.spacingXs
                            width: clipRow.width
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: clipRow.shown.title
                                variant: "caption"
                            }
                            // The song that was playing and who was in the call, when stamped; else how long ago.
                            StyledText {
                                width: parent.width
                                elide: Text.ElideRight
                                text: clipRow.context !== "" ? clipRow.context
                                      : clipRow.shown.time + "  ·  " + ClipsJs.age(clipRow.modelData.mtime, root.nowMs)
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                    }
                }
            }
        }
    }

    // ── A card: flat, on the section fill, its rows stacked ───────────────────
    // `tone` washes it with a colour (the buffer running, a recording); `popIndex` is when it
    // arrives, on a spring, after the cards before it.
    component Tile: Rectangle {
        id: tileRect
        default property alias rows: inner.data
        property color tone: "transparent"
        property int popIndex: 0

        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: inner.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        PopIn { id: tilePop; active: true; index: tileRect.popIndex; step: Motion.stagger * 3 }
        opacity: tilePop.opacity
        scale:   tilePop.scale

        Rectangle {
            anchors.fill: parent
            radius: tileRect.radius
            color: tileRect.tone
            Behavior on color { ColorAnimation { duration: Motion.standard } }
        }
        Column {
            id: inner
            x: Tokens.spacingMd
            y: Tokens.spacingMd
            width: tileRect.width - Tokens.spacingMd * 2
            spacing: Tokens.spacingSm
        }
    }
}
