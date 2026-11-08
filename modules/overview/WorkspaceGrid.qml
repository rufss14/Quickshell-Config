import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/switcher.js" as SwitchJs
import "../notifications"
import QtQuick.Layouts
import "grid"

// ── WorkspaceGrid ─────────────────────────────────────────────────────────────
// The workspace switcher: a grid of scaled-down workspaces showing their live
// windows. Click a workspace to go there; drag a window between them to move it.
//
// Each cell is the monitor's USABLE area (minus the bar) scaled by `previewScale`,
// so a window's thumbnail sits exactly where the window sits.
//
// ── The one structural decision that matters ──────────────────────────────────
// The window previews are NOT children of their workspace cell. They all live in a
// single layer (`windowLayer`) spanning the whole board, each positioned at its
// cell's corner plus its real geometry.
//
// Parenting a preview into its cell is the mistake that made the drag unfixable:
// `z` only orders an item among its SIBLINGS, so a preview could never paint over a
// neighbouring cell, and it physically could not be dragged out of its own square.
// Two rewrites went into smuggling it out — scene-space delta maths, cells raising
// their own z, offsets folded into position bindings — and it still felt wrong.
//
// With one flat layer, none of that is needed and the drag is just QML's: the cells
// carry a DropArea each, the preview carries `drag.target`, and the thing moves.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the view files in grid/.
    property alias winModel: winModel

    required property var monitor

    // Drives the cells' entrance stagger — bound to the overview's own `shown`,
    // not Component.onCompleted: the grid is built once at shell startup and just
    // toggles visible with the rest of the overlay, so "just opened" has to be a
    // property edge, not a one-time constructor hook.
    property bool active: false

    // Alt+Tab's / the search's pick (services/Switcher) is lifted, ringed and labelled
    // here, and the rest step back while one is picked. A search fades every window it
    // didn't find: `matching` is { address: true } while searching, null otherwise.
    // `pickedWorkspace` turns the grid to the pick's page (past ten workspaces).
    property string pickedAddress: ""
    property int pickedWorkspace: -1
    property var matching: null

    property int columns: 5
    property int rows:    2
    readonly property int perPage: columns * rows

    // Wide enough that a lifted window (OverviewWindow: the pick grows a few px) never reaches the next cell.
    readonly property int gap: Tokens.spacingXl

    // Which block of workspaces is shown — 1-10, 11-20, … following the focused one,
    // or the pick's while there is one.
    readonly property int page: Math.floor(((root.pickedWorkspace > 0 ? root.pickedWorkspace
                                                                      : Hypr.focusedWorkspaceId) - 1) / perPage)
    readonly property int firstWorkspace: page * perPage + 1

    readonly property var usable: Hypr.usableSize(root.monitor)

    // ── Which workspaces get a cell (2026-10-20) ──────────────────────────────
    // At rest: the busy ones, the one you're on and the pick's — the page's EMPTY ones get no
    // cell, and their room goes to the busy ones (five empty boxes with big numbers were half
    // the grid; the strip of chips that stood for them went too, 2026-10-20, the user's call). While a window is HELD (dragged), the grid opens out to the whole page —
    // all ten — so any of them can take the drop, and folds back to the busy ones when you
    // let go (the user's call, the same day). The cells glide between the two layouts.
    readonly property var _busySlots: {
        const out = []
        const last = root.firstWorkspace + root.perPage - 1
        for (let ws = root.firstWorkspace; ws <= last; ws++)
            if ((Hypr.countByWorkspace[ws] ?? 0) > 0 || ws === Hypr.focusedWorkspaceId || ws === root.pickedWorkspace)
                out.push(ws)
        if (out.length === 0) out.push(root.firstWorkspace)
        // A sparse grid offers one more: the first empty workspace, as a "+ New" cell (`newWs`).
        if (root.newWs > 0 && out.length <= root.sparseUpTo && out.length < root.perPage) out.push(root.newWs)
        return out
    }
    // ── The "+ New" cell ──────────────────────────────────────────────────────
    // Reaching an empty workspace took Shift or a drag. While the grid is sparse (at most
    // `sparseUpTo` cells) it also draws the page's first EMPTY workspace — one the focus isn't
    // on and nothing is picked in — as a "+ New" cell: click it to go and start something there,
    // drop a window on it to give that window a workspace of its own. It is an ordinary cell of
    // an ordinary workspace; only the label says what it is for. The room it takes is what
    // keeps a grid of one or two workspaces from being a lone box in a big card. When the
    // workspace you are on is itself empty there is already an empty cell, and none is added.
    readonly property int sparseUpTo: 5
    readonly property int newWs: {
        const last = root.firstWorkspace + root.perPage - 1
        let emptyShown = false, first = -1
        for (let ws = root.firstWorkspace; ws <= last; ws++) {
            const empty = (Hypr.countByWorkspace[ws] ?? 0) === 0
            if (!empty) continue
            if (ws === Hypr.focusedWorkspaceId || ws === root.pickedWorkspace) emptyShown = true
            else if (first < 0) first = ws
        }
        return emptyShown ? -1 : first
    }
    // Every empty workspace of the page that has no cell (the focused and the picked have one): the
    // chips under the "+ New workspace" cell's label.
    readonly property var freeSlots: {
        const out = []
        const last = root.firstWorkspace + root.perPage - 1
        for (let ws = root.firstWorkspace; ws <= last; ws++)
            if ((Hypr.countByWorkspace[ws] ?? 0) === 0 && ws !== Hypr.focusedWorkspaceId && ws !== root.pickedWorkspace)
                out.push(ws)
        return out
    }
    // The pill's pick (2026-10-24, the user: a chip SELECTS, it doesn't go): the "+ New" cell
    // then stands for that workspace — a click on the cell goes there, a drop on it sends there.
    // -1, or a pick that has stopped being free, is the cell's own (`newWs`). Forgotten on close.
    property int newChoice: -1
    readonly property int newTarget: root.freeSlots.indexOf(root.newChoice) >= 0 ? root.newChoice : root.newWs
    // The cell the label is on: only while the grid is folded to its busy cells.
    readonly property bool offersNew: !root.showAll
    readonly property var _pageSlots: {
        const out = []
        for (let i = 0; i < root.perPage; i++) out.push(root.firstWorkspace + i)
        return out
    }
    // Shift, tapped (Overview.steer), opens it out to the whole page — a toggle, tap again to fold
    // it. That is how an empty one is reached; a drag no longer opens it (the user's call,
    // 2026-10-24: the cells shifting under a held window was more noise than help).
    property bool showAll: false
    // Ctrl, toggled on (Overview): a click on a window selects it, a drag swaps (OverviewWindow `ctrlMode`).
    property bool ctrlOn: false
    readonly property var slots: root.showAll ? root._pageSlots : root._busySlots

    // ── Cell size — from the room, shared by the busy cells ───────────────────
    // Was FIXED (340×192 on every screen) back when every cell was always drawn; with only
    // the busy ones drawn, a fixed size wasted the room the empty ones gave up. Now: the
    // column count that gives the BIGGEST cell for this many, inside `maxWidth`×`maxHeight`
    // (less what the notifications card beside them takes), at the monitor's own aspect; never past `maxCell` of the real
    // monitor (one busy workspace shouldn't be a wall). The board then sits centred in the
    // room, and the grid's own size is the room's — so the overview's composition doesn't
    // move when a workspace fills or empties; only the cells inside it do (animated).
    property real maxWidth:  0
    property real maxHeight: 0
    readonly property real maxCell: 0.45

    readonly property real aspect: root.usable.width > 0 && root.usable.height > 0
        ? root.usable.width / root.usable.height : 16 / 9
    readonly property int dotsH: root.totalPages > 1 ? Tokens.spacingMd + root.pageDotH : 0
    function _fit(W, H, n) {
        const cap = Math.max(160, (root.usable.width > 0 ? root.usable.width : 1920) * root.maxCell)
        let best = { cols: 1, rows: 1, w: 0 }
        for (let c = 1; c <= Math.min(n, root.columns); c++) {
            const r = Math.ceil(n / c)
            const w = Math.min((W - (c - 1) * root.gap) / c, ((H - (r - 1) * root.gap) / r) * root.aspect, cap)
            if (w > best.w + 0.5) best = { cols: c, rows: r, w: w }
        }
        return best
    }
    readonly property real _roomW: root.maxWidth > 0 ? root.maxWidth : 5 * 340 + 4 * root.gap
    readonly property real _roomH: (root.maxHeight > 0 ? root.maxHeight : 2 * 192 + root.gap) - root.dotsH
    readonly property var _layFull: root._fit(root._roomW, root._roomH, Math.max(1, root.slots.length))
    // The cells stay CENTRED with the centre beside them (the user: "workspaces should stay on
    // the middle, notifications goes to the right"), so its room comes off BOTH sides.
    readonly property var _layNotes: root._fit(root._roomW - (root.notesW + root.gap * 2) * 2, root._roomH, Math.max(1, root.slots.length))

    // ── The notification centre, beside the busy cells (2026-10-20) ───────────
    // The user: the notifications show in the collapsed grid, to the right of the busy
    // workspaces, "if there's space". There's space when the cells, sharing the room with it,
    // keep at least ~two thirds of the size they'd have alone — a busy workspace or two, as a
    // rule. Not while the grid is opened out (Shift's toggle): those are all ten cells.
    readonly property int notesW: Math.round(Tokens.sideCardUnit * 6.5)
    // The side faces (Ask / News / Changes, the notification centre) are the overview's "More" (Config.overviewMore): folded
    // away by default, so a first look is the workspaces.
    readonly property bool notesOn: root.maxWidth > 0 && !root.showAll && Config.overviewMore
                                    && root._layNotes.w >= root._layFull.w * 0.65
    // The two side faces (the notifications right, OverviewFeed left) keep clear of what the card
    // has in its left corners — the watermark above, Shift/Ctrl below (Overview passes their room).
    // Both faces, so their headers line up across the grid.
    property real sideTop: 0
    property real sideBottom: 0
    // The card's whole height, not just the cells' (the user, 2026-10-24: the face "leaves some space
    // out" — it used to stop where the cells did, a strip above the Shift/Ctrl chips left empty).
    readonly property real sideY: root.sideTop
    readonly property real sideH: Math.max(0, root.boardH - root.sideBottom - root.sideTop)
    // …and as wide as the room beside the cells lets them (the user: the face "leaves some space out"):
    // the cells are often height-bound, which leaves more than `notesW` at each side. Up to 1.4×.
    readonly property int sideW: Math.max(root.notesW, Math.min(Math.round(root.notesW * 1.4), Math.floor(root.originX - root.gap * 2)))
    readonly property var lay: root.notesOn ? root._layNotes : root._layFull
    readonly property int layCols: root.lay.cols
    readonly property int layRows: root.lay.rows

    readonly property int cellWidth:  Math.max(80, Math.floor(root.lay.w))
    readonly property int cellHeight: Math.max(45, Math.floor(root.cellWidth / root.aspect))

    readonly property real previewScale: {
        const uw = root.usable.width, uh = root.usable.height
        if (uw <= 0 || uh <= 0) return root.cellWidth / 1920
        return Math.min(root.cellWidth / uw, root.cellHeight / uh)
    }

    readonly property int cellW: root.cellWidth
    readonly property int cellH: root.cellHeight

    // The cells' block, and the BOARD it sits in. The board is the whole room and never
    // moves; the block is centred in it (`originX`/`originY`, folded into cellX/cellY) with
    // the strip under it. A board that hugged the block re-centred whenever the layout
    // changed — and the window layer, with the window you're dragging in it, slid under the
    // pointer as the grid opened out for a drag (2026-10-20, "not really smooth").
    readonly property int cellsW: root.layCols * cellW + (root.layCols - 1) * gap
    readonly property int cellsH: root.layRows * cellH + (root.layRows - 1) * gap
    readonly property int boardW: root.maxWidth > 0 ? Math.floor(root.maxWidth) : root.cellsW
    readonly property int boardH: root.maxHeight > 0 ? Math.max(0, Math.floor(root.maxHeight) - root.dotsH)
                                                     : root.cellsH
    readonly property real originX: Math.max(0, (root.boardW - root.cellsW) / 2)
    readonly property real originY: Math.max(0, (root.boardH - root.cellsH) / 2)

    // A shrink only if even the computed board can't fit (a tiny room: the 80 px floor).
    readonly property real fitScale: {
        let s = 1
        if (root.maxWidth  > 0) s = Math.min(s, root.maxWidth  / root.boardW)
        if (root.maxHeight > 0 && root.contentH > 0)
            s = Math.min(s, root.maxHeight / root.contentH)
        return Math.max(0.4, s)
    }

    // ── Page dots ─────────────────────────────────────────────────────────────
    // Past 10 workspaces this grid pages the same way the bar's own WorkspacesPill
    // does — and borrows that pill's exact visual language for it: a row of small
    // accent-alpha pills, one per page, solid for the one you're on. One page
    // (the overwhelmingly common case) shows none of this at all.
    readonly property int totalPages: {
        let maxId = root.firstWorkspace + root.perPage - 1
        for (const w of Hypr.workspaces) if (w.id > maxId) maxId = w.id
        return Math.max(1, Math.ceil(maxId / root.perPage))
    }
    readonly property int pageDotH: 8

    readonly property int contentH: boardH + root.dotsH

    implicitWidth:  root.maxWidth  > 0 ? root.maxWidth  : Math.round(boardW * root.fitScale)
    implicitHeight: root.maxHeight > 0 ? root.maxHeight : Math.round(root.contentH * root.fitScale)

    // Where a workspace's cell sits on the board.
    // The entrance's ripple: how long the cell (and its windows) wait before arriving — a beat
    // per step out from the focused workspace, so the grid spreads from the thing you know.
    function rippleDelay(ws, index) {
        const f = Hypr.focusedWorkspaceId
        if (f < root.firstWorkspace || f >= root.firstWorkspace + root.perPage)
            return Math.min(index * 18, 160)
        const d = Math.hypot(root.colOf(ws) - root.colOf(f), root.rowOf(ws) - root.rowOf(f))
        return Math.round(Math.min(d * 38, 220))
    }

    // ── The peek ──────────────────────────────────────────────────────────────
    // Rest the pointer on an occupied workspace for a moment and a card hangs off its OUTER
    // edge (above the top row, below the bottom one — never over another workspace) listing
    // what's on it. One card for the board, gliding between cells as the pointer moves on;
    // not while a window is being dragged. `peeking` lets the overview raise the grid over
    // its neighbours, which the card overhangs.
    property int peekWs: -1
    property int _peekCandidate: -1
    readonly property bool peeking: root.peekWs > 0 && root.active && !root.ghosting
    // Turn the left face to a page (overviewdebug / scripts/overview-shots.sh; nothing else calls it).
    function feedPage(n) { if (feedLoader.item) feedLoader.item.go(n) }
    function hoverCell(ws, on) {
        if (on) {
            root._peekCandidate = ws
            if (root.peekWs > 0) root.peekWs = (Hypr.countByWorkspace[ws] ?? 0) > 0 ? ws : -1
            else peekDwell.restart()
        } else if (root._peekCandidate === ws) {
            root._peekCandidate = -1
            peekDwell.stop()
            peekLinger.restart()
        }
    }
    Timer {
        id: peekDwell
        interval: 400
        onTriggered: if ((Hypr.countByWorkspace[root._peekCandidate] ?? 0) > 0) root.peekWs = root._peekCandidate
    }
    // Off a cell, the card waits a beat before going — the pointer is usually crossing the gap
    // to the next one.
    Timer {
        id: peekLinger
        interval: Motion.standard
        onTriggered: if (root._peekCandidate < 0) root.peekWs = -1
    }
    onActiveChanged: if (!root.active) { root.peekWs = -1; root._peekCandidate = -1; root.newChoice = -1 }

    // A workspace's place among the cells (`slots`); -1 = it has no cell (an empty one, a chip).
    // One without a slot answers with its place in the WHOLE page's layout, which is where
    // it fades in when the grid opens out for a drag.
    function slotOf(ws) { return root.slots.indexOf(ws) }
    function _place(ws) {
        const i = root.slotOf(ws)
        if (i >= 0) return { i: i, cols: root.layCols, n: root.slots.length }
        return { i: Math.max(0, ws - root.firstWorkspace), cols: root.columns, n: root.perPage }
    }
    function colOf(ws) { const p = root._place(ws); return p.i % p.cols }
    function rowOf(ws) { const p = root._place(ws); return Math.floor(p.i / p.cols) }

    // A short last row is centred under the full ones.
    function cellX(ws) {
        const p = root._place(ws)
        const row = Math.floor(p.i / p.cols)
        const inRow = Math.min(p.cols, p.n - row * p.cols)
        return root.originX + (p.cols - inRow) * (root.cellW + root.gap) / 2 + (p.i % p.cols) * (root.cellW + root.gap)
    }
    function cellY(ws) { return root.originY + root.rowOf(ws) * (root.cellH + root.gap) }

    // ── Per-workspace monitor ─────────────────────────────────────────────────
    // Workspaces here float freely between monitors — nothing pins a workspace
    // number to a monitor — so a page's ten cells can straddle two screens with
    // different resolutions. Falls back to this grid's own monitor for a
    // workspace that's never been visited (Hyprland hasn't created it yet).
    function monitorOf(ws) { return Hypr.monitorForWorkspace(ws) ?? root.monitor }

    // ── Sizing a cell's DRAWN rectangle ──────────────────────────────────────
    // Every slot on the board is the same fixed cellW × cellH — that's the layout,
    // and it must not move as workspaces come and go. What's DRAWN inside a slot is
    // that workspace's own monitor area fitted into the slot (letterboxed if the
    // aspect differs), so a maximised window fills its drawn rectangle and a
    // workspace on a different-shaped monitor still reads right. Equal to
    // {cellW, cellH} whenever the workspace's monitor matches the slot's aspect.
    function previewSizeFor(ws) {
        const u = Hypr.usableSize(root.monitorOf(ws))
        const s = (u.width > 0 && u.height > 0)
            ? Math.min(root.cellW / u.width, root.cellH / u.height)
            : root.previewScale
        return {
            w: Math.max(1, Math.round(u.width  * s)),
            h: Math.max(1, Math.round(u.height * s))
        }
    }

    // Where that (possibly smaller) rectangle sits within its slot — centred,
    // so the odd one out centres itself instead of dragging its neighbours
    // around. {0, 0} in the common case where it already matches the slot.
    function fitOffsetFor(ws) {
        const sz = root.previewSizeFor(ws)
        return { x: (root.cellW - sz.w) / 2, y: (root.cellH - sz.h) / 2 }
    }

    // Where a window belonging to this workspace actually originates on the
    // board: the slot's corner plus the centring offset above. Everything that
    // positions a window or its ghost uses this, never cellX/cellY directly.
    function winOriginX(ws) { return root.cellX(ws) + root.fitOffsetFor(ws).x }
    function winOriginY(ws) { return root.cellY(ws) + root.fitOffsetFor(ws).y }

    // Every window on the visible page, flattened — the window layer's model.
    //
    // SORTED BY ADDRESS, which is stable for the life of a window. The order Hyprland
    // reports toplevels in is not, and the Repeater below addresses windows by INDEX
    // (see there) — so an unstable order would make previews swap identity, and their
    // live captures swap with them, every time the list was rebuilt.
    readonly property var pageWindows: {
        const out = []
        const last = root.firstWorkspace + root.perPage - 1
        for (let i = 0; i < Hypr.windows.length; i++) {
            const w = Hypr.windows[i]
            if (w.workspaceId >= root.firstWorkspace && w.workspaceId <= last) out.push(w)
        }
        out.sort((a, b) => a.address < b.address ? -1 : a.address > b.address ? 1 : 0)
        return out
    }

    // ── The window layer's model (see the Repeater's note) ─────────────────────
    // address → its record on this page, and the rows: { address, gone, fresh }. Rows are
    // added and marked gone one at a time, never reset.
    readonly property var winMap: {
        const m = {}
        for (const w of root.pageWindows) m[w.address] = w
        return m
    }
    ListModel { id: winModel }
    function _rowOf(address) {
        for (let i = 0; i < winModel.count; i++) if (winModel.get(i).address === address) return i
        return -1
    }
    function _syncWins() {
        for (let i = 0; i < winModel.count; i++) {
            const r = winModel.get(i)
            if (!r.gone && root.winMap[r.address] === undefined) winModel.setProperty(i, "gone", true)
            else if (r.gone && root.winMap[r.address] !== undefined) winModel.setProperty(i, "gone", false)
        }
        for (const w of root.pageWindows)
            if (root._rowOf(w.address) < 0) winModel.append({ address: w.address, gone: false, fresh: root.active })
    }
    // A gone row's shrink has played: the row goes (unless the window came back meanwhile).
    function _drop(address) {
        const i = root._rowOf(address)
        if (i >= 0 && winModel.get(i).gone) winModel.remove(i)
    }
    onWinMapChanged: root._syncWins()
    Component.onCompleted: root._syncWins()

    // The workspace the cursor is currently dragging over. Set by the cells' DropAreas.
    property int dropTarget: -1

    // ── A window landing ──────────────────────────────────────────────────────
    // `land(ws)` rings that cell once (a dropped window, or one sent from the inspector), so
    // the move is seen where it ends, not only where it started. `_landSeq` makes a second
    // landing on the same cell ring again.
    property int _landWs: -1
    property int _landSeq: 0
    function land(ws) { root._landWs = ws; root._landSeq++ }

    // ── The zoom (OverviewZoom) ───────────────────────────────────────────────
    // A workspace's windows, each with where it really sits on THIS screen (window
    // coordinates): its preview's rect scaled back up — so the flight lands where the
    // preview said — and a fullscreen one on the whole screen (`full`: it has no rounding).
    // The previews stay up under the flight; the stand-ins fade over them (OverviewZoom).
    function zoomWindows(ws) {
        const res = Hypr.reservedOf(root.monitor)
        const fullW = root.usable.width + res[0] + res[2], fullH = root.usable.height + res[1] + res[3]
        const ps = Math.max(0.0001, root.previewScale)
        return root.pageWindows.filter(w => w.workspaceId === ws).map(w => {
            const r = root.localRect(w)
            const full = Hypr.geometryOf(w.toplevel).fullscreen
            return { address: w.address, wayland: w.wayland, full: full,
                     real: full ? Qt.rect(0, 0, fullW, fullH)
                                : Qt.rect(res[0] + r.x / ps, res[1] + r.y / ps, r.w / ps, r.h / ps) }
        })
    }
    // Where a window's preview / a workspace's cell is drawn right now, in window coordinates
    // (through every transform above it — the stage's, the card's, its own entrance). Null
    // when there isn't one.
    function previewSceneRect(address) {
        const i = root._rowOf(address)
        const it = i >= 0 ? windowLayer.winRepeater.itemAt(i) : null
        return it ? it.mapToItem(null, 0, 0, it.width, it.height) : null
    }
    function cellSceneRect(ws) {
        const c = cellRepeater.itemAt(ws - root.firstWorkspace)
        return c && c.laid ? c.sceneRect() : null
    }

    // The arrow keys (Overview.steer): the window on the grid that way from `address` (the
    // pick, or the focused window), by where the previews really sit — switcher.js
    // nearest(). A search's non-matches are skipped. "" when nothing lies that way; the
    // first match when `address` isn't on this page.
    function spatialFrom(address, dx, dy) {
        const centre = w => {
            const r = root.localRect(w)
            return { address: w.address,
                     x: root.winOriginX(w.workspaceId) + r.x + r.w / 2,
                     y: root.winOriginY(w.workspaceId) + r.y + r.h / 2 }
        }
        const pool = root.pageWindows.filter(w => !root.matching || root.matching[w.address])
        const from = pool.find(w => w.address === address)
        if (!from) return pool.length > 0 ? pool[0].address : ""
        return SwitchJs.nearest(centre(from), pool.map(centre), dx, dy)
    }

    // Shift+click on a cell or a chip: the window you were in (the focused one, under the
    // overview) — or the whole selection — goes there; the overview stays, the cell rings.
    // `modUsed` tells Overview a Shift or Ctrl was for a click, not a tap (it must not toggle).
    signal modUsed()
    // True when something was sent (a click on a cell goes there instead when nothing can be).
    function sendHere(ws) {
        if (ws <= 0) return false
        // A selection goes whole (Ctrl+click, Switcher.marks).
        if (Switcher.marked.length > 0) {
            for (const m of Switcher.marked) Hypr.moveWindowToWorkspace(m.address, ws, "", "")
            root.land(ws)
            root.modUsed()
            return true
        }
        const a = Hypr.addr(Hyprland.activeToplevel?.address ?? "")
        if (a === "") return false
        Hypr.moveWindowToWorkspace(a, ws, "", "")
        root.land(ws)
        root.modUsed()
        return true
    }

    // ── Drop ghost ────────────────────────────────────────────────────────────
    // An outline of exactly where the dragged window will land. The dragged preview
    // follows the cursor, which tells you where your HAND is — not where the window ends
    // up, because Hyprland re-tiles it on arrival.
    //
    // The ghost and the actual result are computed from the SAME anchor + direction (see
    // resolveDrop), and that pair is then handed to Hyprland as a `preselect` hint, so
    // the two cannot disagree. It's a promise the compositor is made to keep, not a
    // guess about what it might do.
    property bool ghosting:      false
    property bool ghostFloating: false
    property real ghostOffX: 0
    property real ghostOffY: 0
    property real ghostW:    0
    property real ghostH:    0

    // The cell the ghost is drawn in — NOT `dropTarget`.
    //
    // dropTarget goes to -1 whenever the cursor is between cells, and cellX(-1) is a
    // negative offset well outside the board. Positioning the ghost straight from
    // dropTarget meant that every time you crossed a gap it lurched off the grid and
    // the Behavior dutifully animated it there and back. It has to REMEMBER the last
    // real cell instead, and simply fade out while you're over nothing.
    property int ghostWs: -1

    // Where the dragged window came from, so the ghost can stay quiet while you hover
    // its own workspace, and which window is in flight (it can't tile against itself).
    property int    dragSourceWs: -1
    property string dragAddress:  ""

    // The drop, resolved: which window we're splitting, and on which side. Handed to
    // Hypr.moveWindowToWorkspace() so the window lands exactly where the ghost promised.
    property string anchorAddress: ""
    property string splitDir:      ""     // "l" | "r" | "u" | "d"
    // Ctrl held on the dragged window: a drop on another window SWAPS the two (2026-10-20,
    // the user's ask) — yours goes to its workspace, it comes to yours. The anchor is then the
    // window under the pointer (floating ones too), and the ghost outlines all of it.
    property bool swapMode: false
    onSwapModeChanged: if (root.ghosting && root.dropTarget > 0 && root.dropTarget !== root.dragSourceWs && root._lastDrop && root.slotOf(root.dropTarget) >= 0)
                           root.resolveDrop(root.dropTarget, root._lastDrop.x, root._lastDrop.y)
    property var _lastDrop: null

    onDropTargetChanged: if (dropTarget > 0 && root.slotOf(dropTarget) >= 0) root.ghostWs = dropTarget

    // ── Cell-local geometry ───────────────────────────────────────────────────
    // A window's rect inside its workspace's FIT box (winOriginX/Y), in preview
    // px — Hypr.previewRect, the same call OverviewWindow places itself with, so the
    // drop zones and the previews can't disagree. Kept inside the fit box, not the slot:
    // a maximised window on a smaller monitor, or a fullscreen one (which also covers
    // the bar), must not overflow past the box it's actually drawn in.
    function localRect(w) {
        const g = Hypr.geometryOf(w.toplevel)
        const r = Hypr.previewRect(g, w.monitor, root.previewScale, root.previewSizeFor(w.workspaceId))
        r.floating = g.floating
        return r
    }

    // ── Which edge of the window under the cursor are we dropping into? ───────
    // Not a simple "which half" — the zones are deliberately UNEVEN. Top/bottom claim
    // 40% each and are tested first; left/right only get the remaining 20% bands at the
    // sides. A plain half-split makes a horizontal drop nearly impossible to aim,
    // because the diagonal between the two halves runs right through where you want to
    // point. Biasing toward vertical splits and giving horizontal ones a narrow, explicit
    // band is what makes this feel aimed rather than random.
    readonly property real vZone: 0.40
    readonly property real hZone: 0.20

    function edgeDirection(mx, my, r) {
        const relX = r.w > 0 ? (mx - r.x) / r.w : 0.5
        const relY = r.h > 0 ? (my - r.y) / r.h : 0.5

        if (relY < root.vZone)     return "u"
        if (relY > 1 - root.vZone) return "d"
        if (relX < root.hZone)     return "l"
        if (relX > 1 - root.hZone) return "r"

        // Dead centre, in no band at all: keep the default outcome vertical.
        return relY < 0.5 ? "u" : "d"
    }

    function halfFor(dir, r) {
        switch (dir) {
            case "l": return { x: r.x,             y: r.y,             w: r.w / 2, h: r.h }
            case "r": return { x: r.x + r.w / 2,   y: r.y,             w: r.w / 2, h: r.h }
            case "u": return { x: r.x,             y: r.y,             w: r.w,     h: r.h / 2 }
            default:  return { x: r.x,             y: r.y + r.h / 2,   w: r.w,     h: r.h / 2 }
        }
    }

    // ── Resolve the drop ──────────────────────────────────────────────────────
    // Called continuously while a window is dragged over a cell. Works out where it
    // would land, and records the anchor + direction that will MAKE it land there —
    // via dwindle's `preselect` (see Hypr.moveWindowToWorkspace).
    //
    // The ghost and the result are computed from the same two values, so they cannot
    // disagree. An earlier version predicted a slot the compositor then ignored, which
    // is worse than no ghost at all.
    function resolveDrop(ws, mx, my) {
        // mx/my arrive in SLOT-local coordinates (the DropArea spans the whole
        // slot); localRect and everything derived from it work in FIT-local
        // coordinates (relative to winOriginX/Y). Shift into the same space
        // once, here, rather than smuggling the offset into every comparison
        // below.
        root._lastDrop = Qt.point(mx, my)
        const off = root.fitOffsetFor(ws)
        const fx = mx - off.x, fy = my - off.y
        const fit = root.previewSizeFor(ws)

        if (root.swapMode) {
            const under = Hypr.windowsOn(ws).filter(w => w.address !== root.dragAddress)
                .map(w => ({ address: w.address, rect: root.localRect(w) }))
                .find(c => fx >= c.rect.x && fx <= c.rect.x + c.rect.w && fy >= c.rect.y && fy <= c.rect.y + c.rect.h)
            root.anchorAddress = under ? under.address : ""
            root.splitDir = ""
            root.ghostSlot = under ? { x: under.rect.x, y: under.rect.y, w: under.rect.w, h: under.rect.h }
                                   : { x: 0, y: 0, w: fit.w, h: fit.h }
            return
        }

        const candidates = Hypr.windowsOn(ws)
            .filter(w => w.address !== root.dragAddress)
            .map(w => ({ address: w.address, rect: root.localRect(w) }))
            .filter(c => !c.rect.floating && c.rect.w > 0 && c.rect.h > 0)

        // The window under the cursor; failing that, the nearest by centre — so a drop
        // in the gutter between windows still resolves to something sensible.
        let target = null
        for (let i = 0; i < candidates.length; i++) {
            const r = candidates[i].rect
            if (fx >= r.x && fx <= r.x + r.w && fy >= r.y && fy <= r.y + r.h) {
                target = candidates[i]
                break
            }
        }
        if (!target && candidates.length > 0) {
            let best = Infinity
            for (let i = 0; i < candidates.length; i++) {
                const r = candidates[i].rect
                const d = Math.hypot(fx - (r.x + r.w / 2), fy - (r.y + r.h / 2))
                if (d < best) { best = d; target = candidates[i] }
            }
        }

        if (!target) {
            // Nothing to tile against: the window takes the whole workspace —
            // whatever size that workspace's OWN monitor actually is.
            root.anchorAddress = ""
            root.splitDir      = ""
            root.ghostSlot     = { x: 0, y: 0, w: fit.w, h: fit.h }
            return
        }

        const dir = root.edgeDirection(fx, fy, target.rect)
        root.anchorAddress = target.address
        root.splitDir      = dir
        root.ghostSlot     = root.halfFor(dir, target.rect)
    }

    function clearDrop() {
        root.anchorAddress = ""
        root.splitDir      = ""
    }

    // The ghost's rect within its cell. A floating window keeps its own footprint —
    // Hyprland won't tile it, so that one is exact without any hint at all.
    property var ghostSlot: ({ x: 0, y: 0, w: 0, h: 0 })

    Item {
        id: board
        anchors.centerIn: parent
        width:  root.boardW
        height: root.boardH

        // Identity on any normal screen; a uniform shrink only when the fixed board
        // is wider/taller than the room the overlay could give it.
        scale: root.fitScale
        transformOrigin: Item.Center

        // ── Page-switch slide ─────────────────────────────────────────────────
        // Cell positions are index-based (see colOf/rowOf) and don't move when
        // `page` changes — only the content each slot shows does, in the same
        // frame. So this can't be a real two-panel crossfade; it's a directional
        // "arriving from off to the side" cue played on the NEW content, toward
        // wherever the block you just moved to actually is.
        property real slideOffset: 0
        property int  _prevPage: root.page
        transform: Translate { x: board.slideOffset }
        opacity: 1
        Behavior on slideOffset {
            id: slideBehavior
            NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
        Behavior on opacity {
            id: fadeBehavior
            NumberAnimation { duration: Motion.standard }
        }

        Connections {
            target: root
            function onPageChanged() {
                const dir = root.page > board._prevPage ? 1 : -1
                board._prevPage = root.page
                // Jump out to the starting offset with the Behaviors off, then let
                // them ease it back to rest — the standard "disable, jump, re-enable,
                // settle next tick" dance for animating INTO a value rather than away
                // from one.
                slideBehavior.enabled = false
                fadeBehavior.enabled  = false
                board.slideOffset = dir * 56
                board.opacity = 0.3
                slideBehavior.enabled = true
                fadeBehavior.enabled  = true
                Qt.callLater(function() {
                    board.slideOffset = 0
                    board.opacity = 1
                })
            }
        }

        // ══ Cells ═════════════════════════════════════════════════════════════
        // One per workspace of the page, always — each keeps ITS workspace, so when the
        // grid opens out for a drag (see `slots`) the busy cells glide to their places and
        // the empty ones fade in at theirs, rather than cells swapping numbers. A cell with
        // no slot is hidden (at once on the way out: the busy ones are already gliding).
        Repeater {
            id: cellRepeater
            model: root.perPage

            WorkspaceGridCell {
                id: cell
                grid: root
            }
        }

        // ══ Windows ═══════════════════════════════════════════════════════════
        // One flat layer over every cell — see the header.
        WorkspaceGridWindows {
            id: windowLayer
            grid: root
        }

        // ══ The notification centre (see `notesOn`) ═══════════════════════════
        // Right of the centred cells, as tall as they are. The same body the bar's panel wears
        // (NotificationCentre, `compact`: one slim title row, the card being 6.5 units wide) —
        // so the groups, chips, Undo and empty state are one design, not a second copy. It is
        // built when the card is shown and gone when it has faded: opening it counts everything
        // seen, as the panel does, and what was new keeps its dot.
        Item {
            id: notes
            readonly property bool shown: root.notesOn && root.active
            x: root.originX + root.cellsW + root.gap * 2
            y: root.sideY
            width: root.sideW
            height: root.sideH
            Behavior on x { enabled: root.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            visible: opacity > 0.01
            opacity: notes.shown ? 1 : 0
            transform: Translate {
                x: notes.shown ? 0 : Tokens.spacingXl
                Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            }
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: notes.shown ? Motion.stagger * 6 : 0 }
                    NumberAnimation { duration: notes.shown ? Motion.standard : Motion.fast }
                }
            }

            // Sized by the Loader (anchors), which is what we want: the centre fills the card.
            Loader {
                anchors.fill: parent
                active: notes.shown || notes.visible
                sourceComponent: NotificationCentre {
                    compact: true
                    fill: true
                }
            }
        }

        // ══ The left face: pages you swipe (OverviewFeed) ══════════════════════
        // The notification centre's mirror, on the same terms (`notesOn`), arriving from the left
        // as that one does from the right. Built while shown and for its fade.
        Item {
            id: feed
            readonly property bool shown: root.notesOn && root.active
            x: root.originX - root.gap * 2 - root.sideW
            y: root.sideY
            width: root.sideW
            height: root.sideH
            Behavior on x { enabled: root.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            visible: opacity > 0.01
            opacity: feed.shown ? 1 : 0
            transform: Translate {
                x: feed.shown ? 0 : -Tokens.spacingXl
                Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            }
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: feed.shown ? Motion.stagger * 6 : 0 }
                    NumberAnimation { duration: feed.shown ? Motion.standard : Motion.fast }
                }
            }

            Loader {
                id: feedLoader
                anchors.fill: parent
                active: feed.shown || feed.visible
                sourceComponent: OverviewFeed { shown: feed.shown }
            }
        }

        // ══ Which is which ═════════════════════════════════════════════════════
        // A small number on every OTHER busy cell's top-left corner, where the focused one wears the cookie
        // below: the big faded number sits behind the windows, so a busy cell said nothing about which
        // workspace it was until you hovered it (2026-11-03 review). Over the window layer, like the badge.
        Repeater {
            model: root.perPage
            delegate: Item {
                id: numChip
                required property int index
                readonly property int ws: root.firstWorkspace + numChip.index
                readonly property bool shown: root.active && root.slotOf(numChip.ws) >= 0
                    && numChip.ws !== Hypr.focusedWorkspaceId && (Hypr.countByWorkspace[numChip.ws] ?? 0) > 0
                z: 890
                width: 24
                height: 24
                x: root.winOriginX(numChip.ws) + Tokens.spacingSm + 3
                y: root.winOriginY(numChip.ws) + Tokens.spacingSm + 3
                Behavior on x { enabled: root.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                Behavior on y { enabled: root.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                opacity: numChip.shown ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceHigh, 0.92)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outlineNested
                }
                StyledText {
                    anchors.centerIn: parent
                    text: String(numChip.ws)
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: Colors.of(QsWindow.window).fg
                }
            }
        }

        // ══ Where you are ══════════════════════════════════════════════════════
        // The focused workspace's number on a cookie that slowly winds, INSIDE its cell's
        // top-left corner — over the windows, so a maximised one cannot hide it. (It used to
        // poke out across the corner, and cut by the cell's border it read as a glitch.) ONE badge for the board, gliding (on a spring) to the new cell when the
        // workspace changes. The turn is a RotationAnimator: the render thread's, so it costs
        // the GUI thread nothing while the overview is open.
        Item {
            id: hereBadge
            readonly property int ws: Hypr.focusedWorkspaceId
            readonly property bool onPage: root.slotOf(hereBadge.ws) >= 0
            z: 900
            width: 30
            height: 30
            // Glides on M3E springs (a little past the new cell and back). They start AT their target and
            // re-seat whenever the overview opens, so it never flies in from where it last was.
            SpringValue {
                id: bx
                target: root.winOriginX(hereBadge.ws) + Tokens.spacingSm
                spec: Motion.springSpatial
            }
            SpringValue {
                id: by
                target: root.winOriginY(hereBadge.ws) + Tokens.spacingSm
                spec: Motion.springSpatial
            }
            Connections {
                target: root
                function onActiveChanged() {
                    if (!root.active) return
                    bx.jump(bx.target)
                    by.jump(by.target)
                }
            }
            x: bx.value
            y: by.value
            visible: hereBadge.onPage
            opacity: root.active ? 1 : 0
            scale: root.active ? 1 : 0.3
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            Behavior on scale {
                SequentialAnimation {
                    PauseAnimation { duration: root.active ? 180 : 0 }
                    NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                }
            }

            // An M3E shape that MORPHS as the badge moves: each workspace wears the next shape of the
            // family, so a switch reads as the badge changing form on its way, not only changing place.
            MorphShape {
                anchors.fill: parent
                shape: ["cookie9", "sunny", "cookie7", "clover", "cookie12"][hereBadge.ws % 5]
                fillColor: Colors.of(QsWindow.window).primary
                strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.5)
                strokeWidth: 2
                RotationAnimator on rotation {
                    from: 0; to: 360
                    duration: 24000
                    loops: Animation.Infinite
                    running: hereBadge.visible && root.active && Config.motionEnabled
                }
            }
            StyledText {
                anchors.centerIn: parent
                text: String(hereBadge.ws)
                variant: "caption"
                font.weight: Font.Bold
                color: Colors.of(QsWindow.window).primary.hslLightness > 0.5 ? Colors.of(QsWindow.window).base
                                                                            : Colors.of(QsWindow.window).fg
            }
        }

        // ══ The peek (see `peekWs`) ═══════════════════════════════════════════
        Surface {
            id: peek
            // The last cell peeked, kept while the card fades out.
            property int ws: -1
            readonly property bool shown: root.peeking
            onShownChanged: if (peek.shown) peek.ws = root.peekWs
            Connections {
                target: root
                function onPeekWsChanged() { if (root.peekWs > 0) peek.ws = root.peekWs }
            }
            readonly property bool below: peek.ws > 0 && root.rowOf(peek.ws) >= root.layRows - 1
            readonly property var wins: peek.ws > 0 ? Hypr.windowsOn(peek.ws) : []
            // Today's screen time, while ScreenTime records (it's off by default). It counts
            // APPS, not windows or workspaces: so a time sits on the first window of each app
            // only, and the header sums those — "what you've spent today in what's here".
            readonly property var times: {
                const per = [], seen = {}
                let sum = 0
                if (!ScreenTime.enabled) return { per: per, sum: 0 }
                for (const w of peek.wins) {
                    const k = String(w.appClass ?? "").toLowerCase()
                    const s = seen[k] ? 0 : ScreenTime.todayFor(w.appClass ?? "")
                    seen[k] = true
                    per.push(s)
                    sum += s
                }
                return { per: per, sum: sum }
            }

            z: 950
            elevation: Tokens.elevationPopup
            cornerRadius: Tokens.radiusCard
            // A cell's width, up to a list's: cells grow with the room now (see `lay`).
            width: Math.max(Tokens.sideCardUnit * 6, Math.min(root.cellW, Tokens.sideCardUnit * 8))
            height: peekCol.implicitHeight + Tokens.spacingMd * 2
            x: peek.ws > 0 ? root.cellX(peek.ws) + (root.cellW - peek.width) / 2 : 0
            y: peek.ws <= 0 ? 0
             : peek.below ? root.cellY(peek.ws) + root.cellH + Tokens.spacingSm
             : root.cellY(peek.ws) - height - Tokens.spacingSm
            Behavior on x { enabled: peek.opacity > 0.05; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
            Behavior on y { enabled: peek.opacity > 0.05; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

            visible: opacity > 0.01
            opacity: peek.shown ? 1 : 0
            scale: peek.shown ? 1 : 0.94
            transformOrigin: peek.below ? Item.Top : Item.Bottom
            Behavior on opacity { NumberAnimation { duration: peek.shown ? Motion.standard : Motion.fast } }
            Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

            // The card (2026-10-20, the user asked for a better one): a cookie with the number
            // (or the label's icon) winding as it opens, the workspace's name — its biggest
            // labelled app's (WorkspaceLabels), else "Workspace N" — and what's in it; then each
            // window as its app's icon on a tile, the title over the app's name, today's time
            // (ScreenTime) on the right; and at the foot, what the gestures on a cell do.
            Column {
                id: peekCol
                x: Tokens.spacingMd
                y: Tokens.spacingMd
                width: peek.width - Tokens.spacingMd * 2
                spacing: Tokens.spacingSm

                readonly property string label: WorkspaceLabels.nameOf(peek.ws)
                readonly property string icon: WorkspaceLabels.iconOf(peek.ws)

                Row {
                    spacing: Tokens.spacingMd
                    Item {
                        width: Tokens.iconXl + Tokens.spacingSm
                        height: width
                        // The workspace's cookie, tonal like every other header chip; it unwinds into place on a spring.
                        SpringValue {
                            id: peekTurn
                            target: peek.shown ? 0 : -40
                            spec: Motion.springSpatial
                            epsilon: 0.05
                        }
                        MorphShape {
                            anchors.fill: parent
                            shape: "cookie7"
                            turns: false
                            fillColor: Colors.of(QsWindow.window).primaryContainer
                            rotation: peekTurn.value
                        }
                        StyledText {
                            anchors.centerIn: parent
                            visible: peekCol.icon === ""
                            text: String(peek.ws)
                            variant: "label"
                            font.weight: Font.Bold
                            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: peekCol.icon !== ""
                            name: visible ? peekCol.icon : "star"
                            fill: 1
                            color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                            font.pixelSize: Tokens.iconMd
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        StyledText {
                            text: peekCol.label !== "" ? peekCol.label : Translation.tr("Workspace %1").arg(peek.ws)
                            variant: "body"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            text: (peek.wins.length === 1 ? Translation.tr("1 window") : Translation.tr("%1 windows").arg(peek.wins.length))
                                  + (peek.times.sum >= 60 ? "  ·  " + Translation.tr("%1 today").arg(ScreenTime.short(peek.times.sum)) : "")
                                  + (peekCol.label !== "" ? "  ·  " + Translation.tr("workspace %1").arg(peek.ws) : "")
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: Tokens.borderWidth
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.1)
                }

                Repeater {
                    model: peek.wins.slice(0, 5)
                    Item {
                        id: peekRow
                        required property var modelData
                        required property int index
                        readonly property string iconPath: Icons.pathForAppId(peekRow.modelData.appClass ?? "")
                        readonly property real secs: peek.times.per[peekRow.index] ?? 0
                        width: peekCol.width
                        height: Tokens.iconXl + Tokens.spacingXs
                        // Each a beat behind the one above, rising a little.
                        PopIn { id: rowPop; active: peek.shown; index: peekRow.index }
                        opacity: rowPop.opacity
                        transform: Translate { y: (1 - rowPop.opacity) * Tokens.spacingSm }

                        Rectangle {
                            id: appTile
                            anchors.verticalCenter: parent.verticalCenter
                            width: Tokens.iconXl
                            height: width
                            radius: Tokens.radiusSm
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                            Image {
                                anchors.centerIn: parent
                                visible: peekRow.iconPath !== ""
                                source: peekRow.iconPath
                                width: Tokens.iconLg
                                height: Tokens.iconLg
                                sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                visible: peekRow.iconPath === ""
                                name: "apps"
                                color: Colors.of(QsWindow.window).fgMuted
                                font.pixelSize: Tokens.iconMd
                            }
                        }
                        Column {
                            anchors.left: appTile.right
                            anchors.leftMargin: Tokens.spacingSm
                            anchors.right: spent.left
                            anchors.rightMargin: Tokens.spacingSm
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            StyledText {
                                width: parent.width
                                text: peekRow.modelData.title || peekRow.modelData.appClass || ""
                                variant: "label"
                                font.weight: Font.Medium
                                elide: Text.ElideRight
                            }
                            StyledText {
                                width: parent.width
                                text: Icons.nameForAppId(peekRow.modelData.appClass ?? "") || peekRow.modelData.appClass || ""
                                variant: "micro"
                                emphasis: "dim"
                                elide: Text.ElideRight
                            }
                        }
                        StyledText {
                            id: spent
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: peekRow.secs >= 60 ? ScreenTime.short(peekRow.secs) : ""
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                        }
                    }
                }
                StyledText {
                    visible: peek.wins.length > 5
                    text: Translation.tr("and %1 more").arg(peek.wins.length - 5)
                    variant: "caption"
                    emphasis: "dim"
                }

                // What a cell does: keycaps and words.
                Flow {
                    width: parent.width
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: [
                            { key: Translation.tr("Click"),       what: Translation.tr("go") },
                            { key: "Shift",                       what: Translation.tr("all ten  ·  click sends yours") },
                            { key: "Ctrl",                        what: Translation.tr("click selects  ·  drag swaps") }
                        ]
                        Row {
                            required property var modelData
                            spacing: Tokens.spacingXs
                            Rectangle {
                                width: capText.implicitWidth + Tokens.spacingSm * 2
                                height: capText.implicitHeight + Tokens.spacingXs
                                radius: Tokens.radiusXs
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                border.width: Tokens.borderWidth
                                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.14)
                                StyledText {
                                    id: capText
                                    anchors.centerIn: parent
                                    text: modelData.key
                                    variant: "caption"
                                    font.weight: Font.DemiBold
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.what
                                variant: "caption"
                                emphasis: "muted"
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Page dots ─────────────────────────────────────────────────────────────
    Row {
        id: pageDots
        visible: root.totalPages > 1
        anchors.top: board.bottom
        anchors.topMargin: Tokens.spacingMd
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Tokens.spacingSm

        Repeater {
            model: root.totalPages

            Rectangle {
                id: dot
                required property int index
                readonly property bool isCurrent: dot.index === root.page
                readonly property bool hasWindows: {
                    const start = dot.index * root.perPage + 1
                    const end   = start + root.perPage - 1
                    for (let id = start; id <= end; id++)
                        if (Hypr.workspaceOccupied(id)) return true
                    return false
                }

                // Current page stretches into a short pill, same "the active one is
                // wider, not just a different colour" idiom the bar's own indicator
                // uses — a colour swap alone is easy to miss at 8px.
                width:  dot.isCurrent ? root.pageDotH * 2.2 : root.pageDotH
                height: root.pageDotH
                radius: height / 2
                color:  dot.isCurrent   ? Colors.of(QsWindow.window).primary
                      : dot.hasWindows  ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.30)
                      :                   Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.10)

                Behavior on color { ColorAnimation { duration: Motion.fast } }
                Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hypr.focusWorkspace(dot.index * root.perPage + 1, true, root.monitor)
                }
            }
        }
    }
}
