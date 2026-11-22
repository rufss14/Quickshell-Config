pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── UpdatePasswordField ── the update panel's password, in place of the pill field (2026-11-15). ──────────────
// The user: "I don't like its current pill for inputting password, make a little shape animation for the digits
// when typing… think outside the box but don't overdo it". A tonal card rather than a pill:
//
//   left    a key on a badge that blooms (squircle → clover) while there is something typed, and fills in the
//           accent while the field has the keys
//   middle  each character is a small M3E shape: it pops in as a dot and settles, on a spring, into one of six
//           calm shapes in turn; the newest wears the accent, the ones before it step back to a quiet tone;
//           Backspace shrinks the last one away. Holding the eye shows the text instead, for as long as it is held
//   right   the send button, popping in once there is something to send; a line under the card says Caps Lock
//           is on when it is
//
// The keys go to a TextInput that is never drawn (echo Password, so nothing readable is ever on screen unless the
// eye is held). The API is InputField's for the three callers: `text`, `clear()`, `forceFocus()`, `accepted`,
// `keyPressed`. No spinning, no burst: the calm shapes only, the motion is the pop and the morph.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property string placeholder: Translation.tr("Your password")
    property string hint: Translation.tr("sudo asks for it once for this run")
    readonly property alias text: input.text
    signal accepted(string value)
    signal keyPressed(var event)
    function clear() { input.text = "" }
    function forceFocus() { input.forceActiveFocus() }

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool focused: input.activeFocus
    readonly property bool hasText: input.text.length > 0
    property bool peeking: false
    readonly property var shapes: ["cookie6", "clover", "sunny", "squircle", "hexagon", "cookie9"]

    implicitHeight: card.height + (capsLine.visible ? capsLine.implicitHeight + Tokens.spacingXs : 0)

    // The typed characters as a model that grows and shrinks at the END only, so the ones already there keep their
    // shape and only the newest pops (a count model would rebuild them all on every key).
    ListModel { id: dots }
    function _sync() {
        const n = input.text.length
        while (dots.count > n) dots.remove(dots.count - 1)
        while (dots.count < n) dots.append({ k: Math.floor(Math.random() * 1e9) })
    }

    TextInput {
        id: input
        width: 0
        height: 0
        opacity: 0
        echoMode: TextInput.Password
        onTextChanged: root._sync()
        onAccepted: root.accepted(input.text)
        Keys.onPressed: (event) => root.keyPressed(event)
        Accessible.role: Accessible.EditableText
        Accessible.name: root.placeholder
        Accessible.passwordEdit: true
    }

    Rectangle {
        id: card
        width: root.width
        height: Tokens.iconXl + Tokens.spacingLg * 2
        radius: Tokens.radiusXl
        color: root.palette.plate

        // A press anywhere on the card gives it the keys.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.IBeamCursor
            onClicked: input.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            // ── The key ───────────────────────────────────────────────────────
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingXs
                implicitHeight: implicitWidth
                MorphShape {
                    anchors.fill: parent
                    shape: root.hasText ? "clover" : "squircle"
                    spec: Motion.springSpatialFast
                    turns: false
                    fillColor: root.focused ? root.palette.primary : root.palette.section
                    Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "key"
                    fill: 1
                    color: root.focused ? root.palette.fgOnPrimary : root.palette.fgMuted
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }
            }

            // ── The characters ────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !root.hasText
                    spacing: 0
                    StyledText {
                        text: root.placeholder
                        variant: "label"
                        font.weight: Font.DemiBold
                        emphasis: root.focused ? "normal" : "muted"
                    }
                    StyledText {
                        text: root.hint
                        variant: "micro"
                        emphasis: "muted"
                    }
                }

                // Held eye: the text itself, in place of the shapes.
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    visible: root.peeking && root.hasText
                    text: root.peeking ? input.text : ""
                    variant: "label"
                    font.family: Tokens.fontMono
                    elide: Text.ElideLeft
                }

                ListView {
                    id: row
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Tokens.iconLg
                    visible: !root.peeking
                    orientation: ListView.Horizontal
                    interactive: false
                    spacing: Tokens.spacingXs
                    model: dots
                    // The newest stays in view however long it gets.
                    onCountChanged: Qt.callLater(row.positionViewAtEnd)

                    // Backspace: the last one shrinks away, the way it came.
                    remove: Transition {
                        NumberAnimation { property: "scale"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
                        NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
                    }

                    delegate: Item {
                        id: dot
                        required property int index
                        readonly property bool newest: dot.index === row.count - 1
                        width: Tokens.iconLg * 0.9
                        height: row.height

                        // In: from nothing to full size with the spring's small overshoot, as a dot first, then its
                        // own shape a beat later.
                        property bool settled: false
                        Component.onCompleted: settleBeat.start()
                        Timer { id: settleBeat; interval: Motion.fast; onTriggered: dot.settled = true }
                        SpringValue {
                            id: grow
                            target: 1
                            spec: Motion.springSpatialFast
                            epsilon: 0.002
                            Component.onCompleted: grow.jump(0)
                        }

                        MorphShape {
                            anchors.centerIn: parent
                            width: dot.width
                            height: width
                            scale: grow.value * (dot.newest ? 1.08 : 1)
                            rotation: (dot.index * 37) % 90
                            shape: dot.settled ? root.shapes[dot.index % root.shapes.length] : "circle"
                            spec: Motion.springSpatialFast
                            turns: false
                            fillColor: dot.newest ? root.palette.primary : root.palette.alpha(root.palette.fg, 0.42)
                            Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                        }
                    }
                }
            }

            // ── Peek, and send ────────────────────────────────────────────────
            CardTool {
                visible: root.hasText
                symbol: root.peeking ? "visibility" : "visibility_off"
                name: Translation.tr("Hold to see the password")
                // Held, not toggled: the text shows only while the pointer is down on it.
                MouseArea {
                    anchors.fill: parent
                    onPressed: root.peeking = true
                    onReleased: root.peeking = false
                    onCanceled: root.peeking = false
                }
            }
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingXs
                implicitHeight: implicitWidth
                SpringValue {
                    id: sendIn
                    target: root.hasText ? 1 : 0
                    spec: Motion.springSpatialFast
                    epsilon: 0.002
                }
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: root.palette.primary
                    scale: sendIn.value
                    visible: sendIn.value > 0.01
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "arrow_upward"
                        color: root.palette.fgOnPrimary
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.hasText
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.accepted(input.text)
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Continue")
                    }
                }
            }
        }
    }

    // Caps Lock, said once, under the card.
    RowLayout {
        id: capsLine
        anchors.top: card.bottom
        anchors.topMargin: Tokens.spacingXs
        anchors.left: card.left
        anchors.leftMargin: Tokens.spacingMd
        visible: KeyLocks.caps && root.focused
        spacing: Tokens.spacingXs
        MaterialIcon {
            name: "keyboard_capslock"
            color: root.palette.warning
            font.pixelSize: Tokens.iconMd
        }
        StyledText {
            text: Translation.tr("Caps Lock is on")
            variant: "caption"
            color: root.palette.warning
        }
    }
}
