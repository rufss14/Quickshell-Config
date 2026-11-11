pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideVisualizer ────────────────────────────────────────────────────────────
// The bar's visualizer (widgets/VisualizerPill — the cover in its ring, then the spectrum),
// turned onto the sidebar: two cells, the cover (SideNowPlaying's, as this module) and the
// spectrum, its bars lying across the edge and growing from the middle both ways, as the
// pill's grow up and down. The track's title has no room across a cell; the hover card and
// the media panel say it. Along a bottom edge it reads as the bar's, bars upright.
//
//   click    the media panel           right    the desktop spectrum on or off
//   middle   play / pause (the cover)  scroll   next / previous (the cover)
//
// Cava as the pill holds it: refcounted, only while on screen and pointed at the player's
// own PipeWire node (a Discord call or a chime never moves the bars), resting on the idle
// wave with nothing to analyse or while Game mode hides visualisers.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool vertical: true
    property var screen: null
    property bool shown: true
    property string moduleId: "visualizer"

    readonly property var player: MusicPulse.player
    readonly property bool hero: Config.moduleHero("visualizer")
    readonly property color accent: root.hero ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                              : Config.moduleAccent("visualizer", Colors.of(QsWindow.window).primary)

    implicitWidth:  root.vertical ? Config.sidebarCell : Config.sidebarRun(2)
    implicitHeight: root.vertical ? Config.sidebarRun(2) : Config.sidebarCell

    // ── Cava (VisualizerPill's lifecycle) ─────────────────────────────────────
    readonly property string playerNodeName: {
        const appId = root.player ? (root.player.desktopEntry ?? "") : ""
        if (!appId) return ""
        const nodes = Audio.streamsFor(appId)
        return nodes.length > 0 ? nodes[0].name : ""
    }
    readonly property bool frozen: Gamemode.hidesVisualizer
    readonly property bool wantsCava: root.visible && root.shown && root.playerNodeName !== "" && !root.frozen
    property bool _cavaHeld: false
    function _syncCava() {
        if (root.wantsCava) {
            if (!root._cavaHeld) { Cava.acquireSource(root.playerNodeName); root._cavaHeld = true }
            else                 Cava.sourceName = root.playerNodeName
        } else if (root._cavaHeld) {
            Cava.releaseSource()
            root._cavaHeld = false
        }
    }
    onWantsCavaChanged:      root._syncCava()
    onPlayerNodeNameChanged: root._syncCava()
    Component.onCompleted:   root._syncCava()
    Component.onDestruction: if (root._cavaHeld) Cava.releaseSource()

    readonly property int barCount: 6
    readonly property var levels: root._cavaHeld ? Cava.resample(Cava.sourceBars, root.barCount)
                                                 : Cava.idleWave(root.barCount)

    Grid {
        columns: root.vertical ? 1 : 2
        spacing: Config.sidebarCellGap

        SideNowPlaying {
            vertical: root.vertical
            screen: root.screen
            moduleId: "visualizer"
        }

        Item {
            width: Config.sidebarCell
            height: Config.sidebarCell

            CellFeedback {
                id: feedback
                anchors.fill: parent
                hovered: mouse.containsMouse
                active: UiState.isOpen("media")
            }

            // Upright along a bottom edge; turned a quarter across a side, so the bars lie
            // across the edge and grow sideways from its middle.
            Spectrum {
                anchors.centerIn: parent
                width:  Config.sidebarGlyphPx
                height: Config.sidebarGlyphPx
                rotation: root.vertical ? 90 : 0
                centered: true
                levels:   root.levels
                barCount: root.barCount
                barGap:   Math.max(Tokens.borderWidth, Math.round(Config.sidebarGlyphPx / 10))
                accent:   root.accent
            }

            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onPressed: function (m) { feedback.press(m.x, m.y) }
                onReleased: feedback.release()
                onCanceled: feedback.release()
                onClicked: function (m) {
                    if (m.button === Qt.RightButton) Config.cavaBg = !Config.cavaBg
                    else                             UiState.togglePanel("media")
                }
            }
        }
    }
}
