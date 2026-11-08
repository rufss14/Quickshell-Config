pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── SnipPins ──────────────────────────────────────────────────────────────────────
// The snip tool's "Pin" action: the cropped picture floats on top of everything as a card you
// can drag, copy from, or close — a reference to look at while you work. The pictures are
// the shell's, not yours: each is a file in $XDG_RUNTIME_DIR (tmpfs, 0700), removed when its pin
// closes, and anything left by a shell that died is swept when this loads. A pin does not
// survive a shell restart.
//
//     qs ipc -c ~/.config/quicktest call snippins closeAll
//
// A pin is a picture or, with `live`, a window or a region of the screen that keeps updating
// (the "Live" snip action). `items` is the whole state: [{ id, path, screen, x, y, w, h }] and, for a
// live one, `{ live: true, window, src }` — `window` the toplevel to capture (null = a region of the
// screen) and `src` the region's rectangle. x/y/w/h are logical and local to `screen` (the space
// Snip's selection is in).
//
// A live pin of a REGION belongs to the WORKSPACE it was taken from (`workspace`, the id its screen was
// showing; -1 = unknown): it keeps showing that workspace's windows in that region, whichever workspace
// you are on — the pin itself is on every workspace and can be dragged anywhere. See PinCard.
//
// Each screen's PinLayer draws its own, and builds its
// click-through mask from the same records (the way WidgetLayer does for desktop tiles), so a
// card being dragged moves by changing its record here and nothing else.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property var items: []

    // A region pin composes its workspace's windows (PinCard), so it needs the window list kept current
    // (Hypr's event tier), held only while there is one.
    readonly property bool _wantsWindows: root.items.some(p => p.live === true && p.window === null && p.workspace > 0)
    property bool _held: false
    on_WantsWindowsChanged: {
        if (root._wantsWindows === root._held) return
        if (root._wantsWindows) Hypr.acquireEvents()
        else Hypr.releaseEvents()
        root._held = root._wantsWindows
    }

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-quicktest-pins"

    // Image's cache is keyed by URL, so a name must never be reused across shell runs.
    readonly property string _stamp: String(Date.now())
    property int _n: 0

    // A path for the next pin's picture, in this tool's own directory (Snip makes it, mode 0700).
    function nextImage() {
        root._n++
        return root.dir + "/pin-" + root._stamp + "-" + root._n + ".png"
    }

    function get(id) {
        for (const p of root.items) if (p.id === id) return p
        return null
    }

    function add(path, screen, rect, workspace) {
        root.items = root.items.concat([{ id: path, path: path, screen: screen, workspace: workspace ?? -1,
                                          x: rect.x, y: rect.y, w: rect.w, h: rect.h }])
    }

    // A live pin of `src` (a screen-local rectangle) at `at`, showing `window` (a Toplevel) when the
    // source is a whole window, else that region of the screen. Nothing is written to disk.
    function addLive(screen, src, window, at, workspace) {
        root._n++
        const id = "live-" + root._stamp + "-" + root._n
        root.items = root.items.concat([{ id: id, path: "", screen: screen, workspace: workspace ?? -1, live: true,
                                          window: window, src: src,
                                          x: at.x, y: at.y, w: at.w, h: at.h }])
    }

    // Scale a pin about its middle by `factor`, in its source's aspect, kept on screen and no smaller
    // than a thumbnail. `bounds` is the screen's logical size.
    function resize(id, factor, bounds) {
        root.items = root.items.map(p => {
            if (p.id !== id) return p
            const k = Math.max(96 / p.w, Math.min(bounds.width / p.w, bounds.height / p.h, factor))
            const w = p.w * k, h = p.h * k
            return Object.assign({}, p, { w: w, h: h,
                x: Math.max(0, Math.min(bounds.width - w, p.x + (p.w - w) / 2)),
                y: Math.max(0, Math.min(bounds.height - h, p.y + (p.h - h) / 2)) })
        })
    }

    // Move a pin to (x, y), kept on its screen by the layer that calls this.
    function move(id, x, y) {
        root.items = root.items.map(p => p.id === id ? Object.assign({}, p, { x: x, y: y }) : p)
    }

    function close(id) {
        const p = root.get(id)
        if (p === null) return
        root.items = root.items.filter(q => q.id !== id)
        root._remove([p.path])
    }

    function closeAll() {
        const paths = root.items.map(p => p.path)
        root.items = []
        root._remove(paths)
    }

    // argv, never a shell string; only paths this service itself named.
    function _remove(paths) {
        const ours = paths.filter(p => p.indexOf(root.dir + "/pin-") === 0)
        if (ours.length > 0) Quickshell.execDetached(["rm", "-f", "--"].concat(ours))
    }

    Component.onCompleted: Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/pin-*.png', "sh", root.dir])

    IpcHandler {
        target: "snippins"
        function closeAll(): void { root.closeAll() }
        function count(): int { return root.items.length }
    }
}
