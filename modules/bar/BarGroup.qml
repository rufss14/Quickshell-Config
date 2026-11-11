import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services/workspaces.js" as Wsp

// ── BarGroup ──────────────────────────────────────────────────────────────────
// A cluster of related bar widgets on the bar's one surface. It draws no pill of
// its own — those went with the pills shapes — only the inner pill(s) round its
// modules (Config.barInnerPill); its own spacing is what separates it from its
// neighbour.
//
// Reads Config directly rather than taking barShape as a property: a global
// preference, and threading it down through every level of the bar was ceremony.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── Appear / disappear ────────────────────────────────────────────────────
    // Whether this group belongs on the bar right now. A group whose modules can
    // all hide (the DND bell under "only while DND", the empty tray) doesn't pop
    // in and out — it COLLAPSES: width and opacity ease to zero and its
    // neighbours slide over to close the gap.
    //
    // `reveal` is the animated 0/1 factor; width and opacity multiply by it. This
    // is the same discipline as `pad` and `fuseDrop` and the deliberate absence of
    // a Behavior on implicitWidth — never animate a quantity that already tracks
    // content, animate a factor that moves between two fixed values and scale by
    // it. For a group that never hides, `shown` stays true so reveal is pinned at
    // 1 and implicitWidth tracks content 1:1, exactly as before — so the
    // width-animating widgets (Volume/Wifi/Visualizer) get no new target to chase.
    //
    // On the standard spatial spring (Material 3 Expressive): a group opening runs a hair
    // past its width and settles, its neighbours riding the same overshoot. A SpringValue
    // starts AT its target, so a group the layout opens with is there instantly, not
    // growing in on every reload (what a `_ready` flag gated when this was a Behavior).
    property bool shown: true
    SpringValue {
        id: revealSpring
        spec: Motion.springSpatial
        epsilon: 0.002
        target: root.shown ? 1 : 0
    }
    readonly property real reveal: Math.max(0, revealSpring.value)

    visible: reveal > 0.005
    // Only while mid-collapse — the one moment something is wider than the box. Past 1
    // (the overshoot) the box is the wider one, so nothing needs clipping.
    clip:    reveal < 0.999
    opacity: Math.min(1, reveal)

    default property alias content: contentRow.data

    // ── There is deliberately NO overlay layer here ───────────────────────────
    // Arrange mode wants a drop target in the SEAM beside each group ("put it here,
    // on its own"), and the obvious home for it is an overlay Item on this root. Two
    // attempts at that both failed, and the reason is worth recording so it is not
    // tried a third time:
    //
    //   · Declared plainly in this file's body it is appended to `contentRow.data`,
    //     because that is the default property above. With `anchors.fill: parent` the
    //     Row's size then depended on an item sized from the Row — a real polish loop
    //     ("Row called polish() inside updatePolish() of Row"), which took the bar's
    //     whole layout down.
    //   · Moved to a named property to dodge the default property, the object is
    //     created outside the visual tree, and `parent: root` does not take effect
    //     before its own `anchors` are evaluated — so every instance logged "Cannot
    //     anchor to an item that isn't a parent or sibling" and the loop persisted.
    //
    // The seams live in BarGroupRow's SLOTS instead, drawn outside the first and last
    // module of each group. A slot has an explicit implicitWidth/implicitHeight, so a
    // child with a negative x cannot feed back into the Row's size at all — which is
    // the property that makes it safe, and the one both attempts above lacked.

    // The Bar draws ONE surface behind everything — the per-group pills went with
    // the pills shapes (Config's barLayout) — so a group only lays out its modules.
    readonly property bool square: Config.barShape

    // The region supplies the outer padding, so each group needs only enough to
    // keep its neighbours off its widgets.
    readonly property int pad: Tokens.spacingSm

    // ── No Behavior on implicitWidth. This is load-bearing. ───────────────────
    // Several children (VolumePill, WifiPill, VisualizerPill) animate their OWN
    // widths. If this width were also animated, it would ease toward a target
    // that is itself easing — re-aiming every frame, chasing rather than
    // tracking. That chase IS the rubber-banding.
    //
    // The old SplitPill.qml carried a comment warning about exactly this, and I
    // reintroduced the bug anyway. Width tracks content 1:1; the content supplies
    // the motion.
    // Ceil: children may be text-derived and therefore fractional. A group landing
    // off-pixel smears its own 1px border AND every pill inside it.
    //
    // Scaled by `reveal` so a hiding group collapses its width to zero and its
    // neighbours slide in. reveal is 1 for anything that never hides, so this is a
    // no-op there — no Behavior, nothing to chase (see the reveal note above).
    implicitWidth: (Math.ceil(contentRow.implicitWidth) + pad * 2) * root.reveal

    // The PILL's height, not the control's — controls inside are pillHeight (24)
    // and centre within this. Safe to animate: it's a pure function of barShape,
    // a discrete toggle.
    // Derived from the user's bar thickness/inset rather than the Tokens constants —
    // the pill is the bar's height less the margin it floats in.
    implicitHeight: Config.barSurfaceHeight
    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }


    // ── Clearing the band, welded or not ──────────────────────────────────────
    // Whenever a band is showing (`screenFrame`/`barFrame`) and this group's
    // natural top would sit inside its depth, the pill's top has to move down to
    // the band's underside — otherwise it simply overlaps the band instead of
    // sitting below it (the "clips through the frame" bug). That clearance is
    // needed regardless of `frameMerge`: a merge-OFF pill still can't overlap the
    // band, it just clears it with a plain square-cornered top instead of a weld.
    // FrameFusion (declared after the pill) draws the weld visuals ONLY when
    // `fused` is true; the position math here is identical either way.
    //
    // `groupOrigin`, not `Config.barInset` directly: in square mode the group
    // itself sits flush at the screen edge (Bar's `inset` is 0 there), so barInset
    // plays no part in its actual position. Subtracting it anyway used to leave a
    // gap between where the math thought the pill's top was and where it really
    // was.
    readonly property bool fused: Config.frameFused
    readonly property bool bandVisible: Config.frameBandVisible
    readonly property int groupOrigin: root.square ? 0 : Config.barInset
    // Not readonly: the Behavior drives it through intermediate values.
    property real fuseDrop: root.bandVisible ? Math.max(0, Config.frameDepth - root.groupOrigin) : 0
    Behavior on fuseDrop { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }


    // ── The FrameFusion that used to live here is gone ────────────────────────
    // It welded a floating pill into a thin band ABOVE it — erase the seam, flare
    // each shoulder — which the anchored redesign retired: those modes have no
    // band, and the floating ones sit cleanly below theirs. It had been left
    // `active: false` with a note explaining why, rather than deleted.
    //
    // `active: false` does not mean absent. The instance still CONSTRUCTED: an
    // eraser Rectangle, two SeamFillets each holding a Shape with two ShapePaths,
    // and two EdgeJoins — about eleven objects with live bindings on Config, per
    // group, that could never draw. `visible` keeps them off the screen, not out of
    // the scene.
    //
    // The geometry itself is not lost: components/FrameFusion.qml still has all of
    // it, and Bar.qml instantiates that file once, for the edge join. If a
    // band-plus-pill look ever comes back, this is two lines to put back and the
    // hard part was never here.

    // ── No divider ─────────────────────────────────────────────────────────
    // Merged groups used to mark their leading edge with a 2px line where a
    // split-mode pill boundary would have been. Removed on request: with the
    // per-module inner pills gone too (see IconButton.container), a group's
    // own spacing is what separates it from its neighbour now — a line on top
    // of that read as one more seam in a bar that is trying to look seamless.

    // ── The shared inner pill(s) ───────────────────────────────────────────
    // One lighter-fill, borderless surface per CONTIGUOUS run of widgets that
    // want one — the "inner pill" nucleus draws, shared across neighbours in a
    // group rather than drawn per-button (see IconButton.container: individual
    // widgets draw nothing of their own). A module can opt out per-module
    // (Config.moduleInnerPill, set from the module inspector); an opted-out
    // module simply breaks the run and sits directly on the OUTER pill instead.
    //
    // `contentRow.children` are the Repeater's per-module `slot` Items
    // (BarGroupRow.qml) PLUS the Repeater instance itself — Repeater is an
    // Item, and one lands in this list purely because it was declared inside
    // the same default-property content. It carries no `modelData`, so it was
    // silently treated as a real module (`?? ""`) — one phantom slot ahead of
    // every real one, shifting every run's start/end by one. Filtered here
    // instead, and the run objects below carry the actual Item references
    // rather than indices, so nothing has to re-agree on numbering later.
    readonly property var innerPillRuns: {
        const kids = []
        for (const c of contentRow.children)
            if (typeof c.modelData === "string") kids.push(c)
        // A hero (Config.moduleHero) breaks the run and gets a chip of its own kind.
        const hero  = kids.map(k => Config.moduleHero(k.modelData))
        const inner = kids.map((k, i) => !hero[i] && Config.moduleInnerPill(k.modelData))
        const tag = (flags, isHero) => Wsp.runs(flags).map(r => ({
            firstKid: kids[r.start],
            lastKid:  kids[r.start + r.length - 1],
            hero:     isHero
        }))
        return tag(inner, false).concat(tag(hero, true))
    }

    // Passive: it takes no hover from the buttons inside (a handler ABOVE them would).
    HoverHandler { id: groupHover }

    // The group's ONE hover plate, sliding between its buttons (HoverTrack). The buttons
    // find it here (`hoverTrack`); it's drawn over the inner pills (declared after them,
    // below) and under the modules.
    readonly property var hoverTrack: track

    Repeater {
        model: root.innerPillRuns

        Surface {
            required property var modelData
            readonly property var firstKid: modelData.firstKid
            readonly property var lastKid:  modelData.lastKid
            // A module dragged out of this group can shrink `contentRow`'s
            // children a moment either side of `innerPillRuns` catching up —
            // same staleness LyricGlyphs guards against for positionToRectangle.
            readonly property bool ready: firstKid !== undefined && lastKid !== undefined
            visible: ready

            // Sized to the run's own children plus a small margin, so a ring of
            // the OUTER pill's normal-bg colour still shows around it. y/height
            // come from contentRow itself, not the kids — that's the single
            // place the fuse-drop-aware centring above already lives.
            //
            // `firstKid.x` alone would start at the LEFT edge of its reserved gap
            // (BarGroupRow.qml's `gapBefore`), not at the widget it actually draws —
            // that empty sliver belongs to the previous module, not to this pill.
            x:      ready ? contentRow.x + firstKid.x + firstKid.gapBefore - Tokens.spacingSm : 0
            y:      contentRow.y - Tokens.spacingXs
            width:  ready ? (lastKid.x + lastKid.width) - firstKid.x + Tokens.spacingSm * 2 : 0
            height: contentRow.height + Tokens.spacingXs * 2

            elevation:    Tokens.elevationNested
            squareMode:   root.square
            cornerRadius: Config.barRoundness
            borderWidth:  0
            castsShadow:  false
            fillOpacity:  Tokens.barOpacity
            // The hero's chip is the accent's container; the module puts its text on it in
            // fgOnPrimaryContainer (BarGroupRow tells it).
            color: Colors.of(QsWindow.window).fade(modelData.hero
                       ? Colors.of(QsWindow.window).primaryContainer
                       : Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested), Tokens.barOpacity)
            Behavior on color { ColorAnimation { duration: Motion.respond } }

            // The settings cards' light, quieter and tighter: a soft glow under the pointer
            // across the run, catching the edge nearest it. Reads the GROUP's HoverHandler
            // (above), which is an ancestor of the buttons, so it stays lit while one is
            // hovered; draws nothing until hovered.
            PointerGlow {
                hover:  groupHover
                origin: Qt.point(parent.x, parent.y)
                radius: parent.radius
                reach:  Tokens.spacingXxl * 5
                fillStrength: 0.04
                edgeStrength: 0.3
            }

            // The music's rim (Config.barMusicReact), the same as the sidebar's pills.
            MusicRim {
                anchors.fill: parent
                radius: parent.radius
            }
        }
    }

    HoverTrack {
        id: track
        alongY: false
    }

    Row {
        id: contentRow
        // A module resizing reflows its neighbours under a resting pointer: the plate follows.
        onWidthChanged: track.refresh()
        // Rounded rather than anchors.centerIn: centring gives a HALF-PIXEL x when
        // (parent.width - row.width) is odd, which puts every inset pill inside on a
        // half pixel and smears their 1px borders into a soft 2px. Snap to whole
        // pixels and the hairlines stay hairlines.
        x: Math.round((parent.width - width) / 2)
        // ── Content follows the fuse drop only when NOT fused ─────────────────
        // Fused, the band above the drop and the pill below it are the SAME
        // material — FrameFusion erases the seam — so centring across the
        // group's full height is centring in one continuous surface. That's the
        // case this used to special-case for (frameThickness 24 spilling out of
        // a 12px pill), and it still holds: `fused` skips the drop entirely.
        //
        // NOT fused, there is no erase — the band is a separate surface and the
        // pill really is only `parent.height - fuseDrop` tall. Centring past
        // that (the old unconditional behaviour) put the icons too high for a
        // box that had actually gotten shorter: they read as clipped by the
        // band above, and off-centre in the pill below.
        y: root.fused
            ? Math.round((parent.height - height) / 2)
            : Math.round((root.fuseDrop + parent.height - height) / 2)
        // No spacing here any more — each slot reserves its own gap before it
        // (BarGroupRow.qml's `gapBefore`), which is what lets that gap vary
        // instead of being one flat number shared by every pair.
        spacing: 0
    }
}
