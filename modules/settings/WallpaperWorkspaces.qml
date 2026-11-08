pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── WallpaperWorkspaces — a wallpaper per workspace ───────────────────────────
// The card at the end of the Wallpaper page's Appearance view: every workspace as a cell showing
// what it shows now, the controls for giving one its own, and the way back.
//
//   [ 1 ][ 2 ][ 3 ][ 4 ][ 5 ][ 6 ][ 7 ][ 8 ][ 9 ][ 10 ]        Keep scenes running · Reset all
//
// ── How you use it ────────────────────────────────────────────────────────────
// Click a workspace (it lights up: "picking" — the page jumps to the Gallery), then click
// a wallpaper there — that workspace gets it as ITS OWN. The gallery's right-click, which asks for
// several workspaces at once (components/WorkspacePicker), still works; this is the
// slower, more visible way for one. A cell that has its own wallpaper wears a dot, and
// hovering it offers ↺ (back to the shared one). The workspace you are on has an outline.
//
// The cell shows `Wallpaper.shownFor(n)`: the workspace's own picture, else the shared
// one, so with no overrides every cell is the same picture and the strip says so.
//
// All the work is the Wallpaper service's (assign, forgetWorkspace, forgetAllWorkspaces);
// this only shows it and calls it. `picking` is the page's, passed in, so the gallery's
// tiles know to assign instead of apply.
// ─────────────────────────────────────────────────────────────────────────────
Section {
    id: root

    // The workspace waiting for a wallpaper, or 0.
    property int picking: 0
    signal pick(int n)

    glyph:   "󰕮"
    title:   Translation.tr("Per workspace")
    accent:  Colors.of(QsWindow.window).info
    padding: Tokens.spacingMd
    subtitle: root.picking > 0
        ? "Pick a wallpaper in the Gallery for workspace " + root.picking + "."
        : Wallpaper.perWorkspace
        ? Wallpaper.marked.length + " of " + Wallpaper.pickable + " workspaces have their own wallpaper. Click one to choose its wallpaper in the Gallery."
        : "Every workspace shows the same wallpaper. Click one to choose its own in the Gallery — or right-click a wallpaper there to choose several."

    actions: [
        PanelButton {
            capsule: true
            visible: Wallpaper.perWorkspace
            variant: "ghost"
            symbol:  "restart_alt"
            label:   Translation.tr("Reset all")
            onActivated: Wallpaper.forgetAllWorkspaces()
        }
    ]

    // One cell is a tenth of the row, 16:9 — the overview's own proportion.
    readonly property int gap: Tokens.spacingSm
    readonly property real cellW: (root.width - root.padding * 2 - root.gap * (Wallpaper.pickable - 1)) / Wallpaper.pickable
    readonly property real cellH: Math.max(36, Math.round(root.cellW * 9 / 16))

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: root.gap

        Repeater {
            model: Wallpaper.pickable

            delegate: Item {
                id: cell
                required property int index

                readonly property int num: cell.index + 1
                readonly property string now: Wallpaper.shownFor(cell.num)
                readonly property bool own: Wallpaper.wallFor(cell.num) !== ""
                readonly property bool here: Hypr.focusedWorkspaceId === cell.num
                readonly property bool chosen: root.picking === cell.num

                Layout.fillWidth: true
                Layout.preferredWidth: 0
                Layout.preferredHeight: root.cellH

                ClippingRectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusSm
                    color: Colors.of(QsWindow.window).surfaceContainer
                    border.width: cell.chosen || cell.here ? 2 : Tokens.borderWidth
                    border.color: cell.chosen ? Colors.of(QsWindow.window).info
                                : cell.here   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).info, 0.55)
                                :               Colors.of(QsWindow.window).outline
                    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                    Image {
                        anchors.fill: parent
                        source: cell.now !== "" && !Config.wallMaterial ? "file://" + cell.now : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 200
                        smooth: true
                    }
                    // Material is on every workspace: drawn, not a file.
                    Loader {
                        anchors.fill: parent
                        active: Config.wallMaterial
                        sourceComponent: MaterialWallpaper { running: false }
                    }

                    // Dimmed so the number reads; lifted when it is the chosen one, the
                    // way the picker's cells are.
                    Rectangle {
                        anchors.fill: parent
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, cell.chosen ? 0.10 : 0.38)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: String(cell.num)
                        variant: "title"
                        font.weight: Font.DemiBold
                        // On a dimmed picture, in the palette's own light colour.
                        color: Colors.of(QsWindow.window).fg
                    }

                    // Has its own wallpaper.
                    Rectangle {
                        visible: cell.own
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: Tokens.spacingXs
                        width:  Tokens.spacingMd
                        height: Tokens.spacingMd
                        radius: width / 2
                        color:  Colors.of(QsWindow.window).info
                    }
                }

                // Back to the shared wallpaper — only a workspace that has its own.
                Rectangle {
                    visible: cell.own && cellHover.hovered
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Tokens.spacingXs
                    width:  Tokens.iconMd + 4
                    height: Tokens.iconMd + 4
                    radius: width / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outline

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "restart_alt"
                        variant: "caption"
                        color: Colors.of(QsWindow.window).fg
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.forgetWorkspace(cell.num)
                    }
                }

                HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.pick(cell.num) }
            }
        }
    }
}
