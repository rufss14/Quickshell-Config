import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── HudCap ────────────────────────────────────────────────────────────────────
// One key of the input overlay (HudInput): a key cap, a mouse button, a stat tile, the
// mouse's shell. The shell's own roles — a surfaceContainer face with the outline, the
// solid accent when lit.
//
// ── A keycap has depth ────────────────────────────────────────────────────────
// `raised` (the keys) gives the face a lip under it, in the palette's constant shadow; a
// press SINKS the face onto it. Flat parts (the mouse, the tiles) only light.
//
// ── Every press is seen, even in a burst ──────────────────────────────────────
// Lit exactly while held. A press SNAPS the accent to full; a release drains it fast
// (Motion.fast, OutCubic — most of the drop in the first few frames). So a 20 ms tap is
// still a full flash, and a 15 CPS burst reads as separate flashes: each release has
// visibly dimmed the cap before the next press relights it. (A minimum-hold latch was
// tried first: past ~8 CPS its holds overlapped and a burst read as one long press.)
// The accent is driven by explicit animations, not a `Behavior` whose duration binds to
// the same flag — those two updates aren't ordered, so a press could run the release's
// fade and a tap never visibly light.
//
// `fillOpacity` is the overlay's transparency option (hud.js `opacity`). It fades the IDLE
// face, outline and lip — never the lit accent or the text, so a see-through overlay still
// says clearly what you pressed. Corners are four properties (a mouse button squares off
// the ones it shares with its neighbour). Children draw on the face (a tile's figures).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: cap

    property bool on: false
    property string label: ""
    property bool raised: false
    // HudInput's size factor, so text, radii and depth grow with the overlay.
    property real sizeScale: 1
    property real fillOpacity: 1

    property real radius: Math.round(Tokens.radiusXs * cap.sizeScale)
    property real topLeftRadius:     cap.radius
    property real topRightRadius:    cap.radius
    property real bottomLeftRadius:  cap.radius
    property real bottomRightRadius: cap.radius

    default property alias content: face.data

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property int depth: cap.raised ? Math.max(2, Math.round(Tokens.spacingXs * 1.5 * cap.sizeScale)) : 0
    readonly property bool lit: cap.on

    onLitChanged: {
        if (cap.lit) { drain.stop(); accent.opacity = 1 }
        else drain.restart()
    }
    NumberAnimation {
        id: drain
        target: accent
        property: "opacity"
        to: 0
        duration: Motion.fast
        easing.type: Motion.travel
    }

    // The lip: what the face sinks onto.
    Rectangle {
        visible: cap.raised
        anchors.fill: parent
        anchors.topMargin: cap.depth
        topLeftRadius:     cap.topLeftRadius
        topRightRadius:    cap.topRightRadius
        bottomLeftRadius:  cap.bottomLeftRadius
        bottomRightRadius: cap.bottomRightRadius
        antialiasing: true
        color: cap.pal.alpha(cap.pal.shadow, 0.35 * cap.fillOpacity)
    }

    Rectangle {
        id: face
        width: parent.width
        height: parent.height - cap.depth
        y: cap.lit ? cap.depth : 0
        Behavior on y { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
        topLeftRadius:     cap.topLeftRadius
        topRightRadius:    cap.topRightRadius
        bottomLeftRadius:  cap.bottomLeftRadius
        bottomRightRadius: cap.bottomRightRadius
        antialiasing: true
        color: cap.pal.fade(cap.pal.surfaceContainer, cap.fillOpacity)
        border.width: Tokens.borderWidth
        border.color: cap.pal.fade(cap.pal.outline, Math.max(0.4, cap.fillOpacity))

        StyledText {
            anchors.centerIn: parent
            visible: cap.label !== ""
            text: cap.label
            variant: cap.label.length > 1 ? "caption" : "label"
            sizeScale: cap.sizeScale
            font.weight: Font.DemiBold
            color: cap.pal.fgMuted
        }

        // The accent and its own copy of the label, so the two fade as one.
        Rectangle {
            id: accent
            anchors.fill: parent
            topLeftRadius:     cap.topLeftRadius
            topRightRadius:    cap.topRightRadius
            bottomLeftRadius:  cap.bottomLeftRadius
            bottomRightRadius: cap.bottomRightRadius
            antialiasing: true
            color: cap.pal.primary
            opacity: 0
            visible: opacity > 0.01

            StyledText {
                anchors.centerIn: parent
                visible: cap.label !== ""
                text: cap.label
                variant: cap.label.length > 1 ? "caption" : "label"
                sizeScale: cap.sizeScale
                font.weight: Font.DemiBold
                color: cap.pal.fgOnPrimary
            }
        }
    }
}
