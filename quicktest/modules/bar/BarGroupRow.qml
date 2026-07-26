pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// ── BarGroupRow ───────────────────────────────────────────────────────────────
// Walks one region of Config.layout and builds its groups. Everything structural
// about rendering a layout lives here: which group draws a divider, which one is at a
// screen edge and may not overflow it, and how a group's modules become widgets.
//
// It exists because there are now TWO things that render the bar — the bar, and the
// settings page's preview of it — and the second one must not be an approximation of
// the first. A preview drawn by different code is a preview that drifts: it'd keep
// showing dividers where the bar stopped drawing them, and you'd trust it right up
// until it lied.
//
// The callers differ only in what a module DOES, never in how the layout is shaped.
// So the shape is here, and the behaviour arrives as functions:
//
//   componentFor(id)     → the Component to build for a module. Required.
//   groupExpanded(ids)   → is a panel launched from this group open? (bar only)
//   moduleVisible(id)    → may this module hide itself? (the tray, when empty)
//   slotsClickable       → preview mode: widgets go inert, slots emit slotClicked
//
// The two optional ones default to "no" and "yes", which is exactly right for a
// preview: nothing in it owns a panel, and nothing in it should vanish — a preview
// that hides the tray because your real tray is empty is showing you a bar you can't
// reconcile with the chips you just dragged.
// ─────────────────────────────────────────────────────────────────────────────
Repeater {
    id: root

    required property string region

    property var componentFor:  null
    property var groupExpanded: null
    property var moduleVisible: null

    // ── Preview mode ──────────────────────────────────────────────────────────
    // On: each slot's widget is DISABLED and an overlay above it reports clicks
    // through `slotClicked`. Off (the bar): the widget is live and the overlay is dead.
    //
    // The two must swap together, and that's the point of doing it here rather than in
    // the preview. Leaving the widgets enabled would mean right-clicking the preview's
    // visualizer ran the real handler and swapped the real spectrum for media controls —
    // the actual behaviour, fired at a copy. And the obvious alternative, an
    // `enabled: false` wrapper with a separate hit-layer floating over the top, can't
    // work: positioning that layer needs mapToItem, and mapToItem inside a binding never
    // re-evaluates — its position reads happen in C++ and don't notify. It would track
    // the layout exactly once and then silently stop.
    property bool slotsClickable: false

    signal slotClicked(string id)

    // How far the region's edge-most group may extend past the screen edge on hover.
    // 9999 = unlimited, i.e. nothing is at an edge on that side.
    property int roomLeft:  9999
    property int roomRight: 9999

    model: Config.layout[root.region] ?? []

    BarGroup {
        id: barGroup
        required property int index
        required property var modelData          // the group: an array of module ids

        // Whether anything in this group wants to be on the bar right now. BarGroup
        // owns the actual show/hide, animating a collapse rather than popping — a
        // self-hiding module (the DND bell, the empty tray) is its own single-module
        // group, so the group IS the unit that appears and disappears.
        shown: {
            if (!root.moduleVisible) return true
            for (const id of barGroup.modelData) if (root.moduleVisible(id)) return true
            return false
        }

        // Every group but the first. No "is anything visible ahead of me" walk any
        // more — Config prunes empty groups, so a group in the layout has modules in it
        // by construction.
        showDivider: barGroup.index > 0

        forceExpanded: root.groupExpanded ? root.groupExpanded(barGroup.modelData) : false

        outerRoomLeft:  barGroup.index === 0 ? root.roomLeft : 9999
        outerRoomRight: barGroup.index === root.count - 1 ? root.roomRight : 9999

        Repeater {
            model: barGroup.modelData

            Item {
                id: slot
                required property string modelData

                visible: root.moduleVisible ? root.moduleVisible(slot.modelData) : true

                implicitWidth:  widget.implicitWidth
                implicitHeight: widget.implicitHeight

                Loader {
                    id: widget
                    anchors.centerIn: parent
                    // Item.enabled propagates to the loaded widget and every MouseArea
                    // inside it. This one line is what makes a preview a preview.
                    enabled: !root.slotsClickable
                    sourceComponent: root.componentFor ? root.componentFor(slot.modelData) : null
                }

                // Dead on the real bar, so it can't intercept a click meant for the
                // widget underneath. A disabled MouseArea is transparent to input.
                MouseArea {
                    id: slotHit
                    anchors.fill: parent
                    enabled: root.slotsClickable
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.slotClicked(slot.modelData)
                }

                // Hover ring — otherwise there's nothing to suggest the preview
                // responds to a pointer at all.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -1
                    radius: Config.barRoundness
                    color: "transparent"
                    border.width: 1
                    border.color: Colors.outlineFocus
                    opacity: slotHit.containsMouse ? 1 : 0
                    visible: opacity > 0.005
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
            }
        }
    }
}
