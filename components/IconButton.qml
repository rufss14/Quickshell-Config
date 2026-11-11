import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"
import "../services/markhandoff.js" as MarkHandoff

// ── IconButton ────────────────────────────────────────────────────────────────
// The shell's one interactive control. Every bar button, dock button, and panel
// action is this.
//
// It exists to enforce the state ladder, which every button previously
// re-derived for itself — and they disagreed. Some had press states, some
// didn't. The "active" (panel-open) look was `btnActiveBg` in most places, a
// hand-rolled `pw(color1, 0.15)` in UpdateButton, and `pw(color4, 0.20)` in
// WifiButton. The ladder is now one expression:
//
//   idle    → no fill, muted foreground
//   hover   → primary @ 0.18 fill, primary foreground
//   pressed → primary @ 0.35 fill
//   active  → primary @ 0.22 fill, primary foreground   (toggled on)
//
// hover wins over active when both apply, because hover is the more immediate
// feedback — the user is asking "will this respond to me", and the answer has to
// come before "is this already on".
//
// ── container ─────────────────────────────────────────────────────────────────
// ON by default: every control sits in its own inset pill.
//
// The bar used to run two visual languages side by side — flat toggle buttons
// next to pill-wrapped readouts like the clock and the wifi indicator — which is
// precisely what made it read as incoherent. Now the pill is universal, so the
// bar has one rhythm: a group pill, containing inset pills, containing controls.
//
// The state ladder still layers ON TOP of the resting pill, so a fill continues
// to mean "this responded to you" — it's just drawn over a surface rather than
// over nothing. Set `container: false` for a control that must be chromeless.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Screen readers (AT-SPI): what this is and what pressing it does. Keyboard focus
    // order is not wired yet — see docs/standards.md, Accessibility.
    // An icon-only button has no words of its own: the caller names it (a bar module passes its
    // catalogue label), else it falls back to the label, then the symbol's name.
    property string accessibleName: ""
    Accessible.role: Accessible.Button
    Accessible.name: root.accessibleName !== "" ? root.accessibleName : root.label !== "" ? root.label : root.symbol
    Accessible.checkable: root.active
    Accessible.checked: root.active
    Accessible.onPressAction: root.clicked()

    property string glyph: ""

    // ── `icon` is a url, and that changes how you test it for "empty" ─────────
    // `root.icon === ""` compares a url to a STRING and is therefore always false —
    // which would hide the glyph unconditionally and leave the bar blank. The code used
    // `==` to dodge that via coercion, which works but reads like an oversight and
    // invites exactly the "fix" that breaks it.
    //
    // `String(root.icon) === ""` says what it means: resolve the url, then compare
    // strings. Type-safe, and no longer a trap for the next person (or the next linter).
    property url icon: ""
    property string label: ""

    property bool active:     false     // toggled on (e.g. its panel is open)
    property bool squareMode: false     // barShape
    property bool container:   true     // inset pill at rest (see below). Default: yes.
    property bool interactive: true

    // The GROUP's spacing override (Config.groupSpacing), in pixels — half of it
    // becomes this button's own horizontal padding, the other half comes from its
    // neighbour, so two adjacent icons end up exactly `spacing` px apart (with
    // BarGroupRow's own inter-slot gap dropped to 0 for the pair — see its
    // gapBefore). -1 (the default, and Config's "unset" sentinel) means this
    // button keeps its full `pillIconWidth` touch target, unaffected.
    property int spacing: -1

    // ── Scaled by the bar's settings, not raw tokens ──────────────────────────
    // A `glyph` is a Nerd Font ICON that happens to be a character, so it scales with
    // the icons — not with barFontScale, which is for text you read. `label` is the only
    // real text here (the clock, the layout tag, an SSID), so it's the only thing the
    // font scale touches.
    //
    // Defaults, so a caller that sets its own size still wins. IconButton reads Config
    // directly rather than being told: it already does for barRoundness, and it is a bar
    // component — the settings page's preview is built from these same pills, which is
    // why the preview scales for free.
    property int iconSize:  Math.round(Tokens.iconMd    * Config.barIconScale)
    property int glyphSize: Math.round(Tokens.fontTitle * Config.barIconScale)
    // The label is BarLabel's style (the bar's one label style, 2026-10-31): its size, and
    // below its weight and tabular digits. Only bar pills set `label` (keyboard, locks).
    property int labelSize: Math.round(Tokens.fontLabel * Config.barFontScale)

    // ── accent ────────────────────────────────────────────────────────────────
    // The colour this button's state ladder is built from. Defaults to `primary`,
    // which is what the ladder used to name directly — so the default is byte-for-byte
    // the old behaviour, and only a module the user has deliberately recoloured differs.
    //
    // It's a property rather than a Colors lookup because the CALLER knows which module
    // this is; the button doesn't, and shouldn't have to.
    property color accent: Colors.of(QsWindow.window).primary

    // Foreground override — for controls that color their icon by state rather
    // than by interaction (the wifi pill tints by signal strength).
    property color iconColor: root.fg

    // ── symbol / symbolFill ───────────────────────────────────────────────────
    // A Material Symbols ligature name, e.g. "notifications". Takes precedence
    // over `glyph` when set; `glyph` is untouched so un-migrated call sites keep
    // rendering exactly as they did.
    //
    // `symbolFill` is the reason this is worth doing at all. A state change used
    // to mean swapping to a DIFFERENT glyph — `glyph: quiet ? "" : ""` —
    // which cuts. Along the FILL axis the same icon fills instead, animated by
    // MaterialIcon's own Behavior: the bell solidifies as do-not-disturb comes on.
    // Defaulting it to `active` means a toggle gets that for free without the
    // caller doing anything.
    property string symbol: ""
    property real   symbolFill: root.active ? 1 : 0

    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    // ── The pill's shared hover plate ─────────────────────────────────────────
    // In a pill of buttons (BarGroup's), hover is ONE plate that slides from button to
    // button (HoverTrack, which says why). Found on the first ancestor offering `hoverTrack`,
    // at creation and again on a hover if it wasn't there yet; none (anywhere but the bar),
    // and this button draws its own hover as it always did. Its ripple, lift and lean stay
    // its own either way.
    property var _track: null
    function _findTrack() {
        for (let p = root.parent; p; p = p.parent)
            if (p.hoverTrack !== undefined) return p.hoverTrack
        return null
    }
    readonly property bool _tracking: root.hovered && root.interactive
    on_TrackingChanged: {
        if (!root._track) root._track = root._findTrack()
        if (!root._track) return
        if (root._tracking) root._track.claim(root)
        else                root._track.release(root)
    }
    Component.onDestruction: if (root._track) root._track.release(root)
    // The icon leans toward the pointer, a pixel at most (see MagnetLean). Applied to the glyph,
    // the symbol, the label, the SVG and the custom content (`overlay`: the window pill's row).
    MagnetLean {
        id: magnet
        active: root.hovered && root.interactive
        pointerX: mouse.mouseX
        pointerY: mouse.mouseY
        extentW: root.width
        extentH: root.height
    }
    // Hover as ONE spring, 0 → 1, on Material 3 Expressive's fast spatial spring: the plate's
    // swell and the icon's lift both ride it. The overshoot the old OutBack curve drew, but a
    // pointer that leaves mid-swell turns it round with its speed kept instead of restarting.
    SpringValue {
        id: hov
        spec: Motion.springSpatialFast
        epsilon: 0.002
        target: root.hovered && root.interactive ? 1 : 0
    }
    readonly property real _grow: hov.value * Tokens.spacingXs
    // The icon rises a hair under the pointer and settles back. Hover only: the press has its
    // wave and its stretch (below), and a scale on top of those would thud.
    readonly property real _lift: 1 + 0.08 * hov.value
    // Config.barRoundness, not Tokens.radiusPill: the bar's corner is a user setting
    // now. This is safe to key off Config because IconButton is bar-only — panels use
    // PanelButton and the dock has its own icon. Tokens still supplies the DEFAULT that
    // Config starts from.
    readonly property int  cornerRadius: Tokens.corner(squareMode, Config.barRoundness)

    // ── The plate is concentric with the inner pill ───────────────────────────
    // A bar button stands in BarGroup's inner pill, which reaches spacingXs past it above and
    // below and spacingSm past a run's ends. The plate (hover tint, ripple) keeps ONE even gap
    // to that pill, and its corners are the pill's less the gap, so the two curves run
    // parallel (2026-10-31, the user's call: the old swell filled the pill top to bottom, and
    // the press squish then drew a squarer block inside a round pill — "doesn't match the inner
    // pills"). Hover grows it spacingXs along the bar only, out to the gap the pill keeps above
    // and below.
    //
    // Press is Material 3 Expressive's squash and stretch instead of tighter corners: half a
    // step longer along the bar, half a step shorter across it, on the fast spring, corners
    // following — so the plate stays the pill's shape. The spring is a 0→1 factor: at rest
    // the plate tracks the size and roundness 1:1 (a sprung radius chased the height from 0 at
    // creation, opening every button's corners on each reload).
    SpringValue {
        id: pressSpring
        spec: Motion.springSpatialFast
        epsilon: 0.002
        target: root.pressed && root.interactive ? 1 : 0
    }
    readonly property real _alongGrow:  root._grow + pressSpring.value * Tokens.spacingXs / 2
    readonly property real _acrossTrim: pressSpring.value * Tokens.spacingXs / 2
    readonly property real _plateRadius: Math.max(0, Math.min(
        Tokens.corner(root.squareMode, Math.max(0, Config.barRoundness - Tokens.spacingXs)),
        root.height / 2 - root._acrossTrim))

    // Extra content (badges, indicator dots) layers on top of the fill.
    default property alias content: overlay.data

    // A tooltip worked out when the pointer arrives (HelpTip.provide): a function returning the words,
    // or null for none. The caller owns the wording; this file stays free of services.
    property var tipProvider: null
    HelpTip { provide: root.tipProvider; pill: true }

    signal clicked()
    signal rightClicked()
    signal middleClicked()
    signal scrolled(int delta)          // +1 up, -1 down

    // What the pill actually has to hold. Tokens.pillHeight is the floor rather than the
    // answer: with the icon or font scale turned up, fixing the height at 24 would just
    // clip the thing that grew.
    // `symbol` is checked BEFORE `glyph` for the same reason it wins at render
    // time. Miss it here and a symbol-only pill falls through to `iconSize` — the
    // SVG branch's size — so every migrated pill quietly sizes to the wrong thing
    // while still looking plausible.
    readonly property int contentExtent: root.label !== ""  ? Math.ceil(labelText.implicitHeight)
                                       : root.symbol !== "" ? Math.ceil(symbolIcon.implicitHeight)
                                       : root.glyph !== ""  ? Math.ceil(glyphText.implicitHeight)
                                       :                      root.iconSize

    // spacingSm, not spacingXs — a hairline of headroom around the glyph read as
    // cramped once barIconScale grew past its old 1.15 default (the "Big" size
    // preset lands here at ~1.3): the pill barely grew past the glyph it holds.
    // spacingSm gives it room to read as a comfortable pill rather than a tight
    // outline, at every size preset, without a floor that fights small icons.
    implicitHeight: Math.max(Tokens.pillHeight, root.contentExtent + Tokens.spacingSm * 2)
    // Math.ceil, not a raw sum: label width comes from FONT METRICS, which are
    // fractional. A pill landing on x=142.37 puts its 1px border across two device
    // pixels, and antialiasing smears it into a soft ~2px line — the border looks
    // thicker than it is. Snapping the pill to whole pixels keeps it a hairline.
    // A group spacing override swaps the pill's own padding for half of it and
    // drops the `pillIconWidth` touch-target floor — the floor is what a
    // comfortable click target needs, but it's also what makes a "bare" run of
    // status icons (container: false, no label) look far more spread out than
    // the icons drawn inside actually are, and a fixed floor can't be tuned finer
    // than "on or off".
    readonly property int _hPad: root.spacing >= 0 ? Math.round(root.spacing / 2) : Tokens.pillPadding
    implicitWidth:  label !== ""
        ? Math.ceil(labelText.implicitWidth) + root._hPad * 2
        : root.spacing >= 0
            ? root.contentExtent + root._hPad * 2
            : Math.max(Tokens.pillIconWidth, root.contentExtent + root._hPad * 2)

    readonly property color fg: (root.hovered || root.pressed || root.active)
        ? root.accent
        : Colors.of(QsWindow.window).stateIdleFg

    // ── Resting surface ───────────────────────────────────────────────────────
    // `container` is now the DEFAULT: every control in the bar sits in its own
    // inset pill. The bar previously had two languages at once — flat toggle
    // buttons next to pill-wrapped readouts like the clock — which is what made
    // it read as incoherent.
    //
    // Elevation Nested, not Bar. This pill sits INSIDE the group pill, and an
    // outline tuned for sitting on a wallpaper (alpha 0.12) is invisible against
    // another surface's own fill — the nested thing then looks like the parent
    // simply changed size. This is the exact case the Nested elevation exists for,
    // and it's why the old code needed a bespoke `nestedPillBorder` constant.
    Rectangle {
        anchors.fill: parent
        radius:  root.cornerRadius
        visible: root.container
        color:        Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)
        // Config.barBorderWidth, not Tokens.borderWidth — the same "Pill border"
        // slider that already governs the group pill outside this one, so a
        // single knob (down to 0) flattens both at once. Was a fixed hairline;
        // that meant the outer pill could go borderless while every control
        // inside it kept a 1px outline, which reads as chrome nested in flat
        // fill rather than one seamless surface.
        border.width: Config.barBorderWidth
        border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationNested)

        Behavior on radius       { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        Behavior on color        { ColorAnimation  { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation  { duration: Motion.respond } }
    }

    // ── State fill ────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: root._plateRadius

        // The alphas Colors.state*Bg encodes, applied to this button's accent rather
        // than to `primary` unconditionally.
        //
        // ── The PRESSED step (0.35) is gone, and the ripple replaces it ───────
        // Stacking a wave on top of a flat 0.35 darkening double-darkens: the press
        // reads as a thud rather than as a wave leaving your finger, and the two
        // fight over the same pixels. The ripple below IS the press feedback now.
        // Hover (0.18) and active (0.22) are untouched — those are this shell's own
        // ladder and louder than M3's 8% on purpose.
        // ── ACTIVE is no longer a fill ────────────────────────────────────────
        // It used to be a flat `alpha(accent, 0.22)` wash, which is the same KIND of
        // signal as hover (0.18) only slightly louder — so "I am pointing at this"
        // and "this button's panel is open" were told apart by two percent of alpha.
        // The underline below says it instead. Hover keeps the fill, which is
        // now the only thing that uses one.
        // Hover (0.18) is drawn by the StateLayer below now, as a reveal from where the
        // pointer came in; this Rectangle only keeps the corner animation in step.
        color: "transparent"
    }

    // ── The press wave ────────────────────────────────────────────────────────
    // Above the state fill, below the glyph — where M3 puts a state layer, and the
    // only place it reads as part of the surface rather than as something painted
    // over the icon.
    //
    // It also draws hover (`reveal`, 0.18 — the ladder's own step): a tint that grows from
    // the pointer's entry point rather than fading in flat. The Rectangle above no longer
    // draws one, so there is still only the one hover tint.
    //
    // Driven by `mouse` below, not by a MouseArea of its own — see StateLayer.qml
    // for why that inversion matters here and not in caelestia.
    StateLayer {
        id: ripple
        anchors.fill: parent
        visible: root.interactive
        layerColor: root.accent
        hovered: root.hovered
        reveal: true
        // The shared plate draws hover while there is one; the press wave stays here.
        hoverOpacity: root._track ? 0 : 0.26
        ringOpacity: root._track ? 0 : 0.4
        pointerX: mouse.mouseX
        pointerY: mouse.mouseY
        // The plate grows along the bar on hover and stretches on press (see "concentric"
        // above): on a 24px button the tint alone barely read.
        anchors.leftMargin:   -root._alongGrow
        anchors.rightMargin:  -root._alongGrow
        anchors.topMargin:    root._acrossTrim
        anchors.bottomMargin: root._acrossTrim
        radius: root._plateRadius
    }

    // ── The active underline ──────────────────────────────────────────────────
    // A short accent bar under the content while this button is toggled on — its
    // panel is up, its mode is engaged, its work is running. This was UpdatePill's
    // alone, hand-written there because the update panel needed a cue the flat
    // fill could not give; every other button in the shell got the fill and
    // nothing else. It lives here now, so "which button owns the thing I am
    // looking at" is answered the same way by all of them.
    //
    // Replaced a full-perimeter breathing ring: tracing the whole pill and pulsing
    // forever reads as ambient urgency — "something needs you" — for a state that
    // is usually just "yes, this is open". A static underline says the same thing
    // without asking for attention indefinitely, and settling in on `width` rather
    // than snapping keeps a settle-motion cue on entry without an infinite
    // animation running the whole time the panel stays open.
    Rectangle {
        id: mark
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.markGap
        radius: Tokens.radiusFull
        color: root.accent
        height: Tokens.borderChrome
        // Sized off the icon, not the pill (`_markFull`): a wide label pill (the clock) would
        // otherwise draw a long bar spanning almost the whole button instead of a
        // small mark under its content. `markW` is aimed by `_markMoved` below, not bound,
        // so a mark that arrives from another button can start at THAT mark's width.
        width: Math.max(0, markW.value)

        // The hand-off's flight: the mark's offset from where it belongs, springing to 0.
        transform: Translate { x: markFly.value * root._flyDx; y: markFly.value * root._flyDy }
    }

    // ── The mark travels ──────────────────────────────────────────────────────
    // When one button's mark goes out and another's comes on within a moment (a panel
    // swapping for another — Accordion sequences the one out before the next in), the new
    // mark flies in from where the old one was, at the old one's width, instead of growing
    // from nothing beside it. `services/markhandoff.js` is the memory between the two.
    // Anything else (a first open, a close, a toggle set long after another) grows and
    // shrinks in place, as it always did.
    // Distance from the button's bottom edge to the mark. Negative puts it just under the
    // button: for content that fills the height (ClockPill's two lines), where any mark
    // inside would cross the text.
    property real markGap: Tokens.spacingXs
    readonly property bool  _markOn:   root.active && root.interactive
    readonly property real  _markFull: Math.min(root.iconSize, root.width - Tokens.spacingMd * 2)
    readonly property string _markKey: String(QsWindow.window?.screen?.name ?? "")

    // Both on the standard spatial spring: the mark lands with a small overshoot (it grows a
    // touch past its length, or flies a touch past its button) and settles. Motion off
    // (Motion.springTime 0) puts both straight at their targets, so a hand-off is a plain swap.
    SpringValue { id: markW;   spec: Motion.springSpatial; epsilon: 0.05;  target: 0 }
    // 1 → 0: how much of the flight's offset (`_flyDx/_flyDy`) is still left to cover.
    SpringValue { id: markFly; spec: Motion.springSpatial; epsilon: 0.002; target: 0 }
    property real _flyDx: 0
    property real _flyDy: 0

    function _markMoved() {
        const c = mark.mapToItem(null, mark.width / 2, mark.height / 2)
        if (!root._markOn) {
            // Leaving: remember where, then shrink in place.
            MarkHandoff.leave(root._markKey, c.x, c.y, markW.value)
            markW.target = 0
            return
        }
        const from = MarkHandoff.take(root._markKey, 900)
        if (from) {
            // Arriving: start at the old mark's place and width, fly to our own.
            markW.jump(from.w)
            root._flyDx = from.cx - c.x
            root._flyDy = from.cy - c.y
            markFly.jump(1)
        }
        markW.target = root._markFull
    }
    on_MarkOnChanged: root._markMoved()
    on_MarkFullChanged: if (root._markOn) markW.target = root._markFull
    // On at creation: there already, not growing in on every reload.
    Component.onCompleted: {
        if (root._markOn) { markW.target = root._markFull; markW.jump(root._markFull) }
        root._track = root._findTrack()
    }

    Text {
        id: glyphText
        visible: root.glyph !== "" && root.symbol === "" && String(root.icon) === ""
        anchors.centerIn: parent
        text:  root.glyph
        color: root.iconColor
        font.family:    Tokens.glyphFamily(root.glyph)
        font.pixelSize: root.glyphSize
        scale: root._lift
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // ── The Material Symbols path ─────────────────────────────────────────────
    // Additive: `symbol` wins where it is set, and every un-migrated `glyph:` site
    // keeps working untouched. That is what lets the icon migration proceed one
    // directory at a time with a reload between each, rather than as one 75-file
    // commit that either works or doesn't.
    MaterialIcon {
        id: symbolIcon
        visible: root.symbol !== ""
        anchors.centerIn: parent
        name:  root.symbol
        fill:  root.symbolFill
        color: root.iconColor
        // Matches glyphText: an icon scales with the ICON scale, not the font one.
        font.pixelSize: root.glyphSize
        scale: root._lift
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    // Loader-gated rather than an always-present Image with `visible: false`.
    // An Image still *loads* its source when hidden, and an empty url resolves
    // to Quickshell's `qs-blackhole` placeholder, which then fails to open — one
    // "Cannot open: qrc:/qs-blackhole" warning per glyph- or label-only button.
    // Not constructing it at all is both quieter and cheaper.
    Loader {
        active: String(root.icon) !== ""
        anchors.centerIn: parent
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }

        // The asset is TINTED to the same state ladder the glyph icons follow,
        // not drawn as-is: every SVG in assets/icons is baked `fill="#e3e3e3"`,
        // which is fine on a dark pill and *invisible on a light one* — the
        // wallpaper and palette buttons vanished entirely in light mode.
        //
        // ── Mask, not colorize ─────────────────────────────────────────────────
        // This used to be `MultiEffect.colorization`, which turned out to be a
        // MULTIPLY onto the source's own luminance rather than a flat override —
        // close enough to look right on a near-white `#e3e3e3` source tinted
        // toward another near-white, but it never actually stopped mattering what
        // shade the file was drawn in, and any accent further from white than
        // that (the DND bell's warning/danger tint, `Config.moduleAccent`'d icons
        // like Palette) rendered muted and off-hue instead of the real colour.
        // Masking a solid Rectangle by the icon's own alpha sidesteps that: the
        // icon is a pure stencil, its fill colour never reaches the output. Same
        // technique VisualizerPill already uses to round the album art's corners.
        //
        // iconColor reads `root.iconColor`, same as the glyph/symbol/label paths
        // below — it defaults to `root.fg`, so nothing that never touches
        // `iconColor` changes. This was hardcoded to `root.fg` directly, which is
        // what made the DND bell's warning tint silently do nothing the moment it
        // switched from a glyph to an svg asset: three of four content types
        // honoured a caller's iconColor override and this one didn't.
        sourceComponent: Item {
            width:  root.iconSize
            height: root.iconSize

            Image {
                id: assetMask
                anchors.fill: parent
                source: root.icon
                sourceSize: Qt.size(root.iconSize, root.iconSize)
                fillMode: Image.PreserveAspectFit
                smooth: true
                visible: false
            }

            Rectangle {
                id: assetFill
                anchors.fill: parent
                color: root.iconColor
                visible: false

                Behavior on color { ColorAnimation { duration: Motion.respond } }
            }

            MultiEffect {
                anchors.fill: parent
                source: assetFill
                maskEnabled: true
                maskSource: assetMask
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1.0
            }
        }
    }

    Text {
        id: labelText
        visible: root.label !== "" && root.glyph === "" && String(root.icon) === ""
        anchors.centerIn: parent
        text:  root.label
        color: root.iconColor
        font.family:    Tokens.fontFamily
        font.pixelSize: root.labelSize
        font.weight:    Font.Medium
        font.features:  ({ tnum: 1 })
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    Item {
        id: overlay
        anchors.fill: parent
        transform: Translate { x: magnet.offsetX; y: magnet.offsetY }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.interactive
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

        onClicked: function(m) {
            if (m.button === Qt.RightButton)       root.rightClicked()
            else if (m.button === Qt.MiddleButton) root.middleClicked()
            else                                   root.clicked()
        }
        onWheel: function(w) { root.scrolled(w.angleDelta.y > 0 ? 1 : -1) }

        // The wave starts where the pointer actually went down. `onCanceled` matters
        // as much as `onReleased`: dragging off the button (or the compositor taking
        // the grab) never fires a release, and without this the wave would sit at
        // full strength until the next press.
        onPressed:  function(m) { ripple.press(m.x, m.y) }
        onReleased: ripple.release()
        onCanceled: ripple.release()
    }
}
