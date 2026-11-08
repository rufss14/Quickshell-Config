pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"
import "lens.js" as L

// ── Lens ──────────────────────────────────────────────────────────────────────
// Read the text off any part of the screen, and translate it in place. Drag out a
// region (slurp), it's captured (grim) and read (scripts/lens.py → tesseract), and the
// region freezes under an overlay (modules/panels/LensOverlay) with every line boxed:
// click a line to copy it, copy all, search it — or translate, and each line is
// painted over with its translation where it stood, Google-Lens style.
//
//   start("text")       read it
//   start("translate")  read it, then translate it at once
//
// Opened by the sidebar's Lens module (SideLens), or `qs ipc … call lens text|translate`
// (hypr/binds.lua: SUPER+O / SUPER+SHIFT+O).
//
// ── Translation sends the text out — unless argos is installed ───────────────
// It's scripts/lyrics-translate.py with the lyrics' own backend order
// (Config.lyricsTranslateBackends: argos locally first, then DeepL / Google /
// MyMemory over the network), no cache. Only on a click — the overlay says which
// backend answered. The capture itself never leaves the machine: OCR is local.
//
// ── The capture ───────────────────────────────────────────────────────────────
// A file under $XDG_RUNTIME_DIR (tmpfs), a fresh name per read so the overlay's Image
// never shows a cached older one; the previous one is removed. Optional deps:
// tesseract (+ tesseract-data-<lang>); grim and slurp are already the shell's.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // "" | "selecting" | "reading" | "shown" | "translating"
    property string phase: ""
    property string mode: "text"
    readonly property bool open: root.phase === "reading" || root.phase === "shown" || root.phase === "translating"
    readonly property bool busy: root.phase === "selecting" || root.phase === "reading" || root.phase === "translating"

    property var    region: null      // { x, y, w, h, output } — global, logical
    property string image: ""
    property int    imageW: 0
    property int    imageH: 0
    property var    lines: []         // [{ text, x, y, w, h, block, conf }] — image px
    property string text: ""
    property var    translated: []    // one per line, once translated
    property string via: ""           // which backend translated, or "" / "already <lang>"
    property bool   showTranslation: false
    property string error: ""
    property string install: ""       // what to install, when that's the error

    readonly property string target: Config.lensTranslateLang || Config.lyricsTranslateLang || "en"

    function blocker() {
        if (!root._probed) return ""
        if (!root.hasTesseract) return "Needs tesseract (pacman -S tesseract tesseract-data-eng)"
        return ""
    }

    // ── Commands ──────────────────────────────────────────────────────────────
    function start(mode) {
        if (root.busy || root.blocker() !== "") return
        root.close()
        root.mode = mode === "translate" ? "translate" : "text"
        UiState.closeSidePanel()
        root.phase = "selecting"
        slurpProc.running = true
    }
    // ── The snip tool's hand-over (services/Snip) ─────────────────────────────
    // The region is already chosen and already cropped to `image` (a path from
    // nextImage(), under `dir`), so skip slurp and grim and go straight to reading it.
    // `region` is { x, y, w, h, output }, global and logical — the same shape slurp gave.
    function nextImage() {
        root._n++
        return root.dir + "/shot-" + root._n + ".png"
    }
    function adopt(region, image, mode) {
        if (root.busy || root.blocker() !== "") return
        const prev = root.image
        root.close()
        root.mode = mode === "translate" ? "translate" : "text"
        UiState.closeSidePanel()
        root.region = region
        root.image = image
        root.phase = "reading"
        if (prev !== "" && prev !== image) Quickshell.execDetached(["rm", "-f", prev])
        ocrProc.command = ["python3", Quickshell.shellPath("scripts/lens.py"), "ocr", root.image,
                           "--lang", Config.lensOcrLangs || "auto"]
        ocrProc.running = true
    }
    function close() {
        root.phase = ""
        root.lines = []
        root.translated = []
        root.text = ""
        root.error = ""
        root.install = ""
        root.via = ""
        root.showTranslation = false
    }
    function translate() {
        if (root.lines.length === 0 || root.phase === "translating") return
        if (root.translated.length === root.lines.length) { root.showTranslation = true; return }
        root.phase = "translating"
        root.error = ""
        trProc.payload = JSON.stringify({
            lines: root.lines.map(l => l.text), to: root.target, key: "lens",
            backends: Config.lyricsTranslateBackends, cache: false })
        trProc.stdinEnabled = true
        trProc.running = true
    }
    function copyAll() {
        Clipboard.copyText(L.copyText(root.lines, root.translated, root.showTranslation))
    }
    function copyLine(i) {
        const t = root.showTranslation && root.translated.length === root.lines.length
                  ? root.translated[i] : (root.lines[i]?.text ?? "")
        Clipboard.copyText(t)
    }
    function search() {
        const q = (root.showTranslation ? root.translated.join(" ") : root.text).replace(/\s+/g, " ").trim()
        if (q !== "") Qt.openUrlExternally("https://duckduckgo.com/?q=" + encodeURIComponent(q.slice(0, 400)))
    }

    // ── Pipeline ──────────────────────────────────────────────────────────────
    readonly property string dir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/quickshell-quicktest-lens"
    property int _n: 0

    Process {
        id: slurpProc
        command: ["slurp", "-d", "-f", "%x %y %w %h %o"]
        stdout: StdioCollector {
            // A cancelled drag prints nothing and exits non-zero: back to idle, quietly.
            onStreamFinished: {
                const r = L.parseRegion(text)
                if (r === null) { root.phase = ""; return }
                root.region = r
                root._n++
                const prev = root.image
                root.image = root.dir + "/shot-" + root._n + ".png"
                root.phase = "reading"
                grabProc.command = ["sh", "-c",
                    'mkdir -p "$1" && chmod 700 "$1" && rm -f "$4" && grim -g "$2" "$3"',
                    "sh", root.dir, L.grimGeometry(r), root.image, prev]
                grabProc.running = true
            }
        }
    }
    Process {
        id: grabProc
        onExited: function (code) {
            if (code !== 0) { root._fail("Couldn't capture the region"); return }
            ocrProc.command = ["python3", Quickshell.shellPath("scripts/lens.py"), "ocr", root.image,
                               "--lang", Config.lensOcrLangs || "auto"]
            ocrProc.running = true
        }
    }
    Process {
        id: ocrProc
        stdout: StdioCollector {
            onStreamFinished: {
                let r
                try { r = JSON.parse(text) } catch (e) { root._fail("The reader said something odd"); return }
                if (!r.ok) { root.install = r.install || ""; root._fail(r.error || "Couldn't read it"); return }
                root.imageW = r.width
                root.imageH = r.height
                root.lines = r.lines || []
                root.text = r.text || ""
                root.phase = "shown"
                if (root.lines.length === 0)
                    // Nothing read, and only English can be read: the likeliest reason, so say it.
                    root.error = root.onlyEnglish
                        ? "No text found — only English is installed for reading text (Settings › Setup)"
                        : "No text found here"
                else if (root.mode === "translate") root.translate()
            }
        }
    }
    Process {
        id: trProc
        property string payload: ""
        command: ["python3", Quickshell.shellPath("scripts/lyrics-translate.py")]
        stdinEnabled: true
        onStarted: { trProc.write(trProc.payload + "\n"); trProc.stdinEnabled = false }
        stdout: StdioCollector {
            onStreamFinished: {
                root.phase = root.lines.length > 0 ? "shown" : root.phase
                let r
                try { r = JSON.parse(text) } catch (e) { root.error = "The translator said something odd"; return }
                if (!r.ok) { root.error = r.error || "Couldn't translate it"; return }
                const out = r.lines || []
                if (out.length !== root.lines.length) { root.error = "The translation came back the wrong shape"; return }
                root.translated = out
                root.via = r.skipped ? "already " + (r.to || root.target) : (r.backend || r.via || "")
                root.showTranslation = true
            }
        }
    }

    function _fail(msg) {
        root.error = msg
        root.phase = root.region ? "shown" : ""
    }

    // ── Installed? ────────────────────────────────────────────────────────────
    property bool hasTesseract: false
    property bool _probed: false
    Process {
        running: true
        command: ["sh", "-c", "command -v tesseract >/dev/null 2>&1 && echo yes || echo no"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.hasTesseract = text.trim() === "yes"
                root._probed = true
                if (root.hasTesseract) langsProc.running = true
            }
        }
    }

    // The languages tesseract has data for, so the shell can say when reading another language
    // is hopeless instead of returning an empty box. Asked once, after tesseract is known.
    property var  ocrLangs: []
    readonly property bool onlyEnglish: root.ocrLangs.length > 0 && root.ocrLangs.every(l => l === "eng")
    function refreshLangs() { langsProc.running = false; langsProc.running = true }
    Process {
        id: langsProc
        command: ["python3", Quickshell.shellPath("scripts/lens.py"), "langs"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text)
                    if (r.ok) root.ocrLangs = r.langs
                } catch (e) { }
            }
        }
    }

    IpcHandler {
        target: "lens"
        function text(): void      { root.start("text") }
        function translate(): void { root.start("translate") }
        function close(): void     { root.close() }
        function status(): string {
            return "phase=" + root.phase + " mode=" + root.mode + " lines=" + root.lines.length
                 + " translated=" + root.translated.length + " tesseract=" + root.hasTesseract
                 + (root.error !== "" ? " error=" + root.error : "")
        }
    }
}
