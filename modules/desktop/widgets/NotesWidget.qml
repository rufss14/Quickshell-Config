pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
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
    property color accent: Colors.of(QsWindow.window).primary

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

    // ── The sheet (Material 3 Expressive, 2026-10-30) ─────────────────────────
    // The note sits on a sheet one tone up from the tile, with a cookie "pin" in its
    // corner, so the tile reads as a note pinned to the desktop rather than a text box.
    // The sheet's edge takes the focus outline while you type — where the keyboard is.
    Rectangle {
        id: sheet
        anchors.fill: parent
        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
        color: Colors.of(QsWindow.window).surfaceHigh
        border.width: Tokens.borderWidth
        border.color: area.activeFocus ? Colors.of(QsWindow.window).outlineFocus : "transparent"
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }
    }

    Item {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: -Tokens.spacingSm
        width: Tokens.iconLg + Tokens.spacingMd
        height: width
        z: 1
        MorphShape {
            anchors.fill: parent
            shape: Config.barShape ? "squircle" : "cookie7"
            fillColor: Colors.of(QsWindow.window).primaryContainer
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: "sticky_note_2"
            variant: "caption"
            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
        }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingXl
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
            color: Colors.of(QsWindow.window).fg
            selectionColor: Colors.of(QsWindow.window).alpha(root.accent, 0.35)
            selectedTextColor: Colors.of(QsWindow.window).fg
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
            text: Translation.tr("Click and type…")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }

    // ── Footer ────────────────────────────────────────────────────────────────
    // Word count and a one-tap copy of the whole note. Fades while you're typing
    // so it isn't sitting under the cursor; a scratch pad shouldn't wear a header,
    // but "how much have I written" and "give me all of it" are both worth one row.
    RowLayout {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.spacingSm
        spacing: Tokens.spacingXs
        visible: area.text.trim() !== ""
        opacity: area.activeFocus ? 0 : 1
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        readonly property int words:
            area.text.trim() === "" ? 0 : area.text.trim().split(/\s+/).length

        TilePill {
            Layout.alignment: Qt.AlignVCenter
            text: parent.words + (parent.words === 1 ? " word" : " words")
        }
        // Copy the whole note; a tick for a beat says it worked.
        TileChip {
            id: copyChip
            property bool recent: false
            awake: true
            icon: copyChip.recent ? "check" : "content_copy"
            onActivated: {
                Clipboard.copyText(area.text)
                copyChip.recent = true
                resetRecent.restart()
            }
            Timer { id: resetRecent; interval: 1200; onTriggered: copyChip.recent = false }
        }
    }
}
