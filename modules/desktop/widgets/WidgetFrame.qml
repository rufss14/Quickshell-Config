pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── WidgetFrame ───────────────────────────────────────────────────────────────
// The tile every desktop widget sits in: the surface, the size, the drag, and the
// arrange-mode chrome. The widget types put their content inside and know nothing
// about placement.
//
// ── Why the frame owns the drag ───────────────────────────────────────────────
// The obvious alternative is one layer-shell window per widget, moved by rewriting its
// margins. That was rejected before it was written: every frame of a drag would be a
// surface reconfigure round-tripping through the compositor, which is the wrong thing
// to put on a 60fps path. All widgets on a screen share ONE window instead, and moving
// a widget is a plain Item `x`/`y` change inside it.
//
// ── The binding-vs-drag conflict, and why the code looks like this ────────────
// `x` cannot simply bind to `model.x`: dragging assigns `x`, which destroys the
// binding. So the drag writes freely to `x`/`y` and COMMITS on release, and the model
// is re-read whenever it changes identity. Commit-on-release also means one store
// write per drag rather than one per frame.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: frame

    // The instance record from DesktopWidgets: { id, type, screen, x, y, size, opts }.
    required property var model
    property bool arranging: false
    // Where the widget may be dragged to — the layer's own size, so a widget cannot be
    // dropped off the edge of the screen where there is no way to grab it again.
    property real boundsW: 0
    property real boundsH: 0

    signal committed(real nx, real ny)

    // ── Per-widget accent ─────────────────────────────────────────────────────
    // A ROLE NAME from the palette, never a hex string — the same rule the bar's
    // per-module accent follows, and for the same reason: a literal colour pinned here
    // would survive every future wallpaper, which is exactly what the palette exists to
    // prevent. "" means the widget's own default.
    readonly property color accent:
        Colors.of(QsWindow.window).role(frame.model.opts.accent ?? "", Colors.of(QsWindow.window).primary)

    // ── Per-widget material overrides ─────────────────────────────────────────
    // Same "inherit unless set" contract as `accent` above. `opts.opacity`/
    // `opts.roundness` are absent by default — NOT seeded to today's Config value at
    // creation, or every existing tile would freeze at whatever the global slider
    // happened to read the moment it was placed, and "inherit" would be a lie the
    // instant the global slider moved again. `??` treats both a missing key and an
    // explicit `undefined` (what `DesktopWidgets.setOpt(id, key, undefined)` writes
    // to clear an override back to inherit) the same way, before AND after a reload —
    // JSON.stringify drops an undefined-valued key, so a cleared override doesn't
    // come back as a stale `undefined` literal either.
    // Solid under high contrast, whatever the tile or the global slider says (both keep their value).
    readonly property real effOpacity:   Config.highContrast ? 1 : (frame.model.opts.opacity ?? Config.widgetOpacity)
    readonly property int  effRoundness: frame.model.opts.roundness ?? Config.widgetRoundness

    // Glass is TRI-state, not a bool — "on"/"off"/"inherit" ("" or absent). A bool
    // can only ever say on or off; it has no way to say "whatever the global toggle
    // currently is", which has to stay the default so an untouched tile keeps
    // following Settings → Widgets the way it always has.
    readonly property string glassOpt: frame.model.opts.glass ?? ""
    readonly property bool effGlass:
        frame.glassOpt === "on"  ? true
      : frame.glassOpt === "off" ? false
      :                            Config.widgetGlass


    // ── Bare tiles ────────────────────────────────────────────────────────────
    // A tile whose CONTENT is already a card — the media and lyrics tiles are the
    // overview's own surfaces, not bespoke tile layouts — otherwise sits inside two
    // frames: this one's fill, outline and glass, and then the card's own. What that
    // reads as is a coloured rectangle drawn around the card, which is not depth.
    //
    // `bare` hands the whole tile to the content: no fill, no outline, no glass, no
    // inset. Per-tile rather than a catalogue flag, because the same tile is worth
    // framing on a plain wallpaper and worth leaving bare on a busy one.
    //
    // The DRAG and hover affordances are deliberately NOT gated on it — an unframed
    // tile still has to be findable and movable in arrange mode, and that outline is
    // drawn separately below.
    readonly property bool bare: DesktopWidgets.isBare(frame.model)

    default property alias content: body.data

    readonly property real baseW: DesktopWidgets.widthOf(frame.model.size)
    readonly property real baseH: DesktopWidgets.heightOf(frame.model.size)

    implicitWidth:  frame.baseW + frame.grow * 2
    implicitHeight: frame.baseH + frame.grow * 2

    x: frame.model.x
    y: frame.model.y

    // Shifted back by the grow so the tile expands on ALL FOUR sides rather than down
    // and right only. Done as a transform and not by offsetting `x`/`y`: the drag
    // ASSIGNS x/y, which destroys any binding on them, so a tile that had been moved
    // once would stop honouring the offset and grow lopsidedly for the rest of the
    // session. A transform is independent of the position, however that position got
    // set. It composes with the drag's `scale` the same way.
    //
    // ── The entrance rides the same list ──────────────────────────────────────
    // `appear` (below) scales the tile up about its centre and lifts it into place. It is
    // a transform and not a change to `scale`: that property belongs to the press/drag
    // expression and its spring, and a second writer would chase it. Scale is listed
    // FIRST so it is taken about the tile's own centre, before the translate moves it.
    transform: [
        Scale {
            origin.x: frame.width / 2
            origin.y: frame.height / 2
            xScale: 1 - 0.1 * (1 - frame.appear)
            yScale: 1 - 0.1 * (1 - frame.appear)
        },
        // The hover tilt (below): about the tile's own centre, so it sits between the
        // scale (also about the centre) and the translate, which moves the result.
        Rotation {
            origin.x: frame.width / 2
            origin.y: frame.height / 2
            axis { x: 1; y: 0; z: 0 }
            angle: -frame.py * frame.tiltMax
        },
        Rotation {
            origin.x: frame.width / 2
            origin.y: frame.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: frame.px * frame.tiltMax
        },
        // Carried: the tile leans into the way it is being moved, like something held by
        // one corner, and swings back upright when it lands (`lean`, below).
        Rotation {
            origin.x: frame.width / 2
            origin.y: frame.height / 2
            angle: leanSpring.value
        },
        Translate { x: -frame.grow; y: -frame.grow + (1 - frame.appear) * Tokens.spacingLg }
    ]

    // ── The entrance: a staggered spring pop ──────────────────────────────────
    // -1 (the default) means "no entrance" — a settings preview mounts this same frame
    // and must simply be there. The layer passes its tile's place in the row, so the
    // tiles land one after another instead of as one block.
    //
    // It waits for the shell's own entrance (state/Intro) to reach the widgets, which
    // fade up over it: popping earlier would play out behind an invisible layer. Once
    // that has run, a tile added from Settings pops immediately, with no stagger — the
    // stagger is for a whole desktop arriving, not for one tile.
    //
    // `appear` overshoots 1 on the spring, which is the pop. The opacity below clamps it.
    // A physical spring (Motion.springSpatial, Material's expressive default) rather than a
    // bezier that imitates one: same landing, and a tile removed mid-pop turns round.
    property int  enterDelay: -1
    readonly property real appear: appearSpring.value
    property bool _popped: false
    SpringValue {
        id: appearSpring
        spec: Motion.springSpatial
        epsilon: 0.001
        target: frame._popped && !frame.gone ? 1 : 0
    }
    readonly property bool _entranceReady: frame.enterDelay >= 0 && Config.widgetEntrance
                                           && (!Intro.playing || Intro.widgets > 0)
    on_EntranceReadyChanged: if (frame._entranceReady) pop.start()
    Component.onCompleted: {
        if (frame.enterDelay < 0 || !Config.widgetEntrance) {
            frame._popped = true
            appearSpring.jump(frame.gone ? 0 : 1)
        }
        else if (frame._entranceReady) pop.start()
    }
    // `staggered` (a layout swap, WidgetLayer) brings back the entrance's one-after-another.
    property bool staggered: false
    Timer {
        id: pop
        interval: (Intro.playing || frame.staggered) ? Math.max(1, frame.enterDelay) : 1
        onTriggered: frame._popped = true
    }

    // ── Away: a tile with nothing to show ─────────────────────────────────────
    // Set by the layer from a widget's own `hidden` (the lyrics tile with no lyrics). The
    // tile runs its entrance backwards — shrinks, sinks, fades — and comes back the same
    // way. Arrange mode overrides it: a tile you can't see can't be moved. While gone it
    // takes no input (the layer also drops it from the mask) and stops drawing once the
    // spring has landed, so the widget's own work goes quiet with it.
    property bool away: false
    // Leaving with the rest of its layout (a wallpaper with a layout of its own came up).
    property bool leaving: false
    readonly property bool gone: (frame.away || frame.leaving) && !frame.arranging
    visible: !frame.gone || frame.appear > 0.002
    enabled: !frame.gone

    // ── The content lands a beat after the tile ───────────────────────────────
    // Same `appear`, read later and over a shorter span: the tile is up and settling
    // before its contents arrive, so the pop has two layers instead of one block. No
    // animation of its own — it is a window onto the spring above, which is why it
    // costs nothing once the tile has landed (appear 1 → reveal 1) and why a preview,
    // which sets appear 1 immediately, never fades.
    readonly property real reveal: Math.max(0, Math.min(1, (frame.appear - 0.35) / 0.5))

    // The Surface's own item opacity (see Surface.itemOpacity), times the entrance.
    itemOpacity: Tokens.surfaceOpacity * Math.min(1, frame.appear)

    // ── Material 3 Expressive: a tonal container ──────────────────────────────
    // `surfaceContainer` — the wallpaper's own grey, one step up from the bar — instead of
    // the card surface: Material's widget container. Neutral on purpose (see "Both are
    // NEUTRAL" below); the accent lives in each widget's hero element, on
    // `primaryContainer`, not in the tile. The elevation stays a card's (what the tile IS);
    // only the fill's tone is overridden, through the same fade Surface uses.
    elevation: Tokens.elevationCard
    color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, frame.fillOpacity)

    // ── The shape morphs ──────────────────────────────────────────────────────
    // Material 3 Expressive's shape morph: the corners are part of the motion, not a
    // constant. Pressed, the tile squares up (to 60% of its radius), the way an M3E button
    // does under a finger; hovered, it rounds out a touch, like the surface swelling under
    // the pointer; carried, it squares a little, as something lifted and held. Sprung on
    // the FAST spatial spring, so a quick tap is a visible squash-and-recover rather than a
    // fade. `radius` is set straight (not `cornerRadius`, Surface's int) so the morph is
    // continuous instead of stepping a pixel at a time.
    readonly property real shapeRadius: radiusSpring.value
    SpringValue {
        id: radiusSpring
        spec: Motion.springSpatialFast
        epsilon: 0.05
        target: frame.effRoundness * (frame.pressed && !drag.active ? 0.6
                                    : drag.active ? 0.8
                                    : (frame.hovered && !frame.arranging) ? 1.15 : 1)
    }
    radius: frame.shapeRadius

    // ── The macOS / iOS tile look ─────────────────────────────────────────────
    // These float on the wallpaper with no surrounding chrome, which is a different
    // problem from a panel sitting on other panels. Three things do the work:
    //
    //   • A translucent FILL (not item opacity — that would fade the border too, the
    //     bug Surface documents), so the wallpaper reads faintly through the tile the
    //     way an iOS home-screen widget does.
    //   • A TINT: the fill is graded from the widget's accent at the top down to
    //     nothing, so each tile carries its accent in the material rather than in one
    //     coloured glyph. See the gradient below.
    //   • A large corner radius, set above.
    //
    // The first version had a 1px specular line along the top edge instead of the
    // gradient. It was removed on sight: at this radius it reads as a small horizontal
    // bar sitting ON the tile rather than as a lit edge, which is the opposite of the
    // depth it was there to suggest. A graded fill does that job honestly.
    //
    // Deliberately NOT a real blur: this is a wlr-layershell BACKGROUND surface, so
    // there is nothing behind it to blur except the wallpaper, and Hyprland's blur
    // rules do not apply beneath the windows. A frosted look here would mean sampling
    // the wallpaper ourselves, which is a lot of machinery for a static image.
    fillOpacity: frame.bare ? 0 : frame.effOpacity
    // Not while the glass draws it: the shader strokes the same border itself, with light on
    // it (see "LIQUID GLASS"), and a second one underneath would show through a translucent body.
    borderWidth: (frame.bare || frame.refracting) ? 0 : Tokens.borderChrome
    // ── One border, everywhere ────────────────────────────────────────────────
    // The tiles used to carry an elevation-derived outline at rest and swap to the
    // accent on hover. Measured against the rest of the shell, the resting one was
    // (50,49,49) where the ring's stroke is (142,139,139) — nearly 3x apart, the same
    // mismatch the panels had before they were put on `frameLine`. So the tiles now
    // draw the SHELL's stroke, always: bar, frame, panels and desktop tiles are one
    // border again, and hovering no longer changes it.
    //
    // Dragging and arrange-mode hover still take the accent — that outline is how you
    // see which tile you are moving, and it is the only affordance arrange mode has.
    // Ordinary hover keeps the grow (below), which is the affordance it always had.
    borderColor:  frame.focused ? Colors.of(QsWindow.window).outlineFocus : Colors.of(QsWindow.window).frameLine
    focused:      drag.active || hover.hovered

    // Re-read position when the record changes identity — which is what every store
    // mutation produces, including a move committed by this very frame. Assigning
    // rather than binding is deliberate: see the header.
    onModelChanged: {
        // Not mid-snap either: the commit that ends a drag changes the model while the
        // tile is still springing home, and assigning x here would cut that short.
        if (drag.active || frame._homing) return
        frame.x = frame.model.x
        frame.y = frame.model.y
    }

    // ── Hover grow ────────────────────────────────────────────────────────────
    // The same gesture the bar's pills use, driven by the SAME preference
    // (`Config.barHoverGrow`) — turning grow-on-hover off should turn it off
    // everywhere, not leave the desktop doing something the bar no longer does.
    //
    // Grown by a few pixels on each edge rather than by `scale`, for the reason the bar
    // does it that way: scaling resamples the whole tile including its text, which goes
    // soft mid-animation. Growing the geometry re-lays-out crisply at every step. The
    // drag lift IS a scale, because there the point is the tile leaving the surface.
    // 6, where the bar's pills use 3. Not an inconsistency: the bar grows 3px on a 26px
    // pill and a tile is 168px, so the same number would be a proportionally smaller
    // gesture and read as a jitter rather than as a response.
    readonly property int growBy: 6
    // A spring, not the house deceleration: the tile overshoots its grown size by a hair
    // and settles, which is what makes a hover feel like the tile answering rather than a
    // property changing. A physical one now (Motion.springSpatial): a pointer that passes
    // straight over a tile turns the grow round in mid-swell instead of restarting it.
    readonly property real grow: growSpring.value
    SpringValue {
        id: growSpring
        spec: Motion.springSpatial
        epsilon: 0.02
        target: (frame.hovered && Config.barHoverGrow && !frame.arranging) ? frame.growBy : 0
    }

    // Hover is tracked here rather than on a child so it covers the whole tile,
    // including the padding around the content.
    property bool hovered: false
    HoverHandler {
        id: pointer
        enabled: !frame.arranging
        onHoveredChanged: frame.hovered = hovered
    }

    // ── Hover: the tile leans under the pointer ───────────────────────────────
    // The wash that used to lighten the whole tile on hover (a StateLayer glow) is gone —
    // it read as a screen turning on. Hover is now physical: the tile tilts a few degrees
    // so the edge nearest the pointer sinks, and its content shifts a little the other
    // way, which is what gives the surface depth. Plus the spring grow above.
    //
    // `px`/`py` are the pointer's place in the tile, -1..1 from its centre, and 0 when
    // the pointer is off it. They are what animates, so the tilt and the parallax cannot
    // disagree: while the pointer is over the tile they follow it on the stiffest effects
    // spring (critically damped, ~0.1 s: a hover that lags the hand feels broken); on
    // leaving, the fast spatial spring lets it swing back past upright and settle. Motion
    // off: the springs land at once, so it is simply upright.
    //
    // A tilt of this size is a few pixels of edge movement — enough to read as a surface,
    // small enough that text under it stays crisp. Sign: the sinking edge is the one
    // nearer the pointer (Qt's +z is towards the viewer, so +Y-rotation sinks the right
    // edge); if it ever looks like it leans AWAY, negate `tiltMax`.
    //
    // Switched and scaled from Settings › Desktop › Style (`Config.widgetParallax`,
    // `widgetParallaxStrength`). One factor drives BOTH the tilt and the content shift,
    // so the two cannot be tuned out of agreement.
    readonly property real parallax: (Motion.ambientOn && Config.widgetParallax)
                                     ? Config.widgetParallaxStrength : 0
    readonly property real tiltMax: 5 * frame.parallax
    readonly property real _px: (frame.hovered && frame.width > 0)
        ? Math.max(-1, Math.min(1, (pointer.point.position.x / frame.width  - 0.5) * 2)) : 0
    readonly property real _py: (frame.hovered && frame.height > 0)
        ? Math.max(-1, Math.min(1, (pointer.point.position.y / frame.height - 0.5) * 2)) : 0
    readonly property var _pointerSpec: frame.hovered ? Motion.springEffectsFast : Motion.springSpatialFast
    readonly property real px: pxSpring.value
    readonly property real py: pySpring.value
    SpringValue { id: pxSpring; target: frame._px; spec: frame._pointerSpec; epsilon: 0.002 }
    SpringValue { id: pySpring; target: frame._py; spec: frame._pointerSpec; epsilon: 0.002 }

    // ── Press ─────────────────────────────────────────────────────────────────
    // Lifted while dragged, pushed in while pressed. The two cannot both apply — a
    // press that becomes a drag hands off to the DragHandler — so one expression owns
    // `scale` and there is no arithmetic combining them.
    //
    // One fast spatial spring both ways (Material's ~0.14 s to peak): the press lands
    // almost at once, and a release swings past 1 and settles — the bubble coming back up.
    // A release that comes before the press finished turns round with its momentum.
    SpringValue {
        id: scaleSpring
        spec: Motion.springSpatialFast
        epsilon: 0.0005
        target: drag.active ? 1.04 : (frame.pressed ? 0.96 : 1)
    }
    scale: scaleSpring.value

    // ── Carried: the lean ─────────────────────────────────────────────────────
    // The drag's horizontal speed, as a few degrees of roll (capped at 4°), so a tile flung
    // across the desktop leans into it and one moved slowly stays upright. Sprung, so it
    // swings back level when the hand stops or lets go.
    property real _dragVx: 0
    SpringValue {
        id: leanSpring
        spec: Motion.springSpatial
        epsilon: 0.01
        target: drag.active ? Math.max(-4, Math.min(4, frame._dragVx / 600 * frame.parallax)) : 0
    }

    property bool pressed: false
    signal tapped()

    // A tile-wide tap, sitting UNDER the content. A widget's own controls (a transport
    // button, a clipboard row) take the press first and this never fires — which is the
    // behaviour you want: pressing the skip button should not push the whole tile in.
    // Measured rather than assumed; the probe asserts both halves.
    TapHandler {
        id: tap
        enabled: !frame.arranging
        // ReleaseWithinBounds, so dragging off the tile cancels rather than fires —
        // the standard button contract, and the one that lets a press become a drag.
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onPressedChanged: {
            frame.pressed = tap.pressed
            // The ripple starts where the pointer landed, not at the tile's middle.
            if (tap.pressed) feel.press(tap.point.position.x, tap.point.position.y)
            else             feel.release()
        }
        onTapped: frame.tapped()
    }

    // ══ LIQUID GLASS ══════════════════════════════════════════════════════════
    // Optional, behind `Config.widgetGlass`, and it comes in two implementations.
    //
    // ── The real one: a refracting lens ───────────────────────────────────────
    // `shaders/liquidglass.src.frag` samples the WALLPAPER at the tile's own screen position
    // and bends it, hardest at the rim. Refraction is the thing that separates Apple's
    // material from ordinary frosted glass, and no stack of opaque Rectangles can do it —
    // a pane with depth does not merely tint what is behind it, it compresses it into the
    // edge. Honest here specifically because these tiles are on the BACKGROUND layer, so
    // the wallpaper really is the only thing behind them.
    //
    // ── The fallback: layered light ───────────────────────────────────────────
    // Used when there is no wallpaper texture to sample: a settings preview, which has no
    // position on any screen, and a Wallpaper Engine video, where there is no still image
    // at all. A graded body, a rim and a sheen — frosted rather than refracting, but the
    // alternative for those cases is nothing.
    //
    // Both are NEUTRAL, never the accent. An accent wash was tried and rejected: it tints
    // the material instead of lighting it, so seventeen tiles came out looking like
    // seventeen colours of plastic rather than one material.

    // The shared wallpaper texture, handed down by WidgetLayer. One Image per screen, not
    // one per tile — seventeen copies of a 1920x1080 picture to draw seventeen tiles
    // would be absurd, which is also why the blur lives in the shader rather than in a
    // MultiEffect per tile.
    property Item backdrop: null

    readonly property bool refracting:
        frame.effGlass && frame.backdrop !== null && !frame.bare
        && frame.boundsW > 0 && frame.boundsH > 0

    // Wrapped in a Loader gated on `refracting`, so the sampler is NEVER bound to a
    // null texture. It is not merely tidiness: Qt logs
    //     ShaderEffect: Texture t1 is not assigned a valid texture provider
    // once per tile for as long as the binding holds null, and the wallpaper path takes
    // a second or two to resolve because the library comes from a `find`. Twenty of
    // those on every reload is noise that would bury a real warning. Not building the
    // effect until there is something to sample also means no shader pipeline is held
    // while the preference is off.
    Loader {
        anchors.fill: parent
        active: frame.refracting
        sourceComponent: Component {
        ShaderEffect {
            anchors.fill: parent
                // Only ask the GPU for this while it is on screen and switched on. A ShaderEffect
            // that is invisible still holds its pipeline, but it stops shading.
            fragmentShader: Qt.resolvedUrl("../../../shaders/liquidglass.frag.qsb")

            // The body's own translucency goes in as `bodyAlpha`, not as this item's opacity:
            // below 1 the Surface's fill shows through beneath the glass, which keeps one
            // slider (or one per-widget override) meaning one thing, and the shader keeps
            // the border out of it (an item opacity would fade the stroke too).
            property variant src: frame.backdrop
            property vector2d size: Qt.vector2d(width, height)
            // The tile's RENDERED top-left, so the sampled region follows the hover grow
            // instead of sliding under it by `grow` pixels.
            property vector2d tileOrigin: Qt.vector2d(frame.x - frame.grow, frame.y - frame.grow)
            property vector2d screenSize: Qt.vector2d(frame.boundsW, frame.boundsH)
            property real radius:     frame.radius
            property real thickness:  Math.max(8, frame.radius * 0.85)
            property real strength:   14
            property real bulge:      0.04
            property real blurRadius: 7
            property real dispersion: 0.18
            property real tintAmount: 0.10
            property real dim:        0.10
            property real bodyAlpha:  frame.effOpacity
            // The border, drawn by the shader. Its width and colour are the Surface's own
            // (Tokens.borderChrome, and the live `border.color`, so a drag or hover still
            // turns it to the focus outline and the change still fades). Light and shade are
            // the palette's: the foreground on a dark scheme, the base on a light one (the
            // lit edge must be lighter than the tile either way), and the palette's constant
            // black for the far side.
            property real rimWidth:    Tokens.borderChrome
            property real rimStrength: frame.focused ? 0.8 : 1.0
            // A vector, not a colour: a `color` property reaches the shader premultiplied, and
            // the stroke's alpha is wanted straight.
            property vector4d rimBase: Qt.vector4d(frame.border.color.r, frame.border.color.g,
                                                   frame.border.color.b, frame.border.color.a)
            property color rimLight:   Config.themeMode === "light" ? Colors.of(QsWindow.window).base
                                                                    : Colors.of(QsWindow.window).fg
            property color rimShade:   Colors.of(QsWindow.window).shadow
            // The tile's own container tone (see "a tonal container"), so glass and plain
            // tiles are the same colour and only the refraction tells them apart.
            property vector4d tint: Qt.vector4d(Colors.of(QsWindow.window).surfaceContainer.r,
                                                Colors.of(QsWindow.window).surfaceContainer.g,
                                                Colors.of(QsWindow.window).surfaceContainer.b,
                                                1.0)
        }

        }
    }

    // ── No lit-glass overlay, no cast shadow ──────────────────────────────────
    // The tiles used to wear GlassOverlay (a graded body, a top sheen and a rim) when
    // there was no wallpaper to refract, a specular rim in the refracting shader, and the
    // Surface's own elevation shadow. All three were taken off on request (2026-10-07): a
    // tile is a flat translucent fill with the shell's outline, the same material as the bar
    // and the panels. The overlay and the shadow stay off. With glass on, the BORDER is lit
    // again (asked for 2026-11-08): the shell's own stroke, drawn by the shader with light on
    // the upper-left and shade on the far side (see liquidglass.src.frag), not a separate rim on
    // top of it. With no wallpaper to sample, it is simply the fill and the plain border.
    castsShadow: false

    // ── Touch response ────────────────────────────────────────────────────────
    // The shell's own state layer, so a tile answers a press with a wave from the pointer,
    // clipped to its real corners. In the foreground colour, as every other state layer is:
    // the accent is for the one filled thing in a region.
    // Under the content, over the glass. A bare tile hands its whole surface to a card
    // that draws its own, so there is nothing here for the wave to sit on.
    StateLayer {
        id: feel
        anchors.fill: parent
        visible: !frame.bare
        radius: frame.radius
        // The press wave stays; the hover wash does not (see the tilt above). Material's
        // calibrated alphas (Tokens.state*): 10% for the press, 16% held while carried.
        hovered: false
        dragged: drag.active
    }

    // ── Content ───────────────────────────────────────────────────────────────
    Item {
        id: body
        anchors.fill: parent
        // Generous, and generous on purpose: iOS widget content is inset far more than
        // a dense settings panel would be. It is what stops a 168px tile reading as a
        // cramped box with text jammed against the corner.
        anchors.margins: frame.bare ? 0 : Tokens.spacingXl
        opacity: frame.reveal
        // The entrance lift, and the hover parallax: the content leans toward the pointer
        // as the surface tilts away from it.
        transform: Translate {
            x: frame.px * Tokens.spacingSm * frame.parallax
            y: (1 - frame.reveal) * Tokens.spacingSm + frame.py * Tokens.spacingSm * frame.parallax
        }
        // Input goes to the widget only when NOT arranging. Otherwise a click meant to
        // pick a tile up would land in a note's text field instead.
        enabled: !frame.arranging
    }

    // ── Arrange mode ──────────────────────────────────────────────────────────
    HoverHandler {
        id: hover
        enabled: frame.arranging
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    DragHandler {
        id: drag
        enabled: frame.arranging
        target: frame
        // Clamped to the layer, then snapped on release. Snapping DURING the drag makes
        // the tile stutter under the pointer; snapping at the end puts it on the grid
        // without the tile ever lagging the cursor.
        xAxis.minimum: 0
        yAxis.minimum: 0
        xAxis.maximum: Math.max(0, frame.boundsW - frame.width)
        yAxis.maximum: Math.max(0, frame.boundsH - frame.height)

        // The hand's speed, kept while it moves: by the time `active` drops, the centroid
        // has let go and reads 0. Feeds the lean and the snap's starting momentum.
        property vector2d _vel: Qt.vector2d(0, 0)
        onCentroidChanged: if (drag.active) {
            drag._vel = drag.centroid.velocity
            frame._dragVx = drag._vel.x
        }

        onActiveChanged: {
            if (drag.active) {
                drag._vel = Qt.vector2d(0, 0)
                frame._homing = false
                return
            }
            const g = Config.widgetGrid
            const nx = Math.max(0, Math.min(frame.boundsW - frame.width,
                                            Math.round(frame.x / g) * g))
            const ny = Math.max(0, Math.min(frame.boundsH - frame.height,
                                            Math.round(frame.y / g) * g))
            // Springs onto the grid instead of jumping: the tile is let go wherever the
            // hand left it and settles into its cell with the same overshoot the hover
            // has. The store is told straight away — the animation is only what is drawn.
            // It starts with the hand's own velocity (capped), so a tile flicked toward its
            // cell carries into it and one let go still just settles.
            const cap = v => Math.max(-2500, Math.min(2500, v))
            frame._homing = true
            homeX.jump(frame.x); homeX.kick(cap(drag._vel.x)); homeX.target = nx
            homeY.jump(frame.y); homeY.kick(cap(drag._vel.y)); homeY.target = ny
            // Dropped exactly on its cell and still (or animations off): nothing moves, so
            // `_homeMoving` never flips — end the snap here or onModelChanged stays shut.
            if (!frame._homeMoving) frame._homing = false
            frame.committed(nx, ny)
        }
    }

    // The snap home: two springs whose values are written to x/y while `_homing`. Not a
    // binding — the drag assigns x/y, see the header. When both have landed, x/y catch up
    // with whatever the model settled on (onModelChanged skipped it while they ran).
    property bool _homing: false
    SpringValue {
        id: homeX
        spec: Motion.springSpatial
        epsilon: 0.1
        onValueChanged: if (frame._homing) frame.x = homeX.value
    }
    SpringValue {
        id: homeY
        spec: Motion.springSpatial
        epsilon: 0.1
        onValueChanged: if (frame._homing) frame.y = homeY.value
    }
    readonly property bool _homeMoving: homeX.moving || homeY.moving
    on_HomeMovingChanged: if (!frame._homeMoving && frame._homing) {
        frame._homing = false
        frame.x = frame.model.x
        frame.y = frame.model.y
    }

    // A dashed edge while arranging. Drawn as a sibling rather than by switching the
    // Surface's own border, so the tile keeps its normal outline underneath and there
    // is no flicker when arrange mode ends.
    Rectangle {
        anchors.fill: parent
        visible: frame.arranging
        // `frame.radius`, not `parent.radius` — inside a custom type the parent is
        // typed as a plain Item, which has no radius, so the binding silently reads
        // undefined and the outline squares off.
        radius: frame.radius
        color: "transparent"
        border.width: Tokens.borderWidth * 2
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, drag.active ? 0.9 : 0.45)
    }

    // ── Chrome ────────────────────────────────────────────────────────────────
    // Only while arranging. A remove button sitting permanently on a desktop widget is
    // a permanent invitation to delete it by accident.
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.spacingSm
        spacing: Tokens.spacingXs
        visible: frame.arranging
        z: 2

        // Size cycle — only the sizes this type actually has a layout for.
        WidgetChip {
            readonly property var opts: (DesktopWidgets.info(frame.model.type) ?? {}).sizes ?? []
            visible: opts.length > 1
            label: frame.model.size === "small" ? "S"
                 : frame.model.size === "medium" ? "M" : "L"
            onActivated: {
                const i = opts.indexOf(frame.model.size)
                DesktopWidgets.setSize(frame.model.id, opts[(i + 1) % opts.length])
            }
        }

        WidgetChip {
            label: "󰅖"
            danger: true
            onActivated: DesktopWidgets.remove(frame.model.id)
        }
    }

    // A small pill button, local to arrange mode. Not PanelButton: that carries the
    // panel's padding and label machinery, and these sit on a 168px tile where a few
    // pixels of chrome is the whole budget.
    component WidgetChip: Rectangle {
        id: chip
        property string label: ""
        property bool danger: false
        signal activated()

        implicitWidth:  Math.max(22, chipText.implicitWidth + Tokens.spacingSm * 2)
        implicitHeight: 22
        radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
        color: chipMouse.containsMouse
               ? Colors.of(QsWindow.window).alpha(chip.danger ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary, 0.9)
               : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).base, 0.75)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(chip.danger ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary, 0.7)

        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            variant: "caption"
            font.bold: true
            color: chipMouse.containsMouse ? Colors.of(QsWindow.window).fgOnPrimary
                 : chip.danger ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }
    }
}
