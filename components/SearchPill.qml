import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"

// ── SearchPill ────────────────────────────────────────────────────────────────
// The island pages' search field, a feature and not a box: a tonal pill on the section tone, ringed in the
// accent while it has the keys. Idle and empty it TYPES its own hints (TypedPlaceholder, the launcher's and the
// settings search's); with text it says how many it found, out of how many (`found` of `total`, red "None" at
// zero), the glass bumps with every key, and a cross clears it. Escape clears, then lets go of the keys.
//
// `hints`: [{ key, text }] as TypedPlaceholder takes them. `found` < 0 hides the count. `text` is read-only;
// `setText()` / `clear()` write it.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string lead: ""
    property var hints: []
    property int found: -1
    property int total: 0
    property color accent: Colors.of(QsWindow.window).primary
    readonly property alias text: input.text
    readonly property alias editing: input.activeFocus
    signal edited(string value)

    function setText(v) { input.text = v }
    function clear() { input.text = "" }
    function forceFocus() { input.forceActiveFocus() }
    function blur() { input.focus = false }

    readonly property var palette: Colors.of(QsWindow.window)

    implicitHeight: Tokens.iconXl + Tokens.spacingXs
    radius: height / 2
    color: root.palette.section
    border.width: input.activeFocus ? 2 : 0
    border.color: root.accent
    Behavior on border.width { NumberAnimation { duration: Motion.respond } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingSm
        spacing: Tokens.spacingSm

        MaterialIcon {
            name: "search"
            variant: "body"
            color: input.activeFocus ? root.accent : root.palette.fgDim
            scale: glassBump.value
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            SpringValue { id: glassBump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.002 }
        }

        TextInput {
            id: input
            Layout.fillWidth: true
            color: root.palette.fg
            selectionColor: root.palette.alpha(root.accent, 0.35)
            selectByMouse: true
            font.family: Tokens.fontFamily
            font.pixelSize: Tokens.fontLabel
            verticalAlignment: TextInput.AlignVCenter
            cursorVisible: activeFocus
            onTextChanged: {
                if (Config.motionEnabled) { glassBump.jump(1.28); glassBump.target = 1 }
                root.edited(input.text)
            }
            Keys.onEscapePressed: {
                input.text = ""
                input.focus = false
            }

            TypedPlaceholder {
                anchors.fill: parent
                visible: input.text.length === 0
                variant: "label"
                lead: root.lead
                placeholder: root.lead
                // Idle only: while it has the keys the field is plainly waiting for you.
                hints: input.activeFocus ? [] : root.hints
            }
        }

        // How many it found, out of how many.
        Rectangle {
            visible: input.text.length > 0 && root.found >= 0
            implicitWidth: foundText.implicitWidth + Tokens.spacingMd * 2
            implicitHeight: foundText.implicitHeight + Tokens.spacingXs
            radius: height / 2
            color: root.found === 0 ? root.palette.alpha(root.palette.danger, 0.2) : root.palette.primaryContainer
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            StyledText {
                id: foundText
                anchors.centerIn: parent
                text: root.found === 0 ? Translation.tr("None") : Translation.tr("%1 of %2").arg(root.found).arg(root.total)
                variant: "micro"
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: root.found === 0 ? root.palette.fg : root.palette.fgOnPrimaryContainer
            }
        }
        IconButton {
            symbol: "close"
            visible: input.text.length > 0
            onClicked: input.text = ""
        }
    }
}
