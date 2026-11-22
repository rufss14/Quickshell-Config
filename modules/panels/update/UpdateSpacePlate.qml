import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── UpdateSpacePlate ── the update page's "will it fit" plate (island only; 2026-11-15). ──────────────────────
// What this run downloads (official + Flatpak; AUR builds here and has no download size), beside the free space on
// / as a short blocky bar and the pacman cache it lands in. Tight space (less than three times the download, or
// under 5 GB free) turns the bar and its line to the warning tone; nothing else changes.
// Storage is acquired while the plate exists, as the other island pages do.
Rectangle {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var rootFs: Storage.filesystems.filter(f => f.mount === "/")[0] ?? null
    readonly property real avail: root.rootFs ? root.rootFs.avail : 0
    readonly property real usedShare: root.rootFs && root.rootFs.used + root.rootFs.avail > 0
        ? root.rootFs.used / (root.rootFs.used + root.rootFs.avail) : 0
    readonly property var cache: Storage.contextFor("paccache")
    readonly property bool tight: root.rootFs !== null
        && (root.avail < 5 * 1073741824 || root.avail < Updates.downloadBytes * 3)
    readonly property color tone: root.tight ? root.palette.warning : root.palette.primary

    Component.onCompleted: Storage.acquire()
    Component.onDestruction: Storage.release()

    implicitHeight: col.implicitHeight + Tokens.spacingMd * 2
    radius: Tokens.radiusXl
    color: root.palette.plate

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            MaterialIcon {
                name: "download"
                fill: 1
                color: root.palette.fgDim
                font.pixelSize: Tokens.iconMd
            }
            StyledText {
                text: Translation.tr("Download")
                variant: "micro"
                color: root.palette.fgDim
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: Updates.downloadText !== "" ? Updates.downloadText
                : Updates.aurCount > 0 ? Translation.tr("Built here")
                : Updates.total === 0 ? Translation.tr("Nothing to fetch") : "—"
            variant: "title"
            font.weight: Font.Bold
            font.features: ({ tnum: 1 })
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        // How full / is: the blocky bar of the composition strip, short.
        Item {
            id: bar
            Layout.fillWidth: true
            implicitHeight: Tokens.spacingSm + Tokens.spacingXs
            readonly property real r: Math.max(1, Math.round(bar.height * 0.3))
            Rectangle {
                anchors.fill: parent
                radius: bar.r
                color: root.palette.alpha(root.palette.fg, 0.10)
            }
            Rectangle {
                width: Math.max(bar.height, bar.width * root.usedShare)
                height: bar.height
                radius: bar.r
                color: root.tone
                visible: root.rootFs !== null
                Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.rootFs === null ? Translation.tr("Looking at the disk…")
                : root.tight ? Translation.tr("Tight: %1 free").arg(Storage.bytes(root.avail))
                : Translation.tr("%1 free on /").arg(Storage.bytes(root.avail))
            variant: "caption"
            font.weight: root.tight ? Font.DemiBold : Font.Normal
            color: root.tight ? root.palette.warning : root.palette.fg
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: root.cache !== null
            text: root.cache ? Translation.tr("Package cache %1").arg(Storage.bytes(root.cache.bytes)) : ""
            variant: "micro"
            color: root.palette.fgDim
            elide: Text.ElideRight
        }
    }
}
