pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── NotificationGroups ────────────────────────────────────────────────────────
// The notification history grouped by app (Notifications.historyGroups): each app a
// slim header — its icon, name, count and a clear — over its notifications as flat
// NotificationRows. A busy app shows its newest `collapseAt` and a "N more" to open
// the rest. The notification centre (NotificationCentre: the bar/sidebar panel and the
// overview) and the lock screen's (OverviewNotifications) draw this one list. The
// caller sizes it: height = min(contentHeight, its ceiling), so it grows, then scrolls.
//
// ── Tiles, headed by the app ──────────────────────────────────────────────────
// Each notification is a tile (NotificationRow: the app's icon in a cookie, tinted by the
// app), under a slim label — the app's name, its count and, under the pointer, a Clear chip on
// a HoverTray. "N more" is a ChipTray pill. The groups arrive as a PopIn cascade, ONCE: it
// plays for what exists when the list opens, and a group made later (an arrival rebuilds the
// model) is simply there — otherwise every notification would replay the whole page.
//
// ─────────────────────────────────────────────────────────────────────────────
ListView {
    id: groupList

    // false on the lock screen: rows don't run actions, open links or start apps.
    property bool actionable: true
    // Records newer than this get the "new" dot. The panel passes the seenAt it
    // opened with (it marks everything seen as it opens); the default is the live one.
    property real newSince: Notifications.seenAt
    // A busy app shows this many until it's opened.
    property int collapseAt: 2
    // Groups a mute chip makes sense on: apps, not the by-day layout's sections.
    property bool muteable: false
    // Select mode (NotificationCentre): tiles tick instead of acting; `selected` is key → true.
    property bool selecting: false
    property var  selected: ({})
    signal toggled(var rec)
    // The centre's accent: the new-dot, the actions, the chips.
    property color accent: Colors.of(QsWindow.window).primary
    // The cards' entrance — opt-in, so the lock screen's list (which never opens) just shows.
    // `opened` is the host saying it is on screen (NotificationCentre, a beat after it is
    // built): the cascade plays when it turns true, held back by `lead` for a dock's own
    // opening pause. `settled` follows once the cascade has had its time, and from then on a
    // card that appears is just there.
    property bool cascade: false
    property bool opened: false
    property int  lead: Motion.emphasized
    property bool settled: false
    Timer {
        running: groupList.cascade && groupList.opened
        interval: groupList.lead + Motion.emphasized + Motion.stagger * 15
        onTriggered: groupList.settled = true
    }

    // Records the list removed (a row's ✕, an app's clear) — for the host's Undo.
    signal cleared(var recs)

    // App name → true while opened past `collapseAt`. Assigned, never mutated.
    property var openApps: ({})
    function _setOpen(app, on) {
        const next = {}
        for (const k in groupList.openApps) if (k !== app) next[k] = true
        if (on) next[app] = true
        groupList.openApps = next
    }

    clip: true
    // Wider between apps than between tiles, so a label belongs to the tiles BELOW it.
    spacing: Tokens.spacingXl
    boundsBehavior: Flickable.StopAtBounds
    // Group delegates carry a Repeater of rows, so their heights are only known once
    // realised; a little cache stops a fast scroll flashing blank groups.
    cacheBuffer: Tokens.sideCardUnit * 10

    // By app, as the lock screen has it; NotificationCentre sets its own (filtered, or by day).
    model: Notifications.historyGroups

    delegate: Item {
        id: grp
        required property int index
        required property var modelData      // { app, items, latest }
        width: groupList.width
        height: col.implicitHeight

        readonly property var  items: grp.modelData.items
        readonly property bool open: groupList.openApps[grp.modelData.app] === true
        readonly property int  hiddenCount:
            grp.open ? 0 : Math.max(0, grp.items.length - groupList.collapseAt)

        // Groups that exist when the list opens cascade in; one made later is simply there.
        property bool late: false
        Component.onCompleted: grp.late = groupList.settled
        readonly property bool arriving: groupList.cascade && !grp.late
        PopIn { id: pop; active: groupList.opened && grp.arriving; index: grp.index; delay: groupList.lead }
        opacity: grp.arriving ? pop.opacity : 1
        scale:   grp.arriving ? pop.scale : 1

        readonly property bool muted: groupList.muteable && Notifications.isMuted(grp.modelData.app)

        HoverHandler { id: grpHover }

        ColumnLayout {
            id: col
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.top:   parent.top
            spacing: Tokens.spacingSm

            // ── The app ───────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                // In line with the cookies' left edge (a tile's own padding), not the tile's.
                Layout.leftMargin: Tokens.spacingMd
                // Near the Clear chip's height, so it arriving moves little; the chip overhangs a
                // couple of px rather than the label floating a whole row above its tiles.
                Layout.preferredHeight: Tokens.iconLg + Tokens.spacingMd
                spacing: Tokens.spacingSm

                // The app's name, then how many as a small tonal count — a label to read, not a dim aside.
                StyledText {
                    text: grp.modelData.app
                    variant: "body"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    Layout.maximumWidth: groupList.width * 0.6
                }
                Rectangle {
                    visible: grp.items.length > 1
                    implicitWidth: countText.implicitWidth + Tokens.spacingMd
                    implicitHeight: countText.implicitHeight + Tokens.spacingXs
                    radius: height / 2
                    color: Colors.of(QsWindow.window).primaryContainer
                    StyledText {
                        id: countText
                        anchors.centerIn: parent
                        text: String(grp.items.length)
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                    }
                }
                Item { Layout.fillWidth: true }
                // A muted app says so — its notifications land here without a toast.
                MaterialIcon {
                    visible: grp.muted
                    name: "volume_off"
                    font.pixelSize: Tokens.iconSm
                    color: Colors.of(QsWindow.window).fgDim
                }

                // Mute and Clear — under the pointer only, like a tile's chips. Clear takes what the
                // group shows (a search narrows it), not every record the app has.
                HoverTray {
                    Layout.alignment: Qt.AlignVCenter
                    shown: grpHover.hovered && !groupList.selecting
                    ChipButton {
                        visible: groupList.muteable
                        symbol:  "volume_off"
                        on:      grp.muted
                        tint:    groupList.accent
                        onActivated: Notifications.toggleMute(grp.modelData.app)
                    }
                    ChipButton {
                        symbol: "close"
                        label:  grp.items.length > 1 ? "Clear" : ""
                        tint:   Colors.of(QsWindow.window).danger
                        onActivated: groupList.cleared(Notifications.clearRecs(grp.items))
                    }
                }
            }

            // ── Its notifications, newest first ───────────────────────────────
            Repeater {
                model: grp.items.slice(0, grp.items.length - grp.hiddenCount)

                NotificationRow {
                    required property var modelData
                    Layout.fillWidth: true
                    rec:        modelData
                    actionable: groupList.actionable
                    accent:     groupList.accent
                    fresh:      modelData.time > groupList.newSince
                    selecting:  groupList.selecting
                    selected:   groupList.selected[modelData.key] === true
                    onToggled:  groupList.toggled(modelData)
                    onDismissed: groupList.cleared([modelData])
                }
            }

            // ── More / less ───────────────────────────────────────────────────
            // A quiet link, not a pill: an off ChipButton is just its icon and words (a wash under the
            // pointer), which is all "N more" should weigh.
            ChipButton {
                Layout.alignment: Qt.AlignLeft
                Layout.leftMargin: Tokens.spacingXs
                visible: grp.items.length > groupList.collapseAt
                symbol: grp.open ? "expand_less" : "expand_more"
                label:  grp.open ? "Show less" : grp.hiddenCount + " more"
                tint:   groupList.accent
                onActivated: groupList._setOpen(grp.modelData.app, !grp.open)
            }
        }
    }
}
