import QtQuick
import Quickshell
import "../config"
import "../services"
import "../services"
import "../services/medialinks.js" as Links

// ── MediaLink ─────────────────────────────────────────────────────────────────
// A line of text that is a link when it has somewhere to go (services/medialinks.js says where, and what may be
// opened). Under the pointer it takes the accent and a tooltip says where it goes ("Open in Spotify" or "Open in
// browser"); no underline. Pressing it opens it through the system's handler. Without a link it is plain text.
//
//   base   the colour at rest (the accent takes its place under the pointer)
// ─────────────────────────────────────────────────────────────────────────────
StyledText {
    id: root

    property string link: ""
    property color base: Colors.of(QsWindow.window).fg
    readonly property bool linked: Links.openCommand(root.link).length > 0
    readonly property string where: Links.destinationOf(root.link)

    color: root.linked && hover.hovered ? Colors.of(QsWindow.window).primary : root.base
    Behavior on color { ColorAnimation { duration: Motion.respond } }

    // The indicator: a soft accent pill behind the text, and the accent colour on it. Under the text, so it never covers it.
    Rectangle {
        z: -1
        anchors.fill: parent
        anchors.leftMargin: -Tokens.spacingSm
        anchors.rightMargin: -Tokens.spacingSm
        anchors.topMargin: -Tokens.spacingXs
        anchors.bottomMargin: -Tokens.spacingXs
        radius: height / 2
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.16)
        opacity: root.linked && hover.hovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    HoverHandler { id: hover; enabled: root.linked; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        enabled: root.linked
        onTapped: root.open()
    }
    HoverTip {
        enabled: root.linked
        text: root.where === "app" ? Translation.tr("Open in Spotify") : Translation.tr("Open in browser")
    }

    Accessible.role: root.linked ? Accessible.Link : Accessible.StaticText
    Accessible.name: root.text
    Accessible.onPressAction: if (root.linked) root.open()

    // An app page goes through the extension when Spotify is listening (it navigates the app itself); anything else
    // goes to the system's handler.
    function open() {
        if (root.where === "app" && SpotifyBridge.listening) SpotifyBridge.queueOpen(root.link)
        else Quickshell.execDetached(Links.openCommand(root.link))
    }
}
