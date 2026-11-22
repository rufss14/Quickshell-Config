import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../hud"

// ── OverviewIsland ────────────────────────────────────────────────────────────
// The overview's bottom island, and the one thing in it that changes shape: what's playing
// over volume and brightness (OverviewControls) while nothing is picked, the picked window's inspector (WindowInspector) while
// something is, a selection's bulk face (BulkInspector — the windows Ctrl+clicked, Switcher.marks)
// while there are marked windows, and a HUD widget's inspector (modules/hud/HudInspector — where it goes over
// a game) while one of the HUD cards is being tuned (Hud.inspecting). A window pick and
// a HUD pick clear each other (services/Hud). It does not swap two cards — it is ONE surface that springs to the size of
// what it holds (Motion.spring: it passes its size and settles, like a panel's box), while the
// old content sinks out and the new rises in a beat behind (ViewEnter's rhythm).
//
// The material is the island pages': a flat tonal ground (GroundCard), no outline, no shadow, no field.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The Switcher record of the picked window, or null.
    property var picked: null
    property int firstWorkspace: 1
    property bool shown: false

    readonly property bool inspecting: root.picked !== null
    // The Switcher records of the marked windows (a pick and a selection clear each other).
    property var marks: []
    readonly property bool bulking: root.marks.length > 0 && !root.inspecting
    readonly property alias bulk: bulkLoader.item
    readonly property alias inspector: inspectorLoader.item
    // The HUD widget being placed ("" = none), and the screen it's placed on.
    property string hudId: ""
    property real screenW: 1920
    property real screenH: 1080
    property string screenName: ""
    readonly property bool tuning: root.hudId !== "" && !root.inspecting && !root.bulking
    // None of them: the controls.
    readonly property bool idle: !root.inspecting && !root.bulking && !root.tuning
    signal moved(int ws)

    readonly property int pad: Tokens.spacingMd

    // The inspector stays loaded for its fade out, then goes (its live capture with it).
    property bool _hold: false
    onInspectingChanged: {
        if (root.inspecting) { unhold.stop(); root._hold = true }
        else unhold.restart()
    }
    Component.onCompleted: { root._hold = root.inspecting; root._holdBulk = root.bulking }
    Timer { id: unhold; interval: Motion.fast + 80; onTriggered: root._hold = false }
    // Likewise the bulk face.
    property bool _holdBulk: false
    onBulkingChanged: {
        if (root.bulking) { unholdBulk.stop(); root._holdBulk = true }
        else unholdBulk.restart()
    }
    Timer { id: unholdBulk; interval: Motion.fast + 80; onTriggered: root._holdBulk = false }

    // The size of what it is showing, springing there.
    readonly property real wantW: (root.inspecting ? (inspectorLoader.item?.implicitWidth ?? 0)
                                 : root.bulking ? (bulkLoader.item?.implicitWidth ?? 0)
                                 : root.tuning ? (hudLoader.item?.implicitWidth ?? 0)
                                 : controls.implicitWidth) + root.pad * 2
    readonly property real wantH: (root.inspecting ? (inspectorLoader.item?.implicitHeight ?? 0)
                                 : root.bulking ? (bulkLoader.item?.implicitHeight ?? 0)
                                 : root.tuning ? (hudLoader.item?.implicitHeight ?? 0)
                                 : controls.implicitHeight) + root.pad * 2
    implicitWidth: root.wantW
    implicitHeight: root.wantH

    GroundCard {
        id: shell
        anchors.centerIn: parent
        // The box springs to the size of its face on M3E springs (SpringValue): a little past, then settled.
        SpringValue { id: sw; target: root.wantW; spec: Motion.springSpatial }
        SpringValue { id: sh; target: root.wantH; spec: Motion.springSpatial }
        width: sw.value
        height: sh.value
        // The playing cover's colour, lightly, while it shows the controls (OverviewControls).
        readonly property color ground: palette.surfaceFor(Tokens.elevationCard)
        tone: root.idle && controls.dressed ? palette.mix(shell.ground, controls.tone, 0.14) : shell.ground

        Item {
            anchors.fill: parent
            clip: true

            // ── Volume and brightness ─────────────────────────────────────────
            // Its own surface turned off: the island is the surface.
            OverviewControls {
                id: controls
                anchors.centerIn: parent
                live: root.shown && root.idle
                opacity: root.idle ? 1 : 0
                scale: root.idle ? 1 : 0.94
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: root.idle ? Motion.standard : Motion.fast } }
                Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            }

            // ── A HUD widget, being placed ────────────────────────────────────
            // Built only while one is (its map draws live widgets); in a beat behind the box.
            Loader {
                id: hudLoader
                anchors.centerIn: parent
                active: root.tuning
                sourceComponent: HudInspector {
                    wid: root.hudId
                    screenW: root.screenW
                    screenH: root.screenH
                    screenName: root.screenName
                    opacity: 0
                    Component.onCompleted: opacity = 1
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: Motion.fast }
                            NumberAnimation { duration: Motion.standard }
                        }
                    }
                }
            }

            // ── The selection ─────────────────────────────────────────────────
            // Loaded while there are marked windows and for its fade out (it keeps its own copy).
            Loader {
                id: bulkLoader
                anchors.centerIn: parent
                active: root._holdBulk
                property real fadeTo: root.bulking ? 1 : 0
                sourceComponent: BulkInspector {
                    wins: root.marks
                    firstWorkspace: root.firstWorkspace
                    opacity: bulkLoader.fadeTo
                    SpringValue {
                        id: rise
                        target: (1 - bulkLoader.fadeTo) * Tokens.spacingMd
                        spec: Motion.springSpatial
                    }
                    transform: Translate { y: rise.value }
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: bulkLoader.fadeTo > 0 ? Motion.fast : 0 }
                            NumberAnimation { duration: bulkLoader.fadeTo > 0 ? Motion.standard : Motion.fast }
                        }
                    }
                    onMoved: ws => root.moved(ws)
                }
            }

            // ── The picked window ─────────────────────────────────────────────
            // Loaded while there is a pick and for its fade out (the inspector keeps its own copy
            // of the window, so the fade shows the one that was picked).
            Loader {
                id: inspectorLoader
                anchors.centerIn: parent
                active: root._hold
                property real fadeTo: root.inspecting ? 1 : 0
                sourceComponent: WindowInspector {
                    win: root.picked
                    firstWorkspace: root.firstWorkspace
                    opacity: inspectorLoader.fadeTo
                    SpringValue {
                        id: rise
                        target: (1 - inspectorLoader.fadeTo) * Tokens.spacingMd
                        spec: Motion.springSpatial
                    }
                    transform: Translate { y: rise.value }
                    Behavior on opacity {
                        SequentialAnimation {
                            // in a beat behind the box, out at once
                            PauseAnimation { duration: inspectorLoader.fadeTo > 0 ? Motion.fast : 0 }
                            NumberAnimation { duration: inspectorLoader.fadeTo > 0 ? Motion.standard : Motion.fast }
                        }
                    }
                    onMoved: ws => root.moved(ws)
                }
            }
        }
    }
}
