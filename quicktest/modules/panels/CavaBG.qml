import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../services"

// ── CavaBG ────────────────────────────────────────────────────────────────────
// A full-width audio spectrum pinned to the bottom of the desktop, *behind* every
// application window. Transparent, click-through, on the wlr "background" layer.
// Toggled by left-clicking the visualizer pill (Config.cavaBg).
//
// It used to run its own `cava` process — a third one, on top of the two the
// status bar was running. All three analyzed the same audio to draw the same
// spectrum. It now shares the one Cava service, holding a reference only while
// it's actually visible.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // ── Bottom, not Background — so a wallpaper renderer can't bury it ────────
    // linux-wallpaperengine anchors to the `bottom` layer by DEFAULT (its own
    // --layer flag says so), and a full-screen surface one layer up hid this
    // completely. Background→Bottom puts the spectrum above anything drawn on the
    // background layer, and `bottom` is still beneath every normal application
    // window, so this stays what it has always been: desktop decoration, behind
    // your apps.
    //
    // NOTE this only wins deterministically if the wallpaper renderer is on
    // `background`. Left on its default `bottom` it shares this layer and the two
    // stack by MAP ORDER — whoever started last covers the other. Run it with
    // `--layer background` to make the ordering a fact rather than a race.
    WlrLayershell.layer:         WlrLayer.Bottom
    WlrLayershell.namespace:     "quickshell-cava-bg"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true

    implicitHeight: root.maxBarH
    color: "transparent"

    // ── Hide behind a fullscreen window ───────────────────────────────────────
    // This lives on the `bottom` layer, under every window. A fullscreen window is
    // opaque over the whole output, so the spectrum can't be seen — and animating 64
    // bars at 60fps behind it is pure GPU waste. When one covers this monitor, fade
    // out and release the cava reference (the bar's own visualizer keeps the process
    // alive if it's running; this just stops the full-screen animation).
    readonly property bool suppressed: Fullscreen.activeOn(root.screen?.name ?? "")

    // Stay mapped a little past cavaBg/suppressed changing so the fade-out can
    // finish — same pattern the overlay panels use.
    readonly property bool wanted: Config.cavaBg && !root.suppressed
    visible: wanted || viz.opacity > 0.005

    // Never intercept input: clicks fall through to the desktop or the windows
    // below.
    mask: Region {}

    // ── Geometry ──────────────────────────────────────────────────────────────
    readonly property int maxBarH: 180
    // The service publishes 32 bars; mirroring them gives 64, with bass meeting
    // in the middle and treble at both edges — the way cava itself presents a
    // stereo field.
    readonly property int barCount: Cava.barCount * 2

    readonly property real slotW: root.width / root.barCount
    readonly property real barW:  Math.max(2, root.slotW * 0.6)

    // ── Cava lifecycle ────────────────────────────────────────────────────────
    property bool _held: false
    function _sync() {
        if (root.visible === _held) return
        if (root.visible) Cava.acquire()
        else              Cava.release()
        _held = root.visible
    }
    onVisibleChanged: _sync()
    Component.onCompleted: _sync()
    Component.onDestruction: if (_held) Cava.release()

    // Shaped, then mirrored. The expansive curve (exponent > 1) keeps quiet
    // passages low and lets transients — bass hits especially — shoot up, rather
    // than the whole spectrum reading as one flat uniform block.
    readonly property var bars: Cava.mirrored(Cava.shape(Cava.bars, 1.25))

    Item {
        id: viz
        anchors.fill: parent
        opacity: root.wanted ? 1.0 : 0.0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }

        Repeater {
            model: root.barCount

            Rectangle {
                id: bar
                required property int index

                x: bar.index * root.slotW + (root.slotW - root.barW) / 2
                anchors.bottom: parent.bottom
                width: root.barW
                color: Colors.focus

                readonly property real target: Math.max(2, Math.round(
                    (bar.index < root.bars.length ? root.bars[bar.index] : 0) * root.maxBarH))
                height: target

                // Fast attack, slow decay: a boom snaps the bar up almost
                // instantly and then eases back down, instead of both directions
                // moving at the same steady speed — which is what makes a
                // spectrum read as responding to music rather than sloshing.
                Behavior on height {
                    NumberAnimation {
                        duration: bar.target > bar.height ? 35 : 220
                        easing.type: Easing.OutQuad
                    }
                }
            }
        }
    }
}
