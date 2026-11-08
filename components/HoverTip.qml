import QtQuick
import Quickshell
import "../config"

// ── HoverTip ──────────────────────────────────────────────────────────────────
// A floating label for the item this is declared in, after the pointer has rested on it: the sentence that explains a
// control, one hover away, instead of a line of small print under it. HelpTip is the same idea for a settings card, which
// draws the tip itself; nothing outside Settings does, so the overview's cards (and anything else that is not a settings
// page) use this one, which draws its own.
//
// A HoverHandler like HelpTip: passive, no geometry, steals no clicks, and the label is built only while it shows and
// parented to the item it explains. Declare it inside an ITEM (a ChipButton, a Text, a ring) — not directly in a Layout,
// where the label would become a layout cell; put it inside one of the layout's children instead.
//
//   HoverTip { text: "What this does" }              // above the item
//   HoverTip { text: "…"; below: true }              // under it
// ─────────────────────────────────────────────────────────────────────────────
HoverHandler {
    id: root

    property string text: ""
    property bool below: false
    // How long the pointer rests before the label opens, so sweeping across a card does not flash one per control.
    property int delay: 450
    property int maxWidth: 280

    property Item _card: null

    onHoveredChanged: {
        if (root.hovered && root.text !== "") dwell.restart()
        else { dwell.stop(); root._hide() }
    }
    onTextChanged: if (root._card) root._card.text = root.text
    Component.onDestruction: root._hide()

    property Timer _dwell: Timer {
        id: dwell
        interval: root.delay
        onTriggered: root._show()
    }

    function _show() {
        if (!root.parent || root._card || root.text === "") return
        root._card = card.createObject(root.parent, { text: root.text, below: root.below, maxWidth: root.maxWidth })
    }
    function _hide() {
        if (!root._card) return
        root._card.dismiss()
        root._card = null
    }

    property Component _comp: Component {
        id: card
        Item {
            id: c
            property string text: ""
            property bool below: false
            property real maxWidth: 280
            property bool up: false
            z: 10000
            width: bubble.width
            height: bubble.height
            x: Math.round((parent.width - width) / 2)
            y: c.below ? parent.height + Tokens.spacingSm : -height - Tokens.spacingSm
            opacity: c.up ? 1 : 0
            scale: c.up ? 1 : 0.94
            transformOrigin: c.below ? Item.Top : Item.Bottom
            visible: opacity > 0.01
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.exitCurve } }
            Component.onCompleted: c.up = true
            function dismiss() { c.up = false; gone.restart() }
            Timer { id: gone; interval: Motion.respond + 40; onTriggered: c.destroy() }

            Rectangle {
                id: bubble
                width: label.width + Tokens.spacingMd * 2
                height: label.implicitHeight + Tokens.spacingSm * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).surfaceHigh
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).outlineFocus
                StyledText {
                    id: label
                    x: Tokens.spacingMd
                    y: Tokens.spacingSm
                    // Its own width (a Text's implicit width is the unwrapped line), so its implicit height is the wrapped one.
                    width: Math.min(c.maxWidth - Tokens.spacingMd * 2, implicitWidth)
                    text: c.text
                    variant: "caption"
                    wrapMode: Text.Wrap
                }
            }
        }
    }
}
