import QtQuick
import QtQuick.Shapes
import "../config"

// ── Scallop ───────────────────────────────────────────────────────────────────
// The shell's signature shape: a rounded N-petalled star — a circle whose radius
// breathes in and out N times around the turn. Material-3-Expressive calls this a
// "cookie"; it is the one non-rectangular form in the settings surface, and it is
// what keeps a page of soft rectangles from reading as a spreadsheet.
//
// ── Passive on purpose ────────────────────────────────────────────────────────
// This draws and nothing else: no hover, no press, no cursor. CookieButton is this
// plus a TapHandler and the wind gesture; a card's icon holder (ScallopChip) is this
// plus a glyph. Both used to carry their own copy of the petal maths — one shape, one
// definition, so a change to the silhouette cannot land on the button and miss the
// chip.
//
// ── Shape with the curve renderer, not Canvas ─────────────────────────────────
// This was a Canvas: 180 segments rasterised on the CPU into a texture. That was fine
// while the petals only changed with a colour scheme, but the shape now MOVES — it winds
// on hover and breathes with an audio level — and a Canvas texture that is rotated,
// scaled and repainted per frame shows it: soft, slightly stair-stepped edges, and a
// CPU raster for every frame of every animation.
//
// A Shape is scene-graph geometry. With the curve renderer it is antialiased at any
// scale or rotation and costs the GPU nothing to turn (ConcaveCorner made the same move
// for the same reason). The one price is that the outline's point list is rebuilt in JS
// whenever the petal depth or size changes — about 150 points, and only while it moves.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // How many petals. Odd numbers look hand-drawn, even ones look engineered; 8 is
    // the house default and reads as a flower without being twee.
    property int points: 8

    // How deep the petals cut, as a fraction of the radius. 0 is a circle; past ~0.3
    // it stops reading as a disc with a decorated edge and starts reading as a gear.
    property real petalDepth: 0.13

    property color fillColor:   "transparent"
    property color strokeColor: "transparent"
    property real  strokeWidth: Tokens.borderWidth

    // Animated by the CALLER (hover deepens the petals); the Behavior lives here so
    // every user gets the same easing for free.
    // `animatePetals: false` for a caller that reassigns the shape outright (DriftShapes' pool).
    property bool animatePetals: true
    Behavior on petalDepth {
        enabled: root.animatePetals
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // The outline, one point per ~2.5° (and never fewer than 24 per petal, so a deep
    // many-petalled star keeps its curve). The radius breathes between rMax - amp and
    // rMax with the cosine; the closing point repeats the first so a stroke joins up.
    readonly property var _outline: {
        const cx = root.width / 2, cy = root.height / 2
        // -1.5 so a stroke sits inside the item rather than being clipped in half.
        const rMax = Math.min(root.width, root.height) / 2 - 1.5
        const amp  = rMax * root.petalDepth
        const N    = Math.max(3, root.points)
        const steps = Math.max(144, N * 24)
        const out = []
        for (let i = 0; i <= steps; i++) {
            const a = i / steps * Math.PI * 2
            const r = (rMax - amp) + amp * (0.5 + 0.5 * Math.cos(N * a))
            out.push(Qt.point(cx + r * Math.cos(a), cy + r * Math.sin(a)))
        }
        return out
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor:   root.fillColor
            strokeColor: root.strokeColor
            // -1 turns the stroke off outright; 0 would still draw a hairline.
            strokeWidth: root.strokeColor.a > 0 ? root.strokeWidth : -1
            joinStyle:   ShapePath.RoundJoin

            PathPolyline { path: root._outline }
        }
    }
}
