import QtQuick
import Quickshell
import QtQuick.Effects
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── OverviewWindow ────────────────────────────────────────────────────────────
// One window, drawn to scale as a LIVE capture, and draggable between workspaces.
//
// ── Why this is a plain QML drag now ──────────────────────────────────────────
// The previous two versions hand-rolled the drag: scene-coordinate deltas folded
// into the x/y binding, a `z` fight to escape the parent cell, offsets reset on
// release. All of that existed to work around ONE mistake — previews were children
// of their workspace cell, so a drag had to smuggle the item out of its own parent.
//
// They aren't any more. Every preview lives in a single layer spanning the whole
// grid (see WorkspaceGrid), positioned at `origin` (its cell's corner) plus its real
// geometry. A window can therefore just... move, and the drag is the one QML gives
// you for free: `drag.target`, with a DropArea per cell telling us where it landed.
//
// ── x/y are assigned, not bound ───────────────────────────────────────────────
// `drag.target` WRITES x and y, which destroys any binding on them. So x/y are set
// imperatively and re-applied whenever the underlying geometry changes — a binding
// would work exactly once and then silently stop tracking Hyprland forever.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var  window         // an entry from Hypr.windows
    required property real previewScale   // logical px → preview px
    required property real originX        // top-left of this window's workspace cell
    required property real originY
    // The box its workspace is drawn in ({ w, h }, WorkspaceGrid.previewSizeFor): the
    // preview stays inside it (Hypr.previewRect).
    property var fit: ({ w: 1, h: 1 })

    // Which monitor's grid this preview lives on — the grid's own `monitor`, handed
    // straight through. See Hypr.goToWindow()'s `originMonitor` for why a click needs
    // this rather than asking Hyprland which monitor is "current".
    property var monitor: null

    // Which workspace the cursor is currently over, fed down from the grid.
    property int dropTarget: -1

    property int cornerRadius: Tokens.radiusSm

    // Alt+Tab's / the search's pick: lifted, ringed in `focus`, and its label shown
    // (with `ago`, when you last left it). While something else is picked this one
    // `recedes`; a window a search didn't find is `faded` further back.
    property bool picked: false
    // In the selection (Ctrl+click, Switcher.marks): ringed in `primary`, with a tick on the corner.
    property bool marked: false
    property bool receded: false
    property bool faded: false
    property string ago: ""

    // Open the tooltip downward instead of upward. The grid sets this for the bottom
    // row (workspaces 6-10), where an upward tooltip would point out of the cell and
    // land on top of the row above.
    property bool tipBelow: false

    signal requestMove(int target)
    // Ctrl is held during the drag (see the MouseArea).
    property bool swapping: false
    // Ctrl toggled on (Overview): every click and drag counts as Ctrl-held. `ctrlUsed` tells the
    // overview a real Ctrl was for this (so its release is not a tap).
    property bool ctrlMode: false
    signal ctrlUsed()
    signal dragFinished()

    // Announced when a drag actually begins, so the grid can work out where this window
    // will land and draw a ghost there.
    //
    // The offsets are the window's position within its own cell. That is where it ends
    // up only if it's FLOATING (Hyprland keeps a floating window's geometry across a
    // workspace change) or if it lands somewhere empty. A tiled window dropped into an
    // occupied workspace gets re-tiled, so `floating` tells the grid which of those it
    // is — see WorkspaceGrid.predictedSlot().
    signal dragBegan(real offsetX, real offsetY, real w, real h, bool floating)

    // ── geom is CACHED, and only republished when a value actually changed ────
    // This was `readonly property var geom: Hypr.geometryOf(root.window.toplevel)`,
    // and it was the overview's hottest path.
    //
    // geometryOf() builds a NEW object every call, and the binding depended on the
    // toplevel's `lastIpcObject` — which Hypr's refresh loop rewrites on EVERY
    // toplevel four times a second while the overview is open, moved or not. A fresh
    // object is never equal to the last one, so `geomChanged` fired 4×/s per visible
    // preview and dragged everything downstream with it: width, height, initX, initY,
    // and — the expensive one — `iconPath`, a full desktop-entry heuristic lookup plus
    // icon-theme probes, per window, four times a second, to arrive at the same string.
    //
    // Freshness is deliberately UNCHANGED: this still updates from `lastIpcObject` the
    // moment a refresh lands, so a window moving on the real desktop tracks exactly as
    // promptly as before. Reading Hypr.windows instead would have been simpler and
    // would have cost a refresh cycle of lag (rebuild() runs before the refresh it just
    // asked for has come back), which is a visible regression on a dragged window.
    // What changed is only that an unchanged geometry no longer notifies.
    // The fallback in `geom` is not belt-and-braces, it is load-bearing. Seeding `_geom`
    // with a placeholder instead would mean the preview existed, for however many frames
    // it took the first refresh to run, at a stub size — and `Behavior on width/height`
    // is live by then, so every preview would visibly animate up from a stub on creation.
    // Falling back to a direct read means `geom` is correct on its very first evaluation,
    // with no dependence on whether windowChanged happens to fire before completion.
    //
    // Once `_geom` is non-null the fallback stops being evaluated, and QML re-captures
    // dependencies on every pass — so the binding drops `lastIpcObject` at that point and
    // tracks only `_geom`. The churn is gone from the second evaluation onward.
    property var _geom: null
    readonly property var geom: root._geom ?? Hypr.geometryOf(root.window?.toplevel)

    function _refreshGeom() {
        const g = Hypr.geometryOf(root.window?.toplevel)
        const p = root._geom
        if (p !== null
            && g.x === p.x && g.y === p.y
            && g.width === p.width && g.height === p.height
            && g.appClass === p.appClass && g.floating === p.floating
            && g.xwayland === p.xwayland && g.fullscreen === p.fullscreen)
            return
        root._geom = g
    }

    // `lastIpcObject` is the signal geometry actually arrives on; `window` changing
    // means this delegate was pointed at a different toplevel entirely. The Connections
    // target re-binds itself when that happens, but it does not re-fire, so the
    // handler below covers the swap.
    Connections {
        target: root.window?.toplevel ?? null
        function onLastIpcObjectChanged() { root._refreshGeom() }
    }
    onWindowChanged: root._refreshGeom()
    Component.onCompleted: root._refreshGeom()

    readonly property int workspaceId: root.window.workspaceId

    readonly property var _mon: root.window.monitor

    // Where the window belongs: its cell's corner, plus its position on the monitor
    // (less the monitor origin and the reserved edges — our bar — or every preview
    // sits offset downward by the height of the bar), kept inside its cell's box. A
    // fullscreen window fills the box: it also covers the bar, so at its own size it
    // spilled past the cell (Hypr.previewRect).
    readonly property var rect: Hypr.previewRect(root.geom, root._mon, root.previewScale, root.fit)
    readonly property real initX: originX + root.rect.x
    readonly property real initY: originY + root.rect.y

    // Visual state: true only once the drag threshold is actually crossed, so a plain
    // click doesn't shrink the preview.
    readonly property bool dragging: dragArea.drag.active

    onDraggingChanged: {
        if (dragging)
            root.dragBegan(root.initX - root.originX, root.initY - root.originY,
                           root.width, root.height, root.geom.floating)
    }

    // The window in your hand keeps the size it was picked up at: the grid opens out to
    // all ten workspaces during a drag (WorkspaceGrid `slots`), and the cells shrink — a
    // preview snapping smaller under the pointer read as the drag stuttering. It takes
    // its new size (animated) once it's let go.
    property real _heldW: 8
    property real _heldH: 8
    onWidthChanged: if (!root.dragging) root._heldW = root.width
    onHeightChanged: if (!root.dragging) root._heldH = root.height
    width:  root.dragging ? root._heldW : Math.max(8, root.rect.w)
    height: root.dragging ? root._heldH : Math.max(8, root.rect.h)

    // While ANOTHER window is being dragged the grid re-lays itself out; then everything
    // glides there without overshoot (`calm`), saving the spring for a window landing.
    property bool calm: false
    readonly property var _curve: root.calm ? Motion.emphasizedDecel : Motion.spring

    // ── x/y are BOUND, and re-bound after every drag ──────────────────────────
    // `drag.target` writes x and y directly, which destroys the binding — permanently.
    // Patching that up with `onInitXChanged: x = initX` only papers over it: that fires
    // only when initX happens to CHANGE, so any other reason the preview should move (a
    // grid rescale, delegates reshuffling as a window closes and every index shifts) left
    // it stranded wherever the drag dropped it. That's the "sometimes doesn't snap back"
    // — it wasn't random, it was every case except the one I handled.
    //
    // rebind() puts the real binding back with Qt.binding(), so the preview tracks its
    // window again for good, and the Behavior below animates it home.
    x: initX
    y: initY

    function rebind() {
        root.x = Qt.binding(() => root.initX)
        root.y = Qt.binding(() => root.initY)
    }

    // Glide home, or into a new cell after a move — but never while the cursor is
    // holding it, or the preview would ease toward the pointer instead of tracking it,
    // which reads as lag.
    //
    // `spatial`, not `standard`: this is an object CROSSING the grid. At 150ms it
    // arrived before the eye could follow it and the move read as a cut rather than as
    // movement — which is most of why the shell felt abrupt next to the old overview.
    // Size animates too, since a window changing workspace usually changes shape.
    //
    // `Motion.spring`, not `emphasizedDecel` — same reasoning as BarDock's resize-drag
    // release: decel-only has no overshoot to settle back FROM, so the preview coming
    // to rest read as a hard stop rather than a landing. This is a window arriving
    // after being physically dragged; it should pass its resting place and settle,
    // the way the dock card does.
    Behavior on x      { enabled: !root.dragging; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: root._curve } }
    Behavior on y      { enabled: !root.dragging; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: root._curve } }
    Behavior on width  { enabled: !root.dragging; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: root._curve } }
    Behavior on height { enabled: !root.dragging; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: root._curve } }

    z: dragging ? 1000 : root.picked ? 20 : (hover.hovered ? 10 : 1)

    // ── Drag.active is driven BY HAND. Do not bind it. ────────────────────────
    // This was `Drag.active: dragArea.drag.active`, and that one line is why dropping
    // a window did nothing at all:
    //
    //   release → drag.active goes false → the DropArea under the cursor fires
    //   onExited → the grid clears dropTarget to -1 → and only THEN does onReleased
    //   run, read dropTarget, find -1, and conclude the window was dropped on nothing.
    //
    // The drop target is destroyed by the very event we need it for. So the release
    // handler reads the target FIRST and lowers Drag.active itself, afterwards.
    property bool dragActive: false

    Drag.active: root.dragActive
    Drag.source: root

    HoverHandler { id: hover }

    // The pick's halo — the grid cell's own glow, hugging this window.
    OverviewGlow {
        anchors.centerIn: parent
        circular: false
        contentWidth: root.width
        contentHeight: root.height
        contentRadius: root.cornerRadius
        accent: Colors.of(QsWindow.window).primary
        active: root.picked && !root.dragging
    }

    // A lift of `f` of the size, but never more than a few px a side: a preview as big as its cell
    // would otherwise grow into the next one (the gap is the grid's `gap`).
    function lift(f) { return 1 + Math.min(f, (Tokens.spacingSm * 2) / Math.max(1, Math.min(root.width, root.height))) }

    // ── Content ───────────────────────────────────────────────────────────────
    Item {
        id: content
        anchors.fill: parent

        // Shrinks while held, so the ghost, the grid and the windows underneath stay
        // visible past the thing in your hand. The curve is the fast expressive one —
        // this is a scale, not a journey.
        // M3E spring (SpringValue). Grabbing takes the effects spring (no overshoot: an acknowledgement),
        // letting go / a pick / a hover the fast spatial one, which carries a little past and settles.
        SpringValue {
            id: scaleSpring
            target: root.dragging ? 0.82 : root.picked ? root.lift(0.06) : hover.hovered ? root.lift(0.025) : 1.0
            spec: root.dragging ? Motion.springEffectsFast : Motion.springSpatialFast
            epsilon: 0.001
        }
        scale:   scaleSpring.value
        opacity: root.dragging ? 0.92 : root.faded ? 0.22 : root.receded ? 0.55 : 1.0

        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        readonly property string iconPath: Icons.pathForAppId(root.geom.appClass)
        readonly property int iconPx: Math.round(
            Math.min(root.width, root.height) * (Math.min(root.width, root.height) < 90 ? 0.45 : 0.25))

        // The live capture, rounded. A ScreencopyView paints a raw texture and has no
        // radius of its own, so the corner has to be cut with a mask.
        Item {
            anchors.fill: parent

            layer.enabled: true
            layer.smooth: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: shotMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }

            // Mipmapped from a bigger copy: drawn this small, a plain capture shimmers.
            SharpCapture {
                id: shot
                anchors.fill: parent
                captureSource: UiState.overviewOpen ? root.window.wayland : null
                // Live only where the eye is (hovered, picked, selected, in hand, or on the workspace you are on),
                // and until the first frame has landed: every other preview holds its last frame, so ten windows
                // are not all being copied at the monitor's rate for a screen that mostly sits still.
                live: !shot.hasContent || hover.hovered || root.picked || root.marked || root.dragging
                      || root.workspaceId === Hypr.focusedWorkspaceId
            }
        }

        Item {
            id: shotMask
            anchors.fill: parent
            visible: false
            layer.enabled: true
            Rectangle {
                anchors.fill: parent
                radius: root.cornerRadius
                color: "white"
            }
        }

        // The outline sits ON TOP of the capture — a border inside the masked item
        // would be masked away with everything else.
        Rectangle {
            anchors.fill: parent
            color: "transparent"
            radius: root.cornerRadius
            border.width: root.dragging || root.picked || root.marked ? 2 : Tokens.borderWidth
            border.color: root.dragging ? Colors.of(QsWindow.window).primary
                        : root.picked ? Colors.of(QsWindow.window).focus
                        : root.marked ? Colors.of(QsWindow.window).primary
                        : hover.hovered ? Colors.of(QsWindow.window).outlineFocus
                        : Colors.of(QsWindow.window).outlineNested
            Behavior on border.color { ColorAnimation { duration: Motion.respond } }
        }

        // App icon — a capture can be a mostly-empty window, and at thumbnail size the
        // icon is what actually identifies it.
        //
        // Falls back to a GLYPH, not a fallback icon NAME: "application-x-executable"
        // isn't in this icon theme, so asking for it just trades one missing-icon
        // warning for another.
        Image {
            anchors.centerIn: parent
            visible: content.iconPath !== ""
            source:  content.iconPath
            width:   content.iconPx
            height:  content.iconPx
            sourceSize: Qt.size(content.iconPx, content.iconPx)
            fillMode: Image.PreserveAspectFit
            smooth: true
            opacity: 0.8
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: content.iconPath === ""
            glyph: "󰣆"
            color: Colors.of(QsWindow.window).fgMuted
            font.pixelSize: content.iconPx
            opacity: 0.8
        }

        // Making sound: a speaker on the bottom-left corner (the app's playback stream — the same fact `is:audio` reads).
        Item {
            id: audioBadge
            readonly property int size: Tokens.iconXl - Tokens.spacingXs
            readonly property bool on: Audio.streamsFor(root.geom.appClass).length > 0
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingSm
            width: size
            height: size
            opacity: audioBadge.on ? 1 : 0
            visible: opacity > 0.01
            SpringValue { id: audioPop; target: audioBadge.on ? 1 : 0.5; spec: Motion.springSpatialFast; epsilon: 0.002 }
            scale: audioPop.value
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            MorphShape {
                anchors.fill: parent
                shape: "circle"
                fillColor: Colors.of(QsWindow.window).primaryContainer
                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.4)
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: "volume_up"
                fill: 1
                color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                font.pixelSize: Tokens.iconSm
            }
        }

        // In the selection: a tick on the bottom-right corner (the app's icon is the centred one).
        Item {
            readonly property int size: Tokens.iconXl - Tokens.spacingXs
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: Tokens.spacingSm
            width: size
            height: size
            opacity: root.marked ? 1 : 0
            visible: opacity > 0.01
            SpringValue {
                id: tickPop
                target: root.marked ? 1 : 0.5
                spec: Motion.springSpatialFast
                epsilon: 0.002
            }
            scale: tickPop.value
            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            // An M3E cookie, not a plain disc: the selection mark is the same family as the rest.
            MorphShape {
                anchors.fill: parent
                shape: "cookie9"
                fillColor: Colors.of(QsWindow.window).primary
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: "check"
                color: Colors.of(QsWindow.window).primary.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg
                font.pixelSize: Tokens.iconMd
            }
        }

    }

    // ── Tooltip ───────────────────────────────────────────────────────────────
    // A real floating tooltip, OUTSIDE `content` and above the preview.
    //
    // This was an 18px strip pinned inside the preview at 8px type — which at a 0.16
    // scale is unreadable, and on a small window covered most of the thumbnail. It can
    // float free now: previews all live in one flat layer over the grid, so a tooltip
    // can overhang its cell without being clipped by anything.
    Rectangle {
        id: tip

        // On hover, and always on the pick — Alt+Tab's label.
        readonly property bool shown: (hover.hovered || root.picked) && !root.dragging

        // ── Positioned with `y`, NOT with conditional anchors ─────────────────
        // This was:
        //     anchors.bottom: tipBelow ? undefined : parent.top
        //     anchors.top:    tipBelow ? parent.bottom : undefined
        //
        // …and it's why the tooltip sometimes appeared in the middle of the window.
        // The two bindings don't re-evaluate atomically, so as `tipBelow` flips there
        // is a moment where BOTH anchors are set (over-constrained — Qt stretches the
        // item between them) or NEITHER is (the anchor is dropped and y falls back to
        // 0). Either way it lands somewhere it was never meant to be.
        //
        // A plain y binding has one value at all times and cannot be caught half-way.
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.tipBelow ? root.height + Tokens.spacingSm
                         : -tip.height - Tokens.spacingSm

        // Never narrower than the label, never wider than a grid cell's worth of room.
        width:  Math.min(360, tipRow.implicitWidth + Tokens.spacingLg * 2)
        height: 28
        radius: Tokens.radiusSm

        color: root.picked ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, Colors.of(QsWindow.window).focus, 0.12) : Colors.of(QsWindow.window).surfaceHigh
        border.width: root.picked ? Tokens.borderWidth + 1 : Tokens.borderWidth
        border.color: root.picked ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).outlineFocus

        visible: opacity > 0.01
        opacity: tip.shown ? 1 : 0
        scale:   tip.shown ? 1 : 0.92
        // Grow out of the edge nearest the window, whichever side it's on.
        transformOrigin: root.tipBelow ? Item.Top : Item.Bottom
        z: 100

        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
        Behavior on scale   { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }

        Row {
            id: tipRow
            anchors.centerIn: parent
            spacing: Tokens.spacingSm

            Image {
                anchors.verticalCenter: parent.verticalCenter
                visible: content.iconPath !== ""
                source:  content.iconPath
                width:   Tokens.iconSm
                height:  Tokens.iconSm
                sourceSize: Qt.size(Tokens.iconSm, Tokens.iconSm)
                fillMode: Image.PreserveAspectFit
                smooth: true
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 230)
                text: root.window.title !== "" ? root.window.title
                                               : Icons.nameForAppId(root.geom.appClass)
                variant: "label"
                font.weight: root.picked ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.ago !== ""
                text: "·  " + root.ago
                variant: "caption"
                emphasis: "dim"
            }
        }
    }

    // Close, on hover.
    PanelButton {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 3
        implicitHeight: 18
        implicitWidth:  18
        variant: "ghost"
        glyph: "󰅖"
        glyphTint: Colors.of(QsWindow.window).danger
        accent: Colors.of(QsWindow.window).danger
        visible: hover.hovered && !root.dragging && root.width > 60
        onActivated: Hypr.closeWindow(root.window.address)
    }

    // ── Drag / click ──────────────────────────────────────────────────────────
    MouseArea {
        id: dragArea
        anchors.fill: parent
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

        drag.target: root
        drag.smoothed: false      // follow the cursor exactly; smoothing reads as lag

        // Ctrl held while it's dragged: dropped on another window, the two SWAP workspaces
        // (WorkspaceGrid `swapMode`) — read off each move, as the modifiers come with it.
        onPositionChanged: function (m) {
            root.swapping = root.dragging && (root.ctrlMode || (m.modifiers & Qt.ControlModifier) !== 0)
            if (root.swapping && (m.modifiers & Qt.ControlModifier)) root.ctrlUsed()
        }

        onPressed: function(m) {
            // Right: inspect it (the island turns to it) — never a drag.
            if (m.button === Qt.RightButton) {
                Switcher.selectAddress(root.window.address)
                m.accepted = false          // not grabbed, so no drag follows
                return
            }
            // The hotspot is what the DropArea actually tests, and it defaults to the
            // item's TOP-LEFT CORNER. On a preview a couple of hundred pixels wide that
            // corner can sit in a different workspace from the cursor — so you'd drop
            // onto a cell you were never pointing at. Anchor it to the grab point.
            root.Drag.hotSpot = Qt.point(m.x, m.y)
            root.dragActive = true
        }

        onReleased: {
            // ── Everything that READS drop state happens before the teardown ──
            // Lowering Drag.active is what makes the DropArea fire onExited, and that
            // handler clears the whole drop resolution — the target workspace, the anchor
            // window, and the split direction.
            //
            // I learned this once already for `dropTarget` (hence reading it into a local
            // below) and then reintroduced it: `requestMove` reads the anchor + direction
            // straight off the grid, and it was being called AFTER dragActive = false. So
            // the preselect hint was wiped microseconds before it was used, Hyprland fell
            // back to appending the window, and the drop missed the ghost — intermittently,
            // depending on event ordering.
            //
            // So the move is dispatched FIRST, while the drop resolution is still intact,
            // and only then is the drag dismantled. Nothing here may be reordered.
            const target = root.dropTarget

            if (target > 0 && target !== root.workspaceId)
                root.requestMove(target)

            root.dragActive = false
            root.swapping = false

            // Rebind either way. On a move, the binding follows initX/initY into the new
            // cell as soon as Hyprland reports the geometry; on a non-move it animates
            // straight home. Leaving x/y unbound after a drag — which is what the old
            // snapBack() did — is what stranded previews in the wrong place.
            root.rebind()
            root.dragFinished()
        }

        // The grab can vanish without a release — the overview closing under the cursor,
        // the window being destroyed mid-drag. Reset, and move nothing.
        onCanceled: {
            root.dragActive = false
            root.swapping = false
            root.rebind()
            root.dragFinished()
        }

        onClicked: function(m) {
            if (m.button === Qt.RightButton) return
            if (m.button === Qt.MiddleButton) {
                Hypr.closeWindow(root.window.address)
                return
            }
            // Ctrl+click adds it to the selection (or takes it out); the island turns to the lot.
            if (root.ctrlMode || (m.modifiers & Qt.ControlModifier)) {
                if (m.modifiers & Qt.ControlModifier) root.ctrlUsed()
                Switcher.toggleMark(root.window.address)
                return
            }
            // A plain click goes to the window — that is the whole point of a task
            // switcher. MouseArea suppresses `clicked` once a drag has begun, so this
            // and the drop never both fire for one gesture.
            Hypr.goToWindow(root.window.address, root.monitor)
            UiState.leaveOverview(root.workspaceId)
        }
    }
}
