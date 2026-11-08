import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── WidgetHeader ──────────────────────────────────────────────────────────────
// The top strip of a desktop widget: an accent glyph, a bold title, and an
// optional slot on the right for a live stat or a control.
//
// Eight widgets each hand-rolled this — the same RowLayout, disagreeing on
// whether the title was bold or dim, whether it took the accent or the
// foreground, and which glyph size. It's the PanelHeader story one tile down:
// one treatment, declared once, so every widget's head reads the same.
//
// The right slot is a `default` alias, so a caller writes its trailing content
// as a plain child — `WidgetHeader { glyph: "…"; title: "…"; StyledText {…} }`.
// ─────────────────────────────────────────────────────────────────────────────
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// The glyph sits on a SHAPE, not a flat tinted disc: a tonal container
// (primaryContainer, or a mix toward the tile's own accent) cut to one of the M3E
// shapes, `shape` per widget, so a desktop of headers reads as one family of forms
// instead of a row of identical dots. `icon` takes a Material Symbols name; `glyph`
// stays for the Nerd glyphs older callers pass.
RowLayout {
    id: root

    property string glyph: ""
    property string icon: ""
    property string title: ""
    property string shape: "cookie7"
    property color accent: Colors.of(QsWindow.window).primary

    default property alias trailing: trail.data

    // The palette's own accent gets Material's tonal pair; a per-tile accent gets a
    // container mixed toward it, with the accent itself as the ink.
    readonly property bool _paletteAccent: Qt.colorEqual(root.accent, Colors.of(QsWindow.window).primary)
    readonly property color _container: root._paletteAccent
        ? Colors.of(QsWindow.window).primaryContainer
        : Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.26)
    readonly property color _ink: root._paletteAccent
        ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.accent

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingSm

    Item {
        visible: root.glyph !== "" || root.icon !== ""
        Layout.alignment: Qt.AlignVCenter
        implicitWidth:  Tokens.iconLg + Tokens.spacingMd
        implicitHeight: implicitWidth

        MorphShape {
            anchors.fill: parent
            shape: Config.barShape ? "squircle" : root.shape
            fillColor: root._container
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: root.icon
            glyph: root.glyph
            variant: "caption"
            color: root._ink
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.title
        variant: "label"
        font.weight: Font.DemiBold
        color: Colors.of(QsWindow.window).fg
        elide: Text.ElideRight
    }

    RowLayout {
        id: trail
        Layout.alignment: Qt.AlignVCenter
        spacing: Tokens.spacingXs
    }
}
