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
// Clip it and record it, beside the sidebar's clips button (SidePanelDock). It took
// over from the clips pill's three cells and hover card:
//
//   Clipping   the replay buffer: a ring that fills as it holds, its switch, "clip it" — the
//              whole buffer, or the last 10s / 30s / 1 min… (the lengths the recorder can
//              cut on a signal; clips.js saveLengths)
//   Recording  start / stop, a dragged region, pause, and the running time
//   Capture    what the buffer records, and how — and the picker that changes it
//              (ClipsTargetPanel, which a HOLD on the button opens straight away)
//   Latest     the newest clips: click plays one, the gallery has the rest
//
// ── The look is the media / colours / clock panels' ───────────────────────────
// (revamp 2026-10-18) ChipTray + ChipButton in the header and for the small actions, a
// CookieButton for the two things you do (clip it, record), flat `section` cards on
// `radiusCard` (no outline), and each card arriving on a spring, one after another (PopIn).
// One accent for the panel: the focus colour, the danger one while a recording runs.
//
// ── What was added to it (2026-10-18) ─────────────────────────────────────────
//   · what is wrong, in words, with a button for the fix (`Clips.diagnosis` — a missing monitor, a
//     buffer that won't fit in RAM, a full disk) in place of the bare recorder error;
//   · the buffer's real memory beside how much it holds, and "Apply settings" when they changed;
//   · "keep recording N more seconds" on the clip-it chips, and a countdown with Now / Cancel;
//   · "stop after…" on the record card, with what is left while it runs;
//   · profile presets on the capture card;
//   · edit + copy on every latest clip.
// Everything real is services/Clips; this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the latest clips give way.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    // The wallpaper panel's size (620×394), in the sidebar's own unit — a floor for the
    // height, so it only grows if the content (clipping with its buffer meter) needs more.
    implicitWidth: Tokens.sideCardUnit * 13
    implicitHeight: Math.min(root.maxHeight, Math.max(Tokens.sideCardUnit * 8, col.implicitHeight + root.pad * 2))

    readonly property string blocked: Clips.blocker()
    readonly property string warnText: root.blocked !== "" ? root.blocked : Clips.lastError
    // What is wrong, in words (Clips.diagnosis, worst first); the recorder's own words when it has no
    // explanation. A warning (a low disk) is not an error: the card takes the warning tone.
    readonly property var issue: Clips.topIssue
    readonly property string noteText: root.issue ? root.issue.text : root.warnText
    readonly property bool noteIsWarning: root.issue !== null && root.issue.level === "warn"
    function runFix(fix) {
        if (fix === "target") {
            if (UiState.sidePanel === "clips")
                UiState.openSidePanel("clipsTarget", UiState.sidePanelFrom, UiState.sidePanelScreen)
            else UiState.openSettingsTo("ClipsPage.qml")
        } else if (fix === "folder") {
            UiState.openSettingsTo("ClipsPage.qml")
        } else {
            Clips.applyFix(fix)
        }
    }
    // The ways to keep recording after a clip, cycled by one chip.
    readonly property var aheadSteps: [0, 10, 20, 30]
    function cycleAhead() {
        const i = root.aheadSteps.indexOf(Config.clipsAhead)
        Config.clipsAhead = root.aheadSteps[(i + 1) % root.aheadSteps.length]
    }
    // Seconds left of the wait, and of a recording's limit.
    readonly property real aheadLeft: Clips.ahead ? Math.max(0, Clips.ahead.delay - (root.nowMs - Clips.ahead.at) / 1000) : 0
    function cycleLimit() {
        const ids = ClipsJs.RECORD_LIMITS.map(l => l.id)
        Config.clipsRecordLimit = ids[(ids.indexOf(Config.clipsRecordLimit) + 1) % ids.length]
    }
    readonly property string limitLine: {
        if (!Clips.recording || Clips.limit.id === "off") return ""
        if (Clips.limit.seconds > 0)
            return "Stops in " + ClockFmt.clock(Math.max(0, Clips.limit.seconds - root.recordSecs))
        return "Stops at " + Clips.limit.label
    }
    // One accent for the whole panel; a recording turns it to the warning colour.
    readonly property color accent: Clips.recording ? Colors.of(QsWindow.window).danger
                                                    : Colors.of(QsWindow.window).focus

    // ── A clock only while something is counting ──────────────────────────────
    property bool _clockHeld: false
    function _syncClock() {
        if (Clips.busy === root._clockHeld) return
        if (Clips.busy) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._clockHeld = Clips.busy
    }
    Connections { target: Clips; function onBusyChanged() { root._syncClock() } }
    Component.onCompleted: { root._syncClock(); Clips.acquireHealth() }
    Component.onDestruction: { if (root._clockHeld) Clock.releaseSeconds(); Clips.releaseHealth() }

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
          root.blocked !== ""      ? "Unavailable"
        : Clips.mode === "record"  ? (Clips.paused ? "Recording paused · " : "Recording · ") + ClockFmt.clock(root.recordSecs)
        : Clips.buffering          ? (Clips.recording ? "Clipping and recording · " + ClockFmt.clock(root.recordSecs)
                                                      : "Clipping · holding " + ClockFmt.clock(root.heldSecs))
        : Clips.clipping           ? (Clips.gaveUp ? "Clipping stopped — it kept failing" : "Clipping is starting…")
        :                            "Clipping off"

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
            titleTail: "& recording"
            accent:    root.accent
            subtitle:  root.stateLine

            // The panel's own tray (ChipTray, as the media / colours / clock panels'), not ActionGroup.
            ChipTray {
                ChipButton {
                    symbol: "movie"
                    tint:   root.accent
                    onActivated: { UiState.closeSidePanel(); Clips.openGallery() }
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
            color: Colors.of(QsWindow.window).alpha(root.noteIsWarning ? Colors.of(QsWindow.window).warning
                                                                       : Colors.of(QsWindow.window).danger, 0.12)

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
                    color: root.noteIsWarning ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).danger
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    variant: "caption"
                    color: root.noteIsWarning ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).danger
                    text: root.noteText
                }
                ChipTray {
                    Layout.alignment: Qt.AlignTop
                    groupShown: root.issue !== null && Clips.fixLabel(root.issue.fix) !== ""
                    ChipButton {
                        label: root.issue ? Clips.fixLabel(root.issue.fix) : ""
                        tint: root.noteIsWarning ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).danger
                        onActivated: root.runFix(root.issue.fix)
                    }
                }
            }
        }

        // ══ Two columns ═══════════════════════════════════════════════════════
        // Left: what you DO (clip, record). Right: where it goes, and what came of it.
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
                    id: bufferTile
                    popIndex: 0
                    // A faint wash of the accent while the buffer runs.
                    tone: Clips.buffering ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.07)
                                          : "transparent"

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingMd

                        // The buffer, as a ring: how much of its length it holds.
                        RadialGauge {
                            Layout.preferredWidth: Tokens.iconXl * 2.6
                            Layout.preferredHeight: Tokens.iconXl * 2.6
                            thickness: Tokens.spacingSm - 1
                            value: root.bufferFill
                            accent: Clips.buffering ? Colors.of(QsWindow.window).primary
                                                    : Colors.of(QsWindow.window).fgFaint
                            sampleInterval: 1000
                            StyledText {
                                anchors.centerIn: parent
                                text: Clips.buffering ? ClockFmt.clock(root.heldSecs) : "Off"
                                variant: "label"
                                font.weight: Font.DemiBold
                                emphasis: Clips.buffering ? "normal" : "dim"
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingXs / 2

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
                                text: Clips.buffering ? "Holding " + ClockFmt.clock(root.heldSecs) + " of " + ClockFmt.clock(Clips.bufferSeconds)
                                                        + (Clips.health.ramMiB > 0 ? "  ·  " + Clips.health.ramMiB + " MB" : "")
                                    : Clips.clipping  ? (Clips.gaveUp ? "Stopped — it kept failing" : "Starting…")
                                    :                   "Keeps the last " + ClipsJs.span(Clips.bufferSeconds)
                            }
                        }
                    }

                    // Settings changed while it runs: they apply when the recorder restarts (the buffer goes).
                    ChipTray {
                        groupShown: Clips.stale
                        ChipButton {
                            symbol: "restart_alt"
                            label: Translation.tr("Apply settings")
                            tint: Colors.of(QsWindow.window).warning
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
                            tint: Colors.of(QsWindow.window).focus
                            enabled: Clips.buffering && !Clips.aheadWaiting
                            onActivated: Clips.clipIt(0)
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                text: Clips.aheadWaiting ? "Saving in " + Math.ceil(root.aheadLeft) + "s…" : "Clip it"
                                variant: "label"
                                font.weight: Font.DemiBold
                                emphasis: Clips.buffering ? "normal" : "dim"
                            }
                            StyledText {
                                text: Clips.aheadWaiting ? "Still recording what happens next"
                                    : Config.clipsAhead > 0 ? "Alt+F10 saves at once · this waits " + Config.clipsAhead + "s"
                                    :                          "Alt+F10 · the whole buffer"
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }
                        // While it waits: don't wait any more, or never mind.
                        ChipTray {
                            groupShown: Clips.aheadWaiting
                            ChipButton {
                                label: Translation.tr("Now")
                                tint: Colors.of(QsWindow.window).focus
                                onActivated: Clips.saveAheadNow()
                            }
                            ChipButton {
                                symbol: "close"
                                tint: Colors.of(QsWindow.window).focus
                                onActivated: Clips.cancelAhead()
                            }
                        }
                    }
                    // The lengths it can cut (shorter than the buffer — clips.js saveLengths), one tray.
                    ChipTray {
                        // "Keep recording after": off, 10s, 20s, 30s — one chip that cycles. Lit while it is on.
                        ChipButton {
                            symbol: "timer"
                            label: Config.clipsAhead > 0 ? "+" + Config.clipsAhead + "s" : ""
                            on: Config.clipsAhead > 0
                            tint: Colors.of(QsWindow.window).focus
                            onActivated: root.cycleAhead()
                        }
                        Repeater {
                            model: ClipsJs.saveLengths(Clips.bufferSeconds)
                            delegate: ChipButton {
                                required property int modelData
                                label: ClipsJs.span(modelData)
                                tint: Colors.of(QsWindow.window).focus
                                enabled: Clips.buffering && !Clips.aheadWaiting
                                onActivated: Clips.clipIt(modelData)
                            }
                        }
                    }
                }

                // ══ Recording ═════════════════════════════════════════════════
                Tile {
                    popIndex: 1
                    tone: Clips.recording ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.09)
                                          : "transparent"

                    RowLayout {
                        width: parent.width
                        spacing: Tokens.spacingMd

                        CookieButton {
                            Layout.preferredWidth: Tokens.iconXl * 2
                            Layout.preferredHeight: Tokens.iconXl * 2
                            // Record, then stop: the icon swaps through the cookie's own squash.
                            name: Clips.recording ? "stop" : "fiber_manual_record"
                            primary: Clips.recording
                            tint: Colors.of(QsWindow.window).danger
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
                                    implicitWidth: Tokens.spacingSm + 2
                                    implicitHeight: implicitWidth
                                    radius: width / 2
                                    color: Colors.of(QsWindow.window).danger
                                    SequentialAnimation on opacity {
                                        running: Clips.recording && !Clips.paused
                                        loops: Animation.Infinite
                                        NumberAnimation { to: 0.25; duration: Motion.pulse; easing.type: Motion.ambient }
                                        NumberAnimation { to: 1.0;  duration: Motion.pulse; easing.type: Motion.ambient }
                                    }
                                }
                                StyledText {
                                    text: !Clips.recording ? "Record"
                                        : Clips.paused     ? "Paused"
                                        :                    ClockFmt.clock(root.recordSecs)
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    color: Clips.recording ? Colors.of(QsWindow.window).danger
                                                           : Colors.of(QsWindow.window).fg
                                }
                            }
                            StyledText {
                                text: Clips.recording ? (Clips.paused ? "Resume to carry on"
                                                         : root.limitLine !== "" ? root.limitLine : "Alt+F9 stops it")
                                                      : (Clips.limit.id !== "off" ? "Stops after " + Clips.limit.label : "Alt+F9 · starts now")
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
                                tint: Colors.of(QsWindow.window).danger
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
                                onActivated: UiState.sidePanel === "clips"
                                    ? UiState.openSidePanel("clipsTarget", UiState.sidePanelFrom,
                                                            UiState.sidePanelScreen)
                                    : UiState.openSettingsTo("ClipsPage.qml")
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
                            delegate: Rectangle {
                                id: presetPill
                                required property var modelData
                                readonly property bool lit: Clips.preset !== null && Clips.preset.id === presetPill.modelData.id
                                width: presetText.implicitWidth + Tokens.spacingLg * 2
                                height: presetText.implicitHeight + Tokens.spacingXs * 2 + 2
                                radius: height / 2
                                color: presetPill.lit ? Colors.of(QsWindow.window).alpha(root.accent, 0.9)
                                     : presetMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.12)
                                     :                             Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                StyledText {
                                    id: presetText
                                    anchors.centerIn: parent
                                    text: presetPill.modelData.label
                                    variant: "caption"
                                    font.weight: presetPill.lit ? Font.DemiBold : Font.Medium
                                    color: presetPill.lit ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg
                                }
                                MouseArea {
                                    id: presetMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Clips.applyPreset(presetPill.modelData.id)
                                }
                            }
                        }
                    }
                    // How it is recorded: the video, then the sound — two pills.
                    Flow {
                        width: parent.width
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: [
                                { icon: "videocam", text: ClipsJs.summary(Clips.opts) },
                                { icon: "volume_up", text: ClipsJs.audioText(Clips.opts) }
                            ]
                            delegate: Rectangle {
                                id: pill
                                required property var modelData
                                width: Math.min(pillRow.implicitWidth + Tokens.spacingMd * 2, parent.width)
                                height: pillRow.implicitHeight + Tokens.spacingXs * 2
                                radius: height / 2
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                Row {
                                    id: pillRow
                                    anchors.centerIn: parent
                                    spacing: Tokens.spacingSm
                                    MaterialIcon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: pill.modelData.icon
                                        variant: "caption"
                                        color: root.accent
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: pill.modelData.text
                                        variant: "caption"
                                        color: Colors.of(QsWindow.window).fgMuted
                                    }
                                }
                            }
                        }
                    }
                }

                // ══ Latest ════════════════════════════════════════════════════
                // Up to three, thumbnail over name.
                Tile {
                    popIndex: 3

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
                        StyledText {
                            visible: Clips.clips.length > 0
                            text: Clips.clips.length + (Clips.clips.length === 1 ? " clip" : " clips")
                            variant: "micro"
                            emphasis: "dim"
                        }
                        // The library, one labelled tap away (also Alt+F8, and "Clips library" in the launcher).
                        ChipTray {
                            ChipButton {
                                symbol: "movie"
                                label: Translation.tr("Library")
                                on: true
                                tint: root.accent
                                onActivated: { UiState.closeSidePanel(); Clips.openGallery() }
                            }
                        }
                    }

                    // Nothing yet.
                    ColumnLayout {
                        width: parent.width
                        visible: Clips.clips.length === 0
                        spacing: Tokens.spacingXs
                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            name: "movie"
                            font.pixelSize: Tokens.iconXl + Tokens.spacingXs
                            color: Colors.of(QsWindow.window).fgFaint
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
                        visible: Clips.clips.length > 0
                        spacing: Tokens.spacingSm
                        readonly property real cardW: Math.floor((latestRow.width - latestRow.spacing * 2) / 3)

                        Repeater {
                            model: Clips.clips.slice(0, root.latestCount)
                            delegate: Item {
                                id: clipRow
                                required property var modelData
                                required property int index
                                width: latestRow.cardW
                                height: thumb.height + names.implicitHeight + Tokens.spacingXs

                                // Each thumbnail arrives on a spring, a beat after the one before.
                                PopIn { id: pop; active: true; index: clipRow.index; delay: Motion.stagger * 6 }
                                opacity: pop.opacity
                                scale:   pop.scale

                                // A handler, not the MouseArea's containsMouse: that goes false the
                                // moment the pointer is over the copy button, which would hide it.
                                HoverHandler { id: rowHover }
                                MouseArea {
                                    id: clipRowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { UiState.closeSidePanel(); Clips.playClip(clipRow.modelData.path) }
                                }
                                ClipThumb {
                                    id: thumb
                                    width: clipRow.width
                                    height: Math.round(thumb.width * 9 / 16)
                                    entry: clipRow.modelData
                                    showDuration: false
                                    decodeWidth: 240
                                    // Lifts toward the pointer: the card says it is playable.
                                    scale: rowHover.hovered ? 1.04 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }

                                    // A play disc over the frame, under the pointer.
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: Tokens.iconXl + Tokens.spacingSm
                                        height: width
                                        radius: width / 2
                                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.55)
                                        opacity: rowHover.hovered ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            name: "play_arrow"
                                            fill: 1
                                            variant: "label"
                                            color: Colors.of(QsWindow.window).fg
                                        }
                                    }
                                }
                                // Copy rides the thumbnail's corner, shown on hover.
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
                                        elide: Text.ElideMiddle
                                        text: clipRow.modelData.name ?? ""
                                        variant: "caption"
                                    }
                                    StyledText {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: ClockFmt.clock(clipRow.modelData.duration) + "  ·  "
                                              + ClipsJs.age(clipRow.modelData.mtime, root.nowMs)
                                        variant: "micro"
                                        emphasis: "dim"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The latest clips it lists: a strip of three. On a very short edge the strip would not
    // fit at all, so it keeps just the newest.
    readonly property int latestCount: root.maxHeight < Tokens.sideCardUnit * 8 ? 1 : 3

    // ── A card: flat, on the section fill, its rows stacked ───────────────────
    // `tone` washes it with a colour (the buffer running, a recording); `popIndex` is when it
    // arrives, on a spring, after the cards before it.
    component Tile: Rectangle {
        id: tileRect
        default property alias rows: inner.data
        property color tone: "transparent"
        property int popIndex: 0

        Layout.fillWidth: true
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
