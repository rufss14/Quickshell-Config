import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── UndoBar ───────────────────────────────────────────────────────────────────
// "Deleted 'Work' — Undo", for a few seconds, then gone.
//
// ── Why this instead of a confirm ─────────────────────────────────────────────
// A confirmation dialog taxes every correct action to prevent the rare wrong one:
// you delete twelve presets and answer "are you sure?" twelve times. An undo taxes
// nothing and only spends attention when the delete was actually a mistake — which
// is the right trade whenever the action is genuinely reversible.
//
// So the CALLER must be able to put the thing back. `show()` takes a closure that
// restores it, and the caller is responsible for having captured whatever that needs
// (the preset's config object, the widget's type and options) BEFORE deleting. If a
// thing cannot be restored — forgetting a Bluetooth pairing drops a key the device
// has to re-issue — it wants a hold-to-confirm, not this.
//
// ── The window is deliberately short ──────────────────────────────────────────
// Long enough to catch the "wait, no" that follows a wrong click by about a second;
// short enough that it never becomes chrome you learn to ignore. It pauses while the
// pointer is over it, because reaching for Undo should not be a race.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string message: ""
    property int    seconds: 7

    // Set by show(); called by the Undo button.
    property var _restore: null

    readonly property bool shown: root._restore !== null

    function show(text, restore) {
        root.message  = text
        root._restore = restore
        countdown.restart()
    }

    function dismiss() {
        countdown.stop()
        root.message  = ""
        root._restore = null
    }

    function undo() {
        const fn = root._restore
        root.dismiss()
        if (fn) fn()
    }

    Timer {
        id: countdown
        interval: root.seconds * 1000
        // Paused while pointed at: reaching for Undo shouldn't be a race against a
        // timer you can see running out.
        running: false
        onTriggered: if (!barHover.hovered) root.dismiss()
                     else restartWhenLeft.start()
    }

    // If it expired under the pointer, wait for the pointer to leave and give it one
    // more short window rather than dismissing out from under the cursor.
    Timer {
        id: restartWhenLeft
        interval: 400
        repeat: true
        running: false
        onTriggered: if (!barHover.hovered) { stop(); root.dismiss() }
    }

    Layout.fillWidth: true
    implicitHeight: root.shown ? barRow.implicitHeight + Tokens.spacingMd * 2 : 0
    visible: implicitHeight > 0
    clip: true

    radius: Tokens.radiusPill
    color:  Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).outline

    opacity: root.shown ? 1 : 0

    Behavior on implicitHeight {
        NumberAnimation {
            duration: Motion.standard
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Motion.spring
        }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

    HoverHandler { id: barHover }

    RowLayout {
        id: barRow
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin:  Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingSm
        spacing: Tokens.spacingMd

        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: root.message
            variant: "caption"
            elide: Text.ElideRight
        }

        PanelButton {
            variant: "ghost"
            symbol:  "undo"
            label:   Translation.tr("Undo")
            onActivated: root.undo()
        }
        PanelButton {
            variant: "ghost"
            symbol:  "close"
            onActivated: root.dismiss()
        }
    }
}
