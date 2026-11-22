pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../overview"

// ── PanelLyrics ───────────────────────────────────────────────────────────────
// The media panel's lyrics, as quiet as it can be: the words, and nothing around them.
//
// ── Why there is no header, footer or label ───────────────────────────────────
// An earlier pass gave this card a title row, a sync badge, two hairlines and a source
// pill. Beside the panel's own header, title and seek bar it said everything twice —
// "Lyrics", "Instrumental", "Instrumental" — and read as busy. The panel already says what
// is playing; this card's only job is the lyrics. So at rest it is the lyrics, fading into
// the card at the top and bottom, and that is all.
//
// What the busy version carried is still here, but only when asked for: rest the pointer
// on the card and a small pill rises at the foot with where the lyrics came from and the
// timing offset (nudge ±0.1s, tap the number to zero it).
//
// ── Nothing to read ───────────────────────────────────────────────────────────
// The lyrics card has a built-in state for this (a spectrum, the track, a seek bar, a
// pill) that suits the overview, where it is the whole card. Here it would repeat the panel
// beside it, so it is switched off (`showEmpty: false`) and replaced by one soft cookie
// with one line under it: why there are no words.
//
// The lyrics themselves are `OverviewLyrics`, unchanged — word timing, translation and
// the rest are the part that is hard to get right and are shared with every other surface.
// It sits on this card's own fill, so its fades dissolve into it.
//
// ── Flush with the panel, not a box on it ─────────────────────────────────────
// It used to be a raised card (its own lighter fill, outline and rounded corners), which
// stood out from the panel it was part of. Now it has no surface at all: the words sit on
// the panel itself, over its cookie field, and dissolve at the top and bottom through a
// transparency mask — a colour overlay, which is how OverviewLyrics fades on its own card,
// needs a solid fill to fade INTO, and there is none here.
//
// ── Fixed footprint ───────────────────────────────────────────────────────────
// It takes the height its row gives it (the owner sets preferredHeight 0); the lyrics'
// own implicit height must not decide how tall the panel is.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var  player
    required property real position
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    implicitHeight: 0

    // ── The lyrics ────────────────────────────────────────────────────────────
    OverviewLyrics {
        timing: false
        id: lyr
        anchors.fill: parent

        player:   root.player
        position: root.position
        active:   root.active

        // No fill: the words sit on the panel. And NO colour overrides: the text and the lit-word
        // accent are the cover's matched set (`AlbumArt.fg / fgDim / fgMuted / accent`) — which
        // is what the desktop lyrics widget uses and what this card's own defaults already are
        // (with the album-colours switch off, the palette). An earlier pass here mixed the
        // PALETTE's text colours with the ALBUM's accent, and the lit word, which is a blend of
        // the two, came out the wrong colour next to the widget's.
        tintBg:      "transparent"
        artWash:     false
        frameWidth:  0
        castsShadow: false
        cornerRadius: 0
        edgeFade: false
        showEmpty: false

        // Dissolve at the top and bottom of the viewport by transparency (see the header).
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
        }
    }

    Item {
        id: fadeMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        readonly property real edge: Math.min(0.45, (Tokens.spacingXl * 2) / Math.max(1, height))
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0;                   color: "transparent" }
                GradientStop { position: fadeMask.edge;         color: "white" }
                GradientStop { position: 1.0 - fadeMask.edge;   color: "white" }
                GradientStop { position: 1.0;                   color: "transparent" }
            }
        }
    }

    // ── Nothing to read ───────────────────────────────────────────────────────
    // A held copy of what to say, so a change (looking → none) fades instead of cutting,
    // and the words don't blank while the card is fading out.
    property string heldIcon:  "lyrics"
    property string heldTitle: ""
    property string heldSub:   ""

    // Asks again for the playing track: the Spotify bridge (its lyrics), and the shell's own lookup.
    function retryLyrics() {
        const uri = SpotifyBridge.trackUri
        if (uri.indexOf("spotify:track:") === 0) SpotifyBridge.refetchLyrics(uri)
        if (root.player) Lyrics.loadFor(root.player)
    }

    function _words() {
        const st = Lyrics.state
        if (st === "loading")      return { icon: "hourglass_top", title: Lyrics.loadingText, sub: Lyrics.loadingSub }
        if (st === "instrumental") return { icon: "music_note",    title: "Instrumental",        sub: "No words to sing along to" }
        if (st === "error")        return { icon: "warning",       title: "Couldn't reach a provider", sub: "Lyrics will come back with the connection" }
        if (st === "idle")         return { icon: "lyrics",        title: "Lyrics are off",      sub: "" }
        if (Lyrics.blockedReason === "connecting") return { icon: "hourglass_top", title: "Connecting to Spotify…", sub: "" }
        if (Lyrics.blockedReason === "waiting")    return { icon: "hourglass_top", title: "Waiting for Spotify",    sub: "" }
        return { icon: "lyrics", title: "No lyrics found", sub: "This track has none to show", none: true }
    }

    // ── "No lyrics found" is said last, and once ──────────────────────────────
    // Every other state here is "still looking" or a reason; this one is a verdict, and it was being given the moment the
    // fallback lookup came back empty, often a beat BEFORE the Spotify bridge's lyrics landed (the user saw it drawn over
    // lyrics that were already there). So the verdict waits: first a quiet second ask (the bridge and the fallback, once
    // per song), then a few seconds more, and if words arrive meanwhile the message never shows at all.
    readonly property bool wantsNone: lyr.emptyShown && root._words().none === true
    property bool noneSettled: false
    property string _retriedFor: ""
    function _retryQuietly() {
        const key = (root.player?.trackArtist ?? "") + "\u0001" + (root.player?.trackTitle ?? "")
        if (key === root._retriedFor) return
        root._retriedFor = key
        root.retryLyrics()
    }
    onWantsNoneChanged: {
        root.noneSettled = false
        settle.stop()
        giveUp.stop()
        if (root.wantsNone) settle.restart()
    }
    Timer { id: settle; interval: 1200; onTriggered: { root._retryQuietly(); giveUp.restart() } }
    Timer { id: giveUp; interval: 4500; onTriggered: root.noneSettled = true }
    function _hold() {
        if (!lyr.emptyShown) return
        const w = root._words()
        root.heldIcon = w.icon; root.heldTitle = w.title; root.heldSub = w.sub
    }
    // `blockedReason` too, not just `state`: the bridge settling (or the wait running out)
    // changes the reason and leaves the state alone, and a copy refreshed only on state went
    // stale — "Connecting to Spotify…" stayed up long after the bridge had answered.
    Connections {
        target: Lyrics
        function onStateChanged()         { root._hold() }
        function onBlockedReasonChanged() { root._hold() }
        function onPhaseChanged()         { root._hold() }
    }
    Connections {
        target: lyr
        function onEmptyShownChanged() { root._hold() }
    }
    Component.onCompleted: root._hold()

    Item {
        id: empty
        anchors.fill: parent
        opacity: lyr.emptyShown && (!root.wantsNone || root.noneSettled) ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        Column {
            anchors.centerIn: parent
            width: parent.width - Tokens.spacingXl * 2
            spacing: Tokens.spacingMd

            // One soft cookie, still — the panel's cover is the thing that moves.
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width:  Tokens.spacingXl * 4
                height: Tokens.spacingXl * 4

                Scallop {
                    anchors.fill: parent
                    points: 9
                    petalDepth: 0.1
                    fillColor: Colors.of(QsWindow.window).alpha(root.accent, 0.16)
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.heldIcon
                    fill: 0
                    font.pixelSize: Tokens.iconXl
                    color: root.accent
                }
                // Tapped, it asks again: Spotify's lyrics for this track, and the fallback lookup.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.retryLyrics()
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Try the lyrics again")
                    Accessible.onPressAction: root.retryLyrics()
                }
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.heldTitle
                variant: "label"
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            StyledText {
                width: parent.width
                visible: root.heldSub !== ""
                horizontalAlignment: Text.AlignHCenter
                text: root.heldSub
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }
    }

    // ── The game's readout (combo, accuracy and rank, the judgment of each line) ─
    // Only while Karaoke is on, in the corners so the words stay clear; outside the masked card so
    // it stays crisp. Takes no input.
    KaraokeHud {
        anchors.fill: parent
        accent: root.accent
    }

    // ── On request: where from, and the timing offset ─────────────────────────
    HoverHandler { id: hover }

    readonly property string provenance:
        Lyrics.viaBridge ? Lyrics.provider + (Lyrics.community ? " · community" : "")
        : (Lyrics.source || "Fallback lookup")

    // ── The same pill as the panel's header ───────────────────────────────────
    // A ChipTray (solid container fill, hairline edge, round chips) — the look this panel's
    // own header already has — rather than a tinted capsule of its own. The source is a soft
    // accent chip at its head, the offset a stepper beside it: minus and plus are ChipButtons
    // (an icon on the tray until the pointer lights it), and the number between them is
    // dim at 0 and takes the accent once there is a correction to read; tapping it zeroes.
    LyricsTiming {
        id: tools
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingSm
        shown: hover.hovered
        provenance: root.provenance
        accent: root.accent
    }
}
