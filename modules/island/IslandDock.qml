import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/island.js" as Rules
import "../../config/islands.js" as Islands

// ── IslandDock ────────────────────────────────────────────────────────────────
// The island: a handle on the bar's lower edge that opens a card when the pointer rests on it (or on a click,
// `Config.islandOpenBy`). The card is the same lobe growing out of the handle on springs.
//
//     Settings › Desktop › Island        qs ipc -c ~/.config/quicktest call island toggle | show media
//
// ── Six of them ───────────────────────────────────────────────────────────────
// The bar hangs one at its left, its middle and its right, and three more stand on the screen's bottom edge
// (`island`: config/islands.js SIDES; `side` is where along the edge, `bottom` which edge): the same handle,
// lobe, rail and size, each with its own pages (UiState.islandPagesOf). Each opens on its own; UiState.openIsland
// decides what it closes (in a row the middle is alone, the two sides may be open together). A bar button opens
// its panel's island pinned (UiState.togglePanel), a sidebar button its page's (UiState.openSidePanel). Only the
// top middle one has the live handle.
//
// ── The bottom row ────────────────────────────────────────────────────────────
// The same island turned over: the handle on the screen's bottom edge, the card standing on the frame's bottom
// strip (or a sidebar's face on that edge) and growing UP. While the other row has pages, a card is fitted into
// its half of the screen (`fitScale`), so a top and a bottom island never meet.
//
// ── Where it lives ────────────────────────────────────────────────────────────
// In the BAR's window, like WorkspaceGlance and PillTip, because the blob only blends pixels inside one
// Qt Quick scene graph. Welded (`welded`: the blob owns the bar's fill) the surface is a lobe of the bar's
// own material (`island*` in BlobBarLayer): the join, its fillets and the outline are the blob's. Its lobes
// do not deform (BlobBarLayer says why), so `deformMatrix` is the identity; it stays wired in case they do
// again. Not welded (a floating bar, no plugin) it is an ordinary card a hair under the bar.
//
// ── The live handle ───────────────────────────────────────────────────────────
// At rest the handle is a thin line, unless something is going on (Rules.subject): a recording, and with
// `Config.islandLive` a running timer or a song playing. Then the lobe hangs out of the bar as a small pill
// (IslandPill) that says so, and opening grows THAT lobe into the card; closing shrinks the card back into it.
// Opened from a song, the card lands on Media (`Config.islandFollow`, the opening's `page` in UiState.openIsland; only when Media is on this island's rail). A click on a
// recording's pill stops the recording.
//
// The input region is the lobe while it is out (`maskItem`); the line is on the bar strip, which the window
// already takes. Rest the pointer for `Config.islandDelay` and the card opens; leave for `Config.islandLinger`
// and it goes (a pin keeps it). Opened by key there is no pointer yet, so it waits until the pointer has been
// in once, or 3 s.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: dock

    // The bar's own screen.
    required property var forScreen
    // Which island this is (config/islands.js SIDES).
    property string island: "center"
    // Where along its edge it stands ("left" | "center" | "right"), and on which edge. The top middle one hangs
    // where Config.islandAlign puts it; the bottom middle one stands in the middle.
    readonly property string side: Islands.hOf(dock.island)
    readonly property bool atBottom: Islands.rowOf(dock.island) === "bottom"
    readonly property string align: dock.island === "center" ? Config.islandAlign : dock.side === "center" ? "centre" : dock.side
    // Bar.qml's `blobRing`: only a welded bar has a lobe to melt out of.
    property bool welded: false
    property matrix4x4 deformMatrix
    // The bar's underside, in this window's coordinates.
    property real dockInner: Config.belowBar
    // How far in from the window's edge a sidebar stands there (its face): the card keeps clear of it by a
    // blob's reach so the two don't weld.
    property real clearLeft: 0
    property real clearRight: 0
    // The bottom row: how far up from the screen's bottom a sidebar's face stands there (0 = no sidebar on
    // that edge); the card stands on it.
    property real bottomFace: 0

    // The card is opening, and the size and centre it is opening to (Bar.qml runs the rim out to it).
    signal cardOpened(real cx, real top, real w, real h)

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property string screenName: dock.forScreen?.name ?? ""
    readonly property real margin: Tokens.spacingXxl
    readonly property real handleH: 5

    // ── What is on show ───────────────────────────────────────────────────────
    readonly property bool isOpen: UiState.islandIsOpen(dock.island)
    ScreenOwner {
        id: owner
        screen: dock.forScreen
        open: dock.isOpen
    }
    readonly property string openScreen: UiState.islandScreenOf(dock.island)
    readonly property bool mine: dock.openScreen !== "" ? dock.openScreen === dock.screenName : owner.owns
    // An island every page was moved off has nothing to open, and no handle.
    readonly property bool present: Config.island && UiState.islandPagesOf(dock.island).length > 0
    readonly property bool allowed: dock.present && !UiState.arrange
    readonly property bool cardOpen: dock.allowed && dock.isOpen && dock.mine
    readonly property bool shown: dock.cardOpen
    readonly property bool recording: Clips.recording

    // What the handle says at rest ("" = the plain line), and the pill that says it.
    readonly property string subject: dock.allowed && dock.island === "center"
        ? Rules.subject({ recording: dock.recording, timer: Timers.timerRunning, playing: MusicPulse.playing, live: Config.islandLive })
        : ""
    // A plain panel open where this one hangs has the spot: the pill goes back into the bar until
    // it closes.
    readonly property bool spotTaken: dock.align === "left"  ? UiState.leftKey  !== ""
                                    : dock.align === "right" ? UiState.rightKey !== ""
                                    : UiState.centerKey !== "" || UiState.launcherOpen || UiState.updateOpen
    readonly property bool pillOn: dock.subject !== "" && !dock.spotTaken
    // Held through the pill's own fade, so it never empties as it goes.
    property string pillSubject: ""
    onSubjectChanged: if (dock.subject !== "") dock.pillSubject = dock.subject
    Component.onCompleted: dock.pillSubject = dock.subject

    // The surface's contents: "card" or "" (nothing). Held through the fade out.
    property string face: ""
    // This island's options: its own where Settings › Desktop › Island overrides one, else the shared one.
    function opt(name) { return UiState.islandOpt(dock.island, name) }
    readonly property real cardScale: dock.opt("scale")

    // Opened by the pointer (a rest or a click): on this screen, and on the page the pill speaks of.
    function openHere(pin) {
        UiState.openIsland(dock.island, {
            screen: dock.screenName,
            page: Config.islandFollow ? Rules.pageFor(dock.subject, UiState.islandPagesOf(dock.island)) : "",
            pinned: pin
        })
    }

    // ── The pointer ───────────────────────────────────────────────────────────
    // On the handle's reach or on the surface. Two handlers, each on an item the contents sit INSIDE or
    // that has none, so a button in the card doesn't take the hover from either.
    readonly property bool pointerOn: reachHover.hovered || surfHover.hovered
    // The pointer has been on the island since it opened. A key opens it with no pointer there yet.
    property bool armed: false
    // Closed by something other than the pointer leaving, with the pointer still on the handle: it must
    // leave before the handle opens it again.
    property bool held: false

    onCardOpenChanged: {
        if (dock.cardOpen) {
            esc.claim()
            dock.face = "card"
            dock.armed = dock.pointerOn
            if (!dock.armed) grace.restart()
            dock._light = true
        } else {
            grace.stop()
            dock.held = dock.pointerOn
            if (dock.held) heldClear.restart()
        }
    }
    // The card's size is known once its contents have loaded: then the rim can be told where to run.
    property bool _light: false
    onWantHChanged: {
        if (!dock._light || dock.face !== "card" || dock.wantH <= 1) return
        dock._light = false
        if (dock.welded) dock.cardOpened(dock._x(dock.wantW) + dock.wantW / 2, dock.joinY, dock.wantW, dock.wantH)
    }
    Timer { id: grace; interval: 3000; onTriggered: dock.armed = true }
    Timer { id: heldClear; interval: 900; onTriggered: if (!dock.pointerOn) dock.held = false }

    Timer {
        interval: dock.opt("delay")
        // Not while opening this one would close a plain panel or a pinned island (UiState.islandBlocked): a
        // pointer resting here on its way past must not do that. A click still does.
        running: dock.opt("openBy") !== "click" && dock.pointerOn && !dock.cardOpen && !dock.held && dock.allowed
                 && !UiState.islandBlocked(dock.island, dock.screenName)
        onTriggered: dock.openHere(false)
    }
    Timer {
        interval: dock.opt("linger")
        running: dock.cardOpen && dock.armed && !dock.pointerOn && !UiState.islandIsPinned(dock.island)
        onTriggered: UiState.closeIsland(dock.island)
    }
    onPointerOnChanged: {
        if (dock.pointerOn) { if (dock.cardOpen) dock.armed = true }
        else dock.held = false
    }

    // ── The keys ──────────────────────────────────────────────────────────────
    // Escape closes it, after the page on show has had its say (a panel may leave a sub-view first:
    // handleEscape() true = it used the key); any other key is the page's (handleKey(event)). The
    // bar's window gives the keyboard on demand, so this reaches a card a click opened or landed in.
    readonly property bool wantsKeyboardFocus: dock.cardOpen
    // The page needs typing that no click has given it yet (System update's password or a run's question): the
    // bar's window then takes the exclusive grab, only for as long as the page asks.
    readonly property bool wantsExclusive: dock.cardOpen && (cardL.item?.page?.wantsExclusiveKeyboard ?? false)
    EscapeGuard {
        id: esc
        wanted: dock.cardOpen
        onKeyPressed: (event) => {
            const it = cardL.item?.page
            if (it && it.handleKey) event.accepted = it.handleKey(event) === true
        }
        onEscaped: {
            const it = cardL.item?.page
            if (it && it.handleEscape && it.handleEscape() === true) return
            UiState.closeIsland(dock.island)
        }
    }

    // ── How tall it may grow ──────────────────────────────────────────────────
    // The whole screen past the bar (or above the bottom edge) while the other row has no islands; its share
    // while it has, so a top and a bottom card can never meet (the user's pick, 2026-11-15). Not halves: the
    // top row holds the tall pages (Game Mode, the clock), the bottom row's are built to fit its 45%.
    readonly property real screenH: dock.forScreen?.height ?? 1080
    readonly property bool shareHeight: UiState.islandRowPresent(dock.atBottom ? "top" : "bottom")
    readonly property real ownInset: dock.atBottom ? dock.baseInset : dock.dockInner
    readonly property real share: dock.atBottom ? 0.45 : 0.55
    readonly property real room: dock.shareHeight ? dock.screenH * dock.share - dock.ownInset - Tokens.spacingSm
                                                  : dock.screenH - dock.ownInset - Tokens.spacingXxl * 2
    // The tallest a panel's page may be: that room at the card's scale, less the card's gutters.
    readonly property real maxBodyH: Math.max(Rules.BODY.today.h, dock.room / dock.cardScale - Tokens.spacingXl * 2)
    // A page with a fixed size taller than the room (on a short screen) is shown a little smaller whole,
    // never cropped. Never touches maxBodyH, so the two can't chase each other.
    readonly property real fitScale: {
        const natural = cardL.implicitHeight * dock.cardScale
        return natural > dock.room && natural > 0 ? Math.max(0.6, dock.room / natural) : 1
    }
    readonly property real shownScale: dock.cardScale * dock.fitScale

    // ── The animation numbers ─────────────────────────────────────────────────
    // `rv` 0 → 1 as the card shows, on the spatial spring with its overshoot taken out (damping 1: a card
    // this big that overshoots by a percent bounces by several pixels, which reads as a wobble). The box does
    // not chase its target directly: it chases a point travelling from where it rests (the line, the pill) to
    // the card's size WITH `rv`, on a stiffer spring. One spring starts with its hardest push, which is what
    // read as abrupt; two in a row start gently, speed up and settle (an S curve), and the timeline is rv's.
    readonly property var boxSpec: ({ stiffness: Motion.springSpatial.stiffness, damping: 1.0 })
    readonly property var followSpec: ({ stiffness: Motion.springSpatialFast.stiffness, damping: 1.0 })
    SpringValue {
        id: rv
        target: dock.shown ? 1 : 0
        spec: dock.boxSpec
        epsilon: 0.002
        // Also on the value: with animations off nothing ever "moves", the value just lands.
        onValueChanged: if (!dock.shown) dock._drop()
        onMovingChanged: dock._drop()
    }
    // The card is unloaded once the lobe has come to rest, never while it is still shrinking: tearing a page
    // down takes a frame or two, and taken out of the middle of the movement that was a hitch in its tail.
    function _drop() {
        if (!dock.shown && !rv.moving && !sw.moving && !sh.moving && rv.value < 0.01) dock.face = ""
    }
    // What the contents show of themselves. In, they come up once the box is a third of the way open, so
    // the card unfolds around them. Out, they go at once and fast, BEFORE the box shrinks: left to follow it
    // they were cropped by it, line by line, and only then faded. (Tied to `rv` they still were: the box had
    // lost a quarter of its height with the page at 30%. Now it has lost a twentieth by 15%.) A spring
    // carries it, so reopening mid-close does not jump.
    SpringValue {
        id: ca
        target: dock.shown ? Math.max(0, Math.min(1, (rv.value - 0.35) / 0.5)) : 0
        spec: dock.shown ? Motion.springEffects : Motion.springEffectsFast
        epsilon: 0.002
    }

    readonly property real wantW: dock.face === "card" ? cardL.implicitWidth * dock.shownScale : 0
    readonly property real wantH: dock.face === "card" ? cardL.implicitHeight * dock.shownScale : 0
    readonly property real pillW: pillL.item ? pillL.item.implicitWidth : handleBox.w
    readonly property real pillH: dock.pillOn && pillL.item ? pillL.item.implicitHeight : 0
    // 0 → 1 as the pill shows (the card's `reveal` takes it back out while the card is open).
    SpringValue {
        id: pv
        target: dock.pillOn ? 1 : 0
        spec: Motion.springSpatial
        epsilon: 0.002
        onValueChanged: if (!dock.pillOn && pv.value < 0.01) dock.pillSubject = ""
    }
    // A side island opens at its full width at once and only grows down: its lobe is a panel on the
    // frame, not a pill that swells.
    // Where the width rests with nothing open, and where it starts the card from.
    readonly property real startW: dock.pillOn ? dock.pillW : dock.side !== "center" ? dock.restW : handleBox.w
    SpringValue {
        id: sw
        target: dock.startW + (dock.wantW - dock.startW) * Math.max(0, Math.min(1, rv.value))
        spec: dock.followSpec
        epsilon: 0.2
        onMovingChanged: dock._drop()
    }
    property real restW: dock.cardGuess
    onWantWChanged: if (dock.wantW > 1) dock.restW = dock.wantW
    // Where the open card stands along the edge, for UiState's side-by-side check (two side islands whose
    // cards would meet are one or the other).
    readonly property real spanX0: dock._x(dock.restW)
    function _reportSpan() { if (dock.screenName !== "") UiState.islandSpan(dock.island, dock.screenName, dock.spanX0, dock.spanX0 + dock.restW) }
    onSpanX0Changed: dock._reportSpan()
    onRestWChanged: dock._reportSpan()
    onWidthChanged: dock._reportSpan()
    SpringValue {
        id: sh
        target: dock.pillH + (dock.wantH - dock.pillH) * Math.max(0, Math.min(1, rv.value))
        spec: dock.followSpec
        epsilon: 0.2
        onMovingChanged: dock._drop()
    }
    // The lobe's corners: a pill's round ends at rest, the card's corner once it is taller than that.
    readonly property real lobeRadius: Math.min(Tokens.radiusCard, sh.value / 2)

    // ── Where along the bar ───────────────────────────────────────────────────
    // The middle island hangs free (Config.islandAlign). A side island is the bar's panel on that side:
    // welded, it stands ON the frame's strip or the sidebar's face, so the blob melts it out of the corner
    // the two make; free, it keeps the usual margin off them.
    readonly property bool hugFrame: dock.welded && Config.frameFused && Config.screenFrame
    function _inset(face) {
        return face > 0 ? face + (dock.welded ? 0 : dock.margin)
             : dock.hugFrame ? Config.frameDepth : dock.margin
    }
    // The bottom row: how far up from the screen's bottom the card stands (on the sidebar's face there, the
    // frame's strip, or a margin), and the line the card joins (the bar's underside, or that base).
    readonly property real baseInset: dock._inset(dock.bottomFace)
    readonly property real joinY: dock.atBottom ? dock.screenH - dock.baseInset : dock.dockInner
    // The card's width before it has loaded (the rail, the Dashboard's body, the gutters): where a
    // side island's handle stands is the middle of the card it opens.
    readonly property real cardGuess: (Tokens.iconXl + Tokens.spacingXl + Tokens.spacingSm * 2 + Tokens.spacingMd
                                       + Rules.BODY.today.w + Tokens.spacingXl * 2) * dock.cardScale
    function _handleX(w) {
        if (dock.side === "left")  return dock._inset(dock.clearLeft) + (dock.cardGuess - w) / 2
        if (dock.side === "right") return dock.width - dock._inset(dock.clearRight) - (dock.cardGuess + w) / 2
        return dock._x(w)
    }
    function _x(w) {
        if (dock.side === "left")  return dock._inset(dock.clearLeft)
        if (dock.side === "right") return dock.width - dock._inset(dock.clearRight) - w
        return Rules.placeX(dock.align, w, dock.width, dock.margin,
                            dock.clearLeft  > 0 ? dock.clearLeft  + Morph.smoothing : 0,
                            dock.clearRight > 0 ? dock.clearRight + Morph.smoothing : 0)
    }

    // ── The handle ────────────────────────────────────────────────────────────
    // The plain line, on the bar's TOP edge (the bottom row: on the screen's bottom edge): a thin pill at rest
    // (the island's `handle` option long), a little bigger under the pointer. The card still melts out of the
    // bar's underside (the bottom row: out of the base it stands on).
    readonly property real barTop: Math.max(0, dock.dockInner - Config.barSurfaceHeight)
    Item {
        id: handleBox

        readonly property real rest: Math.max(Tokens.spacingXl, dock.opt("handle"))
        readonly property real w: dock.pointerOn ? handleBox.rest + Tokens.spacingXl : handleBox.rest
        readonly property real h: dock.pointerOn ? dock.handleH + 1 : dock.handleH
        width: handleBox.w
        height: handleBox.h
        x: dock._handleX(handleBox.w)
        y: dock.atBottom ? dock.screenH - handleBox.h - 1 : dock.barTop + 1
        opacity: (1 - rv.value) * (1 - pv.value)
        visible: opacity > 0.01 && dock.present

        Behavior on width  { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on height { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: dock.palette.alpha(dock.palette.fg, dock.pointerOn ? 0.7 : 0.42)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        MouseArea {
            anchors.fill: parent
            anchors.margins: -Tokens.spacingXs
            cursorShape: Qt.PointingHandCursor
            // Opening by hover, a click keeps it open; opening by click, the click is the opening.
            onClicked: dock.openHere(dock.opt("openBy") !== "click")
        }
    }

    // Where the pointer counts as "on the handle": its reach, which stays put while the handle swells
    // under it. The bar's strip already takes the pointer there.
    Item {
        id: reach
        x: handleBox.x - 14
        y: handleBox.y - 8
        width: handleBox.w + 28
        height: handleBox.h + 16
        visible: dock.present && !dock.pillOn
        HoverHandler { id: reachHover }
    }

    // ══ Read by Bar.qml ═══════════════════════════════════════════════════════
    // The card is out and wanted: what lights the cookie field in its material.
    readonly property bool lit: dock.welded && dock.shown && sh.value > 1
    readonly property Item maskItem: maskBox
    // The bottom row's handle is on no strip this window already takes the pointer on: its reach is.
    readonly property Item handleMask: dock.atBottom && reach.visible ? reach : null
    // The lobe, welded only; 0 while nothing is out.
    readonly property bool _lobe: dock.welded && sh.value > 1
    readonly property real blobX: dock._lobe ? surf.x : 0
    readonly property real blobY: dock._lobe ? (dock.atBottom ? surf.y + surf.height + dock.tuck - dock._blobH : surf.y - dock.tuck) : 0
    readonly property real blobW: dock._lobe ? surf.width  : 0
    readonly property real blobH: dock._lobe ? dock._blobH : 0
    // In whole pixels. The plugin redraws a shape whose SIZE changed by more than half a pixel in one step
    // (blobshape.cpp geometryChange; only a change of position is summed up), so a lobe growing slower than that
    // was not redrawn at all: a side island's stopped some 4 px short at 165 Hz and stayed there until
    // something else redrew the group, and closing it sat at its last pixels and then vanished. The deform
    // used to hide this (it redraws every frame while it swings); with it off, a whole-pixel step always
    // counts. The bottom row keeps the edge it stands on fixed and steps the other.
    readonly property real _blobH: Math.round(surf.height + dock.tuck - dock.tuckLag)
    // The lobe comes OUT of the strip it hangs from; it does not appear on it. A blob rect whose edge lies on
    // the frame's inner edge already bulges it by a few pixels (blob.frag: the circular smin of two parallel
    // edges), so a lobe that began there popped out in one frame and, closing, crept down to a pixel and then
    // snapped away. The rect starts `tuck` inside the strip instead, where it changes nothing, and its far edge
    // catches the surface up over the first `Morph.smoothing` of travel (`tuckLag`), so the swell grows from
    // nothing. 0.27 of the smoothing: past a quarter (the reach of the shader's 4x boost beside the frame),
    // short of 0.29 (where the frame's wall starts to give way to a rect inside it: `preOff`). Only on the
    // frame's ring: a card on a sidebar's face or standing free has no strip to come out of.
    readonly property real tuck: dock.welded && (!dock.atBottom || (dock.hugFrame && dock.bottomFace <= 0))
        ? Morph.smoothing * 0.27 : 0
    readonly property real tuckLag: {
        const left = 1 - Math.max(0, Math.min(1, sh.value / Morph.smoothing))
        return dock.tuck * left * left
    }

    // The input region: the lobe (the pill or the card) while it is out, nothing otherwise.
    Item {
        id: maskBox
        x: surf.x
        y: surf.y
        width:  sh.value > 1 ? surf.width  : 0
        height: sh.value > 1 ? surf.height : 0
    }

    // ══ The surface ═══════════════════════════════════════════════════════════
    Surface {
        id: surf
        x: dock._x(sw.value)
        y: dock.atBottom ? dock.joinY - sh.value - (dock.welded ? 0 : Tokens.spacingXs)
                       : dock.dockInner + (dock.welded ? 0 : Tokens.spacingXs)
        width: sw.value
        height: sh.value
        visible: sh.value > 1

        // Welded it is the bar's material, drawn by the blob (fill and cookie field alike): no fill, outline
        // or shadow of its own. Free it is a popup.
        radius: dock.lobeRadius
        elevation: Tokens.elevationPopup
        castsShadow: !dock.welded
        borderWidth: dock.welded ? 0 : Tokens.borderWidth
        // Free, it fades in over its first corner's worth of height so a sliver doesn't flash.
        itemOpacity: dock.welded ? 1 : Tokens.surfaceOpacity * Math.min(1, sh.value / (Tokens.radiusCard * 2))
        transform: Matrix4x4 { matrix: dock.welded ? dock.deformMatrix : Qt.matrix4x4() }
        Binding {
            target: surf
            property: "color"
            when: dock.welded
            value: Drift.inBlob ? "transparent" : dock.palette.frameFill
        }

        // What it holds, clipped to the size it has grown to and centred, so the card unfolds rather than slides.
        Item {
            anchors.fill: parent
            clip: true

            // The pill: gone as the card comes in, back as it leaves. A click stops a recording, else opens.
            Loader {
                id: pillL
                active: dock.pillSubject !== ""
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                opacity: Math.min(pv.value, 1 - Math.min(1, rv.value * 2.5))
                visible: opacity > 0.01
                sourceComponent: IslandPill {
                    subject: dock.pillSubject
                    live: dock.pillOn && !dock.shown
                }
                MouseArea {
                    id: pillPress
                    anchors.fill: parent
                    enabled: dock.pillOn && !dock.shown
                    cursorShape: Qt.PointingHandCursor
                    function press() {
                        if (dock.subject === "record") Clips.toggleRecord()
                        else dock.openHere(dock.opt("openBy") !== "click")
                    }
                    onClicked: pillPress.press()
                    Accessible.role: Accessible.Button
                    Accessible.name: dock.subject === "record" ? Translation.tr("Stop recording") : Translation.tr("Island")
                    Accessible.onPressAction: pillPress.press()
                }
            }

            // Built at its own size and scaled whole (the island's `scale` option) from the middle of the edge it
            // grows from (the top; the bottom row's: the bottom).
            Loader {
                id: cardL
                active: dock.face === "card"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: dock.atBottom ? undefined : parent.top
                anchors.bottom: dock.atBottom ? parent.bottom : undefined
                width: implicitWidth
                // A little under full size while it is not there, so it settles into place, and recedes as it goes.
                scale: dock.shownScale * (0.95 + 0.05 * Math.max(0, ca.value))
                transformOrigin: dock.atBottom ? Item.Bottom : Item.Top
                opacity: Math.max(0, Math.min(1, ca.value))
                sourceComponent: IslandCard {
                    side: dock.island
                    reveal: rv.value
                    maxBodyH: dock.maxBodyH
                }
            }
        }

        // An ancestor of everything in it, so a button inside doesn't take the hover.
        HoverHandler { id: surfHover }
    }
}
