pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clips.js" as ClipsJs
import "../../services/clockfmt.js" as ClockFmt

// ── HudClipsCard ──────────────────────────────────────────────────────────────
// The clip recorder, in the order you reach for it. Three things in a row:
//   · Instant replay: the buffer as one plate, the loud one (accent container) while it runs: how
//     long it holds in large figures, a bar for how full that is, its switch. It keeps the last few
//     minutes of the screen in memory so a moment can be saved AFTER it happened.
//   · Save last: one press per length (the shortest few the buffer allows, then all of it), and
//     Record beside them, red while it records. A press waits the configured seconds first when
//     "clip ahead" is on, and says so with a cancel.
//   · The newest clip: play it, drag it out as a file, open the gallery. Rest on it and it plays,
//     muted and looping.
// Everything is services/Clips; a missing recorder disables the controls and says why. Holds the
// seconds clock only while something is running.
// ─────────────────────────────────────────────────────────────────────────────
HudCard {
    id: root
    wid: "clips"

    readonly property string blocked: Clips.blocker()

    // ── The seconds clock, while there is something to count ──────────────────
    readonly property bool counting: Clips.busy || Clips.aheadWaiting
    property bool _clockHeld: false
    function _syncClock() {
        if (root.counting === root._clockHeld) return
        if (root.counting) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._clockHeld = root.counting
    }
    onCountingChanged: root._syncClock()
    Component.onCompleted: root._syncClock()
    Component.onDestruction: if (root._clockHeld) Clock.releaseSeconds()

    readonly property real nowMs: Clock.now.getTime()
    readonly property real heldSecs: Clips.buffering && Clips.since > 0
        ? Math.min(Clips.bufferSeconds, Math.max(0, (root.nowMs - Clips.since) / 1000)) : 0
    readonly property real recordSecs: Clips.recording && Clips.recordSince > 0
        ? Math.max(0, (root.nowMs - Clips.recordSince) / 1000) : 0
    readonly property real aheadLeft: Clips.aheadWaiting
        ? Math.max(0, Clips.ahead.delay - (root.nowMs - Clips.ahead.at) / 1000) : 0
    // How full the buffer is, 0..1.
    readonly property real bufferFill: !Clips.buffering || Clips.since <= 0 ? 0
        : Math.max(0, Math.min(1, (root.nowMs - Clips.since) / 1000 / Math.max(1, Clips.bufferSeconds)))

    // Only what the plates don't already say: why it can't run, or that it's recording.
    status: root.blocked !== "" ? root.blocked
        : Clips.mode === "record" ? (Clips.paused ? Translation.tr("Recording paused · %1") : Translation.tr("Recording · %1"))
                                    .arg(ClockFmt.clock(root.recordSecs))
        : ""

    // ══ Instant replay: the buffer ═══════════════════════════════════════════
    Rectangle {
        id: replay
        readonly property color ink: Clips.buffering ? root.pal.fgOnPrimaryContainer : root.pal.fg
        readonly property color inkDim: Clips.buffering ? root.pal.alpha(root.pal.fgOnPrimaryContainer, 0.72) : root.pal.fgMuted
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumWidth: Tokens.sideCardUnit * 4
        radius: Tokens.radiusCard
        color: Clips.buffering ? root.pal.primaryContainer : root.pal.section
        Behavior on color { ColorAnimation { duration: Motion.standard } }
        enabled: root.blocked === ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Instant replay")
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: replay.ink
                    elide: Text.ElideRight
                    HoverTip {
                        text: Translation.tr("Keeps the last few minutes of your screen in memory, so you can save a moment after it happens.")
                    }
                }
                Toggle {
                    checked: Clips.clipping
                    accent: root.accent
                    onToggled: Clips.toggleClipping()
                }
            }
            Item { Layout.fillHeight: true }
            // How long it holds right now; "Off" when it is not running.
            StyledText {
                Layout.fillWidth: true
                text: Clips.buffering ? ClockFmt.clock(root.heldSecs) : Translation.tr("Off")
                font.pixelSize: Math.round(Tokens.fontDisplay * 1.25)
                font.weight: Font.Bold
                font.features: { "tnum": 1 }
                color: replay.ink
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Clips.buffering ? Translation.tr("held of %1").arg(ClipsJs.span(Clips.bufferSeconds))
                    : Clips.clipping ? (Clips.gaveUp ? Translation.tr("Stopped, it kept failing") : Translation.tr("Starting…"))
                    : Translation.tr("Turn on to keep the last %1").arg(ClipsJs.span(Clips.bufferSeconds))
                variant: "caption"
                color: replay.inkDim
                elide: Text.ElideRight
            }
            // The buffer filling: a pill that grows to the length it keeps, then stays full.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin: Tokens.spacingSm
                implicitHeight: Tokens.spacingSm
                radius: height / 2
                color: root.pal.alpha(replay.ink, 0.16)
                Rectangle {
                    width: parent.width * root.bufferFill
                    height: parent.height
                    radius: height / 2
                    color: root.pal.primary
                    Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                }
            }
        }
    }

    // ══ Save last, and Record ════════════════════════════════════════════════
    Rectangle {
        id: save
        Layout.fillHeight: true
        implicitWidth: saveCol.implicitWidth + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: root.pal.section
        enabled: root.blocked === ""

        ColumnLayout {
            id: saveCol
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                StyledText {
                    Layout.fillWidth: true
                    text: Clips.aheadWaiting ? Translation.tr("Saving in %1s").arg(Math.ceil(root.aheadLeft)) : Translation.tr("Save last")
                    variant: "label"
                    font.weight: Font.DemiBold
                    emphasis: Clips.buffering ? "normal" : "dim"
                    elide: Text.ElideRight
                }
                ChipButton {
                    visible: Clips.aheadWaiting
                    symbol: "close"
                    tonal: true
                    onActivated: Clips.cancelAhead()
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingSm

                // The shortest few the buffer allows, then all of it (0 = everything it holds).
                Repeater {
                    model: ClipsJs.saveLengths(Clips.bufferSeconds).slice(0, 3).concat([0])
                    delegate: HudTile {
                        required property int modelData
                        Layout.fillHeight: true
                        symbol: "content_cut"
                        label: modelData > 0 ? ClipsJs.span(modelData) : Translation.tr("All")
                        tint: root.accent
                        enabled: Clips.buffering && !Clips.aheadWaiting
                        onActivated: Clips.clipIt(modelData)
                    }
                }
                HudTile {
                    Layout.fillHeight: true
                    symbol: Clips.recording ? "stop" : "fiber_manual_record"
                    label: Clips.recording ? (Clips.paused ? Translation.tr("Paused") : ClockFmt.clock(root.recordSecs)) : Translation.tr("Record")
                    lit: Clips.recording
                    tint: root.pal.danger
                    onActivated: Clips.toggleRecord()
                    HoverTip { text: Clips.recording ? Translation.tr("Stop recording and keep it.") : Translation.tr("Start recording your screen now, until you stop it.") }
                }
            }
        }
    }

    // ══ The newest clip ══════════════════════════════════════════════════════
    // Play it with a click, DRAG it out as a file (Qt's drag, text/uri-list, as the gallery's handle
    // does). The overview covers the screen, so while it is dragged it LENDS the screen
    // (UiState.overviewLending: the stage fades and the input mask empties, so the drop lands on the
    // window beneath); the overview closes once the drop is taken and comes back if it isn't.
    // Dropped when the card is too narrow to give it room (a short screen, a wide island).
    Item {
        id: shelf
        Layout.preferredWidth: Math.round(root.bodyHeight * 16 / 9)
        Layout.fillHeight: true
        visible: Clips.latest !== null && root.width >= Tokens.sideCardUnit * 14

        readonly property var clip: Clips.latest
        property bool hot: false

        ClipThumb {
            id: thumb
            anchors.fill: parent
            entry: shelf.clip
            decodeWidth: 480
            radius: Tokens.radiusCard
            scale: tap.pressed ? 0.97 : 1
            Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }

            HoverHandler {
                cursorShape: Qt.PointingHandCursor
                onHoveredChanged: shelf.hot = hovered
            }
            TapHandler { id: tap; onTapped: if (shelf.clip) Clips.playClip(shelf.clip.path) }
            DragHandler { id: dragOut; target: null }
            Drag.active: dragOut.active
            Drag.dragType: Drag.Automatic
            Drag.supportedActions: Qt.CopyAction
            Drag.mimeData: ({ "text/uri-list": shelf.clip ? Clips.uriList([shelf.clip.path]) : "" })
            Drag.imageSource: shelf.clip && shelf.clip.thumb ? "file://" + shelf.clip.thumb : ""
            Drag.onDragStarted: UiState.overviewLending = true
            Drag.onDragFinished: function (action) {
                UiState.overviewLending = false
                if (action !== Qt.IgnoreAction) UiState.overviewOpen = false
            }

            // Rest on it and it plays, muted and looping, after a dwell so sweeping past does not start a
            // decoder. ClipPlayer by URL (Media's probe: qt6-multimedia is optional, and naming it would make
            // this file fail to exist without it); the thumbnail stays under it until the first frame is up.
            readonly property bool wantPreview: shelf.hot && root.running && Media.available && !dragOut.active
            property bool previewing: false
            onWantPreviewChanged: if (thumb.wantPreview) dwell.restart(); else { dwell.stop(); thumb.previewing = false }
            Timer { id: dwell; interval: 400; onTriggered: thumb.previewing = true }
            Loader {
                id: preview
                anchors.fill: parent
                active: thumb.previewing
                source: Media.playerUrl
                opacity: preview.item && preview.item.showing ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                onLoaded: {
                    preview.item.crop = true
                    preview.item.muted = true
                    preview.item.autoplay = true
                    preview.item.loopAll = true
                    preview.item.source = shelf.clip.path
                }
            }
            // The play mark gives way to the preview once it plays: it is already playing.
            MaterialIcon {
                anchors.centerIn: parent
                name: "play_arrow"
                fill: 1
                color: root.pal.fg
                font.pixelSize: Tokens.iconXl
                opacity: shelf.hot && !(preview.item && preview.item.showing) ? 1 : 0
                scale: shelf.hot ? 1 : 0.7
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
            }
        }

        // How old it is, and the gallery: pills on the picture (the thumbnail keeps its length at the bottom right).
        Rectangle {
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingSm
            implicitWidth: age.implicitWidth + Tokens.spacingMd
            implicitHeight: age.implicitHeight + Tokens.spacingXs
            radius: height / 2
            color: root.pal.fade(root.pal.surfaceHigh, 0.85)
            StyledText {
                id: age
                anchors.centerIn: parent
                text: shelf.clip ? ClipsJs.age(shelf.clip.mtime ?? 0, Date.now()) : ""
                variant: "caption"
                font.weight: Font.DemiBold
            }
        }
        ChipButton {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingSm
            symbol: "video_library"
            tonal: true
            onActivated: Clips.openGallery()
            HoverTip { text: Translation.tr("Open all your clips: watch, trim and share them.") }
        }
    }
}
