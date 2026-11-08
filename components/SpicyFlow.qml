import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"

// ── SpicyFlow ─────────────────────────────────────────────────────────────────
// The album cover, several times over, blurred past recognition and slowly turning.
// The background the media and lyrics cards sit on.
//
// ── It is the COVER, not colours taken from it ────────────────────────────────
// The first version drew coloured discs from the extracted palette, and it was wrong in a
// way that is obvious next to the real thing: an accent plus two variants is three
// colours, where a cover is a continuous field of them — gradients, a warm side and a
// cool one, the halo around a bright subject. Blurring the artwork keeps all of that.
// Reducing it to three swatches and drawing circles throws away the exact thing that made
// the effect worth having.
//
// ── Why COPIES rather than one blurred cover ──────────────────────────────────
// One blurred cover still has the cover's composition: a bright corner stays a bright
// corner however hard it is blurred, and plenty of covers put one exactly where the title
// goes. Three copies at different rotations and offsets fold those features over each
// other until none dominates, which is what turns a photograph into a field.
//
// ── The motion has to be nearly invisible ─────────────────────────────────────
// Each copy turns on its own period, none a simple multiple of another, and adjacent ones
// turn in opposite directions. Anything faster is a screensaver behind text you are
// trying to read; the eye should only notice it was moving if it looks away and back.
//
// ── It stops when nobody is looking ───────────────────────────────────────────
// `running` gates every animation. Three rotating images under a blur pass is real
// per-frame work — behind a closed overlay or a covered desktop it must cost nothing,
// the same rule the lyrics wave animator follows.
Item {
    id: flow

    // The artwork. Empty is a legitimate state — a player with no cover — and leaves the
    // flat `base` showing, which is what the card would have had anyway.
    property string source: ""

    // The card's fill. Painted underneath so the copies never reveal what is behind the
    // card through their corners, and laid back over the top at `dim`.
    property color base: Colors.of(QsWindow.window).surface

    property bool running: true

    // ── The legibility control ────────────────────────────────────────────────
    // How much of `base` goes back over the blurred art. The field can be as colourful as
    // it likes underneath as long as the text has a consistently dark ground; text over an
    // undimmed cover is the failure this whole card is arranged to avoid.
    property real dim: 0.55

    // How far the copies drift, as a fraction of the card. Small — large excursions make
    // the field pulse rather than move.
    property real travel: 0.06

    // Gates the blurred layer and the scrim together, so a missing or still-loading cover
    // shows the flat fill rather than a scrim over nothing (which is just a darker card,
    // and would make "no art" look like a different bug).
    readonly property bool hasArt: flow.source !== "" && art0.status === Image.Ready

    Rectangle {
        anchors.fill: parent
        color: flow.base
    }

    // ── The copies ────────────────────────────────────────────────────────────
    // Rendered to ONE texture and blurred together. Blurred individually each would keep
    // its own soft edge and still read as three overlapping pictures.
    Item {
        id: stack
        anchors.fill: parent
        visible: false
        layer.enabled: true

        // Oversized so a rotating square still covers the corners at every angle: a square
        // turned 45° needs √2 of its own width, and the drift asks a little more on top.
        readonly property real d: Math.max(1, Math.max(flow.width, flow.height)) * 1.7

        component Copy: Image {
            id: copy

            required property real spin       // seconds for one full turn
            required property real dir        // +1 / -1
            required property real originX    // 0…1 of the card
            required property real originY
            required property real phase      // 0…1, where in its drift it starts

            source: flow.source

            // Blurred to nothing, so there is no reason to decode it at full size. A 4K
            // cover through three copies and a blur pass is a great deal of texture for an
            // image whose finest visible detail ends up about sixty pixels across.
            // (No sourceClipRect here, so setting sourceSize is safe — see PanelHeader for
            // what happens when both are set.)
            sourceSize: Qt.size(320, 320)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            smooth: true

            width:  stack.d
            height: stack.d

            // Placed by CENTRE, so the origin reads as what it is.
            x: (flow.width  * copy.originX) - copy.width  / 2 + drift.x
            y: (flow.height * copy.originY) - copy.height / 2 + drift.y

            // Drift is a single angle read as an ellipse rather than separate x and y
            // animations: two oscillations at different periods visibly beat against each
            // other, where one angle is a current.
            QtObject {
                id: drift
                property real angle: 0
                readonly property real r: Math.min(flow.width, flow.height) * flow.travel
                readonly property real x: r * Math.cos(drift.angle)
                readonly property real y: r * 0.66 * Math.sin(drift.angle)
            }

            NumberAnimation {
                target: drift
                property: "angle"
                running: flow.running
                loops: Animation.Infinite
                from: copy.phase * 2 * Math.PI
                to:   copy.phase * 2 * Math.PI + 2 * Math.PI
                // Deliberately not the spin period, so a copy never comes back to the same
                // place and the same angle at once.
                duration: copy.spin * 1400
            }

            RotationAnimation on rotation {
                running: flow.running
                loops: Animation.Infinite
                from: 0
                to:   360 * copy.dir
                duration: copy.spin * 1000
            }
        }

        // 41 / 53 / 67 seconds — none a multiple of another, so the arrangement never
        // repeats within anything anyone will sit and watch. Alternating direction is what
        // stops two of them appearing to move as one object.
        Copy {
            id: art0
            spin: 41; dir: 1; originX: 0.30; originY: 0.32; phase: 0.00
            opacity: 1.00
        }
        Copy {
            spin: 53; dir: -1; originX: 0.72; originY: 0.46; phase: 0.40
            opacity: 0.70
        }
        Copy {
            spin: 67; dir: 1; originX: 0.48; originY: 0.74; phase: 0.75
            opacity: 0.55
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: stack
        visible: flow.hasArt

        blurEnabled: true
        blur: 1.0
        // Large, because the copies are large. A blur small relative to the picture leaves
        // the picture legible, which is the one thing this must not be.
        blurMax: 64
        autoPaddingEnabled: false

        // Saturation lifted, brightness barely touched. The darkening is the scrim's job,
        // in the card's OWN colour — crushing brightness here instead greys the field out
        // and loses the hue that is the entire reason for using the cover.
        saturation: 0.45
        brightness: -0.05
    }

    // ── The scrim ─────────────────────────────────────────────────────────────
    // The card's own dark tone, back over the top. Flat rather than a gradient: the lyrics
    // card has text at every height, so there is no edge to bias towards, and a gradient
    // that keeps one end readable makes the other end the problem.
    Rectangle {
        anchors.fill: parent
        visible: flow.hasArt
        color: Colors.of(QsWindow.window).alpha(flow.base, flow.dim)
    }
}
