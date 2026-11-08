import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"

// ── LauncherEmoji ─────────────────────────────────────────────────────────────
// The `:` picker's body: a grid, not a list — you scan emoji by sight and move in two
// dimensions, and a column of one-per-row names would show five at a time. The selection is
// a cookie-shaped plate that glides from cell to cell on a spring (x and y each), the cell
// under it swells, and the line under the grid says what it is called.
//
// The panel owns the keys (arrows move through `step`, Enter picks) and the data; this file
// shows `rows` ([{ char, name, generic }]) and reports a click.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var rows: []
    property int currentIndex: 0
    // Shown when there is nothing to pick (no font, no match, no recents yet).
    property string emptyText: ""

    signal picked(int index)

    readonly property var c: Colors.of(QsWindow.window)

    readonly property int pad:        Tokens.spacingSm
    readonly property int cellMin:    Tokens.iconXl + Tokens.spacingXl
    readonly property int cellH:      Tokens.iconXl + Tokens.spacingXl
    readonly property int visibleRows: 4
    readonly property int captionH:   Tokens.iconLg + Tokens.spacingMd * 2
    readonly property int columns:    Math.max(5, Math.floor((root.width - root.pad * 2) / root.cellMin))
    readonly property real cellW:     (root.width - root.pad * 2) / root.columns

    implicitHeight: root.pad * 2 + root.visibleRows * root.cellH + root.captionH
    readonly property var current: root.rows[Math.max(0, Math.min(root.currentIndex, root.rows.length - 1))] ?? null

    onCurrentIndexChanged: if (root.currentIndex >= 0) grid.positionViewAtIndex(root.currentIndex, GridView.Contain)

    // ── The plate ─────────────────────────────────────────────────────────────
    SpringValue { id: plateX; spec: Motion.springSpatial
                  target: (root.currentIndex % root.columns) * root.cellW }
    SpringValue { id: plateY; spec: Motion.springSpatial
                  target: Math.floor(root.currentIndex / root.columns) * root.cellH - grid.contentY }

    Item {
        id: field
        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        height: root.visibleRows * root.cellH
        clip: true

        MorphShape {
            x: plateX.value + Tokens.spacingXs
            y: plateY.value + Tokens.spacingXs
            width:  root.cellW - Tokens.spacingXs * 2
            height: root.cellH - Tokens.spacingXs * 2
            shape: "cookie9"
            fillColor: root.c.primaryContainer
            visible: root.rows.length > 0
        }

        GridView {
            id: grid
            anchors.fill: parent
            cellWidth: root.cellW
            cellHeight: root.cellH
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            model: root.rows
            currentIndex: root.currentIndex
            // Moves are the panel's (arrow keys); the grid only follows and scrolls.
            keyNavigationEnabled: false

            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool current: root.currentIndex === cell.index
                width: grid.cellWidth
                height: grid.cellHeight

                SpringValue {
                    id: swell
                    spec: Motion.springSpatialFast
                    target: cell.current ? 1.18 : 1
                    epsilon: 0.001
                }
                Text {
                    anchors.centerIn: parent
                    text: cell.modelData.char
                    font.pixelSize: Tokens.iconXl - Tokens.spacingXs
                    scale: swell.value
                }
                HoverHandler {
                    id: hover
                    property real lastX: -1
                    property real lastY: -1
                    // Selection follows a pointer that MOVED, not one that merely rests while
                    // the grid re-flows under it (as in the result list).
                    onPointChanged: {
                        const p = hover.point.scenePosition
                        if (p.x === hover.lastX && p.y === hover.lastY) return
                        hover.lastX = p.x
                        hover.lastY = p.y
                        root.currentIndex = cell.index
                    }
                }
                TapHandler {
                    acceptedButtons: Qt.LeftButton
                    onTapped: { root.currentIndex = cell.index; root.picked(cell.index) }
                }
            }
        }
    }

    // ── What it is ────────────────────────────────────────────────────────────
    RowLayout {
        x: root.pad + Tokens.spacingMd
        y: root.pad * 2 + root.visibleRows * root.cellH
        width: root.width - (root.pad + Tokens.spacingMd) * 2
        height: root.captionH
        spacing: Tokens.spacingMd
        visible: root.current !== null

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: root.current ? root.current.name : ""
            variant: "body"
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.current ? root.current.generic : ""
            variant: "caption"
            emphasis: "dim"
        }
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.rows.length === 0
        width: parent.width - Tokens.spacingXl * 2
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: root.emptyText
        variant: "body"
        emphasis: "dim"
    }
}
