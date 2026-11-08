import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/switcher.js" as SwitchJs
import "../../notifications"
import QtQuick.Layouts
import ".."

// ── WorkspaceGridCell ── part of WorkspaceGrid.qml; `grid` is the WorkspaceGrid it belongs to. ──
Item {
    id: cell
    required property var grid
    required property int index
    function sceneRect() { return card.mapToItem(null, 0, 0, card.width, card.height) }

    readonly property int workspaceId: grid.firstWorkspace + cell.index
    readonly property bool laid: grid.slotOf(cell.workspaceId) >= 0
    visible: cell.laid
    opacity: cell.laid ? 1 : 0
    scale: cell.laid ? 1 : 0.9
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
    Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
    readonly property bool isFocused:  workspaceId === Hypr.focusedWorkspaceId
    readonly property bool isTarget:   grid.dropTarget === workspaceId || (cell.offered && grid.dropTarget === grid.newTarget)
    // Where this cell sends and goes: itself, or — the "+ New" cell — the pill's pick.
    readonly property int goesTo: cell.offered ? grid.newTarget : cell.workspaceId
    // A map lookup, not a filter over every window. This was
    // `Hypr.windowsOn(workspaceId).length > 0` — ten cells each walking the
    // whole window list, four times a second, to answer a yes/no.
    readonly property bool occupied:   (Hypr.countByWorkspace[cell.workspaceId] ?? 0) > 0
    // The cell offered as a new workspace (`newWs`): drawn as an invitation, not an empty box.
    readonly property bool offered: grid.offersNew && grid.newWs === cell.workspaceId && !cell.occupied

    // A brief accent flash on click, so the overview doesn't just vanish
    // the instant you tap a cell — it confirms which one you picked first.
    // Reset by the same timer that actually closes the overview, so it
    // never leaks a stale flash into the next time this cell is shown.
    property bool justClicked: false

    x: grid.cellX(cell.workspaceId)
    y: grid.cellY(cell.workspaceId)
    width:  grid.cellW
    height: grid.cellH
    Behavior on x { enabled: grid.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    Behavior on y { enabled: grid.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

    // The slot (this Item) is always cellW×cellH, so the board's layout
    // never moves. What's actually DRAWN can be smaller — see
    // previewSizeFor — when this workspace's real monitor is.
    readonly property var fitSize:   grid.previewSizeFor(cell.workspaceId)
    readonly property var fitOffset: grid.fitOffsetFor(cell.workspaceId)

    // The screen this workspace is on, when it is not the one this overview is on: a tab on
    // the cell's lower edge names it (several monitors only — one has nothing to tell apart).
    readonly property var screenOf: grid.monitorOf(cell.workspaceId)
    readonly property bool elsewhere: Hypr.monitors.length > 1 && cell.screenOf !== null
                                      && cell.screenOf.name !== (grid.monitor?.name ?? "")

    // ── Focus / target halo ──────────────────────────────────────────
    // The border says "this one" in a hairline; this says it in light —
    // a soft accent bloom hugging the card. The shared OverviewGlow,
    // rounded rather than circular so it reads as this card's own shape
    // rather than a spotlight of the wrong silhouette. Declared before
    // `card` so it paints behind it, and `active`-gated: on a page where
    // at most two cells (focused + drop target) are ever lit, the other
    // eight idle for free.
    OverviewGlow {
        anchors.centerIn: card
        circular:      false
        contentWidth:  card.width
        contentHeight: card.height
        contentRadius: Tokens.radiusCard
        accent:        cell.isTarget ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).primary
        active:        cell.isFocused || cell.isTarget || (grid.peeking && grid.peekWs === cell.workspaceId)
    }

    Surface {
        id: card
        x: cell.fitOffset.x
        y: cell.fitOffset.y
        width:  cell.fitSize.w
        height: cell.fitSize.h
        Behavior on width  { enabled: grid.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on height { enabled: grid.active; NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        // Card, not Nested — this cell sits directly on the overview's
        // dimmed backdrop (gridArea is a bare Item), same as CalendarCard,
        // TimerCard, OverviewDock and everything else out here. Nested
        // means "a control inside a card", which this isn't; it was the
        // one card in the overview still on the wrong shade of grey.
        elevation: Tokens.elevationCard
        cornerRadius: Tokens.radiusCard

        // The focused workspace is where you ARE → `focus`.
        // A drop target is where the window WILL GO → `primary`, because
        // that's an action in progress. They must not read the same.
        focused: cell.isFocused || cell.isTarget
        // A little see-through, like a panel's section cards: the overview's container
        // carries the cookie field, and an empty workspace shows it drifting by.
        color: Colors.of(QsWindow.window).fade(
                 cell.justClicked   ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surface, Colors.of(QsWindow.window).primary, 0.40)
               : cell.isTarget      ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surface, Colors.of(QsWindow.window).primary, 0.28)
               : cell.isFocused     ? Colors.of(QsWindow.window).primaryContainer
               : cell.offered       ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surface, Colors.of(QsWindow.window).primary, cellHover.hovered ? 0.2 : 0.1)
               : cellHover.hovered  ? Colors.of(QsWindow.window).surfaceHigh
               : Colors.of(QsWindow.window).surfaceContainer,
                 cell.occupied || cell.offered || cellHover.hovered || cell.isTarget ? 0.9 : 0.62)

        // A prominent edge, on the shell's chrome border width rather
        // than the fine 1px hairline — a workspace cell is a big surface
        // sitting on the wallpaper, the same class of thing as a bar pill
        // or the screen frame, and reads better with their weight.
        // Chrome weight only for the cell that is lit; the rest sit on a hairline (card, cell and preview each
        // had a heavy edge, which read as noise — 2026-11-03 review).
        border.width: (cell.isTarget || cell.isFocused)
                      ? Tokens.borderChrome + 1
                      : Tokens.borderWidth
        border.color: cell.isTarget  ? Colors.of(QsWindow.window).primary
                    : cell.isFocused ? Colors.of(QsWindow.window).focus
                    : cell.offered   ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, cellHover.hovered ? 0.9 : 0.5)
                    : cellHover.hovered ? Colors.of(QsWindow.window).outlineFocus
                    : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.24)

        Behavior on color        { ColorAnimation { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        // ── Entrance ──────────────────────────────────────────────────
        // Fades and scales up from rest, staggered by index so the board
        // reads as assembling itself rather than popping in as one block.
        // Riding on `grid.active` rather than the overlay's own opacity/
        // scale (`stage`, in Overview.qml) means this cell's fade is
        // rendered MULTIPLICATIVELY under that parent fade — on close the
        // stage's own fast exit already drives visible opacity to zero well
        // before this one's slower staggered animation would matter, so the
        // two never fight; on open the stagger is what actually shows.
        opacity: grid.active ? 1.0 : 0.0
        scale:   grid.active ? 1.0 : 0.90
        // A ripple out from where you are: each cell arrives a beat after its neighbour
        // nearer the focused workspace, so the grid spreads from the thing you know.
        readonly property int entranceDelay: grid.rippleDelay(cell.workspaceId, cell.index)
        Behavior on opacity {
            SequentialAnimation {
                PauseAnimation { duration: card.entranceDelay }
                NumberAnimation { duration: Motion.standard }
            }
        }
        Behavior on scale {
            SequentialAnimation {
                PauseAnimation { duration: card.entranceDelay }
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }
        }

        // ── Hover lift ────────────────────────────────────────────────
        // A few px up, not a scale — scale is spoken for by the entrance
        // above, and stacking a second driver onto it would mean the lift
        // inherits the entrance's stagger pause and feels laggy on every
        // hover. A plain Translate is independent of both.
        SpringValue {
            id: lift
            target: cellHover.hovered ? -3 : 0
            spec: Motion.springSpatialFast
            epsilon: 0.01
        }
        transform: Translate { y: lift.value }

        // ── The workspace's own wallpaper, behind its windows ─────────────────
        // What this workspace actually looks like (Wallpaper.pictureFor: its own picture when it has one,
        // else the shared one), dimmed under the cell's tone, so a cell reads as the place it is and an
        // empty one is not a hollow box. Decoded small (a cell is ~350 px) and only for a cell that is
        // laid; ten cells of the same picture share one decode.
        ClippingRectangle {
            id: cellWall
            anchors.fill: parent
            anchors.margins: card.border.width
            radius: Math.max(0, card.radius - card.border.width)
            color: "transparent"
            readonly property string pic: cell.laid ? Wallpaper.pictureFor(cell.workspaceId) : ""
            // A workspace with its OWN picture always wears it; with the shared one, only a busy cell does,
            // faintly (ten empty cells of the same artwork was wallpaper-wall noise that fought the numbers).
            readonly property bool own: Wallpaper.wallFor(cell.workspaceId) !== ""
            readonly property real amount: own ? 0.45 : cell.occupied ? 0.26 : 0
            visible: pic !== "" && amount > 0 && !cell.offered
            Image {
                anchors.fill: parent
                source: cellWall.pic !== "" ? "file://" + cellWall.pic : ""
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(480, 270)
                asynchronous: true
                cache: true
                opacity: cellWall.amount
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
            }
        }

        // Big faded workspace number behind the windows — legible at a
        // glance without competing with the previews. Lives on the CARD,
        // not the slot, so it scales and centres with whatever size the
        // card actually drew at. (Tried a small corner badge here instead —
        // reverted, the giant number was preferred.)
        StyledText {
            anchors.centerIn: parent
            visible: WorkspaceLabels.iconOf(cell.workspaceId) === "" && !cell.offered
            text: cell.workspaceId
            font.pixelSize: Math.round(card.height * 0.5)
            font.bold: true
            color: cell.isFocused ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
            opacity: cell.occupied ? 0.07 : 0.16
        }
        // A workspace with its own icon (WorkspaceLabels) wears that instead.
        MaterialIcon {
            anchors.centerIn: parent
            visible: WorkspaceLabels.iconOf(cell.workspaceId) !== "" && !cell.offered
            name: visible ? WorkspaceLabels.iconOf(cell.workspaceId) : "star"
            fill: 1
            font.pixelSize: Math.round(card.height * 0.42)
            color: cell.isFocused ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
            opacity: cell.occupied ? 0.07 : 0.16
        }
    }

    // ── The screen tab ───────────────────────────────────────────────
    // Hangs on the cell's lower edge, in the gap: a window on top can't hide it.
    Rectangle {
        id: screenTab
        anchors.horizontalCenter: card.horizontalCenter
        y: card.y + card.height - Tokens.spacingXs
        implicitHeight: Tokens.iconLg
        height: implicitHeight
        width: tabRow.implicitWidth + Tokens.spacingMd * 2
        radius: height / 2
        color: Colors.of(QsWindow.window).surfaceHigh
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outlineNested
        opacity: cell.elsewhere && cell.laid ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        Row {
            id: tabRow
            anchors.centerIn: parent
            spacing: Tokens.spacingXs
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "monitor"
                color: Colors.of(QsWindow.window).fgMuted
                font.pixelSize: Tokens.iconSm
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: cell.screenOf?.name ?? ""
                variant: "caption"
                emphasis: "muted"
            }
        }
    }

    // ── A window landed here: a ring leaves the cell ─────────────────
    Rectangle {
        id: landRing
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: Tokens.radiusCard
        color: "transparent"
        border.width: 2
        border.color: Colors.of(QsWindow.window).primary
        opacity: 0
        visible: opacity > 0.01
        ParallelAnimation {
            id: landAnim
            NumberAnimation { target: landRing; property: "scale";   from: 1.0;  to: 1.12; duration: Motion.emphasized; easing.type: Motion.travel }
            NumberAnimation { target: landRing; property: "opacity"; from: 0.95; to: 0;    duration: Motion.emphasized; easing.type: Motion.travel }
        }
        Connections {
            target: grid
            function on_LandSeqChanged() {
                if (grid._landWs === cell.workspaceId && Config.motionEnabled) landAnim.restart()
            }
        }
    }

    HoverHandler {
        id: cellHover
        onHoveredChanged: grid.hoverCell(cell.workspaceId, cellHover.hovered)
    }

    // Click empty space in a cell to switch to that workspace. The switch
    // itself fires immediately — only the overview's own dismissal waits,
    // just long enough for the click flash above to actually be seen.
    // Shift+click instead SENDS the window you were in here and stays open.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
            // Shift held, or toggled on (`showAll`): send your window here, if there is one.
            if (((mouse.modifiers & Qt.ShiftModifier) || grid.showAll) && grid.sendHere(cell.goesTo)) return
            cell.justClicked = true
            Hypr.focusWorkspace(cell.goesTo, true, grid.monitor)
            // Zooms into this cell, then closes (UiState.leaveOverview).
            UiState.leaveOverview(cell.workspaceId)
            unflash.start()
        }
    }

    Timer {
        id: unflash
        interval: Motion.spatial
        onTriggered: cell.justClicked = false
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
            grid.dropTarget = cell.goesTo
            if (cell.goesTo !== cell.workspaceId) grid.clearDrop()
            else if (cell.workspaceId !== grid.dragSourceWs)
                grid.resolveDrop(cell.workspaceId, drop.drag.x, drop.drag.y)
        }

        onPositionChanged: {
            if (cell.workspaceId === grid.dragSourceWs || cell.goesTo !== cell.workspaceId) return
            grid.resolveDrop(cell.workspaceId, drop.drag.x, drop.drag.y)
        }

        onExited: {
            if (grid.dropTarget === cell.goesTo) {
                grid.dropTarget = -1
                grid.clearDrop()
            }
        }
    }

    // ── The offered empty workspace (`newWs`) ─────────────────────────────
    // A cookie with a plus that turns slowly, what the cell is for, and under it a pill of
    // the page's empty workspaces (the bar's workspace pill, here): drop a window on one to
    // give it that workspace; CLICK one to pick it (ringed), and the cell then goes and
    // sends there (`newTarget`). Over the cell's MouseArea and DropArea (declared after
    // them) so the chips get the click and the drop; the cookie and label take neither.
    Item {
        id: newFace
        readonly property bool on: cell.offered
        readonly property int disc: Math.max(32, Math.min(84, Math.round(card.height * 0.32)))
        readonly property var options: grid.freeSlots
        x: card.x + Math.round((card.width - newFace.width) / 2)
        SpringValue {
            id: newLift
            target: cellHover.hovered ? -3 : 0
            spec: Motion.springSpatialFast
            epsilon: 0.01
        }
        y: card.y + Math.round((card.height - newFace.height) / 2) + newLift.value
        width: Math.max(newFace.disc, newLabel.implicitWidth, newPill.width)
        height: newCol.implicitHeight
        opacity: newFace.on ? 1 : 0
        scale: newFace.on ? 1 : 0.9
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
        Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        Column {
            id: newCol
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Tokens.spacingSm
            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                width: newFace.disc
                height: newFace.disc
                // Opens from a cookie to a sunburst under the pointer (an M3E morph) and turns slowly.
                MorphShape {
                    anchors.fill: parent
                    shape: cellHover.hovered ? "sunny" : "cookie9"
                    fillColor: Colors.of(QsWindow.window).primaryContainer
                    strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.6)
                    strokeWidth: 2
                    RotationAnimator on rotation {
                        from: 0; to: 360
                        duration: 30000
                        loops: Animation.Infinite
                        running: newFace.on && grid.active && Config.motionEnabled
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: "add"
                    color: Colors.of(QsWindow.window).fgOnPrimaryContainer
                    font.pixelSize: Math.round(newFace.disc * 0.5)
                }
            }
            StyledText {
                id: newLabel
                anchors.horizontalCenter: parent.horizontalCenter
                text: Translation.tr("New workspace")
                variant: "label"
                font.weight: Font.DemiBold
                color: Colors.of(QsWindow.window).primary
            }
            // The pill: round chips, the first (this cell's own) ringed. Too small a cell
            // goes without it, and the chips shrink to fit a narrow one.
            Rectangle {
                id: newPill
                readonly property int pad: Tokens.spacingXs + 1
                readonly property int n: newFace.options.length
                readonly property int chip: Math.max(20, Math.min(28, Math.floor(
                    (card.width - Tokens.spacingXl * 2 - newPill.pad * 2 - (newPill.n - 1) * Tokens.spacingXs) / Math.max(1, newPill.n))))
                anchors.horizontalCenter: parent.horizontalCenter
                visible: card.height >= 100 && newPill.n > 0
                width: newPill.n * newPill.chip + Math.max(0, newPill.n - 1) * Tokens.spacingXs + newPill.pad * 2
                height: newPill.chip + newPill.pad * 2
                radius: height / 2
                color: Colors.of(QsWindow.window).surfaceContainer
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                Row {
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: newFace.options
                        delegate: Rectangle {
                            id: wsDot
                            required property var modelData
                            readonly property int ws: wsDot.modelData
                            readonly property bool target: grid.dropTarget === wsDot.ws
                            // The pick (`newTarget`): ringed, and what the cell goes to.
                            readonly property bool first: wsDot.ws === grid.newTarget
                            width: newPill.chip
                            height: newPill.chip
                            radius: height / 2
                            color: wsDot.target ? Colors.of(QsWindow.window).primary
                                 : wsDot.first ? Colors.of(QsWindow.window).primaryContainer
                                 : dotHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.16)
                                 : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                            border.width: wsDot.first && !wsDot.target ? Tokens.borderWidth : 0
                            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.7)
                            SpringValue {
                                id: dotLean
                                target: wsDot.target ? 1.18 : dotTap.pressed ? 0.9 : dotHover.hovered ? 1.06 : 1
                                spec: Motion.springSpatialFast
                                epsilon: 0.001
                            }
                            scale: dotLean.value
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            StyledText {
                                anchors.centerIn: parent
                                text: String(wsDot.ws)
                                variant: "caption"
                                font.weight: Font.DemiBold
                                color: wsDot.target ? (Colors.of(QsWindow.window).primary.hslLightness > 0.5 ? Colors.of(QsWindow.window).base : Colors.of(QsWindow.window).fg)
                                                    : Colors.of(QsWindow.window).fg
                            }
                            HoverHandler { id: dotHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                id: dotTap
                                onTapped: grid.newChoice = wsDot.ws
                            }
                            // A dragged window over a chip: that workspace is the target (it has no cell, so no ghost).
                            DropArea {
                                anchors.fill: parent
                                onEntered: { grid.dropTarget = wsDot.ws; grid.clearDrop() }
                                onExited: if (grid.dropTarget === wsDot.ws) grid.dropTarget = -1
                            }
                        }
                    }
                }
            }
        }
    }
}
