import QtQuick
import QtQuick.Layouts
import "../config"

// ── Disclosure ────────────────────────────────────────────────────────────────
// A labelled header that reveals its content when clicked. Closed by default.
//
// ── Not Accordion ─────────────────────────────────────────────────────────────
// The names are close enough to be worth separating explicitly. Accordion sequences
// the swap between mutually-exclusive panels sharing one window — it's a state
// machine about timing, and it draws nothing. This is a widget that hides its own
// children. Neither is a version of the other.
//
// ── Why the content is lazy ───────────────────────────────────────────────────
// Loader with `active: open`, not `visible: open`. A collapsed disclosure holding a
// live sparkline would still be binding, still be building its path, still be
// repainting on every sample — paying the whole cost of a chart nobody can see. The
// shell's rule is that things you can't see aren't instantiated, and "hidden" is not
// the same as "gone".
//
// The consequence to know about: content is BUILT on first open, so its state doesn't
// survive a close/open cycle. That's correct for read-only detail. Don't put a
// half-filled form in one.
//
// Usage:
//     Disclosure {
//         label: "Advanced"
//         contentComponent: Component { ColumnLayout { ... } }
//     }
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string label: "Advanced"
    property bool   open:  false

    // A Component, not an Item: the point is that it isn't built until `open`.
    property Component contentComponent: null

    spacing: Tokens.spacingMd

    // ── The header ────────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        implicitHeight: Math.max(headerRow.implicitHeight, Tokens.pillHeight)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: hover.hovered ? Colors.alpha(Colors.fg, 0.06) : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        RowLayout {
            id: headerRow
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingSm
            anchors.rightMargin: Tokens.spacingSm
            spacing: Tokens.spacingSm

            // Rotates rather than swaps glyph: one mark that moves is easier to read as
            // "this thing opened" than two marks that replace each other.
            StyledText {
                text: "󰅂"                        // chevron-right
                variant: "caption"
                emphasis: "dim"
                rotation: root.open ? 90 : 0
                Behavior on rotation {
                    NumberAnimation { duration: Motion.fast; easing.type: Easing.OutCubic }
                }
            }

            StyledText {
                text: root.label
                variant: "label"
                emphasis: "muted"
            }

            Item { Layout.fillWidth: true }
        }

        HoverHandler { id: hover }
        TapHandler { onTapped: root.open = !root.open }
    }

    Loader {
        id: content
        Layout.fillWidth: true
        active: root.open
        visible: root.open
        sourceComponent: root.contentComponent
    }
}
