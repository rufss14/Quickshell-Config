import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell.Widgets
import "../../config"
import "../../components"
import "../../services"

// ── CavaBG ────────────────────────────────────────────────────────────────────
// A full-width audio spectrum pinned to the bottom of the desktop, *behind* every
// application window. Transparent, click-through, on the wlr "background" layer.
// Toggled by left-clicking the visualizer pill (Config.cavaBg).
//
// It used to run its own `cava` process — a third one, on top of the two the
// status bar was running. All three analyzed the same audio to draw the same
// spectrum. It now shares the one Cava service, holding a reference only while
// it's actually visible.
//
// ── Ring, music only, caps, glow (2026-10-31, the user's picks) ────────────────
// "ring" is the spectrum as spokes round the screen's middle (the window then covers the
// screen, still click-through and under every window), the album cover inside it
// (Config.cavaBgRingCover). "Music only" (Config.cavaBgMusicOnly, on by default) listens to
// the playing player's own node — Cava.acquireSource, the bar visualiser's lookup — so a call
// or a notification doesn't move it. Caps (Config.cavaBgPeaks) hold over each bar or spoke
// and fall; glow (Config.cavaBgGlow) is a soft light round the shape in its colour.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    // ── Bottom, not Background — so a wallpaper renderer can't bury it ────────
    // linux-wallpaperengine anchors to the `bottom` layer by DEFAULT (its own
    // --layer flag says so), and a full-screen surface one layer up hid this
    // completely. Background→Bottom puts the spectrum above anything drawn on the
    // background layer, and `bottom` is still beneath every normal application
    // window, so this stays what it has always been: desktop decoration, behind
    // your apps.
    //
    // NOTE this only wins deterministically if the wallpaper renderer is on
    // `background`. Left on its default `bottom` it shares this layer and the two
    // stack by MAP ORDER — whoever started last covers the other. Run it with
    // `--layer background` to make the ordering a fact rather than a race.
    WlrLayershell.layer:         WlrLayer.Bottom
    WlrLayershell.namespace:     "quickshell-cava-bg"
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors.left:   true
    anchors.right:  true
    anchors.bottom: true
    // The ring sits in the middle of the screen, so it takes all of it.
    anchors.top:    root.ring

    // Room over the tallest bar for its cap and its glow.
    readonly property int capRoom:  Config.cavaBgPeaks ? 8 : 0
    readonly property int glowRoom: Config.cavaBgGlow ? 24 : 0
    implicitHeight: root.maxBarH + root.capRoom + root.glowRoom
    color: "transparent"

    // ── Hide behind a fullscreen window ───────────────────────────────────────
    // This lives on the `bottom` layer, under every window. A fullscreen window is
    // opaque over the whole output, so the spectrum can't be seen — and animating 64
    // bars at 60fps behind it is pure GPU waste. When one covers this monitor, fade
    // out and release the cava reference (the bar's own visualizer keeps the process
    // alive if it's running; this just stops the full-screen animation).
    // Binds to Fullscreen's monitor MAP, not to a function call. Binding to
    // `Fullscreen.activeOn(...)` made this a binding loop: the call walked
    // Hyprland.monitors and the lazy activeWorkspace objects behind it, which notify
    // mid-evaluation and re-entered this binding ("Binding loop detected for property
    // suppressed"). The combining now happens inside the service — see Fullscreen.qml.
    //
    // ── …and the monitor NAME is cached, for the same class of reason ──────────
    // That fixed the Fullscreen half but left a second re-entrant edge, and the loop
    // survived it. `screen` is a WINDOW property: Quickshell's getter reports the
    // BACKING window's screen, and re-emits screenChanged when that window is created
    // or destroyed. This window's own `visible` is derived from this very property
    // (suppressed → wanted → visible), so reading `root.screen` here closed the cycle:
    //
    //   suppressed → wanted → visible → map/unmap → screenChanged → suppressed
    //
    // Every other surface reads `root.screen?.name` in a binding safely (Bar, the
    // notification overlay) because nothing downstream of it drives their own `visible`.
    // Here it does, so the name is captured imperatively instead. It only genuinely
    // changes when the window moves output, and a same-value write doesn't notify —
    // so map/unmap no longer re-enters anything.
    property string monitorName: ""
    function _syncMonitor() { root.monitorName = root.screen?.name ?? "" }
    onScreenChanged: root._syncMonitor()

    // Gamemode joins the fullscreen check rather than flipping Config.cavaBg, so the
    // user's preference is never edited to express a temporary mode — turn gamemode
    // off and the visualizer comes back to exactly the state it was left in, even if
    // the shell reloaded in between. `Gamemode.hidesVisualizer` (not `.active`) folds
    // in the panel's per-effect toggle. Both inputs are plain notifying bools; neither
    // walks a lazy model, which is what keeps this binding out of the re-entrancy
    // trap described above.
    readonly property bool suppressed: Fullscreen.byMonitor[root.monitorName] === true
                                    || Gamemode.hidesVisualizer

    // Stay mapped a little past cavaBg/suppressed changing so the fade-out can
    // finish — same pattern the overlay panels use.
    readonly property bool wanted: Config.cavaBg && !root.suppressed && !PowerSaver.active
    visible: wanted || viz.opacity > 0.005

    // Never intercept input: clicks fall through to the desktop or the windows
    // below.
    mask: Region {}

    // ── Style ─────────────────────────────────────────────────────────────────
    // Which renderer draws the spectrum. Persisted (Config.cavaBgStyle), picked
    // from the Sound settings page next to the "Show on desktop" toggle.
    readonly property string vizStyle: Config.cavaBgStyle
    readonly property bool ring: root.vizStyle === "ring"

    // ── Geometry ──────────────────────────────────────────────────────────────
    // 180 was a hardcoded ceiling on how tall a full-level bar could reach — one
    // number in code, not something you could turn up. `Config.cavaBgIntensity`
    // (Sound settings, next to Style) replaces it: 180 is now just the "1.0×"
    // baseline, and every style's visible height (bars, wave, dots all draw into
    // the full window height) scales with it. The window has no top anchor, so
    // a higher intensity only grows it upward — the bottom edge never moves.
    readonly property int maxBarH: Math.round(180 * Config.cavaBgIntensity)
    // The "bars" style's own count: the service publishes 32 bars; mirroring
    // them gives 64, with bass meeting in the middle and treble at both edges —
    // the way cava itself presents a stereo field.
    readonly property int barCount: Cava.barCount * 2

    readonly property real slotW: root.width / root.barCount
    readonly property real barW:  Math.max(2, root.slotW * 0.6)

    // The ring: spokes from a circle a seventh of the screen's short side, as long as a bar is
    // tall at 0.6× (the intensity scales both), each as wide as half its share of the circle.
    readonly property int  ringR:    Math.round(Math.min(root.width, root.height) * 0.14)
    readonly property int  ringLen:  Math.round(root.maxBarH * 0.6)
    readonly property real ringBarW: Math.max(2, 2 * Math.PI * root.ringR / root.barCount * 0.5)
    readonly property int  ringBox:  2 * (root.ringR + root.ringLen + root.capRoom + root.glowRoom)

    // ── Caps ──────────────────────────────────────────────────────────────────
    // A cap jumps to its bar's top, holds there a moment, then falls — faster the higher it
    // was, so every cap takes about as long to land.
    readonly property int capH:    3
    readonly property int capGap:  2
    readonly property int capHold: Motion.emphasized
    readonly property int capFall: Motion.slow * 2

    // ── Cava lifecycle ────────────────────────────────────────────────────────
    // "Music only": the player's own node (MusicPulse.sourceNode — the first player playing
    // that isn't Discord). A player PipeWire names no stream for yet falls back to the shared
    // output while it plays; with nothing playing there is nothing to show. Off: the shared
    // output, everything you hear.
    readonly property string musicNode: MusicPulse.sourceNode
    readonly property bool _wantSource: Config.cavaBgMusicOnly && root.musicNode !== ""
    readonly property bool _wantShared: !Config.cavaBgMusicOnly || (root.musicNode === "" && MusicPulse.playing)
    property bool _held: false
    property bool _srcHeld: false
    function _sync() {
        const shared = root.visible && root._wantShared
        if (shared !== root._held) {
            if (shared) Cava.acquire()
            else        Cava.release()
            root._held = shared
        }
        // The bar visualiser's way: one shared source name, taken over while held.
        const src = root.visible && root._wantSource
        if (src && !root._srcHeld) { Cava.acquireSource(root.musicNode); root._srcHeld = true }
        else if (src)              Cava.sourceName = root.musicNode
        else if (root._srcHeld)    { Cava.releaseSource(); root._srcHeld = false }
    }
    onVisibleChanged: _sync()
    on_WantSourceChanged: _sync()
    on_WantSharedChanged: _sync()
    onMusicNodeChanged: _sync()
    // Seed the cached monitor name first: `visible` is downstream of it, so getting it
    // right before the first _sync() avoids acquiring cava for a frame we'd release again.
    Component.onCompleted: { root._syncMonitor(); root._sync() }
    Component.onDestruction: {
        if (root._held) Cava.release()
        if (root._srcHeld) Cava.releaseSource()
    }

    // Shaped, then mirrored — bass meeting in the middle, treble at both edges,
    // the classic cava look. Only the "bars" style wants this: it's what makes a
    // ROW of bars read as one stereo field. The expansive curve (exponent > 1)
    // keeps quiet passages low and lets transients — bass hits especially — shoot
    // up, rather than the whole spectrum reading as one flat uniform block.
    readonly property var bars: root._wantSource ? Cava.sourceShapedMirrored
                              : root._wantShared ? Cava.shapedMirrored : []

    // The same shaping, WITHOUT the mirror. Waveform and dots are each already a
    // self-contained shape (a ribbon, a grid) spanning the full width on their
    // own — mirroring them would just draw the same 32 bins twice, not add
    // information.
    readonly property var barsRaw: root._wantSource ? Cava.sourceShaped
                                 : root._wantShared ? Cava.shaped : []

    Item {
        id: viz
        // The ring draws in a square round the middle, not over the whole screen: the mask
        // and the glow are passes over this item, and a full-screen one would be most of
        // the cost for nothing.
        x: root.ring ? Math.round((root.width - root.ringBox) / 2) : 0
        y: root.ring ? Math.round((root.height - root.ringBox) / 2) : 0
        width:  root.ring ? root.ringBox : root.width
        height: root.ring ? root.ringBox : root.height
        opacity: root.wanted ? Config.cavaBgOpacity : 0.0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }

        // ── Its colours (Config.cavaBgBlend / cavaBgBlendDir, 2026-10-31) ──────
        // The renderer draws a STENCIL (only its alpha counts — Avatar's mask) and one fill is
        // shown through it, so every style takes every blend: 1–5 scheme colours (or the
        // cover's accent), laid across (left to right; round the ring, mirrored so the halves
        // match like the spectrum) or up (base to tips; the circle out).
        //
        // The gradients have nine FIXED stops, each the blend sampled at its position (`at`):
        // a stop list can't be a Repeater, and nine (eighths) land exactly on every colour of
        // a blend of 2, 3 or 5 — of 4, the middle two fall between stops, a few % off.
        readonly property var pal: Colors.of(QsWindow.window)
        function colourOf(id) { return id === "album" ? AlbumArt.accent : viz.pal.role(id, viz.pal.ramp3) }
        readonly property var fills: Config.cavaBlendClean(Config.cavaBgBlend).map(id => viz.colourOf(id))
        readonly property bool across: Config.cavaBgBlendDir !== "up"
        // The blend at t (0..1): the colours evenly spaced, mixed between neighbours.
        function at(t) {
            const c = viz.fills, n = c.length
            if (n < 2) return c[0]
            const x = Math.max(0, Math.min(1, t)) * (n - 1)
            const i = Math.min(Math.floor(x), n - 2)
            return viz.pal.mix(c[i], c[i + 1], x - i)
        }
        // A plain fill's stop at p: across runs left to right; up runs from the base (the
        // gradient's bottom, its 1) to the tips.
        function flat(p) { return viz.at(viz.across ? p : 1 - p) }
        // Round the ring, across: mirrored, the first colour at the top and the bottom.
        function round(p) { return viz.at(1 - Math.abs(2 * p - 1)) }

        // Only the picked style is ever instantiated — switching styles is rare
        // (a settings-page pick, not a per-frame thing), but there is no reason
        // to keep an idle renderer's worth of bindings alive behind the one
        // that's actually drawing.
        Loader {
            id: stencil
            anchors.fill: parent
            visible: false
            layer.enabled: true
            sourceComponent: root.vizStyle === "wave" ? waveComp
                            : root.vizStyle === "dots" ? dotsComp
                            : root.ring ? ringComp
                            : barsComp
        }

        Gradient {
            id: blend
            orientation: viz.across ? Gradient.Horizontal : Gradient.Vertical
            GradientStop { position: 0 / 8; color: viz.flat(0 / 8) }
            GradientStop { position: 1 / 8; color: viz.flat(1 / 8) }
            GradientStop { position: 2 / 8; color: viz.flat(2 / 8) }
            GradientStop { position: 3 / 8; color: viz.flat(3 / 8) }
            GradientStop { position: 4 / 8; color: viz.flat(4 / 8) }
            GradientStop { position: 5 / 8; color: viz.flat(5 / 8) }
            GradientStop { position: 6 / 8; color: viz.flat(6 / 8) }
            GradientStop { position: 7 / 8; color: viz.flat(7 / 8) }
            GradientStop { position: 8 / 8; color: viz.flat(8 / 8) }
        }
        // The glow: the coloured shape's own silhouette, blurred behind it, in the blend's
        // middle colour.
        Item {
            id: drawn
            anchors.fill: parent
            layer.enabled: Config.cavaBgGlow
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: viz.at(0.5)
                shadowBlur: 1.0
                shadowOpacity: 0.9
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 32
            }

            Item {
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: stencil
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root.ring
                    gradient: blend
                }
                // The ring's blends go round it (across) or from the circle out to the tips (up).
                Shape {
                    anchors.fill: parent
                    visible: root.ring
                    ShapePath {
                        strokeWidth: -1
                        fillGradient: viz.across ? conical : radial
                        PathRectangle { x: 0; y: 0; width: viz.width; height: viz.height }
                    }
                    RadialGradient {
                        id: radial
                        centerX: viz.width / 2; centerY: viz.height / 2
                        focalX:  viz.width / 2; focalY:  viz.height / 2
                        centerRadius: root.ringR + root.ringLen + root.capRoom
                        // The blend runs from the circle (`r0`) out to the tips.
                        readonly property real r0: root.ringR / Math.max(1, radial.centerRadius)
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 0 / 8; color: viz.at(0 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 1 / 8; color: viz.at(1 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 2 / 8; color: viz.at(2 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 3 / 8; color: viz.at(3 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 4 / 8; color: viz.at(4 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 5 / 8; color: viz.at(5 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 6 / 8; color: viz.at(6 / 8) }
                        GradientStop { position: radial.r0 + (1 - radial.r0) * 7 / 8; color: viz.at(7 / 8) }
                        GradientStop { position: 1.0; color: viz.at(1) }
                    }
                    ConicalGradient {
                        id: conical
                        centerX: viz.width / 2; centerY: viz.height / 2
                        angle: 90
                        GradientStop { position: 0 / 8; color: viz.round(0 / 8) }
                        GradientStop { position: 1 / 8; color: viz.round(1 / 8) }
                        GradientStop { position: 2 / 8; color: viz.round(2 / 8) }
                        GradientStop { position: 3 / 8; color: viz.round(3 / 8) }
                        GradientStop { position: 4 / 8; color: viz.round(4 / 8) }
                        GradientStop { position: 5 / 8; color: viz.round(5 / 8) }
                        GradientStop { position: 6 / 8; color: viz.round(6 / 8) }
                        GradientStop { position: 7 / 8; color: viz.round(7 / 8) }
                        GradientStop { position: 8 / 8; color: viz.round(8 / 8) }
                    }
                }
            }
        }

        // The cover inside the ring: a picture, not part of the stencil, so it keeps its own
        // colours. Only while something plays that has one.
        ClippingRectangle {
            id: cover
            readonly property string art: AlbumArt.hiRes(MusicPulse.player?.trackArtUrl ?? "")
            visible: root.ring && Config.cavaBgRingCover && art !== "" && MusicPulse.playing
            anchors.centerIn: parent
            width: Math.max(0, 2 * (root.ringR - root.capGap * 4))
            height: width
            radius: width / 2
            color: "transparent"
            Image {
                anchors.fill: parent
                source: cover.art
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                mipmap: true
            }
        }
    }

    // ── "bars" ────────────────────────────────────────────────────────────────
    // Hand-rolled rather than the shared Spectrum component on purpose: a flat
    // Colors.ramp3 fill and a fast-attack/slow-decay Behavior (35ms up, 220ms
    // down), tuned for a strip this wide, rather than Spectrum's gradient and
    // live-tracking curve. Ramp3 rather than a semantic role (focus/primary) —
    // this is decoration, not a control state, so it gets its own hue out of the
    // wallpaper's palette instead of borrowing one that means something
    // elsewhere in the shell. (Since 2026-10-31 that is only the default: the colour is
    // Config.cavaBgBlend's, shown through the bars as a stencil — see `viz`.)
    Component {
        id: barsComp
        Item {
            anchors.fill: parent
            Repeater {
                model: root.barCount

                Item {
                    id: slot
                    required property int index
                    x: slot.index * root.slotW + (root.slotW - root.barW) / 2
                    width: root.barW
                    height: parent.height

                    Rectangle {
                        id: bar
                        anchors.bottom: parent.bottom
                        width: parent.width
                        // A stencil: the colour is the fill shown through it (viz).
                        color: Colors.of(QsWindow.window).fg

                        readonly property real target: Math.max(2, Math.round(
                            (slot.index < root.bars.length ? root.bars[slot.index] : 0) * root.maxBarH))
                        height: target

                        // Fast attack, slow decay: a boom snaps the bar up almost
                        // instantly and then eases back down, instead of both
                        // directions moving at the same steady speed — which is what
                        // makes a spectrum read as responding to music rather than
                        // sloshing.
                        Behavior on height {
                            NumberAnimation {
                                duration: bar.target > bar.height ? 35 : 220
                                easing.type: Motion.respondCurve
                            }
                        }
                    }

                    PeakCap {
                        id: cap
                        armed: Config.cavaBgPeaks
                        level: bar.target
                        full: root.maxBarH
                        hold: root.capHold
                        fallMs: root.capFall
                    }
                    Rectangle {
                        visible: Config.cavaBgPeaks
                        width: parent.width
                        height: root.capH
                        radius: root.capH / 2
                        y: parent.height - cap.peak - root.capGap - root.capH
                        color: Colors.of(QsWindow.window).fg
                    }
                }
            }
        }
    }

    // ── "ring" ────────────────────────────────────────────────────────────────
    // The mirrored spectrum round a circle: treble at the top, the bass at the bottom, the
    // halves matching left and right. Each spoke is a point at the middle turned to its
    // angle, its bar standing out from the circle — the same attack and decay as "bars".
    Component {
        id: ringComp
        Item {
            anchors.fill: parent
            Repeater {
                model: root.barCount

                Item {
                    id: spoke
                    required property int index
                    x: parent.width / 2
                    y: parent.height / 2
                    rotation: spoke.index * 360 / root.barCount

                    readonly property real target: Math.max(2, Math.round(
                        (spoke.index < root.bars.length ? root.bars[spoke.index] : 0) * root.ringLen))
                    property real len: spoke.target
                    Behavior on len {
                        NumberAnimation {
                            duration: spoke.target > spoke.len ? 35 : 220
                            easing.type: Motion.respondCurve
                        }
                    }

                    Rectangle {
                        x: -root.ringBarW / 2
                        y: -root.ringR - spoke.len
                        width: root.ringBarW
                        height: spoke.len
                        radius: width / 2
                        color: Colors.of(QsWindow.window).fg     // a stencil (viz)
                    }

                    PeakCap {
                        id: ringCap
                        armed: Config.cavaBgPeaks
                        level: spoke.target
                        full: root.ringLen
                        hold: root.capHold
                        fallMs: root.capFall
                    }
                    Rectangle {
                        visible: Config.cavaBgPeaks
                        x: -root.ringBarW / 2
                        y: -root.ringR - ringCap.peak - root.capGap - root.capH
                        width: root.ringBarW
                        height: root.capH
                        radius: root.capH / 2
                        color: Colors.of(QsWindow.window).fg
                    }
                }
            }
        }
    }

    // ── "wave" ────────────────────────────────────────────────────────────────
    // The spectrum as a filled ribbon instead of discrete bars — reads as one
    // continuous line skimming the bottom of the screen.
    Component {
        id: waveComp
        WaveformSpectrum {
            levels: root.barsRaw
            barCount: Cava.barCount
            accent: Colors.of(QsWindow.window).fg       // a stencil (viz)
            drawing: true                               // hidden on purpose: the mask reads it
        }
    }

    // ── "dots"────────────────────────────────────────────────────────────────
    // A segmented LED-grid reading of the same spectrum, full width.
    Component {
        id: dotsComp
        DotMatrixSpectrum {
            levels: root.barsRaw
            barCount: Cava.barCount
            accent: Colors.of(QsWindow.window).fg       // a stencil (viz)
        }
    }

    // ── The wave (components/Infection.qml) ───────────────────────────────────
    // A wallpaper/colour change reaches the spectrum first — it sits along the
    // bottom edge, where the front starts. Anchored to the bottom and ignoring every
    // zone, so it spans the screen's full width from its bottom edge up. `screen` is
    // read here freely: nothing about the Infection feeds back into this window's
    // `visible` (see monitorName above for why that matters).
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
        windowY: (root.screen ? root.screen.height : root.height) - root.height
    }
}
