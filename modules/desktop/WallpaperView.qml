pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../services"
import "../../components"

// ── WallpaperView ─────────────────────────────────────────────────────────────
// The static wallpaper, drawn by the shell, one surface per screen — the piece
// that lets the picture move. It replaces handing the image to the awww daemon
// (see scripts/apply-wallpaper.sh, --no-daemon); flip Config.wallShellRender off
// to go back to awww and this surface hides itself.
//
// ── Parallax ──────────────────────────────────────────────────────────────────
// Same idea as nucleus-shell's Background.qml: the picture is scaled past the
// screen edge (Config.wallParallaxZoom) and the surplus is panned —
//   · horizontally by the focused workspace, 1→10 sweeping the image left→right;
//   · by a small drift toward the pointer (Config.wallParallaxMouse), read from
//     the Pointer service because a background-layer surface can't see the mouse
//     without eating desktop clicks.
// zoom 1.0 means no surplus, so nothing moves — that's the "off" state.
//
// ── Layer ─────────────────────────────────────────────────────────────────────
// `Background`, below CavaBG / WidgetLayer / DesktopClock (all on `Bottom`) and
// below every window. A Wallpaper Engine scene renders on `background` too and
// maps after us, so when one is running we just hide — no map-order fight.
//
// ── The black hold ────────────────────────────────────────────────────────────
// `color: "black"` shows for the frame before the first decode, and during a
// shell reload there's a brief black flash where awww used to persist a picture.
// Accepted, like nucleus accepts it; awww stays available for anyone who minds.
//
// ── Game Mode takeover ────────────────────────────────────────────────────────
// While Gamemode holds the scene stopped, painting whatever static image happens
// to be on file (Wallpaper.currentPath — often just the last thing picked, not
// anything to do with gaming) reads as "the wallpaper changed at random". A
// dedicated card instead: says plainly why the screen looks different and to
// whom it's answering. Gated on Gamemode.wallpaperPaused specifically, not on
// "nothing is running" — a user with no scene at all, or one paused by hand
// outside gamemode, must still see their real wallpaper untouched.
//
// ── The water ─────────────────────────────────────────────────────────────────
// A new wallpaper arrives as water from the bottom middle (services/WallWave.qml),
// on the same front as the shell's new colours. It is drawn HERE, not in a window of
// its own, because this surface already owns the picture's framing — the parallax
// zoom and pan — so the water is the settled wallpaper from its first pixel and
// hands over with no jump. When someone else draws the wallpaper (awww, or a scene
// still running under a change to a still) this surface maps for the change alone,
// see-through, carries the water over theirs, and lets go once theirs is in place.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    required property var modelData
    screen: root.modelData

    WlrLayershell.layer:         WlrLayer.Background
    WlrLayershell.namespace:     "quickshell-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    anchors { top: true; bottom: true; left: true; right: true }
    // Black under a picture this surface draws; see-through while it carries only the
    // water over a wallpaper someone else draws.
    color: root.waterOnly ? "transparent" : "black"

    // Never intercept input — the cursor is read through Pointer, not from here.
    mask: Region {}

    // ── When the shell owns the picture ───────────────────────────────────────
    // `probed` gates the reload case: a Wallpaper Engine scene is detached and
    // survives a shell reload, but `WallpaperEngine.running` reads false until the
    // first pgrep returns. Painting the last still image in that gap is exactly
    // the "scene gets replaced then reapplied" flash — so wait for a real answer.
    // With workspaces wearing their own wallpapers (scenes included), it's per SCREEN:
    // this one draws its picture unless the renderer is covering it with the scene meant
    // for it — so a picture workspace shows its picture beside a scene on the other
    // monitor, and a scene loading here keeps its still up until it has really mapped.
    readonly property string screenName: root.modelData?.name ?? ""
    readonly property bool sceneHere: WallpaperEngine.wsMode
        ? (WallpaperEngine.sceneOn(root.screenName) !== "" && WallpaperEngine.coversScreen(root.screenName))
        : WallpaperEngine.layerUp
    readonly property bool shellDraws:
        Config.wallShellRender && WallpaperEngine.probed && !root.sceneHere
    // The pictures workspaces wear (scenes that play from a window aren't pictures).
    readonly property var preloadSources: {
        if (!Wallpaper.perWorkspace || !root.shellDraws) return []
        const out = []
        for (let n = 1; n <= Wallpaper.pickable; n++) {
            const own = Wallpaper.wallFor(n)
            if (own === "" || Wallpaper.sceneOf(own) !== "") continue
            const p = Wallpaper.pictureFor(n)
            if (p !== "" && out.indexOf(p) < 0) out.push(p)
        }
        return out.slice(0, 10)
    }
    // This screen's workspace's picture: its own when it has one (Wallpaper's per-
    // workspace wallpapers), the shared one otherwise. A switch is _load()'s crossfade.
    // A scene that plays from a window of its own waits on ITS still, not the last picture.
    readonly property string src: root.liveId !== "" ? Wallpaper.displayOf("scene:" + root.liveId)
                                                       || Wallpaper.pictureFor(root.wsId)
                                                     : Wallpaper.pictureFor(root.wsId)
    // ── A scene that plays from a window of its own ───────────────────────────
    // A workspace's scene, kept running (services/ScenePreload): this surface draws a live
    // capture of its window over the scene's still, which stays under it until the first
    // frame (or for good, if the scene never gets going). A switch between two such
    // scenes is a swap of capture, not a load.
    // A workspace's own scene, else the shared one when it plays from a window too
    // (WallpaperEngine.windowShared) — a workspace with a PICTURE of its own shows that.
    readonly property string liveId: {
        const own = Wallpaper.perWorkspace ? Wallpaper.wallFor(root.wsId) : ""
        return own !== "" ? Wallpaper.sceneOf(own) : WallpaperEngine.windowSceneOn(root.screenName)
    }
    readonly property var liveTop:
        (root.liveId !== "" && ScenePreload.usable(root.liveId)) ? (ScenePreload.windows[root.liveId] ?? null) : null
    // A fullscreen window over this screen hides the wallpaper entirely: the live capture
    // has nothing to show for the 60 frames a second it would import. It pauses (the last
    // frame stays up) and picks up again when the window leaves.
    readonly property bool covered: Fullscreen.byMonitor[root.screenName] === true

    // Just after the shell starts, a scene this screen's workspace expects may not be
    // captured yet (its renderer is being found, or still loading): hold what is shown —
    // black, at a reload — rather than flash the scene's still. Ends when it arrives, or
    // when ScenePreload gives up waiting.
    readonly property bool liveWait:
        root.liveId !== "" && !root.liveTop && ScenePreload.settling && ScenePreload.expects(root.liveId)

    // Gamemode sets `wallpaperPaused` the instant it decides to stop or restore
    // the scene — synchronous, unlike `shellDraws` above, which depends on
    // WallpaperEngine's OWN probe catching up (pkill → poll the process is
    // actually gone → a further pgrep to confirm). Gating the card on shellDraws
    // too reopened exactly the gap it exists to cover: for however long that
    // probe chain takes, NEITHER the scene NOR this surface owns the background
    // layer, and Hyprland's own compositor-level default shows through.
    readonly property bool gameCard: Config.wallShellRender && Gamemode.wallpaperPaused
    // Up for a change's water even when this surface isn't the renderer.
    property bool waterUp: false
    readonly property bool waterOnly: root.waterUp && !root.shellDraws && !root.gameCard
    // Material Wallpaper: drawn in place of the picture, by whoever draws pictures — and never
    // over a scene, which has the screen when one is playing.
    readonly property bool materialOn:
        Config.wallMaterial && root.shellDraws && !root.gameCard && root.liveId === ""
    // The depth clock (Config.wallDepth): a picture only — never over a scene, the Material
    // Wallpaper or the game card — and not while a change's water holds the screen, because the
    // water brings the NEW picture in from the bottom and a clock for it would sit over the old one.
    readonly property bool depthOn:
        Config.wallDepth && root.shellDraws && !root.gameCard && !root.materialOn
        && root.liveId === "" && !root._watered && root.src !== ""
    // `_remap`: unmapped for a moment so the compositor maps it again, above the fallback's daemon
    // (see MaterialFallback). Over a daemon showing the same still, so nothing is seen to happen.
    property bool _remap: false
    visible: !root._remap && (root.gameCard || (root.shellDraws && root.src !== "") || root.waterUp
        || root.materialOn || material.opacity > 0)

    // ── The still for the fallback ────────────────────────────────────────────
    readonly property bool stillWanted:
        root.materialOn && Config.wallMaterialFallback && MaterialFallback.blocker() === ""
    onStillWantedChanged: if (root.stillWanted) stillTimer.restart()
    function _saveStill() {
        const m = material.item
        if (!root.stillWanted || !m || root.width <= 0 || root.screenName === "" || !MaterialFallback.dirReady) return
        const path = MaterialFallback.pathFor(root.screenName)
        m.snapshot(function (result) {
            // Physical pixels, so awww has nothing to scale.
            if (result.saveToFile(path)) MaterialFallback.publish(root.screenName, path)
            else console.warn("WallpaperView: could not save the Material Wallpaper still to", path)
        }, Qt.size(Math.round(root.width * root._dpr), Math.round(root.height * root._dpr)))
    }
    Connections {
        target: MaterialFallback
        // The still folder exists now: the one that was held back can be written.
        function onDirReadyChanged() { if (MaterialFallback.dirReady && root.stillWanted) stillTimer.restart() }
        function onRemap() {
            if (!root.stillWanted) return
            root._remap = true
            remapTimer.restart()
        }
    }
    Timer { id: remapTimer; interval: 120; onTriggered: root._remap = false }

    // ── Parallax inputs ───────────────────────────────────────────────────────
    // Only when the shell renders the wallpaper. With awww this surface is up only to
    // carry a change's water, and that water must frame the picture exactly as awww
    // will (centred, cropped, unzoomed) or it would shift as it hands over.
    //
    // Two switches, by what this screen is showing: a scene that plays from a window of its
    // own (ScenePreload) is drawn HERE, so it follows the Scene switch (Config.wpeParallax —
    // the same one the renderer reads for scenes it draws itself); a picture follows the
    // Image switch (Config.wallParallax). They used to be one, and the Image switch moved
    // scenes too, which left the Scene switch with nothing to do.
    readonly property bool sceneKind:
        root.liveId !== "" && ScenePreload.usable(root.liveId)
    readonly property bool parallaxOn:
        Config.wallShellRender && (root.sceneKind ? Config.wpeParallax : Config.wallParallax)
        && Config.wallParallaxZoom > 1.0
    // Where the framing is heading, and where it is now. Turning parallax on/off glides the
    // picture between the two (it used to jump); the decode size follows the TARGET, not the
    // glide, or every frame of it would ask for a new decode.
    readonly property real zoomTarget: root.parallaxOn ? Config.wallParallaxZoom : 1.0
    property real zoom: root.zoomTarget
    Behavior on zoom { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.travel } }

    // Horizontal fraction (0..1) from the focused workspace. monitorFor(modelData)
    // is the lookup WorkspacesPill uses; ?? 1 keeps a monitor with no active
    // workspace yet at the left rather than NaN.
    readonly property int  wsId:   Hyprland.monitorFor(root.modelData)?.activeWorkspace?.id ?? 1
    readonly property int  wsSpan: 10
    readonly property real wsFrac: (root.parallaxOn && Config.wallParallaxWorkspace)
        ? ((root.wsId - 1) % root.wsSpan) / (root.wsSpan - 1)
        : 0.5

    // Pointer drift. `wantPointer` gates the poll: no ref taken unless the effect
    // is visible and the strength is non-zero.
    readonly property real mouseAmt:    root.parallaxOn ? Config.wallParallaxMouse : 0
    readonly property bool wantPointer: root.visible && root.mouseAmt > 0

    readonly property real mnx: (root.wantPointer && Pointer.known && root.width > 0)
        ? Math.max(-0.5, Math.min(0.5, (Pointer.pos.x - root.modelData.x) / root.width  - 0.5))
        : 0
    readonly property real mny: (root.wantPointer && Pointer.known && root.height > 0)
        ? Math.max(-0.5, Math.min(0.5, (Pointer.pos.y - root.modelData.y) / root.height - 0.5))
        : 0

    // Final 0..1 pan position, workspace + pointer, clamped.
    readonly property real panX: Math.max(0, Math.min(1, root.wsFrac + root.mnx * root.mouseAmt))
    readonly property real panY: Math.max(0, Math.min(1, 0.5      + root.mny * root.mouseAmt))

    // Pixels of surplus on each side to pan within.
    readonly property real overflowX: root.width  * (root.zoom - 1) / 2
    readonly property real overflowY: root.height * (root.zoom - 1) / 2
    readonly property real tx: (0.5 - root.panX) * 2 * root.overflowX
    readonly property real ty: (0.5 - root.panY) * 2 * root.overflowY

    // ── Keeping it sharp ─────────────────────────────────────────────────────
    // Two things blur a panned wallpaper, and both are fixable:
    //   · the surface renders at width×dpr PHYSICAL pixels, so a sourceSize in
    //     logical units under-decodes on any scaled monitor — the picture is soft
    //     before it even moves. `_dpr` puts the decode back in physical pixels.
    //   · a translate of 0.37px resamples every texel bilinearly, all the time.
    //     `_snap` rounds the pan to a whole physical pixel so the texture lands
    //     1:1 whenever it's at rest.
    // What's left — upscaling a wallpaper smaller than screen×zoom — is physical;
    // a bigger picture or a lower zoom is the only answer to that.
    readonly property real _dpr: (root.modelData && root.modelData.devicePixelRatio > 0)
        ? root.modelData.devicePixelRatio : 1
    function _snap(v) { return Math.round(v * root._dpr) / root._dpr }

    // ── Pointer ref-count ─────────────────────────────────────────────────────
    property bool _held: false
    function _syncPointer() {
        if (root.wantPointer === root._held) return
        if (root.wantPointer) Pointer.acquire()
        else                  Pointer.release()
        root._held = root.wantPointer
    }
    onWantPointerChanged: root._syncPointer()
    Component.onDestruction: if (root._held) Pointer.release()

    // ── The picture, with a crossfade on change ───────────────────────────────
    // `prev` holds the outgoing image only long enough to fade out from under
    // `cur`. Both share the same zoom + translate so the swap doesn't jump.
    // `cur.source` is set imperatively, not bound: the swap has to read the OLD
    // value into `prev` first, and a binding would already have moved on.
    //
    // The crossfade is for a picture that changes WITHOUT a wave (a reload, animations
    // off, the game card). While a change's water is up, the water owns the picture:
    // the marker file (and so `src`) can be written before the front has crossed the
    // screen, and a crossfade under it would change the picture ahead of the water.
    // It catches up when the water hands over (_clearWater).
    //
    // Gated on `shellDraws`, not `visible`: this surface is also up to carry water
    // over a wallpaper it doesn't draw, and must not paint the old still under it.
    function _load() {
        if (root._watered) return
        // A scene with a frame ready (liveTop) is faded in OVER whatever is up, never over
        // its own still: hold the picture as it is until the scene leaves again.
        if (root.liveTop && root.shellDraws && !root.gameCard) return
        if (root.liveWait && root.shellDraws && !root.gameCard) return
        const want = (root.shellDraws && !root.gameCard && root.src !== "") ? "file://" + root.src : ""
        if (want === cur.source.toString()) return
        // Nothing to draw (a scene took over, or the game card): empty BOTH planes. Handing
        // the old picture to `prev` below would strand it there — `prev` only clears when
        // `cur` reports Ready, and an empty source never does — and the next time this
        // surface maps (a change's water over the scene) it would show that old picture
        // under the water: scene → image 2 flashed image 1 first.
        if (want === "") {
            prev.opacity = 0
            prev.source = ""
            cur.opacity = 0
            cur.source = ""
            return
        }
        // The hand-over (picture → picture): the outgoing one goes UNDER at full strength and
        // the incoming one starts invisible — both without animating, or the two fades run
        // against each other and the sum dips (75% at the midpoint: the dark background shows
        // through as a flicker). The incoming one then fades in over it (cur's status), and
        // the outgoing one is dropped once it can't be seen (clearPrev).
        clearPrev.stop()
        root._instant = true
        if (cur.source != "" && cur.opacity > 0) { prev.source = cur.source; prev.opacity = 1 }
        cur.opacity = 0
        root._instant = false
        cur.source = want
    }
    property bool _instant: false         // set an opacity without its Behavior
    Timer {
        id: clearPrev
        interval: Math.max(40, Motion.emphasized + 40)
        onTriggered: {
            root._instant = true
            prev.opacity = 0
            prev.source = ""
            root._instant = false
        }
    }
    // Deferred one turn: a workspace switch changes `src` AND `liveTop` in the same
    // breath, in no fixed order. Reacting to `src` first would see "no scene yet" and
    // start the scene's still fading in, which the scene then has to fade in over — the
    // still showing for a beat. After the turn, both have settled.
    onSrcChanged:        Qt.callLater(root._load)
    onVisibleChanged:    Qt.callLater(root._load)
    onGameCardChanged:   Qt.callLater(root._load)
    onLiveTopChanged:    { Qt.callLater(root._load); root._liveGone() }
    onLiveWaitChanged:   Qt.callLater(root._load)
    onShellDrawsChanged: root._shellDrawsChanged()
    Component.onCompleted: { root._syncPointer(); root._load(); if (root.stillWanted) stillTimer.restart() }

    // ── The water ─────────────────────────────────────────────────────────────
    // One slot per WallWave channel (token % 2), the newest on top: a second change
    // started while the first still spreads floods over it on its own clock. Each
    // slot is the new picture as a Plane — the same zoom, pan and decode size as
    // `cur` — drawn through shaders/wallwave.frag at its channel's progress.
    //
    // When the newest change settles (its picture in place under the water), the
    // water hands over. A change says whether this surface will DRAW the picture
    // from then on (WallWave.keep):
    //   · it will, and does already → `cur` adopts the picture (the same file at the
    //     same size: a pixmap-cache hit, so the swap is invisible), and the slots
    //     clear once it has drawn;
    //   · it will, but a scene is still being stopped under a change to a still →
    //     hold until it is gone, then adopt (Wallpaper stops the scene only once
    //     the water covers the screen, so there is never a gap);
    //   · it won't — awww draws it, or it was a scene's still and the scene is up
    //     over it → the water fades off whatever now shows.
    property bool _watered: false         // a slot holds a change's picture
    property bool _awaitRenderer: false   // landed over a scene that is going away
    property int  _topSlot: -1
    property string _adopting: ""

    function _startWave(token) {
        if (root.gameCard || WallWave.image === "") return
        if (WallWave.output !== "" && WallWave.output !== (root.modelData ? root.modelData.name : "")) return
        const ch = WallWave.channel(token)
        const s = slots.itemAt(ch)
        if (!s) return
        const under = (root._topSlot >= 0 && root._topSlot !== ch) ? slots.itemAt(root._topSlot) : null
        waterFade.stop()
        water.opacity = 1
        s.z = (under && under.token > 0 ? under.z : 0) + 1
        s.token = token
        s.keep = WallWave.keep
        s.load("file://" + WallWave.image, token)
        root._topSlot = ch
        root._watered = true
        root._awaitRenderer = false
        root.waterUp = true
    }

    function _settle() {
        if (!root._watered) return
        const top = slots.itemAt(root._topSlot)
        if (!top || top.token <= 0 || top.failed) { root._clearWater(); return }
        if (!top.keep)            waterFade.restart()
        else if (root.shellDraws && !root.liveTop) root._adopt(top.url)
        else                      { root._awaitRenderer = true; awaitGuard.restart() }
    }

    // A scene in a window of its own leaving (`liveTop`) ends the wait too: its capture is
    // drawn above the picture, so adopting before it is gone lets the scene show again
    // between the water clearing and the capture ending. (Not _load's deferred turn — only
    // the wait is released here.)
    function _liveGone() {
        if (!root.liveTop && root._awaitRenderer && root.shellDraws) root._shellDrawsChanged()
    }
    function _shellDrawsChanged() {
        if (root.shellDraws && !root.liveTop && root._awaitRenderer) {
            root._awaitRenderer = false
            awaitGuard.stop()
            const top = slots.itemAt(root._topSlot)
            if (top && top.token > 0 && !top.failed) { root._adopt(top.url); return }
            root._clearWater()
            return
        }
        root._load()
    }

    function _adopt(url) {
        root._adopting = url
        prev.opacity = 0
        prev.source = ""
        cur.opacity = 1
        if (cur.source.toString() === url && cur.status === Image.Ready) { root._adopted(); return }
        cur.source = url
    }
    function _adopted() {
        root._adopting = ""
        root._clearWater()
    }
    function _clearWater() {
        for (let i = 0; i < slots.count; i++) {
            const s = slots.itemAt(i)
            if (s) s.clear()
        }
        root._topSlot = -1
        root._watered = false
        root._awaitRenderer = false
        root._adopting = ""
        root.waterUp = false
        water.opacity = 1
        // Catch up with anything that changed while the water held the picture.
        root._load()
    }

    Connections {
        target: WallWave
        function onPrepared(token) { root._startWave(token) }
        function onSettledChanged() { if (WallWave.settled) root._settle() }
    }

    // A scene that never goes away (its stop refused mid-restart) must not leave
    // the water standing over the desktop: let it go, the scene shows.
    Timer {
        id: awaitGuard
        interval: 8000
        onTriggered: if (root._awaitRenderer) { root._awaitRenderer = false; waterFade.restart() }
    }

    // Letting go of water that sits over someone else's wallpaper.
    NumberAnimation {
        id: waterFade
        target: water; property: "opacity"; to: 0
        duration: Motion.exit
        easing.type: Motion.exitCurve
        onFinished: root._clearWater()
    }

    // One captured scene: the window's live frame, scaled to cover the box. It is only
    // opaque while it is `front` AND has a frame, so fading it in never shows black.
    component LiveSlot: Item {
        id: slot
        property var source: null
        property bool front: false
        property real boxW: 0
        property real boxH: 0
        property bool paused: false
        readonly property bool ready: view.hasContent
        anchors.fill: parent
        opacity: (slot.front && view.hasContent) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.emphasized } }
        ScreencopyView {
            id: view
            anchors.centerIn: parent
            readonly property real cover: Math.max(slot.boxW / Math.max(1, sourceSize.width),
                                                   slot.boxH / Math.max(1, sourceSize.height))
            width:  sourceSize.width  * cover
            height: sourceSize.height * cover
            live: !slot.paused
            paintCursor: false
            captureSource: slot.source
        }
    }

    // One picture plane: zoomed past the screen edge, panned within the surplus,
    // decoded at physical resolution. Used for both the outgoing and incoming
    // image so the crossfade can't shift.
    component Plane: Image {
        anchors.centerIn: parent
        width:  parent.width  * root.zoom
        height: parent.height * root.zoom
        fillMode: Image.PreserveAspectCrop
        // Decoded to the exact physical size it's shown at: Qt's decode-time
        // downscale is high quality, and it leaves the GPU sampling the texture
        // ~1:1 rather than minifying it every frame.
        sourceSize: Qt.size(Math.round(parent.width  * root.zoomTarget * root._dpr),
                            Math.round(parent.height * root.zoomTarget * root._dpr))
        smooth: true
        cache: true
        asynchronous: true
        // A new decode size (parallax toggled) must not blank the picture while it loads.
        retainWhileLoading: true
        opacity: 0

        transform: Translate {
            x: root._snap(root.tx)
            y: root._snap(root.ty)
            Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }
        // Not while water holds the picture: the hand-over to `cur` must be a
        // swap, not a fade the slots would clear in the middle of.
        Behavior on opacity {
            enabled: !root._watered && !root._instant
            NumberAnimation { duration: Motion.emphasized }
        }
    }

    Item {
        id: content
        anchors.fill: parent
        clip: true

        Plane { id: prev }

        Plane {
            id: cur
            onStatusChanged: {
                if (root._adopting !== "") {
                    if (status === Image.Ready)      root._adopted()
                    else if (status === Image.Error) root._clearWater()
                    return
                }
                if (status === Image.Ready) {
                    cur.opacity = 1               // fades in over prev, which stays opaque
                    clearPrev.restart()
                }
            }
        }

        // The pictures the workspaces will ask for, decoded ahead (to the size a Plane
        // uses, so it is the same cache entry): a switch then finds its picture ready
        // instead of waiting on a 4K decode before it can fade in.
        Repeater {
            model: root.preloadSources
            delegate: Image {
                required property string modelData
                visible: false
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                source: "file://" + modelData
                sourceSize: Qt.size(Math.round(root.width * root.zoomTarget * root._dpr),
                                    Math.round(root.height * root.zoomTarget * root._dpr))
            }
        }

        // ── The depth clock ───────────────────────────────────────────────────
        // A clock in a box framed exactly like a Plane (zoomed past the edge, panned), hidden where a
        // MASK says something stands in front of it — a subject, a leg, a butterfly. The mask is the
        // wallpaper's own proportions with alpha where the foreground is (services/WallpaperDepth makes
        // it, and says where the clock goes; the screen's own shape is part of the question, since a
        // cover-crop moves what is behind the clock). Nothing of the picture is redrawn: see
        // components/DepthMasked for why the first version, which laid a copy of the picture's pixels
        // over the clock, showed an outline along the whole subject.
        //
        // ── What is on screen ─────────────────────────────────────────────────
        // `shown` is a copy of the entry being drawn, because what is drawn outlives what is wanted:
        // a clock must finish sinking before it is replaced. `want` is one of
        //   · a "ready" entry   the clock, masked
        //   · a "none" entry    the clock alone (nothing stands over its spot)
        //   · `ghost`           the picture is being analysed: the clock waits where the last one was,
        //                       breathing, and glides to its place when the answer comes
        //   · null              nothing (depth off, a scene, the water)
        // _apply() reads the pair and picks the move: commit (nothing was up), morph (ghost ⇄ answer:
        // the clock stays and glides), or leave-then-commit (one picture's clock for another's).
        // A placement change keeps the OLD mask on the waiting clock — it is the same picture, and the
        // clock has not moved — but a different picture drops it at once: its mask is the wrong shape.
        //
        // ── The motion ────────────────────────────────────────────────────────
        // Coming in, the clock waits for its mask to decode (so it is never seen whole for a beat),
        // then rises from below — starting hidden behind the subject — decelerating, with a little
        // scale: stepping forward out of the picture. Going out is the quick reverse. The digits roll
        // (RollText), and a minute change never moves the layout (mono digits).
        //
        // Layered: the box rides the picture (zoom, pan), and the clock is pulled back against that
        // pan by Config.wallDepthDepth, so on a workspace switch or a pointer drift it slides behind
        // the subject instead of being printed on the picture. Needs the parallax on.
        Item {
            id: depth
            width:  parent.width  * root.zoom
            height: parent.height * root.zoom
            anchors.centerIn: parent
            visible: depth.lift > 0
            transform: Translate {
                x: root._snap(root.tx)
                y: root._snap(root.ty)
                Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            }

            // The screen's own shape: the surface's size can read as a square for a frame at start.
            readonly property real aspect:
                (root.modelData && root.modelData.height > 0) ? root.modelData.width / root.modelData.height : 0

            // Where the last answer put the clock, so a wait for the next one keeps it there.
            property var ghost: ({ state: "ghost", x: 0.5, y: 0.08, luma: 0.5 })
            readonly property var want: {
                if (!root.depthOn) return null
                const e = WallpaperDepth.entryFor(root.src, depth.aspect)
                if (e) return (e.state === "ready" || e.state === "none") ? e : null
                return WallpaperDepth.waiting(root.src, depth.aspect) ? depth.ghost : null
            }
            property var shown: null
            property string shownPic: ""   // the picture `shown` was made for
            property real lift: 0          // the clock: 0 below and unseen → 1 in place
            property bool glide: false     // the clock's place eases (a morph), instead of jumping
            property string maskSrc: ""    // the mask in use; held apart from `shown`, which changes first
            property bool waitRise: false  // brought in, but waiting for its mask to decode
            readonly property bool isGhost: depth.shown?.state === "ghost"

            function _apply() {
                const w = depth.want, s = depth.shown
                if (w === s) {
                    // Wanted again while it was sinking: come back up from where it is.
                    if (leaveAnim.running) { leaveAnim.stop(); riseAnim.restart() }
                    return
                }
                if (!s) { depth._commit(w); return }
                const sg = s.state === "ghost"
                if (w && (w.state === "ghost") !== sg) { depth._morph(w); return }
                depth._leave()
            }
            onWantChanged: depth._apply()
            Component.onCompleted: depth._apply()

            function _maskOf(w) { return (w && w.state === "ready") ? "file://" + w.cutout : "" }
            function _remember(w) {
                if (w && w.state !== "ghost") depth.ghost = { state: "ghost", x: w.x, y: w.y, luma: w.luma }
            }

            // Nothing was up: set it, then bring it in.
            function _commit(w) {
                depth.glide = false
                depth.shown = w
                depth.shownPic = root.src
                depth._remember(w)
                depth.maskSrc = depth._maskOf(w)
                if (!w) return
                depth.lift = 0
                depth.waitRise = true
                depth._maybeRise()
            }
            // Only once the mask is there to cut it: a clock over a mask still decoding would show whole
            // for a beat, in front of the subject.
            function _maybeRise() {
                if (!depth.waitRise || !depth.shown || !face.maskReady) return
                depth.waitRise = false
                riseAnim.restart()
            }
            // The clock stays and glides to where the answer says.
            function _morph(w) {
                leaveAnim.stop()
                depth.glide = true
                glideOff.restart()
                const samePic = depth.shownPic === root.src
                depth.shown = w
                depth.shownPic = root.src
                depth._remember(w)
                // Waiting: the same picture's mask still fits (the clock has not moved), another's does not.
                if (w.state === "ghost") { if (!samePic) depth.maskSrc = "" }
                else depth.maskSrc = depth._maskOf(w)
            }
            function _leave() {
                riseAnim.stop()
                depth.waitRise = false
                leaveAnim.restart()
            }

            // 0 → 1, decelerating: the shell's own emphasized curve.
            NumberAnimation {
                id: riseAnim
                target: depth; property: "lift"; to: 1
                duration: Motion.intro
                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
            }
            NumberAnimation {
                id: leaveAnim
                target: depth; property: "lift"; to: 0
                duration: Motion.exit
                easing.type: Motion.exitCurve
                onFinished: {
                    depth.shown = null
                    depth.maskSrc = ""
                    depth._apply()          // whatever is wanted NOW, which may not be what started this
                }
            }
            Timer { id: glideOff; interval: Motion.glide + 60; onTriggered: depth.glide = false }

            // A picture still being analysed: the clock waits, breathing. `ghostMix` eases in and out
            // so the clock settles to full strength instead of snapping when the answer arrives.
            property real ghostMix: depth.isGhost ? 1 : 0
            Behavior on ghostMix { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.travel } }
            property real pulse: 0.4
            SequentialAnimation on pulse {
                running: depth.ghostMix > 0
                loops: Animation.Infinite
                NumberAnimation { to: 0.75; duration: 1700; easing.type: Motion.ambient }
                NumberAnimation { to: 0.4;  duration: 1700; easing.type: Motion.ambient }
            }

            // ── Drag the clock on the desktop ─────────────────────────────────
            // Same bounds and drag math as DepthPlacer in Settings, so the preview
            // and the desktop show the same limits and feel.
            property bool _dragging: false
            property real _dragX: 0
            property real _dragY: 0
            property real _grabX: 0
            property real _grabY: 0
            readonly property real _minX: 0.2
            readonly property real _maxX: 0.8
            readonly property real _maxY: 0.66

            // ── Text that reads on THIS picture ───────────────────────────────
            // WallpaperDepth.ink: the palette's darker end on a pale picture, the lighter on a dark
            // one, or the user's pick of a role.
            readonly property var _roles: Colors.of(QsWindow.window)
            // The time is huge, so 3.5:1 is plenty; the small date gets 4.5:1.
            property color ink: WallpaperDepth.ink(depth._roles, depth.shown?.luma ?? 0.5, 3.5)
            property color inkSmall: WallpaperDepth.ink(depth._roles, depth.shown?.luma ?? 0.5, 4.5)
            Behavior on ink { ColorAnimation { duration: Motion.emphasized } }
            Behavior on inkSmall { ColorAnimation { duration: Motion.emphasized } }

            // Sized from the picture's height, like the box wallpaper-depth.py measured (40% × 36% of the
            // screen): another size would put the time somewhere the mask wasn't judged. The scale
            // setting is the user's, on top.
            readonly property real unit: depth.height * Config.wallDepthScale

            DepthMasked {
                id: face
                anchors.fill: parent
                mask: depth.maskSrc
                maskSize: Qt.size(Math.round(root.width  * root.zoomTarget * root._dpr),
                                  Math.round(root.height * root.zoomTarget * root._dpr))
                onMaskReadyChanged: depth._maybeRise()
                onFailed: WallpaperDepth.stale(root.src, depth.aspect)

                Column {
                    id: clock
                    // The place is two animated numbers, so a morph glides and a commit just lands.
                    // While dragging on the desktop, use the dragged coordinates instead.
                    property real cx: depth._dragging ? depth._dragX : (depth.shown?.x ?? 0.5)
                    property real cy: depth._dragging ? depth._dragY : (depth.shown?.y ?? 0.08)
                    Behavior on cx { enabled: depth.glide; NumberAnimation { duration: Motion.glide; easing.type: Motion.glideCurve } }
                    Behavior on cy { enabled: depth.glide; NumberAnimation { duration: Motion.glide; easing.type: Motion.glideCurve } }
                    x: depth.width  * clock.cx - width / 2
                    y: depth.height * clock.cy
                    spacing: depth.unit * 0.01
                    opacity: depth.lift * (1 - depth.ghostMix * (1 - depth.pulse))

                    transform: [
                        // Stepping forward: up from below, a touch larger as it arrives.
                        Translate { y: (1 - depth.lift) * depth.height * 0.06 },
                        Scale {
                            origin.x: clock.width / 2; origin.y: clock.height / 2
                            xScale: 0.96 + 0.04 * depth.lift
                            yScale: 0.96 + 0.04 * depth.lift
                        },
                        // Layered: pulled back against the picture's pan.
                        Translate {
                            x: root._snap(-root.tx * Config.wallDepthDepth)
                            y: root._snap(-root.ty * Config.wallDepthDepth)
                            Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                            Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                        }
                    ]

                    RollText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: {
                            const h = Config.wallDepthHour12 ? (Clock.hours % 12 || 12) : Clock.hours
                            return (h < 10 ? "0" : "") + h + ":" + (Clock.minutes < 10 ? "0" : "") + Clock.minutes
                        }
                        color: depth.ink
                        family: Tokens.fontBlock
                        weight: Font.ExtraBold
                        pixelSize: depth.unit * 0.23
                    }
                    // The lock screen's pairing: a block clock over a quiet, opened-up date.
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: Config.wallDepthDate
                        text: Qt.formatDate(Clock.now, "dddd, d MMMM")
                        color: depth.inkSmall
                        font.family: Tokens.fontFamily
                        font.weight: Font.Medium
                        font.pixelSize: depth.unit * 0.04
                        font.letterSpacing: depth.unit * 0.003
                    }
                }
            }

            // Drag handle for placing the clock. While the drag is in progress, the clock
            // position bindings switch to the dragged coordinates so the user sees it move.
            MouseArea {
                anchors.fill: parent
                enabled: depth.shown !== null
                onPressed: function (m) {
                    depth._dragX = depth.shown?.x ?? 0.5
                    depth._dragY = depth.shown?.y ?? 0.08
                    depth._grabX = m.x / width - depth._dragX
                    depth._grabY = m.y / height - depth._dragY
                    depth._dragging = true
                }
                onPositionChanged: function (m) {
                    if (!depth._dragging) return
                    depth._dragX = Math.max(depth._minX, Math.min(depth._maxX, m.x / width - depth._grabX))
                    depth._dragY = Math.max(0, Math.min(depth._maxY, m.y / height - depth._grabY))
                }
                onReleased: {
                    if (!depth._dragging) return
                    depth._dragging = false
                    if (root.src === "") return
                    WallpaperDepth.place(root.src, depth._dragX, depth._dragY)
                }
                onCanceled: depth._dragging = false
            }
        }

        // The running scene (see liveTop). Framed like a Plane — zoomed past the edge,
        // panned — and covering the screen whatever the window's own shape.
        //
        // Two slots, so a swap never goes through the scene's still: the next scene is
        // captured in the idle slot and only when it has a frame does the one in front
        // fade out. (One view re-pointed at another window blanks for a beat, and the
        // still under it showed — "the unloaded version".) Leaving for a picture fades
        // the front slot out alone.
        Item {
            id: liveBox
            width:  parent.width  * root.zoom
            height: parent.height * root.zoom
            anchors.centerIn: parent
            clip: true
            transform: Translate {
                x: root._snap(root.tx)
                y: root._snap(root.ty)
                Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            }

            // What should be showing: only while this surface is up (a capture costs a
            // copy per frame).
            readonly property var want: (root.shellDraws && !root.gameCard) ? root.liveTop : null
            property var shownTop: null
            property int frontIdx: 0
            property var _old: null          // the slot to fade once the new one has a frame
            function slotAt(i) { return i === 0 ? slotA : slotB }

            function update() {
                if (liveBox.want === liveBox.shownTop) return
                liveBox.shownTop = liveBox.want
                if (!liveBox.want) {
                    slotA.front = false
                    slotB.front = false
                    liveBox._old = null
                    release.restart()
                    return
                }
                // A swap still waiting on its handover (switching fast): let that one go now.
                if (liveBox._old) { liveBox._old.front = false; liveBox._old = null }
                const had = slotA.front || slotB.front
                const idx = had ? 1 - liveBox.frontIdx : liveBox.frontIdx
                const next = liveBox.slotAt(idx)
                next.source = liveBox.want
                next.front = true
                liveBox._old = had ? liveBox.slotAt(liveBox.frontIdx) : null
                liveBox.frontIdx = idx
                if (next.ready) liveBox.handover()
            }
            // The old scene stays fully opaque until the new one is, then goes (under an
            // opaque slot it can't be seen going). Two simultaneous fades only add up to
            // 75% at the midpoint, and whatever lies beneath showed through the rest.
            function handover() {
                if (liveBox._old) swap.restart()
                else release.restart()
            }
            Timer {
                id: swap
                interval: Motion.emphasized + 30
                onTriggered: {
                    if (liveBox._old) { liveBox._old.front = false; liveBox._old = null }
                    release.restart()
                }
            }
            onWantChanged: liveBox.update()
            Component.onCompleted: liveBox.update()

            // A slot that has faded out stops capturing.
            Timer {
                id: release
                interval: Motion.emphasized + 100
                onTriggered: {
                    if (!slotA.front) slotA.source = null
                    if (!slotB.front) slotB.source = null
                }
            }

            LiveSlot {
                id: slotA
                boxW: liveBox.width
                boxH: liveBox.height
                paused: root.covered
                onReadyChanged: if (slotA.ready && slotA.front && liveBox.frontIdx === 0) liveBox.handover()
            }
            LiveSlot {
                id: slotB
                boxW: liveBox.width
                boxH: liveBox.height
                paused: root.covered
                onReadyChanged: if (slotB.ready && slotB.front && liveBox.frontIdx === 1) liveBox.handover()
            }
        }

        // Material Wallpaper (Config.wallMaterial): over the picture, UNDER the water. A picture
        // chosen while it is on arrives as water across the shapes, and Wallpaper turns the flag
        // off as that water lands, so they fade out where nothing can see them go. The picture
        // underneath keeps loading, so turning this off by hand is a fade, not a decode. Built
        // while it is on and for the length of its fade-out, and not otherwise.
        Loader {
            id: material
            anchors.fill: parent
            opacity: root.materialOn ? 1 : 0
            active: root.materialOn || material.opacity > 0
            Behavior on opacity { NumberAnimation { duration: Motion.emphasized } }
            sourceComponent: MaterialWallpaper {
                zoom: root.zoom
                tx: root._snap(root.tx)
                ty: root._snap(root.ty)
                // No frames for a screen nobody can see.
                running: !root.covered && !Gamemode.wallpaperPaused
            }
        }

        // ── The still behind it, for when the shell is not running ───────────────
        // This screen's Material Wallpaper as a PNG, handed to awww (MaterialFallback). Made once the
        // style or the palette has stopped changing — it is a snapshot and an encode, so not on every
        // frame of a colour change, nor of a slider.
        Connections {
            target: material.item
            ignoreUnknownSignals: true
            function onSignatureChanged() { if (root.stillWanted) stillTimer.restart() }
        }
        Timer {
            id: stillTimer
            interval: 2500
            onTriggered: root._saveStill()
        }

        Item {
            id: water
            anchors.fill: parent

            Repeater {
                id: slots
                model: 2

                delegate: Item {
                    id: slot
                    required property int index
                    anchors.fill: parent

                    property int token: -1
                    property bool keep: false
                    readonly property string url: pic.source.toString()
                    readonly property bool failed: pic.status === Image.Error
                    visible: slot.token > 0 && pic.status === Image.Ready

                    // Only while it carries a change: the layer and its shader exist
                    // for the wave and not a frame longer.
                    layer.enabled: slot.token > 0
                    layer.samplerName: "src"
                    layer.effect: ShaderEffect {
                        property real progress: WallWave.progressOf(slot.index)
                        property real aspect: width / Math.max(1, height)
                        property real time: WallWave.t
                        property color tint: Colors.of(QsWindow.window).fg
                        fragmentShader: Qt.resolvedUrl("../../shaders/wallwave.frag.qsb")
                    }

                    // The hold WallWave keeps on this change's `go` while the picture
                    // decodes (see WallWave.loadHold): taken before the source is set, so
                    // a cache hit that is Ready at once still finds it to give back.
                    property int heldToken: -1
                    function _drop() {
                        if (slot.heldToken <= 0) return
                        const t = slot.heldToken
                        slot.heldToken = -1
                        WallWave.loadRelease(t)
                    }
                    function load(u, t) {
                        slot._drop()
                        pic.source = ""
                        slot.heldToken = t
                        WallWave.loadHold(t)
                        pic.source = u
                    }
                    function clear() { slot._drop(); slot.token = -1; slot.keep = false; pic.source = "" }
                    Component.onDestruction: slot._drop()

                    Plane {
                        id: pic
                        opacity: 1
                        onStatusChanged: {
                            if (status === Image.Error)
                                console.warn("WallpaperView: the water could not load", pic.source)
                            if (status === Image.Ready || status === Image.Error) slot._drop()
                        }
                    }
                }
            }
        }
    }

    // ── Music effects (WallFx) ────────────────────────────────────────────────
    // Everything above, drawn again through the music effects while music plays — only
    // while this surface is the one drawing the wallpaper, nothing fullscreen covers it,
    // and Game Mode's card isn't up.
    WallFx {
        anchors.fill: parent
        source: content
        allowed: root.shellDraws && !root.covered && !root.gameCard
    }

    // Fully opaque — whatever's loaded (or not) in the Item above is irrelevant
    // once this covers it, so it doesn't need to coordinate with the picture's
    // own crossfade.
    Rectangle {
        anchors.fill: parent
        visible: root.gameCard
        color: Colors.of(QsWindow.window).base

        RowLayout {
            anchors.centerIn: parent
            spacing: Tokens.spacingXl

            MaterialIcon {
                name: "gamepad"
                fill: 1
                color: Colors.of(QsWindow.window).primary
                variant: "display"
                sizeScale: 3
                Layout.alignment: Qt.AlignVCenter
            }
            StyledText {
                text: Gamemode.wallpaperRestoring ? "Resuming Your Wallpaper" : "Game Mode Activated"
                variant: "display"
                sizeScale: 1.4
                color: Colors.of(QsWindow.window).primary
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }
}
