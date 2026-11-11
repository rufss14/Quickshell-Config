pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick
import "../config"
import "../state"
import "snip.js" as P

// ── Snip ──────────────────────────────────────────────────────────────────────
// Freeze the screen, drag out what you want, adjust it, and do one thing with it — ii's
// region selector, on this shell's own parts:
//
//     copy       the clipboard
//     save       a file in Screenshot.saveDir, the clipboard, and the post-capture toast
//     edit       save, then the shell's own annotator (UiState.openAnnotate)
//     pin        float it on top of everything, a card you can drag (SnipPins)
//     livepin    the same, but live: a window (or region) that keeps updating
//     text       OCR it (Lens)             translate   OCR it and translate in place (Lens)
//     record     the clip recorder on that rectangle (Clips)
//
//     qs ipc -c ~/.config/quicktest call snip copy|save|edit|pin|livepin|text|translate|record|close
//
// SUPER+P is `snip save` and SUPER+SHIFT+P `snip copy` (hypr/binds.lua); Lens's own
// drag-a-region (SUPER+O) still works.
//
// ── The flow ──────────────────────────────────────────────────────────────────
// Drag a box, or click a window; the selection STAYS, with handles, so it can be moved and
// resized, and a toolbar appears beside it. Click an action there, or press Enter for the
// highlighted one (the last you used; `snip copy` / `snip save` choose it for that snip).
// The selection is one thing shared by every screen's overlay (it lives on one screen at a
// time), so this holds it, not the overlay.
//
// ── How the freeze works ──────────────────────────────────────────────────────
// grim captures each output to a file BEFORE any overlay is up (a capture after would
// photograph the overlay); each screen's SnipOverlay then draws its file as a still, so
// what you drag over is what you get. The crop comes from that same file with ImageMagick,
// in the capture's own pixels (the file is logical × the output's scale; snip.js does the
// arithmetic). The files live in $XDG_RUNTIME_DIR (tmpfs, 0700), named per snip, and are
// removed when the action has finished with them.
//
// ── Reverse image search is not here ──────────────────────────────────────────
// ii uploads the crop to a public file host (uguu.se) to hand a URL to Google Lens. That
// sends the picture off the machine to a third party, so it isn't built; "text" +
// Lens's DuckDuckGo search covers searching for what a region SAYS without uploading it.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // "" · "capturing" · "selecting" · "working"
    property string phase: ""

    // What letting go (or Enter) does. Starts as the last one used; an IPC `snip copy`
    // overrides it for this snip only. The toolbar's choices are remembered (Config.snipAction).
    property string action: "save"

    // ── The selection, shared by every screen's overlay ──────────────────────
    // `selRect` is logical and local to `selScreen`; `selScale` is that output's image pixels
    // per logical pixel.
    // A locked aspect ratio (width / height; 0 = free), chosen from the size chip. Per snip: it
    // starts free every time, because a lock left over from last time is a surprise, not a habit.
    property real ratio: 0

    property string selScreen: ""
    property var    selRect: null
    property real   selScale: 1
    property var    selScreenRef: null

    // The screen the pointer is on: where the toolbars show, and what "whole screen" means.
    property string activeScreen: ""
    property var    activeScreenRef: null
    property real   activeScale: 1

    // One id per snip, in the file names. Image's cache is keyed by URL, so reusing a name
    // would show the PREVIOUS screen; a fresh name never can, and the loupe can share the
    // still's decode.
    property int _session: 0

    readonly property bool open: root.phase === "selecting"
    readonly property bool busy: root.phase !== ""

    // The window list must be current while the overlay is up (a click picks a window):
    // Hypr's event tier, held only then.
    property bool _hyprHeld: false
    onOpenChanged: {
        if (root.open === root._hyprHeld) return
        if (root.open) Hypr.acquireEvents()
        else Hypr.releaseEvents()
        root._hyprHeld = root.open
    }

    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-quicktest-snip"

    // id, label, icon, key, and what it does — for the toolbar and its hint line.
    readonly property var actions: [
        { id: "copy",      label: Translation.tr("Copy"),      symbol: "content_copy",        key: "C",
          what: Translation.tr("Copy it to the clipboard") },
        { id: "save",      label: Translation.tr("Save"),      symbol: "save",                key: "S",
          what: Translation.tr("Save it to your screenshots folder and copy it") },
        { id: "edit",      label: Translation.tr("Edit"),      symbol: "edit",                key: "E",
          what: Translation.tr("Save it and open it in the editor") },
        { id: "pin",       label: Translation.tr("Pin"),       symbol: "push_pin",            key: "P",
          what: Translation.tr("Float it on top of everything, to look at while you work") },
        { id: "livepin",   label: Translation.tr("Live"),      symbol: "videocam",             key: "V",
          what: Translation.tr("Float a live view of it that keeps updating") },
        { id: "text",      label: Translation.tr("Text"),      symbol: "text_fields",         key: "T",
          what: Translation.tr("Read the text in it") },
        { id: "translate", label: Translation.tr("Translate"), symbol: "translate",           key: "L",
          what: Translation.tr("Read the text and translate it in place") },
        { id: "record",    label: Translation.tr("Record"),    symbol: "fiber_manual_record", key: "R",
          what: Translation.tr("Record this area of the screen") }
    ]

    function actionById(id) {
        for (const a of root.actions) if (a.id === id) return a
        return root.actions[1]
    }

    // Why an action can't run, or "" — the usual contract.
    function blocker(id) {
        if (id === "text" || id === "translate") return Lens.blocker()
        if (id === "record") return Clips.blocker()
        return ""
    }

    // ── Starting and stopping ────────────────────────────────────────────────
    function start(action) {
        if (root.phase === "working") return
        // The same key again closes it, the way a toggle should.
        if (root.phase !== "" && (action === root.action || action === "")) { root.close(); return }
        if (root.phase !== "") { root.action = action; return }
        const act = action || Config.snipAction
        if (root.blocker(act) !== "") return
        root.action = act
        UiState.closeSidePanel()
        root._session++
        root.clearSelection()
        root.ratio = 0
        root.activeScreen = Hyprland.focusedMonitor?.name ?? ""
        root.phase = "capturing"
        const names = Quickshell.screens.map(s => P.safeName(s.name)).filter(n => n !== "")
        root._outputs = names
        // Every output at once, uncompressed (`-l 0`): measured 0.28 s for two screens one after
        // the other with grim's default PNG, 0.03 s this way — and the file is on tmpfs and
        // deleted a moment later, so its size costs nothing. Each output stands alone: the ones
        // that were captured are printed, and one that can't be (Hyprland refuses an output a
        // fullscreen app is scanned out to: "failed to copy output") must not take the others down.
        // 127 = no grim at all.
        capture.command = ["sh", "-c",
            'dir=$1; id=$2; shift 2; mkdir -p "$dir" && chmod 700 "$dir" || exit 1; '
          + 'command -v grim >/dev/null || exit 127; '
          + 'for o in "$@"; do { grim -l 0 -o "$o" "$dir/snip-$id-$o.png" 2>/dev/null && echo "$o"; } & done; '
          + 'wait; exit 0',
            "sh", root.dir, String(root._session)].concat(names)
        capture.running = true
    }

    function close() {
        // Mid-crop the source file is still being read; the crop's own exit cleans up.
        if (root.phase === "working") return
        root.phase = ""
        root.clearSelection()
        root._clean()
    }

    function _clean() {
        // Only this tool's own captures, by name — never the directory's other contents.
        Quickshell.execDetached(["sh", "-c", 'rm -f "$1"/snip-*.png', "sh", root.dir])
    }

    function imageFor(screenName) {
        return root.dir + "/snip-" + root._session + "-" + P.safeName(screenName) + ".png"
    }

    // ── What the toolbars do ─────────────────────────────────────────────────
    // Choosing an action with a selection up DOES it: "Save" is the button you press once the
    // box is right. With nothing selected it only chooses — and that choice is remembered.
    function pickAction(id) {
        if (root.phase !== "selecting" || root.blocker(id) !== "") return
        root.action = id
        Config.snipAction = id
        if (root.selRect !== null) root.commitSelection()
    }

    // ── The selection ────────────────────────────────────────────────────────
    function setSelection(screen, rect, scale) {
        root.selScreen = screen.name
        root.selScreenRef = screen
        root.selScale = scale
        root.selRect = rect
    }
    // Choose a ratio (0 = free). A selection that is up is cut down to it, about its middle.
    function setRatio(r) {
        root.ratio = r
        if (r > 0 && root.selRect !== null && root.selScreenRef !== null) {
            const c = P.clampRect(P.fitRatio(root.selRect, r), root.selScreenRef.width, root.selScreenRef.height)
            if (c !== null) root.selRect = c
        }
    }
    // A size typed in the capture's own pixels. Typing one is choosing "exactly this", so the
    // ratio lock lets go.
    function setSize(pxW, pxH) {
        if (root.selRect === null || root.selScreenRef === null) return
        root.ratio = 0
        const c = P.clampRect(P.sizeRect(root.selRect, pxW, pxH, root.selScale,
                                         root.selScreenRef.width, root.selScreenRef.height),
                              root.selScreenRef.width, root.selScreenRef.height)
        if (c !== null) root.selRect = c
    }
    function clearSelection() {
        root.selScreen = ""
        root.selScreenRef = null
        root.selRect = null
    }
    function commitSelection() {
        if (root.selRect === null || root.selScreenRef === null) return
        root.commit(root.selScreenRef, root.selRect, root.selScale)
    }
    // Which screen the pointer is on, as reported by that screen's overlay.
    function pointerOn(screen, scale) {
        root.activeScreen = screen.name
        root.activeScreenRef = screen
        root.activeScale = scale
    }
    // The whole screen the pointer is on, as the selection (F).
    function selectWhole() {
        const s = root.activeScreenRef
        if (root.phase !== "selecting" || s === null) return
        root.setSelection(s, P.fullRect(s.width, s.height), root.activeScale)
    }
    // Move the selection by whole pixels (the arrow keys).
    function nudge(dx, dy) {
        if (root.selRect === null || root.selScreenRef === null) return
        root.selRect = P.moveRect(root.selRect, dx, dy, root.selScreenRef.width, root.selScreenRef.height)
    }

    // ── Doing the action ─────────────────────────────────────────────────────
    // `rect` is logical and local to `screen`; `scale` is image pixels per logical pixel.
    function commit(screen, rect, scale) {
        if (root.phase !== "selecting") return
        const r = P.clampRect(rect, screen.width, screen.height)
        if (r === null) { root.close(); return }
        const act = root.action
        const global = P.toGlobal(r, screen.x, screen.y)
        // The workspace this screen is showing: a pin stays with it (SnipPins).
        const ws = Hyprland.monitorFor(screen)?.activeWorkspace?.id ?? -1

        // Nothing to crop either: a live pin shows its source as it changes. A selection that IS a
        // window shows that window (so nothing drawn over it, the pin included, gets in); anything
        // else shows that region of the screen. Read the window list before the overlay lets go of it.
        if (act === "livepin") {
            const wins = Hypr.windows.map(w => ({ x: w.at[0], y: w.at[1], w: w.size[0], h: w.size[1], ref: w }))
            const hit = P.matchWindow(wins, global, 3)
            root.phase = ""
            root.clearSelection()
            root._clean()
            SnipPins.addLive(screen.name, { x: r.x, y: r.y, w: r.w, h: r.h }, hit ? hit.ref.wayland : null,
                             P.livePlace(r, screen.width, screen.height, Tokens.spacingXl), ws)
            return
        }

        // Nothing to crop: the recorder takes the rectangle itself.
        if (act === "record") {
            root.phase = ""
            root.clearSelection()
            root._clean()
            Clips.recordArea(P.geom(global))
            return
        }

        const px = P.toPixels(r, scale)
        const src = root.imageFor(screen.name)
        const cropGeom = P.geom(px)
        root._job = { act: act, dst: "", screen: screen.name, workspace: ws,
                      local: { x: r.x, y: r.y, w: r.w, h: r.h },
                      region: { x: global.x, y: global.y, w: global.w, h: global.h, output: screen.name } }
        root.phase = "working"
        root.clearSelection()

        if (act === "copy") {
            // Straight to the clipboard: no file to leave behind or race a delete against.
            cropProc.command = ["bash", "-c",
                'set -o pipefail; magick "$1" -crop "$2" +repage png:- | wl-copy --type image/png',
                "bash", src, cropGeom]
        } else {
            let dst = ""
            let priv = false
            if (act === "text" || act === "translate") {
                dst = Lens.nextImage()          // Lens's own 0700 directory
                priv = true
            } else if (act === "pin") {
                dst = SnipPins.nextImage()          // Pins' own 0700 directory: a pin is never a file in your folders
                priv = true
            } else {
                dst = Screenshot.saveDir + "/Snip_" + Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh-mm-ss") + ".png"
            }
            root._job.dst = dst
            // The destination's folder first: the screenshots folder may not exist yet, and
            // it is the USER's folder — only Lens's private one is given a mode.
            cropProc.command = ["sh", "-c",
                'd=$(dirname "$1"); if [ "$2" = priv ]; then mkdir -p -m 700 "$d"; else mkdir -p "$d"; fi; '
              + 'shift 2; exec "$@"', "sh", dst, priv ? "priv" : "plain"].concat(P.cropArgs(src, px, dst))
        }
        cropProc.running = true
    }

    property var _job: null

    // The outputs a capture was asked for, and the ones grim could not read.
    property var _outputs: []
    Process {
        id: capture
        stdout: StdioCollector { id: capOut }
        onExited: function (code) {
            if (root.phase !== "capturing") return
            const got = capOut.text.split("\n").map(l => l.trim()).filter(l => l !== "")
            const failed = root._outputs.filter(n => got.indexOf(n) < 0)
            // The screen you are on has to be one of them: its overlay is the one that takes the keys.
            const here = got.indexOf(P.safeName(root.activeScreen)) >= 0
            if (code !== 0 || !here) {
                root.phase = ""
                root._clean()
                Quickshell.execDetached(["notify-send", "-a", "Snip", Translation.tr("Couldn't capture the screen"),
                    code === 127 ? Translation.tr("grim isn't installed")
                    : got.length === 0 ? Translation.tr("grim couldn't read any output")
                    : Translation.tr("Couldn't read") + " " + root.activeScreen + " — "
                      + Translation.tr("a fullscreen app on it can block capture")])
                return
            }
            if (failed.length > 0)
                Quickshell.execDetached(["notify-send", "-a", "Snip", Translation.tr("Couldn't capture") + " " + failed.join(", "),
                                         Translation.tr("It is left as it is; the other screens work.")])
            root.phase = "selecting"
        }
    }

    Process {
        id: cropProc
        onExited: function (code) {
            const job = root._job
            root._job = null
            root.phase = ""
            root._clean()
            if (job === null) return
            if (code !== 0) {
                Quickshell.execDetached(["notify-send", "-a", "Snip", Translation.tr("Couldn't crop it"),
                                         Translation.tr("magick (ImageMagick) or wl-copy failed — are they installed?")])
                return
            }
            if (job.act === "copy") {
                // Already on the clipboard (the pipeline did it).
            } else if (job.act === "pin") {
                SnipPins.add(job.dst, job.screen, job.local, job.workspace)
            } else if (job.act === "text" || job.act === "translate") {
                Lens.adopt(job.region, job.dst, job.act)
            } else {
                // save / edit: the clipboard too (ii does), then the toast or the annotator.
                Clipboard.copyFile(job.dst, "image/png")
                if (job.act === "edit") UiState.openAnnotate(job.dst)
                else                    Screenshot.present(job.dst)
            }
        }
    }

    IpcHandler {
        target: "snip"
        function copy(): void      { root.start("copy") }
        function save(): void      { root.start("save") }
        function edit(): void      { root.start("edit") }
        function pin(): void       { root.start("pin") }
        function livepin(): void   { root.start("livepin") }
        function text(): void      { root.start("text") }
        function translate(): void { root.start("translate") }
        function record(): void    { root.start("record") }
        function close(): void     { root.close() }
        // Put a selection up on the screen the pointer is on, in its local logical pixels —
        // for a script or a test; it is the same as dragging it out.
        function select(x: int, y: int, w: int, h: int): void {
            const s = root.activeScreenRef
            if (root.phase !== "selecting" || s === null) return
            const r = P.clampRect({ x: x, y: y, w: w, h: h }, s.width, s.height)
            if (r !== null) root.setSelection(s, r, root.activeScale)
        }
        function status(): string {
            return "phase=" + root.phase + " action=" + root.action + " screen=" + root.activeScreen
                 + (root.selRect ? " sel=" + P.geom(root.selRect) : "")
        }
    }
}
