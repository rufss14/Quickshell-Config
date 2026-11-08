import QtQuick
import Quickshell
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

    // Each item: { key, glyph, label, tint?, enabled?, trail? } — or { separator: true }.
    // `trail: { key, glyph }` is a second, smaller action at the row's right end,
    // shown while the row is hovered — the pin/unpin on a Windows jump-list row.
    // Clicking it triggers `trail.key` instead of the row's own key.
    // `enabled: false` greys a row out and ignores clicks on it. For an action that
    // can't apply here, with the label saying why (the dock's "Can't pin — no
    // desktop entry") — the same "disable it with a reason" rule the shell's other
    // controls follow, rather than a row that silently does nothing.
    property var items: []

    property bool opened: false

    // How much room the menu has. Defaults to the whole scene it lives in.
    property Item bounds: root.parent

    signal triggered(string key)

    // ── Pinned and melted (the dock's) ────────────────────────────────────────
    // Off everywhere but the dock. `pinned`: the host places the menu (pinX/pinY,
    // its resting top-left) instead of it opening at the cursor. `fused`: it's a
    // lobe of the frame — frame fill, no outline or shadow — that GROWS out of
    // `growFrom` ("left" | "right" | "bottom": the side it's welded to) instead of
    // fading in, and hands its box to the host (blobX…) for the blob to weld.
    property bool   pinned: false
    property real   pinX: 0
    property real   pinY: 0
    property bool   fused: false
    property string growFrom: "left"

    // Where it was asked to open (openAt), for a pinning host to place it by.
    readonly property real atX: root._sceneX
    readonly property real atY: root._sceneY

    // Its full height; a pinning host needs it to place the menu before it opens.
    readonly property real menuHeight: column.implicitHeight + Tokens.spacingMd * 2

    property real grow: root.opened ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(root.opened)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.opened ? Easing.BezierSpline : Motion.exitCurve
        }
    }
    readonly property bool _lobe: root.fused && root.grow > 0.01
    readonly property real blobX: root._lobe ? surface.x : 0
    readonly property real blobY: root._lobe ? surface.y : 0
    readonly property real blobW: root._lobe ? surface.width  : 0
    readonly property real blobH: root._lobe ? surface.height : 0

    anchors.fill: parent
    visible: root.opened || (root.fused ? root.grow > 0.01 : surface.opacity > 0.005)
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

        // Fused, it grows out of the side it's welded to (the dock's face).
        readonly property bool _crossW: root.fused && root.growFrom !== "bottom"
        width:  surface._crossW ? root.menuWidth * root.grow : root.menuWidth
        height: root.fused && !surface._crossW ? root.menuHeight * root.grow : root.menuHeight
        clip: root.fused

        Binding { target: surface; property: "color";       value: Colors.of(QsWindow.window).frameFill; when: root.fused }
        Binding { target: surface; property: "borderWidth"; value: 0;                when: root.fused }
        Binding { target: surface; property: "castsShadow"; value: false;            when: root.fused }
        // The blob's lobe radius (BlobBarLayer's previewRect), so no corner of the
        // fill pokes past the outline the blob draws around it.
        Binding { target: surface; property: "cornerRadius"; value: Tokens.radiusCard; when: root.fused }

        // Clamp into `bounds`, and flip above the cursor when there's no room below.
        readonly property real _spaceBelow:
            (root.bounds ? root.bounds.height : root.height) - root._sceneY

        x: {
            if (root.pinned)
                return root.fused && root.growFrom === "right"
                    ? root.pinX + root.menuWidth * (1 - root.grow) : root.pinX
            const limit = (root.bounds ? root.bounds.width : root.width) - width - Tokens.spacingMd
            return Math.max(Tokens.spacingMd, Math.min(limit, root._sceneX))
        }

        y: {
            if (root.pinned)
                return root.fused && root.growFrom === "bottom"
                    ? root.pinY + root.menuHeight * (1 - root.grow) : root.pinY
            const flip = surface._spaceBelow < height + Tokens.spacingXl
            const top  = flip ? root._sceneY - height - Tokens.spacingMd
                              : root._sceneY + Tokens.spacingMd
            const limit = (root.bounds ? root.bounds.height : root.height) - height - Tokens.spacingMd
            return Math.max(Tokens.spacingMd, Math.min(limit, top))
        }

        opacity: root.fused ? 1.0 : (root.opened ? Tokens.surfaceOpacity : 0.0)
        scale:   root.fused || root.opened ? 1.0 : 0.94

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

        // Full size always, riding the surface's MOVING edge while it grows (the
        // dock's own slide-out), so nothing is squashed as the menu melts out.
        Column {
            id: column
            x: root.fused && root.growFrom === "left" ? surface.width - root.menuWidth + Tokens.spacingMd
                                                      : Tokens.spacingMd
            y: root.fused && root.growFrom === "bottom" ? surface.height - root.menuHeight + Tokens.spacingMd
                                                        : Tokens.spacingMd
            width: root.menuWidth - Tokens.spacingMd * 2
            opacity: root.fused ? root.grow : 1
            spacing: 0

            Repeater {
                model: root.items

                Item {
                    id: row
                    required property var modelData

                    readonly property bool isSeparator: modelData.separator === true
                    readonly property bool isEnabled:   modelData.enabled !== false

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
                        color: (hover.containsMouse || trailMouse.containsMouse) && row.isEnabled ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
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
                        font.family: Tokens.glyphFamily(text)
                        color: !row.isEnabled ? Colors.of(QsWindow.window).fgFaint : (row.modelData.tint ?? Colors.of(QsWindow.window).fgMuted)
                        variant: "label"
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  rowGlyph.visible ? rowGlyph.right : parent.left
                        anchors.right: rowTrail.visible ? rowTrail.left : parent.right
                        anchors.leftMargin:  Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        visible: !row.isSeparator
                        text:  row.modelData.label ?? ""
                        color: !row.isEnabled ? Colors.of(QsWindow.window).fgFaint : (row.modelData.tint ?? Colors.of(QsWindow.window).fg)
                        variant: "label"
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        id: rowTrail
                        readonly property var trail: row.modelData.trail ?? null
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: Tokens.spacingMd
                        visible: !row.isSeparator && rowTrail.trail !== null
                        opacity: hover.containsMouse || trailMouse.containsMouse ? 1 : 0
                        glyph:  rowTrail.trail ? rowTrail.trail.glyph : ""
                        color: trailMouse.containsMouse ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgMuted
                        variant: "label"
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        // Still enabled on a disabled row, just inert: disabled, the
                        // click would fall through to the dismiss layer behind and
                        // close the menu — clicking the explanation shouldn't.
                        enabled: !row.isSeparator
                        hoverEnabled: true
                        cursorShape: row.isEnabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (!row.isEnabled) return
                            root.close()
                            root.triggered(row.modelData.key)
                        }
                    }

                    // Over the row's own area, so it wins in its corner.
                    MouseArea {
                        id: trailMouse
                        anchors.fill: rowTrail
                        anchors.margins: -Tokens.spacingXs
                        enabled: rowTrail.visible
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.close()
                            root.triggered(rowTrail.trail.key)
                        }
                    }
                }
            }
        }
    }
}
