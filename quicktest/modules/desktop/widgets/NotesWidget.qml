pragma ComponentBehavior: Bound
import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── NotesWidget ───────────────────────────────────────────────────────────────
// A scratch pad on the desktop that you can actually type into.
//
// ── Typing on a background-layer surface ──────────────────────────────────────
// This is the widget that decided the layer's design. A wlr-layershell Background
// surface takes keyboard input only if it asks: the host sets
// `WlrLayershell.keyboardFocus = OnDemand` when any editable widget is placed, which
// means "give me the keyboard when the user clicks me, and never otherwise". Exclusive
// would steal every keystroke on the desktop; None would make this a read-only
// rectangle. See WidgetLayer for where that is switched.
//
// ── Saving ────────────────────────────────────────────────────────────────────
// Debounced, not per keystroke. The store writes through JsonStore (itself debounced),
// but a write scheduled on every character would still churn the array on a service
// that rebuilds every widget record on each change. One second of quiet is the trigger,
// plus an unconditional flush when focus leaves — so a note is never lost by clicking
// away, which is the case that would actually lose work.
Item {
    id: root

    required property var opts
    required property string size
    required property int widgetId
    property bool active: true
    property color accent: Colors.primary

    readonly property string saved: root.opts.text ?? ""

    // The editor is the source of truth WHILE focused; the store is when it is not.
    // Rebinding the text on every store change would rewrite the field under the
    // cursor after each debounced save and bounce the caret to the end.
    onSavedChanged: if (!area.activeFocus && area.text !== root.saved) area.text = root.saved
    Component.onCompleted: area.text = root.saved

    Timer {
        id: debounce
        interval: 1000
        onTriggered: DesktopWidgets.setOpt(root.widgetId, "text", area.text)
    }

    function flush() {
        debounce.stop()
        if (area.text !== root.saved)
            DesktopWidgets.setOpt(root.widgetId, "text", area.text)
    }
    Component.onDestruction: root.flush()

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: area.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        TextEdit {
            id: area
            width: flick.width
            // Grows with its content so the Flickable has something to scroll; a fixed
            // height would clip the note at the tile's edge with no way to reach the rest.
            height: Math.max(flick.height, implicitHeight)

            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLabel
            color: Colors.fg
            selectionColor: Colors.alpha(root.accent, 0.35)
            selectedTextColor: Colors.fg
            wrapMode: TextEdit.Wrap
            selectByMouse: true
            persistentSelection: true

            onTextChanged: debounce.restart()
            onActiveFocusChanged: if (!activeFocus) root.flush()

            // Escape hands the keyboard back rather than leaving the desktop holding
            // focus — otherwise the only way out is clicking another window.
            Keys.onEscapePressed: area.focus = false
        }

        StyledText {
            anchors.fill: parent
            visible: area.text === ""
            text: "Click and type…"
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }
}
