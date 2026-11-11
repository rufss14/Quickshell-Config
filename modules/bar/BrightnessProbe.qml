import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../../services/antiflash.js" as A

// ── BrightnessProbe ───────────────────────────────────────────────────────────
// How bright this screen is, for anti-flashbang (services/AntiFlash). Lives inside
// the bar window of the FOCUSED screen only (Bar.qml's Loader), because a
// ScreencopyView binds its buffers to a window.
//
// A still capture (`live: false`, retaken by captureFrame()) of the output, without
// the pointer, kept out of the scene (WaveCurtain's hidden ShaderEffectSource) and
// shrunk on the GPU to a 64×36 mipmapped texture. Grabbing that at 32×18 and drawing
// it into a Canvas gives 576 pixels to average — measured offscreen: a half-white,
// half-black item reads 0.500. Nothing here is drawn; nothing takes input.
//
// The capture skips Hyprland's screen shader (blockScreenShader), so this always sees
// the undimmed picture: the dimming can't feed back into its own measurement.
//
// Every two seconds, and ~150ms after AntiFlash.sampleSoon (focus, workspace, a window
// opening). A fresh frame is asked for, then read a beat later — ScreencopyView
// says nothing when a requested frame lands.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: probe

    property var screen: null

    width: 1
    height: 1
    enabled: false

    ScreencopyView {
        id: shot
        width: 64
        height: 36
        captureSource: probe.screen
        live: false
        paintCursor: false
    }
    ShaderEffectSource {
        id: small
        sourceItem: shot
        hideSource: true
        live: true
        mipmap: true
        textureSize: Qt.size(64, 36)
        width: 32
        height: 18
        opacity: 0
    }

    // The beat: every two seconds, and soon after an event.
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: probe.sample()
    }
    Timer {
        id: soon
        interval: 150
        onTriggered: probe.sample()
    }
    Connections {
        target: AntiFlash
        function onSampleSoon() { soon.restart() }
    }
    Component.onCompleted: soon.restart()

    function sample() {
        if (!shot.hasContent) { shot.captureFrame(); return }
        shot.captureFrame()
        read.restart()
    }
    // A beat for the requested frame to land and the shrunk texture to follow it.
    Timer {
        id: read
        interval: 120
        onTriggered: small.grabToImage(function (r) {
            if (canvas.url !== "") canvas.unloadImage(canvas.url)
            canvas.url = r.url
            canvas.loadImage(r.url)
            canvas.requestPaint()
        }, Qt.size(32, 18))
    }

    // Drawn only to be read back: transparent, behind everything, 32×18.
    Canvas {
        id: canvas
        property string url: ""
        width: 32
        height: 18
        opacity: 0
        z: -1
        onImageLoaded: canvas.requestPaint()
        onPaint: {
            if (canvas.url === "" || !canvas.isImageLoaded(canvas.url)) return
            const ctx = canvas.getContext("2d")
            ctx.drawImage(canvas.url, 0, 0, 32, 18)
            AntiFlash.report(A.meanLuma(ctx.getImageData(0, 0, 32, 18).data))
        }
    }
}
