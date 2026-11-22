import QtQuick
import "../services/calmspot.js" as Calm

// ── WallEnergy ────────────────────────────────────────────────────────────────
// Reads a wallpaper into a grid of "energy" (how much detail each cell holds: services/calmspot.js)
// so something can be put where the picture is quiet, or busy. The picture is cropped to the
// screen's shape first, the way the wallpaper is drawn to cover the screen, so the cells follow
// what is SEEN.
//
// It works only while `active` (the reader — an image and a small canvas — is a Loader's content,
// freed when it is off); the last grid stays after that. `grid` is empty until a read has finished
// and for a source that isn't a still picture (a scene, a video): `ready` says which.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // A file path.
    property string source: ""
    // The screen's width over its height.
    property real aspect: 16 / 9
    property int cols: 32
    property int rows: 18
    property bool active: false

    property var grid: []
    readonly property bool ready: root.grid.length === root.cols * root.rows

    onSourceChanged: root.grid = []

    Loader {
        active: root.active && root.source !== ""

        sourceComponent: Item {
            // Small: a wallpaper's detail at 128 px across is all the layout needs, and it's cheap.
            readonly property int cw: 128
            readonly property int ch: Math.max(1, Math.round(cw / Math.max(0.1, root.aspect)))

            Image {
                id: probe
                source: "file://" + root.source
                sourceSize.width: 256
                asynchronous: true
                cache: false
                opacity: 0.01
                onStatusChanged: if (status === Image.Ready) cv.requestPaint()
            }

            Canvas {
                id: cv
                width: parent.cw
                height: parent.ch
                opacity: 0.01
                renderTarget: Canvas.Image
                onPaint: {
                    if (probe.status !== Image.Ready || probe.implicitWidth <= 0) return
                    const ctx = getContext("2d")
                    const iw = probe.implicitWidth, ih = probe.implicitHeight
                    const a = width / height
                    let sw = iw, sh = ih, sx = 0, sy = 0
                    if (iw / ih > a) { sw = ih * a; sx = (iw - sw) / 2 } else { sh = iw / a; sy = (ih - sh) / 2 }
                    ctx.drawImage(probe, sx, sy, sw, sh, 0, 0, width, height)
                    root.grid = Calm.energy(ctx.getImageData(0, 0, width, height).data, width, height, root.cols, root.rows)
                }
            }
        }
    }
}
