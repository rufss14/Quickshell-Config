pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../config"

// ── SegmentSwitch ─────────────────────────────────────────────────────────────
// A page switch with some presence: a full pill of solid container fill, and a FILLED accent
// indicator that slides to the chosen segment on a spring — it overshoots a touch and
// settles, so a switch reads as a move with weight, not a highlight turning on. The chosen
// segment's icon fills in (the FILL axis, animated) and its label firms up; an unchosen one
// lights a soft wash under the pointer.
//
// TabStrip is this control under another name (2026-10-25): settings pages and panels share
// one page switch. Used for a panel's own switch, e.g. the media panel's Player | Settings.
//
// Text and icon on the indicator are `fgOnPrimary` — what is drawn ON an accent fill
// everywhere else in the shell — rather than the accent's own tint, which would vanish
// into it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // [{ value, label, icon, lit?, fillIcon? }]
    //   lit       fills a segment's icon in the accent while it is NOT the chosen one, for "something
    //             is live over there" (the colours panel's Album tab while the music drives the shell).
    //   fillIcon  false keeps the icon outlined when it is chosen, for a glyph whose filled form turns
    //             to a blob (Material's `palette` loses its paint dots).
    property var   model:   []
    property var   current: ""
    property color accent:  Colors.of(QsWindow.window).primary

    signal picked(var value)

    implicitHeight: Tokens.iconXl + Tokens.spacingMd

    readonly property int  pad:  Tokens.spacingXs * 2
    readonly property int  n:    Math.max(1, root.model.length)
    readonly property real segW: (root.width - root.pad * 2) / root.n
    // Too narrow for every segment to carry its name beside its icon.
    readonly property bool compact: root.segW < 104
    readonly property int  currentIndex: Math.max(0, root.model.findIndex(m => m.value === root.current))

    // ── Compact widths ────────────────────────────────────────────────────────
    // Compact leaves only the chosen segment's name showing; at an equal share it still
    // elided ("De…" for Default). So the chosen segment takes what its icon + name need,
    // and the others split the rest, never below an icon's room.
    readonly property var  _cur: root.model[root.currentIndex] ?? ({})
    StyledText {
        id: curMeasure
        visible: false
        text: root._cur.label ?? ""
        variant: "label"
        font.weight: Font.DemiBold
    }
    readonly property real _avail:  Math.max(0, root.width - root.pad * 2)
    readonly property real _minOff: Tokens.iconMd + Tokens.spacingLg * 2
    readonly property real _onNeed: curMeasure.implicitWidth + Tokens.spacingLg * 2
                                    + ((root._cur.icon ?? "") !== "" ? Tokens.iconMd + Tokens.spacingSm : 0)
    readonly property real onW:  root.compact && root.n > 1
        ? Math.max(root.segW, Math.min(root._onNeed, root._avail - (root.n - 1) * root._minOff))
        : root.segW
    readonly property real offW: root.n > 1 ? (root._avail - root.onW) / (root.n - 1) : root.segW
    function segX(i) {
        return root.pad + (i <= root.currentIndex ? i * root.offW : (i - 1) * root.offW + root.onW)
    }

    // Set once the strip has real geometry, so the indicator doesn't glide in from the left
    // edge every time one is created.
    property bool _settled: false
    Component.onCompleted: Qt.callLater(function () { root._settled = true })

    // ── The pill ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Colors.of(QsWindow.window).surfaceContainer
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
    }

    // ── The indicator ─────────────────────────────────────────────────────────
    // x and width are separate springs, so as it travels it stretches toward the new segment
    // and gathers into it.
    Rectangle {
        id: indicator
        y: root.pad
        height: root.height - root.pad * 2
        radius: height / 2
        color: root.accent

        x:     root.segX(root.currentIndex)
        width: root.onW

        Behavior on x {
            enabled: root._settled
            SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.1 }
        }
        Behavior on width {
            enabled: root._settled
            SpringAnimation { spring: 4.0; damping: 0.40; epsilon: 0.1 }
        }
        Behavior on color { ColorAnimation { duration: Motion.standard } }
    }

    // ── The segments ──────────────────────────────────────────────────────────
    Repeater {
        model: root.model

        delegate: Item {
            id: seg
            required property int index
            required property var modelData

            readonly property bool on:  root.currentIndex === seg.index
            Accessible.role: Accessible.RadioButton
            Accessible.name: seg.modelData.label ?? ""
            Accessible.checkable: true
            Accessible.checked: seg.on
            Accessible.onPressAction: root.picked(seg.modelData.value)
            readonly property bool lit: !seg.on && (seg.modelData.lit ?? false)

            x: root.segX(seg.index)
            y: root.pad
            width:  seg.on ? root.onW : root.offW
            height: root.height - root.pad * 2

            // The hover wash, on a segment that is not the chosen one.
            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                opacity: !seg.on && hover.hovered ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
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
                    color: seg.on ? Colors.of(QsWindow.window).fgOnPrimary
                         : seg.lit ? root.accent
                         : hover.hovered ? Colors.of(QsWindow.window).fg
                         :                 Colors.of(QsWindow.window).fgMuted
                    Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                    Behavior on color { ColorAnimation  { duration: Motion.standard } }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: seg.modelData.label ?? ""
                    // A strip with more segments than room (six tabs in a window at its minimum
                    // width) keeps the chosen one's name and leaves the rest as icons; what still
                    // doesn't fit elides, rather than running into the next segment.
                    visible: text !== "" && (seg.on || !root.compact || (seg.modelData.icon ?? "") === "")
                    width: Math.min(implicitWidth, Math.max(0, seg.width - Tokens.spacingLg * 2
                                    - ((seg.modelData.icon ?? "") !== "" ? Tokens.iconMd + Tokens.spacingSm : 0)))
                    elide: Text.ElideRight
                    variant: "label"
                    font.weight: seg.on ? Font.DemiBold : Font.Medium
                    color: seg.on ? Colors.of(QsWindow.window).fgOnPrimary
                         : hover.hovered ? Colors.of(QsWindow.window).fg
                         :                 Colors.of(QsWindow.window).fgMuted
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }
            }

            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: root.picked(seg.modelData.value) }
        }
    }
}
