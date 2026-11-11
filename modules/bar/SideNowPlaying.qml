import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Mpris
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../components/shapes.js" as Shapes

// ── SideNowPlaying ────────────────────────────────────────────────────────────
// What's playing, as one sidebar cell (2026-10-31, the user's pick for a sidebar less
// "boring compared to the top"): the album cover inside a cookie, in a wavy progress ring —
// the media pill's cover ring (VisualizerPill), on the edge. The most colourful thing on it.
//
//   click    the media panel (the top bar's)
//   middle   play / pause
//   scroll   next / previous
//   right    Settings › Sidebar
//
// The cookie turns one petal per BEAT while the bars' music rims listen (MusicPulse), or
// every `Motion.pulse * 4` otherwise — a tick on a spring, then still, never a constant
// redraw for the length of a song. The ring lies flat while paused (RadialGauge.flat). The
// position is read once a second while playing and on screen. With no player the cell steps
// aside (SideRail.cellsFor gives it no cells).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null
    // "nowplaying", or "visualizer" when SideVisualizer draws this as its cover: the
    // hero and accent are that module's, and right-click is the bar visualizer's
    // (the desktop spectrum on or off) — same face, same buttons (2026-11-08).
    property string moduleId: "nowplaying"

    readonly property var player: MusicPulse.player
    readonly property bool playing: MusicPulse.playing
    readonly property string art: root.player ? AlbumArt.hiRes(root.player.trackArtUrl ?? "") : ""

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // ── Where in the song ─────────────────────────────────────────────────────
    property real pos: 0
    readonly property real len: root.player && root.player.lengthSupported ? root.player.length : 0
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: root.playing && root.visible
        onTriggered: root.pos = root.player ? root.player.position : 0
    }
    onPlayerChanged: root.pos = root.player ? root.player.position : 0

    // ── The cookie's turn ─────────────────────────────────────────────────────
    readonly property string shape: "cookie9"
    SpringValue { id: spin; spec: Motion.springSpatial; epsilon: 0.05 }
    function _turn() { spin.target += Shapes.turnFor(root.shape) }
    Connections {
        target: MusicPulse
        enabled: root.playing && Config.sideMusicReact
        function onBeatsChanged() { root._turn() }
    }
    Timer {
        interval: Motion.pulse * 4
        repeat: true
        running: root.playing && !Config.sideMusicReact && Motion.ambientOn && root.visible
        onTriggered: root._turn()
    }

    CellFeedback {
        id: feedback
        anchors.fill: parent
        hovered: mouse.containsMouse
    }

    readonly property real ringSize: Config.sidebarCell - Tokens.spacingXs * 2

    RadialGauge {
        id: ring
        anchors.centerIn: parent
        width:  root.ringSize
        height: width
        thickness: Math.max(Tokens.spacingXs, Math.round(width / 11))
        wavy: true
        flat: !root.playing
        glide: true
        accent: AlbumArt.accent
        value: root.len > 0 ? Math.min(1, root.pos / root.len) : 0
    }

    // The cover, through a cookie that turns inside the mask (CookieCover's way: the picture
    // stays upright, the petals sweep across it).
    Item {
        id: cover
        anchors.centerIn: parent
        width:  root.ringSize - ring.thickness * 2 - Tokens.spacingXs * 2
        height: width
        scale: feedback.lift
        visible: root.art !== ""

        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: coverMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image {
                anchors.fill: parent
                source: root.art
                sourceSize: Qt.size(cover.width * 2, cover.height * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
        Item {
            id: coverMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            // A stencil: only its alpha counts. Turned as a CHILD — a layer renders its item
            // without its own transform.
            MorphShape {
                anchors.fill: parent
                shape: root.shape
                turns: false
                fillColor: Colors.of(QsWindow.window).fg
                rotation: spin.value
            }
        }
    }

    // No cover: a note, in the cell's ink.
    MaterialIcon {
        anchors.centerIn: parent
        visible: root.art === ""
        name: "music_note"
        fill: root.playing ? 1 : 0
        weight: Config.sidebarGlyphWeight
        font.pixelSize: Math.round(root.ringSize / 2)
        color: Config.moduleHero(root.moduleId) ? Colors.of(QsWindow.window).fgOnPrimaryContainer
             : mouse.containsMouse ? Config.moduleAccent(root.moduleId, Colors.of(QsWindow.window).primary)
             : Colors.of(QsWindow.window).stateIdleFg
        scale: feedback.lift
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    SideHover {
        hovered: mouse.containsMouse
        from:    root.moduleId
        arg:     "nowplaying"
        screen:  root.screen
        enabled: !UiState.isOpen("media")
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feedback.press(m.x, m.y) }
        onReleased: feedback.release()
        onCanceled: feedback.release()
        onClicked: function (m) {
            if (m.button === Qt.RightButton) {
                if (root.moduleId === "visualizer") Config.cavaBg = !Config.cavaBg
                else                                UiState.openSettingsTo("SidebarPage.qml")
            }
            else if (m.button === Qt.MiddleButton) { if (root.player) root.player.togglePlaying() }
            else UiState.togglePanel("media")
        }
        onWheel: function (w) {
            if (!root.player || w.angleDelta.y === 0) return
            if (w.angleDelta.y < 0) { if (root.player.canGoNext) root.player.next() }
            else if (root.player.canGoPrevious) root.player.previous()
        }
    }
}
