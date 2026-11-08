import QtQuick
import Quickshell
import "../config"

// ── HoverTrack ────────────────────────────────────────────────────────────────
// ONE hover plate for a pill of buttons, sliding from button to button as the pointer
// moves along it — the workspaces indicator's motion, for hover (2026-10-31, the user:
// buttons in one pill group should have their hover "connected … so if hovering over the
// rest, the transition is clean, similar to what workspace pill does").
//
// A button (IconButton, CellFeedback) finds the track of the pill it stands in — the first
// ancestor offering a `hoverTrack` (BarGroup on the top bar; the sidebar's hosts hand out
// their region pill's, SideRegionPills) — and instead of fading a plate of its own in and
// out it hands the track its rect: `claim(item)` on hover, `release(item)` on leave. The
// button keeps its ripple, its lift and its lean; only the hover tint and ring move here.
//
// ── The plate ─────────────────────────────────────────────────────────────────
// The buttons' own concentric plate (IconButton's note): the item's rect grown spacingXs
// along the bar, its corners the inner pill's less the gap, and the squash and stretch while
// it's pressed. The two ends along the bar are two springs, and whichever leads the move
// rides the fast spatial one while the other trails on the standard one — so the plate
// stretches across the ground it covers and contracts as it lands, as the workspaces
// indicator does. Leaving a button starts a short linger: a claim inside it slides from
// there (the pointer crossing the gap between two buttons), none fades the plate out where
// it stands. Arriving from nothing it jumps into place and fades in, never sliding in from
// wherever it was last.
//
// ── Keeping up with the layout ────────────────────────────────────────────────
// The rect is re-read on a claim, when the claimed item's own geometry changes, and when
// the host says its layout moved (`refresh()`: BarGroup's row reflowing, the sidebar's rail
// re-laying). No per-frame mapping while the pointer rests.
//
// Zero-sized on purpose: its plate is drawn in its parent's coordinates from its own
// origin, so it can sit in a host without feeding the host's size.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // "Along" is the bar's axis: x on the top bar and along the bottom, y on a side rail.
    property bool alongY: false
    // The inner pill's corner less the gap, as every plate on the bar (IconButton).
    property real radius: Tokens.corner(Config.barShape, Math.max(0, Config.barRoundness - Tokens.spacingXs))

    property Item current: null
    // The claimed button's accent, held while the plate fades out after it.
    property color _accent: Colors.of(QsWindow.window).primary

    function claim(item) {
        if (!item) return
        linger.stop()
        const appearing = shown.value < 0.05
        root.current = item
        if (item.accent !== undefined) root._accent = item.accent
        root._read(appearing)
    }
    function release(item) {
        if (item === root.current) linger.restart()
    }
    function refresh() { if (root.current) root._read(false) }

    // Long enough to cross the gap between two buttons, short enough that leaving the pill
    // reads as leaving.
    Timer {
        id: linger
        interval: Motion.fast > 0 ? Motion.fast : 1
        onTriggered: root.current = null
    }

    // The claimed item's own moves (a pill widening under the pointer, a dock button
    // shifting as an app opens beside it).
    Connections {
        target: root.current
        ignoreUnknownSignals: true
        function onXChanged()      { root.refresh() }
        function onYChanged()      { root.refresh() }
        function onWidthChanged()  { root.refresh() }
        function onHeightChanged() { root.refresh() }
    }
    // Gone while claimed (a module taken off, a group re-keyed): `current` reads null by
    // itself (an object property drops a destroyed object), and the claimants release on
    // their way out too.

    function _read(jump) {
        const it = root.current
        if (!it) return
        const r = it.mapToItem(root, 0, 0, it.width, it.height)
        const lo = root.alongY ? r.y : r.x
        const hi = root.alongY ? r.y + r.height : r.x + r.width
        const ac = root.alongY ? r.x : r.y
        const as = root.alongY ? r.width : r.height
        if (jump) {
            loEnd.jump(lo); hiEnd.jump(hi); across.jump(ac); acrossSize.jump(as)
        } else {
            // The end on the side we're heading leads on the fast spring.
            const forward = (lo + hi) > (loEnd.target + hiEnd.target)
            hiEnd.spec = forward ? Motion.springSpatialFast : Motion.springSpatial
            loEnd.spec = forward ? Motion.springSpatial : Motion.springSpatialFast
        }
        loEnd.target = lo
        hiEnd.target = hi
        across.target = ac
        acrossSize.target = as
    }

    SpringValue { id: loEnd;      spec: Motion.springSpatialFast; epsilon: 0.05 }
    SpringValue { id: hiEnd;      spec: Motion.springSpatialFast; epsilon: 0.05 }
    SpringValue { id: across;     spec: Motion.springSpatialFast; epsilon: 0.05 }
    SpringValue { id: acrossSize; spec: Motion.springSpatialFast; epsilon: 0.05 }
    SpringValue { id: shown;      spec: Motion.springEffectsFast; epsilon: 0.005; target: root.current ? 1 : 0 }

    // Pressed: IconButton's `pressed`, CellFeedback's `_pressed`.
    readonly property bool _pressed: !!root.current
        && (root.current.pressed === true || root.current._pressed === true)
    SpringValue { id: press; spec: Motion.springSpatialFast; epsilon: 0.002; target: root._pressed ? 1 : 0 }

    // IconButton's ladder: the accent at 0.26 with a 0.4 hairline (it says why it's louder
    // than Material's 8% — a 24px button's hover didn't read).
    Rectangle {
        readonly property real grow: Tokens.spacingXs + press.value * Tokens.spacingXs / 2
        readonly property real trim: press.value * Tokens.spacingXs / 2
        readonly property real lo: Math.min(loEnd.value, hiEnd.value) - grow
        readonly property real hi: Math.max(loEnd.value, hiEnd.value) + grow
        readonly property real cross: Math.max(0, acrossSize.value - 2 * trim)

        x: root.alongY ? across.value + trim : lo
        y: root.alongY ? lo : across.value + trim
        width:  root.alongY ? cross : hi - lo
        height: root.alongY ? hi - lo : cross
        radius: Math.max(0, Math.min(root.radius, Math.min(width, height) / 2))

        color: Colors.of(QsWindow.window).alpha(root._accent, 0.26)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(root._accent, 0.4)
        Behavior on color        { ColorAnimation { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        opacity: Math.max(0, Math.min(1, shown.value))
        visible: opacity > 0.01
    }
}
