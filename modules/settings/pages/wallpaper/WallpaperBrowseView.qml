pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperBrowseView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
// ── BROWSE (gallery sub-mode) ────────────────────────────────────
ColumnLayout {
    id: browserView
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    anchors.fill: parent
    visible: page.view === "gallery" && page.browsing
    spacing: Tokens.spacingSm

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        PanelButton {
            capsule: true
            variant: "ghost"
            symbol: "arrow_left"
            label: Translation.tr("Back")
            onActivated: page.browsing = false
        }
        PanelButton {
            capsule: true
            variant: "ghost"
            symbol: "arrow_upward"
            enabled: String(fsModel.parentFolder) !== ""
                     && String(fsModel.parentFolder) !== String(page.browseFolder)
            onActivated: page.browseFolder = fsModel.parentFolder
        }
        PanelButton {
            capsule: true
            variant: "ghost"
            symbol: "home"
            onActivated: page.browseFolder = "file://" + (Quickshell.env("HOME") || "")
        }

        StyledText {
            Layout.fillWidth: true
            text: {
                const home = Quickshell.env("HOME") || ""
                const p = String(page.browseFolder).replace("file://", "")
                return home ? p.replace(home, "~") : p
            }
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideMiddle
        }

        PanelButton {
            capsule: true
            variant: "primary"
            accent: Colors.of(QsWindow.window).primary
            symbol: "add"
            label: "Add " + page.picked.length
            visible: page.picked.length > 0
            enabled: !Wallpaper.importing
            onActivated: { Wallpaper.addPaths(page.picked); page.picked = [] }
        }
    }

    Rectangle {
        Layout.fillWidth:  true
        Layout.fillHeight: true
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceContainer
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outline

        FolderListModel {
            id: fsModel
            folder: page.browseFolder
            showDirs: true
            showDirsFirst: true
            showFiles: true
            showDotAndDotDot: false
            showHidden: false
            caseSensitive: false
            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.webp"]
        }

        GridView {
            id: fileGrid
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            clip: true
            model: fsModel
            boundsBehavior: Flickable.StopAtBounds
            cacheBuffer: fileGrid.cellHeight * 2

            property int cols: Math.max(3, Math.floor(width / 150))
            cellWidth:  Math.floor(width / fileGrid.cols)
            cellHeight: 108

            delegate: Item {
                id: cell
                required property string fileName
                required property string filePath
                required property bool   fileIsDir

                width:  fileGrid.cellWidth
                height: fileGrid.cellHeight

                readonly property bool picked:
                    !cell.fileIsDir && page.isPicked(cell.filePath)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingXs
                    radius: Tokens.radiusXs
                    color: Colors.of(QsWindow.window).surface
                    clip: true
                    border.width: cell.picked ? 2
                        : (cellHover.hovered ? 1 : Tokens.borderWidth)
                    border.color: cell.picked ? Colors.of(QsWindow.window).primary
                        : (cellHover.hovered ? Colors.of(QsWindow.window).outlineFocus : Colors.of(QsWindow.window).outline)
                    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                    MaterialIcon {
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: -6
                        name: "folder"
                        fill: 1
                        variant: "headline"
                        color: Colors.of(QsWindow.window).focus
                        visible: cell.fileIsDir
                    }
                    Image {
                        anchors.fill: parent
                        visible: !cell.fileIsDir
                        source: cell.fileIsDir ? "" : ("file://" + cell.filePath)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        sourceSize.width: 240
                        smooth: true
                    }
                    Rectangle {
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.bottom: parent.bottom
                        height: 18
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.85)
                        StyledText {
                            anchors.fill: parent
                            anchors.leftMargin:  Tokens.spacingXs
                            anchors.rightMargin: Tokens.spacingXs
                            verticalAlignment: Text.AlignVCenter
                            text: cell.fileName
                            variant: "caption"
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        visible: cell.picked
                        anchors.top:   parent.top
                        anchors.right: parent.right
                        anchors.margins: Tokens.spacingXs
                        width:  Tokens.iconMd
                        height: Tokens.iconMd
                        radius: width / 2
                        color: Colors.of(QsWindow.window).primary
                        MaterialIcon {
                            anchors.centerIn: parent
                            name: "check"
                            fill: 1
                            variant: "caption"
                            color: Colors.of(QsWindow.window).fgOnPrimary
                        }
                    }
                }

                HoverHandler { id: cellHover }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (cell.fileIsDir)
                            page.browseFolder = "file://" + cell.filePath
                        else
                            page.togglePick(cell.filePath)
                    }
                }
            }
        }
        Scrollbar { flickable: fileGrid }

        StyledText {
            anchors.centerIn: parent
            visible: fsModel.status === FolderListModel.Ready && fsModel.count === 0
            text: Translation.tr("No images or folders here.")
            variant: "caption"
            emphasis: "dim"
        }
    }
}
