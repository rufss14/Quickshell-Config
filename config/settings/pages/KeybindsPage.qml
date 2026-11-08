import QtQuick
import QtQuick.Layouts
import "../../theming" as T
import "../../config"
import ".."

// Keybinds — view and rebind every Hyprland keybind, grouped by category. Click a
// row, press the new combo (the settings window grabs the keyboard so SUPER-combos
// reach us), and it's written to keybinds.json → binds-generated.lua → hyprctl
// reload. Duplicate combos are flagged with a conflict warning.
Item {
    id: root

    // Which bind id is currently capturing a new combo ("" = none).
    property string capturingId: ""

    function startCapture(id) { root.capturingId = id; Settings.grabKeys = true; captureItem.forceActiveFocus() }
    function endCapture()      { root.capturingId = ""; Settings.grabKeys = false }

    // ── Qt key event → Hyprland combo string ────────────────────────────────────
    function comboFromEvent(e) {
        var mods = []
        if (e.modifiers & Qt.MetaModifier)    mods.push("SUPER")
        if (e.modifiers & Qt.ControlModifier) mods.push("CTRL")
        if (e.modifiers & Qt.AltModifier)     mods.push("ALT")
        if (e.modifiers & Qt.ShiftModifier)   mods.push("SHIFT")
        var k = root.keyName(e.key, e.text)
        if (k === "") return ""   // a bare modifier — keep waiting
        return mods.concat([k]).join(" + ")
    }
    function keyName(key, text) {
        var modKeys = [Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Meta, Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_CapsLock]
        if (modKeys.indexOf(key) !== -1) return ""
        if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
        if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
        var sh = {}
        sh[Qt.Key_Exclam] = "1"; sh[Qt.Key_At] = "2"; sh[Qt.Key_NumberSign] = "3"; sh[Qt.Key_Dollar] = "4"
        sh[Qt.Key_Percent] = "5"; sh[Qt.Key_AsciiCircum] = "6"; sh[Qt.Key_Ampersand] = "7"; sh[Qt.Key_Asterisk] = "8"
        sh[Qt.Key_ParenLeft] = "9"; sh[Qt.Key_ParenRight] = "0"
        if (sh[key] !== undefined) return sh[key]
        if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
        var n = {}
        n[Qt.Key_Space] = "Space"; n[Qt.Key_Left] = "left"; n[Qt.Key_Right] = "right"; n[Qt.Key_Up] = "up"; n[Qt.Key_Down] = "down"
        n[Qt.Key_Return] = "Return"; n[Qt.Key_Enter] = "Return"; n[Qt.Key_Tab] = "TAB"; n[Qt.Key_Backspace] = "BackSpace"
        n[Qt.Key_Delete] = "Delete"; n[Qt.Key_Home] = "Home"; n[Qt.Key_End] = "End"; n[Qt.Key_PageUp] = "Prior"; n[Qt.Key_PageDown] = "Next"; n[Qt.Key_Insert] = "Insert"
        n[Qt.Key_Minus] = "minus"; n[Qt.Key_Equal] = "equal"; n[Qt.Key_Comma] = "comma"; n[Qt.Key_Period] = "period"; n[Qt.Key_Slash] = "slash"
        n[Qt.Key_Semicolon] = "semicolon"; n[Qt.Key_Apostrophe] = "apostrophe"; n[Qt.Key_BracketLeft] = "bracketleft"; n[Qt.Key_BracketRight] = "bracketright"
        n[Qt.Key_Backslash] = "backslash"; n[Qt.Key_QuoteLeft] = "grave"
        n[Qt.Key_MediaNext] = "XF86AudioNext"; n[Qt.Key_MediaPrevious] = "XF86AudioPrev"; n[Qt.Key_MediaPlay] = "XF86AudioPlay"; n[Qt.Key_MediaTogglePlayPause] = "XF86AudioPlay"
        n[Qt.Key_VolumeUp] = "XF86AudioRaiseVolume"; n[Qt.Key_VolumeDown] = "XF86AudioLowerVolume"; n[Qt.Key_VolumeMute] = "XF86AudioMute"; n[Qt.Key_MicMute] = "XF86AudioMicMute"
        n[Qt.Key_MonBrightnessUp] = "XF86MonBrightnessUp"; n[Qt.Key_MonBrightnessDown] = "XF86MonBrightnessDown"
        if (n[key] !== undefined) return n[key]
        if (text && text.length === 1 && text.charCodeAt(0) >= 33) return text.toUpperCase()
        return ""
    }

    // Pretty label for a combo token in a key-cap chip.
    function tokenLabel(t) {
        if (t === "SUPER") return "Super"
        if (t === "CTRL")  return "Ctrl"
        if (t === "ALT")   return "Alt"
        if (t === "SHIFT") return "Shift"
        if (t.indexOf("XF86") === 0) return t.substring(4)   // XF86AudioNext → AudioNext
        return t
    }

    // Key capture surface — focused while capturing; swallows the combo.
    Item {
        id: captureItem
        anchors.fill: parent
        Keys.onPressed: function(e) {
            if (root.capturingId === "") return
            e.accepted = true
            if (e.key === Qt.Key_Escape) { root.endCapture(); return }
            var combo = root.comboFromEvent(e)
            if (combo === "") return
            Keybinds.rebind(root.capturingId, combo)
            root.endCapture()
        }
    }

    Flickable {
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: root.capturingId === ""   // don't scroll mid-capture

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 18

            Text {
                text: "Keybinds"
                color: T.Theme.ink
                font { family: T.Theme.headingFamily; pixelSize: T.Theme.fontSize + 10; bold: true }
            }
            Text {
                Layout.fillWidth: true
                text: "Click a shortcut, then press the new key combo (Esc to cancel). Changes are "
                    + "written to your Hyprland config and applied immediately."
                wrapMode: Text.WordWrap
                color: T.Theme.inkDim
                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3 }
            }

            Repeater {
                model: Keybinds.groups()
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 8

                    Text {
                        text: modelData.name
                        color: T.Theme.accent
                        font { family: T.Theme.headingFamily; pixelSize: T.Theme.fontSize + 1; bold: true }
                    }

                    Repeater {
                        model: modelData.items
                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            readonly property bool capturing: root.capturingId === row.modelData.id
                            readonly property var clash: Keybinds.conflict(row.modelData.key, row.modelData.id)
                            Layout.fillWidth: true
                            implicitHeight: 48
                            radius: T.Theme.radiusMedium
                            color: row.capturing ? T.Theme.surfaceActive : (rowMa.containsMouse ? T.Theme.surfaceHover : T.Theme.surfaceAlt)
                            border.width: row.capturing ? 1 : 0
                            border.color: T.Theme.accent
                            Behavior on color { ColorAnimation { duration: T.Theme.animFast } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    Layout.fillWidth: true
                                    text: row.modelData.label
                                    color: T.Theme.ink
                                    elide: Text.ElideRight
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize }
                                }

                                // Conflict warning.
                                RowLayout {
                                    visible: row.clash !== null && !row.capturing
                                    spacing: 4
                                    Text { text: String.fromCodePoint(0xF0026); color: T.Theme.accentAlt; font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize } } // alert
                                    Text {
                                        text: row.clash ? ("clashes with " + row.clash.label) : ""
                                        color: T.Theme.accentAlt
                                        font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 4 }
                                    }
                                }

                                // Capturing prompt, or the key-cap chips.
                                Text {
                                    visible: row.capturing
                                    text: "Press keys…  Esc to cancel"
                                    color: T.Theme.accent
                                    font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 1; italic: true }
                                }
                                RowLayout {
                                    visible: !row.capturing
                                    spacing: 4
                                    Repeater {
                                        model: String(row.modelData.key).split(" + ")
                                        delegate: Rectangle {
                                            required property var modelData
                                            implicitHeight: 26
                                            implicitWidth: capLbl.implicitWidth + 16
                                            radius: T.Theme.radiusSmall
                                            color: T.Theme.surface
                                            border.width: 1; border.color: T.Theme.border
                                            Text {
                                                id: capLbl
                                                anchors.centerIn: parent
                                                text: root.tokenLabel(modelData)
                                                color: T.Theme.ink
                                                font { family: T.Theme.fontFamily; pixelSize: T.Theme.fontSize - 3; bold: true }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: row.capturing ? root.endCapture() : root.startCapture(row.modelData.id)
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 6 }
        }
    }

    // Leaving the page while capturing must release the grab.
    Component.onDestruction: if (root.capturingId !== "") root.endCapture()
}
