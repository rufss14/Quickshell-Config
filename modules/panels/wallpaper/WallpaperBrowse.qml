import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

Rectangle {
    required property var panel

    // The toolbar lives outside this Loader but drives it, so the two
    // facts it needs about the folder are published here rather than the
    // toolbar reaching into a model that may not exist yet.
    readonly property url  upFolder: fsModel.parentFolder
    readonly property bool canGoUp: String(fsModel.parentFolder) !== ""
        && String(fsModel.parentFolder) !== String(panel.browseFolder)

    radius: Tokens.radiusSm
    color: Colors.of(QsWindow.window).surfaceContainer
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outline

    FolderListModel {
        id: fsModel
        folder: panel.browseFolder
        showDirs: true
        showDirsFirst: true
        showFiles: true
        showDotAndDotDot: false
        showHidden: false
        // So *.jpg matches .JPG too — filters are the only place this
        // browser cares about case.
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

        property int cols: Math.max(3, Math.floor(width / 130))
        cellWidth:  Math.floor(width / fileGrid.cols)
        cellHeight: 92

        delegate: Item {
            id: cell
            required property string fileName
            required property string filePath
            required property bool   fileIsDir

            width:  fileGrid.cellWidth
            height: fileGrid.cellHeight

            readonly property bool picked:
                !cell.fileIsDir && panel.isPicked(cell.filePath)

            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXs
                radius: Tokens.radiusXs
                color: Colors.of(QsWindow.window).surface
                clip: true
                border.width: cell.picked ? 2
                    : (cellHover.containsMouse ? 1 : Tokens.borderWidth)
                border.color: cell.picked ? panel.accent
                    : (cellHover.containsMouse ? Colors.of(QsWindow.window).outlineFocus
                                               : Colors.of(QsWindow.window).outline)

                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                // Folders get an icon — there is no thumbnail to show.
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
                    color: panel.accent

                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "check"
                        fill: 1
                        variant: "caption"
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                }
            }

            MouseArea {
                id: cellHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (cell.fileIsDir) panel.browseFolder = "file://" + cell.filePath
                    else                panel.togglePick(cell.filePath)
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
