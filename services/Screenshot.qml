pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Screenshot ────────────────────────────────────────────────────────────────
// What happens AFTER the shutter.
//
// ── It does not take the screenshot ───────────────────────────────────────────
// hyprshot is already bound to a key and already works. Reimplementing capture in QML
// would replace a working keybind with a slower one, so this deliberately owns only
// the part that was missing: the moment where you have a picture and want to do
// something with it. Capture stays wherever the user put it.
//
// ── How it knows ──────────────────────────────────────────────────────────────
// The shell IS the notification daemon, and every screenshot tool announces itself
// through it. So Notifications hands each incoming notification here first; if it is
// from a screenshot tool and carries a readable image path, this takes it over and the
// daemon drops it — the tool's own "Screenshot saved" toast is REPLACED rather than
// duplicated, and the shell's has the picture and actions on it.
//
// That also fixes a real warning. hyprshot passes the file as the notification's ICON
// (`notify-send -i <path>`), so Quickshell tried to load a 4K screenshot through its
// icon loader and logged "Could not load icon … at size QSize(2, 2)" for every shot.
// Consuming the notification before it reaches the icon path removes the cause rather
// than muting the symptom.
//
// No inotify watch, no polling, no second process: the event already existed.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string _home: Quickshell.env("HOME") || ""

    // Where the shell writes its own files (edited copies). Same "" = default
    // convention as the wallpaper paths, resolved in one place.
    readonly property string saveDir: {
        const c = (Config.screenshotDir || "").trim()
        if (c === "")        return root._home + "/Screenshots"
        if (c === "~")       return root._home
        if (c.startsWith("~/")) return root._home + c.slice(1)
        return c
    }

    // ── The shot waiting to be acted on ───────────────────────────────────────
    // One at a time: a burst of screenshots should replace the toast, not stack six of
    // them up the side of the screen. The previous one has already been saved to disk
    // by the tool, so nothing is lost by moving on.
    readonly property string latest:  root._latest
    readonly property bool   pending: root._latest !== ""
    property string _latest: ""

    // Bumped on every new capture. The toast restarts its own timer from this rather
    // than from `latest` changing, so re-taking the SAME path (an edit written back
    // over itself) still re-shows.
    readonly property int captureId: root._captureId
    property int _captureId: 0

    signal captured(string path)

    function present(path) {
        if (!path) return
        root._latest = path
        root._captureId++
        root.captured(path)
        Sfx.play("shutter")
    }

    function dismiss() { root._latest = "" }

    // ── Taking over a tool's notification ─────────────────────────────────────
    // Returns true when this notification WAS a screenshot and has been handled, which
    // tells the daemon to drop it entirely. False means "not mine", and it continues
    // through the normal path untouched.
    function consume(n) {
        if (!n) return false

        const app = String(n.appName || "").toLowerCase()
        const known = (Config.screenshotApps || []).some(
            a => String(a).toLowerCase() === app)
        if (!known) return false

        const path = root._pathFrom(n)
        // A screenshot tool that reports something OTHER than a file — "copied to
        // clipboard only", or an error — is still its own notification and must be left
        // alone. Consuming it would silently swallow a message the user needs.
        if (path === "") return false

        root.present(path)
        return true
    }

    // The file can arrive as the image hint or as the icon: hyprshot uses `-i <path>`,
    // which is nominally the ICON field, and others use image-path. Both are checked,
    // and a `image://` provider handle is explicitly not a file.
    function _pathFrom(n) {
        const cands = [n.image || "", n.appIcon || ""]
        for (const c of cands) {
            let p = String(c)
            if (p === "" || p.indexOf("image://") === 0) continue
            if (p.indexOf("file://") === 0) p = p.substring(7)
            if (p.indexOf("/") !== 0) continue
            if (!/\.(png|jpg|jpeg|webp|gif)$/i.test(p)) continue
            return p
        }
        return ""
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    function copyToClipboard(path) {
        const p = path || root._latest
        if (!p) return
        Clipboard.copyFile(p, root._mimeFor(p))
        root._notify("Screenshot copied", p.split("/").pop())
    }

    function _mimeFor(p) {
        const ext = p.split(".").pop().toLowerCase()
        return ext === "jpg" || ext === "jpeg" ? "image/jpeg"
             : ext === "webp" ? "image/webp"
             : ext === "gif"  ? "image/gif"
             : "image/png"
    }

    // No `openExternally` here any more. It ran `xdg-open`, and the default handler for
    // image/png on this machine is firefox.desktop — so "open the screenshot" launched a
    // browser, which reads as the click doing nothing. The toast's picture opens the
    // shell's own editor instead, and nothing else wanted the external path, so it went
    // rather than sitting here looking like an option.

    // Trash, not unlink. These are the user's files and a mis-click on a toast that
    // auto-dismisses is exactly the situation where "gone forever" is the wrong
    // behaviour — same call the wallpaper gallery's delete makes.
    function remove(path) {
        const p = path || root._latest
        if (!p) return
        trasher.command = ["gio", "trash", p]
        trasher.running = false
        trasher.running = true
        if (p === root._latest) root.dismiss()
    }

    // Makes saveDir exist, then calls `then()`. For a caller that writes a file there
    // itself (the overview's window picture). Requests made while one mkdir runs ride
    // on it — once it exits the folder exists for all of them.
    property var _afterDir: []
    function ensureSaveDir(then) {
        root._afterDir = root._afterDir.concat([then])
        if (!dirMaker.running) dirMaker.running = true
    }
    Process {
        id: dirMaker
        command: ["mkdir", "-p", root.saveDir]
        onExited: {
            const fns = root._afterDir
            root._afterDir = []
            fns.forEach(f => f())
        }
    }

    Process {
        id: trasher
        running: false
        onExited: function(code) {
            if (code !== 0) root._notify("Could not delete", "gio trash failed")
        }
    }

    // ── Notifications of our own ──────────────────────────────────────────────
    // Deliberately NOT routed through the record/toast path — these confirm an action
    // the user just took and belong in the tray's usual place, not in a second
    // screenshot toast on top of the first.
    Process { id: notifyProc; running: false }
    function _notify(title, body) {
        notifyProc.command = ["notify-send", "--app-name=Quickshell",
                              "--urgency=low", "-t", "1500", title, body]
        notifyProc.running = false
        notifyProc.running = true
    }
}
