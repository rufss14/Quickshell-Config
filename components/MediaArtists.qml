import QtQuick
import Quickshell
import "../config"

// ── MediaArtists ──────────────────────────────────────────────────────────────
// A song's artists as a line of links, one per credit, joined by commas (medialinks.js `artists`: [{ name, link }]).
// A long name is cut at the line's end rather than pushing the others off it.
// ─────────────────────────────────────────────────────────────────────────────
Flow {
    id: root

    property var    artists: []
    property string variant: "body"
    property color  ink: Colors.of(QsWindow.window).fgMuted

    Repeater {
        model: root.artists
        delegate: Row {
            id: credit
            required property var modelData
            required property int index
            MediaLink {
                width: Math.min(implicitWidth, root.width)
                text: credit.modelData.name
                link: credit.modelData.link
                variant: root.variant
                base: root.ink
                elide: Text.ElideRight
            }
            StyledText {
                visible: credit.index < root.artists.length - 1
                text: ", "
                variant: root.variant
                color: root.ink
            }
        }
    }
}
