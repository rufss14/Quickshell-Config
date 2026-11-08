import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Widgets
import "../config"

// ── HoldButton ────────────────────────────────────────────────────────────────
// Press-and-hold to confirm a destructive action. A fill sweeps across while held;
// release before it completes and nothing fires.
//
// ── Why hold rather than a confirm dialog ─────────────────────────────────────
// The actions this guards (clear every notification, wipe the clipboard) are not
// dangerous enough to be worth a modal, but they are far too easy to hit by accident
// for a plain button. Holding costs a beat and can be abandoned mid-way, which is the
// proportionate answer — and unlike an "are you sure?" it can't be trained into a
// reflex that dismisses the one that mattered.
//
// It is built on the panel's button language, so it reads as a control rather than an
// alarm: the accent is the only thing that says destructive.
//
// Extracted from OverviewNotifications, where it was a private component, when the
// clipboard card needed the same gesture for the same reason.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.description: "Press and hold"

    property string label:     ""
    // What it says while held. Defaults to the idle label, so a caller that doesn't
    // care doesn't have to think about it.
    property string busyLabel: root.label
    property string glyph:     ""
    property color  accent:    Colors.of(QsWindow.window).danger

    // How long the hold must last. Long enough that a stray press can't complete it,
    // short enough not to feel like a punishment.
    property int holdMs: 750

    // A capsule at a header chip's height, for a settings page's header (the panels' chips).
    property bool capsule: false

    signal confirmed()

    // 0..1 fill progress. Public so a caller can watch it (and so the animation has
    // something to drive); assigning it from outside would fight the animation.
    property real hold: 0

    implicitWidth:  row.implicitWidth + Tokens.spacingLg * 2
    implicitHeight: root.capsule ? Tokens.iconXl + Tokens.spacingXs : 28
    elevation:      Tokens.elevationNested
    cornerRadius:   root.capsule ? root.implicitHeight / 2 : Tokens.radiusPill
    focused:        mouse.containsMouse

    // The confirm-fill, clipped to the pill so it stays inside the rounded edge.
    ClippingRectangle {
        anchors.fill: parent
        radius: parent.radius
        color: "transparent"

        Rectangle {
            anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
            width: parent.width * root.hold
            color: Colors.of(QsWindow.window).alpha(root.accent, 0.30)
        }
    }

    NumberAnimation {
        id: holdAnim
        target: root; property: "hold"
        from: 0; to: 1
        duration: root.holdMs
        onFinished: { root.confirmed(); root.hold = 0 }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed:  holdAnim.restart()
        onReleased: { holdAnim.stop(); root.hold = 0 }
        onCanceled: { holdAnim.stop(); root.hold = 0 }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Tokens.spacingSm

        MaterialIcon {
            glyph: root.glyph
            visible: root.glyph !== ""
            color: root.accent
            variant: "label"
        }
        StyledText {
            text: mouse.pressed ? root.busyLabel : root.label
            color: root.accent
            variant: "caption"
            font.bold: true
        }
    }
}
