import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../config"
import "../services"

// ── ImagePicker ───────────────────────────────────────────────────────────────
// An in-shell picture (or folder) browser over the whole page, for a setting that names a
// picture: anchor it to fill the page and call `show(path)`. In the shell rather than a
// zenity/portal window for LockPage's reasons — a GTK dialog in someone else's theme on top
// of a shell whose point is looking like itself, and a setting depending on an optional
// package. LockPage's avatar picker is the same idiom, written before this existed.
//
// `picked(path)` for a picture, `pickedFolder(path)` when `folders` is on and "Use this
// folder" is pressed. Paths are absolute; the caller decides how to store them (the photo
// frame stores them `~`-relative — see DesktopWidgets.contractPath).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool open: false
    property bool folders: false
    property string current: ""
    property string title: "Choose a picture"
    signal picked(string path)
    signal pickedFolder(string path)

    readonly property string home: Quickshell.env("HOME") || ""
    property url folder: "file://" + root.home

    // Opens in the folder of `startPath` (a picture or a folder), or at home.
    function show(startPath) {
        const p = startPath || ""
        if (p !== "") {
            // A folder picker is handed the folder itself; a picture picker, the picture.
            const dir = root.folders ? p : p.substring(0, p.lastIndexOf("/"))
            if (dir !== "") root.folder = "file://" + dir
        }
        root.open = true
    }

    function _parent(f) {
        const s = String(f)
        const cut = s.lastIndexOf("/")
        return (cut > 7) ? s.substring(0, cut) : "file:///"   // keep "file://" intact
    }

    visible: root.open
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.72)
    z: 100

    // Swallows clicks aimed at the page underneath; clicking outside closes.
    MouseArea {
        anchors.fill: parent
        onClicked: root.open = false
    }

    Surface {
        anchors.centerIn: parent
        width:  Math.min(parent.width  - Tokens.spacingXxl * 2, 720)
        height: Math.min(parent.height - Tokens.spacingXxl * 2, 520)
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusCard

        // The card itself must not close the browser.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                PanelButton {
                    capsule: true
                    variant: "ghost"
                    symbol: "arrow_upward"
                    // "file:///" is the root; there is nowhere above it.
                    enabled: String(root.folder) !== "file:///"
                    onActivated: root.folder = root._parent(root.folder)
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText { text: root.title; variant: "label"; font.weight: Font.DemiBold }
                    StyledText {
                        Layout.fillWidth: true
                        // The leading "file://" is machinery, not a path.
                        text: String(root.folder).replace("file://", "")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideMiddle
                    }
                }
                PanelButton {
                    capsule: true
                    variant: "ghost"
                    label: Translation.tr("Home")
                    enabled: root.home !== ""
                    onActivated: root.folder = "file://" + root.home
                }
                PanelButton {
                    visible: root.folders
                    capsule: true
                    variant: "primary"
                    label: Translation.tr("Use this folder")
                    onActivated: {
                        root.pickedFolder(String(root.folder).replace("file://", ""))
                        root.open = false
                    }
                }
                PanelButton {
                    capsule: true
                    variant: "ghost"
                    symbol: "close"
                    onActivated: root.open = false
                }
            }

            Divider { Layout.fillWidth: true }

            Item {
                Layout.fillWidth:  true
                Layout.fillHeight: true

                FolderListModel {
                    id: fsModel
                    folder: root.folder
                    showDirs: true
                    showDirsFirst: true
                    showFiles: true
                    showDotAndDotDot: false
                    caseSensitive: false      // so *.jpg matches .JPG
                    nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.gif"]
                }

                GridView {
                    id: fileGrid
                    anchors.fill: parent
                    clip: true
                    model: root.open ? fsModel : null
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: fileGrid.cellHeight * 2
                    readonly property int minCell: 150
                    property int cols: Math.max(2, Math.floor(width / fileGrid.minCell))
                    cellWidth:  Math.floor(width / fileGrid.cols)
                    cellHeight: 116

                    delegate: Item {
                        id: cell
                        required property string fileName
                        required property string filePath
                        required property bool   fileIsDir
                        width:  fileGrid.cellWidth
                        height: fileGrid.cellHeight
                        readonly property bool chosen: !cell.fileIsDir && root.current === cell.filePath

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingXs
                            radius: Tokens.radiusSm
                            color: Colors.of(QsWindow.window).surface
                            border.width: cell.chosen ? 2 : Tokens.borderWidth
                            border.color: cell.chosen       ? Colors.of(QsWindow.window).primary
                                        : cellHover.hovered ? Colors.of(QsWindow.window).outlineFocus
                                        :                     Colors.of(QsWindow.window).outline
                            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                            ClippingRectangle {
                                anchors.fill: parent
                                anchors.margins: Tokens.borderWidth
                                anchors.bottomMargin: nameText.implicitHeight + Tokens.spacingXs * 2
                                radius: Tokens.radiusSm - Tokens.borderWidth
                                color: "transparent"

                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "folder"
                                    variant: "title"
                                    color: Colors.of(QsWindow.window).focus
                                    visible: cell.fileIsDir
                                }
                                Image {
                                    anchors.fill: parent
                                    visible: !cell.fileIsDir
                                    source: cell.fileIsDir ? "" : ("file://" + cell.filePath)
                                    fillMode: Image.PreserveAspectCrop
                                    // Decoded at the drawn size — a folder of 4K photos would
                                    // otherwise decode each at full resolution.
                                    sourceSize: Qt.size(fileGrid.cellWidth * 2, fileGrid.cellHeight * 2)
                                    asynchronous: true
                                    mipmap: true
                                    smooth: true
                                }
                            }
                            StyledText {
                                id: nameText
                                anchors.left:   parent.left
                                anchors.right:  parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: Tokens.spacingXs
                                horizontalAlignment: Text.AlignHCenter
                                text: cell.fileName
                                variant: "micro"
                                emphasis: "dim"
                                elide: Text.ElideMiddle
                            }
                        }

                        HoverHandler { id: cellHover }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (cell.fileIsDir) {
                                    root.folder = "file://" + cell.filePath
                                } else if (!root.folders) {
                                    root.picked(cell.filePath)
                                    root.open = false
                                }
                            }
                        }
                    }
                }
                Scrollbar { flickable: fileGrid }

                StyledText {
                    anchors.centerIn: parent
                    visible: fsModel.status === FolderListModel.Ready && fsModel.count === 0
                    text: Translation.tr("No pictures or folders here.")
                    variant: "body"
                    emphasis: "dim"
                }
            }
        }
    }
}
