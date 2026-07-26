import QtQuick
import "../config"

// ── Meter ─────────────────────────────────────────────────────────────────────
// One ratio against its limit: a track, and a fill showing how much of it is used.
//
// ── Why this and not a ring ───────────────────────────────────────────────────
// A radial gauge for a single ratio is a two-slice pie wearing a hat, and a two-slice
// pie is the canonical wrong answer for "one value against a limit" — you're asking
// the eye to compare arc lengths when a bar lets it compare positions. A track also
// speaks the language this shell already speaks: ValueSlider's rail and the overview's
// brightness fill are the same shape.
//
// ── The fill does not change colour with the value ────────────────────────────
// The tempting move is green→amber→red as it fills. That double-encodes the fill's
// LENGTH as its hue: two channels spent on one fact, and the colour stops being able
// to mean anything else. Length is the value. If a threshold genuinely matters, that's
// what `limit` is for — a mark, not a repaint.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real value: 0            // 0..1
    property color accent: Colors.focus

    // Draw a hairline at this fraction — a capacity line, a target. 0 = none.
    property real limit: 0

    // How long the fill takes to reach a new value. The default suits a value that
    // changes when something HAPPENS (a disk fills, a battery drains). A meter
    // following a live signal — an audio peak arriving many times a second — wants
    // `Motion.track` instead: at 150ms each new peak is still easing toward the last
    // one when it arrives, so the bar reads as a smear at a middling level rather
    // than as the signal.
    property int fillDuration: Motion.standard

    implicitHeight: 8

    readonly property real _v: Math.max(0, Math.min(1, root.value))

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color:  Colors.alpha(Colors.fg, 0.10)

        // ── The fill ──────────────────────────────────────────────────────────
        // Inset from the track and rounded to match, so the fill sits INSIDE its
        // groove instead of covering it. Without the inset a full meter's square-ish
        // corners overhang the track's rounded ones — the same fix the overview's
        // brightness slider needed.
        Rectangle {
            readonly property int pad: 1

            x: pad
            y: pad
            height: parent.height - pad * 2
            // Never narrower than its own corner: a 1% fill with radius 3 renders as a
            // squashed lozenge with no straight edge, which reads as a rendering fault
            // rather than as "nearly empty".
            width: Math.max(height, (parent.width - pad * 2) * root._v)
            radius: height / 2
            color: root.accent

            Behavior on width { NumberAnimation { duration: root.fillDuration; easing.type: Motion.travel } }
        }
    }

    // Solid hairline, never dashed — dashing reads as "projected" or "threshold" when
    // it's just a mark, and adds noise to something 8px tall.
    Rectangle {
        visible: root.limit > 0
        width:  1
        height: parent.height + 4
        y: -2
        x: Math.round(parent.width * Math.max(0, Math.min(1, root.limit)))
        color: Colors.alpha(Colors.fg, 0.45)
    }
}
