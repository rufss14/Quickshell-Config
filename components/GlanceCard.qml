import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── GlanceCard ────────────────────────────────────────────────────────────────
// A glyph in a tinted disc, a headline, and a line of detail under it.
//
// One shape for every ambient corner fact — weather, uptime, whatever a surface
// wants to state without inviting you to act on it. The first version of these was a
// thin single-row pill and they read as tooltips that had got lost: too small to be
// information and too present to be nothing. A card with a hierarchy inside it reads
// as a widget, which is what they are.
//
// Written inline in LockScreen and lifted here when the greeter needed the same
// shape — see the note in StatCard for why these two surfaces share components while
// the other SysInfo renderings deliberately do not.
Surface {
    id: glance

    property string glyph:    ""
    property string headline: ""
    property string detail:   ""
    property color  tint:     Colors.of(QsWindow.window).primary

    implicitWidth:  glanceRow.implicitWidth + Tokens.spacingLg * 2
    implicitHeight: 62

    elevation:    Tokens.elevationCard
    squareMode:   Config.barShape
    cornerRadius: Tokens.radiusCard
    fillOpacity:  Config.surfaceOpacity

    RowLayout {
        id: glanceRow
        anchors.centerIn: parent
        spacing: Tokens.spacingMd

        Rectangle {
            Layout.preferredWidth:  34
            Layout.preferredHeight: 34
            radius: Tokens.corner(Config.barShape, width / 2)
            color: Colors.of(QsWindow.window).alpha(glance.tint, 0.16)

            MaterialIcon {
                anchors.centerIn: parent
                glyph: glance.glyph
                variant: "title"
                color: glance.tint
            }
        }

        ColumnLayout {
            spacing: 0

            StyledText {
                text: glance.headline
                variant: "body"
                font.bold: true
                color: Colors.of(QsWindow.window).fg
            }
            StyledText {
                visible: glance.detail !== ""
                text: glance.detail
                variant: "caption"
                emphasis: "dim"
            }
        }
    }
}
