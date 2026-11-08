import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"

// ── PresetChips ───────────────────────────────────────────────────────────────
// Saved looks as a row of chips: tap one to load it, the one you are wearing is
// filled, and a last "+ Save" chip names the current state. A user preset shows a
// rename and a remove mark while the pointer is on it; a built-in one never does.
//
// ── Why one component ─────────────────────────────────────────────────────────
// Cursor, Bar › Style and System › Presets each carried their own ~120-line list of
// preset rows — the same rows, with the same rename field and the same hover
// actions, already drifting (one had a check icon, one a glyph, one a version tag).
// They differ only in which Config functions they call, so those are the API here:
// the page passes the list and its own predicates and handles the signals.
//
// Chips rather than rows because a preset is a value you pick, like a ChipRow's,
// and two or three of them do not need a list's height.
//
//   presets     [{ name, builtin?, version? }]
//   isActive    function (name) → bool        — which one you are wearing
//   isBuiltin   function (preset) → bool      — default: preset.builtin
//   badgeFor    function (preset) → string    — a small tag after the name ("v0.2")
//   signals     load(name) · save(name) · rename(from, to) · remove(name)
//   renamable   false hides the rename mark
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property var presets: []
    property var isActive:  function (name) { return false }
    property var isBuiltin: function (p) { return p.builtin === true }
    property var badgeFor:  function (p) { return "" }
    property color  accent: Colors.of(QsWindow.window).primary
    property string savePlaceholder: "Name this preset"
    // False where the store has no rename (the desktop's widget layouts).
    property bool   renamable: true

    signal load(string name)
    signal save(string name)
    signal rename(string from, string to)
    signal remove(string name)
    // Right-click, for a caller that gives a preset a second meaning beyond loading it
    // once (the desktop's widgets: right-click a preset to give a wallpaper its own,
    // live). Nothing connects it and nothing fires without a RightButton tap, so every
    // other caller is unaffected.
    signal rightClicked(string name)

    // Which preset is being renamed, by name; and whether the name field is open.
    property string _renaming: ""
    property bool   _adding: false

    function _commitSave() {
        const name = nameField.text.trim()
        if (name === "") return
        root.save(name)
        nameField.clear()
        root._adding = false
    }

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingSm

    Flow {
        Layout.fillWidth: true
        spacing: Tokens.spacingXs

        // A chip opening its marks pushes the rest along; they glide rather than jump.
        move: Transition {
            NumberAnimation { properties: "x,y"; duration: Motion.standard; easing.type: Motion.travel }
        }

        Repeater {
            model: root.presets

            delegate: Rectangle {
                id: chip
                required property var modelData

                readonly property string name: chip.modelData.name
                readonly property bool active:  root.isActive(chip.name)
                readonly property bool builtin: root.isBuiltin(chip.modelData)
                readonly property bool editing: root._renaming === chip.name && !chip.builtin
                readonly property bool hot: chipHover.hovered
                readonly property string badge: root.badgeFor(chip.modelData)

                implicitHeight: 32
                implicitWidth: chipRow.implicitWidth + Tokens.spacingLg * 2 - Tokens.spacingSm
                radius: height / 2

                color: chip.active ? Colors.of(QsWindow.window).alpha(root.accent, chip.hot ? 0.95 : 0.85)
                                   : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, chip.hot ? 0.12 : 0.06)
                Behavior on color { ColorAnimation { duration: Motion.respond } }

                // Loading one pops it, the same acknowledgement a picked chip makes.
                property real pop: 1.0
                onActiveChanged: if (chip.active) popAnim.restart()
                SequentialAnimation {
                    id: popAnim
                    NumberAnimation { target: chip; property: "pop"; to: 1.12; duration: Motion.respond; easing.type: Motion.respondCurve }
                    NumberAnimation {
                        target: chip; property: "pop"; to: 1.0
                        duration: Motion.standard
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                    }
                }
                scale: chip.pop

                RowLayout {
                    id: chipRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingLg - Tokens.spacingXs
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: chip.active ? "check" : "bookmark"
                        fill: chip.active ? 1 : 0
                        color: chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconSm
                    }

                    StyledText {
                        visible: !chip.editing
                        text: chip.name
                        variant: "label"
                        color: chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                        font.weight: chip.active ? Font.DemiBold : Font.Medium
                    }

                    TextInput {
                        id: renameInput
                        visible: chip.editing
                        Layout.preferredWidth: 120
                        text: chip.name
                        color: chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                        font.family:    Tokens.fontFamily
                        font.pixelSize: Tokens.fontLabel
                        selectByMouse:  true
                        selectionColor: Colors.of(QsWindow.window).alpha(root.accent, 0.35)
                        clip: true

                        onVisibleChanged: if (visible) {
                            text = chip.name
                            selectAll()
                            forceActiveFocus()
                        }
                        function commit() {
                            const to = renameInput.text
                            root._renaming = ""
                            if (to.trim() !== "" && to !== chip.name) root.rename(chip.name, to)
                        }
                        onAccepted: renameInput.commit()
                        Keys.onEscapePressed: root._renaming = ""
                        onActiveFocusChanged: if (!activeFocus && chip.editing) renameInput.commit()
                    }

                    StyledText {
                        visible: chip.badge !== "" && !chip.editing
                        text: chip.badge
                        variant: "micro"
                        color: chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgDim
                    }

                    // Rename and remove: a user preset's, sliding out of the chip while
                    // it is pointed at. The chip grows to the right, so the pointer
                    // stays inside it; the chips after it glide over (Flow's `move`).
                    Item {
                        id: marks
                        readonly property bool open: chip.hot && !chip.builtin && !chip.editing
                        // Animated through a plain property: a Behavior on an attached
                        // Layout property is not something to rely on.
                        property real openWidth: marks.open ? markRow.implicitWidth : 0
                        Behavior on openWidth {
                            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                        }
                        Layout.preferredWidth: marks.openWidth
                        Layout.preferredHeight: markRow.implicitHeight
                        Layout.leftMargin: marks.open ? 0 : -Tokens.spacingSm
                        clip: true

                        RowLayout {
                            id: markRow
                            spacing: Tokens.spacingSm
                            opacity: marks.open ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            MaterialIcon {
                                visible: root.renamable
                                name: "edit"
                                font.pixelSize: Tokens.iconSm
                                color: renameHover.hovered ? (chip.active ? Colors.of(QsWindow.window).fgOnPrimary : root.accent)
                                                           : (chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgDim)
                                HoverHandler { id: renameHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root._renaming = chip.name }
                            }
                            MaterialIcon {
                                name: "close"
                                font.pixelSize: Tokens.iconSm
                                color: removeHover.hovered ? Colors.of(QsWindow.window).danger
                                                           : (chip.active ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgDim)
                                HoverHandler { id: removeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.remove(chip.name) }
                            }
                        }
                    }
                }

                HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: !chip.editing
                    // The marks inside have their own taps; a tap on one is not a load.
                    onTapped: if (!renameHover.hovered && !removeHover.hovered) root.load(chip.name)
                }
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    enabled: !chip.editing
                    onTapped: root.rightClicked(chip.name)
                }
            }
        }

        // ── Save the current state ────────────────────────────────────────────
        Rectangle {
            visible: !root._adding
            implicitHeight: 32
            implicitWidth: addRow.implicitWidth + Tokens.spacingLg * 2 - Tokens.spacingSm
            radius: height / 2
            color: addHover.hovered ? Colors.of(QsWindow.window).alpha(root.accent, 0.14) : "transparent"
            border.width: Tokens.borderWidth
            border.color: addHover.hovered ? Colors.of(QsWindow.window).alpha(root.accent, 0.6)
                                           : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).outline, 0.7)
            Behavior on color        { ColorAnimation { duration: Motion.respond } }
            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

            RowLayout {
                id: addRow
                anchors.centerIn: parent
                spacing: Tokens.spacingXs
                MaterialIcon {
                    name: "add"
                    font.pixelSize: Tokens.iconSm
                    color: addHover.hovered ? root.accent : Colors.of(QsWindow.window).fgMuted
                }
                StyledText {
                    text: Translation.tr("Save current")
                    variant: "label"
                    color: addHover.hovered ? root.accent : Colors.of(QsWindow.window).fgMuted
                }
            }

            HoverHandler { id: addHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onTapped: {
                    root._adding = true
                    nameField.forceFocus()
                }
            }
        }
    }

    // The name, asked for only when you have said you want to save.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: root._adding
        spacing: Tokens.spacingSm

        Item {
            Layout.fillWidth: true
            implicitHeight: nameField.implicitHeight
            Keys.onEscapePressed: function (e) {
                nameField.clear()
                root._adding = false
                e.accepted = true
            }
            InputField {
                id: nameField
                anchors.left: parent.left
                anchors.right: parent.right
                placeholder: root.savePlaceholder
                onAccepted: root._commitSave()
            }
        }
        PanelButton {
            label:   Translation.tr("Save")
            variant: "primary"
            accent:  root.accent
            enabled: nameField.text.trim() !== ""
            onActivated: root._commitSave()
        }
        PanelButton {
            variant: "ghost"
            symbol:  "close"
            onActivated: {
                nameField.clear()
                root._adding = false
            }
        }
    }
}
