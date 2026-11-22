pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── TabletProfileRow ──────────────────────────────────────────────────────────
// One profile: a name and a line of what it sets. The one in use is the accent container, goes round and
// blooms its badge into a shape with a tick (the source rail's and OptionCard's idiom); the rest are plates
// with a plain disc. Tools (copy, rename, remove) come out under the pointer. Remove does not arm in place:
// it lays a Keep / Remove layer over the row, so nobody reads a label that moved under their pointer.
//
// Renaming is in place, a field where the name was; Enter or leaving it keeps the new name, Escape the old.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string name: ""
    property string summary: ""
    property bool active: false
    property bool canRemove: true
    property string shape: "cookie9"

    signal picked()
    signal copied()
    signal renamed(string to)
    signal removed()

    // "" | "rename" | "remove"
    property string mode: ""

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: root.active ? root.palette.fgOnPrimaryContainer : root.palette.fg
    readonly property color inkDim: root.active ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
    readonly property bool tools: (hover.hovered || root.active) && root.mode === ""

    implicitHeight: Tokens.iconXl + Tokens.spacingLg
    color: root.active ? root.palette.primaryContainer : root.palette.plate
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    SpringValue { id: shapeK; target: root.active ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
    radius: Tokens.radiusSm + Math.max(0, shapeK.value) * (root.height / 2 - Tokens.radiusSm)

    SpringValue {
        id: lean
        target: tap.pressed ? 0.97 : hover.hovered && !root.active ? 1.015 : 1
        spec: Motion.springSpatialFast
        epsilon: 0.001
    }
    scale: lean.value

    StateLayer {
        anchors.fill: parent
        radius: root.radius
        hovered: hover.hovered && !root.active
        layerColor: root.ink
    }

    // The whole row is the button; the tools and the field are declared after it, so they sit above it.
    MouseArea {
        id: tap
        anchors.fill: parent
        enabled: root.mode === ""
        cursorShape: Qt.PointingHandCursor
        onClicked: root.picked()
    }
    HoverHandler { id: hover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingMd
        anchors.rightMargin: Tokens.spacingMd
        spacing: Tokens.spacingMd

        Item {
            Layout.preferredWidth: Tokens.iconXl - Tokens.spacingXs
            Layout.preferredHeight: Layout.preferredWidth
            MorphShape {
                anchors.fill: parent
                shape: root.active ? root.shape : "circle"
                spec: Motion.springSpatialFast
                fillColor: root.active ? root.palette.primary : root.palette.section
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: root.active ? "check" : "layers"
                fill: root.active ? 1 : 0
                font.pixelSize: Tokens.iconMd
                color: root.active ? root.palette.fgOnPrimary : root.palette.fgMuted
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            visible: root.mode !== "rename"
            StyledText {
                Layout.fillWidth: true
                text: root.name
                variant: "label"
                font.weight: root.active ? Font.DemiBold : Font.Medium
                color: root.ink
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.summary !== ""
                text: root.summary
                variant: "micro"
                color: root.inkDim
                elide: Text.ElideRight
            }
        }

        InputField {
            id: field
            Layout.fillWidth: true
            visible: root.mode === "rename"
            placeholder: Translation.tr("Profile name")
            onAccepted: function (v) { root.renamed(v); root.mode = "" }
            Keys.onEscapePressed: root.mode = ""
        }

        // Tools under the pointer.
        Row {
            Layout.fillWidth: false
            spacing: 0
            visible: opacity > 0.01
            opacity: root.tools ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }

            CardTool {
                symbol: "content_copy"
                tint: root.ink
                name: Translation.tr("Copy this profile")
                onActivated: root.copied()
            }
            CardTool {
                symbol: "edit"
                tint: root.ink
                name: Translation.tr("Rename")
                onActivated: { field.setText(root.name); root.mode = "rename"; field.forceFocus() }
            }
            CardTool {
                visible: root.canRemove
                symbol: "delete"
                tint: root.ink
                name: Translation.tr("Remove")
                onActivated: root.mode = "remove"
            }
        }
    }

    // ── Remove: a layer, not a re-press ───────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.palette.danger
        opacity: root.mode === "remove" ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }

        // Takes the press, so the row under the layer is not chosen by a click on it.
        MouseArea { anchors.fill: parent }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingSm
            spacing: Tokens.spacingSm
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Remove %1?").arg(root.name)
                variant: "label"
                font.weight: Font.DemiBold
                color: root.palette.fgOnPrimary
                elide: Text.ElideRight
            }
            ChipButton {
                tonal: true
                tint: root.palette.fgOnPrimary
                label: Translation.tr("Keep")
                onActivated: root.mode = ""
            }
            ChipButton {
                solid: true
                tint: root.palette.fgOnPrimary
                symbol: "delete"
                label: Translation.tr("Remove")
                onActivated: { root.mode = ""; root.removed() }
            }
        }
    }

    Accessible.role: Accessible.Button
    Accessible.name: root.name
    Accessible.checkable: true
    Accessible.checked: root.active
    Accessible.onPressAction: root.picked()
}
