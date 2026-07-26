pragma ComponentBehavior: Bound

import QtQuick
import "../config"

// ── Spectrum ──────────────────────────────────────────────────────────────────
// A bar spectrum for the Cava service: N levels in, N bars out, bottom-aligned.
//
// Extracted from VisualizerPill, which had the only copy. The settings Sound page wants
// the same spectrum at a very different size, and the shell has been down the road of
// "each widget draws its own" with this exact feature before — three cava processes and
// three renderers, which is what the Cava service was created to end. The renderer had
// stayed duplicated after the service was shared; now it isn't.
//
// ── Sizing ────────────────────────────────────────────────────────────────────
// Bars always fill the available width: bar width is derived, not set. A caller that
// wants a specific bar width sizes the SPECTRUM to suit — with n bars and gap g,
// `n * (barW + g) - g` yields exactly barW per bar. That's what VisualizerPill does, so
// its 3px bars are preserved without this component needing a fixed-width mode.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Levels, 0..1, low frequency → high. Shorter than barCount is fine — missing
    // entries read as silence rather than as an error.
    property var  levels:   []
    property int  barCount: 16
    property int  barGap:   3
    property color accent:  Colors.focus

    // A bar at zero still draws this tall, so silence reads as a quiet spectrum rather
    // than as a component that failed to render.
    property int minBarHeight: 2

    // Rounded caps look right on a tall bar and turn a short one into a lozenge, so the
    // radius is capped at half the bar's own width and disabled on thin bars.
    readonly property real _barW:
        Math.max(1, (width - root.barGap * (root.barCount - 1)) / root.barCount)

    Row {
        anchors.fill: parent
        spacing: root.barGap

        Repeater {
            model: root.barCount

            Item {
                required property int index
                width:  root._barW
                height: root.height

                readonly property real level:
                    index < root.levels.length ? Math.max(0, Math.min(1, root.levels[index])) : 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    width:  parent.width
                    height: Math.max(root.minBarHeight, Math.round(parent.level * parent.height))
                    radius: root._barW >= 4 ? Math.min(root._barW / 2, 3) : 0

                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Colors.alpha(root.accent, 0.90) }
                        GradientStop { position: 1.0; color: Colors.alpha(root.accent, 0.35) }
                    }

                    // `track`, not the UI motion scale: this follows live audio, and
                    // easing it on the standard curve smears transients into mush —
                    // the same reasoning as the peak meters on the Sound page.
                    Behavior on height {
                        NumberAnimation { duration: Motion.track; easing.type: Motion.trackCurve }
                    }
                }
            }
        }
    }
}
