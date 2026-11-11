import QtQuick
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── WorkspaceGlance ───────────────────────────────────────────────────────────
// Rest on a slot of the bar's workspace pill and a card melts out of the bar's underside
// under it: that workspace's windows as live tiles, as the dock shows an app's. Click a
// tile to go there, middle-click to close it, right-click to bring it here. An empty
// workspace gets a small label instead.
//
// The card IS `DockPreview` (fused, `edge: "top"`), which already does the tiles, the melt
// and the blob lobe; this is the strip it asks "what is previewed and where". The key is
// `__ws:<id>` and `groupFor` answers with that workspace's windows in any app, so there is
// no second copy of the tile, the squeeze rule or the peek. Fills Bar.qml's window, like
// BarDockPopups, so the card can stand under any slot; the pill reports its hover through
// `hover()` and Bar.qml folds `maskItem` and the lobe (`blob*`) into the window's.
//
// Unwelded (floating bar, or no blob plugin) it is the dock's ordinary floating card.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var monitor: null
    // Bar.qml's `blobRing`: the blob owns the bar's fill, so the card can melt out of it.
    property bool welded: false
    property matrix4x4 deformMatrix

    // ── What DockPreview reads off its strip ──────────────────────────────────
    property string previewKey: ""
    // The bud the card grows from: one slot's width.
    property real button: 0
    readonly property bool previewHovered: preview.hovered
    function groupFor(key) {
        const g = Taskbar.workspaceGroups[parseInt(key.slice(5))]
        if (!g) return null
        // No Array.flatMap in QML's JS engine (TypeError at every call).
        const windows = []
        for (const k of g.order) for (const w of g.byKey[k].windows) windows.push(w)
        return windows.length > 0 ? { windows: windows, count: windows.length } : null
    }
    function fileFor(key) { return null }
    function closePreview() {
        dwell.stop()
        grace.stop()
        root.previewKey = ""
        // The slot just clicked stays quiet until the pointer leaves it, or going to a
        // workspace would pop its card straight back up.
        root._suppress = root.hoverId
    }

    // ── What the pill reports ─────────────────────────────────────────────────
    // Windows' own hover time and the grace that lets the pointer cross from a slot to its
    // card, as the dock's strip uses (DockIconStrip.previewDwell / previewGrace). Not
    // Motion's: with motion off those are 0 and every slot the pointer crossed would flash.
    readonly property int previewDwell: 400
    readonly property int previewGrace: 250

    property int hoverId: 0
    property int _suppress: 0
    property real anchorX: -1
    readonly property Item maskItem: preview.maskItem
    readonly property real blobX: preview.blobX
    readonly property real blobY: preview.blobY
    readonly property real blobW: preview.blobW
    readonly property real blobH: preview.blobH

    // `id` is the workspace under the pointer, 0 for none; `x` is the slot's centre in `item`.
    // A window being dragged with SUPER+drag is the pill's drop target, not a hover.
    function hover(id, item, x, bud) {
        const on = id > 0 && UiState.windowDrag === ""
        if (on) {
            root.anchorX = item.mapToItem(root, x, 0).x
            root.button = bud
        }
        root.hoverId = on ? id : 0
    }

    onHoverIdChanged: {
        if (root.hoverId !== root._suppress) root._suppress = 0
        if (root.hoverId > 0) {
            grace.stop()
            // Already showing one: follow the pointer at once, as the dock's previews slide
            // from icon to icon. Otherwise wait out the dwell.
            if (root.previewKey !== "" && root.hoverId !== root._suppress)
                root.previewKey = "__ws:" + root.hoverId
            else
                dwell.restart()
        } else {
            dwell.stop()
            if (!root.previewHovered) grace.restart()
        }
    }
    onPreviewHoveredChanged: {
        if (root.previewHovered) grace.stop()
        else if (root.hoverId === 0) grace.restart()
    }

    Timer {
        id: dwell
        interval: root.previewDwell
        onTriggered: if (root.hoverId > 0 && root.hoverId !== root._suppress)
            root.previewKey = "__ws:" + root.hoverId
    }
    Timer {
        id: grace
        interval: root.previewGrace
        onTriggered: root.previewKey = ""
    }

    // Anything that takes the whole screen over puts the card away.
    Connections {
        target: UiState
        function onOverviewOpenChanged() { if (UiState.overviewOpen) root.closePreview() }
        function onLauncherOpenChanged() { if (UiState.launcherOpen) root.closePreview() }
    }

    DockPreview {
        id: preview
        anchors.fill: parent
        strip:        root
        edge:         "top"
        monitor:      root.monitor
        fused:        root.welded
        deformMatrix: root.deformMatrix
        dockInner:    Config.belowBar
        anchorMain:   root.anchorX
        peeks:        Config.dockPeek
    }
}
