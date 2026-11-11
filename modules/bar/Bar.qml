pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "widgets"

// ── Bar ───────────────────────────────────────────────────────────────────────
// The status bar.
//
// ── It renders Config.layout. It does not know what's in it. ──────────────────
// Every widget used to be written into this file by hand, in a fixed order, inside
// hand-picked groups — and then each one carried a `visible: Config.moduleOn(...)`
// so it could be hidden. That made the bar's order and grouping structural (only an
// edit to this file could change them) while visibility was data. Three facts about
// a module, stored two different ways, and only one of them editable.
//
// Now there's one fact: the layout. `Config.layout` is region → groups → module ids,
// this file walks it, and `moduleFor()` maps an id to a widget. A module absent from
// the layout isn't hidden — it isn't built. Dragging one in the settings page moves
// the real thing, because there is nothing else for it to move.
//
// What that bought, concretely: the `visible:` line on all thirteen widgets, the
// hasToggles/hasMainGroup/hasTray booleans that existed to hide a group once all its
// children were hidden, and the showDivider chains that had to ask "is any VISIBLE
// group ahead of me" — all gone. A group in the layout has modules in it by
// construction (Config prunes empty ones), and it has a divider iff it isn't first.
//
// ── The cost, stated plainly ─────────────────────────────────────────────────
// A Repeater over a JS array rebuilds every delegate when the array is reassigned,
// so editing the layout tears down and rebuilds the bar — cava restarts, the tray
// re-reads its items. That's the right trade here (you edit the layout roughly never,
// and the alternative is hand-diffing a nested structure into an ObjectModel), but it
// is why the drag UI must commit on RELEASE and not per-frame: a rebuild mid-drag
// destroys the delegate holding the mouse grab. That bug has been paid for twice in
// this codebase already — once in the overview's window drag, once in Pins.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    anchors.top:   true
    anchors.left:  true
    anchors.right: true
    // Bar height and inset are user settings now (Settings → Bar).
    //
    // The apron is extra window BELOW the bar, only while fused to the screen
    // frame: the fillets where the edge pills sweep into the ring's side strips
    // land past the bar's own height, and an arc crossing a window boundary gets
    // clipped mid-curve (that clipping used to cap them at barInset — a notch,
    // not a sweep). The zone and mask below keep the apron from reserving space
    // or eating clicks, so to everything but the fillets the bar is still
    // barThickness tall.
    // The apron doubles as the pills' shadow bleed: paint stops at a Wayland
    // surface edge, so without extra window below the bar every pill's shadow is
    // sliced off flat at barThickness. Whichever of the two needs more room wins —
    // they are the same surplus, not two stacked ones, and the zone/mask below
    // already keep the surplus from reserving space or eating clicks either way.
    //
    // Nothing is added ABOVE: the bar sits at y=0, so a pill's upward shadow is
    // off-screen. With the frame band drawn behind the pills there is nothing up
    // there to cast onto anyway.
    // ── Arrange mode's shelf ──────────────────────────────────────────────────
    // A fixed ceiling, masked in only while it is up, never animated. It has to be
    // part of THIS window because Qt's Drag/DropArea only work within one window — a shelf in the settings window
    // could not be dragged onto the bar at all. See BarArrange and UiState.barArrange.
    //
    // This room is NOT always reserved: arrange mode is rare and short-lived, so the
    // window grows when it opens. That is one surface
    // resize on entering and one on leaving, which is the cost the "never animate
    // implicitHeight" rule is actually about — not a discrete change.
    // ── Does the blob own the ring's fill and outline? ────────────────────────
    // Only while the bar is ANCHORED. Floating, the bar stands off the frame, and
    // the ring models it as one full-width band welded to the top — so the blob
    // would paint a slab across the screen and stroke a line under nothing. That is the
    // same condition BarDock's `hugBar` already encodes; keeping one name for it
    // means the layer, the docks and the stroke handoff cannot disagree.
    readonly property bool blobRing: Morph.available && Config.barAnchored

    // ── Where this screen's panels are, for the cookie field ──────────────────
    // The bar groups' three cards and the sidebar's panel, in this window's pixels (= the screen's),
    // with how far each card has faded in (`a`) and whether it is still wanted (`open`). Drift lights
    // a shape while it overlaps a fully open one, which is how the bar, the sidebar and the frame
    // show only what has just come out of a panel (Config.barCookiesFrom "panels"), and every
    // window draws a shape near one as strongly as the panel does (drift.js `strength`).
    readonly property var _panelRects: !Config.barCookies ? [] : [
        root._barCard(panelDock.leftCardX,   panelDock.leftCardY,   panelDock.leftCardW,   panelDock.leftCardH,
                      panelDock.leftCardA,   panelDock.leftCardOpen),
        root._barCard(panelDock.centerCardX, panelDock.centerCardY, panelDock.centerCardW, panelDock.centerCardH,
                      panelDock.centerCardA, panelDock.centerCardOpen),
        root._barCard(panelDock.rightCardX,  panelDock.rightCardY,  panelDock.rightCardW,  panelDock.rightCardH,
                      panelDock.rightCardA,  panelDock.rightCardOpen),
        { x: sidePanelDock.maskItem.x, y: sidePanelDock.maskItem.y,
          w: sidePanelDock.maskItem.width, h: sidePanelDock.maskItem.height,
          a: sidePanelDock.cardOpacity, open: sidePanelDock.wanted }
    ]
    // A bar panel's card, cut at the bar's underside: on its way in it starts a slide above it, hidden
    // behind the bar (BarDock's `reveal`), and that part is not the panel's yet — counted, it lit
    // shapes that were wholly on the bar.
    function _barCard(x, y, w, h, a, open) {
        const top = Math.max(panelDock.y, panelDock.y + y)
        return { x: panelDock.x + x, y: top, w: w, h: Math.max(0, panelDock.y + y + h - top), a: a, open: open }
    }
    on_PanelRectsChanged: Drift.setPanels(root.screen?.name ?? "", root._panelRects)
    Component.onDestruction: Drift.setPanels(root.screen?.name ?? "", [])

    readonly property real arrangeRoom: UiState.barArrange ? arrangeHost.shelfHeight : 0

    // The panel docks, the toast deck and the tray menu all hang from the same
    // bar edge down toward the same bottom margin, so they OVERLAP — the tallest
    // ceiling covers them all. Summing them would reserve a second screen-height
    // of window for nothing. The window is always reserved this tall, never
    // animated: resizing a PanelWindow's own implicitHeight resizes the actual
    // Wayland surface every frame, which stutters however clean the QML above is.
    implicitHeight: Math.max(
                      Config.barExtent
                    + Math.max(Config.frameApron, Tokens.shadowRoom(Tokens.elevationBar))
                    + Math.max(panelDock.maxHeight,
                               Math.max(toastHost.maxHeight, trayMenuHost.maxHeight))
                    + root.arrangeRoom,
                      // Arranging dims the whole screen, so the window reaches its bottom.
                      UiState.arrange ? (root.screen?.height ?? 0) : 0,
                      // The docked settings panel hangs off the BOTTOM, not the bar
                      // edge — the window has to be tall enough to hold it too.
                      Math.max(settingsHost.bottomReach,
                      // …and the dock sits on the bottom edge itself, where
                      // auto-hide's reveal zone has to be able to receive hover
                      // (the sidebar's bar and its buttons likewise).
                               Math.max(dockHost.bottomReach, sideBarHost.bottomReach)))
    // Explicit, not Auto-derived from the window size — the apron must not push
    // tiled windows down, and neither may the panels' reserved room above. Same direct-assignment idiom as DesktopClock's zone.
    exclusiveZone: Config.barExtent
    // Clicks belong to the bar strip, the apron's fillets, or (when open) a panel's
    // card — nowhere else, so the reserved room above doesn't
    // eat clicks meant for the desktop under it. `Combine` (the default) unions
    // the two regions rather than replacing one with the other.
    mask: Region {
        Region { width: root.width; height: Config.barExtent }
        Region { item: panelDock.leftMask;   intersection: Intersection.Combine }
        Region { item: panelDock.rightMask;  intersection: Intersection.Combine }
        Region { item: panelDock.centerMask; intersection: Intersection.Combine }
        Region { item: toastHost.maskItem;   intersection: Intersection.Combine }
        Region { item: trayMenuHost.maskItem; intersection: Intersection.Combine }
        Region { item: settingsHost.maskItem; intersection: Intersection.Combine }
        // The dock: its card, its preview, the screen edge that reveals it while
        // auto-hiding, and — only while its menu is open — the whole screen, so the
        // click that dismisses the menu lands on the dismiss layer and not below.
        // Each is zero-sized while it has nothing to do.
        Region { item: dockHost.maskItem;    intersection: Intersection.Combine }
        Region { item: dockHost.previewMask; intersection: Intersection.Combine }
        Region { item: dockHost.menuMask;    intersection: Intersection.Combine }
        // The dock as a bar module (DockPill): its preview card and its menu's dismiss layer.
        Region { item: barDockPopups.previewMask; intersection: Intersection.Combine }
        Region { item: barDockPopups.menuMask;    intersection: Intersection.Combine }
        // The workspace pill's glance: its card, while it is out.
        Region { item: workspaceGlance.maskItem;  intersection: Intersection.Combine }
        // A sidebar button's panel, beside it.
        Region { item: sidePanelDock.maskItem; intersection: Intersection.Combine }
        // The OSD's sliders, while they are up: draggable, so they take the pointer.
        Region { item: osdDock.maskItem; intersection: Intersection.Combine }
        // The power column: the card while it melts, and the WHOLE window while it is up, so
        // a click outside lands on its dismiss layer and closes it.
        Region { item: powerDock.maskItem; intersection: Intersection.Combine }
        // The "Done arranging" button, only while it is up.
        Region { item: arrangeDone.visible ? arrangeDone : null; intersection: Intersection.Combine }
        // Arranging the sidebar: its band and the room beside it (SideArrange).
        Region { item: sideArrangeHost.item?.maskItem ?? null; intersection: Intersection.Combine }
        // The unified sidebar's bar, between and behind the modules — and the edge
        // that reveals the whole sidebar while it auto-hides.
        Region { item: sideBarHost.maskItem; intersection: Intersection.Combine }
        Region { item: sideBarHost.edgeMask; intersection: Intersection.Combine }
        // The arrange shelf, only while it is up. Without this the reserved room
        // below the bar would swallow clicks meant for the desktop — and with the
        // shelf up, a drag that leaves the bar strip has to keep receiving events or
        // the gesture dies the moment the pointer drops below the pills.
        Region {
            width:  root.width
            y:      Config.barExtent
            height: root.arrangeRoom
            intersection: Intersection.Combine
        }
    }
    color: "transparent"

    // Everything docked in this window that wants the keyboard asks for it here.
    // OnDemand only grants focus on a click INTO the surface, and these panels are
    // opened from the bar itself — so without this a wifi password field ignores
    // typing until clicked and Escape never arrives at all.
    // Exclusive for the two centre panels that own a text field a click cannot reach
    // first: the update panel's sudo prompt (it opens itself, unprompted) and the
    // launcher's search box (opened by keystroke, and typing has to land in it
    // immediately). UpdatePanel.wantsKeyboard deliberately drops back to OnDemand for
    // the length of a run, because holding an exclusive grab across a full system
    // upgrade locks the rest of the desktop out of the keyboard.
    WlrLayershell.keyboardFocus:
          (panelDock.centerWantsKeyboard
           || settingsHost.wantsKeyboardFocus
           || dockHost.wantsExclusiveFocus
           || barDockPopups.wantsExclusiveFocus
           // The power column: arrow keys, letters and Escape must reach it, and it is
           // opened from another surface, so OnDemand would never deliver them.
           || powerDock.wantsExclusive)                                   ? WlrKeyboardFocus.Exclusive
        : (panelDock.wantsKeyboardFocus
           || trayMenuHost.expanded || dockHost.wantsKeyboardFocus
           || barDockPopups.wantsKeyboardFocus
           || sidePanelDock.wantsKeyboardFocus
           || UiState.arrange)                                            ? WlrKeyboardFocus.OnDemand
        :                                                                   WlrKeyboardFocus.None

    // ══ WINDOW PEEK ═══════════════════════════════════════════════════════════
    // The dock preview's Aero Peek. FIRST, so it's under everything this window
    // draws — frame, bar, dock, the preview itself — and over the windows below.
    WindowPeek {
        anchors.fill: parent
        monitor: root.hyprMonitor
    }

    // ══ ANTI-FLASHBANG'S EYE ══════════════════════════════════════════════════
    // How bright this screen is (services/AntiFlash), on the FOCUSED screen only
    // and only while anti-flashbang is on. A ScreencopyView needs a window, and this
    // one is always mapped. Draws nothing.
    Loader {
        active: AntiFlash.active && AntiFlash.probeScreen !== ""
                && AntiFlash.probeScreen === (root.screen?.name ?? "")
        sourceComponent: Component { BrightnessProbe { screen: root.screen } }
    }

    // The screen frame's top edge — the thin band, stubs and top corners, drawn
    // behind every pill. Lives inside this window (not in ScreenFrame) because
    // same-layer surfaces stack by map order; see BarFrameEdge for the full story.
    // `barFrame` draws the identical band on its own, without ScreenFrame's
    // side/bottom strips — the "just merge the bar" toggle.
    // The MATERIAL half: the thin band, the stubs and the concave corner fills.
    // Behind the pills, which is where a background belongs. The outline half is
    // mounted at the very bottom of this file — see `BarFrameEdge.part` for why the
    // two cannot be one item.
    BarFrameEdge {
        anchors.fill: parent
        z: -1
        part: "fill"
        // Same guard the "line" mount below carries. BarFrameEdge only has a job
        // when the ring exists; frameDepth never falls to 0, so without this its
        // stubs paint a thin strip down each side even with the frame switched off.
        visible: Config.screenFrame
    }

    // ══ THE BLOB LAYER ════════════════════════════════════════════════════════
    // One BlobGroup for this whole window: the bar strip AND every panel hanging
    // off it, fused by the metaball shader. Mounted HERE — early, at z:-1, before
    // any bar surface — because the group draws the bar strip in the bar's own fill
    // and would otherwise cover every pill. The real Surface lands on top of it
    // exactly; the only part that ever shows is what hangs below the strip, which
    // is the neck and the panel.
    //
    // File-path Loader, never a typed tag: this is the one file in the bar's chain
    // that imports Quicktest.Blobs, and a direct import would take the whole bar
    // down on a machine where the plugin was never built. See state/Morph.qml.
    Loader {
        id: blobLayer
        anchors.fill: parent
        z: -1
        active: root.blobRing
        asynchronous: false
        source: root.blobRing ? Qt.resolvedUrl("../../components/blob/BlobBarLayer.qml") : ""

        onLoaded: {
            item.screenW = Qt.binding(() => root.screen?.width  ?? 1920)
            item.screenH = Qt.binding(() => root.screen?.height ?? 1080)
            item.screenName = Qt.binding(() => root.screen?.name ?? "")

            // The bar is the ring's top border. Anchored it starts at y=0 and its
            // whole extent is material; floating it is inset, and the ring stops at
            // the pill's underside so the gap above stays open.
            item.barHeight = Qt.binding(() =>
                Config.barAnchored ? Config.barSurfaceHeight
                                   : root.inset + Config.barSurfaceHeight)

            // The FULL depth: when the blob owns the ring, ScreenFrame's overlay is
            // unmapped and this band is the only frame there is. (It used to stop one
            // border width short so ScreenFrame's stroke could sit on top — that
            // stroke and the blob's own SDF outline are different curves in different
            // windows, which is exactly the seam that could never be made to meet.)
            item.frameInset = Qt.binding(() => Config.screenFrame ? Config.frameDepth : 0)
            item.borderColor = Qt.binding(() => Colors.of(QsWindow.window).frameLine)
            item.borderWidth = Qt.binding(() => Config.screenFrame ? Config.frameBorderWidth
                                                                   : Config.barBorderWidth)
            item.frameRadius = Qt.binding(() => Config.screenFrame ? Config.frameCornerRadius : 0)

            item.leftX  = Qt.binding(() => panelDock.x + panelDock.leftCardX)
            item.leftY  = Qt.binding(() => panelDock.y + panelDock.leftCardY)
            item.leftW  = Qt.binding(() => panelDock.leftCardW)
            item.leftH  = Qt.binding(() => panelDock.leftCardH)

            item.rightX = Qt.binding(() => panelDock.x + panelDock.rightCardX)
            item.rightY = Qt.binding(() => panelDock.y + panelDock.rightCardY)
            item.rightW = Qt.binding(() => panelDock.rightCardW)
            item.rightH = Qt.binding(() => panelDock.rightCardH)

            item.centerX = Qt.binding(() => panelDock.x + panelDock.centerCardX)
            item.centerY = Qt.binding(() => panelDock.y + panelDock.centerCardY)
            item.centerW = Qt.binding(() => panelDock.centerCardW)
            item.centerH = Qt.binding(() => panelDock.centerCardH)

            item.settingsX = Qt.binding(() => settingsHost.blobX)
            item.settingsY = Qt.binding(() => settingsHost.blobY)
            item.settingsW = Qt.binding(() => settingsHost.blobW)
            item.settingsH = Qt.binding(() => settingsHost.blobH)

            // The hosts sit at the window's origin, so their boxes are window space.
            item.sidebarX = Qt.binding(() => sideBarHost.blobX)
            item.sidebarY = Qt.binding(() => sideBarHost.blobY)
            item.sidebarW = Qt.binding(() => sideBarHost.blobW)
            item.sidebarH = Qt.binding(() => sideBarHost.blobH)

            item.magnifyRects = Qt.binding(() => dockHost.magnifyRects)

            // A sidebar button's panel, melted out of the sidebar's face beside it.
            item.sidePanelX = Qt.binding(() => sidePanelDock.blobX)
            item.sidePanelY = Qt.binding(() => sidePanelDock.blobY)
            item.sidePanelW = Qt.binding(() => sidePanelDock.blobW)
            item.sidePanelH = Qt.binding(() => sidePanelDock.blobH)

            // The OSD's sliders, melted out of the frame's right edge.
            item.osdX = Qt.binding(() => osdDock.blobX)
            item.osdY = Qt.binding(() => osdDock.blobY)
            item.osdW = Qt.binding(() => osdDock.blobW)
            item.osdH = Qt.binding(() => osdDock.blobH)

            // The power menu's column, melted out of the same edge.
            item.powerX = Qt.binding(() => powerDock.blobX)
            item.powerY = Qt.binding(() => powerDock.blobY)
            item.powerW = Qt.binding(() => powerDock.blobW)
            item.powerH = Qt.binding(() => powerDock.blobH)

            item.previewX = Qt.binding(() => dockHost.previewBlobX)
            item.previewY = Qt.binding(() => dockHost.previewBlobY)
            item.previewW = Qt.binding(() => dockHost.previewBlobW)
            item.previewH = Qt.binding(() => dockHost.previewBlobH)

            item.toastRects = Qt.binding(() => toastHost.toastRects)

            // The workspace glance fills this window, so its card is already in window space.
            item.glanceX = Qt.binding(() => workspaceGlance.blobX)
            item.glanceY = Qt.binding(() => workspaceGlance.blobY)
            item.glanceW = Qt.binding(() => workspaceGlance.blobW)
            item.glanceH = Qt.binding(() => workspaceGlance.blobH)

            // The pill tooltip fills this window too.
            item.tipX = Qt.binding(() => pillTip.blobX)
            item.tipY = Qt.binding(() => pillTip.blobY)
            item.tipW = Qt.binding(() => pillTip.blobW)
            item.tipH = Qt.binding(() => pillTip.blobH)

            // Arrange mode's hint cards: the bar's and the sidebar's, each in window coordinates.
            item.arrBarX = Qt.binding(() => arrangeHost.item?.blobX ?? 0)
            item.arrBarY = Qt.binding(() => arrangeHost.item?.blobY ?? 0)
            item.arrBarW = Qt.binding(() => arrangeHost.item?.blobW ?? 0)
            item.arrBarH = Qt.binding(() => arrangeHost.item?.blobH ?? 0)
            item.arrSideX = Qt.binding(() => sideArrangeHost.item?.blobX ?? 0)
            item.arrSideY = Qt.binding(() => sideArrangeHost.item?.blobY ?? 0)
            item.arrSideW = Qt.binding(() => sideArrangeHost.item?.blobW ?? 0)
            item.arrSideH = Qt.binding(() => sideArrangeHost.item?.blobH ?? 0)

            // trayMenuHost fills this whole window at (0,0), so its own card box is
            // already in window coordinates — no dock offset to add, unlike left/
            // right/centre above.
            item.trayX = Qt.binding(() => trayMenuHost.cardX)
            item.trayY = Qt.binding(() => trayMenuHost.cardY)
            item.trayW = Qt.binding(() => trayMenuHost.cardW)
            item.trayH = Qt.binding(() => trayMenuHost.cardH)
        }
        visible: Config.screenFrame
    }

    // ── Its own layer namespace, so the compositor can find it ────────────────
    // Blur is not something this shell can draw — it's a Hyprland layer_rule, matched by
    // namespace, applied when the layer is MAPPED. Without this the bar shared the
    // default `quickshell` namespace with every other PanelWindow, so any rule aimed at
    // the bar would have hit the panels and the launcher too.
    //
    // Naming it is all this file can do. The rule itself lives in your Hyprland config,
    // beside the one the overview already relies on:
    //
    //     hl.layer_rule({ match = { namespace = "^quickshell-bar$" }, blur = true })
    //
    // Config.barOpacity is what makes that blur visible — an opaque pill has nothing
    // behind it to blur.
    WlrLayershell.namespace: "quickshell-bar"

    // ── The idle inhibitor ────────────────────────────────────────────────────
    // The Wayland object that actually stops the screen blanking. It lives here and
    // not in the Idle service because the protocol is anchored to a SURFACE — an
    // inhibitor holds only while its window is mapped and visible — and a singleton
    // has no window. The service owns the policy (who is holding, and why); this is
    // the one line that spends it.
    //
    // The bar is the right window for it: it exists for the whole session, on every
    // screen, and is always mapped. Anything else would mean inventing a zero-sized
    // window whose only job is to be somewhere for this to attach to.
    //
    // ── One per screen is correct, not wasteful ───────────────────────────────
    // Variants builds a Bar per monitor, so a three-monitor machine creates three
    // inhibitors that switch on and off together. That is what the protocol is for:
    // inhibitors are additive, any one of them suppresses idle, and each is a surface
    // honestly saying "not while I'm up". Electing a single screen to own it would be
    // strictly worse — it would need a rule for which screen wins, and the answer
    // would be wrong the moment that monitor was unplugged.
    IdleInhibitor {
        window:  root
        enabled: Idle.inhibited
    }

    readonly property var hyprMonitor:
        Hyprland.monitors.values.find(m => m.name === root.screen?.name) ?? null

    // The bar's pills float inside the bar's height, inset by barInset — except in
    // square mode, where they run flush to the screen edges.
    // Not readonly: the Behavior needs to drive it through intermediate values as
    // barShape flips, which a readonly property won't allow.
    // Anchored, the bar IS the top edge of the screen: flush at y=0, full height, no
    // margin to float in. `barInset` is simply not consulted there — the settings
    // slider says as much rather than moving something nobody can see.
    property int inset: (Config.barShape || Config.barAnchored) ? 0 : Config.barInset
    Behavior on inset { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // Horizontal inset. Fused, the outermost pills run FLUSH to the screen edge and
    // merge into the ring's side stubs — the pill and the strip become one piece of
    // material, which reads cleaner than a pill floating a flare's width inside a
    // stub it is supposed to have grown out of. So there is nothing to inset past.
    // Not readonly: same Behavior note as `inset`.
    property int sideInset: Config.frameFused ? 0 : inset
    Behavior on sideInset { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // ══ One surface behind three regions ═════════════════════════════════════
    // Left stays at the left edge, right at the right, centre on the workspaces
    // anchor. One surface spans from the left cluster's outer edge to the right
    // cluster's, filling the gaps between them. (There used to be pills shapes, a
    // surface per region with desktop between; they were scrapped.)
    //
    // ── Why not pack them together ────────────────────────────────────────────
    // An earlier version slid the clusters inward so the unified bar hugged its
    // content. It animated well and it was wrong: the bar pulled away from the
    // screen corners and left them empty, which reads as the bar having shrunk
    // rather than having merged. Widgets that live at the edges are there BECAUSE
    // they belong at the edges. Filling the gap is the merge; moving the content is
    // a different bar.

    // ── The span the unified surface covers ───────────────────────────────────
    // Read off the regions' live geometry rather than recomputed from insets, so it
    // stays correct while `sideInset` is animating (mode switches move it) and while
    // a region's width changes as modules come and go.
    readonly property real spanLeft:  leftRegion.x
    readonly property real spanRight: rightRegion.x + rightRegion.width

    // Opening a panel marks this screen as the one that owns it. Which column it
    // opens in is UiState's call (Config.panelSide) — the bar button just names
    // the panel it wants toggled.
    function openPanel(name) { UiState.activeScreen = root.screen; UiState.togglePanel(name) }

    // ── Which module owns an open panel ───────────────────────────────────────
    // A group keeps its pill expanded while a panel it launched is open, so the panel
    // visibly belongs to the button you pressed. With groups coming from data, the
    // group can't name its panel in advance — it asks whether any module inside it has
    // one open.
    function panelOpenFor(id) {
        switch (id) {
            case "palette":    return UiState.isOpen("colorScheme")
            case "wallpaper":  return UiState.isOpen("wallpaper")
            case "volume":     return UiState.isOpen("equalizer")
            case "wifi":       return UiState.isOpen("wifi")
            case "bluetooth":  return UiState.isOpen("bluetooth")
            case "update":     return UiState.updateOpen
            case "visualizer": return UiState.isOpen("media")
            case "nowplaying": return UiState.isOpen("media")
            case "clock":      return UiState.isOpen("clock")
            case "notifications": return UiState.isOpen("notifications")
            case "brightness": return UiState.isOpen("brightness")
            case "window":     return UiState.isOpen("window")
            case "layout":     return UiState.isOpen("layout")
            case "stats": case "clipboard": case "timer": case "claude":
            case "screentime": case "clips": case "inactivity": case "tasks":
                               return UiState.isOpen(id)
            default:           return false
        }
    }

    function groupExpanded(group) {
        for (const id of group) if (root.panelOpenFor(id)) return true
        return false
    }

    function regionExpanded(region) {
        for (const g of (Config.layout[region] ?? [])) if (root.groupExpanded(g)) return true
        return false
    }

    // ── Some modules hide themselves ──────────────────────────────────────────
    // Not a preference — a fact about the system: an empty tray, a battery pill on a
    // desktop. The rule lives in services/BarModules rather than here as a private
    // method — the settings page briefly rendered a second copy of the bar through the
    // same BarGroupRow (since removed, see BarPage's own header), and two copies of
    // "does this machine have a battery" would have been two answers waiting to
    // disagree.
    //
    // The wrapper stays because `moduleVisible` is the callback shape BarGroupRow
    // takes, and it is passed by name at three call sites below.
    function moduleVisible(id) { return BarModules.visible(id) }

    // ══ The module registry ═══════════════════════════════════════════════════
    // id → widget, with its wiring. The wiring has to live here (it reaches for
    // root.screen, root.hyprMonitor, UiState) — which is exactly why this is a map of
    // Components in the Bar rather than a lookup table in Config. Config knows what
    // modules ARE; only the bar knows how to build one.
    function moduleFor(id) {
        switch (id) {
            case "shapeToggle": return shapeToggleC
            case "modeToggle":  return modeToggleC
            case "palette":     return paletteC
            case "wallpaper":   return wallpaperC
            case "volume":      return volumeC
            case "keyboard":    return keyboardC
            case "update":      return updateC
            case "workspaces":  return workspacesC
            case "reload":      return reloadC
            case "tray":        return trayC
            case "visualizer":  return visualizerC
            case "wifi":        return wifiC
            case "bluetooth":   return bluetoothC
            case "battery":     return batteryC
            case "idle":        return idleC
            case "gamemode":    return gamemodeC
            case "nightlight":  return nightLightC
            case "privacy":     return privacyC
            case "clock":       return clockC
            case "notifications": return notificationsC
            case "overview":    return overviewC
            case "settings":    return settingsC
            case "brightness":  return brightnessC
            case "window":      return windowC
            case "layout":      return layoutC
            case "locks":       return locksC
            // The sidebar's modules, as pills (widgets/SideModulePill).
            case "stats":       return side_statsC
            case "clipboard":   return side_clipboardC
            case "timer":       return side_timerC
            case "claude":      return side_claudeC
            case "screentime":  return side_screentimeC
            case "inactivity":  return side_inactivityC
            case "tasks":       return side_tasksC
            case "clips":       return side_clipsC
            case "colour":      return side_colourC
            case "lens":        return side_lensC
            case "power":       return side_powerC
            case "tools":       return side_toolsC
            case "voice":       return side_voiceC
            case "nowplaying":  return nowplayingC
            case "dock":        return dockC
            default:            return null
        }
    }

    Component {
        id: shapeToggleC
        BarIconPill {
            moduleId:  "shapeToggle"
            symbol:    Config.barShape ? "fullscreen_exit" : "fullscreen"
            onClicked: Config.toggleShape()
        }
    }
    Component {
        id: modeToggleC
        // Flips the bar between its two silhouettes — floating, and on the frame.
        // (There were four; the pills shapes were scrapped.)
        BarIconPill {
            moduleId: "modeToggle"
            // Lit while the bar sits on the frame.
            active:    Config.barAnchored
            symbol:    "menu"
            onClicked: Config.cycleBarLayout()
        }
    }
    Component {
        id: paletteC
        BarIconPill {
            moduleId:  "palette"
            active:    UiState.isOpen("colorScheme")
            symbol:    "palette"
            onClicked: root.openPanel("colorScheme")
        }
    }
    Component {
        id: wallpaperC
        BarIconPill {
            moduleId:  "wallpaper"
            active:    UiState.isOpen("wallpaper")
            symbol:    "format_paint"
            onClicked: root.openPanel("wallpaper")
        }
    }
    Component {
        id: volumeC
        VolumePill {
            accent: Config.moduleAccent("volume", Colors.of(QsWindow.window).primary)
            active: UiState.isOpen("equalizer")
            onToggled: root.openPanel("equalizer")
        }
    }
    Component { id: keyboardC; KeyboardPill {} }
    Component {
        id: updateC
        UpdatePill {
            accent: Config.moduleAccent("update", Colors.of(QsWindow.window).primary)
            onRequested: function(count) {
                UiState.activeScreen       = root.screen
                UiState.pendingUpdateCount = count
                UiState.updateRequestId++
            }
        }
    }
    Component { id: workspacesC; WorkspacesPill {
        accent:  Config.moduleAccent("workspaces", Colors.of(QsWindow.window).primary)
        monitor: root.hyprMonitor
        glance:  workspaceGlance
    } }
    Component { id: reloadC;     ReloadPill { accent: Config.moduleAccent("reload", Colors.of(QsWindow.window).primary) } }
    Component { id: trayC;       TrayPill {
        accent:      Config.moduleAccent("tray", Colors.of(QsWindow.window).primary)
        contextMenu: trayMenuHost
    } }
    Component {
        id: visualizerC
        VisualizerPill {
            accent: Config.moduleAccent("visualizer", Colors.of(QsWindow.window).primary)
            active: UiState.isOpen("media")
            onToggled: root.openPanel("media")
        }
    }

    Component {
        id: wifiC
        WifiPill {
            accent: Config.moduleAccent("wifi", Colors.of(QsWindow.window).primary)
            active: UiState.isOpen("wifi")
            onToggled: root.openPanel("wifi")
        }
    }
    Component {
        id: bluetoothC
        BluetoothPill {
            accent: Config.moduleAccent("bluetooth", Colors.of(QsWindow.window).primary)
            active: UiState.isOpen("bluetooth")
            onToggled: root.openPanel("bluetooth")
        }
    }
    // Opens the Battery settings page rather than a panel of its own. Charge, health,
    // rate and the power profile already exist there in full, and a second, smaller
    // rendering of the same four facts is a maintenance liability, not a feature.
    // `active` stays false: the pill opens a page, it doesn't own a panel, so there
    // is no state of "this pill's surface is showing" for it to reflect.
    Component {
        id: batteryC
        BatteryPill {
            accent: Config.moduleAccent("battery", Colors.of(QsWindow.window).primary)
            onToggled: UiState.openSettingsTo("BatteryPage.qml")
        }
    }
    Component {
        id: clockC
        ClockPill {
            accent: Config.moduleAccent("clock", Colors.of(QsWindow.window).primary)
            active: UiState.isOpen("clock")
            onToggled: root.openPanel("clock")
        }
    }
    // Notifications / Do Not Disturb. Click opens the notification centre (the
    // sidebar's NotificationsPanel, as a bar panel); right-click toggles DND. The bell changes icon AND colour: bell-off
    // in the warning tint while DND is on, info-tinted when notifications are
    // waiting, muted otherwise.
    Component {
        id: notificationsC
        BarIconPill {
            moduleId: "notifications"
            active:   UiState.isOpen("notifications")
            // `quiet`, not `dnd`: while gamemode holds quiet the bell must show it,
            // or the bar claims notifications are arriving when they aren't. Right-click
            // still toggles the USER's switch — the only one a person owns. No fourth
            // colour for "held by something else": `info` already means "notifications
            // waiting" here, and the overview's card says which it is in words.
            //
            // ── Four states, one symbol each, all through `symbol` ────────────
            // This used to swap between `symbol` (the Material Symbols path) and
            // `icon` (this one SVG, for DND). IconButton sizes those two content
            // types differently — see contentExtent in IconButton.qml — so toggling
            // DND resized the pill and visibly shoved every other icon in the
            // group sideways. Every state going through the SAME content type
            // means the box never changes size, only what's drawn in it. (All four
            // were SVGs until 2026-10-31; now they're the font's, like the rest of
            // the bar, so they take the icon weight and fill while the panel is open.)
            symbol: Notifications.quiet       ? "bedtime"
                  : Notifications.hasCritical ? "notifications_active"
                  : Notifications.count > 0   ? "notifications_unread"
                  :                             "notifications"
            iconColor:  Notifications.quiet       ? Colors.of(QsWindow.window).warning
                      : Notifications.hasCritical ? Colors.of(QsWindow.window).danger
                      : Notifications.count > 0   ? Colors.of(QsWindow.window).info
                      :                             Colors.of(QsWindow.window).stateIdleFg
            onClicked:      root.openPanel("notifications")
            onRightClicked: Notifications.toggleDnd()
        }
    }
    // Stay awake. Click toggles YOUR hold; the glyph is a filled cup while anything is
    // holding and a crossed-out one otherwise.
    //
    // The colour carries a distinction that matters the moment gamemode exists: accent
    // means you set this and clicking will clear it, `info` means something else is
    // holding it and clicking will not. Without that, turning gamemode on and then
    // clicking the lit pill looks like a button that does nothing.
    Component {
        id: idleC
        BarIconPill {
            id: idlePill
            moduleId:   "idle"
            active:     Idle.inhibited
            symbol:     Idle.inhibited ? "coffee" : "no_drinks"
            symbolFill: Idle.inhibited ? 1 : 0
            iconColor:  Idle.manual         ? idlePill.accent
                      : Idle.heldExternally ? Colors.of(QsWindow.window).info
                      :                       Colors.of(QsWindow.window).stateIdleFg
            onClicked:  Idle.toggleManual()
        }
    }
    // Gamemode. Click opens the Gaming panel (the switch, the GPU/CPU glance, the
    // per-effect toggles, the MangoHud preset) — same as the wallpaper and wifi pills
    // open theirs. Right-click is the quick toggle for muscle memory; SUPER+G does it too.
    //
    // The pill still lights on `Gamemode.active`. It also changes the idle pill, which
    // turns info-tinted while gamemode holds it to say the hold is not yours to clear.
    // The microphone-in-use indicator. Hides itself when nothing is recording, so it
    // costs a slot in the layout and no pixels the rest of the time.
    Component {
        id: privacyC
        PrivacyPill {}
    }
    // ── Night light ───────────────────────────────────────────────────────────
    // Click warms the screen, click again clears it. The pill is lit whenever the
    // warmth is actually ON SCREEN — `NightLight.shouldBeOn`, not `Config.nightLight` —
    // because in auto mode those two differ for most of the day, and a pill lit at
    // noon because a schedule is armed would be claiming something untrue about what
    // you are looking at.
    //
    // A machine with neither hyprsunset nor gammastep hides the pill rather than
    // offering a switch that cannot work: same contract as the bluetooth and battery
    // pills, which hide themselves on hardware that hasn't got the thing.
    Component {
        id: nightLightC
        BarIconPill {
            id: nightPill
            moduleId:   "nightlight"
            visible:    NightLight.available
            active:     NightLight.shouldBeOn
            symbol:     NightLight.shouldBeOn ? "bedtime" : "brightness_4"
            symbolFill: NightLight.shouldBeOn ? 1 : 0
            iconColor:  NightLight.shouldBeOn ? nightPill.accent : Colors.of(QsWindow.window).stateIdleFg
            onClicked:  NightLight.toggle()
        }
    }
    Component {
        id: gamemodeC
        BarIconPill {
            id: gamePill
            moduleId:   "gamemode"
            active:     Gamemode.active
            symbol:     Gamemode.active ? "sports_esports" : "videogame_asset_off"
            symbolFill: Gamemode.active ? 1 : 0
            iconColor:  Gamemode.active ? gamePill.accent : Colors.of(QsWindow.window).stateIdleFg
            onClicked:      root.openPanel("gaming")
            onRightClicked: Gamemode.toggle()
        }
    }
    // ── Brightness ────────────────────────────────────────────────────────────
    // Scroll dims the monitor THIS bar is on; click opens every display's slider
    // (BrightnessPanel). The service is probed the first time the pill exists — a
    // ddcutil detect, once a session — never for someone who hasn't placed it.
    function brightnessIndex() {
        const name = root.screen ? root.screen.name : ""
        for (let i = 0; i < Brightness.monitors.count; i++)
            if (Brightness.monitors.get(i).port === name) return i
        return -1
    }
    Component {
        id: brightnessC
        BarIconPill {
            moduleId:  "brightness"
            active:    UiState.isOpen("brightness")
            symbol:    "brightness_6"
            Component.onCompleted: Brightness.ensureProbed()
            onClicked: root.openPanel("brightness")
            onScrolled: function (d) {
                const i = root.brightnessIndex()
                if (i < 0) return
                const m = Brightness.monitors.get(i)
                Brightness.requestBrightness(i, Brightness.clampFor(m.type, m.brightness + d * 5))
            }
        }
    }
    // ── The focused window ────────────────────────────────────────────────────
    Component {
        id: windowC
        WindowPill {
            monitorName: root.screen ? root.screen.name : ""
            active: UiState.isOpen("window")
            onClicked: root.openPanel("window")
        }
    }
    // ── Hyprland's layout ─────────────────────────────────────────────────────
    // Scroll steps through the layouts live; click for the panel.
    Component {
        id: layoutC
        BarIconPill {
            moduleId:  "layout"
            active:    UiState.isOpen("layout")
            symbol:    HyprLayout.info.symbol
            onClicked: root.openPanel("layout")
            onScrolled: function (d) { HyprLayout.step(d > 0 ? -1 : 1) }
        }
    }
    // ── Submap / Caps / Num ───────────────────────────────────────────────────
    Component {
        id: locksC
        LocksPill {}
    }

    // ── The sidebar's modules, as pills ───────────────────────────────────────
    // One file keyed by id (SideModulePill); a Component each, because a Component
    // can't take an argument.
    Component { id: side_statsC;      SideModulePill { moduleId: "stats"; screen: root.screen } }
    Component { id: side_clipboardC;  SideModulePill { moduleId: "clipboard"; screen: root.screen } }
    Component { id: side_timerC;      SideModulePill { moduleId: "timer"; screen: root.screen } }
    Component { id: side_claudeC;     SideModulePill { moduleId: "claude"; screen: root.screen } }
    Component { id: side_screentimeC; SideModulePill { moduleId: "screentime"; screen: root.screen } }
    Component { id: side_inactivityC; SideModulePill { moduleId: "inactivity"; screen: root.screen } }
    Component { id: side_tasksC;      SideModulePill { moduleId: "tasks"; screen: root.screen } }
    Component { id: side_clipsC;      SideModulePill { moduleId: "clips"; screen: root.screen } }
    Component { id: side_colourC;     SideModulePill { moduleId: "colour"; screen: root.screen } }
    Component { id: side_lensC;       SideModulePill { moduleId: "lens"; screen: root.screen } }
    Component { id: side_powerC;      SideModulePill { moduleId: "power"; screen: root.screen } }
    Component { id: side_toolsC;      SideModulePill { moduleId: "tools"; screen: root.screen } }
    Component { id: side_voiceC;      SideModulePill { moduleId: "voice"; screen: root.screen } }
    // Now playing: the sidebar's cover cell, then its transport buttons (NowPlayingPill).
    Component { id: nowplayingC;      NowPlayingPill { screen: root.screen } }
    // The dock: the sidebar's strip at the bar's size; what hangs off it is barDockPopups.
    Component { id: dockC;            DockPill { screen: root.screen; monitor: root.hyprMonitor; popups: barDockPopups } }

    Component {
        id: overviewC
        BarIconPill {
            moduleId:  "overview"
            active:    UiState.overviewOpen
            symbol:    "menu"
            onClicked: UiState.toggleOverview()
        }
    }
    Component {
        id: settingsC
        BarIconPill {
            moduleId: "settings"
            // Reflects the settings WINDOW now, not the overview's page — that is
            // where this button goes, so it is what "active" has to mean.
            active:    UiState.settingsWindowOpen
            symbol:    "settings"
            // Toggle rather than open: this is a bar pill you press twice, and an
            // open-only gear leaves the only way out being to go find the window.
            onClicked: UiState.toggleSettingsWindow()
        }
    }

    // ══ THE UNIFIED SURFACE ═══════════════════════════════════════════════════
    // One pill spanning all three clusters, for the two unified modes. Declared
    // BEFORE the regions so it paints behind them — the widgets sit inside it.
    //
    // It is the region pill's recipe at a different width, deliberately: same
    // elevation, same roundness, same border, same fill opacity, so a mode switch
    // changes the bar's SHAPE and nothing about its material. Anything else here
    // would be a second definition of what a bar surface looks like.
    //
    // Its span is read live off the regions (root.spanLeft/spanRight), so it
    // contracts as they slide together rather than snapping to its final width.
    Item {
        id: unifiedBar

        readonly property bool fused: Config.frameFused
        readonly property bool bandVisible: Config.frameBandVisible
        readonly property int  groupOrigin: Config.barShape ? 0 : Config.barInset
        // Same clearance the regions take: the pill re-seats against the band's
        // underside instead of overlapping it. Not readonly — the Behavior has to
        // drive it through intermediate values.
        property real fuseDrop: unifiedBar.bandVisible
                              ? Math.max(0, Config.frameDepth - unifiedBar.groupOrigin) : 0
        Behavior on fuseDrop { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        readonly property bool hovered:
            leftRegion.hovered || center.hovered || rightRegion.hovered

        // ── Bleeding the outer border off-screen ──────────────────────────
        // Anchored, this bar's top/left/right edges ARE the screen's edges, and a
        // Rectangle cannot drop its border on one side only. Drawn in place, the
        // top border becomes a bright 1px rule along the very top of the display —
        // measured at (194,188,191) against a (39,20,34) bar, which is the line
        // that read as "the bar has a weird edge".
        //
        // So the surface is grown by one borderWidth on each screen-facing side.
        // The border lands outside the layer-shell surface and is clipped away,
        // leaving only the inner edges drawn — the same trick BarRegion already
        // uses for a pill merged into a side strip.
        readonly property real bleed: unifiedBar.fused ? Config.barBorderWidth : 0

        x:      root.spanLeft - unifiedBar.bleed
        y:      root.inset + unifiedBar.fuseDrop - unifiedBar.bleed
        width:  Math.max(0, root.spanRight - root.spanLeft) + unifiedBar.bleed * 2
        height: Math.max(0, Config.barSurfaceHeight - unifiedBar.fuseDrop)
                + unifiedBar.bleed

        // No Behavior on x/width/y/height: every input is either already easing
        // (the regions' x, fuseDrop, inset) or changes discretely. Easing them here
        // too would be the chase Motion.qml opens with.

        Surface {
            anchors.fill: parent
            elevation:    Tokens.elevationBar
            squareMode:   Config.barShape
            // Anchored, every corner is square: the bar spans edge to edge and its
            // underside is met by the frame's side strips on concave arcs
            // (BarFrameEdge). A rounded bottom corner there curves AWAY from the
            // strip and opens a wedge of wallpaper between the two — which is what
            // made the anchored corners look unfinished.
            squareTop:    unifiedBar.fused
            squareLeft:   unifiedBar.fused
            squareRight:  unifiedBar.fused
            cornerRadius: Config.barRoundness
            // ── Borderless only when the FRAME is drawing that line ───────────
            // Fused with a frame, BarFrameEdge carries one unbroken stroke from the
            // left stub, round the arc, under the bar and out the other side — so
            // the bar contributes none, and there is no join anywhere to misalign.
            //
            // This was `fused ? 0 : barBorderWidth`, which asked only whether the
            // bar was anchored. Anchored WITHOUT a frame there is no BarFrameEdge
            // (it is gated on `visible: Config.screenFrame`), so nothing drew the
            // line at all and "Bar on frame" had no bottom edge on any wallpaper.
            //
            // Where the bar does draw it, the bleed above is what keeps it to one
            // side: the surface is grown a borderWidth on each SCREEN-FACING edge,
            // so those three strokes land outside the layer-shell surface and are
            // clipped, leaving exactly the bottom.
            //
            // See Config.barDrawsUnderline for the full table.
            borderWidth:  Config.barDrawsUnderline ? Config.barBorderWidth : 0
            // Welded into the ring, so there is nothing below it to cast onto —
            // the frame's stubs and corners are drawn behind this very surface.
            // See Surface.castsShadow.
            castsShadow:  !Config.barAnchored
            focused:      unifiedBar.hovered
            fillOpacity:  Tokens.barOpacity
            // Without this, the Bar page's "Opacity" slider could never actually
            // reach opaque: this Surface didn't override the item's own opacity,
            // so it defaulted to Tokens.surfaceOpacity (Settings → Appearance's
            // OWN, separate slider) and multiplied with fillOpacity — 100% here
            // still rendered at whatever the Appearance page happened to be set
            // to. See Surface.itemOpacity.
            itemOpacity:  1.0
            // While the blob draws the cookie field (Drift.inBlob) the bar's band is the blob's ring —
            // the same fill (frameFill is this surface's recipe), with the cookies in it. Painted again
            // here it would hide them; transparent, the pills stand straight on the material.
            color:        Drift.inBlob ? "transparent"
                                       : Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationBar), Tokens.barOpacity)
        }

    }

    // ── Cookies in the bar's band and the frame (Config.barCookies; see FrameDrift) ──
    // Directly after the bar's own surface, which would hide them from anywhere below it, and before
    // the regions (the pills), which sit over them.
    FrameDrift {
        part: "ring"
        anchors.fill: parent
        screenW: sideRail.screenW
        screenH: sideRail.screenH
        strip: sideRail.strip
        topH:  Config.barAnchored ? Config.barSurfaceHeight : 0
        screenName: root.screen?.name ?? ""
    }

    // ══ LEFT ══════════════════════════════════════════════════════════════════
    BarRegion {
        id: leftRegion

        anchors.top:        parent.top
        anchors.left:       parent.left
        anchors.topMargin:  root.inset
        anchors.leftMargin: root.sideInset

        forceExpanded: root.regionExpanded("left")

        BarGroupRow {
            region: "left"
            componentFor:  root.moduleFor
            moduleVisible: root.moduleVisible
            // Arrange mode: the real modules become drag sources and drop targets.
            // The drag they start is a PLATFORM drag (see BarGroupRow's dragProxy),
            // so it leaves this layer-shell surface and can be dropped on the
            // settings window's module catalogue to take the module off the bar.
            slotsArranging: UiState.barArrange
        }
    }

    // ══ CENTER ════════════════════════════════════════════════════════════════
    // Positioned so the WORKSPACES group lands on the true screen center, rather than
    // centering the region as a whole. Otherwise the workspace dots — the bar's visual
    // anchor — would drift sideways every time an app added or removed a tray icon, or
    // whenever the keyboard-layout tag changed width.
    BarRegion {
        id: center

        anchors.top:       parent.top
        anchors.topMargin: root.inset

        forceExpanded: root.regionExpanded("centre")

        // ── Finding the anchor group, now that groups are data ────────────────
        // This used to read `keyboardGroup.width + gap + mainGroup.width / 2` off two
        // ids, because the layout was written here and those groups were guaranteed to
        // exist. Neither is true now: the user can drag workspaces anywhere, into any
        // group, or remove it entirely.
        //
        // So: find whichever group CONTAINS workspaces, sum the widths of the groups
        // before it, and centre on that group. With workspaces gone there is no anchor
        // to hold, and the region simply centres itself — which is the honest answer,
        // not a fallback.
        readonly property int anchorGroup: {
            // Anchoring turned off: report "no anchor" and let anchorOffset fall through
            // to centring the region as a whole. The no-workspaces case already had to
            // mean exactly that, so the setting doesn't need a second code path — it
            // just takes the one that was already there.
            if (!Config.barCentreAnchor) return -1

            const groups = Config.layout.centre ?? []
            for (let i = 0; i < groups.length; i++)
                if (groups[i].indexOf("workspaces") !== -1) return i
            return -1
        }

        readonly property real anchorOffset: {
            // Touch the repeater's count so this re-runs as groups are built —
            // itemAt() is not itself a bindable dependency, and without this the
            // offset would be computed once against an empty repeater and stick.
            const n = centerGroups.count
            if (center.anchorGroup < 0 || n === 0) return center.width / 2

            let lead = 0
            for (let i = 0; i < center.anchorGroup && i < n; i++) {
                const item = centerGroups.itemAt(i)
                if (item && item.visible) lead += item.width + center.gap
            }
            const anchor = centerGroups.itemAt(center.anchorGroup)
            return center.edgePad + lead + (anchor ? anchor.width / 2 : 0)
        }

        // ── Never let this region overlap its neighbours ──────────────────────
        // True-centre anchoring (above) pins this region to the screen's midpoint
        // regardless of how wide it or its neighbours are — nothing previously
        // stopped a long track title, a crowded tray, or a bigger `resScale` (see
        // Config.resScale) from pushing this region's box under the left or right
        // one, which reads as pills rendering on top of each other.
        //
        // Clamped to the left region's right edge and the right region's left
        // edge, each with a minimum gap. If the bar is so crowded even that has no
        // room (both clamps disagree), this favours not overlapping the LEFT
        // region and accepts the lesser failure on the right — left-to-right
        // reading order makes that the less confusing thing to see happen.
        readonly property int overlapGap: Tokens.spacingMd
        readonly property real overlapMinX: leftRegion.x + leftRegion.width + center.overlapGap
        readonly property real overlapMaxX: rightRegion.x - center.overlapGap - center.width

        x: Math.max(center.overlapMinX,
                     Math.min(Math.round(root.width / 2 - center.anchorOffset), center.overlapMaxX))

        BarGroupRow {
            id: centerGroups
            region: "centre"
            componentFor:  root.moduleFor
            moduleVisible: root.moduleVisible
            // Arrange mode: the real modules become drag sources and drop targets.
            // The drag they start is a PLATFORM drag (see BarGroupRow's dragProxy),
            // so it leaves this layer-shell surface and can be dropped on the
            // settings window's module catalogue to take the module off the bar.
            slotsArranging: UiState.barArrange
        }
    }

    // ══ RIGHT ═════════════════════════════════════════════════════════════════
    BarRegion {
        id: rightRegion

        anchors.top:         parent.top
        anchors.right:       parent.right
        anchors.topMargin:   root.inset
        anchors.rightMargin: root.sideInset

        forceExpanded: root.regionExpanded("right")

        BarGroupRow {
            region: "right"
            componentFor:  root.moduleFor
            moduleVisible: root.moduleVisible
            // Arrange mode: the real modules become drag sources and drop targets.
            // The drag they start is a PLATFORM drag (see BarGroupRow's dragProxy),
            // so it leaves this layer-shell surface and can be dropped on the
            // settings window's module catalogue to take the module off the bar.
            slotsArranging: UiState.barArrange
        }
    }

    // ══ THE ENTRANCE ══════════════════════════════════════════════════════════
    // Holds everything in this window (it adopts its siblings — see IntroStage). The
    // band drops out of the top edge: content starts one bar above its rest, clipped to
    // the bar's band, and lands as Intro.bar completes. Then the front leaves the band
    // and runs down the screen, so the frame's sides (the blob's ring, BarFrameEdge),
    // the sidebar and the dock appear as it passes — the same front ScreenFrame's
    // overlay clips to, from the same arguments. Inert once the entrance is over.
    IntroStage {
        front: Intro.front(Config.barExtent + Config.frameApron, root.screen?.height ?? root.height)
        lift:  (1 - Intro.bar) * Config.barExtent
    }

    // ══ THE RING'S OUTLINE, ON TOP OF EVERYTHING ══════════════════════════════
    // The other half of BarFrameEdge, and the last thing declared in this file.
    //
    // Anchored, the line under the bar and the bar's own bottom edge are the same
    // line. Drawn behind the bar — which is where this file's single mount used to
    // be — it is painted over by the bar's own fill and never appears at all. In
    // front, it is one continuous stroke over the bar's underside, drawn once,
    // with the stubs and arcs it is already continuous with.
    //
    // It also lands on top of the eraser above, which is what lets that eraser be a
    // plain rectangle: it can cover the arc freely, because the arc is drawn after
    // it. The arc-redraw FrameFusion briefly carried is gone with it.
    BarFrameEdge {
        anchors.fill: parent
        part: "line"
        // Off while the blob owns the ring: the blob's own SDF outline already runs
        // this line, continuous with every panel welded into it. Two strokes for one
        // edge is the doubled, forking junction this whole thing was chasing.
        visible: Config.screenFrame && !root.blobRing
    }

    // ScreenFrame's overlay reads this across the window boundary and unmaps itself.
    Binding {
        target: UiState
        property: "blobRingOwned"
        value: root.blobRing && Config.screenFrame
        when: root.screen === Quickshell.screens[0]
    }

    // ══ THE DOCK ══════════════════════════════════════════════════════════════
    // The persistent app dock, welded into the frame's bottom (or side) strip by
    // the blob the way panels weld into the bar — which is why it lives in this
    // window rather than its own. See DockHost.qml; its exclusive zone is
    // modules/dock/DockReserve, since this window already reserves the top edge.
    //
    // Declared BEFORE the panel docks so a panel opened over a side dock paints
    // over it: the panel is what you just asked for. Screen-sized at the window's
    // origin — it positions itself against the screen's edges, not the bar's.
    // ── The side rail ─────────────────────────────────────────────────────────
    // The edge the dock stands on, and the stats pill with it: one layout for
    // both (SideRail), stepped down past whichever of the panel cards is open
    // over it — or, unified, holding its side's panels on its face instead.
    SideRail {
        id: sideRail
        screenW: dockHost.width
        screenName: root.screen?.name ?? ""
        screenH: dockHost.height
        // Keyed by the ids in Config.sidebarLayout — the big module's (the dock);
        // the rail works the small ones' out itself.
        lengths: ({ dock: dockHost.length })
        barShown:    sideBarHost.shownState
        cross:       sideBarHost.cross
        cards: [
            { side: "left",   x: panelDock.x + panelDock.leftCardX,   y: panelDock.y + panelDock.leftCardY,
              w: panelDock.leftCardW,   h: panelDock.leftCardH },
            { side: "right",  x: panelDock.x + panelDock.rightCardX,  y: panelDock.y + panelDock.rightCardY,
              w: panelDock.rightCardW,  h: panelDock.rightCardH },
            { side: "center", x: panelDock.x + panelDock.centerCardX, y: panelDock.y + panelDock.centerCardY,
              w: panelDock.centerCardW, h: panelDock.centerCardH }
        ]
    }

    // The sidebar's bar: one bar behind everything on the edge, the
    // way the top bar sits behind its groups. Declared first so the modules paint
    // over it; they follow its reveal while it's up.
    SideBarHost {
        id: sideBarHost
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height:  root.screen?.height ?? 1080
        monitor: root.hyprMonitor
        rail:    sideRail
        // …a small group under the pointer, and a panel hanging off its face
        // (SideRail.holdingPanel).
        engaged: dockHost.engaged || sideRail.smallHovered > 0 || sideRail.holdingPanel
                 || sidePanelDock.engaged
        deformMatrix: root.sidebarDeform
    }
    // Unified, the modules ride the bar's spring, not their own (parked) lobes'.
    readonly property matrix4x4 sidebarDeform: blobLayer.item?.sidebarDeform ?? Qt.matrix4x4()

    // …and the sidebar's: after its body, before the dock's icons and the small modules.
    FrameDrift {
        part: "side"
        anchors.fill: parent
        screenW: sideRail.screenW
        screenH: sideRail.screenH
        strip: sideRail.strip
        topH:  Config.barAnchored ? Config.barSurfaceHeight : 0
        // The sidebar's own body (its `lobe`), not its blob geometry — that is zero unless the weld is
        // on, and the cookies belong on the sidebar either way.
        sideX: sideBarHost.maskItem?.x ?? 0
        sideY: sideBarHost.maskItem?.y ?? 0
        sideW: sideBarHost.maskItem?.visible ? sideBarHost.maskItem.width  : 0
        sideH: sideBarHost.maskItem?.visible ? sideBarHost.maskItem.height : 0
        screenName: root.screen?.name ?? ""
    }

    // The sidebar's inner pills, one per region with a divider between its groups — under
    // the dock's icons and the small modules, which stand on them (SideRegionPills).
    SideRegionPills {
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height: root.screen?.height ?? 1080
        rail:   sideRail
        deformMatrix: root.sidebarDeform
    }

    DockHost {
        id: dockHost
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        height:  root.screen?.height ?? 1080
        screen:  root.screen
        monitor: root.hyprMonitor
        rail:    sideRail
        deformMatrix:  root.sidebarDeform
        previewDeform: blobLayer.item?.previewDeform ?? Qt.matrix4x4()
        // Above the panels only while an app is dragged out of the launcher, so the
        // icon in the hand (drawn by the dock) isn't hidden under the launcher.
        z: UiState.appDragKey !== "" ? 50 : 0
    }

    // The small modules (the stats and clips buttons, Power, Shell tools…): a pill
    // per group of them, riding the sidebar's own reveal (SideGroupHost). Keyed on
    // each group's ids, so a group that only moves keeps its delegate.
    Repeater {
        model: ScriptModel { values: sideRail.smallGroups.map(g => g.key) }

        SideGroupHost {
            required property string modelData
            // A removed group's delegate is unparented before it's destroyed.
            anchors.top:   parent ? parent.top : undefined
            anchors.left:  parent ? parent.left : undefined
            anchors.right: parent ? parent.right : undefined
            height:   root.screen?.height ?? 1080
            rail:     sideRail
            groupKey: modelData
            screen:   root.screen
            monitor:  root.hyprMonitor
            contextMenu: trayMenuHost
            deformMatrix: root.sidebarDeform
        }
    }

    // A sidebar button's panel (the stats, the clips): beside its button, melted
    // out of the sidebar's face (SidePanelDock). After the modules, so it paints over
    // the sidebar's band as it melts out of it; before the bar's panel docks, whose
    // column on the sidebar's side it never shares the screen with (UiState).
    SidePanelDock {
        id: sidePanelDock
        anchors.fill: parent
        rail: sideRail
        owns: UiState.sidePanelScreen ? UiState.sidePanelScreen === root.screen
                                      : root.screen === Quickshell.screens[0]
        deformMatrix: blobLayer.item?.sidePanelDeform ?? Qt.matrix4x4()
    }

    // The OSD's sliders (volume, brightness, mic), melted out of the right edge of the
    // frame. After the sidebar's panels so, sharing an edge, it paints over them; it
    // answers a key rather than a click, so it never competes for the same moment.
    // Under a fullscreen window this layer is hidden and modules/osd/OsdSliders answers.
    OsdDock {
        id: osdDock
        anchors.fill: parent
        rail: sideRail
        forScreen: root.screen
        deformMatrix: blobLayer.item?.osdDeform ?? Qt.matrix4x4()
    }

    // The power menu as a column welded into the right edge (modules/bar/PowerDock). Declared
    // after the OSD's so it paints over it (the OSD is quiet while the menu is up), and before
    // the bar's panel docks so a panel opened over it still wins. Under a fullscreen window this
    // layer is hidden, so PowerDock drops the request there.
    PowerDock {
        id: powerDock
        anchors.fill: parent
        rail: sideRail
        forScreen: root.screen
        deformMatrix: blobLayer.item?.powerDeform ?? Qt.matrix4x4()
    }

    // Arranging the sidebar: the REAL sidebar becomes the editor, as the bar does
    // (SideArrange, BarArrange's twin). Behind a Loader, so it costs nothing unless
    // Sidebar › Layout is open; above the sidebar's modules, whose handles it is.
    Loader {
        id: sideArrangeHost
        anchors.fill: parent
        active: UiState.sidebarArrange
        // ABOVE the bar's arrange layer (arrangeHost, z 60, declared later): its
        // "off the bar" shelf is a full-width band under the bar, and on a left or
        // right edge it covers the sidebar's first modules. Qt gives a drag to the
        // topmost DropArea, so a module dragged off the bar onto the sidebar's top
        // was taken off the bar instead (2026-11-08). SideArrange only has targets
        // over the sidebar and the room beside it, so it shadows nothing of the bar's.
        z: 61
        sourceComponent: SideArrange {
            rail: sideRail
            deformMatrix: blobLayer.item?.arrSideDeform ?? Qt.matrix4x4()
        }
    }

    // ══ THE PANELS THAT DROP OUT OF THE BAR ══════════════════════════════════
    // Declared after BarFrameEdge's "line" mount above, which matters: that mount
    // draws the ring's outline — including the rule along the bar's UNDERSIDE —
    // on top of everything else in this window. A panel welding into that
    // underside has to be able to erase the segment it welds across, and it can
    // only do that by painting over it. See BarDock's `underlineErase`.
    //
    // ── The left/right panel groups ───────────────────────────────────────────
    // Formerly two PanelWindows of their own in modules/panels/PanelHost.qml. In
    // this window so Quicktest.Blobs can actually melt them out of the bar; see
    // BarPanelDock.qml and the note on implicitHeight above.
    BarPanelDock {
        id: panelDock
        anchors.top:       parent.top
        anchors.left:      parent.left
        anchors.right:     parent.right
        anchors.topMargin: panelDock.topMargin
        height:  panelDock.maxHeight
        screenH: root.screen?.height ?? 1080
        // An IPC call or a bound key carries NO screen context, so activeScreen can
        // legitimately be unset — and a strict equality test then makes EVERY screen
        // disown the panel and nothing renders at all, while UiState still reports it
        // open. Falls back to the first screen.
        owns:    UiState.activeScreen ? UiState.activeScreen === root.screen
                                      : root.screen === Quickshell.screens[0]

        // The unified sidebar's face on its side: that side's panels hang off it
        // rather than dropping over it (SideRail's header).
        leftFace:  sideRail.edge === "left"  ? sideRail.panelFace : 0
        rightFace: sideRail.edge === "right" ? sideRail.panelFace : 0

        // Identity when the plugin isn't built — the docks just don't deform.
        leftDeform:  blobLayer.item?.leftDeform  ?? Qt.matrix4x4()
        rightDeform:  blobLayer.item?.rightDeform  ?? Qt.matrix4x4()
        centerDeform: blobLayer.item?.centerDeform ?? Qt.matrix4x4()
    }

    // ── The notification deck ─────────────────────────────────────────────────
    // Hosted here so the blob can melt the front toast out of the bar. It hands the
    // deck back to NotificationOverlay's own Overlay-layer window while something is
    // fullscreen — see BarToastHost. Costs nothing when idle: `live` empties the
    // model, so the stack holds no delegates at all.
    BarToastHost {
        id: toastHost
        anchors.top:   parent.top
        anchors.right: parent.right
        anchors.topMargin: toastHost.topMargin
        height:  toastHost.maxHeight
        screenH: root.screen?.height ?? 1080
        screen:  root.screen
    }

    // ── The docked settings panel ─────────────────────────────────────────────
    // SettingsWindow's alternative (Config.settingsPanel on): the settings card
    // welded into the frame's bottom strip. In this window rather than its own for
    // the same reason BarPanelDock is — cross-surface blob fusion is
    // impossible. See SettingsPanelHost.qml. Fills the window (like BarContextMenu)
    // because it positions itself against the screen's own bottom edge, not the
    // bar's.
    SettingsPanelHost {
        id: settingsHost
        anchors.fill: parent
        screenH: root.screen?.height ?? 1080
        owns: UiState.activeScreen ? UiState.activeScreen === root.screen
                                   : root.screen === Quickshell.screens[0]
    }

    // ── The tray's context menu ───────────────────────────────────────────────
    // Fills the whole window (not a partial anchor like the hosts above) — it needs
    // the true (0,0) origin to position itself under WHICHEVER tray icon on
    // WHICHEVER region was clicked, and its dismiss layer has to cover every pill,
    // not just its own corner. See BarContextMenu.qml.
    // ── The bar dock's previews, jump list and keyboard (widgets/DockPill) ─────
    // Fills the window like the tray menu, for the same reason: a card stands under
    // whichever icon was hovered, and the menu's dismiss layer covers every pill.
    BarDockPopups {
        id: barDockPopups
        anchors.fill: parent
        z: 50
        monitor: root.hyprMonitor
    }

    // ── The workspace pill's glance ───────────────────────────────────────────
    // A card of the hovered workspace's windows, melted out of the bar's underside. Fills the
    // window like the dock's popups, for the same reason: it stands under whichever slot.
    WorkspaceGlance {
        id: workspaceGlance
        anchors.fill: parent
        z: 50
        monitor: root.hyprMonitor
        welded: root.blobRing
        deformMatrix: blobLayer.item?.glanceDeform ?? Qt.matrix4x4()
    }

    // ── Tips ──────────────────────────────────────────────────────────────────
    // A pill's tip melts out of the bar (welded); every other tip is the bubble below.
    PillTip {
        id: pillTip
        anchors.fill: parent
        z: 50
        // Not while arranging: the arrange cards hang from the same edges.
        welded: root.blobRing && !UiState.arrange
        except: settingsHost
        // Beside a sidebar the card stays off its face.
        clearLeft:  !UiState.sidebarHidden && sideRail.edge === "left"  ? sideRail.band : 0
        clearRight: !UiState.sidebarHidden && sideRail.edge === "right" ? sideRail.band : 0
        deformMatrix: blobLayer.item?.tipDeform ?? Qt.matrix4x4()
    }

    // The tooltip of everything this window draws: a bar pill's "what is it doing" and a panel
    // control's explanation (components/HelpTip). The docked settings card draws its own.
    TipBubble {
        host: root.contentItem
        except: settingsHost
        skipPills: root.blobRing
        z: 90
    }

    BarContextMenu {
        id: trayMenuHost
        anchors.fill: parent
        deformMatrix: blobLayer.item?.trayDeform ?? Qt.matrix4x4()
        blobWeld: root.blobRing
        // Beside the sidebar (SideTray): melted out of its face when the sidebar is welded.
        sideWelded: sideRail.welded && root.blobRing
        sideFace: sideRail.band
    }

    // ══ ARRANGE MODE ══════════════════════════════════════════════════════════
    // The desktop dims and the snap dots show while arranging, as they do for the desktop widgets
    // (z under the blob layer and everything this window draws); the way out is the button below
    // and Escape, as the widgets' is.
    ArrangeBackdrop {
        anchors.fill: parent
        z: -2
        shown: UiState.arrange
        monitor: root.hyprMonitor
    }
    PanelButton {
        id: arrangeDone
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingXxl * 2
        z: 70
        visible: UiState.arrange
        variant: "primary"
        symbol: "check"
        label: Translation.tr("Done arranging")
        onActivated: UiState.arrange = false
    }
    Item {
        focus: UiState.arrange
        Keys.onEscapePressed: UiState.arrange = false
    }

    // The region labels, the region drop targets, the shelf of modules that are not
    // on the bar, and the ghost. Declared last so all of it paints above the pills it
    // is annotating — the ghost in particular has to be over everything, since it
    // travels across all three regions and down onto the shelf.
    //
    // The draggable modules are NOT in here: they are the real ones, turned into drag
    // sources by `slotsArranging` on the three BarGroupRows above. That is the point
    // of the mode — the bar is the editor, not a picture of one.
    //
    // Loader-gated, so a bar nobody is arranging costs nothing. The shelf builds a
    // real widget per unplaced module, which is not cheap, and `active` keeps all of
    // that out of existence until the Bar settings page is actually open.
    //
    // `shelfHeight` is read off this even while inactive (root.arrangeRoom), so it is
    // declared on the Loader rather than only inside the component — otherwise the
    // window's reserved room would depend on an object that does not exist yet.
    Loader {
        id: arrangeHost

        // The band below the bar that a module is dragged into to come off it.
        //
        // It was `Tokens.pillHeight + spacingXl * 2 + 22` — room for a raised card
        // holding a row of real widget previews. There is no card and there are no
        // widgets any more (see BarArrange): what is down there is one line of text
        // and the room to aim at. Sized for that instead, which takes ~60px of screen
        // off the desktop while arranging rather than ~90.
        //
        // Still a fixed ceiling and still never animated: it feeds the window's
        // implicitHeight, and animating that resizes the actual Wayland surface every
        // frame. Same discipline as the window's own ceiling above.
        readonly property real shelfHeight: Tokens.spacingXl * 2 + 56

        anchors.fill: parent
        active: UiState.barArrange
        z: 60

        sourceComponent: BarArrange {
            leftItem:   leftRegion
            centreItem: center
            rightItem:  rightRegion
            barHeight:    Config.barExtent
            shelfHeight:  arrangeHost.shelfHeight
            fused:        root.blobRing
            deformMatrix: blobLayer.item?.arrBarDeform ?? Qt.matrix4x4()
            // The bar's OWN factory, so the shelf and the ghost are built from the
            // same catalogue the bar renders from rather than a second copy.
            componentFor: root.moduleFor
        }
    }

    // Leaving the mode mid-gesture would strand `dragId` set, so the next entry would
    // begin already dragging a module the pointer is nowhere near. Closing the
    // settings window while holding one is an ordinary way to do that.
    Connections {
        target: UiState
        function onArrangeChanged() {
            if (UiState.arrange) return
            BarDrag.cancel()
            SideDrag.cancel()
        }
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // A wallpaper or colour change: this window — the bar, every panel hanging off
    // it, the dock, the sidebar, and the frame whenever the blob draws it — keeps its
    // old look as a snapshot, and the new colours spread across it from the bottom
    // middle of the screen on the same front as the new wallpaper, glowing in the new
    // accent as they go. The window is anchored to the screen's top-left corner, so
    // its own coordinates are the screen's. LAST, so it is over everything here.
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
    }
}
