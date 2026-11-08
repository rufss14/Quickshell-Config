pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"
import "drift.js" as DriftJs

// ── Drift ─────────────────────────────────────────────────────────────────────
// The cookie field behind the panels: ONE set of shapes on one repeating plane keyed to
// the screen, moved by one frame loop. Each panel (components/DriftShapes) is a window
// onto it, which is why two panels side by side show the same drift, a shape crossing
// from one into the next carries on, and a panel opening or swapping reveals the field
// instead of starting its own. The reasoning and the maths are in drift.js, which has a
// test.
//
// ── Refcounted, like Cava ─────────────────────────────────────────────────────
// A view calls acquire() while it is on screen and release() when it isn't; the loop runs
// iff something holds it. With no panel open this is a field of numbers and nothing else —
// no timer, no frame callback. `Config.motionEnabled` off freezes it where it is (the
// shapes stay, the drift stops), the same switch Motion honours for every animation.
//
// ── One tile for every monitor ────────────────────────────────────────────────
// The plane is a tile, not a screen, so it does not care how many monitors there are or how
// large: each panel asks for the image of the field that lands in its own window.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // The tile: sized for the widest panel at default zoom plus a shape (see drift.js).
    readonly property real periodW: 1000
    readonly property real periodH: 800
    readonly property int  count:   28

    // [{ x, y, r, size, alpha, points, petal, tone, phase, outlined, … }], replaced every
    // frame by a pure step — views read a shape by index and re-evaluate when it moves.
    property var field: DriftJs.make(root.count, root.periodW, root.periodH, Math.random)

    // Bumped every frame: what a view's "where am I on screen" binding hangs on (a panel
    // that moves — sliding in, growing, being dragged — has no notifying scene position),
    // and the clock for the gentle breathing.
    property int frame: 0
    property real clock: 0

    // ── Diagnostics (no persistence — flipped over IPC while looking at the problem) ─────────
    //   drift debug on|off   outline every window onto the field in its own colour, so a screenshot
    //                        shows which regions are covered and which are not (DriftShapes.role)
    //   drift layers top|normal  raise every cookie layer above everything in the bar's window: if
    //                        cookies appear where there were none, something was painting over them
    //   drift freeze on|off  stop stepping the field (shapes hold still where they are) — to measure what
    //                        the field itself costs against the rest of the shell, with nothing else changed
    property bool debug: false
    property bool raised: false
    property bool frozen: false

    property int _refs: 0
    function acquire() { root._refs++ }
    function release() { root._refs = Math.max(0, root._refs - 1) }

    // ── How the bar, the sidebar and the frame join in ────────────────────────
    // They carry the panels' field on (Config.barCookies), so a panel needs no fade and no seam line
    // where it meets them, and the mask is square at its welded corners (DriftShapes) — in BOTH modes:
    // "everywhere" used to keep the fade, which is what cut a shape crossing from the bar into a panel.
    // Not while Game mode stands their layers down, or a panel's field would end in a hard line.
    readonly property bool flows: Config.barCookies && !PowerSaver.quiet
    readonly property bool everywhere: Config.barCookiesFrom === "everywhere"

    // ── Drawn by the blob instead (2026-10-17) ────────────────────────────────
    // With a plugin that can (Morph.cookies), the bar anchored (so the blob owns the ring) and the
    // field on for the bar too, the cookies are drawn INSIDE the blob's merged silhouette by its
    // shader, from `picturesFor(screen)`: exact at every fillet, bridge and weld, which rectangular
    // QML windows could never be, and one GPU pass instead of hundreds of bound items a frame. The
    // welded surfaces then paint no fill of their own (the blob's is the same colour), so the cookies
    // show through them; every QML window onto the field stands down (DriftShapes.on).
    readonly property bool inBlob: Morph.available && Morph.cookies && Config.barAnchored
                                   && Config.panelCookies && Config.barCookies

    // A blob layer holds the loop while it has cookies to draw, as a QML window does.
    property int _blobRefs: 0
    function acquireBlob() { root._blobRefs++ }
    function releaseBlob() { root._blobRefs = Math.max(0, root._blobRefs - 1) }

    // The screens a blob layer draws for ({ key: {w, h} }), and their pictures ({ key: [...] }).
    property var _screens: ({})
    property var _pictures: ({})
    function setScreen(key, w, h) {
        const next = Object.assign({}, root._screens)
        if (w > 0 && h > 0) next[key] = { w: w, h: h }
        else delete next[key]
        root._screens = next
        root._refreshPictures()
    }
    function picturesFor(key) { return root._pictures[key] ?? [] }
    // What one QML window draws (drift.js `windowPictures`): asked once a tick per window.
    function windowPictures(ox, oy, w, h, source, key) {
        return DriftJs.windowPictures(root.field, ox, oy, w, h, root.periodW, root.periodH, source,
                                      root._panelSets[key], root.everywhere, root.clock, key)
    }
    function _refreshPictures() {
        const next = {}
        for (const key in root._screens) {
            const sc = root._screens[key]
            next[key] = (PowerSaver.quiet || !root.inBlob) ? []
                : DriftJs.pictures(root.field, sc.w, sc.h, root._panelSets[key], root.everywhere,
                                   root.clock, key, root.periodW, root.periodH)
        }
        root._pictures = next
    }
    onEverywhereChanged: root._refreshPictures()
    onInBlobChanged: root._refreshPictures()
    Connections {
        target: Gamemode
        function onActiveChanged() { root._refreshPictures() }
    }
    // How strongly a window that is not a panel draws the picture of shape `s` at (x, y) on screen
    // `key` (drift.js `strength`): one number per picture, whichever window asks, so no join cuts it.
    function strength(s, x, y, key) {
        return DriftJs.strength(s, x, y, root._panelSets[key], root.everywhere, root.clock, s.lit[key])
    }

    // ── Where the panels are ──────────────────────────────────────────────────
    // Published by each Bar window (screen-local pixels, like the field): the cards of the three
    // bar groups and the sidebar's panel, each with how far its card has faded in (`a`) and whether
    // it is still wanted (`open`). The field lights a shape while it overlaps a fully open one
    // (drift.js `wake`), which is what lets the bar, the sidebar and the frame show only what has just
    // come from a panel, and every window near one draws it stronger (`strength`). Keyed by screen, so
    // one monitor's panels don't replace another's.
    property var _panelSets: ({})
    readonly property var panels: Object.values(root._panelSets).reduce((a, b) => a.concat(b), [])
    // One screen's panels (the strips between them and the bar / frame / sidebar are laid over, see
    // FrameDrift).
    function panelsFor(key) { return root._panelSets[key] ?? [] }
    function setPanels(key, rects) {
        const clean = (rects || []).filter(r => r.w > 0.5 && r.h > 0.5)
        const next = Object.assign({}, root._panelSets)
        if (clean.length > 0) next[key] = clean
        else delete next[key]
        root._panelSets = next
        root._hot = 0.25
        // Frozen (motion off) the loop does not run, and a panel opening still changes what is drawn.
        if (!root._running) root._refreshPictures()
    }
    // Is any picture lit anywhere (drift.js `wake`)? While none is, and no panel is open, a surface that
    // shows only what came from a panel has nothing to draw and lets go of the frame loop. A lit one
    // goes on drifting until it leaves the screen — so after a panel closes the loop runs a while longer,
    // for as long as a cookie that left it is still crossing the bar.
    property bool anyLit: false
    readonly property bool alive: root.panels.length > 0 || root.anyLit

    // The largest screen: a lit picture is dropped once it is wholly beyond it.
    // (A plain loop: Quickshell.screens is a QML list, which reliably has length and indexing, not
    // Array methods.)
    readonly property var screenBounds: {
        const sc = Quickshell.screens
        let w = 0, h = 0
        for (let i = 0; i < sc.length; i++) { w = Math.max(w, sc[i].width); h = Math.max(h, sc[i].height) }
        return { w: w, h: h }
    }

    function wrap(v, origin, size) { return DriftJs.place(v, origin, root.periodW, size) }
    function wrapY(v, origin, size) { return DriftJs.place(v, origin, root.periodH, size) }
    function breathe(phase, seconds, amount) { return DriftJs.breathe(root.clock, phase, seconds, amount) }
    // How much of a shape is there right now, for a surface where shapes should come and go
    // (the bar, the sidebar, the frame): see drift.js `presence`.
    function presence(phase, period, duty) { return DriftJs.presence(root.clock, phase, period, duty) }

    // `qs ipc -c ~/.config/quicktest call drift status` — what the field thinks, for when a cookie
    // is cut or missing and there is no way to see why from outside.
    property var _ipc: IpcHandler {
        target: "drift"
        function debug(on: string): string { root.debug = (on === "on" || on === "true"); return "debug=" + root.debug }
        function freeze(on: string): string { root.frozen = (on === "on" || on === "true"); return "frozen=" + root.frozen }
        function layers(where: string): string { root.raised = (where === "top"); return "layers=" + (root.raised ? "top" : "normal") }
        function status(): string {
            const lit = root.field.map((s, i) => ({ i: i, n: Object.keys(s.lit).map(k => k + ":" + s.lit[k].length).join(",") }))
                                  .filter(x => x.n !== "")
            return "debug=" + root.debug + " layers=" + (root.raised ? "top" : "normal")
                 + " refs=" + root._refs + " blobRefs=" + root._blobRefs + " inBlob=" + root.inBlob
                 + " running=" + root._running
                 + " alive=" + root.alive + " anyLit=" + root.anyLit
                 + " panels=" + JSON.stringify(root._panelSets)
                 + " bounds=" + root.screenBounds.w + "x" + root.screenBounds.h
                 + " lit=" + lit.length + " " + JSON.stringify(lit.slice(0, 12))
        }
    }

    readonly property bool _running: (root._refs > 0 || root._blobRefs > 0) && Config.motionEnabled && !root.frozen
    // ── How often it steps ────────────────────────────────────────────────────
    // At rest, 30 times a second: the whole field drifts 6px/s, so a step is a fifth of a pixel
    // — below what an antialiased edge shows — and every step costs a repaint of the bar's whole
    // window (it was stepping at the display's 165Hz). Full rate only while a panel is moving
    // (`_hot`, set by setPanels): a QML window re-reads where its card is on the tick, and at 30Hz
    // its shapes would lag the card between ticks.
    readonly property real restInterval: 1 / 30
    property real _hot: 0
    property real _acc: 0
    FrameAnimation {
        running: root._running
        onTriggered: {
            root._acc += frameTime
            const hot = root._hot > 0 && root._refs > 0
            if (root._hot > 0) root._hot -= frameTime
            if (!hot && root._acc < root.restInterval) return
            const dt = root._acc
            root._acc = 0
            // Pictures are tracked only while the bar/sidebar/frame cookies are on AND take their cookies
            // from the panels. Otherwise no panels and no bounds: nothing is recorded, and anything
            // already lit is dropped at once (no bounds = off screen) — so switching the feature off
            // leaves nothing behind and does no work.
            const track = Config.barCookies && !root.everywhere
            root.field = DriftJs.step(root.field, dt, root.periodW, root.periodH,
                                      track ? root._panelSets : ({}), track ? root.screenBounds : null)
            root.anyLit = DriftJs.anyLit(root.field)
            root.clock += Math.min(dt, 0.1)
            root.frame++
            if (root._blobRefs > 0) root._refreshPictures()
        }
    }
}
