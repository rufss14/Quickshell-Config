import QtQuick
import Quickshell
import Quicktest.Blobs
import "../../config"
import "../../services"
import "../../state"

// ── BlobBarLayer ──────────────────────────────────────────────────────────────
// One BlobGroup for the whole bar window: the BAR ITSELF is a shape in it, and so
// is every panel hanging off it. The smooth-min union between them IS the morph —
// a real neck that grows, thins and pinches as a panel travels.
//
// ── Why the bar has to be in the group ────────────────────────────────────────
// This is the thing the first two attempts got wrong, and it is worth stating
// plainly: a metaball union needs TWO shapes. The earlier BlobPanelBackground put
// a 26px decorative "notch" in the group and fused the panel with that — so the
// panel was melting into a pebble, not into the bar. At smoothing 20 a 26px blob
// unioned with a 535px card produces a fat sagging drip hanging off a dot, which
// is exactly the "slimy" it looked like. caelestia-dots/shell does not do this:
// its ContentWindow.qml puts a BlobInvertedRect for the whole screen border in the
// group and every panel is a BlobRect fused into THAT.
//
// ── It must paint BEHIND the bar's own surface ────────────────────────────────
// The bar rect below is drawn in the bar's own fill colour and spans the whole
// strip, so it would cover every pill if it painted on top. Caelestia has no
// conflict here because its blob group IS the bar's background — its bar draws no
// surface of its own. This shell's bar does, so this layer is mounted early and
// low (see Bar.qml): the bar's real Surface covers the bar rect exactly, and the
// only part of the group that ever shows is what hangs BELOW the strip — the neck
// and the panel. The two fills are the same recipe, measured 1/255 apart.
//
// ── deformScale is 33× smaller than the C++ default, on purpose ───────────────
// BlobRect deforms from its own scene-space VELOCITY: stretch along the direction
// of travel, compress across it, on an underdamped spring. `deformScale` converts
// px/s into stretch. The C++ default is 0.0005, which caelestia NEVER uses — every
// call site overrides it with `(deformAmount * Config.appearance.deformScale) /
// 10000`, and with their defaults (deformAmount 0.15, deformScale 1) that is
// 1.5e-5. Using the raw C++ default meant ~33× the deformation at every speed, so
// a 700px/s slide hit the 0.35 stretch CAP instead of stretching about 1%. That
// was most of the slime.
//
// The one file besides MorphProbe allowed to `import Quicktest.Blobs`.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── The ring's geometry, in this Item's coordinates ───────────────────────
    // (0,0) here is the screen's top-left: the bar's window is anchored top/left/
    // right at y=0, and it is TALLER than the screen (barExtent + apron + a full
    // panel ceiling), so the whole screen is addressable from inside it.
    property real screenW: 0
    property real screenH: 0

    // The bar is the ring's TOP border — not a separate shape. This is exactly how
    // caelestia has it: their bar is vertical, so theirs is `borderLeft:
    // bar.implicitWidth` on the same BlobInvertedRect that carries the screen
    // border. One shape, one outline, nothing to fuse between bar and frame
    // because they were never two things.
    property real barHeight: 0

    // Frame strip depth, stepped in by one border width so ScreenFrame's own stroke
    // is not sat on. The ring renders no material anyway (see the note on `ring`),
    // but the inset also puts the SDF boundary on the stroke rather than outside it,
    // which is where a panel should fillet to.
    property real frameInset: 0
    property real frameRadius: 0

    property color fill: Colors.of(QsWindow.window).frameFill

    // ── The outline of the merged silhouette ──────────────────────────────────
    // One continuous stroke around bar, frame, fillet and panel, computed by the
    // shader from the same union that produces the fill. This is what a Qt-drawn
    // border could never do: a Rectangle's stroke is a closed rectangle, so a panel
    // that draws its own can only ever butt against the ring's, never continue it.
    //
    // This does NOT replace the frame's own stroke. The ring participates in the SDF
    // but paints no material (verified by forcing the shader to output pure red: the
    // strips stayed frame-coloured), so the blob's outline only appears where a shape
    // actually renders — around an open panel and the fillet welding it to the bar.
    // That is exactly the edge that had no border, and the frame keeps drawing its
    // own as it always did.
    property color borderColor: Colors.of(QsWindow.window).frameLine
    property real  borderWidth: 0

    // caelestia's border.smoothing default. Kept AT their value rather than tuned
    // down: the earlier "reduce the smoothing" pass was treating the symptom of
    // fusing with a pebble. Against a shape the size of the bar, 20 is a fillet.
    property real smoothing: Morph.smoothing

    // See the header. deformAmount 0.15 is their PanelBg default.
    readonly property real deformScale: 0.15 / 10000

    // ── Panel slots ───────────────────────────────────────────────────────────
    // Explicit reals rather than an Item reference: the cards live several parents
    // down and this needs their geometry in WINDOW coordinates, which the caller
    // already knows. Plain property reads make real bindings; mapToItem() in a
    // binding would not re-evaluate when an ancestor moves.
    property real leftX: 0
    property real leftY: 0
    property real leftW: 0
    property real leftH: 0

    property real rightX: 0
    property real rightY: 0
    property real rightW: 0
    property real rightH: 0

    property real centerX: 0
    property real centerY: 0
    property real centerW: 0
    property real centerH: 0

    // The docked settings panel (Config.settingsPanel). Welds into the bottom
    // strip — and, at side "left"/"right", a side strip too, since the ring is one
    // continuous shape. Zero W/H (closed) parks it off in BlobRect's own
    // "nothing to draw" corner, same as the centre slot and the toast pool.
    property real settingsX: 0
    property real settingsY: 0
    property real settingsW: 0
    property real settingsH: 0

    // The sidebar's bar (SideBarHost): one lobe along the dock's edge, strip to
    // strip, behind everything on it. Zero W/H while it's off or sunk.
    property real sidebarX: 0
    property real sidebarY: 0
    property real sidebarW: 0
    property real sidebarH: 0


    // A sidebar button's panel (SidePanelDock: the stats, the clips), melted out of
    // the sidebar's face beside its button. Zero W/H while it's shut.
    property real sidePanelX: 0
    property real sidePanelY: 0
    property real sidePanelW: 0
    property real sidePanelH: 0

    // The OSD's sliders (OsdDock), melted out of the frame's right edge. Zero W/H while
    // it is shut.
    property real osdX: 0
    property real osdY: 0
    property real osdW: 0
    property real osdH: 0

    // The power menu's column (PowerDock), melted out of the frame's right edge. Zero W/H
    // while it is shut.
    property real powerX: 0
    property real powerY: 0
    property real powerW: 0
    property real powerH: 0

    // Magnified dock icons' reach, [{x, y, w, h}], so the dock's material swells
    // around them (DockIconStrip.magnifyBoxes, moved to window space by DockHost).
    property var magnifyRects: []


    // The dock's hover preview, when Config.dockPreviewFuse melts it out of the
    // dock: a lobe a `gap` away from the dock's, which the smooth-min bridges.
    property real previewX: 0
    property real previewY: 0
    property real previewW: 0
    property real previewH: 0

    // The tray's context menu — not a dock slot, so no fixed edge the way left/
    // right/centre have one. It hangs off the bar's underside alone, same as the
    // centre slot, just at whatever X the clicked icon happens to be rather than a
    // fixed dock position. Zero W/H (no menu open) puts it off in BlobRect's own
    // "nothing to draw" corner the same way the toast pool's empty slots do.
    property real trayX: 0
    property real trayY: 0
    property real trayW: 0
    property real trayH: 0

    // The workspace pill's glance (WorkspaceGlance): a card melted out of the bar's underside
    // at the hovered slot. Its own lobe, not previewRect — the sidebar's dock owns that one.
    property real glanceX: 0
    property real glanceY: 0
    property real glanceW: 0
    property real glanceH: 0

    // A bar pill's tooltip (modules/bar/PillTip): a small card melted out of the bar's underside.
    property real tipX: 0
    property real tipY: 0
    property real tipW: 0
    property real tipH: 0

    // Arrange mode's hint cards (components/ArrangeHint): one under the bar, one off the sidebar's face.
    property real arrBarX: 0
    property real arrBarY: 0
    property real arrBarW: 0
    property real arrBarH: 0
    property real arrSideX: 0
    property real arrSideY: 0
    property real arrSideW: 0
    property real arrSideH: 0

    // Every visible notification toast, newest first, as {x, y, w, h} in this Item's
    // coordinates. The whole deck fuses — into each other and, through the top one,
    // into the bar.
    property var toastRects: []

    // Handed back to the cards so their CONTENT squashes with the blob instead of
    // riding on top of it rigidly. caelestia does exactly this — see the
    // `<panel>.transform: Matrix4x4 { matrix: <bg>.deformMatrix }` block at the
    // bottom of their ContentWindow.qml. Without it the card and its background
    // visibly disagree, which reads as the panel sliding across its own shadow.
    readonly property matrix4x4 leftDeform:   leftRect.deformMatrix
    readonly property matrix4x4 rightDeform:  rightRect.deformMatrix
    readonly property matrix4x4 centerDeform: centerRect.deformMatrix
    readonly property matrix4x4 trayDeform:   trayRect.deformMatrix
    readonly property matrix4x4 settingsDeform: settingsRect.deformMatrix
    readonly property matrix4x4 sidebarDeform:  sidebarRect.deformMatrix
    readonly property matrix4x4 previewDeform:  previewRect.deformMatrix
    readonly property matrix4x4 glanceDeform:   glanceRect.deformMatrix
    readonly property matrix4x4 tipDeform:      tipRect.deformMatrix
    readonly property matrix4x4 arrBarDeform:   arrBarRect.deformMatrix
    readonly property matrix4x4 arrSideDeform:  arrSideRect.deformMatrix
    readonly property matrix4x4 sidePanelDeform: sidePanelRect.deformMatrix
    readonly property matrix4x4 osdDeform: osdRect.deformMatrix
    readonly property matrix4x4 powerDeform: powerRect.deformMatrix

    // ── Why a panel's blob is BIGGER than its card ────────────────────────────
    // The shader draws the outline in the innermost `borderWidth` of the material,
    // the same inset a Qt Rectangle uses. Sized to the card exactly, that band sits
    // UNDER the card — which is opaque — so the outline was invisible at rest and
    // only appeared mid-animation, when the spring deformation briefly made the blob
    // larger than the card it tracks. ("The border disappears after the animation.")
    //
    // Grown by one border width on every side, the band lands exactly in the ring
    // between the card's edge and the blob's, which is where a border belongs. It
    // also means the soft SDF edge is what meets the desktop at rest instead of the
    // card's hard rectangle — the settled state stops looking cut out.
    //
    // The radius grows with it so the corner stays concentric with the card's; a
    // constant radius on a grown box pinches the corners.
    function grow(v) { return v > 0 ? v + root.borderWidth * 2 : 0 }

    // ── The id is `blobGroup`, not `group`, and that is load-bearing ─────────
    // Every shape below assigns `group: <this>`. Inside a Repeater DELEGATE that
    // delegate is its own component, and unqualified `group` there resolves to the
    // delegate's OWN `group` property (BlobRect declares one) before it ever reaches
    // an outer id — so `group: group` bound the shape to itself, it never registered,
    // and it rendered nothing at all while reporting perfect geometry. The toasts
    // were positioned exactly right and completely invisible.
    BlobGroup {
        id: blobGroup
        color: root.fill
        smoothing: root.smoothing
        cornerFill: true
        borderColor: root.borderColor
        borderWidth: root.borderWidth
    }

    // ── The cookie field, in the material (Drift.inBlob) ──────────────────────
    // The shell's field (services/Drift) as one list of pictures for this screen, drawn by the
    // shader inside the merged silhouette — so a cookie runs into a fillet, across a bridge and
    // round a weld exactly as the material does. Set through Bindings, never as properties on the
    // group: a plugin built before these existed would refuse the file, and with it the whole blob.
    // Drift.inBlob is only true when it has them (Morph.cookies).
    property string screenName: ""
    readonly property bool cookiesLive: Drift.inBlob && !PowerSaver.quiet
                                        && Fullscreen.byMonitor[root.screenName] !== true
                                        && (Drift.everywhere || Drift.alive)
    property bool _held: false
    function _sync() {
        if (root.cookiesLive && !root._held)      { Drift.acquireBlob(); root._held = true }
        else if (!root.cookiesLive && root._held) { Drift.releaseBlob(); root._held = false }
    }
    onCookiesLiveChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: {
        if (root._held) Drift.releaseBlob()
        Drift.setScreen(root.screenName, 0, 0)
    }
    function _register() { if (root.screenName !== "") Drift.setScreen(root.screenName, root.screenW, root.screenH) }
    onScreenNameChanged: root._register()
    onScreenWChanged: root._register()
    onScreenHChanged: root._register()

    Binding { target: blobGroup; property: "cookies"; when: Drift.inBlob
              value: root.cookiesLive ? Drift.picturesFor(root.screenName) : [] }
    Binding { target: blobGroup; property: "cookieTone0"; when: Drift.inBlob; value: Colors.of(QsWindow.window).primary }
    Binding { target: blobGroup; property: "cookieTone1"; when: Drift.inBlob; value: Colors.of(QsWindow.window).focus }
    Binding { target: blobGroup; property: "cookieTone2"; when: Drift.inBlob; value: Colors.of(QsWindow.window).outline }
    Binding { target: blobGroup; property: "cookieTone3"; when: Drift.inBlob; value: Colors.of(QsWindow.window).fg }
    Binding { target: blobGroup; property: "cookieStroke"; when: Drift.inBlob; value: Tokens.borderWidth }

    // ── The rim sweep: a band of light along a panel's outline as it opens ─────────
    // The shader brightens the outline where its distance from a centre is near a radius
    // (BlobGroup.rimSweep / rimColor, 2026-10-27). When a panel opens, a ring of light runs
    // outward from where it joins the bar and fades, once. Through Bindings, like the cookies:
    // a plugin built before the property exists has no `rimSweep`, so `rimOk` stays false and
    // nothing here does anything.
    readonly property bool rimOk: blobGroup.rimSweep !== undefined
    property real _rimX: 0
    property real _rimY: 0
    property real _rimR: 0
    property real _rimBand: 0
    property real _rimA: 0

    Binding { target: blobGroup; property: "rimSweep"; when: root.rimOk
              value: Qt.vector4d(root._rimX, root._rimY, root._rimR, root._rimBand) }
    Binding { target: blobGroup; property: "rimColor"; when: root.rimOk
              value: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, root._rimA) }

    // Whether each slot was open the last time it changed, so only an OPENING lights the rim.
    property var _wasOpen: ({})

    function _box(key) {
        switch (key) {
            case "left":      return { x: root.leftX,      y: root.leftY,      w: root.leftW,      h: root.leftH,      top: true }
            case "right":     return { x: root.rightX,     y: root.rightY,     w: root.rightW,     h: root.rightH,     top: true }
            case "center":    return { x: root.centerX,    y: root.centerY,    w: root.centerW,    h: root.centerH,    top: true }
            case "tray":      return { x: root.trayX,      y: root.trayY,      w: root.trayW,      h: root.trayH,      top: true }
            case "settings":  return { x: root.settingsX,  y: root.settingsY,  w: root.settingsW,  h: root.settingsH,  top: false }
            case "sidePanel": return { x: root.sidePanelX, y: root.sidePanelY, w: root.sidePanelW, h: root.sidePanelH, top: false }
            case "osd":       return { x: root.osdX,       y: root.osdY,       w: root.osdW,       h: root.osdH,       top: false }
            default:          return { x: root.powerX,     y: root.powerY,     w: root.powerW,     h: root.powerH,     top: false }
        }
    }

    function _watch(key) {
        if (!root.rimOk) return
        const b = root._box(key)
        const open = b.w > 1 && b.h > 1
        if (open && !root._wasOpen[key]) {
            // The box's x/y can land a binding after its size does: read them next tick.
            Qt.callLater(() => root.ignite(key))
        }
        root._wasOpen[key] = open
    }

    // Hanging off the bar: from the join, top-centre. Everything else: from its middle.
    function ignite(key) {
        const b = root._box(key)
        if (b.w <= 1 || b.h <= 1) return
        const reach = b.top ? Math.hypot(b.w / 2, b.h) * 1.1 : Math.hypot(b.w, b.h) / 2 * 1.2
        root._igniteAt(b.x + b.w / 2, b.top ? b.y : b.y + b.h / 2, reach)
    }

    function _igniteAt(cx, cy, reach) {
        if (!root.rimOk || reach < 1) return
        root._rimX = cx
        root._rimY = cy
        root._rimBand = Math.max(20, reach * 0.14)
        rimRun.reach = reach
        rimRun.restart()
    }

    // ── The events that light the rim, besides a panel opening ─────────────────
    // A notification toast arriving: from the join of the newest one (`toastRects` is newest
    // first). Only an INCREASE in the count — toasts moving and leaving change the list every
    // frame and must not. Under do-not-disturb no toast welds, so nothing lights.
    property int _toastCount: 0
    onToastRectsChanged: {
        const n = root.toastRects ? root.toastRects.length : 0
        if (n > root._toastCount && root.rimOk) Qt.callLater(root._igniteToast)
        root._toastCount = n
    }
    function _igniteToast() {
        const r = root.toastRects && root.toastRects[0]
        if (!r || r.w <= 1 || r.h <= 1) return
        root._igniteAt(r.x + r.w / 2, r.y, Math.hypot(r.w / 2, r.h) * 1.1)
    }

    // The volume reaching 100% on a key press: the column's rim flashes once as it tops out —
    // the OSD is usually open already by then, so this is the only sweep it gets. Osd.value is
    // 0..1 and clamps at 100%, so "full" is the value reaching 1.
    property real _lastVolume: 0
    Connections {
        target: Osd
        function onRequestIdChanged() {
            if (Osd.kind !== "volume") return
            const full = Osd.value >= 0.999
            if (full && root._lastVolume < 0.999) Qt.callLater(() => root.ignite("osd"))
            root._lastVolume = Osd.value
        }
    }

    ParallelAnimation {
        id: rimRun
        property real reach: 0
        // Motion off: the durations collapse to 0, the alpha lands on 0 and nothing is drawn.
        NumberAnimation { target: root; property: "_rimR"; from: 0; to: rimRun.reach
                          duration: Motion.slow; easing.type: Easing.BezierSpline
                          easing.bezierCurve: Motion.emphasizedDecel }
        NumberAnimation { target: root; property: "_rimA"; from: 0.9; to: 0
                          duration: Motion.slow; easing.type: Motion.respondCurve }
    }

    onLeftHChanged:      root._watch("left")
    onLeftWChanged:      root._watch("left")
    onRightHChanged:     root._watch("right")
    onRightWChanged:     root._watch("right")
    onCenterHChanged:    root._watch("center")
    onCenterWChanged:    root._watch("center")
    onTrayHChanged:      root._watch("tray")
    onTrayWChanged:      root._watch("tray")
    onSettingsHChanged:  root._watch("settings")
    onSettingsWChanged:  root._watch("settings")
    onSidePanelHChanged: root._watch("sidePanel")
    onSidePanelWChanged: root._watch("sidePanel")
    onOsdHChanged:       root._watch("osd")
    onOsdWChanged:       root._watch("osd")
    onPowerHChanged:     root._watch("power")
    onPowerWChanged:     root._watch("power")

    // ── The ring: bar AND screen frame, as ONE shape ──────────────────────────
    // The other half of every union in this group. A BlobInvertedRect is the
    // COMPLEMENT of a rounded rect — material everywhere except the middle — so one
    // of them is the bar across the top, both side strips and the bottom strip,
    // with a single continuous SDF. A panel welding into the left strip and a panel
    // welding into the bar are then the same operation, which is what "it should
    // function the same as the bar" means.
    //
    // Inflated by `pad` so the ring's OUTER edge and its outer corner rounding fall
    // off-screen; only the inner boundary — the one panels fuse against — is ever
    // in view.
    //
    // This band is painted in the BAR's window, which maps after (and therefore
    // above) ScreenFrame's — so it covers the real strips outright. That is now
    // correct rather than a problem: the blob draws the ring's fill AND its stroke,
    // and the two files that used to draw them stand down while it does.
    readonly property real pad: 50

    // How many toasts can weld at once. The deck itself is not capped — a burst past
    // this many simply stops welding the overflow rather than dropping it, which is
    // the right failure: the notification still shows.
    readonly property int toastPool: 6

    // The toast lobes' corner radius, named because the bridge above has to know how
    // far into a neighbour it must reach to bury one.
    readonly property real corner: Tokens.radiusCard + root.borderWidth

    // ── How much of one lobe the other still covers, 0..1 ─────────────────────
    // Whether two lobes should weld is a HORIZONTAL question, and it is not "are
    // their edges equal": the deck is right-aligned, so a 372-wide toast under a
    // 400-wide one (an attachment preview widens it) is still completely covered and
    // must still weld. Overlap measured against the NARROWER of the two says that,
    // and still says no the moment one of them slides out on its own enter or exit.
    function cover(a, b) {
        if (!a || !b) return 0
        const span = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
        const w = Math.min(a.w, b.w)
        return w > 0 ? Math.max(0, Math.min(1, span / w)) : 0
    }

    // Full bridge while the two are essentially stacked, tapering to none across the
    // last tenth of that cover — continuous, so the weld lets go over the same frames
    // the card is travelling instead of switching off in one.
    //
    // The knee can sit this high because the deck is right-aligned and every toast is
    // one of two widths, so cover is EXACTLY 1 whenever nothing is moving — including
    // through a reflow, which only changes y. It costs nothing at rest and buys a
    // bridge that is already gone by the time the enter is 37px from home.
    function weld(a, b) { return Math.max(0, (root.cover(a, b) - 0.9) * 10) }

    BlobInvertedRect {
        id: ring
        group: blobGroup
        x: -root.pad
        y: -root.pad
        width:  root.screenW + root.pad * 2
        height: root.screenH + root.pad * 2
        radius: root.frameRadius
        // One border width PAST the bar's underside, deliberately. BlobMaterial
        // draws its outline on the INSIDE of the silhouette (the band where the SDF
        // is within borderWidth of zero), and inside-the-ring at the top means
        // behind the bar's own opaque Surface — so an outline placed exactly on the
        // bar's bottom edge is invisible, and the bar loses its underline the moment
        // the blob takes the ring over. Pushing the hole down by one border width
        // puts that band just below the Surface instead, where it is the line.
        // The extra material is under the Surface and never seen.
        borderTop:    root.pad + root.barHeight + root.borderWidth
        borderLeft:   root.pad + root.frameInset
        borderRight:  root.pad + root.frameInset
        borderBottom: root.pad + root.frameInset
        // No deformScale here: the spring physics live on BlobRect, and
        // BlobInvertedRect derives straight from BlobShape whose updatePhysics() is
        // the empty base. It is a static shape by construction, which is what the
        // ring should be — neither bar nor frame moves.
    }

    BlobRect {
        id: leftRect
        group: blobGroup
        x: root.leftX - root.borderWidth
        y: root.leftY - root.borderWidth
        width:  root.grow(root.leftW)
        height: root.grow(root.leftH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    BlobRect {
        id: rightRect
        group: blobGroup
        x: root.rightX - root.borderWidth
        y: root.rightY - root.borderWidth
        width:  root.grow(root.rightW)
        height: root.grow(root.rightH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // ── The notification deck ─────────────────────────────────────────────────
    // A FIXED pool, not a Repeater over `toastRects`. A JS array as a Repeater model
    // destroys and rebuilds every delegate on every change (QQuickRepeater::regenerate,
    // the same trap NotificationStack documents for its own Repeater) — and these
    // change every frame while a toast slides, which would mean tearing down and
    // reincubating the whole pool 60 times a second. A constant model never
    // regenerates; the delegates just re-read their slot.
    //
    // Grown by a border width on every side for the same reason the panel rects are:
    // BlobMaterial draws its outline on the INSIDE of the silhouette, so a rect sized
    // exactly to the card puts that band under the card's own opaque fill, where it is
    // invisible. The cards drop their own borders when welded (NotificationStack.welded)
    // and this is the stroke that replaces them.
    Repeater {
        model: root.toastPool
        delegate: BlobRect {
            required property int index
            readonly property var r: root.toastRects[index] ?? null

            group: blobGroup

            // ── Bridging the gap between stacked toasts ───────────────────────
            // The cards sit `Tokens.spacingMd` apart, and two rounded rects that far
            // apart do not merge into a column — the smooth-min pinches a WAIST
            // between them, and each pinch reads as a pair of corners cut into the
            // side of the stack. So a rect with a neighbour is extended past the gap
            // and far enough into that neighbour to swallow its rounded corner
            // entirely, which leaves the union with a straight side and no pinch.
            //
            // The extension is on the BLOB only; the cards keep their spacing, so the
            // deck still reads as separate notifications rather than one long slab.
            //
            // How FAR it reaches is root.weld(), not a boolean, because a bridge is
            // only sound while it is BURIED in the neighbour it reaches for. As a flat
            // "is there a card above me", it went on reaching into the slot above
            // throughout every enter and every swipe — while the card up there had
            // slid 84px out of that slot, or 140 on its way off. What was left was a
            // 29px tongue of material standing proud of the stack pointing at nothing,
            // for the whole of the animation. Tapering it as the two separate lets the
            // weld break the way the rest of the morph now does.
            readonly property real bridge: Tokens.spacingMd + root.corner
            readonly property real bridgeAbove:
                root.weld(r, root.toastRects[index - 1]) * bridge
            readonly property real bridgeBelow:
                root.weld(r, root.toastRects[index + 1]) * bridge

            x: r ? r.x - root.borderWidth : -100000
            y: r ? r.y - root.borderWidth - bridgeAbove : -100000
            width:  r ? root.grow(r.w) : 0
            height: r ? root.grow(r.h) + bridgeAbove + bridgeBelow : 0
            radius: root.corner
            deformScale: root.deformScale
        }
    }

    // The centre slot (system updates). Unlike the other two this one touches no
    // side strip — it hangs off the bar's underside alone, so its only join is the
    // top one and the smooth-min has just the bar to blend into.
    BlobRect {
        id: centerRect
        group: blobGroup
        x: root.centerX - root.borderWidth
        y: root.centerY - root.borderWidth
        width:  root.grow(root.centerW)
        height: root.grow(root.centerH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The docked settings panel. Grows up out of the bottom strip; at side
    // "left"/"right" its edge also meets a side strip and the ring welds both.
    BlobRect {
        id: settingsRect
        group: blobGroup
        x: root.settingsX - root.borderWidth
        y: root.settingsY - root.borderWidth
        width:  root.grow(root.settingsW)
        height: root.grow(root.settingsH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The unified sidebar's bar. The dock's weld, the whole edge long. The sidebar
    // wears the top bar's corner (Config.sidebarRadius), and so do its lobes.
    BlobRect {
        id: sidebarRect
        group: blobGroup
        x: root.sidebarX - root.borderWidth
        y: root.sidebarY - root.borderWidth
        width:  root.grow(root.sidebarW)
        height: root.grow(root.sidebarH)
        radius: Config.sidebarRadius + root.borderWidth
        deformScale: root.deformScale
    }


    // A sidebar button's panel: a card like the bar's panels (their corner), welded
    // into the sidebar's lobe the way those weld into the bar.
    BlobRect {
        id: sidePanelRect
        group: blobGroup
        x: root.sidePanelX - root.borderWidth
        y: root.sidePanelY - root.borderWidth
        width:  root.grow(root.sidePanelW)
        height: root.grow(root.sidePanelH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The OSD's sliders: a card like a panel's, welded into the frame's right strip.
    BlobRect {
        id: osdRect
        group: blobGroup
        x: root.osdX - root.borderWidth
        y: root.osdY - root.borderWidth
        width:  root.grow(root.osdW)
        height: root.grow(root.osdH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The power menu's column: the same, one edge-hugging card.
    BlobRect {
        id: powerRect
        group: blobGroup
        x: root.powerX - root.borderWidth
        y: root.powerY - root.borderWidth
        width:  root.grow(root.powerW)
        height: root.grow(root.powerH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // ── The magnification bump ────────────────────────────────────────────────
    // A FIXED pool, like the toasts', not a Repeater over the array: the boxes
    // change every frame the pointer moves, and an array model would rebuild every
    // lobe each time. Magnification reaches two slots either side of the pointer,
    // so a handful covers it. No spring: these follow the hand, and a deform on a
    // shape the pointer drives reads as lag (the rule the drags follow too).
    readonly property int magnifyPool: 7
    Repeater {
        model: root.magnifyPool
        delegate: BlobRect {
            required property int index
            readonly property var r: root.magnifyRects[index] ?? null
            group: blobGroup
            x: r ? r.x - root.borderWidth : -100000
            y: r ? r.y - root.borderWidth : -100000
            width:  r ? root.grow(r.w) : 0
            height: r ? root.grow(r.h) : 0
            // Each layer's own radius (dock.js magnifyBell) — as round as it is tall.
            radius: (r && r.r !== undefined ? r.r : Tokens.radiusCard) + root.borderWidth
            deformScale: 0
        }
    }

    // The dock's preview, fused. A free lobe like trayRect's, welded to the dock.
    BlobRect {
        id: previewRect
        group: blobGroup
        x: root.previewX - root.borderWidth
        y: root.previewY - root.borderWidth
        width:  root.grow(root.previewW)
        height: root.grow(root.previewH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The workspace glance: the same single join as the tray menu, at the hovered slot.
    BlobRect {
        id: glanceRect
        group: blobGroup
        x: root.glanceX - root.borderWidth
        y: root.glanceY - root.borderWidth
        width:  root.grow(root.glanceW)
        height: root.grow(root.glanceH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The arrange hint cards: single joins like the glance's, with the hero corner.
    BlobRect {
        id: arrBarRect
        group: blobGroup
        x: root.arrBarX - root.borderWidth
        y: root.arrBarY - root.borderWidth
        width:  root.grow(root.arrBarW)
        height: root.grow(root.arrBarH)
        radius: Tokens.radiusXl + root.borderWidth
        deformScale: root.deformScale
    }
    BlobRect {
        id: arrSideRect
        group: blobGroup
        x: root.arrSideX - root.borderWidth
        y: root.arrSideY - root.borderWidth
        width:  root.grow(root.arrSideW)
        height: root.grow(root.arrSideH)
        radius: Tokens.radiusXl + root.borderWidth
        deformScale: root.deformScale
    }

    // A bar pill's tooltip: the glance's single join, smaller.
    BlobRect {
        id: tipRect
        group: blobGroup
        x: root.tipX - root.borderWidth
        y: root.tipY - root.borderWidth
        width:  root.grow(root.tipW)
        height: root.grow(root.tipH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }

    // The tray context menu. Same single-join treatment as centerRect, at a free X.
    BlobRect {
        id: trayRect
        group: blobGroup
        x: root.trayX - root.borderWidth
        y: root.trayY - root.borderWidth
        width:  root.grow(root.trayW)
        height: root.grow(root.trayH)
        radius: Tokens.radiusCard + root.borderWidth
        deformScale: root.deformScale
    }
}
