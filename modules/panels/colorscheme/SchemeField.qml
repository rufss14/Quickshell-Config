import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── SchemeField ───────────────────────────────────────────────────────────────
// A text capsule for the colour scheme page (the hex, the palette's name), in the page's own dialect rather than
// a form box: a lifted pill with a round badge in front (a swatch of the colour it holds, or a glyph in a disc),
// the text, and room at the right for what acts on it (`trailing`: a copy tool, a Save pill). It rings in the
// accent while it has the keys, the badge leans in under the pointer, and an empty one types its own hints
// (TypedPlaceholder) while idle.
//
// `seed` is the value from outside, taken while the field is NOT being typed in; `setText()` writes it now.
// `committed` fires on Enter and on blur (put back whatever is not a value in the caller), `accepted` only on Enter.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string seed: ""
    property string lead: ""
    property var hints: []
    // A glyph for the badge, or a colour for it to be a swatch of (`swatch`'s alpha > 0 wins).
    property string icon: ""
    property color swatch: "transparent"
    property bool mono: false
    property color tone: Colors.of(QsWindow.window).plate
    property color accent: Colors.of(QsWindow.window).primary
    default property alias trailing: trail.data

    readonly property alias text: input.text
    readonly property alias editing: input.activeFocus
    signal committed(string value)
    signal accepted(string value)
    signal edited(string value)
    signal keyPressed(var event)

    function setText(v) { input.text = v }
    function clear() { input.text = "" }
    function forceFocus() { input.forceActiveFocus() }
    function blur() { input.focus = false }

    readonly property var palette: Colors.of(QsWindow.window)

    implicitHeight: Tokens.iconXl + Tokens.spacingLg
    radius: height / 2
    color: root.tone
    border.width: input.activeFocus ? 2 : 0
    border.color: root.accent
    Behavior on border.width { NumberAnimation { duration: Motion.respond } }

    onSeedChanged: if (!input.activeFocus) input.text = root.seed
    Component.onCompleted: input.text = root.seed

    // The badge.
    Item {
        id: badge
        anchors.left: parent.left
        anchors.leftMargin: Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        width: parent.height - Tokens.spacingSm * 2
        height: width
        SpringValue {
            id: lean
            target: hover.hovered || input.activeFocus ? 1.08 : 1
            spec: Motion.springSpatialFast
            epsilon: 0.001
        }
        scale: lean.value

        MorphShape {
            anchors.fill: parent
            shape: input.activeFocus ? "squircle" : "circle"
            spec: Motion.springSpatialFast
            fillColor: root.swatch.a > 0 ? root.swatch : root.palette.primaryContainer
            strokeColor: root.swatch.a > 0 ? root.palette.alpha(root.palette.fg, 0.2) : "transparent"
            Behavior on fillColor { enabled: root.swatch.a === 0; ColorAnimation { duration: Motion.standard } }
        }
        MaterialIcon {
            anchors.centerIn: parent
            visible: root.swatch.a === 0
            name: root.icon
            fill: input.activeFocus ? 1 : 0
            font.pixelSize: Tokens.iconMd
            color: root.palette.fgOnPrimaryContainer
            Behavior on fill { NumberAnimation { duration: Motion.standard } }
        }
    }

    TextInput {
        id: input
        anchors.left: badge.right
        anchors.leftMargin: Tokens.spacingMd
        anchors.right: trail.left
        anchors.rightMargin: Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.mono ? Tokens.fontMono : Tokens.fontFamily
        font.pixelSize: root.mono ? Tokens.fontTitle : Tokens.fontLabel
        font.weight: root.mono ? Font.DemiBold : Font.Normal
        color: root.palette.fg
        selectionColor: root.palette.alpha(root.accent, 0.35)
        selectByMouse: true
        clip: true
        Accessible.role: Accessible.EditableText
        Accessible.name: root.lead

        Keys.onPressed: event => root.keyPressed(event)
        onTextChanged: root.edited(input.text)
        onAccepted: { root.accepted(input.text); root.committed(input.text) }
        onActiveFocusChanged: if (!input.activeFocus) root.committed(input.text)

        TypedPlaceholder {
            anchors.fill: parent
            visible: input.text.length === 0
            variant: "label"
            lead: root.lead
            placeholder: root.lead
            hints: input.activeFocus ? [] : root.hints
        }
    }

    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacingXs
    }

    HoverHandler { id: hover; cursorShape: Qt.IBeamCursor }
}
