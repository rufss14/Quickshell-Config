import QtQuick
import Quickshell
import "../../../config"
import "../../../components"

// ── CompositionStrip ─────────────────────────────────────────────────────
// Official / AUR / Flatpak side by side, widths by share of the total. Since 2026-11-15 it is the blocky bar
// of the media page's slider (ThickSlider) rather than a hairline: as tall as that slider, its outer ends squared
// off (30% of the height), the corners where two pieces meet small, a gap between pieces, and a piece's count
// written inside it when it is wide enough to hold it. A source with none takes no piece; nothing pending draws
// one quiet track.
// (Was UpdatePanel's inline `CompositionStrip`; `host` is the UpdatePanel.)
Item {
    required property var host
    id: strip

    property int official: 0
    property int aur:      0
    property int flatpak:  0
    readonly property int total: strip.official + strip.aur + strip.flatpak

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property real big: Math.round(strip.height * 0.3)
    readonly property real small: Math.max(1, Math.round(strip.big * 0.4))
    readonly property real gap: Tokens.spacingXs * 2
    readonly property var parts: [
        { n: strip.official, tone: strip.host.officialTint },
        { n: strip.aur,      tone: strip.host.aurTint },
        { n: strip.flatpak,  tone: strip.host.flatpakTint }
    ].filter(p => p.n > 0)
    readonly property real room: strip.width - strip.gap * Math.max(0, strip.parts.length - 1)

    implicitHeight: Tokens.spacingXl + Tokens.spacingXs

    Rectangle {
        anchors.fill: parent
        radius: strip.big
        color: strip.palette.alpha(strip.palette.fg, 0.10)
        visible: strip.total === 0
    }

    Row {
        anchors.fill: parent
        visible: strip.total > 0
        spacing: strip.gap

        Repeater {
            model: strip.parts
            delegate: Rectangle {
                id: piece
                required property var modelData
                required property int index
                readonly property bool first: piece.index === 0
                readonly property bool last: piece.index === strip.parts.length - 1
                // At least wide enough for its number, so one AUR update among a hundred still reads.
                width: Math.max(strip.height * 1.6, strip.room * piece.modelData.n / Math.max(1, strip.total))
                height: strip.height
                color: piece.modelData.tone
                topLeftRadius:     piece.first ? strip.big : strip.small
                bottomLeftRadius:  piece.first ? strip.big : strip.small
                topRightRadius:    piece.last  ? strip.big : strip.small
                bottomRightRadius: piece.last  ? strip.big : strip.small
                Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }

                StyledText {
                    anchors.centerIn: parent
                    visible: piece.width > implicitWidth + Tokens.spacingMd
                    text: String(piece.modelData.n)
                    variant: "caption"
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: strip.palette.fgOnPrimary
                }
            }
        }
    }
}
