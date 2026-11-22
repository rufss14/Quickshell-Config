pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── MixerDevice ───────────────────────────────────────────────────────────────
// One audio output or input as a card. The device's KIND is the badge ("HD-Audio Generic" tells a beginner nothing,
// a headset or a monitor does): a plain disc until it is the one in use, then it blooms into a cookie and the card
// goes loud (the island's "this one is on": a primary container, a full pill). A tap anywhere makes it the default.
//
// "Which is the default" comes from the service (`current`), so it stays right when something outside the shell
// changes it. An output also has tools under the pointer (send every playing app here, open its options) and
// unfolds its options INLINE, under the row: a volume limit as option cards (a limit is a decision, not a
// quantity) and the balance when the device has a left and a right.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var node
    property var current: null
    property bool isSink: false
    property bool canMove: false
    property int order: 0

    signal picked()
    signal moveHere()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool on: root.node !== null && root.node === root.current
    readonly property string codec: Audio.bluetoothCodecOf(root.node)
    readonly property real cap: root.isSink ? Audio.capOf(root.node) : 0
    readonly property bool canBalance: root.isSink && Audio.canBalanceNode(root.node)
    property bool editing: false
    readonly property color ink: root.on ? root.palette.fgOnPrimaryContainer : root.palette.fg
    readonly property color inkDim: root.on ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted

    color: root.on ? root.palette.primaryContainer : root.palette.plate
    Behavior on color { ColorAnimation { duration: Motion.standard } }
    SpringValue { id: shapeK; target: root.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
    // The whole card goes rounder when it is the one in use, as an OptionCard does. It goes back to a card while it
    // is open (a pill with a form under it would be a strange shape).
    readonly property real pillR: Tokens.radiusCard + Math.max(0, shapeK.value) * (root.headH / 2 - Tokens.radiusCard)
    radius: root.pillR + (Tokens.radiusCard - root.pillR) * Math.min(1, Math.max(0, optionsK.value))
    readonly property real headH: Tokens.iconXl * 2 + Tokens.spacingLg * 2
    implicitHeight: headH + optionsK.value * optionsCol.implicitHeight + (optionsK.value > 0.005 ? root.pad : 0)
    readonly property real pad: Tokens.spacingLg

    PopIn { id: pop; active: root.visible; index: root.order; cap: 5 }
    opacity: pop.opacity
    SpringValue {
        id: lean
        target: tap.pressed ? 0.98 : headHover.hovered && !root.on ? 1.015 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value * pop.scale

    SpringValue { id: optionsK; target: root.editing ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }

    // ── The row ───────────────────────────────────────────────────────────────
    Item {
        id: head
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.headH

        StateLayer {
            anchors.fill: parent
            radius: root.radius
            hovered: headHover.hovered && !root.on
            layerColor: root.ink
        }
        HoverHandler { id: headHover; cursorShape: Qt.PointingHandCursor }
        // A MouseArea under the row's buttons, so a button never also picks the device.
        MouseArea { id: tap; anchors.fill: parent; z: -1; onClicked: root.picked() }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.pad
            anchors.rightMargin: root.pad
            spacing: Tokens.spacingLg

            Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl * 2
                Layout.preferredHeight: Tokens.iconXl * 2
                MorphShape {
                    anchors.fill: parent
                    shape: root.on ? (root.isSink ? "cookie12" : "sunny") : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: root.on ? root.palette.primary : root.palette.section
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    glyph: Audio.deviceGlyph(root.node)
                    fill: root.on ? 1 : 0
                    font.pixelSize: Tokens.iconLg
                    color: root.on ? root.palette.fgOnPrimary : root.palette.fgMuted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Audio.shortLabelFor(root.node)
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.on ? (Audio.profileOf(root.node) !== "" ? Translation.tr("In use · %1").arg(Audio.profileOf(root.node)) : Translation.tr("In use"))
                                  : Audio.profileOf(root.node)
                    variant: "micro"
                    color: root.inkDim
                    elide: Text.ElideRight
                }
            }

            Badge {
                visible: root.codec !== ""
                label: root.codec
                tint: root.ink
            }
            Badge {
                visible: root.cap > 0
                label: Translation.tr("Limit %1%").arg(Math.round(root.cap * 100))
                tint: root.on ? root.ink : root.palette.warning
            }

            // Tools: only for an output, only under the pointer or while open.
            Row {
                id: tools
                readonly property bool shown: root.isSink && (headHover.hovered || root.editing)
                Layout.alignment: Qt.AlignVCenter
                spacing: 0
                visible: tools.shown || toolsK.value > 0.005
                opacity: Math.min(1, Math.max(0, toolsK.value))
                scale: 0.7 + 0.3 * Math.max(0, toolsK.value)
                transformOrigin: Item.Right
                SpringValue { id: toolsK; target: tools.shown ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }

                LitTool {
                    visible: root.canMove
                    symbol: "swap_horiz"
                    ink: root.ink
                    tip: Translation.tr("Play every app here")
                    tipBelow: true
                    onActivated: root.moveHere()
                }
                LitTool {
                    symbol: "tune"
                    lit: root.editing
                    ink: root.ink
                    tip: Translation.tr("Limit and balance")
                    tipBelow: true
                    onActivated: root.editing = !root.editing
                }
            }
        }
    }

    // ── The options, unfolded ─────────────────────────────────────────────────
    Item {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: head.bottom
        anchors.bottom: parent.bottom
        clip: true
        visible: optionsK.value > 0.005

        ColumnLayout {
            id: optionsCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: root.pad
            anchors.rightMargin: root.pad
            spacing: Tokens.spacingMd
            opacity: optionsK.value

            StyledText {
                text: Translation.tr("Maximum volume").toUpperCase()
                variant: "caption"
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: root.inkDim
            }
            // A limit is a decision ("keep my headphones under 60%"), so presets and not a slider.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Repeater {
                    model: [0, 40, 60, 80]
                    delegate: Rectangle {
                        id: lim
                        required property int modelData
                        readonly property bool chosen: (root.cap > 0 ? Math.round(root.cap * 100) : 0) === lim.modelData
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl
                        radius: height / 2
                        color: lim.chosen ? root.palette.primary : root.palette.alpha(root.ink, 0.1)
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                        StateLayer { anchors.fill: parent; radius: parent.radius; hovered: limHover.hovered && !lim.chosen; layerColor: root.ink }
                        StyledText {
                            anchors.centerIn: parent
                            text: lim.modelData === 0 ? Translation.tr("No limit") : lim.modelData + "%"
                            variant: "caption"
                            font.weight: lim.chosen ? Font.DemiBold : Font.Medium
                            color: lim.chosen ? root.palette.fgOnPrimary : root.ink
                        }
                        HoverHandler { id: limHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: Audio.setCap(root.node, lim.modelData / 100) }
                    }
                }
            }

            // Only for an output that has a left and a right.
            ColumnLayout {
                id: balBox
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.canBalance
                spacing: Tokens.spacingSm
                readonly property real balance: Audio.balanceOf(root.node)

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Balance").toUpperCase()
                        variant: "caption"
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: root.inkDim
                    }
                    StyledText {
                        text: Math.abs(balBox.balance) < 0.01 ? Translation.tr("Centred")
                            : Math.round(Math.abs(balBox.balance) * 100) + "% " + (balBox.balance < 0 ? Translation.tr("left") : Translation.tr("right"))
                        variant: "caption"
                        color: root.inkDim
                    }
                    ChipButton {
                        visible: Math.abs(balBox.balance) >= 0.01
                        label: Translation.tr("Centre")
                        tonal: true
                        onActivated: Audio.centreBalance(root.node)
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    StyledText { text: "L"; variant: "caption"; color: root.inkDim }
                    ValueSlider {
                        Layout.fillWidth: true
                        expressive: true
                        thickness: Tokens.spacingLg
                        // -1..+1 folded onto 0..1; the notch marks the centre.
                        value: (balBox.balance + 1) / 2
                        maximum: 1.0
                        notchAt: 0.5
                        accent: root.palette.primary
                        accessibleName: Translation.tr("Balance")
                        onMoved: function (v) { Audio.setBalance(root.node, v * 2 - 1) }
                        onScrolled: function (d) { Audio.setBalance(root.node, balBox.balance + d * 0.05) }
                    }
                    StyledText { text: "R"; variant: "caption"; color: root.inkDim }
                }
            }
        }
    }
}
