pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick
import "../../config"
import "../../services"

// ── WaveCurtain ───────────────────────────────────────────────────────────────
// The apps' share of the wave (services/WallWave.qml, services/Contagion.qml), on
// one screen. Other apps can't be drawn into, so at the freeze this takes ONE copy of
// the screen and stands a piece of it over every window someone is looking at —
// exactly what was there. Every app then recolours underneath, unseen, and the same
// front that eats the shell's old look (components/Infection.qml, the same two
// shaders) eats these: each app is revealed already in its new colours, pixel by
// pixel, with the front's line crossing it. Before this, a near-full-screen window
// flipped whole the instant the front touched its bottom edge, and late.
//
// ── Only during a wave ────────────────────────────────────────────────────────
// Mapped only while Contagion has windows for this screen (the freeze → settled);
// the capture, its texture and the shaders exist for exactly that long. Hyprland
// would ease a freshly mapped layer in over a second — WallWave puts in a runtime
// `no_anim` rule for this namespace, or the frozen copies would fade up over the
// live windows they are meant to hide.
//
// ── The capture ───────────────────────────────────────────────────────────────
// One ScreencopyView of the whole output, taken once (`live: false`) without the
// pointer. It is never drawn itself — the hidden ShaderEffectSource keeps it out of
// the scene, and the patches each take their window's rectangle of it. A capture
// that never arrives covers nothing; Contagion is told which screens are covered and
// times the rest.
//
// Top layer: over every ordinary window, under a fullscreen one (which Contagion
// leaves alone) and under the Overlay-layer shell surfaces, which carry their own
// Infection. Click-through, no keyboard, no zone.
PanelWindow {
    id: curtain

    required property var modelData
    screen: curtain.modelData

    readonly property string screenName: curtain.modelData ? curtain.modelData.name : ""
    readonly property var covers: Contagion.covers[curtain.screenName] || []
    visible: curtain.covers.length > 0

    WlrLayershell.layer:         WlrLayer.Top
    WlrLayershell.namespace:     "quickshell-wave"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    mask: Region {}

    Loader {
        anchors.fill: parent
        // Once the window really exists: the capture binds its buffers to it as it's
        // built, and a mapping window may not have one yet.
        active: curtain.visible && curtain.backingWindowVisible

        sourceComponent: Item {
            id: body

            ScreencopyView {
                id: shot
                anchors.fill: parent
                captureSource: curtain.screen
                live: false
                paintCursor: false
                onHasContentChanged: Contagion.setCovered(curtain.screenName, shot.hasContent)
            }

            // Keeps the capture itself out of the scene from the first frame. Never
            // sampled, so it asks for a 1px texture rather than a screenful.
            ShaderEffectSource {
                sourceItem: shot
                hideSource: true
                live: false
                visible: false
                textureSize: Qt.size(1, 1)
                width: 1
                height: 1
            }

            Repeater {
                model: shot.hasContent ? curtain.covers : []

                delegate: Item {
                    id: patch
                    required property var modelData

                    x: patch.modelData.x
                    y: patch.modelData.y
                    width: patch.modelData.w
                    height: patch.modelData.h

                    readonly property vector4d place:
                        Qt.vector4d(patch.x / Math.max(1, curtain.width), patch.y / Math.max(1, curtain.height),
                                    patch.width / Math.max(1, curtain.width), patch.height / Math.max(1, curtain.height))

                    ShaderEffectSource {
                        id: tex
                        sourceItem: shot
                        sourceRect: Qt.rect(patch.x, patch.y, patch.width, patch.height)
                        hideSource: true
                        visible: false
                    }
                    // The window as it was, wherever the front hasn't reached.
                    ShaderEffect {
                        anchors.fill: parent
                        blending: false
                        property var src: tex
                        property real progress: WallWave.infectProgress
                        property real aspect: curtain.width / Math.max(1, curtain.height)
                        property real time: WallWave.t
                        property real cover: 1
                        property vector4d rect: patch.place
                        fragmentShader: Qt.resolvedUrl("../../shaders/infect.frag.qsb")
                    }
                    // The front crossing it: the line, and a lighter burn than the
                    // chrome's — here the whole window is ground.
                    ShaderEffect {
                        anchors.fill: parent
                        property var src: tex
                        property real progress: WallWave.infectProgress
                        property real aspect: curtain.width / Math.max(1, curtain.height)
                        property real time: WallWave.t
                        property real cover: 1
                        property vector4d rect: patch.place
                        property color glow: Colors.of(QsWindow.window).primary
                        property color lift: Colors.of(QsWindow.window).fg
                        property vector2d texel: Qt.vector2d(1 / Math.max(1, width), 1 / Math.max(1, height))
                        property real burn: 0.35
                        fragmentShader: Qt.resolvedUrl("../../shaders/infectglow.frag.qsb")
                    }
                }
            }

            Component.onDestruction: Contagion.setCovered(curtain.screenName, false)
        }
    }
}
