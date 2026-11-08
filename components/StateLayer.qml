import QtQuick
import Quickshell
import QtQuick.Shapes
import "../config"

// ── StateLayer ────────────────────────────────────────────────────────────────
// Material 3's state layer: a hover wash plus a ripple that expands from the
// point you actually pressed, rather than from the middle of the control.
//
// ── It is NOT a MouseArea, and that inversion is the whole design ─────────────
// caelestia's is, because their controls have no other input handler. Every
// control HERE already owns one: IconButton derives `hovered`, `pressed`, `fg`
// and its entire state ladder from a MouseArea called `mouse`, and PanelButton
// does the same. Laying a second MouseArea over the top would silently steal
// hover from the first — the ladder would stop responding and the ripple would
// become the only feedback left, which looks like the button half-working.
//
// So this takes `hovered` as an INPUT and is driven by the owner's own handler
// through press()/release(). One handler, one source of truth.
//
// ── Why a Shape and not a clipped Rectangle ───────────────────────────────────
// `clip: true` clips to the BOUNDING BOX, never to rounded corners — so a circle
// expanding inside a bar pill would square off at every corner. A Shape path
// traces the real per-corner radii, and the wave is painted by a RadialGradient
// FILLING that path: the disc is clipped to the pill's true silhouette for free,
// with no second render target. That is also why there is one path and not a
// path plus a circle.
//
// The hover wash is a plain Rectangle rather than a second Shape — Rectangle has
// had per-corner radii since 6.7 and renders them exactly, so there is no reason
// to pay for a second set of Shape geometry that never animates.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The colour BOTH the wash and the wave are drawn in. Named `layerColor`
    // rather than `color` because Item has no `color` — calling it that would
    // read like a Rectangle property and invite someone to expect a fill.
    property color layerColor: Colors.of(QsWindow.window).fg

    // Driven by the owner's MouseArea. Never read back — this component has no
    // opinion about the pointer, only about what to paint.
    property bool hovered: false

    // M3's own state-layer alpha (Tokens.stateHover). Set to 0 by any control that already
    // draws its own hover tint (IconButton does, louder, and two of them would double up).
    property real hoverOpacity: Tokens.stateHover

    // Being carried (a desktop tile in arrange mode): M3's dragged layer, the loudest of
    // the four, held for as long as the drag lasts. Under the ripple, over the hover wash.
    property bool dragged: false
    property real dragOpacity: Tokens.stateDrag

    // ── The hover reveal ──────────────────────────────────────────────────────
    // Opt-in. Instead of the whole control fading to its hover tint at once, the tint
    // grows as a soft disc from where the pointer came in, and fades when it leaves —
    // the same wave language as the press ripple, one step quieter. `hoverOpacity` is
    // the tint's alpha either way. `pointerX/Y` are the OWNER's MouseArea
    // (`pointerX: mouse.mouseX`), read at the moment `hovered` flips; with none given
    // it grows from the centre.
    property bool reveal: false
    // A hairline in the layer's colour round the revealed tint, for a control too small for
    // the tint alone to read (a 24px bar button). Reveal mode only; 0 = none.
    property real ringOpacity: 0
    property real pointerX: root.width  / 2
    property real pointerY: root.height / 2

    property real _hx: 0
    property real _hy: 0
    property real _hr: 0
    property real _ha: 0

    onHoveredChanged: if (root.reveal) root._revealTo(root.hovered)

    function _revealTo(on) {
        hoverIn.stop()
        hoverOut.stop()
        // Motion off: state feedback is not decoration, so the tint still shows — it just
        // doesn't travel (unlike the ripple, where there is no meaningful instant version).
        if (Motion.ripple <= 0) {
            root._hr = root._coverFrom(root.width / 2, root.height / 2)
            root._ha = on ? root.hoverOpacity : 0
            return
        }
        if (on) {
            root._hx = root.pointerX
            root._hy = root.pointerY
            root._hr = 0
            root._ha = root.hoverOpacity
            hoverIn.restart()
        } else {
            hoverOut.restart()
        }
    }

    // Radius that covers the whole control from (x, y), with headroom (as the ripple's).
    function _coverFrom(x, y) {
        return 1.3 * Math.max(Math.hypot(x, y), Math.hypot(root.width - x, y),
                              Math.hypot(x, root.height - y), Math.hypot(root.width - x, root.height - y))
    }

    NumberAnimation {
        id: hoverIn
        target: root; property: "_hr"
        to: root._coverFrom(root._hx, root._hy)
        duration: Motion.exit
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecel
    }

    NumberAnimation {
        id: hoverOut
        target: root; property: "_ha"
        to: 0
        duration: Motion.respond
        easing.type: Motion.exitCurve
    }

    readonly property real _hSoftStop:
        Math.max(0.01, Math.min(0.99, 1 - root._softPx / Math.max(1, root._hr)))

    // Mirrored from whatever this sits on. A caller with one uniform radius can
    // set `radius` and let the four track it.
    property real radius: 0
    property real topLeftRadius:     root.radius
    property real topRightRadius:    root.radius
    property real bottomLeftRadius:  root.radius
    property real bottomRightRadius: root.radius

    // ── The ripple ────────────────────────────────────────────────────────────
    // press() defaults to the centre precisely so a KEYBOARD activation — which
    // has no press point — is a legal caller and still gets a wave.
    //
    // No clamping of x/y is needed: they arrive from the owner's own MouseArea and
    // are inside the control by construction. (caelestia needs a C++ CUtils.clamp
    // only because their StateLayer accepts coordinates from outside itself. QML
    // has no clamp built in; Math.min/Math.max is the answer if that changes.)
    function press(x, y) {
        // ── "Turn off animations" must mean ABSENT, not instant ───────────────
        // Motion.ripple collapses to 0 when Config.motionEnabled is off, and a
        // 0ms NumberAnimation does not skip — it JUMPS to its end value. The wave
        // would snap to full size, cover the whole control, and vanish a frame
        // later: a flash on every click, which is worse than the thing that was
        // switched off. There is no meaningful zero-duration ripple, so there
        // isn't one.
        if (Motion.ripple <= 0) return

        root._px = (x === undefined) ? root.width  / 2 : x
        root._py = (y === undefined) ? root.height / 2 : y
        rippleFade.stop()
        rippleOut.stop()
        root._released = false
        root._radius = 0
        root._alpha  = root.pressOpacity
        rippleOut.restart()
    }

    // Fades the wave out — but only once it has finished travelling. A quick click
    // releases long before the wave has crossed the control, and killing it there
    // makes a fast click look like nothing happened at all. The flag is checked
    // again in rippleOut's onStopped for exactly that case.
    function release() {
        root._released = true
        if (!rippleOut.running) rippleFade.restart()
    }

    property real pressOpacity: Tokens.statePress

    property real _px: 0
    property real _py: 0
    property real _radius: 0
    property real _alpha: 0
    property bool _released: false

    // Furthest corner from the press point, with headroom so the wave has visibly
    // LEFT the control before it fades rather than stopping at the edge.
    readonly property real _endRadius: 1.3 * Math.max(
        Math.hypot(root._px,              root._py),
        Math.hypot(root.width - root._px, root._py),
        Math.hypot(root._px,              root.height - root._py),
        Math.hypot(root.width - root._px, root.height - root._py))

    // The soft leading edge, held at roughly a constant PIXEL width instead of a
    // constant fraction — a fractional band grows with the wave and turns the
    // whole thing into a smear by the time it crosses the control.
    readonly property real _softStop:
        Math.max(0.01, Math.min(0.99, 1 - root._softPx / Math.max(1, root._radius)))
    readonly property real _softPx: Tokens.spacingLg

    NumberAnimation {
        id: rippleOut
        target: root; property: "_radius"
        to: root._endRadius
        duration: Motion.ripple
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecel
        // Covers the release-before-arrival case above.
        onStopped: if (root._released) rippleFade.restart()
    }

    NumberAnimation {
        id: rippleFade
        target: root; property: "_alpha"
        to: 0
        duration: Motion.exit
        easing.type: Motion.exitCurve
    }

    // ── The hover wash ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.layerColor
        opacity: (root.hovered && !root.reveal) ? root.hoverOpacity : 0
        radius:            root.radius
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius

        Behavior on opacity {
            NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve }
        }
    }

    // ── The drag wash ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: root.layerColor
        opacity: root.dragged ? root.dragOpacity : 0
        visible: opacity > 0.001
        radius:            root.radius
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        Behavior on opacity {
            NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve }
        }
    }

    // ── The hover ring ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "transparent"
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(root.layerColor, root.ringOpacity)
        radius:            root.radius
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        opacity: (root.reveal && root.hovered && root.ringOpacity > 0) ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
    }

    // ── The wave ──────────────────────────────────────────────────────────────
    // CurveRenderer, as VectorIcon / ConcaveCorner / FrameFusion already use: the
    // geometry renderer visibly facets small curves, and every corner here is one.
    Shape {
        anchors.fill: parent
        visible: root._alpha > 0.001 || root._ha > 0.001
        preferredRendererType: Shape.CurveRenderer

        // The hover reveal, under the ripple. Same rounded rect, traced the same way.
        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root._hx; centerY: root._hy
                focalX:  root._hx; focalY:  root._hy
                centerRadius: root._hr

                GradientStop { position: 0.0;              color: Colors.of(QsWindow.window).alpha(root.layerColor, root._ha) }
                GradientStop { position: root._hSoftStop;  color: Colors.of(QsWindow.window).alpha(root.layerColor, root._ha) }
                GradientStop { position: 1.0;              color: Colors.of(QsWindow.window).alpha(root.layerColor, 0) }
            }

            startX: root._c(root.topLeftRadius); startY: 0

            PathLine { x: root.width - root._c(root.topRightRadius); y: 0 }
            PathArc {
                x: root.width; y: root._c(root.topRightRadius)
                radiusX: root._c(root.topRightRadius); radiusY: root._c(root.topRightRadius)
            }
            PathLine { x: root.width; y: root.height - root._c(root.bottomRightRadius) }
            PathArc {
                x: root.width - root._c(root.bottomRightRadius); y: root.height
                radiusX: root._c(root.bottomRightRadius); radiusY: root._c(root.bottomRightRadius)
            }
            PathLine { x: root._c(root.bottomLeftRadius); y: root.height }
            PathArc {
                x: 0; y: root.height - root._c(root.bottomLeftRadius)
                radiusX: root._c(root.bottomLeftRadius); radiusY: root._c(root.bottomLeftRadius)
            }
            PathLine { x: 0; y: root._c(root.topLeftRadius) }
            PathArc {
                x: root._c(root.topLeftRadius); y: 0
                radiusX: root._c(root.topLeftRadius); radiusY: root._c(root.topLeftRadius)
            }
        }

        ShapePath {
            strokeWidth: -1
            fillGradient: RadialGradient {
                centerX: root._px; centerY: root._py
                focalX:  root._px; focalY:  root._py
                centerRadius: root._radius

                GradientStop { position: 0.0;             color: Colors.of(QsWindow.window).alpha(root.layerColor, root._alpha) }
                GradientStop { position: root._softStop;  color: Colors.of(QsWindow.window).alpha(root.layerColor, root._alpha) }
                GradientStop { position: 1.0;             color: Colors.of(QsWindow.window).alpha(root.layerColor, 0) }
            }

            // A rounded rect traced corner by corner. Radii are clamped to half the
            // shorter side — a pill asking for radiusFull (999) would otherwise
            // produce arcs larger than the shape and the path would fold on itself.
            startX: root._c(root.topLeftRadius); startY: 0

            PathLine { x: root.width - root._c(root.topRightRadius); y: 0 }
            PathArc {
                x: root.width; y: root._c(root.topRightRadius)
                radiusX: root._c(root.topRightRadius); radiusY: root._c(root.topRightRadius)
            }
            PathLine { x: root.width; y: root.height - root._c(root.bottomRightRadius) }
            PathArc {
                x: root.width - root._c(root.bottomRightRadius); y: root.height
                radiusX: root._c(root.bottomRightRadius); radiusY: root._c(root.bottomRightRadius)
            }
            PathLine { x: root._c(root.bottomLeftRadius); y: root.height }
            PathArc {
                x: 0; y: root.height - root._c(root.bottomLeftRadius)
                radiusX: root._c(root.bottomLeftRadius); radiusY: root._c(root.bottomLeftRadius)
            }
            PathLine { x: 0; y: root._c(root.topLeftRadius) }
            PathArc {
                x: root._c(root.topLeftRadius); y: 0
                radiusX: root._c(root.topLeftRadius); radiusY: root._c(root.topLeftRadius)
            }
        }
    }

    function _c(r) {
        return Math.max(0, Math.min(r, root.width / 2, root.height / 2))
    }
}
