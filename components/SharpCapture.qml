import QtQuick
import Quickshell.Wayland
import "../config"

// ── SharpCapture ──────────────────────────────────────────────────────────────
// A live window capture (ScreencopyView) that stays crisp drawn SMALL. ScreencopyView
// samples its buffer with plain linear filtering and no mipmaps (view.cpp:
// setFiltering(Linear)), so a 1920 px window drawn 330 px wide reads one source pixel in
// six: text turns to grit and edges crawl as the window repaints — the overview's
// workspace previews looked like that (2026-10-20). Here the capture renders into a layer
// up to `oversample`× this item's size (never past the buffer's own), WITH mipmaps, and
// that layer is drawn down to size: trilinear, so every source pixel counts.
//
// Used where a capture is drawn SMALLER than the window: the overview's grid and inspector,
// the dock's previews. (WindowPeek draws windows at their real size — nothing to gain.)
// The cost is one texture per capture at ≤2× its drawn size (plus a third for the mips),
// redrawn when the window repaints — only while the capture is live at all.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property alias captureSource: view.captureSource
    property alias live: view.live
    readonly property alias hasContent: view.hasContent
    readonly property alias sourceSize: view.sourceSize
    // 2, not 3 (2026-10-20): a third the texture per window, redrawn per repaint, for the
    // overview's opening frames; at ≤2:1 the linear draw into the layer still reads clean.
    property real oversample: 2

    // As many times this item's size as the buffer has pixels for, up to `oversample`; 1
    // until the first frame says how big the buffer is.
    readonly property real _k: Math.max(1, Math.min(root.oversample,
        view.sourceSize.width / Math.max(1, root.width),
        view.sourceSize.height / Math.max(1, root.height)))

    // Fades in once the first frame is there, rather than popping from blank.
    opacity: view.hasContent ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.mipmap: true
        layer.textureSize: Qt.size(Math.max(1, Math.round(root.width * root._k)),
                                   Math.max(1, Math.round(root.height * root._k)))

        ScreencopyView {
            id: view
            anchors.fill: parent
        }
    }
}
