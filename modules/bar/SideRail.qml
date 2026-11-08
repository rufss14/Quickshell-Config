import QtQuick
import "../../config"
import "../../state"
import "../../services"
import "../../services/dock.js" as DockJs
import "../../services/sidemodules.js" as Side

// ── SideRail ──────────────────────────────────────────────────────────────────
// The layout of the one screen edge the dock stands on, shared by everything
// that stands there with it: the dock (DockHost) and the small modules' groups
// (SideGroupHost — the stats and clips buttons, Power, Shell tools…). One place
// decides where each goes, so they can never overlap or disagree about the edge.
// Non-visual; Bar.qml builds one per screen and hands it to every host, and to
// the panel slot beside the buttons (SidePanelDock), which reads `at`.
//
// ── The order along the edge ──────────────────────────────────────────────────
// Config.sidebarLayout: three regions along the edge, each a list of groups of
// module ids, in the places the clips, the dock and the stats first had (dock.js
// `sideRail`). `start` packs from the near corner — welded into the bar's
// underside on a side, into the left strip at the bottom. `centre` is one block
// centred along the span. `end` packs back from the far corner — below a side
// dock, right of a bottom one. A centre too long to stay centred slides back
// from the far corner's pills rather than under them, and never onto the near
// corner's. Each host tells the rail how long it is (`lengths`, keyed by id) and
// reads back where it goes (`at`) and, for the dock, how long it may grow
// (`room`).
//
// ── Out of a panel's way ──────────────────────────────────────────────────────
// On a side the rail holds its side's panels (below), so this is only for a card
// that isn't its own — a safety net more than a path. A panel dropping out of
// the very corner the start region is stuck in. While one is open across that
// corner, whatever stands there COLLAPSES into the frame (`startCollapsed`,
// `isCollapsed(id)`) and gives its length back, and comes back when it closes:
// stepping it down instead pushed the dock into the stats. The centre steps down
// past the card (dock.js `railAvoid`) and follows it back up as it closes — the
// card's height is animated, so the rail rides it rather than jumping.
//
// ── One bar ───────────────────────────────────────────────────────────────────
// One bar runs the whole edge behind the modules (SideBarHost), each an inner
// pill on it, `inset` in from its ends — the separate-pills shape was scrapped.
// The bar is drawn from `barStart` to `barEnd`, and it decides whether the edge
// is out (`barShown`, handed back by Bar.qml).
//
// ── Holding its side's panels (on a side) ─────────────────────────────────────
// The bar is the frame's inner edge on its side then, so the panels on that side
// hang off its FACE (`panelFace`, BarDock.sideFace) the way they hang off the
// top bar's underside, and the blob melts them out of the corner the two make.
// They're beside the rail, not over it: nothing steps down or collapses for
// them. Stepping was the old answer, and past a certain panel height it had no
// room left — the dock parked above the stats with the card over its top, and a
// strip of it bare between the card and where the bar resumed.
// ─────────────────────────────────────────────────────────────────────────────
QtObject {
    id: rail

    // The screen, in this window's coordinates (Bar's window starts at its origin).
    property real screenW: 0
    property real screenH: 0
    // This sidebar's screen, by name: the focused-window module's length depends on what is
    // focused HERE (cellsFor).
    property string screenName: ""

    // What stands on the rail: each module's length along the edge, by id
    // (0 = absent — off, empty, or not loaded yet). Bar.qml fills it from the big
    // module's host (the dock's); the small ones' are data (`smallLengths`, below).
    property var lengths: ({})

    // The sidebar's reveal as it moves (SideBarHost's), set by Bar.qml: the small
    // module groups ride it rather than easing one of their own.
    property real cross: 0

    // Bar's panel cards, in window coordinates: [{ side, x, y, w, h }], closed = 0
    // tall; `side` is the slot, "left" | "right" | "center".
    property var cards: []

    // Anything that isn't a side reads as "bottom" — DockReserve's rule too, so a
    // hand-edited position can't draw on one edge and reserve another.
    readonly property string edge:
        (Config.dockPosition === "left" || Config.dockPosition === "right")
            ? Config.dockPosition : "bottom"
    readonly property bool vertical: rail.edge !== "bottom"

    // The frame strip's depth (0 without a frame).
    readonly property int strip: Config.screenFrame ? Config.frameDepth : 0

    // The room along the edge: the full screen width at the bottom; at a side,
    // the stretch between the bar and the bottom strip.
    readonly property real spanStart: rail.vertical ? Config.barExtent : 0
    readonly property real spanEnd:   rail.vertical ? rail.screenH - rail.strip : rail.screenW

    // ── The top bar's shape, worn by the sidebar ──────────────────────────────
    // Anchored or floating, and welded into the frame wherever the blob can weld it
    // (the hosts' `blobWeld`). SidePill draws each case the way the top bar does.
    readonly property bool anchored: Config.barAnchored
    readonly property bool welded: Morph.available && Config.screenFrame && Config.barAnchored
    // Floating, everything stands `barInset` off what's around it, as the floating
    // top bar does; anchored, flush.
    readonly property int gapAlong: rail.anchored ? 0 : Config.barInset

    // SideBarHost's shownState, set by Bar.qml.
    property bool barShown: false
    // How far each pill sits in from the bar's ENDS, along the edge.
    readonly property int inset: Config.sidebarInset

    // ── Across the edge ───────────────────────────────────────────────────────
    // Where the sidebar's surface starts and ends, measured in from the screen
    // edge — dock.js `sideSurface`, which DockReserve reserves from too. Welded, the
    // strip and the surface are one material, so it starts at the edge itself and
    // what stands on it centres across the strip and all (centring on the lobe
    // alone left `inset` on one side and `inset + strip` on the other). The blob
    // only has to cover what the strip doesn't.
    readonly property var surface: DockJs.sideSurface({
        depth: Config.sidebarDepth, strip: rail.strip, anchored: rail.anchored,
        welded: rail.welded, inset: Config.barInset
    })
    readonly property int surfaceLo: rail.surface.lo
    readonly property int surfaceHi: rail.surface.hi
    // How far out everything's reveal goes: the surface's own depth.
    readonly property int depth: Math.max(0, rail.surfaceHi - rail.surfaceLo)
    // The rail's inner face: where its side's panels hang from, and how deep in a
    // panel card has to reach to be in the rail's way.
    readonly property real band: rail.surfaceHi

    // ── Along the edge ────────────────────────────────────────────────────────
    // Unified and welded, the bar covers the strips' ends at the screen's corners,
    // as the unified top bar covers the top ones, so each pill is `inset` from the
    // screen's own corner (`pinDepth` 0). Anything else stops at the strips.
    readonly property int pinDepth: rail.welded ? 0 : rail.strip
    // The bar runs strip to strip, or from the bar's underside on a side,
    // stepping down past an open panel card there.
    readonly property real barStart: rail.vertical
        ? Math.max(rail.spanStart + rail.gapAlong, rail.avoid)
        : rail.strip + rail.gapAlong
    readonly property real barEnd: (rail.vertical ? rail.screenH : rail.screenW) - rail.strip - rail.gapAlong
    // Stepped down past a panel: no longer against the bar's underside.
    readonly property bool barStepped: rail.barStart > rail.spanStart + rail.gapAlong + 0.5

    // Kept clear of the ring's rounded inner corners at either end.
    readonly property real margin: rail.strip + Config.frameCornerRadius + Tokens.spacingXl

    // Where the end region ends: flush in the frame's far corner, welding into
    // both strips at once.
    readonly property real corner:
        (rail.vertical ? rail.screenH : rail.screenW) - rail.pinDepth - rail.gapAlong - rail.inset

    // Where the start region starts: flush in the near corner — against the bar's
    // underside on a side, the left strip at the bottom — welding into both.
    readonly property real near:
        (rail.vertical ? rail.spanStart : rail.pinDepth) + rail.gapAlong + rail.inset

    // Two welded lobes closer than the blob's smoothing melt into one another —
    // a bridge between dock and stats, or between the dock and a panel. This far
    // apart they stay two shapes.
    readonly property real apart: Morph.smoothing + Tokens.spacingMd

    // What stands between two groups along the edge: the top bar's gap between
    // groups. There's one lobe (the bar) and nothing on it to bridge.
    readonly property real groupGap: Tokens.spacingMd

    // ── Where a module stands across the edge ─────────────────────────────────
    // The surface's screen-edge side, in a host's coordinates (a host fills the
    // screen, `w`×`h`): every module's reveal box is pinned here and grows `depth`
    // inward, and its pill rides the box's moving edge out of the frame.
    function edgePos(w, h) {
        return rail.edge === "left" ? rail.surfaceLo
             : rail.edge === "right" ? w - rail.surfaceLo
             : h - rail.surfaceLo
    }
    // Along the edge, a module's pill is its content plus `pad` at each end — the
    // top bar's inner pill's margin.
    readonly property int pad: Tokens.spacingSm

    // A pill standing flush against the near end (the bar's underside on a side,
    // the left strip along the bottom) or in the far corner. Where nothing welds it
    // (SidePill's `flush`) it's square there, as it is against the strip.
    function atNear(pos)        { return Math.abs(pos - rail.near) < 1 }
    function atCorner(pos, len) { return Math.abs(pos + len - rail.corner) < 1 }

    // ── Holding its side's panels ─────────────────────────────────────────────
    // See the header. Decided from config and the hosts' own lengths ONLY: the
    // panels' x follows `panelFace`, `cards` follows the panels, and
    // `startCollapsed` follows `cards` — as do `placed` and `hasContent`, and so
    // `barShown`. Reading any of those here would close that loop.
    readonly property bool occupied: {
        for (const id in rail.allLengths) if (rail.allLengths[id] > 0) return true
        return false
    }
    readonly property bool holdsPanels: rail.vertical && rail.occupied
    // Where that side's panels hang from: the bar's face, or 0 (BarDock's own
    // frame margin) while SUPER+SHIFT+D has the bar sunk. The rail keeps holding
    // them while sunk, so the bar goes down and comes back up where it is rather
    // than stepping past a card sliding across its band.
    readonly property int panelFace: rail.holdsPanels && !UiState.sidebarHidden ? rail.band : 0

    // One of its own side's panels is open, or still closing: an auto-hiding bar
    // stays out for it (Bar.qml ORs this into SideBarHost's `engaged`), or it
    // would slide away and leave the panel hanging off nothing.
    readonly property bool holdingPanel: rail.panelFace > 0
        && rail.cards.some(c => c.side === rail.edge && c.h > 0.5)

    // The cards the rail keeps out of: every one, but its own side's while it
    // holds those.
    readonly property var obstacles: rail.holdsPanels ? rail.cards.filter(c => c.side !== rail.edge) : rail.cards

    readonly property real avoid:
        rail.edge === "left"  ? DockJs.railAvoid("left", 0, rail.band, rail.obstacles, rail.apart)
      : rail.edge === "right" ? DockJs.railAvoid("right", rail.screenW - rail.band, rail.screenW, rail.obstacles, rail.apart)
      :                         0

    // A panel card over the near corner — over the rail's band, or near enough
    // (`apart`) that the blob would bridge the two. Side rails only: a bottom
    // rail's near corner is nowhere near the bar.
    readonly property bool startCollapsed:
          rail.edge === "left"  ? DockJs.railAvoid("left", 0, rail.band + rail.apart, rail.obstacles, 0) > 0
        : rail.edge === "right" ? DockJs.railAvoid("right", rail.screenW - rail.band - rail.apart, rail.screenW,
                                                   rail.obstacles, 0) > 0
        :                         false

    // Where everything goes (dock.js `sideRail`): `at` by id, `room` by id (the
    // dock's ceiling, at rest), and the groups with a length. A host that isn't
    // placed has no entry — 0, and it's switched off anyway.
    readonly property var placed: rail._lay(rail.allLengths)
    function _lay(lengths) {
        return DockJs.sideRail({
            start: rail.spanStart, end: rail.spanEnd, margin: rail.margin, gap: rail.groupGap,
            near: rail.near, corner: rail.corner,
            avoid: rail.avoid > 0 ? rail.avoid + rail.inset : 0,
            collapsed: rail.startCollapsed,
            // Every module's length already carries its own pill margin (`pad` at each
            // end), so a group's members butt together: two of them in one pill stand
            // 2 × pad apart, the top bar's gap between the modules of a group.
            pad: 0, inner: 0,
            layout: rail.groups,
            lengths: lengths
        })
    }

    // The dock's ceiling is laid out apart from `placed`, with the dock's own length pinned
    // to 1. A module's room never depends on its own length (dock.js: `lay(…, skip)`;
    // test-dock.js pins it in every region), but QML tracks the whole `lengths` object — and
    // DockHost caps its length by this room, so reading `placed.room` closed a loop:
    // length → lengths → placed → dockRoom → length ("Binding loop detected for property
    // placed"), re-laying the rail twice per dock resize. 1, not 0: present, as the real
    // dock is whenever the room matters.
    readonly property var _roomLayout: rail._lay(Object.assign({}, rail.smallLengths, { dock: 1 }))

    // ── The small modules (Power, Shell tools, …) ─────────────────────────────
    // A few cells each (Config.sidebarModuleList `small`), drawn by SideGroupHost —
    // a pill per GROUP of them, the top bar's grouping. The dock has a host of its
    // own and always stands alone (dock.js sideGroups).
    // A small module's length is data — its cells and its pill's margins — so the
    // rail places it without asking anything that's drawn.
    readonly property var groups: DockJs.sideGroups(Config.sidebarLayout, id => !Config.sidebarIsSmall(id))

    // How many cells a small module takes: its catalogue row's, or — where that
    // changes with what's going on — what it will draw (sidemodules.js, the same
    // functions the modules draw with).
    function cellsFor(id) {
        if (id === "voice")  return Side.voiceLayout(Discord.inCall, Discord.users.length).cells
        if (id === "colour") return Side.colourCells(ColorPicker.history.length)
        if (id === "window") {
            const w = ActiveWindow.byMonitor[rail.screenName] ?? null
            return Side.windowCells(w !== null, w !== null && Config.dockEnabled && Taskbar.onDock(w.key ?? ""),
                                    UiState.sidebarArrange)
        }
        // Nothing playing anywhere: it steps aside, as the window cell does (arranging shows it).
        if (id === "nowplaying") return MusicPulse.player !== null || UiState.sidebarArrange ? 1 : 0
        return Config.sidebarModuleInfo(id)?.cells ?? 0
    }

    readonly property var smallLengths: {
        const out = ({})
        for (const r of Config.sidebarRegionIds)
            for (const g of (Config.sidebarLayout[r] ?? []))
                for (const id of g)
                    if (Config.sidebarIsSmall(id)) {
                        // None is nothing — not an empty pill's margins (the window cell
                        // stepping aside, sidemodules.js windowCells).
                        const cells = rail.cellsFor(id)
                        out[id] = cells > 0 ? Config.sidebarRun(cells) + rail.pad * 2 : 0
                    }
        return out
    }
    readonly property var allLengths: Object.assign({}, rail.lengths, rail.smallLengths)

    // The small groups the rail placed: [{ key, region, ids, pos, len }], `key` the
    // ids joined — what SideGroupHost's Repeater is keyed on, so a group that only
    // moves keeps its delegate.
    readonly property var smallGroups: rail.placed.groups
        .filter(g => Config.sidebarIsSmall(g.ids[0]))
        .map(g => Object.assign({ key: g.ids.join(",") }, g))
    function smallGroup(key) { return rail.smallGroups.find(g => g.key === key) ?? null }

    // The pointer is on a small group: the sidebar stays out for it (Bar.qml ORs
    // this into SideBarHost's `engaged`). Counted by the groups themselves.
    property int smallHovered: 0

    // Each region pill's hover plate, by region (SideRegionPills registers them): what the
    // hosts standing in that region hand their buttons as `hoverTrack` (HoverTrack).
    property var regionTracks: ({})

    // ── Each module's own item, by id ─────────────────────────────────────────
    // Arranging (SideArrange) drags a picture of the real module, grabbed on press,
    // as the bar's arrange mode does. The hosts register what they draw a module in
    // and take it back when it goes. Read imperatively only (on a press), so it's a
    // plain map mutated in place, not a notifying property.
    property var items: ({})
    function registerItem(id, item) { rail.items[id] = item }
    function unregisterItem(id, item) { if (rail.items[id] === item) delete rail.items[id] }
    readonly property var at: rail.placed.at

    // Sunk into the frame under a panel: whatever stands in the near corner.
    function isCollapsed(id) { return rail.startCollapsed && Config.sidebarRegionOf(id) === "start" }

    // Something is showing — not everything placed is collapsed under a panel.
    readonly property bool hasContent:
        rail.placed.groups.some(g => g.region !== "start" || !rail.startCollapsed)

    readonly property real dockPos:  rail.at.dock  ?? 0

    // How long the dock may grow along the edge, at rest (a panel stepping the
    // rail down is transient).
    readonly property real dockRoom: rail._roomLayout.room.dock ?? 0
}
