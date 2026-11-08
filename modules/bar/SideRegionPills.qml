pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── SideRegionPills ───────────────────────────────────────────────────────────
// The sidebar's inner pills: ONE per region (start, centre, end), from its first group to
// its last, with a hairline divider where one group ends and the next begins (2026-10-31,
// the user's pick for a "cleaner and less busy" sidebar: six pills read as six things; three
// read as the edge's three places). Each group used to draw its own pill (SideGroupHost,
// DockHost); they draw none now and stand on these. Still the top bar's inner pill, exactly
// (SidePill "inner" — 2026-10-17's call), only fewer of them.
//
// ── Riding what the groups ride ───────────────────────────────────────────────
// A region's box is the rail's: from `rail.placed` (the groups' pos/len — the same numbers
// the hosts stand at), `rail.cross` out of the frame (the sidebar's reveal, which the small
// groups ride and the dock's matches), and the start region collapses with the near corner
// (SideRail.startCollapsed). The blob's spring deformation applies as it does to the hosts'
// bands. Nothing here is a lobe: the sidebar's bar is the one surface (SideBarHost).
//
// ── The region's hover plate ──────────────────────────────────────────────────
// Each region holds a HoverTrack, so hover slides between the buttons of every group in that
// pill — the dock's apps and the clips beside them included. The hosts hand it out as their
// `hoverTrack` (SideRail.regionTracks); it re-reads its button when the rail re-lays.
//
// ── Islands, a hero, the music (2026-10-31) ───────────────────────────────────
// The user then found the sidebar "boring compared to the top" and picked the top bar's own
// devices back:
//   · Config.sidebarIslands (default on): a pill PER GROUP, the top bar's stray islands — the
//     same delegate, keyed "region:ids" (SideRail.smallGroups' key, so a group that only
//     moves keeps its pill) instead of by region, its track registered under that key (hosts
//     ask for their group's first, then their region's). The keys are a joined string, so the
//     Repeater rebuilds only when the set of groups changes, never on a re-lay. Off: one pill
//     per region with dividers, as above.
//   · Config.sidebarHero: that module on a primaryContainer chip inside its pill, concentric
//     like a hover plate (the bar's hero); the module itself turns its ink to the container's.
//   · Config.barMusicReact: while music plays, each pill's rim glows with it (MusicRim — the
//     same on the top bar's chips). It first scaled the pills on the beat with a wash over
//     them, which the user found messy.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property SideRail rail
    // The sidebar bar's spring deformation; identity while the plugin is absent.
    property matrix4x4 deformMatrix

    readonly property string edge: root.rail.edge
    readonly property bool vertical: root.rail.vertical
    readonly property int depth: root.rail.depth
    readonly property real edgePos: root.rail.edgePos(root.width, root.height)

    readonly property string _keys: Config.sidebarIslands
        ? root.rail.placed.groups.map(g => g.region + ":" + g.ids.join(",")).join("|")
        : "start|centre|end"

    Repeater {
        model: root._keys === "" ? [] : root._keys.split("|")

        Item {
            id: region
            required property string modelData

            anchors.fill: parent

            readonly property bool island: region.modelData.indexOf(":") >= 0
            readonly property string regionName: region.modelData.split(":")[0]
            // In order along the edge (dock.js sideRail lays each region in order).
            readonly property var groups: root.rail.placed.groups.filter(g => region.island
                ? g.region + ":" + g.ids.join(",") === region.modelData : g.region === region.modelData)
            readonly property real lo: region.groups.length > 0 ? region.groups[0].pos : 0
            readonly property real hi: region.groups.length > 0
                ? region.groups[region.groups.length - 1].pos + region.groups[region.groups.length - 1].len : 0
            readonly property real len: Math.max(0, region.hi - region.lo)
            readonly property bool collapsed: region.regionName === "start" && root.rail.startCollapsed
            readonly property real cross: region.collapsed ? 0 : root.rail.cross

            // The box as it slides out of the frame (SideGroupHost's reveal).
            Item {
                id: reveal

                x: root.edge === "left"  ? root.edgePos
                 : root.edge === "right" ? root.edgePos - region.cross
                 :                         region.lo
                y: root.vertical ? region.lo : root.edgePos - region.cross
                width:  root.vertical ? region.cross : region.len
                height: root.vertical ? region.len : region.cross
                // Behind the frame's strip until it's out (DockHost's reveal says why).
                clip: root.rail.strip > 0
                visible: region.len > 0 && region.cross > 0.5

                Item {
                    id: band

                    width:  root.vertical ? root.depth : region.len
                    height: root.vertical ? region.len : root.depth
                    x: root.edge === "left" ? reveal.width - root.depth : 0
                    y: 0

                    transform: Matrix4x4 { matrix: root.deformMatrix }

                    SidePill {
                        id: pill
                        anchors.centerIn: parent
                        visible: Config.barInnerPill
                        role: "inner"
                        width:  root.vertical ? Config.sidebarPillCross : region.len
                        height: root.vertical ? region.len : Config.sidebarPillCross
                    }

                    // The music's rim (Config.barMusicReact), on the pill's edge.
                    MusicRim {
                        anchors.fill: pill
                        visible: pill.visible
                        radius: Tokens.corner(Config.barShape, Math.min(Config.barRoundness, Math.min(width, height) / 2))
                    }

                    // The hero's chip, under its cells, concentric with the pill (a hover plate's
                    // radius). Only in the pill that holds it.
                    Rectangle {
                        readonly property string heroId: Config.sidebarHero
                        readonly property real at: heroId !== "" && root.rail.at[heroId] !== undefined ? root.rail.at[heroId] - region.lo : -1
                        readonly property real len: heroId !== "" ? (root.rail.allLengths[heroId] ?? 0) : 0
                        readonly property bool here: at >= 0 && len > 0 && at + len <= region.len + 0.5
                        visible: here && Config.sidebarRegionOf(heroId) === region.regionName
                        readonly property real across: Config.sidebarCell
                        width:  root.vertical ? across : len
                        height: root.vertical ? len : across
                        x: root.vertical ? Math.round((band.width - width) / 2) : at
                        y: root.vertical ? at : Math.round((band.height - height) / 2)
                        radius: Tokens.corner(Config.barShape,
                                              Math.min(Math.min(width, height) / 2, Math.max(0, Config.barRoundness - Tokens.spacingXs)))
                        color: Colors.of(QsWindow.window).primaryContainer
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    // Between two groups, centred in the gap the rail leaves (SideRail.groupGap):
                    // an inset hairline across the pill, Material's divider.
                    Repeater {
                        model: Math.max(0, region.groups.length - 1)

                        Divider {
                            required property int index
                            readonly property var before: region.groups[index]
                            readonly property var after:  region.groups[index + 1]
                            readonly property real at: before && after
                                ? (before.pos + before.len + after.pos) / 2 - region.lo : 0
                            readonly property real span: Config.sidebarPillCross - Tokens.spacingMd * 2

                            orientation: root.vertical ? Qt.Horizontal : Qt.Vertical
                            width:  root.vertical ? span : Tokens.borderWidth
                            height: root.vertical ? Tokens.borderWidth : span
                            x: root.vertical ? Math.round((band.width - width) / 2) : Math.round(at - width / 2)
                            y: root.vertical ? Math.round(at - height / 2) : Math.round((band.height - height) / 2)
                        }
                    }

                    HoverTrack {
                        id: track
                        alongY: root.vertical
                    }
                }
            }

            // Handed out to the hosts standing in this region (their `hoverTrack`).
            function _register(on) {
                if (!root.rail) return
                const m = Object.assign({}, root.rail.regionTracks)
                if (on) m[region.modelData] = track
                else if (m[region.modelData] === track) delete m[region.modelData]
                root.rail.regionTracks = m
            }
            Component.onCompleted: region._register(true)
            Component.onDestruction: region._register(false)

            // The rail re-laid (a group grew, the dock gained an app, a panel stepped it):
            // the plate follows its button.
            Connections {
                target: root.rail
                function onPlacedChanged() { track.refresh() }
            }
        }
    }
}
