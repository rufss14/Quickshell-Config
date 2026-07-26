pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Clipboard ─────────────────────────────────────────────────────────────────
// Clipboard history: what you've copied, so you can put it back.
//
// ── Why a singleton, and why it runs all the time ─────────────────────────────
// Every other list-shaped service here is refcounted — acquired when a panel opens,
// released when it closes — and this one deliberately is not. A history that only
// records while you're looking at it is not a history: by the time you open the panel
// wanting the thing you copied five minutes ago, a refcounted watcher would never have
// seen it. So the watcher starts with the shell and stays up.
//
// The cost is one `wl-paste --watch` process. It sleeps on a Wayland event and wakes
// once per clipboard change — no polling, no timer, and nothing runs between copies.
//
// ── The split with scripts/clip-store.py ──────────────────────────────────────
// The script owns STORAGE (writing payloads, dedupe, the cap); this owns the shell's
// view of it (parsing, putting something back on the clipboard, deleting). That line is
// where it is because storage has to handle raw bytes — an image is not a string, and
// pushing binary through QML's process pipes would corrupt it. QML never touches the
// payload: it gets a file path and hands it to `Image`, or to `wl-copy`.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string storeDir:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quicktest/clipboard"
    readonly property string indexPath: root.storeDir + "/index.json"

    // Newest first. Each entry: { hash, kind, mime, file, bytes, at, preview, lines }
    property var entries: []
    readonly property int  count: root.entries.length
    readonly property bool ready: root._loaded

    property bool _loaded: false

    // Set briefly after a copy so the panel can say it landed. Holds the hash of the
    // entry that was put back, "" the rest of the time.
    property string justCopied: ""

    // ── The watcher ───────────────────────────────────────────────────────────
    // `wl-paste --watch CMD` runs CMD once per clipboard change with the contents on its
    // stdin. It fires once immediately at startup too (measured — not assumed), which is
    // how the clipboard you already had survives a shell reload: the store dedupes by
    // content hash, so re-seeing it moves it to the top rather than adding a twin.
    //
    // NOT Quickshell's native `clipboardText`: that is Qt's QClipboard, which on Wayland
    // reads through wl_data_device and only serves the FOCUSED client — a bar essentially
    // never has focus. wl-paste speaks wlr-data-control, the protocol meant for exactly
    // this, and it is also the only one of the two that can see images.
    Process {
        id: watcher
        running: true
        command: ["wl-paste", "--watch",
                  "python3", Quickshell.shellPath("scripts/clip-store.py")]

        // The store prints one line per change. That line — not an inotify watch — is
        // what tells us to re-read: the index is replaced by atomic rename, and a watch
        // on the file follows the inode that rename just orphaned. We already own this
        // pipe, and it reports the exact moment the write completed.
        stdout: SplitParser {
            onRead: function (line) {
                if (line.startsWith("STORED")) index.reload()
            }
        }

        // A watcher that dies takes the whole feature with it SILENTLY — the shell would
        // look like it had merely stopped being copied to. So it comes back up, which is
        // the right answer to the case that actually happens: the compositor going away
        // and returning across a reload.
        //
        // Bounded, though. If wl-paste is missing or the protocol is unavailable it exits
        // instantly, and an unbounded retry would be a hot loop writing a warning per
        // pass. After `_maxRetries` it gives up and says so once.
        onExited: function (exitCode) {
            if (root._retries >= root._maxRetries) {
                console.warn("Clipboard: wl-paste --watch keeps exiting (last code "
                             + exitCode + ") — clipboard history is OFF. Is wl-clipboard installed?")
                return
            }
            root._retries++
            restart.restart()
        }
    }

    property int _retries: 0
    readonly property int _maxRetries: 5

    // Any successful store proves the watcher is healthy, so the budget resets. Without
    // this a shell up for days would spend its five retries on five unrelated blips.
    onEntriesChanged: root._retries = 0

    Timer {
        id: restart
        interval: 2000
        onTriggered: watcher.running = true
    }

    // ── The index ─────────────────────────────────────────────────────────────
    // `watchChanges` is kept as a BACKSTOP, not the primary signal — it catches an
    // external edit (the store pruning, or the directory being cleared from a terminal)
    // that never comes up the watcher's pipe.
    FileView {
        id: index
        path: root.indexPath
        watchChanges: true
        onFileChanged: index.reload()
        onLoaded: root._parse(index.text())
        // An absent index is the normal state before anything has been copied, not a
        // fault. Reporting empty is the honest answer and lets the panel show its
        // empty state rather than a spinner that never resolves.
        onLoadFailed: { root.entries = []; root._loaded = true }
    }

    function _parse(txt) {
        try {
            const list = JSON.parse(txt)
            root.entries = Array.isArray(list) ? list : []
        } catch (e) {
            console.warn("Clipboard: index.json is unreadable —", e)
            root.entries = []
        }
        root._loaded = true
    }

    // ── Putting something back ────────────────────────────────────────────────
    // The payload goes to wl-copy from the FILE, never through a shell string: an entry
    // is arbitrary user content, and interpolating it into a command is how a copied
    // line containing a quote becomes a command. The path is passed as an argument for
    // the same reason.
    //
    // This re-fires the watcher (the clipboard did change), and the store's hash dedupe
    // is what stops that from growing a second row for every paste.
    function copy(entry) {
        if (!entry || !entry.file) return
        writer.command = ["bash", "-c",
                          'wl-copy --type "$1" < "$2"', "bash",
                          entry.mime || "text/plain", entry.file]
        writer.running = true
        root.justCopied = entry.hash
        copiedFlash.restart()
    }

    Timer {
        id: copiedFlash
        interval: 1400
        onTriggered: root.justCopied = ""
    }

    Process { id: writer }

    // ── Removing ──────────────────────────────────────────────────────────────
    // Done in QML rather than by another script: we already hold the parsed index, so
    // this is a filter and a write, and shelling out would mean re-reading, re-parsing
    // and racing the store for the same file.
    //
    // There IS a race left, and it is deliberately not engineered against: copying
    // something in the same instant as deleting a row means one of the two writes wins
    // and the other is lost. Both are human-paced actions by the same pair of hands, and
    // a lock file guarding a list of copied text would cost more than the entry.
    function remove(entry) {
        if (!entry) return
        const left = root.entries.filter(e => e.hash !== entry.hash)
        root.entries = left
        index.setText(JSON.stringify(left))
        if (entry.file) {
            unlink.command = ["rm", "-f", "--", entry.file]
            unlink.running = true
        }
    }

    Process { id: unlink }

    // ── Wiping ────────────────────────────────────────────────────────────────
    // Removes the payloads as well as the list. Clearing only the index would leave
    // every image and every copied line sitting in the cache — the user asked to wipe
    // their clipboard history, and a wipe that leaves the contents on disk is a lie.
    //
    // The store is rebuilt EMPTY rather than left deleted. Removing index.json works —
    // the script treats a missing file as an empty history — but FileView then logs a
    // read failure on every reload, and an ordinary user action should not produce
    // warnings in the shell's log. Writing `[]` costs two bytes and says the same thing.
    //
    // `data` is removed by path rather than by glob, so an empty or unset store
    // directory can't widen the command into an `rm -rf` of something else.
    function wipe() {
        root.entries = []
        wiper.command = ["bash", "-c",
                         'rm -rf -- "$1/data" && mkdir -p "$1/data" && printf "[]" > "$1/index.json"',
                         "bash", root.storeDir]
        wiper.running = true
    }

    Process {
        id: wiper
        onExited: index.reload()
    }

    // ── Display helpers ───────────────────────────────────────────────────────
    // Here rather than in the panel because they describe an ENTRY, and a second view
    // of this list (a launcher mode, say) would need exactly the same sentences.

    function label(entry) {
        if (!entry) return ""
        if (entry.kind === "image") return "Image"
        const t = (entry.preview || "").trim()
        if (t === "") return "(blank)"
        // First non-empty line, so a copied block is identified by its first sentence
        // rather than by whatever whitespace happened to lead it.
        const first = t.split("\n").find(l => l.trim() !== "") || t
        return first.trim()
    }

    function detail(entry) {
        if (!entry) return ""
        const parts = [root.size(entry.bytes)]
        if (entry.kind === "text" && entry.lines > 1)
            parts.push(entry.lines + " lines")
        parts.push(root.age(entry.at))
        return parts.join(" · ")
    }

    // ── Links ─────────────────────────────────────────────────────────────────
    // A URL is still a text entry as far as STORAGE is concerned — it is text, it
    // dedupes like text, it copies back like text. Being a link is a fact about how to
    // DISPLAY it, so it's derived here rather than tagged by the store: tagging would
    // mean every entry written before this existed stays unrecognised forever, and a
    // stored classification can't be improved without a migration.

    // The whole entry must BE a link, not merely contain one. A paragraph that mentions
    // a URL is prose — showing it as a link would hide the text you actually copied
    // behind a hostname. `\s` covers the multi-line case in one test.
    readonly property var _urlRe: /^(https?:\/\/|www\.)[^\s]+$/i

    function isLink(entry) {
        if (!entry || entry.kind !== "text") return false
        return root._urlRe.test((entry.preview || "").trim())
    }

    function _url(entry) {
        const t = (entry && entry.preview || "").trim()
        // `www.example.com` is a link to a human and a relative path to xdg-open, which
        // would try to open it as a file. Scheme added only for opening, never shown.
        return /^www\./i.test(t) ? "https://" + t : t
    }

    // The bit worth reading first. A hostname answers "where does this go", which is the
    // question you have about a link you copied twenty minutes ago; the path rarely is.
    function linkHost(entry) {
        const t = (entry && entry.preview || "").trim()
        const m = t.match(/^(?:https?:\/\/)?(?:[^@\/\n]+@)?([^:\/?#\n]+)/i)
        if (!m) return t
        return m[1].replace(/^www\./i, "")
    }

    // Mirrors linkHost's shape exactly — optional userinfo, host, optional port. An
    // earlier version stopped at the first colon, which made
    // `https://user:pw@host/deep/path` report a "path" of `:pw@host/deep/path`. Caught
    // by testing the parse against real URL forms rather than the ones I had in mind.
    function linkPath(entry) {
        const t = (entry && entry.preview || "").trim()
        const m = t.match(/^(?:https?:\/\/)?(?:[^@\/\n]+@)?[^:\/?#\n]+(?::\d+)?(.*)$/i)
        const rest = m ? m[1] : ""
        return (rest === "" || rest === "/") ? "" : rest
    }

    // Opens in whatever the desktop has registered. The URL is passed as an ARGUMENT,
    // never interpolated into a shell string — a clipboard entry is arbitrary text, and
    // a URL containing a quote or a semicolon is a command otherwise.
    function openLink(entry) {
        if (!root.isLink(entry)) return
        opener.command = ["xdg-open", root._url(entry)]
        opener.running = true
    }

    Process { id: opener }

    function size(bytes) {
        const b = bytes || 0
        if (b < 1024) return b + " B"
        if (b < 1024 * 1024) return (b / 1024).toFixed(b < 10240 ? 1 : 0) + " KB"
        return (b / 1048576).toFixed(1) + " MB"
    }

    function age(at) {
        const secs = Math.max(0, Math.floor(Date.now() / 1000) - (at || 0))
        if (secs < 60)    return "just now"
        if (secs < 3600)  return Math.floor(secs / 60) + "m ago"
        if (secs < 86400) return Math.floor(secs / 3600) + "h ago"
        return Math.floor(secs / 86400) + "d ago"
    }
}
