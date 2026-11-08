import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── TilePill ──────────────────────────────────────────────────────────────────
// The small chip a desktop widget uses for a fact it wants to set apart: a reading under
// a headline figure, a label on a tile. One treatment so the tiles' secondary text reads
// as one family instead of as eight kinds of grey caption.
//
// A soft rectangle at `radiusSm`, never a capsule — the shell's corner table puts rows
// and chips at 8 and reserves full rounds for dots and gauges. Neutral by default: a
// reading is data, and the accent is spent once per region on the thing that is the
// value. `tone: "accent"` is for that one chip; `strong` fills it.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string text: ""
    property string glyph: ""
    // A Material Symbols name, for the icons that have one; `glyph` stays for the rest.
    property string icon: ""
    // Turns the icon (a wind arrow pointing where it blows); springs to a new bearing.
    property real iconRotation: 0
    property color accent: Colors.of(QsWindow.window).primary
    property bool strong: false
    property string tone: "neutral"         // "neutral" | "accent"

    // The accent tone is Material's tonal pair — `primaryContainer` with its own ink —
    // rather than the accent at 16% over whatever the tile is: same hue, but a solid
    // container whose text contrast is guaranteed (PaletteRoles). A widget that passes its
    // own `accent` (an album colour, a per-tile pick) keeps the old wash in that colour.
    readonly property bool _paletteAccent: Qt.colorEqual(root.accent, Colors.of(QsWindow.window).primary)
    readonly property color _ink:
        root.strong ? Colors.of(QsWindow.window).fgOnPrimary
      : root.tone === "neutral" ? Colors.of(QsWindow.window).fg
      : root._paletteAccent ? Colors.of(QsWindow.window).fgOnPrimaryContainer
      : root.accent

    implicitWidth:  row.implicitWidth + Tokens.spacingLg * 2
    implicitHeight: row.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
    color: root.strong ? root.accent
         : root.tone === "neutral" ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
         : root._paletteAccent ? Colors.of(QsWindow.window).primaryContainer
         : Colors.of(QsWindow.window).alpha(root.accent, 0.16)

    Behavior on color { ColorAnimation { duration: Motion.respond } }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingXs

        MaterialIcon {
            visible: root.glyph !== "" || root.icon !== ""
            name: root.icon
            glyph: root.glyph
            variant: "caption"
            color: root._ink
            rotation: root.iconRotation
            Behavior on rotation {
                NumberAnimation {
                    duration: Motion.spatial
                    easing.bezierCurve: Motion.spring
                    easing.type: Easing.BezierSpline
                }
            }
        }
        StyledText {
            text: root.text
            variant: "caption"
            font.bold: true
            color: root._ink
        }
    }
}
