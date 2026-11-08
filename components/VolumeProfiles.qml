pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"

// ── VolumeProfiles ────────────────────────────────────────────────────────────
// Named volume levels — soft, medium, max, boost — in the pill-and-spring language of
// SegmentSwitch, for a panel whose volume bar has been folded away. Boost is the one that
// reaches past 100% (it lifts the general volume, volumeprofiles.js), which is why it wears the
// palette's warning colour instead of the accent: it is louder than everything else on the
// machine, and it should look like it.
//
// ── Dumb on purpose ───────────────────────────────────────────────────────────
// The names, levels and which one is lit all come from outside (services/volumeprofiles.js
// and Audio.volumeProfileOf): the lit one is DERIVED from the real volumes, never stored, so a
// level changed elsewhere — the player's own slider, a hardware key, a device that caps
// boost — shows what is true rather than what was last clicked here. This only draws it and
// says which was tapped.
//
// ── Only the chosen segment spells its name ───────────────────────────────────
// The strip is a few dozen pixels wide per segment; four labels do not fit, so the chosen one
// takes a larger share (its icon and label) and the rest shrink to an icon, on springs, so
// the pill reads as one object that re-shapes around the choice.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // [{ label, icon, boost }] — volumeprofiles.js PROFILES.
    property var   profiles: []
    // The lit one (an index), or -1.
    property int   current:  -1
    property color accent:   Colors.of(QsWindow.window).primary

    // A tap of the left button, and of the right one — a profile may mean something different
    // by each (the boost: left unlocks the bar, right unlocks it AND sets it).
    signal picked(int index)
    signal alternated(int index)

    implicitHeight: Tokens.iconXl + Tokens.spacingSm

    readonly property int pad: Tokens.spacingXs * 2
    // The chosen segment's share, against 1 for each of the others; with none chosen they
    // are all equal and icon-only.
    readonly property real chosenWeight: 2.6
    readonly property real _unit: (root.width - root.pad * 2)
        / Math.max(1, root.profiles.length - 1 + (root.current >= 0 ? root.chosenWeight : 1))

    // The colour under the chosen segment: the accent, or the warning for the boost profile.
    function tintOf(i) {
        return root.profiles[i].boost ? Colors.of(QsWindow.window).warning : root.accent
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.of(QsWindow.window).surfaceContainer
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
    }

    // ── The indicator rides the chosen segment ────────────────────────────────
    // Bound to that segment's own (animated) geometry, so it needs no spring of its own.
    Rectangle {
        id: indicator
        // `count` so it is looked up again once the delegates exist (itemAt alone isn't a binding).
        readonly property var seg: reps.count > 0 && root.current >= 0 ? reps.itemAt(root.current) : null
        y: root.pad
        height: root.height - root.pad * 2
        radius: height / 2
        x:     indicator.seg ? row.x + indicator.seg.x : row.x
        width: indicator.seg ? indicator.seg.width : 0
        color: root.current >= 0 ? root.tintOf(root.current) : root.accent
        opacity: root.current >= 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        Behavior on color   { ColorAnimation  { duration: Motion.standard } }
    }

    Row {
        id: row
        x: root.pad
        y: root.pad
        height: root.height - root.pad * 2

        Repeater {
            id: reps
            model: root.profiles

            delegate: Item {
                id: seg
                required property int index
                required property var modelData

                readonly property bool on: root.current === seg.index

                height: row.height
                width:  root._unit * (seg.on ? root.chosenWeight : 1)
                Behavior on width { SpringAnimation { spring: 4.5; damping: 0.55; epsilon: 0.2 } }
                clip: true

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                    opacity: !seg.on && hover.hovered ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: seg.modelData.icon
                        fill: seg.on ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: seg.on ? Colors.of(QsWindow.window).fgOnPrimary
                             : hover.hovered ? Colors.of(QsWindow.window).fg
                             :                 Colors.of(QsWindow.window).fgMuted
                        Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                        Behavior on color { ColorAnimation  { duration: Motion.standard } }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: seg.on
                        text: seg.modelData.label
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fgOnPrimary
                    }
                }

                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.picked(seg.index) }
                TapHandler { acceptedButtons: Qt.RightButton; onTapped: root.alternated(seg.index) }
            }
        }
    }
}
