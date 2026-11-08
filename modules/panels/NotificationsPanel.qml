pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../notifications"

// ── NotificationsPanel ────────────────────────────────────────────────────────
// The notification centre, beside the sidebar's bell (SidePanelDock) or under the
// bar's (BarPanelDock). A thin host: the body — header, Undo, empty state, the by-app
// list — is NotificationCentre, which the overview's notification card hosts too, so the
// two are one design. This only gives it a width and a height to hug up to the slot.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the list scrolls past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 8
    implicitHeight: Math.min(root.maxHeight, centre.implicitHeight + root.pad * 2)

    NotificationCentre {
        id: centre
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        maxHeight: root.maxHeight - root.pad * 2
    }
}
