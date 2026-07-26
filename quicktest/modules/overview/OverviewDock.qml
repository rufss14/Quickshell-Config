import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── OverviewDock ──────────────────────────────────────────────────────────────
// The bar along the bottom of the overview:
//
//     [ pinned apps ] │ [ running apps ] │ [ launcher ]
//
// Pinned apps launch. Running apps go to their window (and dismiss the overview). An
// app that is both pinned AND running shows as running rather than appearing twice.
//
// ONE ICON PER APP, wherever its windows live. Hovering it peeks at every one of them
// as a live thumbnail, each labelled with the workspace it's on, and clicking a
// thumbnail focuses THAT window.
//
// ── Interaction ───────────────────────────────────────────────────────────────
//   click        launch (pinned) / go to the app's first window (running)
//   hover        live preview of every window the app has open
//   right-click  pin/unpin · close window · close all windows
//   drag a pin   reorder the pinned strip
//   drag a run.  onto the pinned strip → pins it
//
// The context menu is NOT owned here: it's a single instance living at the overlay's
// top level (see Overview.qml) and handed down. A menu parented inside the dock could
// only ever open *within* the dock — 72px tall, at the bottom of the screen — which is
// exactly where a menu must not be.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    // The shared ContextMenu instance, owned by Overview.
    property var contextMenu: null

    elevation: Tokens.elevationCard

    implicitWidth:  content.implicitWidth + Tokens.spacingXl * 2
    implicitHeight: 72

    readonly property int iconSize: 52
    readonly property int iconGap:  Tokens.spacingSm

    // ── Running apps, grouped by appId ────────────────────────────────────────
    // ONE icon per app, wherever its windows happen to live. The dock used to key on
    // (workspace, appId), so the same app open on three workspaces appeared three
    // times — which is a workspace list wearing a dock's clothes. An app is an app;
    // the fact that two of its windows sit on different workspaces is something you
    // discover when you hover it, not a reason to draw it twice.
    readonly property var running: {
        const seen = {}
        const list = []

        for (let i = 0; i < Hypr.windows.length; i++) {
            const w = Hypr.windows[i]
            if (!w.appClass) continue

            if (seen[w.appClass] !== undefined) {
                list[seen[w.appClass]].windows.push(w)
            } else {
                seen[w.appClass] = list.length
                list.push({ appId: w.appClass, windows: [w] })
            }
        }
        return list
    }

    function groupFor(appId) {
        return root.running.find(g => g.appId === appId) ?? null
    }

    // What the RUNNING strip actually draws: everything running that isn't already
    // pinned.
    //
    // A pinned app was being drawn twice — once in the pinned strip, once again here —
    // which is silly, because a pinned icon is ALREADY a full running icon when the app
    // is up: it gets the group, so it shows the underline, the window count and the live
    // peek. The pin is the app's spot. The running strip is only for things that don't
    // have one.
    readonly property var unpinnedRunning:
        root.running.filter(g => !Pins.isPinned(g.appId))

    function launch(appId) {
        const entry = DesktopEntries.heuristicLookup(appId)
        if (entry) entry.execute()
    }

    // Focus the window. Hyprland brings its workspace along on its own — we don't
    // dispatch a workspace switch of our own.
    function goTo(w) {
        if (!w) return
        Hypr.goToWindow(w.address)
        UiState.overviewOpen = false
    }

    // ── Drag state ────────────────────────────────────────────────────────────
    // `dragPinIndex >= 0` ⇒ a pinned icon is being reordered; `dragTargetSlot` is
    // where it would land. `dragAppId != ""` with dragPinIndex < 0 ⇒ a running icon
    // is being dragged, and dropping it on the pinned strip pins it.
    //
    // ── Why the reorder commits on RELEASE, not live ──────────────────────────
    // The obvious implementation — call Pins.move() each time the cursor crosses a
    // slot, so the strip rearranges under your hand — cannot work here, and fails in
    // a way that looks like a broken mouse rather than a bug.
    //
    // `Pins.move()` assigns a NEW array to `Pins.ids`, which is this Repeater's model.
    // A Repeater over a JS array has no concept of a move: any new array is a full
    // model reset, so it destroys and recreates every delegate — including the very
    // MouseArea that currently holds the mouse grab. The drag would die the instant it
    // crossed its first slot boundary.
    //
    // So the drag is purely visual (a Translate on the icon, which also keeps it out of
    // the Row positioner's way) with an insertion caret showing where it lands, and
    // exactly ONE Pins.move() on release — by which time there is no grab left to lose.
    property int    dragPinIndex:   -1
    property int    dragTargetSlot: -1
    property string dragAppId:      ""
    property bool   overPinStrip:   false

    readonly property bool draggingToPin:
        root.dragAppId !== "" && root.dragPinIndex < 0 && root.overPinStrip

    readonly property bool reorderingPins:
        root.dragPinIndex >= 0 && root.dragTargetSlot >= 0

    function endDrag() {
        root.dragAppId      = ""
        root.dragPinIndex   = -1
        root.dragTargetSlot = -1
        root.overPinStrip   = false
    }

    function pinStripHit(sceneX, sceneY) {
        const p = pinDrop.mapFromItem(null, sceneX, sceneY)
        return p.x >= 0 && p.y >= 0 && p.x <= pinDrop.width && p.y <= pinDrop.height
    }

    // Which pin slot a scene-x lands in.
    function pinSlotAt(sceneX) {
        const p = pinRow.mapFromItem(null, sceneX, 0)
        const slot = root.iconSize + root.iconGap
        return Math.max(0, Math.min(Pins.ids.length - 1, Math.floor(p.x / slot)))
    }

    // ── Context menu ──────────────────────────────────────────────────────────
    // One menu, one connection. Each icon just records who it's for.
    property string menuAppId: ""

    function openMenu(appId, sceneX, sceneY) {
        if (!root.contextMenu) return

        root.menuAppId = appId
        const group = root.groupFor(appId)
        const count = group ? group.windows.length : 0

        const items = [
            Pins.isPinned(appId)
                ? { key: "unpin", glyph: "󰐃", label: "Unpin from dock" }
                : { key: "pin",   glyph: "󰐃", label: "Pin to dock" }
        ]

        if (count > 0) {
            items.push({ separator: true })
            items.push({ key: "focus", glyph: "󰍉", label: "Focus" })
            items.push({ key: "close", glyph: "󰅖", label: "Close window",
                         tint: Colors.danger })
            if (count > 1)
                items.push({ key: "closeAll", glyph: "󰅖",
                             label: "Close all (" + count + ")", tint: Colors.danger })
        } else {
            items.push({ separator: true })
            items.push({ key: "launch", glyph: "󰐊", label: "Launch" })
        }

        root.contextMenu.items = items
        root.contextMenu.openAt(sceneX, sceneY)
    }

    Connections {
        target: root.contextMenu
        enabled: root.contextMenu !== null

        function onTriggered(key) {
            const appId = root.menuAppId
            const group = root.groupFor(appId)

            switch (key) {
                case "pin":    Pins.pin(appId);   break
                case "unpin":  Pins.unpin(appId); break
                case "launch": root.launch(appId); UiState.overviewOpen = false; break
                case "focus":
                    if (group) root.goTo(group.windows[0])
                    break
                case "close":
                    if (group) Hypr.closeWindow(group.windows[0].address)
                    break
                case "closeAll":
                    // Snapshot the addresses first: `group.windows` is derived from
                    // Hypr.windows, and closing the first one re-derives the list out
                    // from under the loop.
                    if (group) {
                        const addrs = group.windows.map(w => w.address)
                        for (let i = 0; i < addrs.length; i++)
                            Hypr.closeWindow(addrs[i])
                    }
                    break
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    Row {
        id: content
        anchors.centerIn: parent
        spacing: Tokens.spacingLg

        // ── Pinned ────────────────────────────────────────────────────────────
        // The drop zone is wider than the icons themselves, so dragging a running
        // app "at" the strip doesn't demand pixel accuracy — and it stays targetable
        // when there are no pins at all.
        Item {
            id: pinDrop
            anchors.verticalCenter: parent.verticalCenter

            width: Math.max(pinRow.implicitWidth, root.dragAppId !== "" ? 64 : 0)
            height: root.iconSize + Tokens.spacingSm * 2
            visible: Pins.ids.length > 0 || root.dragAppId !== ""

            Rectangle {
                anchors.fill: parent
                anchors.margins: -Tokens.spacingSm
                radius: Tokens.radiusSm
                color: root.draggingToPin ? Colors.alpha(Colors.primary, 0.18) : "transparent"
                border.width: root.draggingToPin ? Tokens.borderWidth : 0
                border.color: Colors.primary
                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }

            // Insertion caret — where the dragged pin will land. It has to live in
            // pinDrop rather than in pinRow: pinRow is a positioner and would lay the
            // caret out as if it were another icon.
            Rectangle {
                visible: root.reorderingPins

                x: pinRow.x + root.dragTargetSlot * (root.iconSize + root.iconGap) - 2
                anchors.verticalCenter: parent.verticalCenter

                width: 3
                height: root.iconSize
                radius: 2
                color: Colors.primary

                Behavior on x { NumberAnimation { duration: Motion.fast; easing.type: Motion.travel } }
            }

            Row {
                id: pinRow
                anchors.centerIn: parent
                spacing: root.iconGap

                Repeater {
                    model: Pins.ids

                    DockIcon {
                        required property var modelData
                        required property int index

                        appId:    modelData
                        pinIndex: index

                        // A pinned app that's running is shown as running — you want
                        // to switch to it, not launch a second copy.
                        group: root.groupFor(modelData)

                        onActivated: {
                            if (group) root.goTo(group.windows[0])
                            else {
                                root.launch(appId)
                                UiState.overviewOpen = false
                            }
                        }
                    }
                }
            }
        }

        // Hides when there's nothing on the far side of it, rather than dangling.
        Rectangle {
            visible: pinDrop.visible && root.unpinnedRunning.length > 0
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 38
            color: Colors.alpha(Colors.fg, 0.15)
        }

        // ── Running (unpinned only) ───────────────────────────────────────────
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.iconGap

            Repeater {
                model: root.unpinnedRunning

                DockIcon {
                    required property var modelData

                    appId: modelData.appId
                    group: modelData

                    onActivated: root.goTo(modelData.windows[0])
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 38
            color: Colors.alpha(Colors.fg, 0.15)
        }

        // ── Launcher ──────────────────────────────────────────────────────────
        // Power and the calendar used to live here as panel toggles. They're on the
        // overlay itself now, so all that's left is "show me every app".
        PanelButton {
            anchors.verticalCenter: parent.verticalCenter
            variant: "ghost"
            implicitWidth:  42
            implicitHeight: 42
            glyph: "󰀻"                                    // 󰀻 apps
            onActivated: {
                UiState.overviewOpen = false
                UiState.activeScreen = null
                UiState.launcherOpen = true
            }
        }
    }

    // ── DockIcon ──────────────────────────────────────────────────────────────
    component DockIcon: Item {
        id: icon

        property string appId: ""
        property var    group: null            // null ⇒ pinned but not running
        property int    pinIndex: -1           // ≥0 ⇒ lives in the pinned strip

        signal activated()

        readonly property bool isRunning: icon.group !== null
        readonly property int  count:     icon.group ? icon.group.windows.length : 0

        // Object identity, not appId string — see the header.
        readonly property bool isFocused:
            icon.group ? icon.group.windows.some(w => w.toplevel?.activated ?? false)
                       : false

        readonly property bool dragging: root.dragAppId === icon.appId
                                      && (icon.pinIndex < 0) === (root.dragPinIndex < 0)

        readonly property string iconPath: Icons.pathForAppId(icon.appId)
        readonly property bool   showList: (hover.hovered || popupHover.hovered)
                                        && !icon.dragging
                                        && root.dragAppId === ""

        width:  root.iconSize
        height: root.iconSize

        // The dragged icon must paint over its neighbours as it passes them.
        z: icon.dragging ? 100 : (icon.showList ? 50 : 0)

        // ── Drag offset ───────────────────────────────────────────────────────
        // A TRANSFORM, not `x`. These icons live in a Row, and a Row is a positioner
        // that owns its children's `x` — binding x here would just fight it. A
        // Translate moves the rendered item without touching the layout at all.
        //
        // No Behavior: this tracks the cursor, and easing a value the user is
        // physically holding reads as lag. (Same rule as OverviewWindow and the bar.)
        property real dragDX: 0

        transform: Translate { x: icon.dragging ? icon.dragDX : 0 }

        HoverHandler { id: hover }

        // ── Fill ──────────────────────────────────────────────────────────────
        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: icon.isFocused  ? Colors.alpha(Colors.focus, 0.20)
                 : hover.hovered   ? Colors.stateHoverBg
                 : "transparent"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        // ── Glyph fallback ────────────────────────────────────────────────────
        // A GLYPH, not a fallback icon NAME: "application-x-executable" isn't in this
        // icon theme, so asking for it just trades one missing-icon warning for another.
        StyledText {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            visible: icon.iconPath === ""
            text: "󰬉"
            color: Colors.fgMuted
            font.pixelSize: 30
            opacity: icon.isRunning ? 0.9 : 0.5
        }

        Image {
            id: img
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -4
            visible: icon.iconPath !== ""
            source: icon.iconPath
            width:  32
            height: 32
            sourceSize: Qt.size(32, 32)
            fillMode: Image.PreserveAspectFit
            smooth: true

            // A pinned-but-not-running app is dimmed: it's a thing you can start,
            // not a thing you can switch to.
            opacity: icon.isRunning ? 1.0 : 0.55
            scale: icon.dragging ? 1.15 : hover.hovered ? 1.10 : 1.0

            Behavior on scale   { NumberAnimation { duration: Motion.respond; easing.type: Easing.OutBack } }
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        }

        // ── Running / focused underline ───────────────────────────────────────
        // Replaces the old per-window dot row. A focused app gets a wide accent bar;
        // a running one a short muted stub; a pinned-only app nothing at all. Width
        // carries the state, so it survives `focus` and `primary` being near-identical
        // on a low-contrast pywal ramp.
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4

            width: icon.isFocused ? 22 : icon.isRunning ? 8 : 0
            height: 3
            radius: 2

            color: icon.isFocused ? Colors.focus : Colors.alpha(Colors.fg, 0.45)

            Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
            Behavior on color { ColorAnimation  { duration: Motion.respond } }
        }

        // ── Window count ──────────────────────────────────────────────────────
        // Replaces the workspace badge. The dock no longer splits an app by workspace,
        // so "which workspace" is not a property of the ICON any more — it belongs to
        // each individual window, and each window says so on its own preview.
        Badge {
            visible: icon.count > 1
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 2
            label: "" + icon.count
            tint:  icon.isFocused ? Colors.focus : Colors.fgMuted
            filled: icon.isFocused
        }

        // ── Hover popup: name + one row per window ────────────────────────────
        // The gap between the icon and the popup is INSIDE the hover item, not an
        // anchors margin — a margin would be a dead zone the cursor crosses on its way
        // to the popup, and the popup would vanish just as you reached for it.
        Item {
            id: popupHost

            anchors.bottom: parent.top
            anchors.horizontalCenter: parent.horizontalCenter

            width:  popup.width
            height: popup.height + Tokens.spacingSm

            // Stays alive while the popup fades OUT — a hard `visible: icon.showList`
            // here would yank it off screen and there'd be no exit animation to see.
            visible: popup.opacity > 0.01

            HoverHandler { id: popupHover }

            // ── Windows 11-style peek ─────────────────────────────────────────
            // One LIVE thumbnail per window, side by side, each clickable — so you
            // pick the window by looking at it rather than by reading a title. Middle-
            // click closes one straight from the peek.
            //
            // The captures only exist while this popup is on screen: the Repeater has
            // no model unless the popup is showing, so hovering a dock icon is what
            // starts the capture, and moving away tears it down. A dock that held a
            // live capture open for every running window would be paying for a dozen
            // screencopy streams to show nothing.
            Surface {
                id: popup

                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter

                elevation: Tokens.elevationPopup
                cornerRadius: Tokens.radiusSm

                // Accent-lit and animated in. It's a peek you summoned by pointing at
                // something — it should arrive, not simply be there.
                focused: true

                opacity: icon.showList ? Tokens.surfaceOpacity : 0
                scale:   icon.showList ? 1.0 : 0.94
                transformOrigin: Item.Bottom

                Behavior on opacity {
                    NumberAnimation {
                        duration: Motion.surfaceDuration(icon.showList)
                        easing.type: Motion.surfaceEasing(icon.showList)
                    }
                }
                Behavior on scale {
                    NumberAnimation {
                        duration: Motion.surfaceDuration(icon.showList)
                        easing.type: Motion.surfaceEasing(icon.showList)
                    }
                }

                // Big enough to actually recognise a window by. The first pass used
                // 168×100, which reads as a blurry stamp — a peek you have to squint at
                // is no better than the title list it replaced.
                readonly property int thumbW: 260
                readonly property int thumbH: 150

                width:  Math.ceil(popupCol.implicitWidth)  + Tokens.spacingMd * 2
                height: Math.ceil(popupCol.implicitHeight) + Tokens.spacingMd * 2

                Column {
                    id: popupCol
                    anchors.top:  parent.top
                    anchors.left: parent.left
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: Icons.nameForAppId(icon.appId)
                        variant: "label"
                        font.bold: true
                    }

                    StyledText {
                        visible: !icon.isRunning
                        text: "Not running  ·  click to launch"
                        variant: "caption"
                        emphasis: "dim"
                    }

                    Row {
                        spacing: Tokens.spacingSm

                        Repeater {
                            // Empty unless the peek is actually on screen — see above.
                            //
                            // Keyed to the HOST's visibility, not to `showList`: showList
                            // drops the moment the cursor leaves, and gating the captures
                            // on it would empty the card of thumbnails and then fade an
                            // empty box out. This keeps them alive for the exit.
                            model: (popupHost.visible && icon.group) ? icon.group.windows : []

                            Item {
                                id: peek
                                required property var modelData

                                readonly property bool isActive: modelData.toplevel?.activated ?? false

                                width:  popup.thumbW
                                height: popup.thumbH + 18

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Tokens.radiusXs
                                    color: peekHover.containsMouse ? Colors.alpha(Colors.fg, 0.12)
                                         : peek.isActive           ? Colors.alpha(Colors.focus, 0.16)
                                         : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                }

                                // The live capture, rounded by a mask — a ScreencopyView
                                // paints a raw texture and has no radius of its own.
                                //
                                // `smooth` and `mipmap` matter here: this is a 1920×1080
                                // window being shrunk to thumbnail size, and a naive
                                // downscale point-samples it — which is what made the
                                // first previews look cheap and shimmery rather than
                                // merely small.
                                Item {
                                    id: shot
                                    anchors.top: parent.top
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    anchors.topMargin: 2
                                    width:  popup.thumbW - 8
                                    height: popup.thumbH - 6

                                    layer.enabled: true
                                    layer.smooth: true
                                    layer.mipmap: true
                                    layer.effect: MultiEffect {
                                        maskEnabled: true
                                        maskSource: peekMask
                                        maskThresholdMin: 0.5
                                        maskSpreadAtMin: 1.0
                                    }

                                    ScreencopyView {
                                        anchors.fill: parent
                                        captureSource: peek.modelData.wayland
                                        live: true
                                        smooth: true
                                    }
                                }

                                Item {
                                    id: peekMask
                                    anchors.fill: shot
                                    visible: false
                                    layer.enabled: true
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Tokens.radiusXs
                                        color: "white"
                                    }
                                }

                                Rectangle {
                                    anchors.fill: shot
                                    color: "transparent"
                                    radius: Tokens.radiusXs
                                    border.width: Tokens.borderWidth
                                    border.color: peek.isActive ? Colors.focus
                                                                : Colors.outlineNested
                                    Behavior on border.color { ColorAnimation { duration: Motion.respond } }
                                }

                                // Now that one icon covers every workspace, "which
                                // workspace is this one on" is a property of the WINDOW,
                                // so each preview carries its own.
                                Badge {
                                    anchors.top:   shot.top
                                    anchors.right: shot.right
                                    anchors.margins: 4
                                    label: "" + peek.modelData.workspaceId
                                    tint:  peek.isActive ? Colors.focus : Colors.fgMuted
                                    filled: true
                                }

                                StyledText {
                                    anchors.bottom: parent.bottom
                                    anchors.left:   parent.left
                                    anchors.right:  parent.right
                                    anchors.leftMargin:  4
                                    anchors.rightMargin: 4
                                    horizontalAlignment: Text.AlignHCenter
                                    text: peek.modelData.title !== ""
                                        ? peek.modelData.title
                                        : Icons.nameForAppId(icon.appId)
                                    variant: "caption"
                                    emphasis: peek.isActive ? "normal" : "muted"
                                    elide: Text.ElideRight
                                }

                                MouseArea {
                                    id: peekHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                    onClicked: function(m) {
                                        if (m.button === Qt.MiddleButton)
                                            Hypr.closeWindow(peek.modelData.address)
                                        else
                                            root.goTo(peek.modelData)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Click / right-click / drag ────────────────────────────────────────
        MouseArea {
            id: mouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: icon.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

            // SCENE coordinates. An item-relative delta fights itself once the item
            // starts moving — the same trap already fixed in OverviewWindow.
            property real pressSceneX: 0
            property bool moved: false

            onPressed: function(m) {
                pressSceneX = mapToItem(null, m.x, m.y).x
                moved = false
            }

            onPositionChanged: function(m) {
                if (!pressed || m.buttons !== Qt.LeftButton) return

                const s = mapToItem(null, m.x, m.y)

                if (!moved) {
                    if (Math.abs(s.x - pressSceneX) < 8) return    // slop
                    moved = true
                    root.dragAppId    = icon.appId
                    root.dragPinIndex = icon.pinIndex
                }

                icon.dragDX = s.x - pressSceneX

                if (icon.pinIndex >= 0) {
                    // Only WHERE it would land. The list itself is not touched until
                    // release — mutating it now would reset the Repeater and destroy
                    // this very MouseArea mid-grab. See the drag-state header.
                    root.dragTargetSlot = root.pinSlotAt(s.x)
                } else {
                    root.overPinStrip = root.pinStripHit(s.x, s.y)
                }
            }

            onReleased: function(m) {
                if (mouse.moved) {
                    if (icon.pinIndex >= 0) {
                        // The one and only mutation of the pin list.
                        if (root.dragTargetSlot >= 0 && root.dragTargetSlot !== icon.pinIndex)
                            Pins.move(icon.pinIndex, root.dragTargetSlot)
                    } else if (root.overPinStrip) {
                        // A running app dropped on the pinned strip ⇒ pin it.
                        Pins.pin(icon.appId)
                    }

                    icon.dragDX = 0
                    mouse.moved = false
                    root.endDrag()
                    return
                }

                if (m.button === Qt.RightButton) {
                    const s = mapToItem(null, m.x, m.y)
                    root.openMenu(icon.appId, s.x, s.y)
                } else if (m.button === Qt.MiddleButton) {
                    if (icon.group) Hypr.closeWindow(icon.group.windows[0].address)
                } else {
                    icon.activated()
                }
            }

            // The grab can be taken away without a release — the overview closing, a
            // window vanishing under the cursor. Without this the dock would be left
            // believing a drag is still in progress: caret showing, icon translated,
            // hover popups suppressed, and no way back.
            onCanceled: {
                icon.dragDX = 0
                mouse.moved = false
                root.endDrag()
            }
        }
    }
}
