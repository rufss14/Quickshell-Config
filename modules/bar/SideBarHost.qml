pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs

// ── SideBarHost ───────────────────────────────────────────────────────────────
// The sidebar: ONE bar along the dock's edge,
// behind the dock, the stats and the clips, the way the top bar sits behind its
// groups. It only draws the bar and runs its auto-hide. The modules stay in their
// own hosts, at the places SideRail gives them, and each draws itself as an inner
// pill on this bar instead of as a card of its own.
//
// ── One surface, one lobe, one reveal ─────────────────────────────────────────
// Welded, the bar is a single blob lobe (BlobBarLayer's sidebarRect) running
// strip to strip, so it reads as the frame's strip thickened. Along the bottom,
// both ends fillet into the side strips. On a side, it welds into the bar's
// underside and the bottom strip. The hosts have no lobes of their own —
// lobes laid on one strip would bulge wherever their faces coincide. They keep
// only what reaches PAST the bar's face (a hover card), which melts out of
// the bar the way a panel melts out of the top bar. With no plugin it butt-joins
// the strips with square corners; floating (the top bar floating) it stands off
// them, outlined and rounded — SidePill's "bar", the top bar's unified surface.
// The strip counts as bar: welded, the surface starts at the screen edge with the
// strip inside it (SideRail.surfaceLo..surfaceHi), and the pills are centred
// across the whole band, so they reach over the strip.
//
// ── The sidebar's one reveal ──────────────────────────────────────────────────
// The whole sidebar hides as ONE (Config.sidebarAutoHide, and its dodge mode), so
// this runs whenever anything is on the edge.
// What holds it out is this bar's own hover plus anything a module is busy with
// (`engaged`: a hovered card, a drag, a menu, the dock's keyboard mode, a clip
// peek, a small group under the pointer). The big hosts slide on `rail.barShown`
// with the same curve and duration as this reveal, and the small groups ride its
// `cross` itself, so everything moves as one body.
//
// Behind a Loader like the hosts: with nothing on the edge it builds nothing and
// forwards 0/null.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: host

    required property var monitor
    required property SideRail rail

    // Anything a module on the rail is busy with — Bar.qml ORs the three hosts'
    // `engaged` into this.
    property bool engaged: false

    // BlobBarLayer.sidebarDeform; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    readonly property bool shownState: body.item?.shownState ?? false
    // The reveal as it moves, 0 → the surface's depth (SideRail.cross).
    readonly property real cross: body.item?.cross ?? 0
    // Anything on the edge — or it's being arranged, where an empty sidebar still
    // shows, so the first module has somewhere to land (UiState.sidebarArrange).
    readonly property bool live: Config.sidebarAnyPlaced || UiState.sidebarArrange
    readonly property int  bottomReach: host.live ? host.height : 0
    readonly property Item maskItem: body.item?.maskItem ?? null
    readonly property Item edgeMask: body.item?.edgeMask ?? null

    readonly property real blobX: body.item?.blobX ?? 0
    readonly property real blobY: body.item?.blobY ?? 0
    readonly property real blobW: body.item?.blobW ?? 0
    readonly property real blobH: body.item?.blobH ?? 0

    Loader {
        id: body
        anchors.fill: parent
        active: host.live
        sourceComponent: Body {}
    }

    component Body: Item {
        id: bar

        // ══ Where ═════════════════════════════════════════════════════════════
        readonly property string edge: host.rail.edge
        readonly property bool vertical: host.rail.vertical
        readonly property int strip: host.rail.strip
        readonly property bool blobWeld: host.rail.welded
        // Across the edge: the surface's depth (SideRail.surfaceLo..surfaceHi —
        // welded, from the screen edge, the strip being the same material).
        readonly property int depth: host.rail.depth

        // ══ When ══════════════════════════════════════════════════════════════
        // Something to stand behind: not everything on the rail sunk under a panel
        // in the near corner (SideRail.hasContent).
        readonly property bool hasContent: host.rail.hasContent

        // ── Auto-hide ─────────────────────────────────────────────────────────
        // DockHost's rule and timings: interaction timings, not Motion durations.
        readonly property int revealDwell: 150
        readonly property int hideGrace:   500

        property bool fileAtEdge: false
        // SUPER+D's latch (UiState.dockRevealed) pins the whole sidebar out, dock
        // or no dock on it.
        readonly property bool held: barHover.hovered || host.engaged || bar.fileAtEdge
                                     || UiState.dockRevealed
        property bool revealed: false

        onHeldChanged: {
            if (bar.held) {
                hideTimer.stop()
                bar.revealed = true
            } else if (bar.revealed && !edgeHover.hovered) {
                hideTimer.restart()
            }
        }
        Timer {
            id: revealTimer
            interval: bar.revealDwell
            onTriggered: if (edgeHover.hovered && Config.sidebarEdgeReveal) bar.revealed = true
        }
        Timer {
            id: hideTimer
            interval: bar.hideGrace
            onTriggered: if (!bar.held && !edgeHover.hovered) bar.revealed = false
        }

        readonly property bool shownState: UiState.sidebarArrange
            || (bar.hasContent && !UiState.sidebarHidden
                && (!Config.sidebarAutoHide || bar.revealed || (bar.dodging && !bar.covered)
                    || bar.onEmptyWorkspace))

        // ── Dodge windows ─────────────────────────────────────────────────────
        // DockHost's mode, over the whole bar: out until a window on this screen's
        // current workspace overlaps it. Hypr's event tier, held only while on.
        readonly property bool dodging: Config.sidebarAutoHide && Config.sidebarDodge

        // ── Empty workspaces (Config.sidebarEmptyReveal) ──────────────────────
        // ii's rule: with nothing on this monitor's current workspace there is nothing to
        // cover and nothing else to look at, so the bar stays out. Same events as dodging.
        readonly property bool wantsEmpty: Config.sidebarAutoHide && Config.sidebarEmptyReveal
        readonly property bool onEmptyWorkspace: {
            if (!bar.wantsEmpty || !host.monitor) return false
            const ws = host.monitor.activeWorkspace?.id ?? -1
            const wins = Hypr.windows
            for (let i = 0; i < wins.length; i++)
                if (wins[i].workspaceId === ws) return false
            return true
        }

        // Either rule needs the window list kept current: Hypr's event tier, held only then.
        readonly property bool watching: bar.dodging || bar.wantsEmpty
        property bool _eventsHeld: false
        function _syncEvents() {
            if (bar.watching === bar._eventsHeld) return
            if (bar.watching) Hypr.acquireEvents()
            else Hypr.releaseEvents()
            bar._eventsHeld = bar.watching
        }
        onWatchingChanged: bar._syncEvents()
        Component.onCompleted: bar._syncEvents()
        Component.onDestruction: if (bar._eventsHeld) Hypr.releaseEvents()

        readonly property rect restRect:
              bar.edge === "left"  ? Qt.rect(bar.edgePos, bar.mainPos, bar.depth, bar.mainLen)
            : bar.edge === "right" ? Qt.rect(bar.edgePos - bar.depth, bar.mainPos, bar.depth, bar.mainLen)
            :                        Qt.rect(bar.mainPos, bar.edgePos - bar.depth, bar.mainLen, bar.depth)

        readonly property bool covered: {
            if (!bar.dodging || !host.monitor) return false
            const mon = host.monitor
            const ws  = mon.activeWorkspace?.id ?? -1
            const r = { x: mon.x + bar.restRect.x, y: mon.y + bar.restRect.y,
                        w: bar.restRect.width, h: bar.restRect.height }
            const rects = []
            const wins = Hypr.windows
            for (let i = 0; i < wins.length; i++)
                if (wins[i].workspaceId === ws)
                    rects.push({ x: wins[i].at[0], y: wins[i].at[1], w: wins[i].size[0], h: wins[i].size[1] })
            return DockJs.overlaps(r, rects)
        }

        // ══ Geometry ══════════════════════════════════════════════════════════
        readonly property real mainPos: host.rail.barStart
        readonly property real mainLen: Math.max(0, host.rail.barEnd - host.rail.barStart)

        readonly property real edgePos: host.rail.edgePos(bar.width, bar.height)

        // ══ Forwarded to Bar.qml through the host ═════════════════════════════
        readonly property Item maskItem: lobe
        readonly property Item edgeMask: edgeZone
        readonly property real blobX: bar.blobWeld ? lobe.x : 0
        readonly property real blobY: bar.blobWeld ? lobe.y : 0
        readonly property real blobW: bar.blobWeld ? lobe.width  : 0
        readonly property real blobH: bar.blobWeld ? lobe.height : 0
        readonly property real cross: reveal.cross

        // The bar's own box as it slides out of the frame (DockHost's `lobe`).
        Item {
            id: lobe
            x: bar.edge === "left"  ? bar.edgePos
             : bar.edge === "right" ? bar.edgePos - reveal.cross
             :                        bar.mainPos
            y: bar.vertical ? bar.mainPos : bar.edgePos - reveal.cross
            width:  bar.vertical ? reveal.cross : bar.mainLen
            height: bar.vertical ? bar.mainLen : reveal.cross
            visible: reveal.cross > 0.5
        }

        // ══ The bar ═══════════════════════════════════════════════════════════
        Item {
            id: reveal

            // The hosts' reveal, exactly — same depth, curve and duration.
            readonly property real depth: bar.shownState ? bar.depth : 0
            property real cross: reveal.depth
            Behavior on cross {
                NumberAnimation {
                    duration: Motion.surfaceDuration(bar.shownState)
                    easing.bezierCurve: Motion.emphasizedDecel
                    easing.type: bar.shownState ? Easing.BezierSpline : Motion.exitCurve
                }
            }

            x: lobe.x
            y: lobe.y
            width:  lobe.width
            height: lobe.height
            clip: bar.strip > 0
            visible: lobe.visible

            // The top bar's unified surface, on end (SidePill "bar"). Flush against
            // the frame with no blob to weld it, it's square wherever it meets a
            // strip: all round, but the top of a side bar stepped down past a panel.
            SidePill {
                id: card
                role:   "bar"
                edge:   bar.edge
                welded: bar.blobWeld
                squareStart: !bar.vertical || !host.rail.barStepped
                squareEnd:   true
                focused: barHover.hovered

                width:  bar.vertical ? bar.depth : bar.mainLen
                height: bar.vertical ? bar.mainLen : bar.depth

                x: bar.edge === "left" ? reveal.width - bar.depth : 0
                y: 0

                transform: Matrix4x4 { matrix: host.deformMatrix }

                HoverHandler { id: barHover }

                // The bar between the modules: right-click, its settings.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.RightButton
                    onClicked: UiState.openSettingsTo("SidebarPage.qml")
                }
            }
        }

        // ══ Auto-hide's edge ══════════════════════════════════════════════════
        // The frame's strip along the bar's whole run (a couple of px at the very
        // edge without a frame). A file dragged here reveals the bar too, so it
        // can be dropped on a dock app.
        Item {
            id: edgeZone
            readonly property bool live: Config.sidebarAutoHide && bar.hasContent && !UiState.sidebarHidden
            readonly property int  depth: edgeZone.live ? Math.max(bar.strip, Tokens.spacingXs) : 0

            x: bar.edge === "right" ? bar.width - edgeZone.depth
             : bar.edge === "left"  ? 0
             :                        bar.mainPos
            y: bar.edge === "bottom" ? bar.height - edgeZone.depth : bar.mainPos
            width:  bar.vertical ? edgeZone.depth : bar.mainLen
            height: bar.vertical ? bar.mainLen : edgeZone.depth

            DropArea {
                anchors.fill: parent
                onEntered: bar.fileAtEdge = true
                onExited:  bar.fileAtEdge = false
                onDropped: bar.fileAtEdge = false
            }

            HoverHandler {
                id: edgeHover
                onHoveredChanged: {
                    if (edgeHover.hovered && Config.sidebarEdgeReveal) {
                        hideTimer.stop()
                        revealTimer.restart()
                    } else {
                        revealTimer.stop()
                        if (bar.revealed && !bar.held) hideTimer.restart()
                    }
                }
            }
        }
    }
}
