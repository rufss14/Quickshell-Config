import QtQuick
import Quickshell
import QtQuick.Effects
import Quickshell.Widgets
import Quickshell.Services.SystemTray
import "../../../config"
import "../../../components"
import "../../../state"

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
    property color accent: Colors.of(QsWindow.window).primary

    // Bar.qml's own BarContextMenu instance — lives in the bar's window so it can
    // weld into the blob, and is shared by every tray entry (only one menu can be
    // open at a time anyway). See BarContextMenu.qml.
    property var contextMenu: null

    readonly property int itemCount: SystemTray.items.values.length

    // One entry's width, defined once because TWO things need it: the pill's own width,
    // and the entries inside it. They were both spelling `26` — so the moment the icon
    // scale moved the entries, the pill would have been sized for icons it no longer had.
    readonly property int entryWidth: Math.round(26 * Config.barIconScale)

    // The group's spacing override (module inspector) — see Config.groupSpacing.
    // -1 (unset) keeps the original tokens; set, half of it becomes this pill's
    // own edge padding, matching how every other member of the group divides it.
    readonly property int groupSpacing: Config.groupSpacing("tray")
    readonly property int  entrySpacing: root.groupSpacing >= 0 ? Tokens.spacingXs : Tokens.spacingSm
    readonly property int  edgePad:      root.groupSpacing >= 0
        ? Math.round(root.groupSpacing / 2) : Tokens.spacingMd

    implicitWidth:  itemCount * root.entryWidth
                  + Math.max(0, itemCount - 1) * root.entrySpacing
                  + root.edgePad * 2
    implicitHeight: Config.barPillHeight

    Row {
        anchors.centerIn: parent
        spacing: root.entrySpacing

        Repeater {
            model: SystemTray.items

            Item {
                id: entry
                required property var modelData
                readonly property var sni: modelData

                // The icon leans a pixel toward the pointer, as the bar's buttons do (MagnetLean).
                MagnetLean {
                    id: magnet
                    active: hit.containsMouse
                    pointerX: hit.mouseX
                    pointerY: hit.mouseY
                    extentW: entry.width
                    extentH: entry.height
                }

                // Follows the icon scale, like everything else the bar draws as an icon —
                // a tray of app icons that ignored the Icon size slider would be the one
                // part of the bar that didn't. Shared with implicitWidth above.
                width:  root.entryWidth
                height: Config.barPillHeight

                // Tray items appear and disappear at runtime, so they animate in
                // rather than popping.
                opacity: 0.0
                scale:   0.5
                Component.onCompleted: entryAnim.start()

                ParallelAnimation {
                    id: entryAnim
                    NumberAnimation { target: entry; property: "opacity"; to: 1; duration: Motion.fast;     easing.type: Motion.enter }
                    NumberAnimation { target: entry; property: "scale";   to: 1; duration: Motion.standard; easing.type: Motion.overshoot }
                }

                // The bar's own plate (2026-10-31): a small rounded square with a flat hover
                // used to sit here, a different shape and a different ladder from every other
                // button in the same inner pill. CellFeedback is that ladder — concentric with
                // the pill, growing and stretching along the bar (`alongY: false`), the ripple.
                CellFeedback {
                    id: feedback
                    anchors.fill: parent
                    alongY: false
                    hovered: hit.containsMouse
                    accent: root.accent
                    pointerX: hit.mouseX
                    pointerY: hit.mouseY
                }

                IconImage {
                    id: appIcon
                    anchors.centerIn: parent
                    implicitSize: Math.round(Tokens.iconMd * Config.barIconScale)
                    source:  entry.sni?.icon ?? ""
                    visible: source !== ""
                    scale: feedback.lift
                    transform: Translate { x: magnet.offsetX; y: magnet.offsetY }

                    // Off by default — layer.enabled costs an offscreen texture and a
                    // shader pass per icon, so a tray left in its native colours (the
                    // common case) pays nothing for a toggle it doesn't use.
                    layer.enabled: Config.colorizeIcons
                    layer.effect: MultiEffect {
                        colorization:      1.0
                        colorizationColor: root.accent
                    }
                }

                // Placeholder for an item that ships no icon at all.
                Rectangle {
                    anchors.centerIn: parent
                    width:   Math.round(Tokens.iconMd * Config.barIconScale)
                    height:  Math.round(Tokens.iconMd * Config.barIconScale)
                    visible: !appIcon.visible
                    transform: Translate { x: magnet.offsetX; y: magnet.offsetY }
                    radius:  Tokens.corner(Config.barShape, Tokens.radiusXs)
                    color:   Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).info, 0.28)
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

                    // ── Attention pulse, category 3 (see Motion.qml) ──────────
                    // `status === 2` is NeedsAttention — the item is asking to be
                    // looked at, and the blink is the entire channel that request
                    // has. Not gated on motionEnabled for the same reason the
                    // spinners aren't: turning animations off should quieten the
                    // shell, not suppress a notification.
                    //
                    // `Motion.pulse` — exempt from the animations toggle, so the
                    // dot keeps asking. It was a bespoke 600ms literal; the token is
                    // 400, which is the shell's one breathing rate. A widget should
                    // not carry a tempo of its own.
                    SequentialAnimation on opacity {
                        running: entry.sni?.status === 2
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.2; duration: Motion.pulse; easing.type: Motion.ambient }
                        NumberAnimation { to: 1.0; duration: Motion.pulse; easing.type: Motion.ambient }
                    }
                }

                MouseArea {
                    id: hit
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    // ── Press: the ripple and the plate's stretch ─────────────
                    // Was a scale bounce (0.82, then 1.10, then back), the one press in
                    // the bar that shrank the whole icon — the "thud" IconButton keeps
                    // out. The plate answers now, as every other button's does.
                    onPressed:  function(m) { feedback.press(m.x, m.y) }
                    onReleased: feedback.release()
                    onCanceled: feedback.release()

                    onClicked: function(m) {
                        if (m.button === Qt.MiddleButton)     entry.sni?.secondaryActivate()
                        else if (m.button === Qt.RightButton) root.contextMenu?.open(entry.sni?.menu, entry)
                        else                                  entry.sni?.activate()
                    }
                }
            }
        }
    }
}
