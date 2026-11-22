import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/queuemodel.js" as QueueModel
import "../../../services/medialinks.js" as Links

// ── QueueRowContent ───────────────────────────────────────────────────────────
// One queue row's contents: cover, title, artist (linked, MediaArtists), and a Jam's credit ("added by you / Zed").
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    property var    row: null
    property var    jam: null
    property color  ink: Colors.of(QsWindow.window).fg
    property color  inkDim: Colors.of(QsWindow.window).fgMuted

    spacing: Tokens.spacingMd

    // The queue carries names, not ids: the artist links to a search for it (medialinks.js).
    readonly property var artistLinks: root.row && root.row.artist !== ""
        ? [{ name: root.row.artist, link: Links.searchUri(root.row.artist) }] : []

    // The cover in the same cookie as the album cover on the Now Playing page (CookieCover): a turning scallop, not a
    // square. Masked by the shape, the way the cover is.
    Item {
        id: cover
        Layout.preferredWidth: Tokens.iconXl * 2 - Tokens.spacingSm
        Layout.preferredHeight: Layout.preferredWidth
        Layout.alignment: Qt.AlignVCenter

        Rectangle {
            anchors.fill: parent
            color: Colors.of(QsWindow.window).alpha(Config.albumCardColors ? AlbumArt.accent : Colors.of(QsWindow.window).primary, 0.2)
            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: coverMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
            Image {
                anchors.fill: parent
                visible: root.row && root.row.image !== ""
                source: root.row ? root.row.image : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(width * 2, height * 2)
            }
        }
        Item {
            id: coverMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            MorphShape { anchors.fill: parent; shape: "cookie9"; fillColor: "white"; turns: false }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.row ? root.row.title : ""
            variant: "label"
            font.weight: Font.DemiBold
            color: root.ink
            elide: Text.ElideRight
        }
        MediaArtists {
            Layout.fillWidth: true
            artists: root.artistLinks
            variant: "caption"
            ink: root.ink
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: {
                const who = root.row ? QueueModel.creditFor(root.row, root.jam) : ""
                return who !== "" ? Translation.tr("Added by %1").arg(who) : ""
            }
            variant: "micro"
            color: root.inkDim
            elide: Text.ElideRight
        }
    }
}
