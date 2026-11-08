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
// The clip recorder as the Clips panel draws it (2026-10-20, the user: "make it sort of like
// the panel"), at the card's height: flat tiles on the section fill —
//   · Clipping: the buffer as a ring (how much of its length it holds; "Off" when off), what
//     it holds, its switch; washed with the accent while it runs;
//   · Clip it (a scissors cookie — the whole buffer) and the shortest lengths it can cut,
//     then Record (a cookie: record ↔ stop) with the running time; washed red while it records;
// and, beside them, the last clips as a deck (play, drag out as a file, the gallery). Replaced
// the timeline-with-notches card. Everything is services/Clips; a missing recorder disables the
// controls and says why. Holds the seconds clock only while something is running.
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

    // Only what the tiles don't already say: why it can't run, or that it's recording.
    status: root.blocked !== "" ? root.blocked
        : Clips.mode === "record" ? (Clips.paused ? Translation.tr("Recording paused · %1") : Translation.tr("Recording · %1"))
                                    .arg(ClockFmt.clock(root.recordSecs))
        : ""

    // How full the buffer is, 0..1 (the panel's ring).
    readonly property real bufferFill: !Clips.buffering || Clips.since <= 0 ? 0
        : Math.max(0, Math.min(1, (root.nowMs - Clips.since) / 1000 / Math.max(1, Clips.bufferSeconds)))

    // ── The Clips panel's tiles, at the card's height ─────────────────────────
    // Flat tiles on the section fill (the panel's Tile), the top one washed with the accent
    // while the buffer runs.
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: Tokens.spacingSm
        enabled: root.blocked === ""

        // ══ Clipping: the buffer as a ring, its switch ═════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Clips.buffering ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.07) : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingSm
                anchors.rightMargin: Tokens.spacingMd
                spacing: Tokens.spacingMd
                RadialGauge {
                    readonly property int d: Math.max(Tokens.iconXl, parent.height - Tokens.spacingSm * 2)
                    Layout.preferredWidth: d
                    Layout.preferredHeight: d
                    thickness: Tokens.spacingXs + 1
                    value: root.bufferFill
                    accent: Clips.buffering ? root.accent : Colors.of(QsWindow.window).fgFaint
                    sampleInterval: 1000
                    StyledText {
                        anchors.centerIn: parent
                        text: Clips.buffering ? ClockFmt.clock(root.heldSecs) : "Off"
                        variant: "micro"
                        font.weight: Font.DemiBold
                        emphasis: Clips.buffering ? "normal" : "dim"
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0
                    // Named for what it does: it is an instant replay — the screen's last minutes, kept so a moment can be
                    // saved AFTER it happened. ("Clipping" read as the verb for cutting.)
                    StyledText {
                        text: Translation.tr("Instant replay")
                        variant: "label"
                        font.weight: Font.DemiBold
                        HoverTip {
                            text: Translation.tr("Keeps the last few minutes of your screen in memory, so you can save a moment after it happens.")
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Clips.buffering ? Translation.tr("On · remembering the last %1").arg(ClockFmt.clock(root.heldSecs))
                            : Clips.clipping ? (Clips.gaveUp ? Translation.tr("Stopped — it kept failing") : Translation.tr("Starting…"))
                            : Translation.tr("Off · turn on to keep the last %1").arg(ClipsJs.span(Clips.bufferSeconds))
                        variant: "micro"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                Toggle {
                    checked: Clips.clipping
                    accent: root.accent
                    onToggled: Clips.toggleClipping()
                }
            }
        }

        // ══ Clip it, the lengths it cuts; record ═══════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Tokens.radiusCard
            color: Colors.of(QsWindow.window).section
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: Clips.recording ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.09) : "transparent"
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingSm
                anchors.rightMargin: Tokens.spacingSm
                spacing: Tokens.spacingSm
                readonly property int d: Math.max(Tokens.iconXl, height - Tokens.spacingSm * 2)

                CookieButton {
                    Layout.preferredWidth: parent.d
                    Layout.preferredHeight: parent.d
                    name: "content_cut"
                    primary: true
                    tint: root.accent
                    enabled: Clips.buffering && !Clips.aheadWaiting
                    onActivated: Clips.clipIt(0)
                    HoverTip { text: Clips.buffering ? Translation.tr("Save everything the replay holds as a clip.") : Translation.tr("Turn Instant replay on first: there is nothing to save yet.") }
                }
                StyledText {
                    text: Clips.aheadWaiting ? Translation.tr("in %1s").arg(Math.ceil(root.aheadLeft)) : Translation.tr("Save last")
                    variant: "label"
                    font.weight: Font.DemiBold
                    emphasis: Clips.buffering ? "normal" : "dim"
                }
                // The lengths it can cut (clips.js saveLengths), the shortest few.
                ChipTray {
                    groupShown: Clips.buffering && !Clips.aheadWaiting
                    Repeater {
                        model: ClipsJs.saveLengths(Clips.bufferSeconds).slice(0, 3)
                        delegate: ChipButton {
                            required property int modelData
                            label: ClipsJs.span(modelData)
                            tint: root.accent
                            onActivated: Clips.clipIt(modelData)
                        }
                    }
                }
                ChipButton {
                    visible: Clips.aheadWaiting
                    symbol: "close"
                    onActivated: Clips.cancelAhead()
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    visible: Clips.recording
                    text: Clips.paused ? Translation.tr("Paused") : ClockFmt.clock(root.recordSecs)
                    variant: "label"
                    font.weight: Font.DemiBold
                    font.family: Tokens.fontMono
                    color: root.pal.danger
                }
                StyledText {
                    visible: !Clips.recording
                    text: Translation.tr("Record")
                    variant: "label"
                    font.weight: Font.DemiBold
                    emphasis: "muted"
                }
                CookieButton {
                    Layout.preferredWidth: parent.d
                    Layout.preferredHeight: parent.d
                    HoverTip { text: Clips.recording ? Translation.tr("Stop recording and keep it.") : Translation.tr("Start recording your screen now, until you stop it.") }
                    name: Clips.recording ? "stop" : "fiber_manual_record"
                    primary: Clips.recording
                    tint: root.pal.danger
                    onActivated: Clips.toggleRecord()
                }
            }
        }
    }

    // ── The last clips: a shelf ───────────────────────────────────────────────
    // The newest three, stacked like a deck. Hover and they FAN out leftwards over the
    // timeline (a spring, each a beat behind the one in front); hover one and it lifts with
    // a play mark; click plays it; DRAG one out — into a chat, a file manager — as a file
    // (Qt's drag, text/uri-list, as the gallery's handle does). The overview covers the
    // screen, so while a clip is being dragged it LENDS the screen (UiState.overviewLending:
    // its stage fades and its input mask empties, so the drop lands on the window beneath)
    // and closes once the drop is taken, or comes back if it isn't.
    // Rest on one and it plays, muted and looping, in its frame (with qt6-multimedia).
    // Under it: how old the one under the pointer is (or the newest), and the gallery.
    // Dropped when the card is too narrow to give it room (a short screen's grid, a wide island).
    Item {
        id: shelf
        Layout.preferredWidth: Tokens.sideCardUnit * 2.8
        Layout.fillHeight: true
        visible: Clips.latest !== null && root.width >= Tokens.sideCardUnit * 10
        z: 2

        readonly property var deck: Clips.clips.slice(0, 3)
        readonly property real thumbW: shelf.width
        readonly property real thumbH: Math.round(shelf.thumbW * 9 / 16)
        // Room above the front card for the two behind it to peek up.
        readonly property real baseY: Tokens.spacingSm * 2
        // The one under the pointer (-1: none), and whether the deck is fanned. Fanning
        // outlives the pointer by a beat, so moving from one card to the next (a moment over
        // neither) doesn't fold it.
        property int hot: -1
        readonly property bool wantFan: shelfHover.hovered || shelf.hot >= 0
        property bool fanned: false
        onWantFanChanged: if (shelf.wantFan) { fold.stop(); shelf.fanned = true } else fold.restart()
        Timer { id: fold; interval: Motion.standard; onTriggered: shelf.fanned = false }
        readonly property var shown: shelf.hot >= 0 ? (shelf.deck[shelf.hot] ?? Clips.latest) : Clips.latest

        HoverHandler { id: shelfHover }

        Repeater {
            model: shelf.deck

            ClipThumb {
                id: card
                required property var modelData
                required property int index
                readonly property bool hot: shelf.hot === card.index

                entry: card.modelData
                decodeWidth: 240
                showDuration: card.index === 0 || shelf.fanned
                width: shelf.thumbW
                height: shelf.thumbH
                z: shelf.deck.length - card.index
                // At rest a deck (each one behind peeking up and left, smaller); fanned, a
                // spread to the left with a slight turn, the front one where the deck was.
                x: shelf.fanned ? -card.index * shelf.thumbW * 0.62 : -card.index * Tokens.spacingSm
                y: shelf.baseY + (shelf.fanned ? card.index * Tokens.spacingXs : -card.index * Tokens.spacingSm)
                   + (card.hot ? -Tokens.spacingSm : 0)
                rotation: shelf.fanned ? -card.index * 4 : -card.index * 3
                scale: (shelf.fanned ? 1 : 1 - card.index * 0.07) * (cardTap.pressed ? 0.95 : 1)
                opacity: shelf.fanned || card.index === 0 ? 1 : 0.7 - card.index * 0.15
                Behavior on x { NumberAnimation { duration: Motion.spatial + card.index * Motion.stagger * 2; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on rotation { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                HoverHandler {
                    cursorShape: Qt.PointingHandCursor
                    onHoveredChanged: {
                        if (hovered) shelf.hot = card.index
                        else if (shelf.hot === card.index) shelf.hot = -1
                    }
                }
                TapHandler { id: cardTap; onTapped: Clips.playClip(card.modelData.path) }
                DragHandler { id: dragOut; target: null }
                Drag.active: dragOut.active
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.CopyAction
                Drag.mimeData: ({ "text/uri-list": Clips.uriList([card.modelData.path]) })
                Drag.imageSource: card.modelData.thumb ? "file://" + card.modelData.thumb : ""
                Drag.onDragStarted: UiState.overviewLending = true
                Drag.onDragFinished: function (action) {
                    UiState.overviewLending = false
                    if (action !== Qt.IgnoreAction) UiState.overviewOpen = false
                }

                // ── The hover preview ─────────────────────────────────────────────
                // Rest on a clip and it plays, muted and looping, in its own frame — after a
                // dwell, so sweeping across the deck doesn't start three decoders. The player is
                // ClipPlayer by URL (Media's probe: qt6-multimedia is optional, and naming it
                // would make this file fail to exist without it); the thumbnail stays under it
                // until the first frame is up.
                readonly property bool wantPreview: card.hot && root.running && Media.available && !dragOut.active
                property bool previewing: false
                onWantPreviewChanged: if (card.wantPreview) dwell.restart(); else { dwell.stop(); card.previewing = false }
                Timer { id: dwell; interval: 400; onTriggered: card.previewing = true }
                Loader {
                    id: preview
                    anchors.fill: parent
                    active: card.previewing
                    source: Media.playerUrl
                    opacity: preview.item && preview.item.showing ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    onLoaded: {
                        preview.item.crop = true
                        preview.item.muted = true
                        preview.item.autoplay = true
                        preview.item.loopAll = true
                        preview.item.source = card.modelData.path
                    }
                }

                // A ring and a play mark on the one under the pointer.
                Rectangle {
                    anchors.fill: parent
                    // `card`, not `parent`: inside a ClippingRectangle (ClipThumb) the parent is its content item, which
                    // has no radius ("Unable to assign [undefined] to double", 10x per overview open).
                    radius: card.radius
                    color: root.pal.alpha(root.pal.base, card.hot && !(preview.item && preview.item.showing) ? 0.25 : 0)
                    border.width: card.hot ? Tokens.borderChrome : 0
                    border.color: root.accent
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "play_arrow"
                    fill: 1
                    color: root.pal.fg
                    font.pixelSize: Tokens.iconXl
                    // Gives way to the preview once it plays: it's already playing.
                    opacity: card.hot && !(preview.item && preview.item.showing) ? 1 : 0
                    scale: card.hot ? 1 : 0.7
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                }
            }
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            spacing: Tokens.spacingXs
            StyledText {
                Layout.fillWidth: true
                text: shelf.shown ? ClipsJs.age(shelf.shown.mtime ?? 0, Date.now()) : ""
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            ChipButton {
                symbol: "video_library"
                onActivated: Clips.openGallery()
                HoverTip { text: Translation.tr("Open all your clips: watch, trim and share them.") }
            }
        }
    }
}
