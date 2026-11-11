pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SideNotifications ─────────────────────────────────────────────────────────
// The notification centre as a sidebar button: a bell, with a dot while anything
// arrived since you last opened its panel (Notifications.unseen), and the centre
// itself in a panel beside it (NotificationsPanel, in SidePanelDock).
//
//   click     the panel, beside this button (again: shut it)
//   middle    Do Not Disturb
//   right     Settings › Sidebar
//
// The bell wears the top bar's bell states: bell-off in the warning tint while quiet
// (DND or a hold, e.g. gamemode), danger while something critical is up. A dot says
// something arrived since you last looked (never "how many in total"); a new
// arrival swings the bell and bumps the dot.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Along the edge: a column on a side, a row along the bottom (SideGroupHost).
    property bool vertical: true
    // The screen this sidebar is on: its panel opens here.
    property var screen: null

    readonly property bool ownsPanel: UiState.sidePanelScreen
        ? UiState.sidePanelScreen === root.screen : root.screen === Quickshell.screens[0]
    readonly property bool open: UiState.sidePanel === "notifications" && root.ownsPanel

    implicitWidth:  Config.sidebarCell
    implicitHeight: Config.sidebarCell

    // ── The swing ─────────────────────────────────────────────────────────────
    // Only when the count goes UP (a dismissal or markSeen lowers it).
    // Set once, then by the handler — a binding would already hold the new count
    // by the time the handler compares against it.
    property int _lastUnseen: 0
    Component.onCompleted: root._lastUnseen = Notifications.unseen
    Connections {
        target: Notifications
        function onUnseenChanged() {
            if (Notifications.unseen > root._lastUnseen && !root.open) {
                swingAnim.restart()
                if (root._lastUnseen > 0) bumpAnim.restart()
            }
            root._lastUnseen = Notifications.unseen
        }
    }
    property real swing: 0
    SequentialAnimation {
        id: swingAnim
        NumberAnimation { target: root; property: "swing"; to: 18;  duration: Motion.fast;     easing.type: Motion.respondCurve }
        NumberAnimation { target: root; property: "swing"; to: -14; duration: Motion.standard; easing.type: Motion.inOut }
        NumberAnimation { target: root; property: "swing"; to: 8;   duration: Motion.standard; easing.type: Motion.inOut }
        NumberAnimation { target: root; property: "swing"; to: 0;   duration: Motion.slow;     easing.type: Easing.OutElastic }
    }

    SideCell {

        moduleId: "notifications"
        anchors.fill: parent
        // The bar pill's four states and colours (Bar.qml notificationsC): same face on
        // both surfaces (2026-11-08).
        symbol: Notifications.quiet       ? "bedtime"
              : Notifications.hasCritical ? "notifications_active"
              : Notifications.count > 0   ? "notifications_unread"
              :                             "notifications"
        tint:   Notifications.quiet       ? Colors.of(QsWindow.window).warning
              : Notifications.hasCritical ? Colors.of(QsWindow.window).danger
              : Notifications.count > 0   ? Colors.of(QsWindow.window).info
              :                             Colors.of(QsWindow.window).stateIdleFg
        active: root.open
        glyphAngle: root.swing

        onClicked:       UiState.toggleSidePanel("notifications", "notifications", root.screen)
        onMiddleClicked: Notifications.toggleDnd()
        onRightClicked:  UiState.openSettingsTo("SidebarPage.qml")
    }

    // ── New since you looked ──────────────────────────────────────────────────
    // A dot, not a count (the user's pick, 2026-10-02: "9+" hanging off the corner
    // read clumsy; the panel says how many). Pops in on the spring and bumps when
    // more arrive.
    Rectangle {
        id: dot
        readonly property bool shown: Notifications.unseen > 0 && !root.open
        readonly property int size: Tokens.spacingSm * 2

        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.margins: Config.sidebarCellPad
        width:  dot.size
        height: dot.size
        radius: dot.size / 2
        color:  Colors.of(QsWindow.window).primary

        scale: dot.shown ? 1 : 0
        visible: dot.scale > 0.01
        // Its own transform, so the pop's Behavior doesn't smooth the bump away.
        property real bump: 1
        transform: Scale {
            origin.x: dot.width / 2
            origin.y: dot.height / 2
            xScale: dot.bump
            yScale: dot.bump
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.standard; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
        SequentialAnimation {
            id: bumpAnim
            NumberAnimation { target: dot; property: "bump"; to: 1.4
                              duration: Motion.fast; easing.type: Motion.enter }
            NumberAnimation { target: dot; property: "bump"; to: 1
                              duration: Motion.standard; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
    }
}
