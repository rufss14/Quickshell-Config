import QtQuick
import Quickshell
import "../../config"

// ── OverviewGlow ──────────────────────────────────────────────────────────────
// The overlay's one ambient-light primitive: a soft accent bloom faked with a
// stack of concentric shapes that each breathe on their own period, so the pile
// drifts in and out of phase and reads as light rather than as a pulsing object.
//
// This replaces five hand-rolled copies of the same trick — behind the media
// row, behind the clock, and ×3 rings on every workspace cell — which had drifted
// apart on ring count, alpha, breathing period, and even whether the breathing
// was gated at all.
//
// Two shapes, one `circular` flag:
//   circular   a point source. Sized by `spread` (the outermost ring's
//              diameter). Behind the clock, behind the media row.
//   rounded    a bloom hugging a rectangle — behind a workspace cell. Give it
//              `contentWidth` / `contentHeight` / `contentRadius` and `reach`
//              (how far the outermost ring extends past the rectangle).
//
// Non-visual when `active` is false: the whole thing fades to nothing and the
// breathing stops. A stopped SequentialAnimation settles and costs nothing (the
// same measurement BusyDot's header records), so a closed overview's grid — up to
// ten cells — idles for free.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent:    Colors.of(QsWindow.window).primary
    property real  intensity: 1.0          // 0..1 master multiplier on every ring's alpha
    property bool  active:    true
    property bool  circular:  true

    // circular: the outermost ring's diameter.
    property real spread: 320

    // rounded: the rectangle to wrap, and how far the outermost ring reaches past it.
    property real contentWidth:  0
    property real contentHeight: 0
    property real contentRadius: Tokens.radiusCard
    property real reach:         Tokens.spacingXxl + Tokens.spacingMd

    // Rings, faint + wide → less-faint + tight. Kept deliberately weak — this is a
    // hint of colour at an edge, not a light source; anything stronger reads as a
    // smudge on the scrim. The periods are not multiples of one another, so the
    // rings drift out of phase instead of pulsing as one block.
    readonly property var _rings: [
        { f: 1.00, a: 0.010, dur: 4200 },
        { f: 0.66, a: 0.016, dur: 3400 },
        { f: 0.38, a: 0.024, dur: 2800 },
        { f: 0.18, a: 0.034, dur: 2300 }
    ]

    implicitWidth:  root.circular ? root.spread : root.contentWidth  + root.reach * 2
    implicitHeight: root.circular ? root.spread : root.contentHeight + root.reach * 2

    opacity: root.active ? 1 : 0
    visible: opacity > 0.005
    Behavior on opacity { NumberAnimation { duration: Motion.exit } }

    Repeater {
        model: root._rings

        Rectangle {
            id: ring
            required property var modelData

            anchors.centerIn: parent

            width: root.circular ? root.spread * ring.modelData.f
                                 : root.contentWidth  + root.reach * ring.modelData.f * 2
            height: root.circular ? root.spread * ring.modelData.f
                                  : root.contentHeight + root.reach * ring.modelData.f * 2
            radius: root.circular ? width / 2
                                  : root.contentRadius + root.reach * ring.modelData.f

            color: Colors.of(QsWindow.window).alpha(root.accent, ring.modelData.a * root.intensity)
            Behavior on color { ColorAnimation { duration: Motion.standard } }

            SequentialAnimation on scale {
                running: root.active
                loops: Animation.Infinite
                NumberAnimation {
                    to: root.circular ? 1.10 : 1.04
                    duration: ring.modelData.dur
                    easing.type: Motion.ambient
                }
                NumberAnimation {
                    to: root.circular ? 0.90 : 0.96
                    duration: ring.modelData.dur
                    easing.type: Motion.ambient
                }
            }
        }
    }
}
