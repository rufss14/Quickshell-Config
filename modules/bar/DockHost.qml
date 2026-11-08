pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs

// ── DockHost ──────────────────────────────────────────────────────────────────
// The persistent app dock, welded into the screen frame: a lobe of the frame's
// own material that rises out of the bottom strip (or a side strip) the way a
// panel melts down out of the bar. What's IN it is the shared DockIconStrip over
// the Taskbar service; this file is the surface, the melt, auto-hide, and the
// preview card and jump list that hang off it.
//
// ── Why it lives in Bar's window ──────────────────────────────────────────────
// `Quicktest.Blobs` fuses shapes within ONE Qt Quick scene graph; two layer-shell
// surfaces are composited independently by Hyprland. The ring (bar + frame) is
// drawn by BlobBarLayer in Bar's window, so a dock that genuinely melts out of
// the frame has to be in Bar's window too — the move SettingsPanelHost
// and BarPanelDock both made, for the same reason. The one
// thing this window can't do for the dock is reserve its space (Bar reserves the
// top edge); modules/dock/DockReserve does that.
//
// ── The melt ─────────────────────────────────────────────────────────────────
// `reveal` is a box pinned to the frame's inner edge that grows 0 → the dock's
// thickness, in step with the sidebar's bar (SideBarHost), whose one lobe
// (BlobBarLayer's sidebarRect) the blob smooth-min unions into the ring — the
// neck and the fillets where it meets the strip are the shader's. The card rides reveal's
// MOVING edge: it slides out of the strip rather than being wiped into view, the
// same way a BarDock card slides out from under the bar. Auto-hide is that
// motion in reverse — the dock sinks back into the frame and the lobe retracts.
//
// Welded, the card draws the frame's fill with no border or shadow of its own:
// the blob supplies the silhouette and one continuous outline around ring, neck
// and dock (see BarDock's `blobWeld` for why a card's own rectangular stroke can
// never agree with it). Without the plugin it butt-joins the strip with squared
// corners on that side; floating (the top bar floating), it stands off the
// strip as a rounded, outlined pill. It wears the top bar's style throughout —
// SidePill draws each case the way the bar does, and the strip is bar-sized
// with the bar's hover and press (DockIconStrip.barFeedback).
//
// ── A disabled dock is not built ─────────────────────────────────────────────
// Everything below lives in `Body`, behind a Loader on Config.dockEnabled — the
// strip, its buttons and their icons, the preview, the menu, and the Taskbar
// service they'd otherwise keep regrouping on every focus change. What Bar.qml
// reads is forwarded out of it; with nothing loaded each of those is null or 0,
// and a Region over a null item is empty.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property var screen
    required property var monitor
    // The edge's layout, shared with the stats pill (SideRail): where the dock
    // goes along it. This host tells it back how long the dock is.
    required property SideRail rail

    readonly property real length: body.item && body.item.hasContent ? body.item.cardMain : 0

    // Busy with something that must keep an auto-hiding sidebar out (SideBarHost).
    readonly property bool engaged: body.item?.held ?? false

    // BlobBarLayer.dockDeform / previewDeform; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    // The hover plate of the region pill the dock stands in (SideRegionPills), shared by
    // its apps (CellFeedback finds it by ancestry) and whatever else is in that pill.
    // Its island's own first (Config.sidebarIslands: SideRegionPills keys it "region:ids").
    readonly property var _group: host.rail.placed.groups.find(g => g.ids.indexOf("dock") >= 0) ?? null
    readonly property var hoverTrack: (host._group
        ? host.rail.regionTracks[host._group.region + ":" + host._group.ids.join(",")] : undefined)
        ?? host.rail.regionTracks[Config.sidebarRegionOf("dock")] ?? null
    property matrix4x4 previewDeform

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    // Bar's window must reach the screen's bottom edge so the auto-hide zone can
    // sit on it; otherwise it stops a few px short in the floating-bar modes.
    // Config-only on purpose: the window's height must not wait on the Loader.
    readonly property int bottomReach: Config.dockEnabled ? host.height : 0

    readonly property Item maskItem:    body.item?.maskItem    ?? null
    readonly property Item previewMask: body.item?.previewMask ?? null
    readonly property Item menuMask:    body.item?.menuMask    ?? null
    readonly property bool wantsKeyboardFocus: body.item?.wantsKeyboardFocus ?? false
    // Keyboard mode (SUPER+T) arrives from a keybind, not a click into this window,
    // so it needs EXCLUSIVE focus — OnDemand would never grant it.
    readonly property bool wantsExclusiveFocus: body.item?.wantsExclusiveFocus ?? false


    // Where magnified icons swell past the dock, as blob boxes in window
    // coordinates — [] unless welded and magnifying.
    readonly property var magnifyRects: body.item?.magnifyRects ?? []

    // The fused preview's lobe (Config.dockPreviewFuse); zero otherwise.
    readonly property real previewBlobX: body.item?.previewBlobX ?? 0
    readonly property real previewBlobY: body.item?.previewBlobY ?? 0
    readonly property real previewBlobW: body.item?.previewBlobW ?? 0
    readonly property real previewBlobH: body.item?.previewBlobH ?? 0

    Loader {
        id: body
        anchors.fill: parent
        active: Config.dockEnabled
        sourceComponent: Body {}
    }

    component Body: Item {
        id: dock

        // ══ Where ═════════════════════════════════════════════════════════════
        // The rail decides the edge (see SideRail for the rule).
        readonly property string edge: host.rail.edge
        readonly property bool vertical: host.rail.vertical

        // The frame strip's depth (0 without a frame).
        readonly property int strip: host.rail.strip

        // The same condition SettingsPanelHost welds under: a ring to weld into,
        // drawn by the blob (which only owns the ring while the bar is anchored).
        readonly property bool blobWeld: host.rail.welded

        // Across the edge: the sidebar's surface, SideRail.surfaceLo..surfaceHi — the
        // top bar's depth — with the strip centred in it at a bar module's size.
        readonly property int depth: host.rail.depth
        // Along the edge, pill → strip: the top bar's inner-pill margin (SideRail.pad).
        readonly property int pad: host.rail.pad

        // ══ When ══════════════════════════════════════════════════════════════
        // Nothing to show (no pins, nothing running, no launcher button) — no dock.
        readonly property bool hasContent: dockStrip.fullLength > 0

        // (The overview does NOT sink the dock or the sidebar any more — the user, 2026-10-24: they
        // stay up under its dim. It used to, via SideBarHost's `overviewHere`.)

        // ── Shown ─────────────────────────────────────────────────────────────
        // The sidebar's one reveal decides (SideBarHost): auto-hide and its dodge
        // mode, the overview, SUPER+SHIFT+D — for the whole edge at once, in either
        // shape. What the dock is busy with holds that reveal out (`held`, exported
        // as `engaged`): the pointer over it, its preview, its menu or a drag
        // (strip.engaged), the SUPER+D latch (UiState.dockRevealed), keyboard mode,
        // an app dragged in from the launcher. In the near corner, a panel over it
        // sinks it into the frame (SideRail.isCollapsed), as it does the clips.
        readonly property bool held: cardHover.hovered || dockStrip.engaged || UiState.dockRevealed
                                     || dockStrip.kbActive || dock.appOver
        readonly property bool collapsed: host.rail.isCollapsed("dock")
        readonly property bool shownState: dock.hasContent && !dock.collapsed && host.rail.barShown

        // Where the dock rests when fully out, in this screen's coordinates.
        readonly property rect restRect:
              dock.edge === "left"  ? Qt.rect(dock.edgePos, dock.mainPos, dock.depth, dock.cardMain)
            : dock.edge === "right" ? Qt.rect(dock.edgePos - dock.depth, dock.mainPos, dock.depth, dock.cardMain)
            :                         Qt.rect(dock.mainPos, dock.edgePos - dock.depth, dock.cardMain, dock.depth)

        // ── An app dragged in from the launcher ───────────────────────────────
        // The launcher is in this same window (BarPanelDock's centre slot), on
        // whichever screen UiState.activeScreen names — the same ownership rule
        // BarPanelDock applies. The pointer arrives in this window's scene
        // coordinates, which are this item's (it sits at the window's origin).
        readonly property bool launcherHere:
            UiState.activeScreen ? UiState.activeScreen === host.screen
                                 : host.screen === Quickshell.screens[0]
        readonly property bool appDragging: UiState.appDragKey !== "" && dock.launcherHere

        // Over the dock — its resting box, grown by a thickness all round so the
        // gap opens as the icon approaches rather than only once it's inside. An
        // auto-hidden dock rises to meet it (it's in `held`).
        readonly property bool appOver: dock.appDragging
            && UiState.appDragX > dock.restRect.x - dock.depth
            && UiState.appDragX < dock.restRect.x + dock.restRect.width + dock.depth
            && UiState.appDragY > dock.restRect.y - dock.depth
            && UiState.appDragY < dock.restRect.y + dock.restRect.height + dock.depth

        readonly property point appPoint: dockStrip.mapFromItem(null, UiState.appDragX, UiState.appDragY)

        Binding { target: dockStrip; property: "insertKey"; value: dock.appOver ? UiState.appDragKey : "" }
        Binding {
            target: dockStrip
            property: "insertAt"
            value: dock.appOver && Taskbar.canPin(UiState.appDragKey)
                   ? dockStrip.insertionAt(dock.appPoint.x, dock.appPoint.y) : -1
        }

        Connections {
            target: UiState
            function onAppDropped(key) {
                if (dock.appOver && dockStrip.insertAt >= 0) Taskbar.pin(key, dockStrip.insertAt)
            }
        }

        // (A file dragged to the screen edge reveals an auto-hidden sidebar so it
        // can be dropped on an app: SideBarHost's edge zone, `fileAtEdge`.)

        // ── Keyboard, and SUPER+ALT+n ─────────────────────────────────────────
        // Both go to the dock on the FOCUSED monitor — the one you're looking at.
        readonly property bool focusedHere:
            Hyprland.focusedMonitor !== null
            && Hyprland.focusedMonitor.name === (host.monitor?.name ?? "")

        readonly property bool wantsExclusiveFocus: dockStrip.kbActive

        Connections {
            target: UiState
            function onDockKeyboardChanged() {
                if (!UiState.dockKeyboard || !dock.focusedHere) return
                // A hidden sidebar isn't there to steer: let the request go.
                if (UiState.sidebarHidden) UiState.dockKeyboard = false
                else dockStrip.kbStart()
            }
            function onDockActivateSeqChanged() {
                if (dock.focusedHere) dockStrip.activateAt(UiState.dockActivateIndex)
            }
            // Something else took the screen: leave keyboard mode.
            function onOverviewOpenChanged() { if (UiState.overviewOpen) dockStrip.kbStop() }
            function onLauncherOpenChanged() { if (UiState.launcherOpen) dockStrip.kbStop() }
        }

        Connections {
            target: dockStrip
            function onKbDone() { UiState.dockKeyboard = false }
            function onKbIndexChanged() { if (dockStrip.kbActive) kbIdle.restart() }
        }

        // Exclusive focus holds the whole keyboard, and a click elsewhere can't take
        // it back (this window never sees that click). So keyboard mode lets go by
        // itself after a spell with no keys pressed — Escape isn't the only way out.
        Timer {
            id: kbIdle
            interval: 8000
            onTriggered: dockStrip.kbStop()
        }

        // ══ Geometry ══════════════════════════════════════════════════════════
        // The room along the edge (SideRail's span).
        readonly property real spanStart: host.rail.spanStart
        readonly property real spanEnd:   host.rail.spanEnd

        // Clear of the ring's rounded inner corners at either end, and of the
        // stats pill when it shares the edge.
        readonly property real maxSpan: host.rail.dockRoom

        // "grow" runs the whole room; "clip" caps at Config.dockClipPercent % of it and
        // scrolls past.
        readonly property real maxLength:
            Math.max(Config.sidebarCell,
                     (Config.dockOverflow === "grow" ? dock.maxSpan : dock.maxSpan * Config.dockClipPercent / 100)
                     - dock.pad * 2)

        // The card's length along the dock, following the strip's eased length.
        readonly property real cardMain:
            (dock.vertical ? dockStrip.implicitHeight : dockStrip.implicitWidth) + dock.pad * 2

        // Where the rail puts it: centred with the stats, stepped past an open panel.
        readonly property real mainPos: host.rail.dockPos

        // Where the reveal box is pinned: the surface's screen-edge side
        // (SideRail.surfaceLo — the screen edge itself while welded).
        readonly property real edgePos: host.rail.edgePos(dock.width, dock.height)

        // Where the dock's inward face comes to rest when fully out — the preview
        // stands off this. The RESTING face, not the animated one, so a preview
        // opened mid-slide doesn't slide with it.
        readonly property real innerRest:
              dock.edge === "left" ? dock.edgePos + dock.depth
            :                        dock.edgePos - dock.depth

        // ══ Forwarded to Bar.qml through the host ═════════════════════════════
        // `lobe`, not `reveal`: with magnification the clip reaches past the dock
        // into the screen, and neither the input mask nor the blob may follow it.
        readonly property Item maskItem:    lobe
        readonly property Item previewMask: preview.maskItem
        readonly property Item menuMask:    menuDismiss
        readonly property bool wantsKeyboardFocus: dockMenu.opened


        // Room past the dock's inner face for magnified icons (0 when magnification
        // is off, or the strip scrolls and keeps them inside).
        readonly property int headroom: dockStrip.magnifyHeadroom

        // The dock's own box as it slides out of the frame: `cross` of it is out.
        // The blob's lobe, the input mask and the wallpaper wave all use this.
        Item {
            id: lobe
            x: dock.edge === "left"  ? dock.edgePos
             : dock.edge === "right" ? dock.edgePos - reveal.cross
             :                         dock.mainPos
            y: dock.vertical ? dock.mainPos : dock.edgePos - reveal.cross
            width:  dock.vertical ? reveal.cross : dock.cardMain
            height: dock.vertical ? dock.cardMain : reveal.cross
            visible: reveal.cross > 0.5
        }

        // The band's origin in window coordinates (it rides the lobe: flush with
        // its inner side on a left dock, its origin otherwise), then the strip's
        // offset inside the band — so the strip's boxes can be moved into window
        // space by addition, with no mapToItem in a binding.
        readonly property real cardX: dock.edge === "left" ? lobe.x + lobe.width - dock.depth : lobe.x
        readonly property real cardY: lobe.y
        readonly property var magnifyRects: {
            if (!dock.blobWeld) return []
            const ox = dock.cardX + dockStrip.x
            const oy = dock.cardY + dockStrip.y
            return dockStrip.magnifyBoxes.map(b => ({ x: ox + b.x, y: oy + b.y, w: b.w, h: b.h }))
        }

        // The preview's lobe — or the melted menu's, which takes the slot while it's
        // out (the two are never open together; the menu has priority).
        readonly property bool _menuLobe: dockMenu.blobW > 0
        readonly property real previewBlobX: dock._menuLobe ? dockMenu.blobX : preview.blobX
        readonly property real previewBlobY: dock._menuLobe ? dockMenu.blobY : preview.blobY
        readonly property real previewBlobW: dock._menuLobe ? dockMenu.blobW : preview.blobW
        readonly property real previewBlobH: dock._menuLobe ? dockMenu.blobH : preview.blobH

        // ══ The dock ══════════════════════════════════════════════════════════
        Item {
            id: reveal

            // How far out of the frame it has come: 0 → the surface's depth.
            readonly property real depth: dock.shownState ? dock.depth : 0
            property real cross: reveal.depth
            Behavior on cross {
                NumberAnimation {
                    duration: Motion.surfaceDuration(dock.shownState)
                    easing.bezierCurve: Motion.emphasizedDecel
                    easing.type: dock.shownState ? Easing.BezierSpline : Motion.exitCurve
                }
            }

            // Pinned to the frame's inner edge, growing inward — the lobe, plus
            // the headroom magnified icons can reach into.
            x: dock.edge === "left"  ? dock.edgePos
             : dock.edge === "right" ? dock.edgePos - reveal.cross - dock.headroom
             :                         dock.mainPos
            y: dock.vertical ? dock.mainPos : dock.edgePos - reveal.cross - dock.headroom
            width:  dock.vertical ? reveal.cross + dock.headroom : dock.cardMain
            height: dock.vertical ? dock.cardMain : reveal.cross + dock.headroom

            // Behind the frame's strip the card is hidden by this clip until it
            // slides out. With no frame there's nothing to hide behind: the card
            // slides in from past the screen edge, the surface's own edge does the
            // clipping — which also keeps its drop shadow whole.
            clip: dock.strip > 0
            // Keyboard mode counts as visible from its first instant: an invisible
            // item can't take active focus, and SUPER+T on an auto-hidden dock asks
            // for focus before the dock has slid out.
            visible: reveal.cross > 0.5 || dockStrip.kbActive

            // ── The dock at rest, riding the reveal box's MOVING edge ─────────
            // Flush with the box's inner side on a left dock, its top or left edge
            // otherwise, so it slides out of the strip rather than being wiped into
            // view. Fully out it spans the sidebar's surface (SideRail.depth).
            Item {
                id: band

                width:  dock.vertical ? dock.depth : dock.cardMain
                height: dock.vertical ? dock.cardMain : dock.depth
                x: dock.edge === "left"  ? reveal.width - dock.headroom - dock.depth
                 : dock.edge === "right" ? dock.headroom : 0
                y: dock.vertical ? 0 : dock.headroom

                // The blob's spring deformation, applied to the content so it
                // squashes with the lobe instead of riding it rigidly (as BarDock).
                transform: Matrix4x4 { matrix: host.deformMatrix }

                // Arranging: the dock is a thing being moved, not a control
                // (SideArrange's handle sits over it), and dims while in the hand.
                enabled: !UiState.sidebarArrange
                opacity: SideDrag.dragging && SideDrag.dragId === "dock" ? 0.25 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                Component.onCompleted: host.rail.registerItem("dock", band)
                Component.onDestruction: if (host.rail) host.rail.unregisterItem("dock", band)

                // The lighter pill round the apps is its region's now (SideRegionPills,
                // 2026-10-31): one pill per region, a divider where the dock's group ends.

                HoverHandler { id: cardHover }

                // The surface round the strip: right-click → the dock menu.
                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: function(m) {
                        const s = cardMouse.mapToItem(null, m.x, m.y)
                        dockStrip.openDockMenu(s.x, s.y)
                    }
                }

                DockIconStrip {
                    id: dockStrip
                    anchors.centerIn: parent

                    // A bar module's size and feel (Config.sidebarCell, CellFeedback).
                    buttonSize:     Config.sidebarCell
                    iconPx:         Config.sidebarIconPx
                    barFeedback:    true
                    shown:          dock.shownState
                    edge:           dock.edge
                    // A melted preview welds flush to the face: keep it flat under one.
                    flatUnderPreview: Config.dockPreviewFuse && dock.blobWeld
                    screen:         host.screen
                    monitor:        host.monitor
                    contextMenu:    dockMenu
                    maxLength:      dock.maxLength
                    previewHovered: preview.hovered
                    scope:          Config.dockScope
                    // The dock's rounded ends — its pill's — reach this far into the strip.
                    swellInset:     Math.max(0, Math.min(Tokens.corner(Config.barShape, Config.barRoundness),
                                                         Config.sidebarPillCross / 2) - dock.pad)
                }
            }
        }

        // ══ The preview ═══════════════════════════════════════════════════════
        // Outside `reveal` — a card standing clear of the dock would be cut off by
        // the very clip the dock slides out of. Fills this item: the screen.
        DockPreview {
            id: preview
            anchors.fill: parent

            strip:      dockStrip
            edge:       dock.edge
            monitor:    host.monitor
            // Only where there's a lobe to melt out of.
            fused:        Config.dockPreviewFuse && dock.blobWeld
            deformMatrix: host.previewDeform
            // Floating: standing on the magnification swell as it is NOW (the strip
            // holds it up while a preview is open), so it never sits in it. The strip
            // starts `spacingSm` inside the dock's face, so that much of the swell is
            // already covered. Melted: flush on the dock's own face — the strip lets
            // the swell relax under it (flatUnderPreview), so the join is flat.
            readonly property real swell: preview.fused ? 0
                : Math.max(0, dockStrip.magnifyPeakNow - Tokens.spacingSm)
            dockInner:  dock.edge === "left" ? dock.innerRest + preview.swell
                                             : dock.innerRest - preview.swell
            strokeColor: dock.blobWeld ? Colors.of(QsWindow.window).frameLine : Colors.of(QsWindow.window).outlineFor(Tokens.elevationCard)
            strokeWidth: dock.blobWeld ? Config.frameBorderWidth : Tokens.borderWidth
            anchorMain: dockStrip.previewCenter < 0 ? -1
                      : dock.mainPos + dock.pad + dockStrip.previewCenter
            // Rest on a window to peek at its workspace (WindowPeek, in Bar).
            peeks: Config.dockPeek
            // Melted, it stays within the dock's own length.
            spanLo: dock.mainPos
            spanHi: dock.mainPos + dock.cardMain
        }

        // An icon dragged off the dock and let go: the poof, where it happened.
        DockPoof {
            id: poof
            anchors.fill: parent
            size: Config.sidebarIconPx
        }
        Connections {
            target: dockStrip
            function onUnpinnedAt(x, y, icon) { poof.play(x, y, icon) }
        }

        // ══ The jump list ═════════════════════════════════════════════════════
        // Fills this item so it can open anywhere and flip upward off a bottom
        // dock. While it's open `menuDismiss` joins the window's input mask, so the
        // click that dismisses it lands here instead of on the desktop below.
        Item {
            id: menuDismiss
            width:  dockMenu.opened ? dock.width  : 0
            height: dockMenu.opened ? dock.height : 0
        }

        // Melted like the preview (same setting, same weld): pinned flush on the
        // dock's face beside the clicked icon, inside the dock's length, growing out
        // of it. It and the preview are never open together — opening the menu
        // closes the preview and blocks it (DockIconStrip._openMenu) — so they
        // share the preview's blob lobe.
        ContextMenu {
            id: dockMenu
            anchors.fill: parent

            readonly property bool melt: Config.dockPreviewFuse && dock.blobWeld
            readonly property real alongLen: dock.vertical ? dockMenu.menuHeight : dockMenu.menuWidth
            // Clear of the dock's ENDS by the blob's reach plus a corner, as the
            // preview is (DockPreview.endInset): an end landing on the dock's end
            // blends the two rounded corners into a bump. Too long for that room, it
            // falls back to the dock's full length.
            readonly property real endInset: Morph.smoothing + Tokens.radiusCard
            readonly property real alongAt: {
                const a  = (dock.vertical ? dockMenu.atY : dockMenu.atX) - dockMenu.alongLen / 2
                const lo = dock.mainPos + dockMenu.endInset
                const hi = dock.mainPos + dock.cardMain - dockMenu.endInset
                return dockMenu.alongLen <= hi - lo
                    ? Math.max(lo, Math.min(hi - dockMenu.alongLen, a))
                    : Math.max(dock.mainPos, Math.min(dock.mainPos + dock.cardMain - dockMenu.alongLen, a))
            }
            pinned:   dockMenu.melt
            fused:    dockMenu.melt
            growFrom: dock.edge
            pinX: dock.edge === "left"  ? dock.innerRest
                : dock.edge === "right" ? dock.innerRest - dockMenu.menuWidth
                :                         dockMenu.alongAt
            pinY: dock.vertical ? dockMenu.alongAt : dock.innerRest - dockMenu.menuHeight
        }

        // Escape closes the menu. On an Item, never the window — `Keys` does
        // nothing on a PanelWindow (see BarPanelDock's escFocus). Bar.qml asks for
        // OnDemand focus while the menu is open; the right-click that opened it is
        // the click INTO the surface that OnDemand needs.
        Item {
            id: escFocus
            Keys.onEscapePressed: dockMenu.close()
            Connections {
                target: dockMenu
                function onOpenedChanged() { if (dockMenu.opened) escFocus.forceActiveFocus() }
            }
        }

        // ══ The app in the hand ═══════════════════════════════════════════════
        // The launcher's own row is clipped inside its panel, so the icon being
        // dragged is drawn here, under the pointer, over everything in this window
        // (Bar.qml lifts this whole host above the panels for the drag).
        Image {
            id: ghost
            readonly property int px: Config.sidebarIconPx
            visible: dock.appDragging
            source: dock.appDragging ? Taskbar.iconFor(UiState.appDragKey) : ""
            x: UiState.appDragX - ghost.px / 2
            y: UiState.appDragY - ghost.px / 2
            width:  ghost.px
            height: ghost.px
            sourceSize: Qt.size(ghost.px, ghost.px)
            opacity: dock.appOver ? 1 : 0.75
            z: 10
        }
    }
}
