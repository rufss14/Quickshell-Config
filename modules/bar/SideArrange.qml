pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"

// ── SideArrange ───────────────────────────────────────────────────────────────
// Arrange mode for the sidebar, drawn in the bar's window over the REAL sidebar —
// BarArrange's twin (read its header: the drag is a platform one, the targets
// commit on drop, and the thing you arrange is the thing itself, not a copy). Bar.qml
// keeps it behind a Loader on UiState.sidebarArrange, so a sidebar nobody is
// arranging pays for none of it.
//
//   drag a module          along the sidebar to move it
//   …onto another          into that group, before or after it (which HALF you're
//                          over is the gesture) — never the dock's: it stands alone
//   …into a gap            a group of its own, there
//   …onto an empty region  a group of its own, in that region
//   …out past the sidebar  off it — it waits in Settings › Sidebar
//   from Settings          the module tiles there are the same drag, into here
//
// Every target is computed from the rail and the layout (SideRail.at, allLengths,
// Config.sidebarLayout), never read off the modules' items, so it can't disagree
// with where the rail put them. The handles sit over the modules, which are
// disabled while arranging (SideGroupHost, DockHost) and dim while in the hand.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property SideRail rail

    anchors.fill: parent

    // For Bar.qml's input mask: the sidebar's band and the room beside it, so a
    // drag that leaves the sidebar keeps landing somewhere (BarArrange's shelf).
    readonly property Item maskItem: maskBox

    // ══ Geometry ══════════════════════════════════════════════════════════════
    readonly property string edge: root.rail.edge
    readonly property bool vertical: root.rail.vertical
    readonly property real bandLo: root.rail.surfaceLo
    readonly property real bandHi: root.rail.surfaceHi
    // The room beside the sidebar that takes a module off it.
    readonly property real offDepth: Tokens.sideCardUnit * 3
    // How much of a gap between groups is there to aim at.
    readonly property real seamW: Math.max(root.rail.groupGap * 2, Tokens.spacingXl)

    // An along-the-edge span as a box across the sidebar's band, in window space.
    function rectFor(pos, len) {
        const d = root.bandHi - root.bandLo
        return root.edge === "left"  ? Qt.rect(root.bandLo, pos, d, len)
             : root.edge === "right" ? Qt.rect(root.rail.screenW - root.bandHi, pos, d, len)
             :                         Qt.rect(pos, root.rail.screenH - root.bandHi, len, d)
    }
    // A pointer's place along the edge inside a box of that span.
    function along(x, y) { return root.vertical ? y : x }

    // The span of group `gi` in `region`: from its first module to its last.
    function groupSpan(region, gi) {
        const g = (Config.sidebarLayout[region] ?? [])[gi] ?? []
        let lo = Infinity, hi = -Infinity
        for (const id of g) {
            const at = root.rail.at[id], len = root.rail.allLengths[id] ?? 0
            if (at === undefined || len <= 0) continue
            lo = Math.min(lo, at)
            hi = Math.max(hi, at + len)
        }
        return lo === Infinity ? null : { lo: lo, hi: hi }
    }

    // ══ The modules, as handles ═══════════════════════════════════════════════
    // By id: a module that moves keeps its handle (and, mid-gesture, its drag).
    readonly property var placedIds: {
        const out = []
        for (const r of Config.sidebarRegionIds)
            for (const g of (Config.sidebarLayout[r] ?? []))
                for (const id of g) out.push(id)
        return out
    }

    Repeater {
        model: ScriptModel { values: root.placedIds }
        delegate: Item {
            id: handle
            required property string modelData

            readonly property var loc: Config.sidebarLocate(handle.modelData)
            readonly property real pos: root.rail.at[handle.modelData] ?? -1
            readonly property real len: root.rail.allLengths[handle.modelData] ?? 0
            readonly property rect box: root.rectFor(handle.pos, handle.len)

            x: handle.box.x
            y: handle.box.y
            width:  handle.box.width
            height: handle.box.height
            visible: handle.loc !== null && handle.pos >= 0 && handle.len > 0

            // ── As a target: into its group, before or after it ───────────────
            function target(px, py) {
                const after = root.along(px, py) > (root.vertical ? handle.height : handle.width) / 2
                return { kind: "chip", owner: handle.modelData, region: handle.loc.region,
                         group: handle.loc.group, index: handle.loc.index + (after ? 1 : 0) }
            }
            DropArea {
                id: chipDrop
                anchors.fill: parent
                keys: [SideDrag.mime]
                enabled: SideDrag.dragId !== handle.modelData
                onEntered: function (d) { SideDrag.drop = handle.target(d.x, d.y) }
                onPositionChanged: function (d) { SideDrag.drop = handle.target(d.x, d.y) }
                onExited: if (SideDrag.drop?.kind === "chip" && SideDrag.drop?.owner === handle.modelData)
                              SideDrag.drop = null
                onDropped: function (d) {
                    const id = SideDrag.idFromDrop(d)
                    if (id === "" || id === handle.modelData) return
                    SideDrag.dropExternal(id, handle.target(d.x, d.y))
                    d.acceptProposedAction()
                }
            }

            // "It lands here, inside this group": a bar across the sidebar at the
            // side it lands on — the bar's solid insertion mark, turned.
            Rectangle {
                id: mark
                readonly property bool lit: SideDrag.drop?.kind === "chip" && SideDrag.drop?.owner === handle.modelData
                readonly property bool after: mark.lit && SideDrag.drop.index > (handle.loc?.index ?? 0)
                visible: mark.lit
                color: Colors.of(QsWindow.window).focus
                radius: Tokens.borderChrome
                width:  root.vertical ? parent.width - Tokens.spacingSm * 2 : Tokens.borderChrome * 2
                height: root.vertical ? Tokens.borderChrome * 2 : parent.height - Tokens.spacingSm * 2
                x: root.vertical ? Tokens.spacingSm : (mark.after ? parent.width - width : 0)
                y: root.vertical ? (mark.after ? parent.height - height : 0) : Tokens.spacingSm
            }

            // Hover: this is a thing you can pick up.
            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXs
                radius: Config.sidebarRadius
                color: "transparent"
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).outlineFocus
                opacity: grab.containsMouse && !SideDrag.dragging ? 1 : 0
                visible: opacity > 0.005
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // ── As a source ───────────────────────────────────────────────────
            // BarGroupRow's drag proxy, as-is: `drag.target` must point at
            // something for `drag.active` to go true, and not at anything laid out.
            // `armed` is a latch only this file writes (BarGroupRow says why a
            // binding to drag.active loops).
            Item {
                id: proxy
                width: 1
                height: 1
                property bool armed: false
                Drag.active: proxy.armed
                Drag.dragType: Drag.Automatic
                Drag.supportedActions: Qt.MoveAction
                Drag.proposedAction: Qt.MoveAction
                Drag.mimeData: {
                    const m = {}
                    m[SideDrag.mime] = handle.modelData
                    return m
                }
                Drag.hotSpot: Qt.point(handle.width / 2, handle.height / 2)
                Drag.onDragFinished: {
                    proxy.armed = false
                    SideDrag.cancel()
                }
            }

            MouseArea {
                id: grab
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                cursorShape: SideDrag.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                drag.target: proxy
                drag.smoothed: false
                drag.onActiveChanged: {
                    if (!grab.drag.active) return
                    SideDrag.dragging = true
                    SideDrag.dragId = handle.modelData
                    proxy.armed = true
                }
                // The picture it carries: the real module, grabbed on press so it's
                // ready by the time the drag starts (grabToImage is asynchronous).
                onPressed: {
                    const item = root.rail.items[handle.modelData] ?? handle
                    item.grabToImage(function (result) { proxy.Drag.imageSource = result.url },
                                     Qt.size(Math.max(1, item.width), Math.max(1, item.height)))
                }
            }
        }
    }

    // ══ The gaps between groups, and the group lines ══════════════════════════
    // One per group ("region|index"), carrying the gap before it and — the last in
    // its region — the one after. Keys are positions, not contents: a group that
    // changes keeps its delegate, which just reads the layout again.
    readonly property var groupKeys: {
        const out = []
        for (const r of Config.sidebarRegionIds) {
            const n = (Config.sidebarLayout[r] ?? []).length
            for (let i = 0; i < n; i++) out.push(r + "|" + i)
        }
        return out
    }

    Repeater {
        model: ScriptModel { values: root.groupKeys }
        delegate: Item {
            id: grp
            required property string modelData
            readonly property string region: grp.modelData.split("|")[0]
            readonly property int index: parseInt(grp.modelData.split("|")[1])
            readonly property var span: root.groupSpan(grp.region, grp.index)
            readonly property bool last: grp.index === (Config.sidebarLayout[grp.region] ?? []).length - 1
            anchors.fill: parent
            visible: grp.span !== null

            // The group line: along the sidebar's face, the group's length — which
            // modules share a group is otherwise invisible exactly when you decide it.
            Rectangle {
                readonly property rect r: grp.span ? root.rectFor(grp.span.lo + Tokens.spacingXs,
                                                                  grp.span.hi - grp.span.lo - Tokens.spacingXs * 2)
                                                   : Qt.rect(0, 0, 0, 0)
                readonly property int t: Tokens.borderChrome
                x: root.edge === "left"  ? r.x + r.width - t * 2
                 : root.edge === "right" ? r.x + t
                 :                         r.x
                y: root.vertical ? r.y : r.y + t
                width:  root.vertical ? t : r.width
                height: root.vertical ? r.height : t
                radius: t / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.55)
            }

            Seam { region: grp.region; gap: grp.index;     at: grp.span ? grp.span.lo - root.rail.groupGap / 2 : -1 }
            Seam { region: grp.region; gap: grp.index + 1; at: grp.span ? grp.span.hi + root.rail.groupGap / 2 : -1
                   visible: grp.last && grp.span !== null }
        }
    }

    // "A group of its own, here": a hollow outline in the gap — a different SHAPE
    // from the insertion bar, because they mean different things (BarGroupRow).
    component Seam: Item {
        id: seam
        property string region: ""
        property int gap: 0
        property real at: -1
        readonly property rect r: root.rectFor(seam.at - root.seamW / 2, root.seamW)
        readonly property bool armed: SideDrag.drop?.kind === "gap" && SideDrag.drop?.region === seam.region
                                      && SideDrag.drop?.groupIndex === seam.gap
        x: seam.r.x
        y: seam.r.y
        width:  seam.r.width
        height: seam.r.height
        z: 2
        DropArea {
            anchors.fill: parent
            keys: [SideDrag.mime]
            onEntered: SideDrag.drop = { kind: "gap", region: seam.region, groupIndex: seam.gap }
            onExited: if (seam.armed) SideDrag.drop = null
            onDropped: function (d) {
                const id = SideDrag.idFromDrop(d)
                if (id === "") return
                SideDrag.dropExternal(id, { kind: "gap", region: seam.region, groupIndex: seam.gap })
                d.acceptProposedAction()
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: Tokens.spacingXs
            visible: seam.armed
            radius: Config.sidebarRadius
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.14)
            border.width: Tokens.borderChrome
            border.color: Colors.of(QsWindow.window).focus
        }
    }

    // ══ Empty regions ═════════════════════════════════════════════════════════
    // Where nothing stands there's nothing to aim between, so an empty region is a
    // target of its own, at the place its first module would go — only while
    // something is in the air.
    readonly property real zoneLen: Config.sidebarCell + root.rail.pad * 2
    Repeater {
        model: Config.sidebarRegionIds
        delegate: Item {
            id: zone
            required property string modelData
            readonly property bool empty: (Config.sidebarLayout[zone.modelData] ?? []).length === 0
            readonly property real pos:
                  zone.modelData === "start" ? root.rail.near
                : zone.modelData === "end"   ? root.rail.corner - root.zoneLen
                : ((root.vertical ? root.rail.spanStart : 0)
                   + (root.vertical ? root.rail.spanEnd : root.rail.screenW)) / 2 - root.zoneLen / 2
            readonly property rect r: root.rectFor(zone.pos, root.zoneLen)
            x: zone.r.x
            y: zone.r.y
            width:  zone.r.width
            height: zone.r.height
            visible: zone.empty

            DropArea {
                id: zoneDrop
                anchors.fill: parent
                keys: [SideDrag.mime]
                onEntered: SideDrag.drop = { kind: "region", region: zone.modelData }
                onExited: if (SideDrag.drop?.kind === "region" && SideDrag.drop?.region === zone.modelData)
                              SideDrag.drop = null
                onDropped: function (d) {
                    const id = SideDrag.idFromDrop(d)
                    if (id === "") return
                    SideDrag.dropExternal(id, { kind: "region", region: zone.modelData })
                    d.acceptProposedAction()
                }
            }
            Rectangle {
                anchors.fill: parent
                anchors.margins: Tokens.spacingXs
                visible: SideDrag.dragging || zoneDrop.containsDrag
                radius: Config.sidebarRadius
                color: zoneDrop.containsDrag ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.16) : "transparent"
                border.width: Tokens.borderWidth
                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.45)
            }
        }
    }

    // ══ Off the sidebar ═══════════════════════════════════════════════════════
    // The room beside it: drop a module here and it comes off (it waits in
    // Settings › Sidebar). No card — the room and one line saying what's about to
    // happen, as the bar's shelf became.
    Item {
        id: off
        readonly property real lo: root.vertical ? root.rail.spanStart : root.rail.strip
        readonly property real hi: root.vertical ? root.rail.spanEnd : root.rail.screenW - root.rail.strip
        x: root.edge === "left"  ? root.bandHi
         : root.edge === "right" ? root.rail.screenW - root.bandHi - root.offDepth
         :                         off.lo
        y: root.vertical ? off.lo : root.rail.screenH - root.bandHi - root.offDepth
        width:  root.vertical ? root.offDepth : off.hi - off.lo
        height: root.vertical ? off.hi - off.lo : root.offDepth

        DropArea {
            id: offDrop
            anchors.fill: parent
            keys: [SideDrag.mime]
            onEntered: SideDrag.drop = { kind: "off" }
            onExited: if (SideDrag.drop?.kind === "off") SideDrag.drop = null
            onDropped: function (d) {
                const id = SideDrag.idFromDrop(d)
                if (id === "" || !Config.sidebarPlaced(id)) return
                SideDrag.dropExternal(id, { kind: "off" })
                d.acceptProposedAction()
            }
        }

        // A hairline along the sidebar's face while a module is over the room —
        // in the danger colour, because what happens next is a removal.
        Rectangle {
            visible: offDrop.containsDrag
            color: Colors.of(QsWindow.window).danger
            radius: Tokens.borderChrome
            width:  root.vertical ? Tokens.borderChrome * 2 : off.width - Tokens.spacingXl * 2
            height: root.vertical ? off.height - Tokens.spacingXl * 2 : Tokens.borderChrome * 2
            x: root.edge === "left"  ? Tokens.spacingXs
             : root.edge === "right" ? off.width - width - Tokens.spacingXs
             :                         Tokens.spacingXl
            y: root.vertical ? Tokens.spacingXl : off.height - height - Tokens.spacingXs
        }

        // ── The one line that says what's about to happen ─────────────────────
        // In a chip of the bar's material, so it reads over whatever is behind.
        Rectangle {
            id: caption
            readonly property int pad: Tokens.spacingSm
            // Measured unwrapped (TextMetrics), not off the Text's own implicitWidth:
            // a wrapping Text sized from itself can loop.
            readonly property real textMax: off.width - Tokens.spacingMd * 2 - caption.pad * 2
            width: Math.min(caption.textMax, captionMetrics.advanceWidth + Tokens.spacingXs) + caption.pad * 2
            height: captionText.implicitHeight + caption.pad * 2

            TextMetrics {
                id: captionMetrics
                font: captionText.font
                text: captionText.text
            }
            x: root.edge === "right" ? off.width - width - Tokens.spacingMd : Tokens.spacingMd
            y: root.vertical ? Tokens.spacingXl : Math.round((off.height - height) / 2)
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup), Config.barOpacity)
            border.width: Tokens.borderWidth
            border.color: SideDrag.drop?.kind === "off" ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).outline

            StyledText {
                id: captionText
                x: caption.pad
                y: caption.pad
                width: caption.width - caption.pad * 2
                wrapMode: Text.WordWrap
                variant: "caption"
                text: SideDrag.dragging
                    ? SideDrag.description
                    : "Drag a module along the sidebar to move it, onto another to group them, "
                      + "or out here to take it off"
                color: SideDrag.drop?.kind === "off" ? Colors.of(QsWindow.window).danger
                     : SideDrag.dragging             ? Colors.of(QsWindow.window).focus
                     :                                 Colors.of(QsWindow.window).fgDim
            }
        }
    }

    // The input mask: the sidebar's band and the room beside it, the whole span.
    Item {
        id: maskBox
        x: root.edge === "left"  ? 0
         : root.edge === "right" ? root.rail.screenW - root.bandHi - root.offDepth
         :                         0
        y: root.vertical ? root.rail.spanStart : root.rail.screenH - root.bandHi - root.offDepth
        width:  root.vertical ? root.bandHi + root.offDepth : root.rail.screenW
        height: root.vertical ? root.rail.spanEnd - root.rail.spanStart : root.bandHi + root.offDepth
    }
}
