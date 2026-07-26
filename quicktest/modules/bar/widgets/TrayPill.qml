import QtQuick
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../../config"
import "../../../components"
import "../../../state"
import "../../panels" as P

// ── TrayPill ──────────────────────────────────────────────────────────────────
// System tray icons. Left-click activates, middle-click secondary-activates,
// right-click opens the item's DBus menu.
//
// The tray no longer draws its own pill — its group provides one, like every
// other bar widget now.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.primary

    property var parentWindow: null

    readonly property int itemCount: SystemTray.items.values.length

    // One entry's width, defined once because TWO things need it: the pill's own width,
    // and the entries inside it. They were both spelling `26` — so the moment the icon
    // scale moved the entries, the pill would have been sized for icons it no longer had.
    readonly property int entryWidth: Math.round(26 * Config.barIconScale)

    implicitWidth:  itemCount * root.entryWidth
                  + Math.max(0, itemCount - 1) * Tokens.spacingSm
                  + Tokens.spacingMd * 2
    implicitHeight: Tokens.pillHeight

    // The tray gets the same inset pill as every other bar control.
    Surface {
        anchors.fill: parent
        elevation:    Tokens.elevationNested
        squareMode:   Config.barShape
        cornerRadius: Config.barRoundness
    }

    P.TrayMenu {
        id: trayMenu
        barShape:     Config.barShape
        parentWindow: root.parentWindow
    }

    Row {
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        Repeater {
            model: SystemTray.items

            Item {
                id: entry
                required property var modelData
                readonly property var sni: modelData

                // Follows the icon scale, like everything else the bar draws as an icon —
                // a tray of app icons that ignored the Icon size slider would be the one
                // part of the bar that didn't. Shared with implicitWidth above.
                width:  root.entryWidth
                height: Tokens.pillHeight

                // Tray items appear and disappear at runtime, so they animate in
                // rather than popping.
                opacity: 0.0
                scale:   0.5
                Component.onCompleted: entryAnim.start()

                ParallelAnimation {
                    id: entryAnim
                    NumberAnimation { target: entry; property: "opacity"; to: 1; duration: Motion.fast;     easing.type: Motion.enter }
                    NumberAnimation { target: entry; property: "scale";   to: 1; duration: Motion.standard; easing.type: Easing.OutBack }
                }

                Rectangle {
                    anchors.centerIn: parent
                    width:  Math.round(22 * Config.barIconScale)
                    height: Math.round(22 * Config.barIconScale)
                    radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                    color:  hit.containsMouse ? Colors.stateHoverBg : "transparent"
                    Behavior on color  { ColorAnimation  { duration: Motion.respond } }
                    Behavior on radius { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                }

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    implicitSize: Math.round(Tokens.iconMd * Config.barIconScale)
                    source:  entry.sni?.icon ?? ""
                    visible: source !== ""
                }

                // Placeholder for an item that ships no icon at all.
                Rectangle {
                    anchors.centerIn: parent
                    width:   Math.round(Tokens.iconMd * Config.barIconScale)
                    height:  Math.round(Tokens.iconMd * Config.barIconScale)
                    visible: !appIcon.visible
                    radius:  Tokens.corner(Config.barShape, Tokens.radiusXs)
                    color:   Colors.alpha(Colors.info, 0.28)
                }

                // "Needs attention" — the SNI status the spec defines for an app
                // asking to be looked at.
                Rectangle {
                    visible: entry.sni?.status === 2
                    width:  5
                    height: 5
                    radius: 2.5
                    color:  root.accent
                    anchors.bottom: parent.bottom
                    anchors.right:  parent.right
                    anchors.margins: 1

                    SequentialAnimation on opacity {
                        running: entry.sni?.status === 2
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                        NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InOutSine }
                    }
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onPressed:  entry.scale = 0.82
                    onReleased: bounce.restart()

                    SequentialAnimation {
                        id: bounce
                        NumberAnimation { target: entry; property: "scale"; to: 1.10; duration: 70;  easing.type: Easing.OutQuad }
                        NumberAnimation { target: entry; property: "scale"; to: 1.00; duration: 110; easing.type: Easing.InOutQuad }
                    }

                    onClicked: function(m) {
                        if (m.button === Qt.MiddleButton)     entry.sni?.secondaryActivate()
                        else if (m.button === Qt.RightButton) trayMenu.open(entry.sni?.menu, entry)
                        else                                  entry.sni?.activate()
                    }
                }
            }
        }
    }
}
