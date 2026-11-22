import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"

// ── WorkoutField ──────────────────────────────────────────────────────────────
// The workout page's "add an exercise" field, built like the shell's other search fields (SearchPill,
// the launcher's): a capsule that types its own hints while it is idle, a dumbbell that lifts on every key,
// a focus ring, and a pill that says what Enter will do the moment the text is something it can add. It does
// not know what an exercise is: the page reads the text (`edited`), works out what it means, and hands back
// `readyText`. The keys the page wants are signals: Up / Down walk the suggestions (`step`), Tab takes the
// highlighted one (`complete`), Enter adds (`accepted`); Escape clears, and bubbles when there is nothing to clear.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    // [{ key, text }]: typed after `lead` while the field is empty and does not have the keys.
    property var hints: []
    property string lead: ""
    property color accent: Colors.of(QsWindow.window).primary
    // What Enter adds ("3 × 8 · 60 kg"), or "" when there is nothing to add yet.
    property string readyText: ""

    readonly property alias text: input.text
    readonly property alias editing: input.activeFocus
    signal edited(string value)
    signal accepted()
    signal step(int dir)
    signal complete()

    function setText(v) { input.text = v }
    function clear() { input.text = "" }
    function forceFocus() { input.forceActiveFocus() }

    readonly property var palette: Colors.of(QsWindow.window)

    implicitHeight: Tokens.iconXl + Tokens.spacingMd
    radius: height / 2
    color: root.palette.plate
    border.width: input.activeFocus ? 2 : 0
    border.color: root.accent
    Behavior on border.width { NumberAnimation { duration: Motion.respond } }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingSm
        spacing: Tokens.spacingMd

        // The dumbbell: it lifts and settles on every keystroke, and wears the accent while the field has the keys.
        Item {
            Layout.preferredWidth: Tokens.iconLg
            Layout.preferredHeight: Tokens.iconLg
            Layout.alignment: Qt.AlignVCenter
            SpringValue { id: lift; target: 0; spec: Motion.springSpatialFast; epsilon: 0.01 }
            SpringValue { id: bump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.002 }
            MaterialIcon {
                anchors.centerIn: parent
                name: "dumbbell"
                fill: input.activeFocus ? 1 : 0
                font.pixelSize: Tokens.iconLg
                color: input.activeFocus ? root.accent : root.palette.fgDim
                scale: bump.value
                transform: Translate { y: lift.value }
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }
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
                if (Config.motionEnabled) {
                    lift.jump(-4); lift.target = 0
                    bump.jump(1.22); bump.target = 1
                }
                root.edited(input.text)
            }
            onAccepted: root.accepted()
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_Down) { root.step(1); event.accepted = true }
                else if (event.key === Qt.Key_Up) { root.step(-1); event.accepted = true }
                else if (event.key === Qt.Key_Tab) { root.complete(); event.accepted = true }
            }
            Keys.onEscapePressed: function (event) {
                if (input.text === "") { event.accepted = false; return }
                input.text = ""
            }

            TypedPlaceholder {
                anchors.fill: parent
                visible: input.text.length === 0
                variant: "label"
                lead: root.lead
                placeholder: root.lead
                hints: input.activeFocus ? [] : root.hints
            }
        }

        // What Enter does: it springs in as soon as there is something to add, and its words follow the text.
        Rectangle {
            id: ready
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: readyRow.implicitWidth + Tokens.spacingMd * 2
            implicitHeight: readyRow.implicitHeight + Tokens.spacingXs * 2
            radius: height / 2
            color: root.palette.primaryContainer
            readonly property bool shown: root.readyText !== ""
            visible: readyK.value > 0.02
            scale: Math.max(0, readyK.value)
            opacity: Math.min(1, readyK.value * 1.4)
            transformOrigin: Item.Right
            SpringValue { id: readyK; target: ready.shown ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
            Row {
                id: readyRow
                anchors.centerIn: parent
                spacing: Tokens.spacingXs
                StyledText {
                    text: "↵"
                    variant: "micro"
                    font.weight: Font.Bold
                    color: root.palette.fgOnPrimaryContainer
                }
                StyledText {
                    text: root.readyText
                    variant: "micro"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                    color: root.palette.fgOnPrimaryContainer
                }
            }
        }

        IconButton {
            symbol: "close"
            visible: input.text.length > 0
            onClicked: { input.text = ""; input.forceActiveFocus() }
        }
    }
}
