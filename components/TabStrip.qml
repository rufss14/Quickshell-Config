pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"

// ── TabStrip ──────────────────────────────────────────────────────────────────
// A settings page's choice of two to four values, or a panel's page switch. Same API as SegmentSwitch:
// `model` [{ value, label, icon, lit?, fillIcon? }], `current`, `accent`, `picked(value)`.
//
// Two looks:
//   · `connected: false` (the default) IS SegmentSwitch: one pill with a filled indicator that slides.
//     Every call site that does not ask for the other look draws exactly what it drew before.
//   · `connected: true` is Material 3 Expressive's connected button group: separate segments a hairline
//     gap apart, the outer ends fully round and the inner corners small. The chosen one is the filled
//     accent; it goes round to a full pill and takes a little more room, so its neighbours squeeze, all on
//     springs (the selection's spring may overshoot a touch, island-style §3). A press dips a segment.
//
// The connected group is built only when asked for (a Loader), so the strips that keep the old look pay
// nothing for it.
//
// Keys (connected): ← → move the choice while the group has focus (Tab reaches it).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var   model:   []
    property var   current: ""
    property color accent:  Colors.of(QsWindow.window).primary
    property bool  connected: false

    signal picked(var value)

    implicitHeight: Tokens.iconXl + Tokens.spacingMd

    readonly property int  n: Math.max(1, root.model.length)
    readonly property int  currentIndex: Math.max(0, root.model.findIndex(m => m.value === root.current))
    // Too narrow for every segment to carry its name beside its icon (SegmentSwitch's rule).
    readonly property bool compact: root.connected ? (root.width - group.gap * (root.n - 1)) / root.n < 104
                                                   : (plain.item ? plain.item.compact : false)

    Loader {
        id: plain
        anchors.fill: parent
        active: !root.connected
        sourceComponent: SegmentSwitch {
            model:   root.model
            current: root.current
            accent:  root.accent
            onPicked: function (value) { root.picked(value) }
        }
    }

    // ── The connected group ───────────────────────────────────────────────────
    // Geometry is plain arithmetic on the segments' WEIGHTS: each segment's width is its weight's share
    // of the row (less the gaps). The chosen segment's weight rises on a spring and the others' share
    // falls with it, which is the squeeze. In compact mode the chosen one's weight is whatever gives it
    // the room its name needs, and the rest keep an icon's room.
    QtObject {
        id: group
        readonly property real gap: Tokens.spacingXs
        readonly property real inner: Tokens.radiusSm
        // How much more room the chosen segment takes, as a share of an equal one.
        readonly property real grow: 0.14
    }

    Loader {
        id: conn
        anchors.fill: parent
        active: root.connected
        sourceComponent: Item {
            id: strip

            readonly property real avail: Math.max(0, strip.width - group.gap * (root.n - 1))
            readonly property var cur: root.model[root.currentIndex] ?? ({})

            StyledText {
                id: curMeasure
                visible: false
                text: strip.cur.label ?? ""
                variant: "label"
                font.weight: Font.DemiBold
            }
            // The chosen segment's weight against an unchosen one's 1.
            readonly property real selWeight: {
                if (root.n < 2) return 1
                if (!root.compact) return 1 + group.grow
                const minOff = Tokens.iconMd + Tokens.spacingLg * 2
                const need = curMeasure.implicitWidth + Tokens.spacingLg * 2
                           + ((strip.cur.icon ?? "") !== "" ? Tokens.iconMd + Tokens.spacingSm : 0)
                const onW = Math.max(strip.avail / root.n, Math.min(need, strip.avail - (root.n - 1) * minOff))
                const offW = (strip.avail - onW) / (root.n - 1)
                return offW > 0 ? Math.max(1, onW / offW) : 1
            }

            // Sum of the live weights and each segment's left edge, read off the delegates.
            readonly property real total: {
                let s = 0
                for (let i = 0; i < segs.count; i++) {
                    const it = segs.itemAt(i)
                    if (it) s += it.weight
                }
                return Math.max(0.001, s)
            }
            function leftOf(index) {
                // Read so a segment's edge re-evaluates once every delegate exists.
                if (segs.count <= index) return index * group.gap
                let s = 0
                for (let i = 0; i < index; i++) {
                    const it = segs.itemAt(i)
                    if (it) s += it.weight
                }
                return s / strip.total * strip.avail + index * group.gap
            }

            function step(d) {
                const next = Math.max(0, Math.min(root.model.length - 1, root.currentIndex + d))
                if (next !== root.currentIndex) root.picked(root.model[next].value)
            }

            activeFocusOnTab: true
            Keys.onLeftPressed:  strip.step(-1)
            Keys.onRightPressed: strip.step(1)

            // Keyboard focus: a ring round the whole group, in the focus role.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Tokens.spacingXs
                radius: height / 2
                color: "transparent"
                border.width: Tokens.borderWidth * 2
                border.color: Colors.of(QsWindow.window).outlineFocus
                visible: strip.activeFocus
            }

            Repeater {
                id: segs
                model: root.model

                delegate: Item {
                    id: seg
                    required property int index
                    required property var modelData

                    readonly property bool on: root.currentIndex === seg.index
                    readonly property bool lit: !seg.on && (seg.modelData.lit ?? false)
                    readonly property bool firstSeg: seg.index === 0
                    readonly property bool lastSeg: seg.index === root.model.length - 1

                    SpringValue {
                        id: weightK
                        target: seg.on ? strip.selWeight : 1
                        spec: Motion.springSpatialFast
                        epsilon: 0.001
                    }
                    readonly property real weight: Math.max(0.2, weightK.value)

                    // 0 = a connected segment, 1 = a full pill (the chosen one).
                    SpringValue { id: roundK; target: seg.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
                    SpringValue { id: dip; target: tap.pressed ? 0.95 : 1; spec: Motion.springSpatialFast; epsilon: 0.001 }
                    scale: dip.value

                    x: strip.leftOf(seg.index)
                    width: seg.weight / strip.total * strip.avail
                    height: strip.height

                    readonly property real full: seg.height / 2
                    readonly property real innerR: Math.max(0, Math.min(seg.full,
                        group.inner + roundK.value * (seg.full - group.inner)))
                    readonly property real startR: seg.firstSeg ? seg.full : seg.innerR
                    readonly property real endR:   seg.lastSeg  ? seg.full : seg.innerR

                    readonly property color ink: seg.on ? Colors.of(QsWindow.window).fgOnPrimary
                                               : seg.lit ? root.accent
                                               : hover.hovered ? Colors.of(QsWindow.window).fg
                                               : Colors.of(QsWindow.window).fgMuted

                    Accessible.role: Accessible.RadioButton
                    Accessible.name: seg.modelData.label ?? ""
                    Accessible.checkable: true
                    Accessible.checked: seg.on
                    Accessible.onPressAction: root.picked(seg.modelData.value)

                    Rectangle {
                        id: plate
                        anchors.fill: parent
                        color: seg.on ? root.accent : Colors.of(QsWindow.window).section
                        topLeftRadius:     seg.startR
                        bottomLeftRadius:  seg.startR
                        topRightRadius:    seg.endR
                        bottomRightRadius: seg.endR
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }

                    StateLayer {
                        anchors.fill: parent
                        hovered: hover.hovered && !seg.on
                        layerColor: seg.ink
                        topLeftRadius:     seg.startR
                        bottomLeftRadius:  seg.startR
                        topRightRadius:    seg.endR
                        bottomRightRadius: seg.endR
                    }

                    Row {
                        anchors.centerIn: parent
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: seg.modelData.icon ?? ""
                            visible: name !== ""
                            fill: (seg.on || seg.lit) && (seg.modelData.fillIcon ?? true) ? 1 : 0
                            font.pixelSize: Tokens.iconMd
                            color: seg.ink
                            Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                            Behavior on color { ColorAnimation  { duration: Motion.standard } }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: seg.modelData.label ?? ""
                            visible: text !== "" && (seg.on || !root.compact || (seg.modelData.icon ?? "") === "")
                            width: Math.min(implicitWidth, Math.max(0, seg.width - Tokens.spacingLg * 2
                                            - ((seg.modelData.icon ?? "") !== "" ? Tokens.iconMd + Tokens.spacingSm : 0)))
                            elide: Text.ElideRight
                            variant: "label"
                            font.weight: seg.on ? Font.DemiBold : Font.Medium
                            color: seg.ink
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                    }

                    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                    // A MouseArea, not a TapHandler: nothing sits under a segment, but a press here must
                    // never also reach whatever is under the strip.
                    MouseArea {
                        id: tap
                        anchors.fill: parent
                        onClicked: root.picked(seg.modelData.value)
                    }
                }
            }
        }
    }
}
