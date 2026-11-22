pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── IslandCaptures ────────────────────────────────────────────────────────────
// Screenshots on an island (2026-11-15, the user's pick of new pages): the shell's snip tool and the pictures it
// saved, beside Clips on the bottom-middle island.
//
//   left    the loud card: Snip as the one loud pill (Super+P), and the snip tool's other ends as four option
//           cards (Copy, Text, Pin, Record area); how many pictures float pinned, with Close all
//   right   the screenshots folder newest first as pictures on canvases (Screenshot.saveDir), copy / edit /
//           remove under the pointer (remove asks on a layer over the picture), the folder one press away
//
// The tool is services/Snip; a press steps the island aside first so the snip overlay has the screen. The folder
// is read with FolderListModel (Qt's own, as the wallpaper browser does). Everything real is the services'.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    // Out of the way, then the snip tool.
    function snip(action) {
        UiState.closeIsland(UiState.islandOfPage("captures"))
        Qt.callLater(() => Snip.start(action))
    }

    FolderListModel {
        id: shots
        folder: "file://" + Screenshot.saveDir
        showDirs: false
        showDotAndDotDot: false
        caseSensitive: false
        nameFilters: ["*.png", "*.jpg", "*.jpeg", "*.webp"]
        sortField: FolderListModel.Time
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ The tool, loud ════════════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: "content_cut"
                        shape: Snip.busy ? "cookie9" : "squircle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Capture")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: shots.count === 1 ? Translation.tr("1 screenshot saved") : Translation.tr("%1 screenshots saved").arg(shots.count)
                            variant: "caption"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }

                // The newest picture, large: what the last snip caught (press it to edit).
                Rectangle {
                    id: latest
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    readonly property string path: shots.count > 0 ? (shots.get(0, "filePath") ?? "") : ""
                    radius: Tokens.radiusCard
                    color: root.palette.alpha(hero.ink, 0.08)
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: latest.path !== "" && !StreamMode.active ? "file://" + latest.path : ""
                        sourceSize.width: 560
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: latest.path === "" || StreamMode.active
                        name: StreamMode.active ? "visibility_off" : "image"
                        font.pixelSize: Tokens.iconXl
                        color: hero.inkDim
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: latest.path !== ""
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { UiState.closeIsland(UiState.islandOfPage("captures")); UiState.openAnnotate(latest.path) }
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Edit the newest screenshot")
                    }
                }

                // The tool's other ends, as cards: each starts a snip that ends there.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    columns: 2
                    columnSpacing: Tokens.spacingXs
                    rowSpacing: Tokens.spacingXs
                    Repeater {
                        model: [
                            { id: "copy",   label: Translation.tr("Copy"),        shape: "cookie9", symbol: "content_copy" },
                            { id: "text",   label: Translation.tr("Read text"),   shape: "clover", symbol: "text_fields" },
                            { id: "pin",    label: Translation.tr("Pin"),         shape: "sunny", symbol: "push_pin" },
                            { id: "record", label: Translation.tr("Record"), shape: "squircle", symbol: "fiber_manual_record" }
                        ]
                        delegate: OptionCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: modelData.label
                            symbol: modelData.symbol
                            shape: modelData.shape
                            enabled: Snip.blocker(modelData.id) === ""
                            opacity: enabled ? 1 : 0.45
                            onActivated: root.snip(modelData.id)
                        }
                    }
                }

                // Pictures floating pinned on the screen.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: SnipPins.items.length > 0
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: "push_pin"
                        fill: 1
                        color: hero.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: SnipPins.items.length === 1 ? Translation.tr("1 pinned") : Translation.tr("%1 pinned").arg(SnipPins.items.length)
                        variant: "caption"
                        color: hero.inkDim
                    }
                    ChipButton {
                        label: Translation.tr("Close all")
                        tonal: true
                        tint: hero.ink
                        onActivated: SnipPins.closeAll()
                    }
                }

                ChipButton {
                    Layout.fillWidth: true
                    solid: true
                    symbol: "content_cut"
                    label: Translation.tr("Snip  ·  Super+P")
                    onActivated: root.snip("save")
                }
            }
        }

        // ══ The folder ════════════════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: true
            Layout.fillHeight: true
            order: 1
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText {
                        text: String(shots.count)
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Screenshots")
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: StreamMode.active ? Translation.tr("Hidden while you share your screen") : Screenshot.saveDir
                            variant: "micro"
                            emphasis: "dim"
                            elide: Text.ElideMiddle
                        }
                    }
                    ChipButton {
                        symbol: "folder_open"
                        label: Translation.tr("Folder")
                        tonal: true
                        onActivated: { Clips.showFolder(Screenshot.saveDir); UiState.closeIsland(UiState.islandOfPage("captures")) }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Column {
                        anchors.centerIn: parent
                        visible: shots.count === 0
                        spacing: Tokens.spacingXs
                        MorphShape {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Tokens.iconXl * 1.5
                            height: width
                            shape: "cookie9"
                            turns: false
                            fillColor: root.palette.plate
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "image"
                                color: root.palette.fgMuted
                            }
                        }
                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Translation.tr("No screenshots yet. Press Super+P.")
                            variant: "caption"
                            emphasis: "muted"
                        }
                    }

                    GridView {
                        id: grid
                        anchors.fill: parent
                        visible: shots.count > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: shots
                        cellWidth: Math.floor(grid.width / 3)
                        cellHeight: Math.round((grid.cellWidth - Tokens.spacingSm) * 9 / 16) + Tokens.spacingSm

                        delegate: Item {
                            id: cell
                            required property string filePath
                            required property string fileName
                            required property int index
                            width: grid.cellWidth
                            height: grid.cellHeight
                            property bool confirm: false

                            PopIn { id: pop; active: true; index: cell.index; cap: 6; delay: Motion.stagger * 3 }
                            opacity: pop.opacity
                            HoverHandler { id: hover }
                            SpringValue {
                                id: lean
                                target: hover.hovered ? 1.03 : 1
                                spec: Motion.springSpatialFast
                                epsilon: 0.002
                            }

                            Rectangle {
                                id: canvas
                                x: Tokens.spacingXs
                                width: cell.width - Tokens.spacingSm
                                height: cell.height - Tokens.spacingSm
                                radius: Tokens.radiusCard
                                color: root.palette.plate
                                border.width: Tokens.borderWidth
                                border.color: cell.index === 0 ? root.palette.primary : root.palette.outline
                                scale: lean.value * pop.scale
                                clip: true

                                // While the screen is being shared (StreamMode) the pictures stay off the stream: say so.
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: StreamMode.active
                                    name: "visibility_off"
                                    color: root.palette.fgDim
                                }
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.borderWidth
                                    source: StreamMode.active ? "" : "file://" + cell.filePath
                                    sourceSize.width: 320
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { UiState.closeIsland(UiState.islandOfPage("captures")); UiState.openAnnotate(cell.filePath) }
                                    Accessible.role: Accessible.Button
                                    Accessible.name: Translation.tr("Edit %1").arg(cell.fileName)
                                }
                                // Copy, edit, remove: a capsule at the corner, under the pointer.
                                Rectangle {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Tokens.spacingXs
                                    width: tools.implicitWidth + Tokens.spacingXs * 2
                                    height: tools.implicitHeight + Tokens.spacingXs * 2
                                    radius: height / 2
                                    color: root.palette.alpha(root.palette.surface, 0.9)
                                    opacity: hover.hovered && !cell.confirm ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                    Row {
                                        id: tools
                                        anchors.centerIn: parent
                                        CardTool {
                                            symbol: "content_copy"
                                            name: Translation.tr("Copy")
                                            onActivated: Screenshot.copyToClipboard(cell.filePath)
                                        }
                                        CardTool {
                                            symbol: "close"
                                            name: Translation.tr("Remove")
                                            onActivated: cell.confirm = true
                                        }
                                    }
                                }
                                // Remove asks on a layer over the picture.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: cell.confirm
                                    color: root.palette.alpha(root.palette.surface, 0.88)
                                    MouseArea { anchors.fill: parent }
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Tokens.spacingXs
                                        ChipButton {
                                            label: Translation.tr("Keep")
                                            tonal: true
                                            onActivated: cell.confirm = false
                                        }
                                        ChipButton {
                                            symbol: "delete"
                                            label: Translation.tr("Remove")
                                            solid: true
                                            tint: root.palette.danger
                                            onActivated: { cell.confirm = false; Screenshot.remove(cell.filePath) }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
