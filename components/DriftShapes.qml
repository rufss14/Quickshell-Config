pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import "../config"
import "../services"

// ── DriftShapes ───────────────────────────────────────────────────────────────
// One panel's WINDOW onto the shared cookie field (services/Drift): soft, translucent
// Scallops drifting and turning behind the content. Put inside a Card with `drift: true`,
// which is how every bar and sidebar panel gets it. The look is borrowed from Caelestia's
// media tab (a drift of blobs behind everything); the code is this shell's own, on the
// Scallop it already draws its petals with.
//
// ── A window, not a copy ──────────────────────────────────────────────────────
// This owns no shapes and no clock. Every panel draws the SAME field, each shifted by where
// it is on screen (`origin`), so a shape leaving one panel's edge is the one entering the
// next, and a panel opening or swapping reveals the drift instead of restarting it. How
// strongly a shape is drawn is the field's to say too (`source`), never the window's. The
// field's frame loop runs while something holds it (acquire/release below), i.e. while at
// least one of these is on screen.
//
// ── Depth ─────────────────────────────────────────────────────────────────────
// A shape's size, opacity and wander follow one number, so the small ones are faint and
// settled and the big ones nearer and livelier. (Not speed: shapes at different speeds catch
// each other and pile up — see drift.js.) Each also swells and settles a few percent on its
// own beat, and every third has a faint outline, so it is not all flat discs.
//
// ── The edges ─────────────────────────────────────────────────────────────────
// Masked to the card's rounded corners (a panel's content area clips to a RECTANGLE, so a
// shape would poke past the corner). While the bar has no cookies of its own, also faded in over
// `fade` pixels at the TOP — where the panel meets the bar, and a hard clip read as the shapes
// being sliced off — with a hairline (`seam`) along that edge, inset by the corner radius, so the
// join reads as a deliberate line rather than a cut. The seam sits outside the masked layer, or the
// fade would swallow it. A window with no corners and no fade (a piece of the frame, a strip
// between two panels) needs no mask at all, and is clipped instead.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The card's corner radius — the mask's.
    property real radius: Tokens.radiusCard
    // How far down the shapes take to arrive at full strength — none while the bar carries the field
    // on (Drift.flows): the fade existed so a shape would not be cut where the panel met a bar with
    // none; with the bar showing the same shape, the fade is what cuts it.
    property real fade: Drift.flows ? 0 : Tokens.spacingXl * 2
    // Likewise the hairline along that join.
    property bool seam: !Drift.flows
    // Which edge(s) of this card are WELDED to something that carries the field on — "top" for a bar
    // panel, "left" / "right" / "bottom" for a sidebar panel on that edge; "" for a floating card. When
    // the field flows (Drift.flows) the mask is SQUARE at those corners. A welded card is still drawn
    // with rounded corners (the blob fills the wedge between each one and the bar), so a mask rounded
    // the same way left that wedge — real material, in the bar's colour — with no cookie in it while
    // the bar's layer stopped at the bar's edge: a cookie crossing there was cut along an arc. Square,
    // the card's field covers the wedge and runs straight into the bar's. Only where it IS welded: a
    // floating card's corners are its real edge, and a square mask there drew cookies past them.
    property string joins: ""
    function _corner(a, b) {
        return (Drift.flows && (root.joins.indexOf(a) >= 0 || root.joins.indexOf(b) >= 0)) ? 0 : root.radius
    }
    // A panel — where the field comes from — draws every shape at its own full strength. Every other
    // window (the bar's band, the frame, the sidebar, the strips bridging them to a panel) draws each
    // picture at the strength the field gives THAT picture (Drift.strength): the same number in every
    // window, so where two windows meet, a shape crossing between them is drawn alike on both sides.
    // `screenKey` is this screen's name (the panels and the recorded pictures are kept per screen).
    property bool source: true
    property string screenKey: ""
    // What this window is, for the debug outline (Drift.debug): "card", "bridge", "ring", "side", "gap".
    property string role: "card"
    // The whole field shifted by this many px — a parallax (the overview's, UiState.overviewDrift).
    // Every window onto the field in one place must take the SAME shift, or a shape crossing
    // between them jumps by the difference.
    property point shift: Qt.point(0, 0)

    readonly property bool on: Config.panelCookies && root.visible && root.width > 0 && root.height > 0

    // ── Held while it is on screen ────────────────────────────────────────────
    property bool _held: false
    function _sync() {
        if (root.on && !root._held)       { Drift.acquire(); root._held = true }
        else if (!root.on && root._held)  { Drift.release(); root._held = false }
    }
    onOnChanged: root._sync()
    Component.onCompleted: root._sync()
    // A destroyed panel must not keep the frame loop alive.
    Component.onDestruction: if (root._held) Drift.release()

    // Where this window's top-left is on the screen. The bar's window is anchored to the
    // screen's top-left corner, so its own coordinates ARE the screen's. Re-read every
    // frame the field ticks: a panel that slides, grows or is dragged has no notifying scene
    // position, and the tick is the one thing that already fires each frame it moves.
    readonly property point origin: { Drift.frame; return root.mapToItem(null, 0, 0) }
    // What lands in this window this tick (see the pool below). The window's screen rect is its
    // box from `origin`, grown 6% for a card mid-scale (0.96 → 1) so a corner shape is not dropped.
    readonly property var _pics: root.on
        ? Drift.windowPictures(root.origin.x - root.shift.x - root.width * 0.03, root.origin.y - root.shift.y - root.height * 0.03,
                               root.width * 1.06, root.height * 1.06, root.source, root.screenKey)
        : []

    readonly property var tones: [Colors.of(QsWindow.window).primary,
                                  Colors.of(QsWindow.window).focus,
                                  Colors.of(QsWindow.window).outline,
                                  Colors.of(QsWindow.window).fg]

    // ── The field, through the mask ───────────────────────────────────────────
    // Only a window with a corner or a fade has anything for a mask to do. For a plain rectangle a
    // clip is the same edge, without rendering the window offscreen every frame — and the frame alone
    // is a dozen such windows, redrawn for as long as the bar is up.
    readonly property bool _masked: root.radius > 0 || root.fade > 0
    Item {
        id: field
        anchors.fill: parent

        clip: !root._masked
        layer.enabled: root.on && root._masked
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: clipMask
        }

        // The mask: the card's rounded rectangle, fading in at the top (see the header) and
        // NOT feathered anywhere else. It was, for a round: blurred on every edge so the
        // clip would dissolve rather than cut. But two panels side by side share an edge, and
        // feathering BOTH sides of it dims a shape exactly where it crosses from one into the
        // other — a pale notch and a visible line through the cookie, the very thing the shared
        // field exists to avoid. A shape now runs right up to the edge of the card it is in, and
        // the two halves at a junction meet.
        Item {
            id: clipMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                radius: root.radius
                topLeftRadius:     root._corner("top", "left")
                topRightRadius:    root._corner("top", "right")
                bottomLeftRadius:  root._corner("bottom", "left")
                bottomRightRadius: root._corner("bottom", "right")
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: Math.min(0.5, Math.max(0.001, root.fade / Math.max(1, root.height))); color: "white" }
                    GradientStop { position: 1.0; color: "white" }
                }
            }
        }

        // ── A pool, not a shape per item ──────────────────────────────────────
        // The window asks the field once a tick what lands in it (`_pics`, drift.js
        // `windowPictures`) and a fixed pool draws that. It used to be one bound Scallop per
        // shape, 28 a window, each re-running a dozen bindings every frame because the field it
        // read had changed — though most were nowhere near the window. Measured worst cases: 9
        // in a piece of the bar, 5 in a strip (drift.js tests), all 28 in a big card.
        Repeater {
            model: root.on ? (root.source ? Drift.count : 12) : 0

            delegate: Scallop {
                id: sh
                required property int index

                readonly property var p: root._pics[sh.index] ?? null
                readonly property color tone: sh.p ? root.tones[sh.p.tone] : "transparent"

                visible: sh.p !== null
                // A slot moves to another shape only when one enters or leaves the window; the
                // petals must not then animate from the last one's (Scallop's own Behavior).
                animatePetals: false
                width:  sh.p ? sh.p.size : 0
                height: sh.p ? sh.p.size : 0
                points: sh.p ? sh.p.points : 8
                petalDepth: sh.p ? sh.p.petal : 0

                // Where the picture sits on the SCREEN, then back through this card's whole
                // transform to where that is in the card. Using only the card's translation
                // was right at rest and wrong in motion: a panel opening also scales (from
                // 0.96) and the blob's spring deforms it, and both move things in
                // proportion to their distance from the origin — so the corners slid against
                // the screen, and against the next panel's field, exactly where the eye
                // goes. Mapped through the real transform, a shape stays put on screen
                // however the panel moves.
                readonly property point at: sh.p ? root.mapFromItem(null, sh.p.x + root.shift.x, sh.p.y + root.shift.y) : Qt.point(0, 0)
                x: sh.at.x
                y: sh.at.y
                rotation: sh.p ? sh.p.r : 0
                // A few percent either way, each on its own beat.
                scale: sh.p ? sh.p.s : 1
                opacity: sh.p ? sh.p.o : 0

                fillColor: sh.tone
                strokeColor: sh.p && sh.p.outlined ? Colors.of(QsWindow.window).alpha(sh.tone, 0.55) : "transparent"
                strokeWidth: Tokens.borderWidth
            }
        }
    }

    // ── Debug outline (Drift.debug) ───────────────────────────────────────────
    // One colour per kind of window, in the palette's own roles. Over everything in this window.
    Rectangle {
        anchors.fill: parent
        visible: Drift.debug && root.on
        color: "transparent"
        border.width: 1
        border.color: root.role === "card"   ? Colors.of(QsWindow.window).info
                    : root.role === "bridge" ? Colors.of(QsWindow.window).success
                    : root.role === "ring"   ? Colors.of(QsWindow.window).warning
                    : root.role === "side"   ? Colors.of(QsWindow.window).danger
                    :                          Colors.of(QsWindow.window).primary
    }

    // ── The seam ──────────────────────────────────────────────────────────────
    Divider {
        visible: root.seam && Config.panelCookies
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.leftMargin:  root.radius
        anchors.rightMargin: root.radius
    }
}
