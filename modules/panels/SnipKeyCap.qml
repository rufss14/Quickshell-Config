import QtQuick
import Quickshell
import "../../config"
import "../../components"

// ── SnipKeyCap ────────────────────────────────────────────────────────────────
// A key, drawn as a key: "F", "Esc", or an icon (⏎ as `keyboard_return`, a gesture as
// `drag_pan`). The snip tool's hint line and its buttons name their shortcuts with these,
// so a shortcut is something you can see rather than something you were told once.
//
// `onFilled`: the cap sits on a primary-filled button, so it is a wash of the button's own
// text colour, not a tonal plate (which would be unreadable on the fill).
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: cap

    property string text: ""
    property string symbol: ""
    property bool onFilled: false

    readonly property color _fg: cap.onFilled ? Colors.of(QsWindow.window).fgOnPrimary
                                              : Colors.of(QsWindow.window).fgMuted

    implicitHeight: Tokens.iconLg
    implicitWidth: Math.max(cap.implicitHeight, content.implicitWidth + Tokens.spacingMd * 2)
    radius: Tokens.radiusXs + Tokens.spacingXs
    color: cap.onFilled ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimary, 0.18)
                        : Colors.of(QsWindow.window).surfaceHigh
    border.width: cap.onFilled ? 0 : Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.12)

    Item {
        id: content
        anchors.centerIn: parent
        implicitWidth: cap.symbol !== "" ? icon.implicitWidth : label.implicitWidth
        implicitHeight: cap.symbol !== "" ? icon.implicitHeight : label.implicitHeight
        width: implicitWidth
        height: implicitHeight

        MaterialIcon {
            id: icon
            visible: cap.symbol !== ""
            anchors.centerIn: parent
            name: cap.symbol
            font.pixelSize: Tokens.iconMd
            color: cap._fg
        }
        StyledText {
            id: label
            visible: cap.symbol === ""
            anchors.centerIn: parent
            text: cap.text
            variant: "caption"
            font.family: Tokens.fontMono
            font.weight: Font.DemiBold
            color: cap._fg
        }
    }
}
