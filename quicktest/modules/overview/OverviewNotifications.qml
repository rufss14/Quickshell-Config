import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../notifications"

// ── OverviewNotifications ─────────────────────────────────────────────────────
// The notification centre on the overview's second page, bottom-right — a card at the
// same elevation as the calendar and timer.
//
// ── Grouped by app ────────────────────────────────────────────────────────────
// A flat chronological stack made a busy chat app bury everything else. The centre now
// buckets by app (Notifications.historyGroups): each app is a header — its icon, name, a
// count and a per-app clear — with its notifications stacked beneath as the same toast
// cards you see on screen, so the drawer and the toasts speak one visual language.
//
// It sizes to its CONTENT: a couple of notifications makes a couple-of-notifications-tall
// card, and an empty inbox makes a small one. It doesn't stretch to fill the corner.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard
    implicitWidth:  400
    implicitHeight: layout.implicitHeight + Tokens.spacingXl * 2

    // How tall the scrolling list may get before it scrolls instead of growing. The
    // caller can lower it to fit a short corner.
    property int maxListHeight: 460

    ColumnLayout {
        id: layout
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            // Bell in a tinted disc — the bit of colour that stops the header reading flat.
            Rectangle {
                Layout.preferredWidth:  30
                Layout.preferredHeight: 30
                radius: Tokens.radiusSm
                color: Colors.alpha(Colors.focus, 0.16)

                StyledText {
                    anchors.centerIn: parent
                    text: Notifications.dnd ? "󰂛" : "󰂚"
                    color: Colors.focus
                    variant: "title"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: "Notifications"
                    variant: "title"
                    font.bold: true
                }
                StyledText {
                    text: Notifications.dnd ? "Do Not Disturb"
                        : Notifications.count === 0 ? "All caught up"
                        : Notifications.count === 1 ? "1 notification"
                        : Notifications.count + " notifications from "
                          + Notifications.historyGroups.length
                          + (Notifications.historyGroups.length === 1 ? " app" : " apps")
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            // Do Not Disturb — spelled out, not "DND". Filled when on.
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                variant: Notifications.dnd ? "primary" : "normal"
                accent:  Colors.focus
                glyph:   Notifications.dnd ? "󰂛" : "󰂚"
                label:   "Do Not Disturb"
                onActivated: Notifications.toggleDnd()
            }
        }

        Divider {}

        // ── Clear-all toolbar ─────────────────────────────────────────────────
        // The old clear-all was an unlabelled glyph tucked in the header corner — easy to
        // mis-hit and unclear what it did. It's now a labelled, HOLD-to-confirm action in
        // its own row: you press and hold for a beat (a fill sweeps across) to wipe every
        // notification, so a destructive action can't happen on a stray tap. Only shown
        // when there's something to clear.
        RowLayout {
            Layout.fillWidth: true
            visible: Notifications.count > 0
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: Notifications.historyGroups.length
                      + (Notifications.historyGroups.length === 1 ? " app" : " apps")
                variant: "caption"
                emphasis: "dim"
            }

            HoldButton {
                // Set at the call site now that HoldButton is shared — the private
                // version baked this in, which a component used in two layouts can't.
                Layout.alignment: Qt.AlignVCenter
                glyph: "󰃢"                 // broom — sweep it all away
                label: "Clear all"
                busyLabel: "Hold to clear…"
                onConfirmed: Notifications.clearHistory()
            }
        }

        // ── Empty state ───────────────────────────────────────────────────────
        // Compact by design — a couple of lines, so an empty inbox is a small card.
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            visible: Notifications.count === 0
            spacing: Tokens.spacingMd

            StyledText { text: "󰂚"; font.pixelSize: 22; color: Colors.fgDim; opacity: 0.5 }
            StyledText {
                Layout.fillWidth: true
                text: Notifications.dnd
                    ? "Do Not Disturb is on. New notifications wait here quietly."
                    : "No notifications right now."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── The stack, grouped by app ─────────────────────────────────────────
        // preferredHeight (not fillHeight) so the card's own height follows the content:
        // it grows with the groups up to maxListHeight, then the list scrolls inside it.
        ListView {
            id: groupList
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, root.maxListHeight)
            visible: Notifications.count > 0
            clip: true
            spacing: Tokens.spacingLg
            boundsBehavior: Flickable.StopAtBounds
            // Group delegates carry a Repeater of cards, so their heights are only known
            // once realised; a little cache stops a fast scroll flashing blank groups.
            cacheBuffer: 600

            model: Notifications.historyGroups

            delegate: Column {
                id: grp
                required property var modelData      // { app, items, latest }
                width: groupList.width
                spacing: Tokens.spacingSm

                readonly property var  items: grp.modelData.items
                readonly property bool multi: grp.items.length > 1

                // ── Stack, expand on CLICK ────────────────────────────────────
                // A busy app collapses to a PILE: the newest card on top, the rest tucked
                // behind as peeking edges. CLICK the app header to open the pile to the
                // full list — hover was too twitchy, the stack reflowing as the pointer
                // merely crossed it. `expand` is the animated 0→1 that drives the height,
                // so opening and closing glide rather than snap; a single-notif group has
                // nothing to stack, so it's always open.
                property bool open: false
                property real expand: (grp.open || !grp.multi) ? 1 : 0
                Behavior on expand {
                    NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                }

                // ── App header ────────────────────────────────────────────────
                RowLayout {
                    width: grp.width
                    height: implicitHeight
                    spacing: Tokens.spacingSm

                    // Everything but the per-app clear is one CLICK target that toggles the
                    // pile. The clear ✕ sits OUTSIDE it (own MouseArea) so clearing an app
                    // can't also expand it.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        // The app's icon in a faint tile — glyph fallback when it has none.
                        Rectangle {
                            Layout.preferredWidth:  22
                            Layout.preferredHeight: 22
                            radius: Tokens.radiusSm - 2
                            color: Colors.alpha(Colors.fg, 0.06)

                            Image {
                                id: appIco
                                anchors.centerIn: parent
                                width: 16; height: 16
                                source: Notifications.appIconFor(grp.modelData.latest)
                                sourceSize: Qt.size(16, 16)
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                visible: status === Image.Ready
                            }
                            StyledText {
                                anchors.centerIn: parent
                                visible: appIco.status !== Image.Ready
                                text: "󰂚"
                                color: Colors.fgDim
                                font.pixelSize: 13
                            }
                        }

                        StyledText {
                            text: grp.modelData.app
                            variant: "body"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        // Count pill — only worth showing when there's more than one.
                        Rectangle {
                            visible: grp.multi
                            implicitWidth:  Math.max(16, cnt.implicitWidth + Tokens.spacingSm)
                            implicitHeight: 16
                            radius: 8
                            color: Colors.alpha(Colors.focus, 0.16)
                            StyledText {
                                id: cnt
                                anchors.centerIn: parent
                                text: grp.items.length
                                variant: "caption"
                                color: Colors.focus
                            }
                        }

                        // Chevron — the affordance that says "this pile opens". Multi
                        // groups only; points up when open.
                        StyledText {
                            visible: grp.multi
                            text: "󰅀"
                            variant: "caption"
                            color: Colors.fgDim
                            rotation: grp.open ? -180 : 0
                            Behavior on rotation {
                                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Tapping the strip opens/closes the pile. Disabled for single-notif
                        // groups (nothing to stack).
                        TapHandler {
                            enabled: grp.multi
                            onTapped: grp.open = !grp.open
                        }
                    }

                    // Clear just this app's notifications — its own target.
                    PanelButton {
                        Layout.alignment: Qt.AlignVCenter
                        variant: "ghost"
                        glyph: "󰅖"
                        onActivated: Notifications.clearApp(grp.modelData.app)
                    }
                }

                // ── The stack ─────────────────────────────────────────────────
                // Front card is always the newest; the rest are revealed downward as
                // the group expands. Clipped, so the tucked-away cards are hidden by
                // the shrinking height rather than overflowing the group.
                Item {
                    id: stackArea
                    width: grp.width
                    clip: true

                    // How far the pile peeks below the front card when collapsed.
                    readonly property real peek: grp.multi ? 10 : 0
                    // The revealed block below the front card, present only when there
                    // ARE more cards (so a single-notif group adds no phantom spacing).
                    readonly property real restBlock:
                        rest.implicitHeight > 0 ? Tokens.spacingSm + rest.implicitHeight : 0

                    // No Behavior here: height is a pure function of the animated
                    // `expand` and the content's own height. Behaviour-ing it would
                    // chase card images that resize as they load.
                    height: front.height
                          + stackArea.peek * (1 - grp.expand)
                          + stackArea.restBlock * grp.expand

                    // Peeking edges of the cards behind the front one — a cheap "there's
                    // a pile here" cue that fades out as the stack opens.
                    Repeater {
                        model: grp.multi ? Math.min(grp.items.length - 1, 2) : 0

                        Rectangle {
                            required property int index
                            z: -1 - index
                            width: front.width - (index + 1) * 12
                            x: (front.width - width) / 2
                            y: front.height - 3 + (index + 1) * 5 * (1 - grp.expand)
                            height: 16
                            radius: Tokens.radiusSm
                            color: Colors.surfaceFor(Tokens.elevationCard)
                            border.width: Tokens.borderWidth
                            border.color: Colors.outlineBar
                            opacity: (1 - grp.expand) * (0.65 - index * 0.22)
                            visible: opacity > 0.01
                        }
                    }

                    NotificationToast {
                        id: front
                        width: stackArea.width
                        notif: grp.items[0]
                        inCentre: true
                        onDismissed: Notifications.dismiss(grp.items[0])
                    }

                    Column {
                        id: rest
                        width: stackArea.width
                        y: front.height + Tokens.spacingSm
                        spacing: Tokens.spacingSm
                        opacity: grp.expand
                        visible: grp.expand > 0.005

                        Repeater {
                            model: grp.multi ? grp.items.length - 1 : 0

                            NotificationToast {
                                required property int index
                                width: rest.width
                                notif: grp.items[index + 1]
                                inCentre: true
                                onDismissed: Notifications.dismiss(grp.items[index + 1])
                            }
                        }
                    }
                }
            }
        }
    }
}
