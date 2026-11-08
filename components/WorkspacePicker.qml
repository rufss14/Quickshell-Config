pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Widgets
import "../config"
import "../services"
import "../services/palette.js" as Palette

// ── WorkspacePicker ───────────────────────────────────────────────────────────
// Which workspaces get a wallpaper — what the wallpaper gallery FOLDS INTO when
// Choose workspaces is on and a picture is clicked (WallpaperPanel, WallpaperPage).
//
//      [▣ Pier]  Choose its workspaces          (a picture, or a Wallpaper Engine scene)                       All   None
//      ┌─────────┐ ┏━━━━━━━━━┓ ┌─────────┐ ┌─────────┐ ┌─────────┐
//      │░░ 1 ░░░░│ ┃   2     ┃ │░░ 3 ░░░░│ │░░ 4 ░░░░│ │░░ 5 ░░░░│
//      └─────────┘ ┗━━━━━━━━━┛ └─────────┘ └─────────┘ └─────────┘
//      … 6–10
//      1 workspace · the others keep theirs              Cancel  [Apply]
//
// Each cell is that workspace's wallpaper now, DIMMED, with its number big in the
// middle — the overview's own cell (WorkspaceGrid). Choosing a cell lifts the dim and
// reveals the NEW picture in it, so the grid shows the result before you commit. The
// workspace you're on has a bar under its number and starts chosen; one that already
// has its own wears a dot, and hovering it offers ↺ (back to the shared one).
//
// It asks the same question for a colour SCHEME (`scheme`: a saved scheme's name — the Colours panel's
// library, right-click a card). Each cell then keeps the workspace's own wallpaper, dimmed, and a chosen
// one is washed with the scheme's background and gets its ribbon of colours: the picture stays, the
// colours change. A dotted cell is one that already wears a scheme; ↺ lets it go.
//
// And for the ALBUM's workspaces (`album`: Colours panel › Album › "Chosen workspaces"): the cells wear
// the current album palette's wash, the chosen set REPLACES `Config.albumWorkspaces` (it starts with
// what is there), and ↺ takes one out.
//
// Keys: 1–9, 0 toggle · A all/none · Enter apply · Esc cancel.
// ─────────────────────────────────────────────────────────────────────────────
FocusScope {
    id: root

    // A picture's path or "scene:<id>" (services/Wallpaper's values); drawn as itself
    // or the scene's still/preview.
    property string picture: ""
    readonly property string pictureFile: Wallpaper.displayOf(root.picture)
    // …or a saved colour scheme's name instead (then `picture` is left empty).
    property string scheme: ""
    readonly property bool forScheme: root.scheme !== ""
    // …or the album's workspaces.
    property bool album: false
    // Either: a palette to show, not a picture.
    readonly property bool forPalette: root.forScheme || root.album
    readonly property var schemePal: root.forScheme ? ColorScheme.schemePalette(root.scheme)
                                   : root.album ? (AlbumScheme.scopedPalette ?? AlbumScheme.palette) : null
    // Arrives: true once it's on screen (the cells rise in turn).
    property bool shown: false

    signal applied(var workspaces)
    signal cancelled()

    readonly property int count: Wallpaper.pickable
    readonly property int columns: 5
    readonly property int gap: Tokens.spacingSm
    readonly property real cellW: Math.floor((root.width - root.gap * (root.columns - 1)) / root.columns)
    readonly property real cellH: Math.round(root.cellW * 9 / 16)

    property var selected: []
    function reset() {
        const here = Hypr.focusedWorkspaceId
        // A scheme that already has workspaces starts with those chosen (so Apply edits the set);
        // otherwise, as ever, the one you're on.
        const had = root.forScheme ? ColorScheme.workspacesOf(root.scheme).filter(n => n <= root.count)
                  : root.album ? Config.albumWorkspaces.filter(n => n <= root.count) : []
        root.selected = had.length > 0 ? had : (here > 0 && here <= root.count ? [here] : [])
    }
    onPictureChanged: if (root.picture !== "") root.reset()
    onSchemeChanged: if (root.scheme !== "") root.reset()
    onAlbumChanged: if (root.album) root.reset()
    Component.onCompleted: root.reset()

    function toggle(n) {
        const s = root.selected.slice()
        const i = s.indexOf(n)
        if (i >= 0) s.splice(i, 1)
        else s.push(n)
        root.selected = s.sort((a, b) => a - b)
    }
    function apply() { if (root.selected.length > 0) root.applied(root.selected) }

    implicitHeight: col.implicitHeight

    Keys.onPressed: function (ev) {
        if (ev.key === Qt.Key_Escape) root.cancelled()
        else if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) root.apply()
        else if (ev.key === Qt.Key_A)
            root.selected = root.selected.length === root.count ? []
                          : Array.from({ length: root.count }, (_, i) => i + 1)
        else if (ev.key >= Qt.Key_1 && ev.key <= Qt.Key_9) root.toggle(ev.key - Qt.Key_0)
        else if (ev.key === Qt.Key_0) root.toggle(10)
        else return
        ev.accepted = true
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.spacingMd

        // ── The picture (or scheme), and the question ─────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            ClippingRectangle {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 27
                radius: Tokens.radiusXs
                color: root.forPalette && root.schemePal ? Palette.slotValue(root.schemePal, "background")
                                                        : Colors.of(QsWindow.window).surfaceContainer
                Image {
                    anchors.fill: parent
                    visible: !root.forPalette
                    source: root.pictureFile !== "" ? "file://" + root.pictureFile : ""
                    sourceSize: Qt.size(96, 54)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                }
                // A scheme: its colours as a ribbon along the bottom of the swatch.
                Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * 0.4
                    visible: root.forPalette && root.schemePal !== null
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: parent.width / 6
                            height: parent.height
                            color: Palette.slotValue(root.schemePal, "color" + (index + 1))
                        }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: root.forScheme ? root.scheme : root.album ? "Album colours" : "Choose its workspaces"
                variant: "label"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            PanelButton {
                variant: "ghost"
                label: Translation.tr("All")
                onActivated: root.selected = Array.from({ length: root.count }, (_, i) => i + 1)
            }
            PanelButton {
                variant: "ghost"
                label: Translation.tr("None")
                onActivated: root.selected = []
            }
        }

        // ── The workspaces ────────────────────────────────────────────────────
        Grid {
            Layout.fillWidth: true
            columns: root.columns
            spacing: root.gap

            Repeater {
                model: root.count

                Item {
                    id: cell
                    required property int index
                    readonly property int num: cell.index + 1
                    readonly property bool on: root.selected.indexOf(cell.num) >= 0
                    readonly property bool own: root.forScheme ? ColorScheme.schemeFor(cell.num) !== null
                                              : root.album ? Config.albumWorkspaces.indexOf(cell.num) >= 0
                                              : Wallpaper.wallFor(cell.num) !== ""
                    readonly property bool here: Hypr.focusedWorkspaceId === cell.num
                    readonly property bool hot: tap.containsMouse
                    readonly property string now: Wallpaper.shownFor(cell.num)

                    width: root.cellW
                    height: root.cellH

                    // Rises in turn as the picker arrives.
                    property real rise: root.shown ? 0 : 1
                    Behavior on rise {
                        SequentialAnimation {
                            PauseAnimation { duration: root.shown ? Math.min(cell.index * Motion.stagger, Motion.staggerCap) : 0 }
                            NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline
                                              easing.bezierCurve: Motion.emphasizedDecel }
                        }
                    }
                    opacity: 1 - cell.rise
                    transform: Translate { y: cell.rise * Tokens.spacingLg + (cell.hot && !cell.on ? -1 : 0) }

                    // The chosen: a soft halo outside the ring.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -Tokens.spacingXs
                        radius: Tokens.radiusCard + Tokens.spacingXs
                        color: "transparent"
                        border.width: Tokens.spacingXs
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.28)
                        opacity: cell.on ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    }

                    ClippingRectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusCard
                        color: Colors.of(QsWindow.window).surfaceContainer

                        // What it has now…
                        Image {
                            anchors.fill: parent
                            source: cell.now !== "" && !Config.wallMaterial ? "file://" + cell.now : ""
                            sourceSize: Qt.size(Math.round(root.cellW * 2), Math.round(root.cellH * 2))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                        // Material is on every workspace: drawn, not a file.
                        Loader {
                            anchors.fill: parent
                            active: Config.wallMaterial
                            sourceComponent: MaterialWallpaper { running: false }
                        }
                        // …and what it would get, revealed from the middle.
                        Image {
                            anchors.fill: parent
                            source: root.pictureFile !== "" ? "file://" + root.pictureFile : ""
                            sourceSize: Qt.size(Math.round(root.cellW * 2), Math.round(root.cellH * 2))
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            opacity: cell.on ? 1 : 0
                            scale: cell.on ? 1 : 1.12
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline
                                                                  easing.bezierCurve: Motion.emphasizedDecel } }
                        }
                        // …or, for a scheme, the colours it would wear: its background over the picture and
                        // its ribbon along the foot — the picture stays.
                        Item {
                            anchors.fill: parent
                            visible: root.forPalette && root.schemePal !== null
                            opacity: cell.on ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            Rectangle {
                                anchors.fill: parent
                                color: root.schemePal ? Qt.alpha(Palette.slotValue(root.schemePal, "background"), 0.55) : "transparent"
                            }
                            Row {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: Tokens.spacingSm
                                Repeater {
                                    model: 6
                                    Rectangle {
                                        required property int index
                                        width: parent.width / 6
                                        height: parent.height
                                        color: Palette.slotValue(root.schemePal, "color" + (index + 1))
                                    }
                                }
                            }
                        }
                        // The dim: deep at rest, lifted when chosen or pointed at.
                        Rectangle {
                            anchors.fill: parent
                            color: Colors.of(QsWindow.window).base
                            opacity: cell.on ? 0.22 : cell.hot ? 0.45 : 0.6
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        }
                    }

                    // The ring.
                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusCard
                        color: "transparent"
                        border.width: cell.on ? Tokens.borderChrome + 1 : Tokens.borderWidth
                        border.color: cell.on ? Colors.of(QsWindow.window).primary : cell.hot ? Colors.of(QsWindow.window).outlineFocus : Colors.of(QsWindow.window).outline
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }
                    }

                    // The number, big in the middle — the overview's own.
                    StyledText {
                        id: number
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: cell.here ? -Tokens.spacingXs : 0
                        text: "" + cell.num
                        font.pixelSize: Math.round(root.cellH * 0.48)
                        font.bold: true
                        color: Colors.of(QsWindow.window).fg
                        opacity: cell.on ? 0.95 : cell.hot ? 0.7 : 0.5
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        property real pop: 1
                        scale: number.pop
                        Connections {
                            target: cell
                            function onOnChanged() { popAnim.restart() }
                        }
                        SequentialAnimation {
                            id: popAnim
                            NumberAnimation { target: number; property: "pop"; to: 1.16; duration: Motion.respond; easing.type: Motion.respondCurve }
                            NumberAnimation { target: number; property: "pop"; to: 1; duration: Motion.standard
                                              easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                        }
                    }
                    // You are here.
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.top: number.bottom
                        anchors.topMargin: -Tokens.spacingXs
                        visible: cell.here
                        width: Tokens.spacingXl
                        height: Tokens.spacingXs + 1
                        radius: height / 2
                        color: cell.on ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).focus
                    }
                    // Has its own picture (or scheme) already.
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.spacingSm
                        visible: cell.own
                        width: Tokens.spacingSm
                        height: width
                        radius: width / 2
                        color: Colors.of(QsWindow.window).primary
                    }

                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.toggle(cell.num)
                    }
                    // Its own picture back to the shared one (over the tap).
                    PanelButton {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.margins: Tokens.spacingXs
                        visible: cell.own && !cell.on && cell.hot
                        variant: "ghost"
                        symbol: "undo"
                        onActivated: {
                            if (root.forScheme) ColorScheme.forgetWorkspace(cell.num)
                            else if (root.album) Config.albumWorkspaces = Config.albumWorkspaces.filter(n => n !== cell.num)
                            else Wallpaper.forgetWorkspace(cell.num)
                        }
                    }
                }
            }
        }

        // ── What will happen, and the two answers ─────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: root.selected.length === 0 ? "Choose at least one"
                    : root.selected.length === root.count ? "Every workspace — the same as applying it normally"
                    : (root.selected.length === 1 ? "1 workspace" : root.selected.length + " workspaces")
                      + (root.album ? " follow the album" : " · the others keep theirs")
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            PanelButton {
                variant: "ghost"
                label: Translation.tr("Cancel")
                onActivated: root.cancelled()
            }
            PanelButton {
                variant: "primary"
                accent: Colors.of(QsWindow.window).primary
                enabled: root.selected.length > 0
                label: Translation.tr("Apply")
                onActivated: root.apply()
            }
        }
    }
}
