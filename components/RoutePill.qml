import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── RoutePill ─────────────────────────────────────────────────────────────────
// "Playing to <device>", as a pill you can click to change it. The device glyph does
// the heavy lifting for a beginner: "HD-Audio Generic" says nothing about where the
// sound comes out, but a headphone or screen icon does.
//
// Lived inline in SoundPage; the bar's mixer wanted the same control, so it moved here.
// It only reports the click — the caller owns the menu and the move (Audio.moveStream).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: pill

    property var   sink: null
    property color accent: Colors.of(QsWindow.window).primary
    // Just the glyph and chevron — for a row with no room for a name.
    property bool  compact: false
    signal picked()

    implicitHeight: Tokens.pillHeight
    // Its content's width, so it can sit in a row beside other things; in a column with
    // Layout.fillWidth it still hugs (the rectangle below takes the smaller of the two).
    implicitWidth:  pillRow.implicitWidth + Tokens.spacingMd * 2

    Rectangle {
        anchors.left:   parent.left
        anchors.top:    parent.top
        anchors.bottom: parent.bottom
        // Hugs its content instead of stretching the row's full width — a pill that
        // spans the column reads as a text field, not a button.
        width: Math.min(parent.width, pillRow.implicitWidth + Tokens.spacingMd * 2)
        radius: Tokens.radiusPill

        color: pillHover.hovered ? Colors.of(QsWindow.window).alpha(pill.accent, 0.22)
                                 : Colors.of(QsWindow.window).alpha(pill.accent, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(pill.accent, pillHover.hovered ? 0.55 : 0.30)
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        RowLayout {
            id: pillRow
            anchors.fill: parent
            anchors.leftMargin:  Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingSm

            MaterialIcon {
                glyph:  Audio.deviceGlyph(pill.sink)
                color: pill.accent
                variant: "caption"
            }
            StyledText {
                visible: !pill.compact
                Layout.fillWidth: true
                // shortLabelFor, never labelFor: the full description runs to 60
                // characters and would blow the pill apart.
                // "Not connected", not "Default output": a null sink means this
                // stream is linked to no output at all, and naming the default would
                // be a guess dressed up as a fact.
                text: pill.sink ? Audio.shortLabelFor(pill.sink) : "Not connected"
                variant: "caption"
                elide: Text.ElideRight
            }
            MaterialIcon {
                glyph:  "󰅀"                                  // chevron-down
                color: Colors.of(QsWindow.window).fgDim
                variant: "caption"
            }
        }

        HoverHandler { id: pillHover }
        TapHandler { onTapped: pill.picked() }
    }
}
