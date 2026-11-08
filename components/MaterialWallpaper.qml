import QtQuick
import QtQuick.Shapes
import Quickshell
import "../config"
import "../services/materialwall.js" as MW

// ── MaterialWallpaper ─────────────────────────────────────────────────────────
// A wallpaper drawn from the palette instead of from a picture: big flat Material shapes in
// tonal steps of the screen's own colours, after End-4's default wallpaper. The composition is
// data in services/materialwall.js; this only draws it. Shown by modules/desktop/WallpaperView
// while Config.wallMaterial is on, and by the Wallpaper panel's Material tab as its preview.
//
// ── Colour ────────────────────────────────────────────────────────────────────
// Every fill is the palette's base mixed toward a ROLE by the shape's `tone` (the first role for most
// of it, the second for the shapes marked `alt` when one is chosen), so the picture is never a colour
// of its own: it re-tints with the wallpaper, the album scheme and a workspace's own palette, and a
// light scheme gives a light picture.
//
// ── Framing ───────────────────────────────────────────────────────────────────
// `zoom` / `tx` / `ty` are WallpaperView's parallax, so this pans exactly as a picture would: the
// field is scaled about its centre by `zoom` (the surplus the pan moves within), and shifted by
// (tx, ty) on the OUTSIDE of that scale — a shift on the scaled item would itself be multiplied by
// the zoom, overshooting the surplus and baring the edge. The shift eases as a picture's does.
// The zoom is a SCALE of the finished field, not a bigger layout: the model below depends only on
// the size, and a Repeater rebuilds every delegate when its model changes, which a glide would do
// every frame. (Shapes are scene-graph geometry; they scale without going soft.)
//
// ── Motion ────────────────────────────────────────────────────────────────────
// Drift and spin are one clock (`t`, seconds × speed) advanced by a FrameAnimation, and every shape
// reads its own place and turn off it (services/materialwall.js wander/spin). It is a frame loop on
// a full-screen surface, so it runs only while it is asked for AND `running` — WallpaperView drops
// that while a fullscreen window covers the screen or Game Mode holds the wallpaper.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real zoom: 1
    property real tx: 0
    property real ty: 0
    // False stops the clock whatever the style says.
    property bool running: true

    // The style (Config.wallMaterial*). A panel previewing another style can assign these.
    property string role:      Config.wallMaterialRole
    property string role2:     Config.wallMaterialRole2
    property real   contrast:  Config.wallMaterialContrast
    property real   softness:  Config.wallMaterialSoftness
    property real   sizeScale: Config.wallMaterialSize
    property int    seed:      Config.wallMaterialSeed
    property bool   drift:     Config.wallMaterialDrift
    property real   driftSpeed: Config.wallMaterialDriftSpeed
    property real   spin:      Config.wallMaterialSpin
    property real   backdrop:  Config.wallMaterialBackdrop
    property bool   mirror:    Config.wallMaterialMirror
    readonly property var forms: ({
        stack:  Config.wallMaterialStack,
        centre: Config.wallMaterialCentre,
        side:   Config.wallMaterialSide,
        corner: Config.wallMaterialCorner
    })

    readonly property var _c: Colors.of(QsWindow.window)
    readonly property color _tint:  root._c.role(root.role, root._c.primary)
    // The ground behind the shapes: the palette's base, with a faint wash of the first colour.
    readonly property color _ground: root._c.mix(root._c.base, root._tint, root.backdrop)
    readonly property color _tint2: root.role2 !== "" ? root._c.role(root.role2, root._tint) : root._tint
    // What a still of this is made of: told to the fallback so it re-renders when any of it changes.
    readonly property string signature: [root.role, root.role2, root._tint, root._tint2, root._c.base,
        root.backdrop, root.mirror, root.contrast, root.softness, root.sizeScale, root.seed, JSON.stringify(root.forms),
        root.width, root.height].join("|")

    // ── The composition ───────────────────────────────────────────────────────
    // Laid out again once per turn of the event loop, however many of its inputs changed in it: a look
    // (services/MaterialPresets) sets a dozen options one after another, and each would otherwise lay
    // out and rebuild every shape on its own.
    property var _boxes: []
    readonly property string _layoutKey: [root.width, root.height, root.contrast, root.softness,
        root.sizeScale, root.seed, JSON.stringify(root.forms)].join("|")
    function _relayout() {
        root._boxes = root.width > 0 && root.height > 0
            ? MW.layout(root.width, root.height, { contrast: root.contrast, softness: root.softness,
                                                   size: root.sizeScale, seed: root.seed, forms: root.forms })
            : []
    }
    on_LayoutKeyChanged: Qt.callLater(root._relayout)
    Component.onCompleted: root._relayout()

    // ── The clock ─────────────────────────────────────────────────────────────
    property real t: 0
    readonly property bool animated: root.running && (root.drift || root.spin > 0)
    FrameAnimation {
        running: root.animated
        onTriggered: root.t += frameTime * root.driftSpeed
    }

    // The finished picture as an image, at `size` (device pixels), for a still of it. The shapes
    // only, unzoomed and unshifted — what the surface shows with parallax at rest.
    function snapshot(callback, size) {
        content.grabToImage(callback, size)
    }

    Item {
        id: pan
        anchors.fill: parent
        transform: Translate {
            x: root.tx
            y: root.ty
            Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }

        Item {
            id: field
            anchors.fill: parent
            scale: root.zoom

            Item {
                id: content
                anchors.fill: parent

                // Everything the picture is made of, flipped as one when asked. Inside `content`, so
                // the snapshot (which grabs `content`) is flipped too.
                Item {
                    id: flip
                    anchors.fill: parent
                    transform: Scale { origin.x: flip.width / 2; xScale: root.mirror ? -1 : 1 }

                    // Inside the scale, so the surplus the pan moves within is the ground colour too.
                    Rectangle {
                        anchors.fill: parent
                        color: root._ground
                    }

                    Repeater {
                        model: root._boxes

                        delegate: Item {
                            id: shape
                            required property int index
                            required property var modelData

                            readonly property var sway: root.drift ? MW.wander(shape.index, root.t) : null

                            x: shape.modelData.x + (shape.sway ? shape.sway.x * root.height : 0)
                            y: shape.modelData.y + (shape.sway ? shape.sway.y * root.height : 0)
                            width: shape.modelData.w
                            height: shape.modelData.h
                            rotation: shape.modelData.rot + (shape.sway ? shape.sway.r : 0)
                                      + (root.spin > 0 ? MW.spin(shape.index, root.t, root.spin * 4) : 0)

                            readonly property color fill: root._c.mix(root._ground,
                                shape.modelData.alt ? root._tint2 : root._tint, shape.modelData.tone)

                            Rectangle {
                                anchors.fill: parent
                                visible: shape.modelData.kind === "circle" || shape.modelData.kind === "rect"
                                antialiasing: true
                                color: shape.fill
                                radius: shape.modelData.kind === "circle" ? width / 2
                                      : Math.min(width, height) * shape.modelData.round
                            }

                            Loader {
                                anchors.fill: parent
                                active: shape.modelData.kind === "poly"
                                sourceComponent: Shape {
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        fillColor: shape.fill
                                        strokeWidth: -1
                                        PathPolyline {
                                            path: shape.modelData.outline.map(function (p) { return Qt.point(p.x, p.y) })
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
