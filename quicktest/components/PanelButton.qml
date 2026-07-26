import QtQuick
import QtQuick.Layouts
import "../config"

// ── PanelButton ───────────────────────────────────────────────────────────────
// The action button inside a panel: "Connect", "Apply", "Cancel", "Save".
//
// Three variants, and they are not interchangeable:
//
//   primary   filled with the accent. The one thing this dialog is FOR. At most
//             one per row — if two buttons are both primary, neither is.
//   normal    outlined on a container fill. Secondary actions.
//   ghost     no chrome until hovered. For icon-only affordances (rescan, close,
//             reveal) where a border would be visual noise.
//
// Every panel had its own; WifiPanel alone had two (DialogButton + HeaderButton)
// that differed only in whether they had a label.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property string label:   ""
    property string glyph:   ""
    property string variant: "normal"     // "primary" | "normal" | "ghost"
    property color  accent:  Colors.focus

    // Tint the glyph independently — the wifi panel's eye toggle dims when the IP
    // is hidden and lights up when revealed.
    property color glyphTint: root.variant === "primary" ? Colors.fgOnPrimary
                                                         : Colors.fgMuted

    signal activated()

    readonly property bool isPrimary: variant === "primary"
    readonly property bool isGhost:   variant === "ghost"

    implicitHeight: 30
    implicitWidth:  label !== ""
        ? Math.ceil(content.implicitWidth) + Tokens.spacingXl
        : implicitHeight                                  // icon-only ⇒ square

    radius: Tokens.radiusSm

    // NOTE: no `property bool enabled` — Item already has one, and redeclaring it
    // shadows the property QML uses to gate input. Item.enabled also propagates to
    // the MouseArea for free.
    opacity: enabled ? 1.0 : 0.4
    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

    color: root.isPrimary
        ? Colors.alpha(root.accent, hover.containsMouse ? 0.92 : 0.78)
        : root.isGhost
            ? (hover.containsMouse ? Colors.alpha(root.accent, 0.18) : "transparent")
            : (hover.containsMouse ? Colors.alpha(Colors.fg, 0.10) : Colors.surfaceContainer)

    border.width: (root.isPrimary || root.isGhost) ? 0 : Tokens.borderWidth
    border.color: Colors.outline

    Behavior on color { ColorAnimation { duration: Motion.respond } }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: 5

        StyledText {
            visible: root.glyph !== ""
            text:    root.glyph
            color:   root.glyphTint
            variant: "label"
            font.pixelSize: 13
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        StyledText {
            visible: root.label !== ""
            text:    root.label
            color:   root.isPrimary ? Colors.fgOnPrimary : Colors.fg
            opacity: root.isPrimary ? 1.0 : 0.70
            variant: "caption"
            font.weight: root.isPrimary ? Font.DemiBold : Font.Medium
        }
    }

    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
