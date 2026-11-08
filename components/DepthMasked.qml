import QtQuick
import "../config"

// ── DepthMasked ───────────────────────────────────────────────────────────────
// Whatever is put inside, hidden wherever a mask says something stands in front of it: the depth
// clock behind its subject. `mask` is a picture whose ALPHA is the foreground (WallpaperDepth's
// grey+alpha PNG, already cut to the screen's shape, so it maps onto this item edge to edge); the
// content is multiplied by (1 − alpha) in shaders/depthmask.frag.qsb, soft edges and all.
//
// ── Why a mask, and not the picture drawn over the clock ──────────────────────
// The first version drew the wallpaper's own pixels, clear except where the foreground is, over the
// clock. It never lined up: Qt scales an image with alpha premultiplied, so the copy differed from the
// picture under it by up to ~47 levels along the whole subject (a thin outline, measured by rendering
// both headless and diffing) and by faint noise in every soft zone. A mask puts no picture pixel on
// screen, so there is nothing to mismatch: the only thing that can show is the clock, cut.
//
// ── Why our own shader, and a bare Image for the mask (round 4) ───────────────
// The second version used MultiEffect's mask with the mask wrapped in an invisible layer — and the
// clock drew NOTHING: the repo's own shader notes (liquidglass.frag) record that an invisible
// layered source yields a 0x0 texture and the effect then draws nothing. The mask is a plain hidden
// `Image` now (the ordinary idiom for a ShaderEffect source: its texture exists while it is
// invisible), and the product is one line of GLSL instead of MultiEffect's thresholds and spread.
//
// ── Holding the mask ──────────────────────────────────────────────────────────
// `retainWhileLoading`: a new mask keeps the old one until it has decoded, so a change never shows the
// clock whole for a beat. `maskReady` is true when there is no mask, or the mask is up (or failed: a
// clock shown uncut beats one that never appears) — what a caller waits on before bringing it in.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // A file:// url, or "" for none (the content is drawn plainly, and no layer exists).
    property string mask: ""
    // Decoded to this many physical pixels, like the picture it lies over.
    property size maskSize: Qt.size(0, 0)
    // The occlusion's edge, softened by this many pixels (see shaders/depthmask.src.frag).
    property real soft: Config.wallDepthSoft

    readonly property bool maskReady:
        root.mask === "" || maskImg.status === Image.Ready || maskImg.status === Image.Error

    // The mask file could not be read: the caller may ask for it again (WallpaperDepth.stale).
    signal failed()

    default property alias content: stage.data

    Item {
        id: stage
        anchors.fill: parent
        // No mask, no layer: the content is drawn straight.
        layer.enabled: root.mask !== ""
        layer.samplerName: "src"
        layer.effect: ShaderEffect {
            // Named for the sampler in the shader.
            property variant mask: maskImg
            // One mask texel in texture coordinates, and the kernel's spacing in texels. The mask is
            // decoded at maskSize, so a texel is a physical screen pixel.
            property vector2d texel: Qt.vector2d(1 / Math.max(1, root.maskSize.width),
                                                 1 / Math.max(1, root.maskSize.height))
            property real soft: root.soft
            fragmentShader: Qt.resolvedUrl("../shaders/depthmask.frag.qsb")
        }
    }

    // Never painted: it is only a texture for the shader above.
    Image {
        id: maskImg
        visible: false
        source: root.mask
        sourceSize: root.maskSize
        fillMode: Image.Stretch
        smooth: true
        cache: true
        asynchronous: true
        retainWhileLoading: true
        onStatusChanged: if (status === Image.Error) {
            console.warn("DepthMasked: the mask could not load", source)
            root.failed()
        }
    }
}
