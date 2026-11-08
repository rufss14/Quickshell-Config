import QtQuick
import Quickshell
import Quickshell.Widgets
import "../config"
import "../services/clockfmt.js" as ClockFmt
// ── ClipThumb ─────────────────────────────────────────────────────────────────
// One clip's thumbnail, rounded: the frame clips-lib.py cut from it, or a film
// glyph while there isn't one (a recording still being written, a file ffprobe
// can't read). Optionally its duration in a corner badge. Used by the clips pill,
// its card and the gallery (services/Clips `clips` entries).
// ─────────────────────────────────────────────────────────────────────────────
ClippingRectangle {
    id: root

    property var entry: null          // a Clips.clips entry, or null (NOT `clip`: that is Item.clip)
    property bool showDuration: true
    // Decode size: the tile's own box is plenty, never the 480px source.
    property int decodeWidth: 320

    readonly property string _thumb: root.entry?.thumb ?? ""

    radius: Tokens.radiusSm
    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)

    Image {
        id: img
        anchors.fill: parent
        source: root._thumb !== "" ? "file://" + root._thumb : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        smooth: true
        sourceSize.width: root.decodeWidth
        opacity: img.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    MaterialIcon {
        anchors.centerIn: parent
        visible: img.status !== Image.Ready
        glyph: "\u{F0567}"                                   // 󰕧 video
        font.pixelSize: Math.round(Math.min(root.width, root.height) * 0.4)
        color: Colors.of(QsWindow.window).fgMuted
    }

    Rectangle {
        visible: root.showDuration && (root.entry?.duration ?? 0) > 0 && root.height >= Tokens.fontCaption * 3
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.spacingXs
        width: durText.implicitWidth + Tokens.spacingSm
        height: durText.implicitHeight + Tokens.spacingXs / 2
        radius: height / 2
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.6)
        StyledText {
            id: durText
            anchors.centerIn: parent
            text: ClockFmt.clock(root.entry?.duration ?? 0)
            variant: "caption"
            color: Colors.of(QsWindow.window).fg
        }
    }
}
