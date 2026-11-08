import QtQuick
import Quickshell
import "../config"
import "../services"

// ── Infection ─────────────────────────────────────────────────────────────────
// One shell window's share of a wallpaper/colour change (services/WallWave.qml).
// The new colours don't simply appear: they spread from the bottom middle of the
// screen on the SAME front as the new wallpaper, glowing in the new accent as they
// go. Put one of these as the LAST child of a window:
//
//     Infection { host: root.contentItem; screen: root.screen; hostVisible: root.visible }
//
// freeze: the window's current look is captured and stands in front of it, exactly
// (infect.frag replaces the pixels, so a translucent surface doesn't leak the new
// colour through). The palette then changes underneath, unseen.
// go: that snapshot is eaten away along the front (infect.frag), and the front glows
// in the new accent wherever there is shell to glow on (infectglow.frag). Draws
// only; takes no input.
//
// ── Taking the snapshot ───────────────────────────────────────────────────────
// A ShaderEffectSource only captures while it is part of the drawn scene, and it
// captures the window INCLUDING this item — so on freeze it enters the scene drawing
// NOTHING (cover 0), the capture happens in the next frame, and only once frames have
// actually been drawn does it cover. Counted in frames (FrameAnimation), not
// milliseconds: covering before the capture would record the cover itself — a
// window captured as blank, standing in for the real one until the front passed.
// (grabToImage can't be used: a window's content item has no QML engine.)
//
// ── windowX / windowY ─────────────────────────────────────────────────────────
// Where the window's top-left sits on its screen, so a window that doesn't fill it
// turns when the front reaches IT (a toast in a corner turns last). Read at the
// freeze, with the size — a window that resizes mid-wave keeps the picture it had,
// rather than having it stretched onto its new shape. Full-screen windows at the
// origin leave both 0.
//
// ── Only during a wave ────────────────────────────────────────────────────────
// The snapshot and both shaders exist only while a change runs and the window is
// up. The original crashed Quickshell (QQuickItem::update) when a shader item bound
// to window geometry outlived its window; with nothing built between waves there is
// nothing left to write into.
Item {
    id: inf

    required property Item host
    property var screen: null
    property bool hostVisible: true
    property real windowX: 0
    property real windowY: 0

    anchors.fill: parent
    z: 100000
    visible: inf.shown

    readonly property real screenW: inf.screen ? inf.screen.width  : Math.max(1, inf.width)
    readonly property real screenH: inf.screen ? inf.screen.height : Math.max(1, inf.height)

    property bool shown: false
    property bool cover: false
    // While a new snapshot is taken mid-spread, keep drawing the previous spread
    // where it got to — the capture then takes exactly that picture.
    property real heldProgress: -1
    // Frozen with the picture: its size, and where it sat on the screen.
    property size shot: Qt.size(0, 0)
    property vector4d place: Qt.vector4d(0, 0, 1, 1)
    property int _frames: 0

    readonly property real _progress: inf.heldProgress >= 0 ? inf.heldProgress : WallWave.infectProgress
    readonly property real _cover: (inf.cover || inf.heldProgress >= 0) ? 1 : 0

    Loader {
        id: fx
        // Sized explicitly on purpose: a Loader resizes its item to match, which is
        // exactly the "keep the captured shape" rule above.
        width: inf.shot.width
        height: inf.shot.height
        active: inf.shown && inf.hostVisible
        sourceComponent: Item {
            function capture() { oldLook.scheduleUpdate() }

            ShaderEffectSource {
                id: oldLook
                sourceItem: inf.host
                live: false
                // It captures the window it sits in, this item included — a quick
                // second change snapshots the first one mid-spread.
                recursive: true
                hideSource: false
                visible: false
            }
            // The old look, exactly, wherever the front hasn't reached.
            ShaderEffect {
                anchors.fill: parent
                blending: false
                property var src: oldLook
                property real progress: inf._progress
                property real aspect: inf.screenW / Math.max(1, inf.screenH)
                property real time: WallWave.t
                property real cover: inf._cover
                property vector4d rect: inf.place
                fragmentShader: Qt.resolvedUrl("../shaders/infect.frag.qsb")
            }
            // The front: the old look's soft edge, the rim, the burn behind it.
            ShaderEffect {
                anchors.fill: parent
                property var src: oldLook
                property real progress: inf._progress
                property real aspect: inf.screenW / Math.max(1, inf.screenH)
                property real time: WallWave.t
                property real cover: inf._cover
                property vector4d rect: inf.place
                property color glow: Colors.of(QsWindow.window).primary
                property color lift: Colors.of(QsWindow.window).fg
                property vector2d texel: Qt.vector2d(1 / Math.max(1, width), 1 / Math.max(1, height))
                property real burn: 1
                fragmentShader: Qt.resolvedUrl("../shaders/infectglow.frag.qsb")
            }
        }
    }

    Connections {
        target: WallWave
        function onFroze(token) {
            if (!inf.hostVisible || inf.width < 1 || inf.height < 1) return
            // Held until this window's snapshot is drawn and covering (cover, below):
            // the script waits for every window's.
            inf._snapDone()
            inf._snapTok = token
            WallWave.snapHold(token)
            if (inf.shown) inf.heldProgress = WallWave.lastProgress
            inf.shot = Qt.size(inf.width, inf.height)
            inf.place = Qt.vector4d(inf.windowX / inf.screenW, inf.windowY / inf.screenH,
                                    inf.width / inf.screenW, inf.height / inf.screenH)
            inf.shown = true                     // builds the snapshot + shaders, synchronously
            if (fx.item) fx.item.capture()
            inf._frames = 0
            coverWhenDrawn.restart()
        }
    }

    // Cover once the capture has certainly been drawn: the frame after next.
    FrameAnimation {
        id: coverWhenDrawn
        running: false
        onTriggered: {
            inf._frames++
            if (inf._frames < 3) return
            coverWhenDrawn.stop()
            inf.heldProgress = -1
            inf.cover = true
            inf._snapDone()
        }
    }

    // The hold taken on WallWave's `froze` (see WallWave.snapHold), given back once.
    property int _snapTok: -1
    function _snapDone() {
        if (inf._snapTok < 0) return
        const t = inf._snapTok
        inf._snapTok = -1
        WallWave.snapRelease(t)
    }
    Component.onDestruction: inf._snapDone()

    // A window that hides mid-wave drops out of it for good: coming back, it would
    // rebuild its snapshot while already covering — capturing the cover, a blank
    // window. Back, it simply shows its new colours.
    onHostVisibleChanged: {
        if (inf.hostVisible) return
        coverWhenDrawn.stop()
        inf._snapDone()
        inf.shown = false
        inf.cover = false
        inf.heldProgress = -1
    }

    // The newest change has swept past: nothing left to cover. `settled` too, as a
    // net — with nothing frozen, spreading or held, nothing may stay covered.
    readonly property bool _swept: (WallWave.infectProgress >= 1 && !WallWave.frozen) || WallWave.settled
    on_SweptChanged: {
        if (!inf._swept || inf.heldProgress >= 0) return
        inf._snapDone()
        inf.shown = false
        inf.cover = false
    }
}
