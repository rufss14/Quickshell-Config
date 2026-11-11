pragma ComponentBehavior: Bound

import QtQuick
import "../config"
import "../services"

// ── WallBackdrop ──────────────────────────────────────────────────────────────
// The wallpaper as it looks on one screen RIGHT NOW, for the desktop tiles' glass to
// refract (`shaders/liquidglass.src.frag` samples this as a texture at the tile's screen
// position).
//
// A plain Image of the wallpaper is only right while the wallpaper holds still. The shell
// draws it zoomed past the screen edge and panned (workspace, pointer: WallpaperView's
// parallax), so a glass that sampled the raw picture looked at the wrong part of it, and
// slid against what it was meant to show. This item takes the framing from the screen's
// own WallpaperView (services/WallFrame) and draws the same planes the same way: one
// zoom, one pan, one crossfade. The glass then follows the pointer, a workspace switch and
// a new wallpaper without knowing about any of them.
//
// Layered, so the tiles sample one screen-sized texture; its size is the screen's, which
// is also what the shader's `screenSize` is. Decoded at logical size: it is blurred
// anyway, and a physical-size decode of every picture twice would be wasted memory.
//
// With nothing to follow (no view for this screen, or a scene / the game card on it) it
// shows the plain picture, unzoomed and centred, as it always did.
Item {
    id: root

    property string screenName: ""

    readonly property var view: WallFrame.of(root.screenName)
    readonly property string path: {
        const drawn = root.view ? root.view.drawn : ""
        return drawn !== "" ? drawn : (Wallpaper.currentPath === "" ? "" : "file://" + Wallpaper.currentPath)
    }
    readonly property real zoom:       root.view ? root.view.zoom : 1
    readonly property real zoomTarget: root.view ? root.view.zoomTarget : 1

    // True once there is a picture in the layer to sample, and it stays true across a new
    // decode (a parallax toggle re-decodes at another size; `retainWhileLoading` keeps the
    // old picture up), so the tiles' glass doesn't drop out and rebuild. Not `Image.Ready`
    // alone: that says the file decoded, not that it has been rendered into the layer.
    property bool ready: false

    layer.enabled: true
    layer.smooth: true

    component Plane: Image {
        anchors.centerIn: parent
        width:  parent.width  * root.zoom
        height: parent.height * root.zoom
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(Math.round(parent.width * root.zoomTarget), Math.round(parent.height * root.zoomTarget))
        smooth: true
        cache: true
        asynchronous: true
        retainWhileLoading: true
        opacity: 0
        transform: Translate {
            x: root.view ? root.view.glideTx : 0
            y: root.view ? root.view.glideTy : 0
        }
    }

    Plane { id: prev }
    Plane {
        id: cur
        onStatusChanged: if (status === Image.Ready) { root.ready = root.width > 0 && root.height > 0; fade.restart() }
    }

    // The outgoing picture goes under at full strength and the incoming one fades in over
    // it, so the two never run against each other and dip (WallpaperView's crossfade, and
    // for the same reason). With nothing under, the first picture is simply there.
    NumberAnimation {
        id: fade
        target: cur
        property: "opacity"
        to: 1
        duration: Motion.emphasized
        onFinished: prev.source = ""
    }

    function _swap() {
        fade.stop()
        if (root.path === cur.source.toString()) return
        if (root.path === "") { prev.source = ""; cur.source = ""; cur.opacity = 0; root.ready = false; return }
        const had = cur.source.toString() !== "" && cur.opacity > 0
        prev.source = had ? cur.source : ""
        prev.opacity = had ? 1 : 0
        cur.opacity = had ? 0 : 1
        cur.source = root.path
    }
    onPathChanged: root._swap()
    Component.onCompleted: root._swap()
}
