pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── LyricsTranslate ───────────────────────────────────────────────────────────
// An English (or whatever you pick) line under each lyric, translated ON THIS MACHINE.
//
// scripts/lyrics-translate.py → here → the line under each row in OverviewLyrics.
//
// ── Four backends, local preferred, none required ─────────────────────────────
// argostranslate runs on this machine and is tried first; DeepL's documented API is
// tried next when a key is configured (see hasKey/saveKey below); Google's public
// endpoint over plain HTTP and then MyMemory's API are the fallbacks that need nothing
// installed. Installing argos, or pasting a DeepL key, later silently upgrades the
// privacy/reliability with nothing else to change here.
//
// That order is the DEFAULT. `backends` (below, from Config) overrides it — the Now
// Playing panel's settings reorder the list and drop backends from it entirely, so a
// DeepL key holder who wants every line on DeepL can exclude Google/MyMemory, and
// whoever cares more about idiom than about privacy can lead with `deepl`.
//
// On the network backends, each line of the track IS SENT OUT — to DeepL if a key is
// set, otherwise to Google or MyMemory. No account beyond DeepL's own signup (held only
// in its key), and nothing identifying the listener travels with it, and it happens only
// while the button is on — which is off by default, deliberately, because this config is
// published and that is not a thing a stranger should switch on unknowingly.
//
// ── The blocker is still real ─────────────────────────────────────────────────
// The fallback needs no install, so the usual "not installed" case is gone — but the
// network can be down, the endpoint can refuse, and a language pair can have no local
// model. `blocker()` carries whichever sentence applies and the button reads it rather
// than failing on click, the same contract as Discord.pressBlocker() and
// WallpaperEngine.blocker().
//
// ── The probe costs a request ─────────────────────────────────────────────────
// It translates one short word to prove the whole path works rather than checking for a
// file and hoping. On the fallback backend that is an outbound request, so it runs only
// once translation has actually been switched ON — never on a shell start where nobody
// asked for it.
//
// ── Keyed to the TRACK, never to the position ─────────────────────────────────
// One request per track, deduplicated here and cached on disk for a week by the script.
// Nothing in this file runs on a position tick; a translated line is static once it
// arrives, and re-requesting it as the song plays would spend a local model's CPU on an
// answer that cannot have changed.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property bool enabled: Config.lyricsTranslate
    readonly property string target: Config.lyricsTranslateLang || "en"

    // ── Backend priority, and whether to cache ────────────────────────────────
    // Both are passed straight to the script on every request. `backends` is the
    // order it tries them in (first that answers wins); an id left out is never
    // contacted. `cacheEnabled` gates the script's seven-day disk cache — off
    // means every play re-translates, which is only what you want while comparing
    // backends. The editor for both lives in the Now Playing panel's settings.
    readonly property var allBackends: ["argos", "deepl", "google", "mymemory"]

    readonly property var backends: {
        const chosen = (Config.lyricsTranslateBackends || [])
            .filter(b => root.allBackends.indexOf(b) >= 0)
        // Empty ⇒ the full default order, never "translate with nothing" — the
        // master toggle is how you turn the feature off. The script agrees.
        return chosen.length > 0 ? chosen : root.allBackends
    }
    readonly property bool cacheEnabled: Config.lyricsTranslateCache

    function backendEnabled(id) {
        return (Config.lyricsTranslateBackends || []).indexOf(id) >= 0
    }

    // ── Mutations, kept here rather than in the panel ─────────────────────────
    // "Which translator, in what order" is this service's business, the same way
    // the DeepL key below is. The panel shows the list and calls these.
    function _cleanList() {
        return (Config.lyricsTranslateBackends || [])
            .filter((b, i, a) => root.allBackends.indexOf(b) >= 0 && a.indexOf(b) === i)
    }

    function setBackendEnabled(id, on) {
        if (root.allBackends.indexOf(id) < 0) return
        let list = root._cleanList()
        const at = list.indexOf(id)
        if (on && at < 0)       list.push(id)
        else if (!on && at >= 0) list.splice(at, 1)
        else return
        Config.lyricsTranslateBackends = list
    }

    // dir: -1 earlier (higher priority), +1 later. A no-op at the ends.
    function moveBackend(id, dir) {
        let list = root._cleanList()
        const at = list.indexOf(id)
        const to = at + dir
        if (at < 0 || to < 0 || to >= list.length) return
        list.splice(at, 1)
        list.splice(to, 0, id)
        Config.lyricsTranslateBackends = list
    }

    // Reordering or narrowing the list changes which service a NEW request would
    // reach — and can change the probe's verdict (a key removed, MyMemory turned
    // off). Re-probe so the blocker text keeps up. Nothing already translated is
    // re-requested: the disk cache is keyed by language pair, not by backend, so
    // it stays a hit, and the point of all this is to spend LESS on the network.
    onBackendsChanged: if (root.enabled && root._probed) root._probe()

    // "idle" | "probing" | "loading" | "ready" | "none" | "error"
    property string state: "idle"

    // Translated lines, index-aligned with Lyrics.lines. Empty until one arrives.
    property var    lines: []
    property string sourceLang: ""
    property string lastError: ""

    // ── Which backend produced what is on screen ─────────────────────────────
    // "argos" | "deepl" | "google" | "mymemory", or "" before an answer. The
    // script returns it in the payload — disk cache included — so a track served
    // from cache still reports where it originally came from. Blank for entries
    // cached before this field existed; they refresh within the week.
    property string backend: ""

    readonly property var backendNames: ({
        "argos":    "On-device",
        "deepl":    "DeepL",
        "google":   "Google",
        "mymemory": "MyMemory"
    })
    readonly property string backendUsed: root.backendNames[root.backend] || root.backend

    // Filled from the script's `install` hint, so the reason can name the exact command.
    property string installHint: ""

    // Was the track already in the target language? Not an error — there is simply
    // nothing to show, and saying "failed" for a song already in English would be a lie.
    property bool skipped: false

    readonly property bool hasLines:
        root.state === "ready" && root.lines.length > 0 && !root.skipped

    // ── blocker() ─────────────────────────────────────────────────────────────
    // "" when translation can actually run, or when nothing has been tried yet — the
    // button has to stay clickable to be switched on in the first place. Otherwise the
    // sentence to show the user.
    //
    // Probed rather than assumed, because a backend can be present and still unable to do
    // a particular pair, and the network can be down under either of them.
    property bool _probed: false
    property string _probeResult: ""

    function blocker() {
        return root._probeResult
    }

    // ── Probed only once the feature is ON ────────────────────────────────────
    // The probe is a real translation of one word, which on the fallback backend means an
    // outbound request. Running it at startup regardless would send that request on every
    // shell start on every machine that installs this config, to test a feature nobody
    // had switched on. It waits for the switch instead.
    //
    // The cost of waiting is that the button reads "checking…" for the moment after it is
    // first enabled, which is honest — that is exactly what is happening.
    // Both responsibilities live here because a signal may only be handled ONCE per object:
    // a second `onEnabledChanged` on the same singleton is a duplicate-handler error, not
    // an addition.
    onEnabledChanged: {
        if (root.enabled) {
            // Re-probe whenever the last attempt did NOT succeed. `_probed` used to latch
            // on the first result, so a probe that failed once — no network for a moment,
            // the endpoint briefly refusing — left the blocker set for the whole session
            // and translation permanently unavailable with no way to retry short of a
            // reload. Switching the feature back on is exactly the moment to try again.
            if (!root._probed || root._probeResult !== "") root._probe()
        } else {
            // Turning it off mid-track must drop what is on screen; turning it back on
            // re-requests rather than showing a stale answer from a previous song.
            root._key = ""
            root.clear()
        }
    }

    Component.onCompleted: {
        if (root.enabled) root._probe()
        else root._probeResult = ""      // nothing known against it yet; the switch decides
        root.refreshKeys()
    }

    function _probe() {
        root.state = "probing"
        root._probeResult = "checking the translator…"
        probeProc.out = ""
        probeProc.running = true
    }

    // A tiny request with one word in a script that is definitely not English. It exercises
    // the whole path — library present, model installed, translation callable — rather
    // than checking for a file and hoping.
    property Process probeProc: Process {
        property string out: ""

        command: ["python3", Quickshell.shellPath("scripts/lyrics-translate.py")]
        stdinEnabled: true

        stdout: SplitParser { onRead: function (line) { probeProc.out += line } }

        onStarted: {
            write(JSON.stringify({
                lines: ["こんにちは"],   // one kana word
                to: root.target,
                backends: root.backends,
                // Keyed to the chain so a reorder re-tests rather than reading a
                // stale "it worked" from a backend that is no longer first.
                key: "__probe__:" + root.backends.join(",")
            }))
            stdinEnabled = false
        }

        onExited: {
            root._probed = true
            try {
                const d = JSON.parse(probeProc.out)
                if (d.ok) {
                    root._probeResult = ""
                } else {
                    root._probeResult = d.error || "translation unavailable"
                    root.installHint = d.install || ""
                }
            } catch (e) {
                root._probeResult = "the local translator could not be run"
            }
            root.state = "idle"
        }
    }

    // ── Request ───────────────────────────────────────────────────────────────
    property string _key: ""

    // ── Answers already given this session ────────────────────────────────────
    // The script caches on disk for a week, which is what makes a repeat cheap — measured
    // at 28ms against 202ms, and nearly all of that 28ms is Python starting up. But cheap
    // is not free, and it is not INSTANT: `_key` only ever remembered the current track, so
    // skipping back one song still spawned a process, still passed through `clear()`, and
    // the card still blanked and showed its loading dots for a beat before the same answer
    // came back.
    //
    // Holding the answers keyed the same way the script keys its files makes a track played
    // twice in one session cost nothing at all and, more visibly, never flicker. The disk
    // cache stays exactly as it is — this is the layer in front of it, for the case where
    // the process spawn is the only thing left to remove.
    //
    // Bounded, because a long session is a lot of tracks and these are whole songs of text.
    property var _memo: ({})
    property var _memoOrder: []
    readonly property int _memoMax: 24

    function _remember(key, payload) {
        if (root._memo[key] === undefined) {
            const order = root._memoOrder.slice()
            order.push(key)
            while (order.length > root._memoMax) {
                const drop = order.shift()
                delete root._memo[drop]
            }
            root._memoOrder = order
        }
        root._memo[key] = payload
    }

    // Apply a remembered answer. Same field order as onExited — state settled before
    // lines — so a consumer reacting to either signal sees one consistent result.
    function _applyMemo(m) {
        root.lastMs     = 0
        root.lastCached = true
        root.sourceLang = m.from
        root.backend    = m.backend || ""
        root.skipped    = m.skipped
        root.state      = m.lines.length > 0 ? "ready" : "none"
        root.lines      = m.lines
    }

    function clear() {
        root.lines = []
        root.sourceLang = ""
        root.backend = ""
        root.skipped = false
        root.state = "idle"
    }

    // `key` identifies the track, `texts` are its lines in order.
    function load(key, texts) {
        if (!root.enabled)          { root._key = ""; root.clear(); return }
        if (!key || !texts || texts.length === 0) { root._key = ""; root.clear(); return }
        // ── No blocker check here, deliberately ───────────────────────────────
        // This used to refuse while `blocker()` was non-empty — which INCLUDES the moment
        // the probe is running. Enabling the feature starts the probe and requests a
        // translation in the same breath, so the request arrived while the blocker still
        // said "checking…", was dropped, and nothing re-ran it when the probe cleared.
        // The first enable therefore did nothing and the second worked, forever
        // alternating.
        //
        // There is nothing to check for anyway: the script reports its own failures, so a
        // missing backend comes back as ok:false with a reason and lands in `state`. Asking
        // twice only created a window where the answer was "not yet".
        if (key === root._key)      return          // same track — already have it

        root._key = key
        root._retried = false
        retryTimer.stop()

        // Answered this session already: no process, no clear(), no loading state. The card
        // goes straight from one track's lines to the other's. Skipped when caching is
        // off — that switch means "re-translate every play", and this in-memory layer is
        // still a cache.
        const m = root.cacheEnabled ? root._memo[key] : undefined
        if (m !== undefined) { root._applyMemo(m); return }

        root.clear()
        root.state = "loading"

        root._startedAt = Date.now()
        root.lastCount = texts.length
        root.runs += 1

        proc.out = ""
        proc.pending = JSON.stringify({
            lines: texts, to: root.target, key: key,
            backends: root.backends, cache: root.cacheEnabled
        })

        // ── Re-arm stdin before every run ─────────────────────────────────────
        // `stdinEnabled: true` is an initial value, and onStarted below ASSIGNS it false —
        // which is not a binding being re-evaluated, it is the property permanently set.
        // So the second run of this process, and every one after it, started with no stdin
        // at all: write() went nowhere, the script read EOF and answered "bad request", and
        // translation was dead for the rest of the session with a reload as the only cure.
        proc.stdinEnabled = true
        proc.running = true
    }

    // Set while a retry is outstanding, cleared by the next successful answer or by a new
    // track. One per request, never per session.
    property bool _retried: false

    Timer {
        id: retryTimer
        interval: 1500
        repeat: false

        // The request this retry belongs to. A skip during the wait moves `_key` on, and
        // re-running the old payload would put the previous song's translation under the
        // current song's lyrics.
        property string forKey: ""

        onTriggered: {
            if (retryTimer.forKey !== root._key) return
            if (root.state !== "error") return
            root.state = "loading"
            root._startedAt = Date.now()
            root.runs += 1
            proc.out = ""
            proc.stdinEnabled = true
            proc.running = true
        }
    }

    property Process proc: Process {
        property string out: ""
        property string pending: ""

        command: ["python3", Quickshell.shellPath("scripts/lyrics-translate.py")]
        stdinEnabled: true

        stdout: SplitParser { onRead: function (line) { proc.out += line } }

        onStarted: {
            write(proc.pending)
            stdinEnabled = false
        }

        onExited: {
            const text = proc.out
            proc.out = ""

            try {
                const d = JSON.parse(text)
                if (!d.ok) {
                    root.lastError = d.error || "translation failed"
                    root.installHint = d.install || root.installHint
                    root.state = "error"

                    // ── One retry, then stop ──────────────────────────────────
                    // The common failure here is a moment of no network — a laptop coming
                    // back from suspend, the endpoint refusing one request — and the whole
                    // track then stayed untranslated until the NEXT song, because nothing
                    // re-asks: the key is already recorded, so every later signal
                    // deduplicates against it and returns.
                    //
                    // Exactly one attempt, and only for a request that is still current.
                    // A retry loop against a genuinely unreachable endpoint is a request
                    // every few seconds for as long as the song lasts.
                    if (!root._retried) {
                        root._retried = true
                        retryTimer.forKey = root._key
                        retryTimer.restart()
                    }
                    return
                }
                root._retried = false
                root.lastMs     = Date.now() - root._startedAt
                root.lastCached = d.cached === true

                // Counts and timings only — never the text. The words are the one thing
                // that has no business in a diagnostic.
                root.backend    = d.backend || ""

                const h = root.history.slice(-9)
                h.push({ n: root.lastCount, ms: Math.round(root.lastMs),
                         cached: root.lastCached, src: root.backend,
                         key: root._key.slice(0, 28) })
                root.history = h
                root.sourceLang = d.from || ""
                root.skipped    = d.skipped === true

                // Kept so the same track later in the session costs neither a process nor
                // a visible loading state. Stored before the properties are published so a
                // consumer reacting to them can already find it.
                root._remember(root._key, {
                    from:    root.sourceLang,
                    backend: root.backend,
                    skipped: root.skipped,
                    lines:   d.lines || []
                })

                // Order matters to consumers: anything reading `hasLines` on
                // onLinesChanged would see state still "loading" and conclude there is
                // nothing to show. Settle the state FIRST so a single notification is
                // enough to describe the whole result.
                root.state      = (d.lines || []).length > 0 ? "ready" : "none"
                root.lines      = d.lines || []
            } catch (e) {
                console.warn("LyricsTranslate: could not parse output —", e)
                root.state = "error"
            }
        }
    }

    // ── The DeepL key ──────────────────────────────────────────────────────────
    // Same contract as Ai.hasKey/Discord.hasSecret: this only ever learns a boolean.
    // The key itself is typed into MiscPage, handed to
    // scripts/lyrics-translate-credentials.py over stdin, written 0600 there, and read
    // back inside lyrics-translate.py — never through QML.
    property bool hasDeeplKey: false

    function refreshKeys() { keyStatusProc.running = false; keyStatusProc.running = true }

    property Process keyStatusProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/lyrics-translate-credentials.py"),
                  "--status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hasDeeplKey = ((JSON.parse(text) || {}).has || {}).deepl === true }
                catch (e) { root.hasDeeplKey = false }
            }
        }
    }

    property string _pendingKeyPatch: ""

    function saveDeeplKey(key) {
        const k = (key || "").trim()
        if (k === "") return
        root._pendingKeyPatch = JSON.stringify({ deepl: k })
        keyWriteProc.running = false
        keyWriteProc.running = true
    }

    // An explicit empty string is what lyrics-translate-credentials.py reads as "clear
    // this one" — omitting the field would mean "leave it alone".
    function removeDeeplKey() {
        root._pendingKeyPatch = JSON.stringify({ deepl: "" })
        keyWriteProc.running = false
        keyWriteProc.running = true
    }

    property Process keyWriteProc: Process {
        command: ["python3", Quickshell.shellPath("scripts/lyrics-translate-credentials.py")]
        stdinEnabled: true
        onRunningChanged: if (running) stdinEnabled = true
        onStarted: {
            write(root._pendingKeyPatch + "\n")
            stdinEnabled = false
            // Dropped as soon as it is handed over — holding it would keep the key in a
            // QML property for the rest of the session for no reason at all.
            root._pendingKeyPatch = ""
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try { root.hasDeeplKey = ((JSON.parse(text) || {}).has || {}).deepl === true }
                catch (e) { root.refreshKeys() }
            }
        }
    }

    // ── Timing, kept rather than guessed at ───────────────────────────────────
    // "Slow" is not a diagnosis. These record where the time actually went, so the next
    // person to ask does not have to reason about it from the source.
    property real lastMs: 0          // wall time of the last script run
    property int  lastCount: 0       // lines it was asked for
    property bool lastCached: false  // did the script answer from its own disk cache
    property real _startedAt: 0

    // How many script runs this session, and a short history of what each one cost.
    // "Sometimes slow" is a pattern, not an event — it needs more than the last value.
    property int  runs: 0
    property var  history: []

    IpcHandler {
        target: "lyricstranslate"

        // Flip the setting without the overlay. The button is the normal way in; this
        // exists so the path can be driven from a script while measuring it.
        function toggle(): string {
            Config.lyricsTranslate = !Config.lyricsTranslate
            return Config.lyricsTranslate ? "on" : "off"
        }

        function runlog(): string {
            let out = "runs this session: " + root.runs + "\n"
            for (const h of root.history)
                out += "  " + h.n + " lines  " + h.ms + "ms"
                     + (h.cached ? "  cache" : "  fetch")
                     + (h.src ? "  " + h.src : "")
                     + "   key=" + h.key + "\n"
            return out
        }

        function timing(): string {
            return root.lastCount + " lines in " + root.lastMs.toFixed(0) + "ms"
                 + (root.lastCached ? " (from cache)" : " (fetched)")
                 + (root.backend ? "  via " + root.backend : "")
                 + "  state=" + root.state
        }

        function status(): string {
            const chain = root.backends.join(" → ")
                        + (root.cacheEnabled ? "  cache:on" : "  cache:off")
            const b = root.blocker()
            if (b !== "") return "unavailable: " + b
                                + (root.installHint ? "  (" + root.installHint + ")" : "")
                                + "\n" + chain
            if (!root.enabled) return "off\n" + chain
            return root.state
                 + (root.sourceLang ? "  " + root.sourceLang + " → " + root.target : "")
                 + (root.backend ? "  via " + root.backend
                                            + (root.lastCached ? " (cached)" : "") : "")
                 + (root.skipped ? "  (already in " + root.target + ")" : "")
                 + "  " + root.lines.length + " lines"
                 + "\n" + chain
        }
    }
}
