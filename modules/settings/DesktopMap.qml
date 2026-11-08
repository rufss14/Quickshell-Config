pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../desktop/widgets"

// ── DesktopMap ────────────────────────────────────────────────────────────────
// One screen, small: what it shows right now (Wallpaper.shownFor its workspace) with
// every widget placed on it drawn at its real position, as the real widget
// (WidgetPreview, inert). Click one to pick it; drag one and it moves on the actual
// desktop when you let go (DesktopWidgets.move, which also nudges it off a neighbour).
//
// The page's list of names used to be the only way to pick a widget, and "where is it"
// had to be answered by looking at the desktop behind the window. The map answers both
// in the place you are already looking.
//
// Positions are screen pixels; `k` maps them onto the map. The drag writes x/y directly
// (breaking their bindings) — the move replaces DesktopWidgets.widgets, which rebuilds
// the delegates, so every one starts bound again.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string screenName: ""
    property int    selectedId: -1
    signal picked(int id)

    readonly property var scr: Quickshell.screens.find(s => s.name === root.screenName)
                               ?? (Quickshell.screens.length > 0 ? Quickshell.screens[0] : null)
    readonly property real sw: root.scr ? root.scr.width  : 1920
    readonly property real sh: root.scr ? root.scr.height : 1080
    readonly property real k:  root.width / root.sw

    // What THIS screen is showing: the wallpaper of the workspace active on its own
    // monitor (each workspace can wear its own), not the focused one elsewhere.
    readonly property int workspace: {
        const m = root.scr ? Hypr.monitorFor(root.scr) : null
        return m && m.activeWorkspace ? m.activeWorkspace.id : Hypr.focusedWorkspaceId
    }
    readonly property string picture: Wallpaper.shownFor(root.workspace)

    implicitHeight: root.width * root.sh / root.sw

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationBar)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outline
        clip: true

        // ── This screen's part of the picture ───────────────────────────────────
        // A scene spanned across monitors has ONE still covering all of them (3600×1080
        // for a 1920 + 1680 pair), so cropping it to this screen's shape from the
        // centre drew the seam between two screens' halves. When the picture is
        // clearly wider than this screen, it is a span: lay it out at the frame's
        // height and slide it so this screen's slice — by the screen's place among the
        // monitors, left to right — is the part in the frame. Otherwise, a plain crop.
        Item {
            anchors.fill: parent
            anchors.margins: Tokens.borderWidth
            clip: true

            Image {
                id: pic
                readonly property real aspect: pic.implicitHeight > 0 ? pic.implicitWidth / pic.implicitHeight : 0
                readonly property bool spanned: pic.aspect > (root.sw / root.sh) * 1.2
                // The monitors side by side, as Hyprland lays them out: where this one
                // starts within the whole row, 0..1.
                readonly property real offset: {
                    const all = Quickshell.screens
                    if (!pic.spanned || !root.scr || all.length < 2) return 0
                    const minX = Math.min(...all.map(s => s.x))
                    const maxR = Math.max(...all.map(s => s.x + s.width))
                    return (root.scr.x - minX) / Math.max(1, maxR - minX)
                }

                source: root.picture !== "" && !Config.wallMaterial ? "file://" + root.picture : ""
                // By height: a span is several screens wide, and decoding it 640 wide
                // left one screen's slice a blurry 200px.
                sourceSize.height: 720
                asynchronous: true
                smooth: true
                mipmap: true
                opacity: 0.85

                height: parent.height
                width: pic.spanned ? parent.height * pic.aspect : parent.width
                x: pic.spanned ? -pic.offset * pic.width : 0
                fillMode: pic.spanned ? Image.Stretch : Image.PreserveAspectCrop
            }

            // The Material Wallpaper is on every workspace (applying it clears the rest), drawn rather than shown.
            Loader {
                anchors.fill: parent
                active: Config.wallMaterial
                sourceComponent: MaterialWallpaper { running: false }
            }
        }
        // A touch of dark, so light wallpapers don't swallow the widgets on them.
        Rectangle {
            anchors.fill: parent
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.25)
        }
    }

    // A click on bare wallpaper picks nothing — the page puts its card away.
    TapHandler { onTapped: root.picked(-1) }

    Repeater {
        // The layout this screen is showing (live layouts per wallpaper), like the desktop.
        model: DesktopWidgets.forScreen(root.scr ? root.scr.name : "")

        delegate: Item {
            id: tile
            required property var modelData
            readonly property bool picked: root.selectedId === tile.modelData.id

            x: tile.modelData.x * root.k
            y: tile.modelData.y * root.k
            width:  DesktopWidgets.widthOf(tile.modelData.size)  * root.k
            height: DesktopWidgets.heightOf(tile.modelData.size) * root.k
            z: tile.picked || drag.drag.active ? 2 : 1

            // Lifts under the pointer, and a little more while dragged.
            scale: drag.drag.active ? 1.08 : (tileHover.hovered ? 1.04 : 1.0)
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.standard
                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                }
            }

            WidgetPreview {
                anchors.centerIn: parent
                type:   tile.modelData.type
                size:   tile.modelData.size
                opts:   tile.modelData.opts
                accent: Colors.of(QsWindow.window).role(tile.modelData.opts.accent ?? "", Colors.of(QsWindow.window).primary)
                boxWidth:  tile.width
                maxHeight: tile.height
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: -3
                radius: Tokens.radiusSm
                color: "transparent"
                border.width: 2
                border.color: Colors.of(QsWindow.window).primary
                opacity: tile.picked ? 1 : (tileHover.hovered ? 0.45 : 0)
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
            }

            HoverHandler { id: tileHover }

            MouseArea {
                id: drag
                anchors.fill: parent
                cursorShape: drag.drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: tile
                drag.minimumX: 0
                drag.minimumY: 0
                drag.maximumX: root.width  - tile.width
                drag.maximumY: root.height - tile.height
                drag.threshold: 4

                onPressed: root.picked(tile.modelData.id)
                onReleased: {
                    if (!drag.drag.active && Math.abs(tile.x - tile.modelData.x * root.k) < 1
                                          && Math.abs(tile.y - tile.modelData.y * root.k) < 1) return
                    DesktopWidgets.move(tile.modelData.id, tile.x / root.k, tile.y / root.k,
                                        root.sw, root.sh)
                }
            }
        }
    }
}
