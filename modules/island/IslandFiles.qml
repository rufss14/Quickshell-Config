pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── IslandFiles ───────────────────────────────────────────────────────────────
// Your files on an island (2026-11-15, one of the user's new pages; the bottom-left island, beside Desk and Timer):
//
//   left    the loud card: the newest downloads (finished ones only), press to open; the trash, with Open and
//           Empty (Empty asks on the row, never by arming in place)
//   right   the files you opened lately in any app (the freedesktop recent store, services/Recents) as cards: a
//           press opens one, a pin under the pointer keeps it on the dock (FilePins); the pinned ones as chips;
//           and every disk as a bar of how full it is (services/Storage, held while this shows)
//
// Opening goes through gio (Places.openFile). Everything real is the services'.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    Component.onCompleted: Storage.acquire()
    Component.onDestruction: Storage.release()

    readonly property var recent: Recents.recent(12)
    readonly property var downloads: Places.recentDownloads(4)
    readonly property var disks: Storage.filesystems.filter(f => f.size > 0).slice(0, 3)
    property bool confirmEmpty: false

    function open(path) {
        UiState.closeIsland(UiState.islandOfPage("files"))
        Places.openFile(path)
    }
    // A symbol for a file by what its name says it is.
    function iconFor(name) {
        const ext = String(name).split(".").pop().toLowerCase()
        if (["png", "jpg", "jpeg", "gif", "webp", "svg", "avif"].indexOf(ext) >= 0) return "image"
        if (["mp4", "mkv", "webm", "mov", "avi"].indexOf(ext) >= 0) return "movie"
        if (["mp3", "flac", "ogg", "wav", "m4a", "opus"].indexOf(ext) >= 0) return "music_note"
        if (["js", "ts", "py", "qml", "c", "cpp", "rs", "go", "sh", "lua", "json", "toml"].indexOf(ext) >= 0) return "code"
        if (["zip", "tar", "gz", "xz", "7z", "rar", "zst"].indexOf(ext) >= 0) return "folder"
        return "description"
    }
    function ago(t) {
        void Clock.now
        const m = Math.max(0, Math.round((Date.now() - t) / 60000))
        if (m < 1) return Translation.tr("just now")
        if (m < 60) return Translation.tr("%1 min ago").arg(m)
        const h = Math.round(m / 60)
        if (h < 24) return Translation.tr("%1 h ago").arg(h)
        return Translation.tr("%1 d ago").arg(Math.round(h / 24))
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Downloads and trash, loud ═════════════════════════════════════════
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
                        symbol: "download"
                        shape: root.downloads.length > 0 ? "cookie9" : "circle"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Downloads")
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: hero.ink
                    }
                    ChipButton {
                        symbol: "folder_open"
                        tint: hero.ink
                        Accessible.name: Translation.tr("Open Downloads")
                        onActivated: { UiState.closeIsland(UiState.islandOfPage("files")); Places.openDownloads() }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.downloads.length === 0
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Nothing downloaded yet")
                    variant: "caption"
                    color: hero.inkDim
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: root.downloads.length > 0
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: root.downloads
                        delegate: Rectangle {
                            id: dl
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                            radius: Tokens.radiusSm
                            color: dlArea.containsMouse ? root.palette.alpha(hero.ink, 0.12) : root.palette.alpha(hero.ink, 0.06)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Tokens.spacingSm
                                anchors.rightMargin: Tokens.spacingSm
                                spacing: Tokens.spacingSm
                                MaterialIcon { name: root.iconFor(dl.modelData.name); color: hero.ink }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: dl.modelData.name
                                    variant: "caption"
                                    color: hero.ink
                                    elide: Text.ElideMiddle
                                }
                            }
                            MouseArea {
                                id: dlArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.open(dl.modelData.path)
                                Accessible.role: Accessible.Button
                                Accessible.name: Translation.tr("Open %1").arg(dl.modelData.name)
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // What is pinned on the dock: one press away here too.
                StyledText {
                    Layout.fillWidth: true
                    visible: FilePins.files.length > 0
                    text: Translation.tr("Pinned")
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: hero.ink
                }
                Flow {
                    Layout.fillWidth: true
                    visible: FilePins.files.length > 0
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: FilePins.files.slice(0, 6)
                        delegate: ChipButton {
                            required property var modelData
                            symbol: modelData.dir ? "folder" : root.iconFor(modelData.name)
                            label: modelData.name
                            labelVariant: "caption"
                            tonal: true
                            tint: hero.ink
                            onActivated: root.open(modelData.path)
                        }
                    }
                }

                // The usual places, one press each.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    columns: 2
                    columnSpacing: Tokens.spacingXs
                    rowSpacing: Tokens.spacingXs
                    Repeater {
                        model: [
                            { t: Translation.tr("Home"),     d: Places.home,              i: "folder",      s: "cookie9" },
                            { t: Translation.tr("Pictures"), d: Places.picturesDir,       i: "image",       s: "clover" },
                            { t: Translation.tr("Videos"),   d: Places.home + "/Videos",  i: "movie",       s: "sunny" },
                            { t: Translation.tr("Shots"),    d: Screenshot.saveDir,       i: "content_cut", s: "squircle" }
                        ]
                        delegate: OptionCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            label: modelData.t
                            symbol: modelData.i
                            shape: modelData.s
                            onActivated: { UiState.closeIsland(UiState.islandOfPage("files")); Clips.showFolder(modelData.d) }
                        }
                    }
                }

                // The trash: Open, Empty (asks on the row).
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    MaterialIcon { name: "delete"; fill: Places.trashFull ? 1 : 0; color: hero.ink }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.confirmEmpty ? Translation.tr("Empty the trash?")
                            : Places.trashCount === 0 ? Translation.tr("Trash is empty")
                            : Translation.tr("Trash: %1").arg(Places.trashCount)
                        variant: "caption"
                        color: hero.inkDim
                        elide: Text.ElideRight
                    }
                    ChipButton {
                        visible: !root.confirmEmpty && Places.trashFull
                        label: Translation.tr("Open")
                        tonal: true
                        tint: hero.ink
                        onActivated: { UiState.closeIsland(UiState.islandOfPage("files")); Places.openTrash() }
                    }
                    ChipButton {
                        visible: !root.confirmEmpty && Places.trashFull
                        label: Translation.tr("Empty")
                        tonal: true
                        tint: hero.ink
                        onActivated: root.confirmEmpty = true
                    }
                    ChipButton {
                        visible: root.confirmEmpty
                        label: Translation.tr("Keep")
                        tonal: true
                        tint: hero.ink
                        onActivated: root.confirmEmpty = false
                    }
                    ChipButton {
                        visible: root.confirmEmpty
                        label: Translation.tr("Empty")
                        solid: true
                        tint: root.palette.danger
                        onActivated: { root.confirmEmpty = false; Places.emptyTrash() }
                    }
                }
            }
        }

        // ══ Right ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── Recent files ───────────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: Translation.tr("Opened lately")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        visible: root.recent.length === 0
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Translation.tr("Files you open in your apps show up here")
                        variant: "caption"
                        emphasis: "muted"
                    }
                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.recent.length > 0
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        model: root.recent
                        cellWidth: Math.floor(grid.width / 3)
                        cellHeight: Tokens.iconXl + Tokens.spacingLg * 2 + Tokens.spacingXs

                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            readonly property bool pinned: FilePins.isPinned(cell.modelData.path)
                            width: grid.cellWidth
                            height: grid.cellHeight
                            PopIn { id: pop; active: true; index: cell.index; cap: 6 }
                            opacity: pop.opacity
                            HoverHandler { id: hover }

                            Rectangle {
                                x: Tokens.spacingXs / 2
                                width: cell.width - Tokens.spacingXs
                                height: cell.height - Tokens.spacingXs
                                scale: pop.scale
                                radius: Tokens.radiusCard
                                color: hover.hovered ? root.palette.alpha(root.palette.fg, 0.10) : root.palette.surfaceHigh
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.open(cell.modelData.path)
                                    Accessible.role: Accessible.Button
                                    Accessible.name: Translation.tr("Open %1").arg(cell.modelData.name)
                                }
                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Tokens.spacingSm
                                    anchors.rightMargin: Tokens.spacingXs
                                    spacing: Tokens.spacingSm
                                    MorphShape {
                                        Layout.preferredWidth: Tokens.iconXl
                                        Layout.preferredHeight: Tokens.iconXl
                                        shape: cell.pinned ? "cookie9" : "squircle"
                                        turns: false
                                        fillColor: cell.pinned ? root.palette.primaryContainer : root.palette.section
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            name: root.iconFor(cell.modelData.name)
                                            color: cell.pinned ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: cell.modelData.name
                                            variant: "caption"
                                            font.weight: Font.DemiBold
                                            elide: Text.ElideMiddle
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: root.ago(cell.modelData.time)
                                            variant: "micro"
                                            emphasis: "muted"
                                        }
                                    }
                                    CardTool {
                                        visible: hover.hovered || cell.pinned
                                        symbol: "push_pin"
                                        filled: cell.pinned
                                        name: cell.pinned ? Translation.tr("Unpin from the dock") : Translation.tr("Pin to the dock")
                                        onActivated: cell.pinned ? FilePins.unpin(cell.modelData.path) : FilePins.pin(cell.modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Disks ──────────────────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: diskCol.implicitHeight + Tokens.spacingMd * 2
                visible: root.disks.length > 0
                order: 2

                ColumnLayout {
                    id: diskCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: root.disks
                        delegate: RowLayout {
                            id: disk
                            required property var modelData
                            readonly property real frac: disk.modelData.size > 0 ? disk.modelData.used / disk.modelData.size : 0
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            MaterialIcon { name: "hard_drive"; color: root.palette.fgMuted }
                            StyledText {
                                Layout.preferredWidth: Tokens.spacingXl * 5
                                text: disk.modelData.mount
                                variant: "caption"
                                font.weight: Font.DemiBold
                                elide: Text.ElideMiddle
                            }
                            Meter {
                                Layout.fillWidth: true
                                value: disk.frac
                                accent: disk.frac > 0.9 ? root.palette.danger : root.palette.primary
                            }
                            StyledText {
                                Layout.preferredWidth: Tokens.spacingXl * 6
                                horizontalAlignment: Text.AlignRight
                                text: Translation.tr("%1 free").arg(Storage.bytes(disk.modelData.avail))
                                variant: "caption"
                                emphasis: "muted"
                                font.features: ({ tnum: 1 })
                            }
                        }
                    }
                }
            }
        }
    }
}
