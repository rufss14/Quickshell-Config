import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── BarContextMenu ────────────────────────────────────────────────────────────
// The tray's right-click menu (a remote DBusMenu, via QsMenuOpener) — moved out of
// its own PanelWindow (modules/panels/TrayMenu.qml, now retired) and into Bar's own
// window, for the same reason every other panel made that move: `Quicktest.Blobs`
// can only fuse shapes sharing one Qt Quick scene graph, and a second layer-shell
// surface is composited independently by Hyprland. This is the one panel that
// stays anchored to WHERE YOU CLICKED rather than a fixed dock slot — see BarDock
// for the fixed-slot version of the same deal.
//
// ── Not `components/ContextMenu.qml` ──────────────────────────────────────────
// That one's model is a plain `items: [...]` array; this one's is a live DBusMenu
// handle whose activation goes back over D-Bus. Genuinely different data, so it's
// a different Repeater — but the visual recipe (Surface, Tokens, StyledText,
// Divider, the dismiss layer) is copied from it on purpose, so the shell's two
// context menus finally look like they belong to the same design system instead
// of one looking ten years newer than the other.
//
// ── Morph wiring, the minimal slice of what BarDock does ──────────────────────
// `cardX/Y/W/H` (the Surface's own box) and `maskItem` (for the window's input
// mask) go up to Bar.qml the same way BarDock's do; `deformMatrix` comes back down
// and is applied to the Surface's own transform, same as BarDock applies it to its
// card's content. This menu only ever welds to the bar's UNDERSIDE (never a side
// strip) — architecturally the same single-join lobe as the centre (update panel)
// slot in BlobBarLayer, just at whatever X the clicked icon happens to be instead
// of a fixed dock position.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var menuHandle: null
    property var anchorItem: null

    // Drives the fade/scale; stays "shown" until the exit animation finishes so it
    // can animate out rather than vanish, same contract the old PanelWindow had.
    property bool expanded: false

    // Fed back from BlobBarLayer.trayDeform; identity while the blob is absent.
    property matrix4x4 deformMatrix

    // Matches Bar.qml's own `blobRing` exactly (Morph.available && Config.barAnchored)
    // — same condition BarDock's `blobWeld` reduces to for a centre-style slot. A
    // welded lobe draws no outline or shadow of its own; the blob's smooth-min IS
    // the join, and a rectangular stroke on top of an organic silhouette can never
    // agree with it (see BarDock's own comment on this exact point). Gated on the
    // plugin being present: with no blob there is no silhouette to supply, so the
    // ordinary Surface border/shadow is what a floating popup should have.
    property bool blobWeld: false

    // Zeroed when closed — a menu that's fading out on its own opacity/scale
    // Behavior (below) still reports a real box otherwise, which would leave a
    // permanent phantom lobe welded into the bar's underside forever. Closing is
    // quick enough (Motion.exit) that popping straight out of the blob group here
    // reads as part of the same fade rather than a separate snap.
    readonly property real cardX: root.expanded ? surface.x      : 0
    readonly property real cardY: root.expanded ? surface.y      : 0
    readonly property real cardW: root.expanded ? surface.width  : 0
    readonly property real cardH: root.expanded ? surface.height : 0
    readonly property Item maskItem: surface

    // A ceiling on how tall this can get, fed into Bar.qml's implicitHeight the
    // same way ccHost/panelDock/toastHost's maxHeight already are — so the window
    // always reserves enough room, and a long DBus menu clamps rather than
    // reserving unbounded space for the rare case.
    readonly property real maxHeight: 400

    function open(handle, anchor) {
        root.menuHandle = handle
        root.anchorItem = anchor
        root.expanded   = true
    }
    function close() { root.expanded = false }

    visible: root.expanded || surface.opacity > 0.005
    z: 50

    QsMenuOpener {
        id: opener
        menu: root.menuHandle
    }

    // ── Dismiss layer ─────────────────────────────────────────────────────────
    // Fills the whole bar window and eats the next click anywhere else — the exact
    // mechanism ContextMenu.qml already uses. Without it a click meant to close the
    // menu would fall through to whatever pill is underneath.
    MouseArea {
        anchors.fill: parent
        enabled: root.expanded
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: root.close()
    }

    // Escape, and a place to hold focus while open. Bar.qml folds `expanded` into
    // its own WlrKeyboardFocus binding, the same way it already does for the left/
    // right panel Accordions (see escFocus there).
    Item {
        id: escFocus
        anchors.fill: parent
        Keys.onEscapePressed: root.close()
        Connections {
            target: root
            function onExpandedChanged() { if (root.expanded) escFocus.forceActiveFocus() }
        }
    }

    // ── Position: anchored to the clicked icon, not a dock slot ───────────────
    // `anchorItem` lives in this SAME window now (it didn't before — the old
    // PanelWindow needed mapToGlobal and its own top/right margins to reach across
    // window boundaries), so mapping into `root`'s own space is enough on its own.
    // The CENTRE of the icon, not a corner — the menu centres under it below.
    readonly property real _anchorCenterX: root.anchorItem
        ? root.anchorItem.mapToItem(root, root.anchorItem.width / 2, root.anchorItem.height).x : 0
    readonly property real _anchorY: root.anchorItem
        ? root.anchorItem.mapToItem(root, root.anchorItem.width / 2, root.anchorItem.height).y : 0

    Surface {
        id: surface

        // Card, not Popup: elevationPopup resolves to Colors.surfaceHigh, a
        // lighter fill meant for a menu floating ABOVE a card — the wrong tier
        // now that this is welded to the bar like every other panel (BarDock's
        // Card.qml, which those all go through, is flatly Colors.surface; Card
        // itself resolves the same way via the default branch below).
        elevation: Tokens.elevationCard
        // No stroke of its own while welded — the blob's outline is the border.
        // No cast shadow either: a lobe of the bar casts no shadow onto the bar
        // it's made of, same as BarDock's `elevated: !dock.blobWeld`.
        borderWidth: root.blobWeld ? 0 : Tokens.borderWidth
        castsShadow: !root.blobWeld
        // …and no fill while the blob draws the cookie field: the blob's lobe is this same colour.
        fillOpacity: root.blobWeld && Drift.inBlob ? 0 : 1
        // A right-click menu, not a panel — sized like the native ones this
        // replaces (the old PanelWindow was 150), not like a touch-sized popup.
        width: 168

        // Capped at the reserved ceiling — see maxHeight above.
        height: Math.min(column.implicitHeight + Tokens.spacingSm * 2, root.maxHeight)

        // Centred under the icon, clamped so it never crosses either edge of the
        // window (a tray icon near the screen's edge would otherwise centre the
        // menu half off-screen).
        x: Math.max(Tokens.spacingMd,
                     Math.min(root.width - width - Tokens.spacingMd,
                               root._anchorCenterX - width / 2))
        y: Math.max(Tokens.spacingMd,
                     Math.min(root.height - height - Tokens.spacingMd,
                               root._anchorY + Tokens.spacingXs))

        opacity: root.expanded ? Tokens.surfaceOpacity : 0.0
        scale:   root.expanded ? 1.0 : 0.94
        transformOrigin: Item.TopRight

        Behavior on opacity {
            NumberAnimation { duration: Motion.surfaceDuration(root.expanded); easing.type: Motion.surfaceEasing(root.expanded) }
        }
        Behavior on scale {
            NumberAnimation { duration: Motion.surfaceDuration(root.expanded); easing.type: Motion.surfaceEasing(root.expanded) }
        }

        // The card's own content squashes with the blob's spring instead of riding
        // on top of it rigidly — same idiom as BarDock's `transform:` on its card.
        transform: Matrix4x4 { matrix: root.deformMatrix }

        Column {
            id: column
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: Tokens.spacingSm }
            spacing: 0

            Item {
                width:   parent.width
                height:  visible ? 20 : 0
                visible: (root.menuHandle?.title ?? "") !== ""

                StyledText {
                    anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                              leftMargin: Tokens.spacingSm; rightMargin: Tokens.spacingSm }
                    text:    root.menuHandle?.title ?? ""
                    variant: "caption"
                    emphasis: "muted"
                    elide:   Text.ElideRight
                }
            }
            Divider { visible: (root.menuHandle?.title ?? "") !== "" }

            Repeater {
                model: opener.children.values

                Item {
                    id: row
                    required property var modelData
                    readonly property var  entry:     modelData
                    readonly property bool isSep:     entry?.isSeparator ?? false
                    readonly property bool isEnabled: entry?.enabled ?? true
                    readonly property bool hasSub:    entry?.hasChildren ?? false

                    // ── Entries the app asked to hide ──────────────────────────
                    // The DBusMenu protocol lets an app mark an item `visible:
                    // false` (Spotify does this for "Show Spotify" while its window
                    // is already visible) — but QsMenuEntry exposes no `visible`
                    // property to read that back (verified against the installed
                    // qmltypes: isSeparator/enabled/text/icon/buttonType/
                    // checkState/hasChildren, nothing else). What actually happens
                    // is the entry still gets a slot in the list, just with an
                    // empty label — so a genuinely blank, non-separator row is the
                    // only signal there is that this one was meant to be hidden.
                    readonly property bool isBlank:
                        !isSep && (entry?.text ?? "").trim() === "" && (entry?.icon ?? "") === ""

                    width:  column.width
                    height: isBlank ? 0 : (isSep ? Tokens.spacingSm + 1 : 24)
                    visible: !isBlank

                    Divider {
                        visible: row.isSep
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left:  parent.left
                        anchors.right: parent.right
                    }

                    Rectangle {
                        visible: !row.isSep && row.isEnabled && hover.containsMouse
                        anchors.fill: parent
                        radius: Tokens.radiusXs
                        color:  Colors.of(QsWindow.window).stateHoverBg
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    IconImage {
                        id: rowIcon
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: Tokens.spacingMd }
                        implicitSize: 13
                        source:  row.entry?.icon ?? ""
                        visible: !row.isSep && source !== ""
                        opacity: row.isEnabled ? 1.0 : 0.35
                    }

                    StyledText {
                        anchors {
                            // Off the icon's own right edge, not a guessed fixed margin
                            // from parent.left — that guess (spacingXl, 16px) was
                            // SMALLER than where a 13px icon at spacingMd actually ends
                            // (21px), so the label started underneath it. Anchoring to
                            // rowIcon.right can't drift out of sync with its size again.
                            left: rowIcon.visible ? rowIcon.right : parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin:  rowIcon.visible ? Tokens.spacingSm : Tokens.spacingMd
                            rightMargin: row.hasSub ? Tokens.spacingLg : Tokens.spacingMd
                        }
                        visible:  !row.isSep
                        text:     row.entry?.text ?? ""
                        variant:  "label"
                        color:    row.isEnabled ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgFaint
                        opacity:  row.isEnabled ? 1.0 : 0.6
                        elide:    Text.ElideRight
                    }

                    MaterialIcon {
                        visible: row.hasSub && !row.isSep
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: Tokens.spacingSm }
                        name: "chevron_right"
                        font.pixelSize: Tokens.fontCaption
                        color:  Colors.of(QsWindow.window).fgDim
                    }

                    MouseArea {
                        id: hover
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled:      row.isEnabled && !row.isSep
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (row.hasSub) return
                            row.entry?.triggered()
                            root.close()
                        }
                    }
                }
            }
        }
    }
}
