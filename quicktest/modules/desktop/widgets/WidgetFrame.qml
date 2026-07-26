pragma ComponentBehavior: Bound
import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

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
        Colors.role(frame.model.opts.accent ?? "", Colors.primary)

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
    transform: Translate { x: -frame.grow; y: -frame.grow }

    elevation:    Tokens.elevationCard
    cornerRadius: Config.widgetRoundness

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
    fillOpacity: Config.widgetOpacity
    // The accent outline: pointing at a tile, dragging it, or hovering it in arrange
    // mode. `focused` is Surface's own mechanism for exactly this — it swaps the border
    // to `outlineFocus`, a change of HUE rather than of strength, which is what makes a
    // hovered tile read as picked out rather than merely brighter.
    focused:      frame.hovered || drag.active || hover.hovered

    // Re-read position when the record changes identity — which is what every store
    // mutation produces, including a move committed by this very frame. Assigning
    // rather than binding is deliberate: see the header.
    onModelChanged: {
        if (drag.active) return
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
    property real grow:
        (frame.hovered && Config.barHoverGrow && !frame.arranging) ? frame.growBy : 0
    Behavior on grow {
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // Hover is tracked here rather than on a child so it covers the whole tile,
    // including the padding around the content.
    property bool hovered: false
    HoverHandler {
        enabled: !frame.arranging
        onHoveredChanged: frame.hovered = hovered
    }

    // ── Press ─────────────────────────────────────────────────────────────────
    // Lifted while dragged, pushed in while pressed. The two cannot both apply — a
    // press that becomes a drag hands off to the DragHandler — so one expression owns
    // `scale` and there is no arithmetic combining them.
    Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
    scale: drag.active ? 1.04 : (frame.pressed ? 0.972 : 1)

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
        onPressedChanged: frame.pressed = tap.pressed
        onTapped: frame.tapped()
    }

    // ══ LIQUID GLASS ══════════════════════════════════════════════════════════
    // Optional, behind `Config.widgetGlass`, and it comes in two implementations.
    //
    // ── The real one: a refracting lens ───────────────────────────────────────
    // `shaders/liquidglass.frag` samples the WALLPAPER at the tile's own screen position
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
        Config.widgetGlass && frame.backdrop !== null
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

            // `Config.widgetOpacity` lands here rather than in the shader body: below 1 the
            // Surface's own fill shows through beneath the glass, which is a sensible blend
            // and keeps one slider meaning one thing.
            opacity: Config.widgetOpacity

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
            property real specular:   0.32
            property real tintAmount: 0.10
            property real dim:        0.10
            property vector4d tint: Qt.vector4d(Colors.surfaceFor(Tokens.elevationCard).r,
                                                Colors.surfaceFor(Tokens.elevationCard).g,
                                                Colors.surfaceFor(Tokens.elevationCard).b,
                                                1.0)
        }

        }
    }

    // The fallback, now the SHARED component rather than a private copy — the bar and
    // the screen frame need exactly this material, and two copies of a light recipe is
    // how they drift apart. Inset by one border width so it stops where the outline
    // begins: painting flush covers the inner half of that line and softens the one edge
    // that defines the tile.
    GlassOverlay {
        anchors.fill: parent
        anchors.margins: Tokens.borderWidth
        visible: Config.widgetGlass && !frame.refracting
        radius: Math.max(0, frame.radius - Tokens.borderWidth)
    }

    // ── Content ───────────────────────────────────────────────────────────────
    Item {
        id: body
        anchors.fill: parent
        // Generous, and generous on purpose: iOS widget content is inset far more than
        // a dense settings panel would be. It is what stops a 168px tile reading as a
        // cramped box with text jammed against the corner.
        anchors.margins: Tokens.spacingXl
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

        onActiveChanged: {
            if (drag.active) return
            const g = Config.widgetGrid
            const nx = Math.max(0, Math.min(frame.boundsW - frame.width,
                                            Math.round(frame.x / g) * g))
            const ny = Math.max(0, Math.min(frame.boundsH - frame.height,
                                            Math.round(frame.y / g) * g))
            frame.x = nx
            frame.y = ny
            frame.committed(nx, ny)
        }
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
        border.color: Colors.alpha(Colors.primary, drag.active ? 0.9 : 0.45)
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
        radius: Tokens.radiusFull
        color: chipMouse.containsMouse
               ? Colors.alpha(chip.danger ? Colors.danger : Colors.primary, 0.9)
               : Colors.alpha(Colors.base, 0.75)
        border.width: Tokens.borderWidth
        border.color: Colors.alpha(chip.danger ? Colors.danger : Colors.primary, 0.7)

        StyledText {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            variant: "caption"
            font.bold: true
            color: chipMouse.containsMouse ? Colors.fgOnPrimary
                 : chip.danger ? Colors.danger : Colors.fg
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
