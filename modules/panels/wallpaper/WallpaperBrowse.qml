import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/wallpaperlib.js" as Lib

// ── WallpaperBrowse ───────────────────────────────────────────────────────────
// Where pictures are chosen to copy into the library. Built for finding, not for listing files:
//
//   places       Home, Pictures, Downloads and the library itself, one press away; the one you are in is lit
//   the path     each folder you are inside, as a step you can press, and one up; All ticks every picture here
//   the folder   folders as cards with a badge, pictures as large cards on a canvas, as the gallery's are; a
//                press ticks a picture (a cookie with a tick comes up on it) or opens a folder
//   Add          a capsule floats up as soon as anything is ticked: how many, Clear, and Add
//
// The panel owns what is ticked (`picked`, cleared when the browser closes) and where the browser is
// (`browseFolder`); this draws them. Behind a Loader: a GridView builds delegates for its viewport whether
// or not it is visible, so an always-mounted browser would decode a screenful of $HOME thumbnails every time
// the panel opened.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property string home: Quickshell.env("HOME") || ""

    radius: Tokens.radiusSm
    color: root.panel.island ? "transparent" : root.palette.plateLow
    border.width: root.panel.island ? 0 : Tokens.borderWidth
    border.color: root.palette.outline

    readonly property url upFolder: fsModel.parentFolder
    readonly property bool canGoUp: String(fsModel.parentFolder) !== ""
        && String(fsModel.parentFolder) !== String(root.panel.browseFolder)
    readonly property string here: String(root.panel.browseFolder).replace(/^file:\/\//, "").replace(/\/+$/, "")

    // How many pictures the folder holds, and whether every one of them is ticked.
    property int pics: 0
    readonly property bool allPicked: root.pics > 0 && root.picturePaths().every(p => root.panel.isPicked(p))
    function picturePaths() {
        const out = []
        for (let i = 0; i < fsModel.count; i++)
            if (!fsModel.get(i, "fileIsDir")) out.push(fsModel.get(i, "filePath"))
        return out
    }
    function recount() { root.pics = root.picturePaths().length }
    function pickAll() {
        const here = root.picturePaths()
        if (root.allPicked) root.panel.picked = root.panel.picked.filter(p => here.indexOf(p) === -1)
        else root.panel.picked = root.panel.picked.concat(here.filter(p => !root.panel.isPicked(p)))
    }

    // Where the browser can jump to: a place is shown whatever its folder holds.
    readonly property var places: [
        { label: Translation.tr("Home"),      icon: "home",      path: root.home },
        { label: Translation.tr("Pictures"),  icon: "image",     path: Places.picturesDir },
        { label: Translation.tr("Downloads"), icon: "download",  path: Places.downloadsDir },
        { label: Translation.tr("Library"),   icon: "wallpaper", path: Wallpaper.wallpaperDir }
    ]

    FolderListModel {
        id: fsModel
        folder: root.panel.browseFolder
        showDirs: true
        showDirsFirst: true
        showFiles: true
        showDotAndDotDot: false
        showHidden: false
        // So *.jpg matches .JPG too: filters are the only place this browser cares about case.
        caseSensitive: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.webp"]
        onCountChanged: Qt.callLater(root.recount)
        onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(root.recount)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.panel.island ? 0 : Tokens.spacingSm
        spacing: Tokens.spacingSm

        // ── Places ────────────────────────────────────────────────────────
        Flow {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            Repeater {
                model: root.places
                delegate: ChipButton {
                    required property var modelData
                    visible: modelData.path !== ""
                    tonal: true
                    symbol: modelData.icon
                    label: modelData.label
                    on: root.here === String(modelData.path).replace(/\/+$/, "")
                    tint: root.panel.accent
                    onActivated: root.panel.browseFolder = "file://" + modelData.path
                }
            }
        }

        // ── Where you are ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            ChipButton {
                tonal: true
                symbol: "arrow_upward"
                enabled: root.canGoUp
                tint: root.panel.accent
                onActivated: root.panel.browseFolder = root.upFolder
                HoverTip { text: Translation.tr("Up one folder"); below: true }
            }
            // The steps, scrolled to the end: the folder you are in is always in view.
            Flickable {
                id: crumbFlick
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXs
                contentWidth: crumbRow.implicitWidth
                contentHeight: height
                clip: true
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                onContentWidthChanged: crumbFlick.contentX = Math.max(0, crumbFlick.contentWidth - crumbFlick.width)

                Row {
                    id: crumbRow
                    height: crumbFlick.height
                    spacing: Tokens.spacingXs

                    Repeater {
                        model: Lib.crumbs(root.panel.browseFolder, root.home)
                        delegate: Row {
                            id: step
                            required property var modelData
                            required property int index
                            readonly property bool last: step.index === Lib.crumbs(root.panel.browseFolder, root.home).length - 1
                            height: crumbRow.height
                            spacing: Tokens.spacingXs

                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: step.index > 0
                                name: "chevron_right"
                                font.pixelSize: Tokens.iconMd
                                color: root.palette.fgDim
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: stepLabel.implicitWidth + Tokens.spacingLg * 2
                                height: Tokens.iconLg + Tokens.spacingSm
                                radius: height / 2
                                color: step.last ? root.palette.primaryContainer
                                     : stepMouse.containsMouse ? root.palette.plate : root.palette.section
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                StyledText {
                                    id: stepLabel
                                    anchors.centerIn: parent
                                    text: step.modelData.label
                                    variant: "label"
                                    font.weight: step.last ? Font.DemiBold : Font.Medium
                                    color: step.last ? root.palette.fgOnPrimaryContainer : root.palette.fgMuted
                                }
                                MouseArea {
                                    id: stepMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.panel.browseFolder = "file://" + step.modelData.path
                                    Accessible.role: Accessible.Button
                                    Accessible.name: step.modelData.label
                                    Accessible.onPressAction: root.panel.browseFolder = "file://" + step.modelData.path
                                }
                            }
                        }
                    }
                }
            }
            ChipButton {
                visible: root.pics > 0
                tonal: true
                symbol: "select_all"
                label: root.allPicked ? Translation.tr("None") : Translation.tr("All %1").arg(root.pics)
                on: root.allPicked
                tint: root.panel.accent
                onActivated: root.pickAll()
            }
        }

        // ── The folder ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: fileGrid
                anchors.fill: parent
                clip: true
                model: fsModel
                boundsBehavior: Flickable.StopAtBounds
                cacheBuffer: fileGrid.cellHeight * 2
                bottomMargin: root.panel.picked.length > 0 ? Tokens.iconXl * 2 : Tokens.spacingLg
                Behavior on bottomMargin { NumberAnimation { duration: Motion.standard } }

                readonly property int cols: Math.max(2, Math.floor(width / 150))
                cellWidth:  Math.floor(width / fileGrid.cols)
                cellHeight: Math.round((fileGrid.cellWidth - Tokens.spacingXs * 2 - root.panel.cardMat * 2) * 9 / 16)
                            + Tokens.spacingXs * 2 + root.panel.cardMat * 2

                delegate: Item {
                    id: cell
                    required property string fileName
                    required property string filePath
                    required property bool   fileIsDir
                    required property int    index

                    width:  fileGrid.cellWidth
                    height: fileGrid.cellHeight

                    readonly property bool picked: !cell.fileIsDir && root.panel.isPicked(cell.filePath)
                    readonly property real corner: Tokens.radiusCard
                    readonly property real ring: root.panel.cardMat + (cell.picked ? Tokens.spacingXs : 0)

                    PopIn { id: pop; active: true; index: cell.index; cap: 9 }
                    opacity: pop.opacity
                    SpringValue {
                        id: lean
                        target: press.pressed ? 0.96 : hover.hovered ? 1.03 : 1
                        spec: Motion.springSpatialFast
                        epsilon: 0.001
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingXs
                        scale: lean.value * pop.scale

                        // ── A folder: a card with a badge ─────────────────
                        Rectangle {
                            anchors.fill: parent
                            visible: cell.fileIsDir
                            radius: cell.corner
                            color: root.palette.plate
                            border.width: Tokens.borderWidth
                            border.color: root.palette.outline

                            Column {
                                anchors.centerIn: parent
                                width: parent.width - Tokens.spacingMd * 2
                                spacing: Tokens.spacingXs
                                Item {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Tokens.iconXl + Tokens.spacingMd
                                    height: width
                                    MorphShape {
                                        anchors.fill: parent
                                        shape: hover.hovered ? "cookie9" : "squircle"
                                        spec: Motion.springSpatialFast
                                        fillColor: hover.hovered ? root.palette.primary : root.palette.primaryContainer
                                    }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: hover.hovered ? "folder_open" : "folder"
                                        fill: 1
                                        font.pixelSize: Tokens.iconLg
                                        color: hover.hovered ? root.palette.fgOnPrimary : root.palette.fgOnPrimaryContainer
                                    }
                                }
                                StyledText {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: cell.fileName
                                    variant: "caption"
                                    font.weight: Font.Medium
                                    elide: Text.ElideMiddle
                                }
                            }
                        }

                        // ── A picture: on its canvas ──────────────────────
                        Rectangle {
                            anchors.fill: parent
                            visible: !cell.fileIsDir
                            radius: cell.corner
                            color: cell.picked ? root.palette.primary : root.palette.plate
                            border.width: Tokens.borderWidth
                            border.color: cell.picked ? "transparent" : root.palette.outline
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        ClippingRectangle {
                            id: pic
                            anchors.fill: parent
                            anchors.margins: cell.ring
                            visible: !cell.fileIsDir
                            radius: Math.max(Tokens.radiusSm, cell.corner - cell.ring)
                            color: root.palette.section
                            Behavior on anchors.margins { NumberAnimation { duration: Motion.respond } }

                            Image {
                                anchors.fill: parent
                                source: cell.fileIsDir ? "" : ("file://" + cell.filePath)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: false
                                sourceSize.width: 360
                                sourceSize.height: 240
                                smooth: true
                            }
                            StateLayer {
                                anchors.fill: parent
                                radius: pic.radius
                                hovered: hover.hovered
                                layerColor: root.panel.accent
                            }

                            // The tick: an empty ring under the pointer (it says a press ticks), a cookie once ticked.
                            Item {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.margins: Tokens.spacingSm
                                width: Tokens.iconLg + Tokens.spacingXs
                                height: width
                                opacity: cell.picked || hover.hovered ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                MorphShape {
                                    anchors.fill: parent
                                    shape: cell.picked ? "cookie9" : "circle"
                                    spec: Motion.springSpatialFast
                                    fillColor: cell.picked ? root.palette.primary : root.palette.alpha(root.palette.surface, 0.86)
                                    strokeColor: cell.picked ? "transparent" : root.palette.outline
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "check"
                                    fill: 1
                                    font.pixelSize: Tokens.iconMd
                                    color: root.palette.fgOnPrimary
                                    opacity: cell.picked ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                }
                            }

                            // Its name, under the pointer.
                            Rectangle {
                                readonly property bool shown: hover.hovered
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: Tokens.spacingSm
                                width: Math.min(nameText.implicitWidth + Tokens.spacingMd * 2, pic.width - Tokens.spacingSm * 2)
                                height: Tokens.iconLg + Tokens.spacingSm
                                radius: height / 2
                                color: root.palette.alpha(root.palette.surface, 0.86)
                                opacity: shown ? 1 : 0
                                visible: opacity > 0.005
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                StyledText {
                                    id: nameText
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.leftMargin: Tokens.spacingMd
                                    width: parent.width - Tokens.spacingMd * 2
                                    text: cell.fileName
                                    variant: "caption"
                                    elide: Text.ElideMiddle
                                }
                            }
                        }
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    MouseArea {
                        id: press
                        anchors.fill: parent
                        onClicked: {
                            if (cell.fileIsDir) root.panel.browseFolder = "file://" + cell.filePath
                            else                root.panel.togglePick(cell.filePath)
                        }
                        Accessible.role: Accessible.Button
                        Accessible.name: cell.fileName
                        Accessible.onPressAction: press.clicked(null)
                    }
                }
            }
            Scrollbar { flickable: fileGrid }

            // Nothing here: say so, and say what to do.
            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - Tokens.spacingXxl * 2
                spacing: Tokens.spacingSm
                visible: fsModel.status === FolderListModel.Ready && fsModel.count === 0

                Item {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.iconXl * 2
                    Layout.preferredHeight: Tokens.iconXl * 2
                    MorphShape { anchors.fill: parent; shape: "cookie9"; fillColor: root.palette.primaryContainer }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "image"
                        fill: 1
                        font.pixelSize: Tokens.iconXl
                        color: root.palette.fgOnPrimaryContainer
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("No pictures here")
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Open a folder, or drop pictures on the panel to add them.")
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            // ── Add ───────────────────────────────────────────────────────
            // Copies the ticked files in, then clears the ticks but stays open: the gallery rescans
            // underneath, and you may well want more from the same folder.
            ChipTray {
                z: 5
                groupShown: root.panel.picked.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.spacingMd

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    leftPadding: Tokens.spacingSm
                    text: Translation.tr("%1 picked").arg(root.panel.picked.length)
                    variant: "label"
                }
                ChipButton {
                    symbol: "close"
                    label: Translation.tr("Clear")
                    tint: root.panel.accent
                    onActivated: root.panel.picked = []
                }
                ChipButton {
                    symbol: "add"
                    label: Translation.tr("Add")
                    on: true
                    tint: root.panel.accent
                    enabled: !Wallpaper.importing
                    onActivated: { Wallpaper.addPaths(root.panel.picked); root.panel.picked = [] }
                }
            }
        }
    }
}
