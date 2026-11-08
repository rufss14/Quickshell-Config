import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── WindowPill ────────────────────────────────────────────────────────────────
// The window this screen is about (services/ActiveWindow, per monitor): the app's own
// icon and its title, elided. An empty workspace says so instead of disappearing, so
// the bar doesn't shift every time you switch to one. Click: its panel (WindowPanel).
//
// The icon is drawn as-is, not tinted: it is the app's identity, the one thing that
// makes the title findable at a glance.
// ─────────────────────────────────────────────────────────────────────────────
BarIconPill {
    id: root

    property string monitorName: ""
    readonly property var win: ActiveWindow.byMonitor[root.monitorName] ?? null
    readonly property int maxTitle: Math.round(260 * Config.barFontScale)

    moduleId: "window"
    implicitWidth: Math.ceil(row.implicitWidth) + Tokens.pillPadding * 2

    // ── Focus moving animates; a title changing does not ──────────────────────
    // `shown` is the window the row DRAWS, held back from `win` so the old one can
    // finish fading out first (see SwapFade). A terminal or a browser tab rewrites its
    // title every second or so, and each of those fading would never settle — so only
    // a change of WINDOW (its address) swaps; the same window updates in place. The
    // pill's width follows the row 1:1, with no Behavior of its own (Motion.qml's
    // rule), and changes at the midpoint while the row is at opacity 0.
    readonly property string winKey: root.win ? root.win.address : ""
    property var shown: null
    Component.onCompleted: root.shown = root.win
    // Same window: update in place (also during the fade-in). A different one waits for
    // SwapFade's midpoint.
    onWinChanged: if (root.winKey === (root.shown ? root.shown.address : "")) root.shown = root.win

    SwapFade {
        id: swap
        target:   row
        key:      root.winKey
        shownKey: root.shown ? root.shown.address : ""
        onSwapped: root.shown = root.win
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        Image {
            Layout.alignment: Qt.AlignVCenter
            visible: !!(root.shown && root.shown.icon)
            source: root.shown && root.shown.icon ? root.shown.icon : ""
            sourceSize: Qt.size(root.iconSize, root.iconSize)
            Layout.preferredWidth: root.iconSize
            Layout.preferredHeight: root.iconSize
            fillMode: Image.PreserveAspectFit
            smooth: true
            asynchronous: true
        }
        MaterialIcon {
            visible: !(root.shown && root.shown.icon)
            name: root.shown ? "window" : "desktop_mac"
            color: root.iconColor
            font.pixelSize: root.iconSize
        }
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: root.maxTitle
            text: root.shown ? (root.shown.title || root.shown.name) : "Desktop"
            color: root.iconColor
            font.family: Tokens.fontFamily
            font.pixelSize: root.labelSize
            // BarLabel's weight (the bar's one label style); a layout child, so a plain Text.
            font.weight: Font.Medium
            elide: Text.ElideRight
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }
}
