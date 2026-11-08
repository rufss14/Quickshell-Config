import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../panels"

// ── BarPanelDock ──────────────────────────────────────────────────────────────
// The left and right panel groups — wallpaper / colour scheme / equalizer on one
// side, wifi / bluetooth on the other.
//
// These used to be two `PanelWindow`s in modules/panels/PanelHost.qml. They live
// inside Bar's own window now for exactly one reason: `Quicktest.Blobs` can only
// fuse shapes sharing a Qt Quick scene graph, and two layer-shell surfaces are
// composited independently by Hyprland. A panel that actually melts out of the
// bar has to be in the bar's window. Everything else about them — the Accordion
// swap, the Loader that makes a closed panel genuinely not exist, the size
// ceiling, the shadow bleed — moved across unchanged. See BarDock.qml.
//
// What did NOT move: the panels are no longer on `WlrLayer.Overlay` (their own
// windows were; Bar's is `Top`), so notification toasts now sit above an open
// panel rather than fighting it for order. That is the better answer of the two,
// but it IS a behaviour change.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property int screenH

    // This screen owns the panels (or no screen does, e.g. an IPC invocation).
    required property bool owns

    // The unified sidebar's face, from the screen edge, on the side it stands on
    // (0 elsewhere): that side's panels hang off it instead of dropping over the
    // sidebar. See BarDock.sideFace and SideRail's header.
    property int leftFace:  0
    property int rightFace: 0

    // Every panel shares one width, so switching between them never shifts the
    // dock sideways — only the height changes with content.
    readonly property int panelWidth: 535
    // The widest a panel may become. A ceiling rather than a free-for-all: a panel
    // that grows without limit stops reading as a popup and starts covering the
    // desktop.
    readonly property int panelWidthMax: 660

    // ── The dock Item's own footprint, reserved for the LARGEST zoom ──────────
    // Each BarDock sizes its Item to this once and clips its card to it, so it has
    // to cover the widest card that could ever open inside it — the widest natural
    // panel at the largest zoom anyone can drag to. Binding it to the LIVE zoom
    // instead would move the dock's footprint mid-drag, and `reveal` clips to that
    // footprint: the card would be trimmed by the very edge that is chasing it.
    //
    // Costs nothing to over-reserve. The Item is transparent, the input mask is the
    // CARD (BarDock.maskItem), and the window's own height already covers the full
    // screen (Bar.qml) — so the only thing this number decides is where the clip is.
    readonly property int maxCardWidth: Math.round(root.panelWidthMax * Config.panelZoomMax)

    // ── Letting two panels MEET without letting them overlap ─────────────────
    // Two open panels can now be wide enough to reach each other — 535 at 1.5× is
    // 802, and there are up to three of them. Left alone that is an overlap, and an
    // overlap is not a merge: the later card's fill paints over the earlier card's
    // CONTENT, so one panel's controls vanish under the other's background. That is
    // the clipping to avoid.
    //
    // What should happen instead is what the blob is for. Held a short distance
    // apart, the metaball smooth-min bridges the gap and the two cards read as one
    // continuous mass — genuinely merged, with each panel's content still inside its
    // own box and nothing overlapping anything. So the rule is: boxes may come
    // within `mergeGap` of each other and no closer.
    //
    // The gap is sized to the blend, not to taste: the smooth-min reaches about
    // smoothing/2 out from each surface (Morph.filletRadius), so at that distance
    // the two lobes are already fusing. Without the plugin there is nothing to
    // bridge with, so the gap becomes ordinary breathing room instead — two panels
    // sitting near each other, which is the honest look when nothing can weld them.
    readonly property int mergeGap: Morph.available ? Math.round(Morph.filletRadius)
                                                    : Tokens.spacingLg

    // ── Resolution order: centre first, then the sides ───────────────────────
    // Deliberately acyclic. The centre panel is anchored to the midpoint and owes
    // nothing to either side, so it resolves against the screen alone; the sides
    // then resolve against whatever the centre took. Letting the sides push back on
    // the centre would be a cycle — three widths each defined in terms of the other
    // two — and QML would either loop or settle somewhere arbitrary.
    readonly property real centerHalfW:
        centerAccordion.anyOpen
            ? root.widthFor(centerAccordion.activeKey, centerLoader, centerDock, root.width) / 2
            : 0

    // How wide a SIDE panel may be. Three cases, in order:
    //   centre open    — up to the centre card's edge, less the gap.
    //   both sides     — half the screen each, splitting the gap between them. An
    //                    arbitrary split, but a symmetric one, and it only ever
    //                    binds when both are genuinely competing for the middle.
    //   one side only  — the whole width. Nothing to collide with, so nothing to
    //                    limit; capping it at half would shrink a lone panel to
    //                    dodge a neighbour that isn't there.
    // Less the dock's edgeMargin, because a card starts that far in from its dock's
    // edge — the allowance is a WIDTH, and the card does not begin at zero. Per
    // side: a side the sidebar holds starts its card at the sidebar's face.
    function sideAllowance(dock) {
        const half = root.width / 2
        const inset = dock.edgeMargin
        if (centerAccordion.anyOpen)
            return Math.max(0, half - root.centerHalfW - root.mergeGap - inset)
        if (leftAccordion.anyOpen && rightAccordion.anyOpen)
            return Math.max(0, half - root.mergeGap / 2 - inset)
        return Math.max(0, root.width - root.mergeGap - inset)
    }

    // ── When a side still overlaps the centre, the centre steps aside ────────
    // sideAllowance already shrinks a side panel's ZOOM to keep it clear of the
    // centre — but zoomFor() has a floor at 1.0 (see its own comment): a panel
    // never shrinks below its natural size, so a side panel wider than the room
    // it was given still reaches the centre card and overlaps it. Today that
    // overlap is accepted for the CARD (see mergeGap above), but the centre
    // panel's own CONTROLS sitting under a wallpaper thumbnail grid is a
    // different kind of clipping — the background merging is the blob's whole
    // point; a slider or a button vanishing under someone else's panel isn't.
    //
    // So the centre panel itself steps away from whichever side is still
    // overlapping it, by exactly enough to clear that side — capped at the
    // room before it would in turn reach the OTHER side (or the screen edge,
    // when that side is closed). If both sides overlap at once, it splits the
    // difference rather than picking one to favour.
    //
    // Built from leftCardX/rightCardX etc., which do not depend on this offset
    // (the sides are anchored to the screen edges, not to the centre) — so this
    // has nowhere to feed back into itself.
    readonly property real centerPushX: {
        if (!centerAccordion.anyOpen) return 0

        const halfW  = root.centerHalfW
        const left0  = root.width / 2 - halfW
        const right0 = root.width / 2 + halfW

        const leftOverlap  = leftAccordion.anyOpen
            ? Math.max(0, root.leftCardX + root.leftCardW - left0) : 0
        const rightOverlap = rightAccordion.anyOpen
            ? Math.max(0, right0 - root.rightCardX) : 0
        if (leftOverlap === 0 && rightOverlap === 0) return 0

        // Room to move into before reaching the OTHER boundary — that side's
        // card if it's open, otherwise just the screen edge.
        const roomRight = rightAccordion.anyOpen
            ? Math.max(0, root.rightCardX - right0) : Math.max(0, root.width - right0)
        const roomLeft = leftAccordion.anyOpen
            ? Math.max(0, left0 - (root.leftCardX + root.leftCardW)) : Math.max(0, left0)

        const want = leftOverlap - rightOverlap   // >0: step right, <0: step left
        return want >= 0 ? Math.min(want, roomRight) : -Math.min(-want, roomLeft)
    }

    // The wallpaper gallery runs wider and taller than the shared size — it is a
    // thumbnail grid, and the extra room buys a rank without changing the
    // height:width ratio it was tuned at (~1.57:1). Still a fixed pin, not
    // content-driven: see heightFor(). (Tried 660×560 on 2026-11-06; the user said not to
    // change the dimensions much, so the layout lives inside the original pin.)
    readonly property int wallpaperPanelWidth:  620
    readonly property int wallpaperPanelHeight: 394


    // Bar.qml reads these — see there.
    readonly property int maxHeight: Math.max(leftDock.maxHeight,
                                    Math.max(rightDock.maxHeight, centerDock.maxHeight))
    // How far below the window's top the docks start. A pure function of Config
    // (no geometry in it), so Bar can bind its anchor margin to it without a loop.
    readonly property int topMargin: leftDock.topMargin
    readonly property Item leftMask:  leftDock.maskItem
    readonly property Item rightMask: rightDock.maskItem
    readonly property Item centerMask: centerDock.maskItem

    // ── Card geometry, up to the blob layer ───────────────────────────────────
    // BlobBarLayer holds one BlobGroup for the whole window and needs each card's
    // box in WINDOW coordinates. Each dock reports its card in dock-local space;
    // this adds the dock's own offset, and Bar.qml adds this Item's.
    readonly property real leftCardX:  leftDock.x + leftDock.cardX
    readonly property real leftCardY:  leftDock.y + leftDock.cardY
    readonly property real leftCardW:  leftDock.cardW
    readonly property real leftCardH:  leftDock.cardH

    readonly property real centerCardX: centerDock.x + centerDock.cardX
    readonly property real centerCardY: centerDock.y + centerDock.cardY
    readonly property real centerCardW: centerDock.cardW
    readonly property real centerCardH: centerDock.cardH

    readonly property real rightCardX: rightDock.x + rightDock.cardX
    readonly property real rightCardY: rightDock.y + rightDock.cardY
    readonly property real rightCardW: rightDock.cardW
    readonly property real rightCardH: rightDock.cardH

    // …and, for the cookie field (Bar.qml → Drift.setPanels), each card's fade and whether its panel
    // is still wanted: the field around a panel follows the first, and a closing panel takes the
    // cookies that are in it with it.
    readonly property real leftCardA:    leftDock.cardOpacity
    readonly property bool leftCardOpen: leftDock.wanted
    readonly property real centerCardA:    centerDock.cardOpacity
    readonly property bool centerCardOpen: centerDock.wanted
    readonly property real rightCardA:    rightDock.cardOpacity
    readonly property bool rightCardOpen: rightDock.wanted

    // ── The seam between two welded panels ────────────────────────────────────
    // Held `mergeGap` apart, two open panels are bridged by the blob into one mass — but they
    // are still two rectangles with a strip of bridge between them, and the cookie field
    // (Card.drift) stopped at each card's edge, so a shape crossing was cut at both. Where
    // the blob can bridge (the plugin is present and the cards are within its blend), a
    // DriftBridge lays another window onto the same field over the strip. Inset at the foot by
    // the fillet's radius, where the bridge curves away rather than running straight.
    function _bridge(ax, ay, aw, ah, bx, by, bw, bh) {
        if (!Morph.available) return null
        if (ah < 1 || bh < 1 || aw < 1 || bw < 1) return null
        const gap = bx - (ax + aw)
        if (gap < -0.5 || gap > Morph.smoothing) return null
        const y0 = Math.max(ay, by)
        const y1 = Math.min(ay + ah, by + bh) - Morph.filletRadius
        if (y1 - y0 < 1) return null
        return { x: ax + aw, y: y0, w: Math.max(0, gap), h: y1 - y0 }
    }
    readonly property var bridgeLC: root._bridge(root.leftCardX,   root.leftCardY,   root.leftCardW,   root.leftCardH,
                                                 root.centerCardX, root.centerCardY, root.centerCardW, root.centerCardH)
    readonly property var bridgeCR: root._bridge(root.centerCardX, root.centerCardY, root.centerCardW, root.centerCardH,
                                                 root.rightCardX,  root.rightCardY,  root.rightCardW,  root.rightCardH)
    // Left to right with nothing between: only possible while the centre is shut.
    readonly property var bridgeLR: root._bridge(root.leftCardX,  root.leftCardY,  root.leftCardW,  root.leftCardH,
                                                 root.rightCardX, root.rightCardY, root.rightCardW, root.rightCardH)

    DriftBridge {
        z: Drift.raised ? 1000 : 2
        gapX: root.bridgeLC ? root.bridgeLC.x : 0
        gapY: root.bridgeLC ? root.bridgeLC.y : 0
        gapW: root.bridgeLC ? root.bridgeLC.w : 0
        gapH: root.bridgeLC ? root.bridgeLC.h : 0
    }
    DriftBridge {
        z: Drift.raised ? 1000 : 2
        gapX: root.bridgeCR ? root.bridgeCR.x : 0
        gapY: root.bridgeCR ? root.bridgeCR.y : 0
        gapW: root.bridgeCR ? root.bridgeCR.w : 0
        gapH: root.bridgeCR ? root.bridgeCR.h : 0
    }
    DriftBridge {
        z: Drift.raised ? 1000 : 2
        gapX: root.bridgeLR ? root.bridgeLR.x : 0
        gapY: root.bridgeLR ? root.bridgeLR.y : 0
        gapW: root.bridgeLR ? root.bridgeLR.w : 0
        gapH: root.bridgeLR ? root.bridgeLR.h : 0
    }

    // ── …and the spring deformation back down ─────────────────────────────────
    // Computed by the blob from the card's own velocity, applied to the card's
    // content so the two move as one body. Identity while the plugin is absent.
    property matrix4x4 leftDeform
    property matrix4x4 rightDeform
    property matrix4x4 centerDeform
    readonly property bool wantsKeyboardFocus: leftAccordion.anyOpen || rightAccordion.anyOpen
                                               || centerAccordion.anyOpen

    // ══ LEFT — wallpaper / colorScheme / equalizer ═════════════════════════════
    Accordion {
        id: leftAccordion
        requestedKey: root.owns ? UiState.leftPanel : ""
    }

    BarDock {
        id: leftDock
        edge:    "left"
        screenH: root.screenH
        sideFace: root.leftFace
        anchors.top:  parent.top
        anchors.left: parent.left

        cardWidth:    root.widthFor(leftAccordion.activeKey, leftLoader, leftDock, root.sideAllowance(leftDock))
        maxCardWidth: root.maxCardWidth
        cardHeight:   root.heightFor(leftAccordion.activeKey, leftLoader, leftDock, root.sideAllowance(leftDock))
        contentZoom:  root.zoomFor(leftAccordion.activeKey, leftLoader, leftDock, root.sideAllowance(leftDock))
        resizable:    leftAccordion.activeKey !== ""
        onResizeRequested: z => Config.setPanelZoom(leftAccordion.activeKey, z)
        shown:        leftAccordion.contentVisible
        wanted:       leftAccordion.anyOpen
        deformMatrix: root.leftDeform

        Loader {
            id: leftLoader
            anchors.fill: parent
            // THE line that kills the idle cost: no active key, no panel. A hidden
            // panel is still a running panel — WifiPanel used to rescan every 15s
            // and EqualizerPanel polled wpctl every 3s while closed.
            active: leftAccordion.activeKey !== ""
            sourceComponent: root.componentFor(leftAccordion.activeKey)
        }
    }

    // ══ RIGHT — wifi / bluetooth ═══════════════════════════════════════════════
    Accordion {
        id: rightAccordion
        requestedKey: root.owns ? UiState.rightPanel : ""
    }

    BarDock {
        id: rightDock
        edge:    "right"
        screenH: root.screenH
        sideFace: root.rightFace
        anchors.top:   parent.top
        anchors.right: parent.right

        // Same widthFor()/panelWidthMax pair the left dock uses, not a bare
        // panelWidth — a panel's width shouldn't depend on which side of the bar
        // it opens on, and Config.panelSide can now put any of them here,
        // including the wallpaper gallery's wider pin.
        cardWidth:    root.widthFor(rightAccordion.activeKey, rightLoader, rightDock, root.sideAllowance(rightDock))
        maxCardWidth: root.maxCardWidth
        cardHeight:   root.heightFor(rightAccordion.activeKey, rightLoader, rightDock, root.sideAllowance(rightDock))
        contentZoom:  root.zoomFor(rightAccordion.activeKey, rightLoader, rightDock, root.sideAllowance(rightDock))
        resizable:    rightAccordion.activeKey !== ""
        onResizeRequested: z => Config.setPanelZoom(rightAccordion.activeKey, z)
        shown:        rightAccordion.contentVisible
        wanted:       rightAccordion.anyOpen
        deformMatrix: root.rightDeform

        Loader {
            id: rightLoader
            anchors.fill: parent
            active: rightAccordion.activeKey !== ""
            sourceComponent: root.componentFor(rightAccordion.activeKey)
        }
    }

    // ══ CENTRE — system updates ════════════════════════════════════════════════
    // Moved out of PanelHost's own Overlay-layer PanelWindow so it welds into the
    // bar like every other panel — the blob can only fuse shapes sharing one scene
    // graph. The trade is real and worth stating: this is the bar's layer (Top), so
    // a notification toast or the OSD (both Overlay) can now draw over it.
    //
    // UpdatePanel is the one panel that decides for itself when it is up — it opens
    // on a request and closes when the run is dismissed — so `updateActive` is
    // driven by the REQUEST, and UiState.updateOpen going false tears it down. The
    // Loader cannot be gated on updateOpen directly: the panel can't report itself
    // open until it exists, and it wouldn't exist until it reported itself open.
    property bool updateActive: false

    // `Loader.item` is statically a bare QObject, so calling startUpdate on it is an
    // unchecked call into the dark. Casting once gives every use below a checked type.
    readonly property UpdatePanel updatePanel: centerLoader.item as UpdatePanel

    // What the bar's window needs to escalate its keyboard grab for — the sudo
    // password field. Deliberately NOT held for the length of a run; see
    // UpdatePanel.wantsKeyboard.
    // Exclusive keyboard, for the two centre panels that own a text field the user
    // never clicks into first: the sudo prompt, and the launcher's search box. The
    // cast yields null when the slot holds the other one, so `?? false` is the
    // ordinary "not that panel" answer rather than a guard against a mistake.
    readonly property bool centerWantsKeyboard:
        centerAccordion.activeKey === "launcher"
            ? true
            : (root.updatePanel?.wantsKeyboard ?? false)

    Connections {
        target: UiState

        // Cleared on close so the panel's height snaps back to collapsed BEFORE the
        // fade starts — otherwise the next open begins full-height and shrinks, which
        // is the launcher appearing to fall in rather than grow out. Carried over from
        // AppLauncherPopup, which owned this while the launcher had its own window.
        function onLauncherOpenChanged() {
            if (!UiState.launcherOpen) centerLoader.item?.resetSearch()
        }

        function onUpdateRequestIdChanged() {
            if (!root.owns) return
            if (!root.updateActive) root.updateActive = true
            else root.updatePanel?.startUpdate(UiState.pendingUpdateCount)
        }

        function onUpdateOpenChanged() {
            if (!UiState.updateOpen) root.updateActive = false
        }
    }

    // Through the same Accordion as the other two, for the entrance and exit rather
    // than for sequencing — it has no siblings to swap with.
    // The launcher shares this slot with the update panel, which also makes them
    // properly exclusive: they are the same piece of screen, and an Accordion is
    // exactly the thing that sequences one out before the other comes in. The
    // launcher wins a tie — it is the one the user just asked for by keystroke.
    //
    // UiState.centerKey is the third thing this slot can hold: any panel Settings →
    // Bar → Panel placement has moved to the middle. It loses to both launcher and
    // update — those two already have their own request-driven lifetime and a
    // reassigned panel arriving mid-run would have nowhere sensible to go.
    Accordion {
        id: centerAccordion
        requestedKey: !root.owns              ? ""
                    : UiState.launcherOpen    ? "launcher"
                    : root.updateActive       ? "update"
                    :                           UiState.centerKey
    }

    BarDock {
        id: centerDock
        edge:    "center"
        screenH: root.screenH
        anchors.top:              parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        // See root.centerPushX — steps aside from a side panel it would
        // otherwise overlap. Same curve as the card's own width/height so the
        // step and any concurrent resize read as one motion.
        anchors.horizontalCenterOffset: root.centerPushX
        Behavior on anchors.horizontalCenterOffset {
            NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
        }

        // Same widthFor()/panelWidthMax pair the side docks use — a panel's width
        // shouldn't depend on which of the three columns it opens in, and
        // Config.panelSide can now put any of them here, including the wallpaper
        // gallery's wider pin. Update/launcher never asked for extra width, so
        // this is unchanged for them.
        cardWidth:    root.widthFor(centerAccordion.activeKey, centerLoader, centerDock, root.width)
        maxCardWidth: root.maxCardWidth
        // Same heightFor() the side docks use — was a bare implicitHeight read
        // with no ceiling, harmless while only update/launcher ever landed here,
        // but a reassigned panel needs the same cap they get everywhere else.
        cardHeight:   root.heightFor(centerAccordion.activeKey, centerLoader, centerDock, root.width)
        contentZoom:  root.zoomFor(centerAccordion.activeKey, centerLoader, centerDock, root.width)
        resizable:    centerAccordion.activeKey !== ""
        onResizeRequested: z => Config.setPanelZoom(centerAccordion.activeKey, z)
        shown:        centerAccordion.contentVisible
        wanted:       centerAccordion.anyOpen
        deformMatrix: root.centerDeform

        Loader {
            id: centerLoader
            anchors.fill: parent
            active: centerAccordion.activeKey !== ""
            sourceComponent: root.componentFor(centerAccordion.activeKey)
            onLoaded: {
                if (centerAccordion.activeKey === "update")
                    root.updatePanel?.startUpdate(UiState.pendingUpdateCount)
                else if (centerAccordion.activeKey === "launcher")
                    Qt.callLater(() => centerLoader.item?.focusSearch())
            }
        }
    }

    // ── Escape closes whichever group is open ─────────────────────────────────
    // On an Item, never on the window: `Keys` is an attached property that does
    // nothing at all on a PanelWindow, and logs why.
    // The panel that has the keyboard: the one Escape would close. A panel may answer `handleEscape()`
    // (true = it used the key, e.g. to leave a sub-view first) and `handleKey(event)` (true = handled).
    function keyTarget() {
        const l = UiState.rightPanel !== "" ? rightLoader : UiState.leftPanel !== "" ? leftLoader : centerLoader
        return l.item
    }
    EscapeGuard {
        id: escFocus
        wanted: UiState.leftPanel !== "" || UiState.rightPanel !== "" || UiState.centerPanel !== ""
        onKeyPressed: (event) => {
            const it = root.keyTarget()
            if (it && it.handleKey) event.accepted = it.handleKey(event) === true
        }
        onEscaped: {
            const it = root.keyTarget()
            if (it && it.handleEscape && it.handleEscape() === true) return
            if (UiState.rightPanel !== "")       UiState.closeRight()
            else if (UiState.leftPanel !== "")   UiState.closeLeft()
            else                                 UiState.closeCenter()
        }
    }
    Connections {
        target: UiState
        function onLeftPanelChanged()   { if (UiState.leftPanel   !== "") escFocus.forceActiveFocus() }
        function onRightPanelChanged()  { if (UiState.rightPanel  !== "") escFocus.forceActiveFocus() }
        function onCenterPanelChanged() { if (UiState.centerPanel !== "") escFocus.forceActiveFocus() }
    }

    // ── Panel registry ────────────────────────────────────────────────────────
    // A key → Component map. The Loaders above instantiate exactly one of these at
    // a time; everything else genuinely does not exist.
    function componentFor(key) {
        switch (key) {
            case "wallpaper":   return wallpaperComponent
            case "colorScheme": return colorSchemeComponent
            case "equalizer":   return equalizerComponent
            case "media":       return null      // always mounted — see mediaPanel
            case "wifi":        return wifiComponent
            case "bluetooth":   return bluetoothComponent
            case "gaming":      return gamingComponent
            case "clock":       return clockComponent
            case "notifications": return notificationsComponent
            case "update":      return updateComponent
            case "launcher":    return launcherComponent
            case "brightness":  return brightnessComponent
            case "window":      return windowComponent
            case "layout":      return layoutComponent
            // The sidebar's panels, for its modules placed on the bar (SideModulePill).
            case "stats":       return statsComponent
            case "clipboard":   return clipboardComponent
            case "timer":       return timerComponent
            case "claude":      return claudeComponent
            case "screentime":  return screenTimeComponent
            case "inactivity":  return inactivityComponent
            case "tasks":       return tasksComponent
            case "clips":       return clipsComponent
            default:            return null
        }
    }

    // ── Panels size themselves, within limits ─────────────────────────────────
    // These were hard-coded to 340 once, which silently CLIPPED the taller panels:
    // the wallpaper gallery asked for 420 and the colour editor for 500, and both
    // lost everything past 340 with no warning anywhere. A panel knows what it
    // needs; this only enforces a ceiling so nothing runs off the screen.
    // ── Natural size: what the panel asks for, before any zoom ───────────────
    // Split out because three things need it and must agree: the box, the
    // collision allowance, and the ratio the zoom preserves. Inlining it in
    // widthFor() was fine until the allowance needed the same number.
    //
    // The wallpaper gallery is a fixed pin, not content-driven — it is a thumbnail
    // grid and self-sizing to its content made it worse.
    function naturalW(key, loader) {
        if (key === "") return 0
        if (key === "wallpaper") return root.wallpaperPanelWidth
        const w = root.itemFor(key, loader)?.implicitWidth ?? 0
        // Floored at the shared panelWidth so the narrow panels stay aligned with
        // each other, and only a panel that explicitly asks is ever wider.
        return Math.max(root.panelWidth, Math.min(w, root.panelWidthMax))
    }

    function naturalH(key, loader) {
        if (key === "") return 0
        // Pinned — except while it's folded into the workspace picker, which hugs.
        if (key === "wallpaper") {
            const pinned = root.itemFor(key, loader)?.pinnedHeight ?? 0
            return pinned > 0 ? pinned : root.wallpaperPanelHeight
        }
        const h = root.itemFor(key, loader)?.implicitHeight ?? 0
        return h > 0 ? h : 340
    }

    function itemFor(key, loader) {
        return key === "media" ? mediaPanel : loader.item
    }

    // ── Every limit is resolved as a smaller ZOOM, never as a clamped axis ────
    // Config.panelZoom is spent in exactly two places: here, growing the card's
    // BOX, and BarDock.contentZoom, scaling the card's CONTENT by the same number.
    // Both read this one function, so the two can't disagree about the size.
    //
    // The zoom is applied AFTER the natural size is measured. That order is what
    // keeps the panel content-hugging: it still reports the implicitHeight its
    // content needs, at its natural width (the Loader inside cardBody is sized
    // natural, not zoomed), so the zoom never feeds back into the measurement.
    //
    // Both limits — the screen's height and the neighbouring panel — are folded in
    // HERE rather than clamping width or height at the end. Clamping one axis is
    // what breaks the ratio: a tall panel would stop growing vertically while the
    // width kept going, and the one thing this feature promises would fail exactly
    // where it is most visible. A smaller zoom shrinks both axes together.
    //
    // ── Neither limit may shrink a panel below its natural size ───────────────
    // Hence Math.max(1, …) on each. A limit's job is to take back zoom the user
    // ADDED; a screen too narrow to hold two panels at 1.0 is today's behaviour
    // (they clip, and the content scrolls) and is not this feature's to change —
    // scaling a panel below 1.0 to fit would shrink its text instead, which is
    // worse than the clipping it replaced.
    function zoomFor(key, loader, dock, allowW) {
        if (key === "") return 1.0
        let z = Config.panelZoomFor(key)

        const h0 = root.naturalH(key, loader)
        if (h0 > 0) z = Math.min(z, Math.max(1, dock.maxHeight / h0))

        const w0 = root.naturalW(key, loader)
        if (w0 > 0 && allowW > 0) z = Math.min(z, Math.max(1, allowW / w0))

        return z
    }

    function heightFor(key, loader, dock, allowW) {
        if (key === "") return 0
        const h = Math.round(root.naturalH(key, loader) * root.zoomFor(key, loader, dock, allowW))
        return Math.min(h, dock.maxHeight)
    }

    function widthFor(key, loader, dock, allowW) {
        if (key === "") return root.panelWidth
        return Math.round(root.naturalW(key, loader) * root.zoomFor(key, loader, dock, allowW))
    }

    Component { id: wallpaperComponent;   WallpaperPanel   {} }
    Component { id: colorSchemeComponent; ColorSchemePanel {} }
    Component { id: equalizerComponent;   EqualizerPanel   {} }

    // ── Now Playing is the one panel that is NOT lazy ─────────────────────────
    // Built on open and destroyed on close like the rest, every open rebuilt the
    // lyrics card from nothing and it visibly re-connected. So it is created once
    // and reparented into whichever dock opens it, parked hidden otherwise. `shown`
    // is what stops the closed copy doing per-frame work (MediaPanel gates on it).
    MediaPanel {
        id: mediaPanel
        readonly property Item host:
              leftAccordion.activeKey   === "media" ? leftDock.body
            : rightAccordion.activeKey  === "media" ? rightDock.body
            : centerAccordion.activeKey === "media" ? centerDock.body
            : null
        parent: host ?? root
        anchors.fill: parent
        shown: host !== null
        visible: shown
    }
    Component { id: wifiComponent;        WifiPanel        {} }
    Component { id: bluetoothComponent;   BluetoothPanel   {} }
    Component { id: gamingComponent;      GamingPanel      {} }
    Component { id: clockComponent;       ClockPanel       {} }
    // The notification centre the overview's second page used to hold — the same
    // panel the sidebar's bell opens.
    Component { id: notificationsComponent; NotificationsPanel {} }
    Component { id: updateComponent;      UpdatePanel      {} }
    // The new modules' panels — the same files the sidebar's dock opens.
    Component { id: brightnessComponent;  BrightnessPanel  {} }
    Component { id: windowComponent;      WindowPanel      {} }
    Component { id: layoutComponent;      LayoutPanel      {} }
    Component { id: statsComponent;       StatsPanel       {} }
    Component { id: clipboardComponent;   ClipboardPanel   {} }
    Component { id: timerComponent;       TimerPanel       {} }
    Component { id: claudeComponent;      ClaudePanel      {} }
    Component { id: screenTimeComponent;  ScreenTimePanel  {} }
    Component { id: inactivityComponent;  InactivityPanel  {} }
    Component { id: tasksComponent;       TasksPanel       {} }
    Component { id: clipsComponent;       ClipsPanel       {} }
    Component {
        id: launcherComponent
        AppLauncherPanel { onCloseRequested: UiState.launcherOpen = false }
    }
}
