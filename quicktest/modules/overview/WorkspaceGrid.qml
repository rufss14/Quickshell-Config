import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"

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

    required property var monitor

    property int columns: 5
    property int rows:    2
    readonly property int perPage: columns * rows

    readonly property int gap: Tokens.spacingLg

    // Which block of workspaces is shown — 1-10, 11-20, … following the focused one.
    readonly property int page: Math.floor((Hypr.focusedWorkspaceId - 1) / perPage)
    readonly property int firstWorkspace: page * perPage + 1

    readonly property var usable: Hypr.usableSize(root.monitor)

    // ── Fitting ───────────────────────────────────────────────────────────────
    // The area the grid may occupy (0 = unconstrained). The caller hands us the free
    // band between the overlay's top and bottom rows and we shrink to fit, so the grid
    // never slides under the corner cards at a different resolution.
    property real maxWidth:  0
    property real maxHeight: 0

    readonly property real previewScale: {
        let s = 0.16                                     // the preferred size

        const uw = root.usable.width
        const uh = root.usable.height
        if (uw <= 0 || uh <= 0) return s

        if (root.maxWidth > 0) {
            const room = root.maxWidth - (root.columns - 1) * root.gap
            s = Math.min(s, room / (root.columns * uw))
        }
        if (root.maxHeight > 0) {
            const room = root.maxHeight - (root.rows - 1) * root.gap
            s = Math.min(s, room / (root.rows * uh))
        }
        return Math.max(0.04, s)
    }

    readonly property int cellW: Math.round(usable.width  * previewScale)
    readonly property int cellH: Math.round(usable.height * previewScale)

    readonly property int boardW: columns * cellW + (columns - 1) * gap
    readonly property int boardH: rows    * cellH + (rows    - 1) * gap

    implicitWidth:  boardW
    implicitHeight: boardH

    // Where a workspace's cell sits on the board.
    function colOf(ws) { return (ws - root.firstWorkspace) % root.columns }
    function rowOf(ws) { return Math.floor((ws - root.firstWorkspace) / root.columns) }

    function cellX(ws) { return root.colOf(ws) * (root.cellW + root.gap) }
    function cellY(ws) { return root.rowOf(ws) * (root.cellH + root.gap) }

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

    // The workspace the cursor is currently dragging over. Set by the cells' DropAreas.
    property int dropTarget: -1

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

    onDropTargetChanged: if (dropTarget > 0) root.ghostWs = dropTarget

    // ── Cell-local geometry ───────────────────────────────────────────────────
    // A window's rect inside its workspace cell, in preview px. Same maths
    // OverviewWindow uses to place itself.
    function localRect(w) {
        const g = Hypr.geometryOf(w.toplevel)
        const m = w.monitor
        const r = Hypr.reservedOf(m)
        return {
            x: Math.max(0, (g.x - (m?.x ?? 0) - r[0]) * root.previewScale),
            y: Math.max(0, (g.y - (m?.y ?? 0) - r[1]) * root.previewScale),
            w: Math.min(g.width  * root.previewScale, root.cellW),
            h: Math.min(g.height * root.previewScale, root.cellH),
            floating: g.floating
        }
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
        const candidates = Hypr.windowsOn(ws)
            .filter(w => w.address !== root.dragAddress)
            .map(w => ({ address: w.address, rect: root.localRect(w) }))
            .filter(c => !c.rect.floating && c.rect.w > 0 && c.rect.h > 0)

        // The window under the cursor; failing that, the nearest by centre — so a drop
        // in the gutter between windows still resolves to something sensible.
        let target = null
        for (let i = 0; i < candidates.length; i++) {
            const r = candidates[i].rect
            if (mx >= r.x && mx <= r.x + r.w && my >= r.y && my <= r.y + r.h) {
                target = candidates[i]
                break
            }
        }
        if (!target && candidates.length > 0) {
            let best = Infinity
            for (let i = 0; i < candidates.length; i++) {
                const r = candidates[i].rect
                const d = Math.hypot(mx - (r.x + r.w / 2), my - (r.y + r.h / 2))
                if (d < best) { best = d; target = candidates[i] }
            }
        }

        if (!target) {
            // Nothing to tile against: the window takes the whole workspace.
            root.anchorAddress = ""
            root.splitDir      = ""
            root.ghostSlot     = { x: 0, y: 0, w: root.cellW, h: root.cellH }
            return
        }

        const dir = root.edgeDirection(mx, my, target.rect)
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

        // ══ Cells ═════════════════════════════════════════════════════════════
        Repeater {
            model: root.perPage

            Item {
                id: cell
                required property int index

                readonly property int workspaceId: root.firstWorkspace + cell.index
                readonly property bool isFocused:  workspaceId === Hypr.focusedWorkspaceId
                readonly property bool isTarget:   root.dropTarget === workspaceId
                readonly property bool occupied:   Hypr.windowsOn(workspaceId).length > 0

                x: root.cellX(cell.workspaceId)
                y: root.cellY(cell.workspaceId)
                width:  root.cellW
                height: root.cellH

                Surface {
                    anchors.fill: parent
                    elevation: Tokens.elevationNested
                    cornerRadius: Tokens.radiusCard

                    // The focused workspace is where you ARE → `focus`.
                    // A drop target is where the window WILL GO → `primary`, because
                    // that's an action in progress. They must not read the same.
                    focused: cell.isFocused || cell.isTarget
                    color: cell.isTarget      ? Colors.mix(Colors.surfaceContainer, Colors.primary, 0.28)
                         : cell.isFocused     ? Colors.mix(Colors.surfaceContainer, Colors.focus, 0.16)
                         : cellHover.hovered  ? Colors.surfaceHigh
                         : Colors.surfaceContainer

                    border.width: (cell.isTarget || cell.isFocused) ? 2 : Tokens.borderWidth
                    border.color: cell.isTarget  ? Colors.primary
                                : cell.isFocused ? Colors.focus
                                : Colors.outlineNested

                    Behavior on color        { ColorAnimation { duration: Motion.respond } }
                    Behavior on border.color { ColorAnimation { duration: Motion.respond } }
                }

                HoverHandler { id: cellHover }

                // Big faded workspace number behind the windows — legible at a glance
                // without competing with the previews.
                StyledText {
                    anchors.centerIn: parent
                    text: cell.workspaceId
                    font.pixelSize: Math.round(cell.height * 0.5)
                    font.bold: true
                    color: cell.isFocused ? Colors.focus : Colors.fg
                    opacity: cell.occupied ? 0.07 : 0.16
                }

                // Click empty space in a cell to switch to that workspace.
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Hypr.focusWorkspace(cell.workspaceId)
                        UiState.overviewOpen = false
                    }
                }

                // Where a dragged window lands. QML tracks which DropArea the dragged
                // item's hotspot is over, so the grid never has to hit-test anything.
                //
                // `onExited` clearing the target is only safe because OverviewWindow
                // reads dropTarget BEFORE it lowers Drag.active — lowering it is what
                // makes this fire. Bind Drag.active to the MouseArea's drag state
                // instead and the order inverts: the target is wiped a moment before the
                // drop handler looks at it, every drop reads -1, and dragging silently
                // does nothing. That was the bug.
                // Where a dragged window lands. `drag.x`/`drag.y` are the cursor in
                // cell-local coordinates — exactly what resolveDrop() needs to work out
                // which window is being split and on which side.
                DropArea {
                    id: drop
                    anchors.fill: parent

                    onEntered: {
                        root.dropTarget = cell.workspaceId
                        if (cell.workspaceId !== root.dragSourceWs)
                            root.resolveDrop(cell.workspaceId, drop.drag.x, drop.drag.y)
                    }

                    onPositionChanged: {
                        if (cell.workspaceId === root.dragSourceWs) return
                        root.resolveDrop(cell.workspaceId, drop.drag.x, drop.drag.y)
                    }

                    onExited: {
                        if (root.dropTarget === cell.workspaceId) {
                            root.dropTarget = -1
                            root.clearDrop()
                        }
                    }
                }
            }
        }

        // ══ Windows ═══════════════════════════════════════════════════════════
        // One flat layer over every cell — see the header.
        Item {
            id: windowLayer
            anchors.fill: parent

            // ── Drop ghost ────────────────────────────────────────────────────
            // It lives INSIDE the window layer, and that placement is the whole fix.
            //
            // It used to be a sibling declared BEFORE windowLayer — same parent, same
            // default z — so every window preview painted straight over it. On an empty
            // workspace there was nothing to cover it, which is exactly why it appeared
            // to work there and nowhere else.
            //
            // z:500 puts it above windows at rest (1, or 10 hovered) and below the one
            // in your hand (1000): visible over the windows it's going to tile against,
            // never over the window you're actually dragging.
            //
            // Deliberately still, too. The first version pulsed, and it was noise — the
            // ghost already glides between cells and already fades in and out; a
            // breathing outline on top of that just competed with the drag.
            Rectangle {
                id: ghost
                z: 500

                // Hidden when the cursor is over no cell, and when hovering the window's
                // own workspace — a ghost saying "it'll go back exactly where it is"
                // tells you nothing.
                readonly property bool shown:
                    root.ghosting && root.dropTarget > 0 && root.dropTarget !== root.dragSourceWs

                visible: opacity > 0.01
                opacity: ghost.shown ? 1 : 0

                // Positioned from ghostWs (the last REAL cell), never from dropTarget,
                // and sized to the slot it will TILE into rather than to the window's
                // current geometry.
                x: root.cellX(root.ghostWs) + root.ghostSlot.x
                y: root.cellY(root.ghostWs) + root.ghostSlot.y
                width:  root.ghostSlot.w
                height: root.ghostSlot.h

                radius: Math.max(2, Tokens.radiusCard - 4)
                color: Colors.alpha(Colors.primary, 0.16)
                border.width: 2
                border.color: Colors.primary

                // Glides and reshapes as you move, rather than blinking from slot to
                // slot. This is the thing you're actually watching while you drag, so it
                // gets the emphasized curve — but at `standard`, not `spatial`: it has to
                // keep up with the pointer, and 400ms here would lag your hand.
                Behavior on x       { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                Behavior on y       { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                Behavior on width   { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                Behavior on height  { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // ── The model is a COUNT, not the array. This is load-bearing. ────
            // `model: root.pageWindows` looks obviously right and is the bug that made
            // dragging fail intermittently and the overview flicker.
            //
            // pageWindows derives from Hypr.windows, which rebuild() REASSIGNS whenever
            // its snapshot changes — and the snapshot includes each window's TITLE. With
            // a music player running, titles change on their own. A Repeater over a JS
            // array has no concept of an update: any new array is a full model reset, so
            // it destroyed and recreated every delegate — including the one under your
            // cursor, along with the MouseArea holding the mouse grab.
            //
            // So a passing title change would kill an in-progress drag and lose the
            // drop, and every window move tore down and restarted every live capture on
            // screen (the flicker). It was timing-dependent, which made it look like one
            // particular workspace was cursed.
            //
            // Binding to the LENGTH instead means the delegates survive: the count is
            // unchanged, so nothing is recreated, and each delegate re-reads its own
            // window through a binding. Captures stay alive, the drag stays alive, and a
            // moved window now animates to its new cell instead of blinking there.
            Repeater {
                model: root.pageWindows.length

                OverviewWindow {
                    required property int index

                    readonly property var win: root.pageWindows[index] ?? null

                    window: win
                    previewScale: root.previewScale

                    originX: win ? root.cellX(win.workspaceId) : 0
                    originY: win ? root.cellY(win.workspaceId) : 0

                    // A shade tighter than the cell, so a maximised window's corner
                    // nests inside the cell's corner instead of fighting it.
                    cornerRadius: Math.max(2, Tokens.radiusCard - 4)

                    dropTarget: root.dropTarget

                    // Tooltips on the bottom row open DOWNWARD. Anchored above, they'd
                    // point off the top of a cell into the row overhead and collide with
                    // the previews living there.
                    tipBelow: win ? root.rowOf(win.workspaceId) >= root.rows - 1 : false

                    onDragBegan: function(offX, offY, w, h, floating) {
                        if (!win) return

                        root.ghostOffX     = offX
                        root.ghostOffY     = offY
                        root.ghostW        = w
                        root.ghostH        = h
                        root.ghostFloating = floating
                        root.dragAddress   = win.address

                        // A floating window is never re-tiled, so its ghost is simply its
                        // own footprint — no anchor, no preselect, and exact.
                        if (floating)
                            root.ghostSlot = { x: offX, y: offY, w: w, h: h }

                        // Seed the ghost in the window's OWN cell, so its first move is a
                        // glide from somewhere real rather than a jump in from wherever
                        // the last drag happened to end.
                        root.dragSourceWs = win.workspaceId
                        root.ghostWs      = win.workspaceId
                        root.ghosting     = true
                    }

                    // The anchor + direction resolved by the DropArea are what MAKE the
                    // window land where the ghost showed it — see Hypr.moveWindowToWorkspace.
                    onRequestMove: function(target) {
                        if (!win) return
                        Hypr.moveWindowToWorkspace(win.address, target,
                                                   root.ghostFloating ? "" : root.anchorAddress,
                                                   root.ghostFloating ? "" : root.splitDir)
                    }

                    // Whatever happened — moved, snapped back, or the grab was taken
                    // away — the highlight and the ghost go with it.
                    onDragFinished: {
                        root.dropTarget   = -1
                        root.ghosting     = false
                        root.dragSourceWs = -1
                        root.dragAddress  = ""
                        root.clearDrop()
                    }
                }
            }
        }
    }
}
