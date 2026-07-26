import QtQuick
import "../config"

// ── ContextMenu ───────────────────────────────────────────────────────────────
// A small right-click menu, driven by a plain JS array:
//
//     ContextMenu {
//         items: [
//             { key: "pin",   glyph: "󰐃", label: "Pin to dock" },
//             { separator: true },
//             { key: "close", glyph: "󰅖", label: "Close", tint: Colors.danger }
//         ]
//         onTriggered: key => …
//     }
//
// `TrayMenu` looks similar but cannot be reused: it renders a DBusMenu handle from
// a StatusNotifierItem, so its model is remote and its activation goes back over
// D-Bus. This one owns nothing and just reports which key was clicked.
//
// ── Positioning ───────────────────────────────────────────────────────────────
// The menu is anchored in SCENE space and clamped to the overlay, because a menu
// opened on the last icon in the dock would otherwise open half off-screen. Call
// `openAt(sceneX, sceneY)` — the caller doesn't have to know how tall the menu is.
//
// It also opens UPWARD when there isn't room below, which for a dock pinned to the
// bottom of the screen is the normal case rather than the exception.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Each item: { key, glyph, label, tint? } — or { separator: true }.
    property var items: []

    property bool opened: false

    // How much room the menu has. Defaults to the whole scene it lives in.
    property Item bounds: root.parent

    signal triggered(string key)

    anchors.fill: parent
    visible: root.opened || surface.opacity > 0.005
    z: 9999

    function openAt(sceneX, sceneY) {
        root._sceneX = sceneX
        root._sceneY = sceneY
        root.opened = true
    }

    function close() { root.opened = false }

    property real _sceneX: 0
    property real _sceneY: 0

    // Settable: 200 suits short verbs ("Pin to dock", "Close"), but a menu listing audio
    // devices needs far more — PipeWire device descriptions run to 60 characters. Labels
    // elide regardless, so an under-sized menu degrades to a truncated name instead of
    // text running out past the edge of the surface, which is what used to happen.
    property int menuWidth: 200

    // ── Dismiss layer ─────────────────────────────────────────────────────────
    // Fills the overlay and eats the next click anywhere. Without this, clicking
    // "somewhere else" would fall through to whatever is underneath (the backdrop,
    // which closes the whole overview) — so a stray click would blow away the
    // overlay rather than just the menu.
    MouseArea {
        anchors.fill: parent
        enabled: root.opened
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.close()
    }

    Surface {
        id: surface

        elevation: Tokens.elevationPopup

        width:  root.menuWidth
        height: column.implicitHeight + Tokens.spacingMd * 2

        // Clamp into `bounds`, and flip above the cursor when there's no room below.
        readonly property real _spaceBelow:
            (root.bounds ? root.bounds.height : root.height) - root._sceneY

        x: {
            const limit = (root.bounds ? root.bounds.width : root.width) - width - Tokens.spacingMd
            return Math.max(Tokens.spacingMd, Math.min(limit, root._sceneX))
        }

        y: {
            const flip = surface._spaceBelow < height + Tokens.spacingXl
            const top  = flip ? root._sceneY - height - Tokens.spacingMd
                              : root._sceneY + Tokens.spacingMd
            const limit = (root.bounds ? root.bounds.height : root.height) - height - Tokens.spacingMd
            return Math.max(Tokens.spacingMd, Math.min(limit, top))
        }

        opacity: root.opened ? Tokens.surfaceOpacity : 0.0
        scale:   root.opened ? 1.0 : 0.94

        // A menu appears at your cursor and must be usable instantly — it enters
        // fast, and leaves faster.
        Behavior on opacity {
            NumberAnimation {
                duration: Motion.surfaceDuration(root.opened)
                easing.type: Motion.surfaceEasing(root.opened)
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: Motion.surfaceDuration(root.opened)
                easing.type: Motion.surfaceEasing(root.opened)
            }
        }

        Column {
            id: column
            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.margins: Tokens.spacingMd
            spacing: 0

            Repeater {
                model: root.items

                Item {
                    id: row
                    required property var modelData

                    readonly property bool isSeparator: modelData.separator === true

                    width: column.width
                    height: isSeparator ? Tokens.spacingMd + 1 : 30

                    Divider {
                        visible: row.isSeparator
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  parent.left
                        anchors.right: parent.right
                    }

                    Rectangle {
                        visible: !row.isSeparator
                        anchors.fill: parent
                        radius: Tokens.radiusXs
                        color: hover.containsMouse ? Colors.alpha(Colors.fg, 0.10)
                                                   : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    // Anchored rather than a Row: a Row sizes to its content, so a long
                    // label simply overflowed the surface and painted outside the menu.
                    // Anchoring the label to BOTH edges gives it a real width, which is
                    // what makes elide work at all — elide on an unconstrained Text does
                    // nothing.
                    StyledText {
                        id: rowGlyph
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spacingMd
                        visible: !row.isSeparator && (row.modelData.glyph ?? "") !== ""
                        text:  row.modelData.glyph ?? ""
                        color: row.modelData.tint ?? Colors.fgMuted
                        variant: "label"
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  rowGlyph.visible ? rowGlyph.right : parent.left
                        anchors.right: parent.right
                        anchors.leftMargin:  Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        visible: !row.isSeparator
                        text:  row.modelData.label ?? ""
                        color: row.modelData.tint ?? Colors.fg
                        variant: "label"
                        elide: Text.ElideRight
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        enabled: !row.isSeparator
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.close()
                            root.triggered(row.modelData.key)
                        }
                    }
                }
            }
        }
    }
}
