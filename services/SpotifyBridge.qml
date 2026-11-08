pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "spicylyrics.js" as SpicyLyrics

// ── SpotifyBridge ─────────────────────────────────────────────────────────────
// Spotify's OWN playhead, pushed out of the app by a Spicetify extension.
//
//   ~/.config/spicetify/Extensions/quickshell-bridge.js   (inside Spotify)
//        │  POST on songchange / play-pause / seek
//        ▼
//   scripts/spotify-bridge.py                             (loopback listener)
//        │  one JSON line per anchor, on stdout
//        ▼
//   this service                                          (anchor + monotonic clock)
//
// ── Why not just use MPRIS ────────────────────────────────────────────────────
// MPRIS gives a coarse, laggy approximation of the playhead — fine for a progress bar,
// not fine for word-level lyrics where a syllable is ~250ms. The extension reports the
// number Spotify is drawing its own progress bar from.
//
// It also carries the track URI, which is the real prize: `spotify:track:…` is an exact
// identity. scripts/lyrics.py currently matches on artist/title/duration and its own
// header calls the failure mode out — the wrong recording's lyrics, confidently in sync
// with nothing. A URI cannot be ambiguous.
//
// ── ANCHORS, not a stream ─────────────────────────────────────────────────────
// About five messages a song. Everything between them is derived here from elapsed wall
// time, exactly as OverviewNowPlaying does for the MPRIS path — same reasoning, better
// anchor. Nothing in this file runs per-frame; consumers read `position` when they
// render.
//
// ── It is OPTIONAL, and absence is normal ─────────────────────────────────────
// No Spotify, no Spicetify, extension not applied, listener port taken — all of these
// end with `available: false` and every consumer falling back to MPRIS. This must never
// be a hard dependency of the media card.
//
// ── WHY THE SYNC BREAKS, AND WHERE TO LOOK ────────────────────────────────────
// Three processes with no view of each other: an extension inside Spotify, a listener
// holding a loopback port, and this. A failure in any of them looks identical from the
// card — no lyrics, red cross — so the only way to tell them apart is to ask.
//
//     qs ipc -c ~/.config/quicktest call spotify lyrics
//
// reports which stage stopped, and its output maps directly onto the cause:
//
//   "bridge: no", no error line
//       Nothing was ever ATTEMPTED. Either the extension is dead (see failure 2 in
//       quickshell-bridge.js — it throws at load and is silent about it), or the shell
//       restarted and this session simply has not been re-told yet. The extension
//       re-states a cached payload every ~20s off `onprogress`; give it that long before
//       concluding anything.
//
//   "last error: no access token"
//       The Spicetify token API moved. Verify against helper/spicetifyWrapper.js.
//
//   "last error: http 400 — …"
//       Their server rejected the request; the message says which field. Nearly always
//       the pinned client version.
//
//   "last error: payload did not map — …"
//       The request WORKED and the shape changed. The structure is printed beside it —
//       types and counts only, never the words themselves.
//
//   status "error"
//       The listener could not bind. Almost always a previous shell's listener still
//       holding the port; see spotify-bridge.py.
//
//   status "listening (no track)", and it stays there
//       PLAY SOMETHING before investigating. The anchor heartbeat rides `onprogress`,
//       which is the only signal Chromium does not throttle — and which requires
//       playback. Paused, with the window hidden, after a shell restart, there is no
//       unthrottled event left and the bridge is genuinely silent. It is indistinguishable
//       from a dead extension and is not one. Clears on play. See failure 8 in
//       quickshell-bridge.js.
//
// ── The timing is a separate question from the words ──────────────────────────
// A live playhead with no lyrics means the anchor path works and the fetch does not —
// those are independent, and conflating them wasted a lot of time. `status` answers the
// first, `lyrics` the second.
//
// ── Why anything here reports at all ──────────────────────────────────────────
// `lastLyricsError` exists because a fetch throwing on every single track was
// indistinguishable, on screen, from a track that genuinely has no lyrics. The failure
// was invisible for four rounds of debugging. Anything added here that can fail must
// leave a reason behind, not just a console line nobody will be watching for.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool enabled: true

    // ── What the extension last told us ───────────────────────────────────────
    property string trackUri:   ""
    property string title:      ""
    property string artist:     ""
    property string album:      ""
    property real   duration:   0        // seconds
    property bool   playing:    false

    // "off" | "starting" | "waiting" | "live" | "error"
    //   waiting — the listener is up but Spotify has never spoken to it
    property string state: "off"
    property string lastError: ""

    readonly property bool listening: root.state === "waiting" || root.state === "live"

    // ══ IS IT SET UP? — a different question from "is it connected" ═══════════
    // `state`/`available` above answer "is Spotify talking to us RIGHT NOW", which is
    // a runtime fact and the right one for the lyrics card. It is the WRONG one for a
    // setup page, and conflating them is why a correctly-installed bridge reported
    // itself as missing: with Spotify closed the state is "waiting", and "waiting"
    // rendered with a warning glyph is indistinguishable from "you never installed
    // this".
    //
    // These four are install facts. They are true with Spotify shut, they stay true
    // across reboots, and together they say exactly which of the three setup steps
    // has not been done yet.
    //
    // ── Asked of spicetify, not of the filesystem ─────────────────────────────
    // `spicetify path userdata` and `spicetify config extensions` are its own
    // authoritative answers. Reading ~/.config/spicetify/config-xpui.ini directly
    // would be a second implementation of where spicetify keeps its things — and a
    // wrong one on any install that moved it. Both are read-only queries.
    property bool   _setupProbed: false
    property bool   _spicetify:   false
    property bool   _extFile:     false
    property bool   _extEnabled:  false

    readonly property bool setupProbed:      root._setupProbed
    readonly property bool spicetifyPresent: root._spicetify
    readonly property bool extensionPresent: root._extFile
    readonly property bool extensionEnabled: root._extEnabled

    // Fully installed as far as anything off-line can tell. Whether Spotify has been
    // PATCHED (`spicetify apply`) is deliberately not claimed here: there is no
    // reliable read-only way to ask, and guessing would be worse than saying so.
    readonly property bool setupComplete:
        root._spicetify && root._extFile && root._extEnabled

    // The first unfinished step, or "" — same contract as every other blocker() in
    // the shell (NightLight, WallpaperEngine).
    function setupBlocker() {
        if (!root._setupProbed) return "Checking the Spicetify install…"
        if (!root._spicetify)   return "Needs the spicetify package"
        if (!root._extFile)     return "quickshell-bridge.js is not in Spicetify's Extensions folder"
        if (!root._extEnabled)  return "The extension is installed but not enabled"
        return ""
    }

    property Process _setupProbe: Process {
        running: true
        // One shot, three facts, no shell-side parsing beyond splitting on spaces.
        // `spicetify config extensions` prints the configured list; the grep is for
        // the filename because the list is comma-separated and may hold others.
        command: ["bash", "-c",
                  "command -v spicetify >/dev/null 2>&1 || { echo '0 0 0'; exit 0; }; "
                + "d=$(spicetify path userdata 2>/dev/null); "
                + "[ -n \"$d\" ] && [ -f \"$d/Extensions/quickshell-bridge.js\" ] && f=1 || f=0; "
                + "spicetify config extensions 2>/dev/null | grep -q 'quickshell-bridge.js' && e=1 || e=0; "
                + "echo \"1 $f $e\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                root._spicetify  = p[0] === "1"
                root._extFile    = p[1] === "1"
                root._extEnabled = p[2] === "1"
                root._setupProbed = true
            }
        }
    }

    // Re-run the install probe. The setup page offers this because the whole point of
    // that page is that you go and fix something in a terminal and come back — a
    // status frozen at whatever was true when the shell started would send you off to
    // reload for no reason.
    function recheckSetup() {
        root._setupProbed = false
        root._setupProbe.running = false
        root._setupProbe.running = true
    }

    // ── Lyrics, when the extension managed to fetch them ──────────────────────
    // `{ kind, lines, plain }` — the same shape scripts/lyrics.py prints, already mapped
    // by spicylyrics.js. Null whenever nothing usable arrived, which is a normal state:
    // the shell's own two-provider lookup is the fallback and covers everything this
    // does not.
    property var    lyrics: null
    property string lyricsUri: ""

    // Why the last fetch failed, if it did. Kept rather than only logged: a fetch that
    // throws on every track is indistinguishable on screen from a track with no lyrics.
    property string lastLyricsError: ""

    // ── Attempted, regardless of outcome ──────────────────────────────────────
    // The uri of the last "lyrics" message this side actually processed — success OR
    // failure, unlike `lyricsUri` (only ever a HIT) and `lastLyricsError` (only ever a
    // MISS, and not tagged to which track it was about). Lyrics.qml needs this to tell
    // "the bridge hasn't answered for THIS track yet" from "it answered, and the answer
    // was no" — the first should read as still connecting, the second as no lyrics.
    // Same "attempted is not the same as succeeded" split the extension itself keeps
    // (`lyricsHaveFor` vs `lyricsTriedFor`), for the same reason.
    property string lyricsTriedUri: ""

    // Latched so the "lyrics connected" notification fires once a session rather than
    // once a song.
    property bool _notified: false

    property Process _notifyProc: Process {
        id: notifyProc
        running: false
    }

    readonly property bool hasLyrics:
        root.lyrics !== null && root.lyricsUri !== "" && root.lyricsUri === root.trackUri

    // ── The anchor ────────────────────────────────────────────────────────────
    property real _anchorPos: 0          // seconds, at the moment of the anchor
    property real _anchorMs:  0          // Date.now() when we received it

    // Seconds since the last anchor arrived. Also the staleness measure.
    readonly property real sinceAnchor:
        root._anchorMs > 0 ? (Date.now() - root._anchorMs) / 1000 : 1e9

    // ── position ──────────────────────────────────────────────────────────────
    // NOT a bound property: a binding on Date.now() never re-evaluates, because nothing
    // notifies. Consumers call this when they draw — OverviewNowPlaying does that once a
    // frame off its FrameAnimation.
    function position() {
        if (!root.playing) return root._anchorPos
        return root._anchorPos + (Date.now() - root._anchorMs) / 1000
    }

    // ── available ─────────────────────────────────────────────────────────────
    // "Is this playhead worth trusting right now?" Two ways it stops being:
    //
    //   · Spotify quit. No goodbye is sent — the app is simply gone — so a paused anchor
    //     would otherwise sit here looking authoritative forever. Consumers pair this
    //     with the MPRIS player still being Spotify, which is the real liveness signal.
    //   · We ran off the end of the track, meaning a songchange was missed. Interpolating
    //     past the duration is how a lyrics view ends up confidently past the last line.
    signal restyleAsked(bool listening)
    signal restyled(int sheets, int loaded, int ms)

    readonly property bool available:
        root.state === "live"
        && root.trackUri !== ""
        && !(root.playing && root.duration > 0 && root.position() > root.duration + 5)

    function _num(v, fallback) {
        const n = Number(v)
        return isFinite(n) ? n : fallback
    }

    function _ingest(line) {
        let d
        try {
            d = JSON.parse(line)
        } catch (e) {
            console.warn("SpotifyBridge: unparseable line:", line.substring(0, 120))
            return
        }

        if (d.type === "ready") {
            root._relaunches = 0
            root.state = "waiting"
            root.lastError = ""
            return
        }

        if (d.type === "error") {
            root.state = "error"
            root.lastError = d.error || "bridge failed"
            console.warn("SpotifyBridge:", root.lastError)
            return
        }

        // ── The wave's restyle (reload-theme.sh → bridge → extension → here) ────
        // `restyle`: a repaint was asked for, and whether an extension was there to
        // hear it. `restyled`: the extension's word that the new sheets are loaded and
        // painted. Contagion holds the wave's front on the second, or not at all
        // without the first. A reattach replays old lines; Contagion only listens while
        // it has a Spotify recolour in flight.
        if (d.type === "restyle") {
            root.restyleAsked(d.listening === true)
            return
        }
        // The extension's word about itself (its build, how its poll fails) — the
        // console nobody can open. States and error names only, never lyrics.
        if (d.type === "ext") {
            console.info("SpotifyBridge: extension", String(d.build || "?"), String(d.event || "?"),
                         d.error ? String(d.error).substring(0, 160) : "", d.ms !== undefined ? d.ms + " ms" : "")
            return
        }
        if (d.type === "restyled") {
            root.restyled(root._num(d.sheets, 0), root._num(d.loaded, 0), root._num(d.ms, 0))
            return
        }
        // A Canvas clip the bridge could not fetch or re-encode (QuickSpice shows the cover
        // instead). Logged, never an anchor.
        if (d.type === "canvas-error") {
            console.warn("SpotifyBridge: canvas —", String(d.error || "?").substring(0, 160))
            return
        }

        // ── Lyrics pushed from inside Spotify ─────────────────────────────────
        // The extension fetched these with the client's own access token — something the
        // shell cannot do for itself. Mapped here into the shape Lyrics.qml already
        // speaks, so the consumer never learns where they came from.
        if (d.type === "lyrics") {
            // Recorded before branching on outcome, so every exit below — error, missing,
            // unmapped, or a real hit — counts as "attempted" for this uri.
            root.lyricsTriedUri = d.trackUri || ""

            if (d.error) {
                // Not surfaced as an error STATE: the shell's own lookup still runs, and
                // "the API said no" is not something the card should report when NetEase is
                // about to answer perfectly well.
                //
                // But it IS kept, because the failure was invisible before: a fetch that
                // threw on every track looked exactly like a track that simply had no
                // lyrics, and the only difference on screen was a red cross that also means
                // five other things. `qs ipc … call spotify lyrics` prints this.
                root.lastLyricsError = d.error
                console.warn("SpotifyBridge: lyrics fetch failed —", d.error)
                root.lyricsUri = ""
                root.lyrics = null
                return
            }
            root.lastLyricsError = ""

            const mapped = SpicyLyrics.toLines(d.payload)
            if (mapped.missing) {
                // The server answered, and its answer is "no lyrics". Not a mapping fault.
                root.lastLyricsError = "no lyrics upstream — " + mapped.reason
                root.lyricsUri = ""
                root.lyrics = null
                return
            }
            if (mapped.kind === "none") {
                // ── A payload arrived and did not map ─────────────────────────
                // This was silent, and it is the worst of the three outcomes to lose:
                // `d.error` is empty, so the error line cleared, and `lyrics` stayed null —
                // indistinguishable from never having asked. It means the request WORKED
                // and the shape is not what spicylyrics.js expects.
                //
                // Records the payload's STRUCTURE — top-level keys and the length of
                // whatever Content is — never its text. That is enough to see which field
                // moved, and keeps the lyrics themselves out of logs and IPC output.
                // Describes each slot by TYPE, and shows short strings and numbers because
                // those are status tokens ("lyrics-not-found", 404) — the thing we need to
                // read. Long strings are reported by length only: that is where lyrics
                // would live, and they have no business in a log line.
                // Recurses one level so an array reports what it CONTAINS: a run of numbers
                // is encoded bytes, a run of objects is structured lines. Strings below the
                // top level are reported by length only — that is where lyric text would
                // be, and it does not belong in a log line.
                function describe(v, depth) {
                    depth = depth || 0
                    if (v === null) return "null"
                    if (Array.isArray(v)) {
                        if (v.length === 0) return "array(0)"
                        return depth >= 2
                            ? "array(" + v.length + ")"
                            : "array(" + v.length + ") of " + describe(v[0], depth + 1)
                    }
                    const t = typeof v
                    if (t === "number" || t === "boolean") return String(v)
                    if (t === "string") {
                        if (depth > 0) return "string(" + v.length + ")"
                        return v.length <= 40 ? '"' + v + '"' : "string(" + v.length + ")"
                    }
                    if (t === "object") return "{" + Object.keys(v).join(",") + "}"
                    return t
                }

                let shape = "not an object"
                try {
                    const p = d.payload
                    if (Array.isArray(p)) {
                        shape = "array(" + p.length + ") ["
                              + p.map(describe).join(" | ") + "]"
                    } else if (p && typeof p === "object") {
                        shape = "keys=[" + Object.keys(p).join(",") + "]"
                             + " Content=" + describe(p.Content)
                    }
                } catch (e) { shape = "unreadable" }

                root.lastLyricsError = "payload did not map — " + shape
                                      + (mapped.reason ? " (" + mapped.reason + ")" : "")
                console.warn("SpotifyBridge:", root.lastLyricsError)
                root.lyricsUri = ""
                root.lyrics = null
                return
            }

            root.lyricsUri = d.trackUri || ""
            root.lyrics = mapped

            // ── Say so, once ──────────────────────────────────────────────────
            // Announced on the FIRST successful payload of a session, not per track: the
            // interesting event is "the bridge is working", which you otherwise only learn
            // by noticing a small tick on the media card. Per-track would be a notification
            // every three minutes for something that is now routine.
            if (!root._notified) {
                root._notified = true
                // One line. An earlier version explained the whole mechanism — providers,
                // line counts, why the playhead is better — which is a paragraph nobody
                // wants from a toast. The provider and the sync granularity are the only
                // parts that differ run to run; everything else belongs in the Setup page.
                const grain = mapped.kind === "syllable" ? "syllable-synced"
                            : mapped.kind === "line"     ? "line-synced"
                            : mapped.kind

                notifyProc.command = [
                    "notify-send", "--app-name=Quickshell", "--icon=spotify",
                    "Lyrics connected",
                    "Connected to Spicetify — "
                        + (mapped.provider || "Spicy Lyrics")
                        + (mapped.community ? " (community)" : "")
                        + ", " + grain + "."
                ]
                notifyProc.running = true
            }
            return
        }

        if (d.type !== "anchor") return

        // A new track invalidates whatever lyrics we are holding, immediately. Waiting for
        // the replacement to arrive would leave the previous song's words on screen for
        // the length of a network round trip — and if the fetch fails they would simply
        // stay, matched to the wrong song.
        if ((d.trackUri || "") !== root.trackUri) {
            root.lyrics = null
            root.lyricsUri = ""
        }

        root.trackUri = d.trackUri || ""
        root.title    = d.title    || ""
        root.artist   = d.artist   || ""
        root.album    = d.album    || ""
        root.duration = root._num(d.durationMs, 0) / 1000
        root.playing  = !!d.playing

        root._anchorPos = Math.max(0, root._num(d.positionMs, 0) / 1000)

        // ── recvAt, not Date.now() ─────────────────────────────────────────
        // spotify-bridge.py stamps `recvAt` (wall-clock ms) the instant it reads the
        // extension's POST. Date.now() here instead would stamp whenever THIS line
        // happened to reach the front of the QML event loop — which lags recvAt by
        // however busy the shell's JS thread was at that moment, and that lag is
        // exactly the kind of jitter `Lyrics.offset` cannot fix, because it is not
        // constant. Both clocks are wall-clock ms on the same machine, so they are
        // directly comparable.
        //
        // It also fixes reattachment: detached mode replays the tail of a log that may
        // be seconds old (see _syncDetached()). Stamping those with Date.now() froze
        // the playhead as if the anchor had just arrived, so a reload could come back
        // a few seconds BEHIND the real position until the next heartbeat corrected it.
        // recvAt lets position() extrapolate forward through however long the reload
        // actually took, correctly, from the first replayed line.
        //
        // ── Sanity-checked, not trusted outright ────────────────────────────
        // The DETACHED listener (spotify-bridge-run.sh) survives a shell reload on
        // purpose — see its own docstring — so it can keep running code from before
        // this file last changed for a long time. An older build stamped `recvAt`
        // off time.monotonic() (an uptime count, not an epoch) rather than
        // time.time(). Trusting that outright made `Date.now() - _anchorMs` compute
        // roughly Date.now() itself — billions of "elapsed seconds" — which tripped
        // the "ran off the end of the track" guard in `available` below and made an
        // otherwise perfectly live bridge report as permanently disconnected. Reject
        // anything more than a day off Date.now(): that can't be this machine's
        // wall clock a moment ago, whatever units it actually is.
        const recvAt   = root._num(d.recvAt, 0)
        const recvSane = recvAt > 0 && Math.abs(Date.now() - recvAt) < 86400000
        root._anchorMs = recvSane ? recvAt : Date.now()

        root.state = "live"
    }

    // ── The listener ──────────────────────────────────────────────────────────
    // Restarted by Quickshell if it dies; the extension retries on every event anyway, so
    // a gap costs at most one anchor. Off while `detached` mode owns the listener
    // instead (below) — the two must never both be trying to bind the same port.
    // Gated on the install probe: with no Spicetify / extension there is nothing that
    // could ever POST to the listener, so binding the loopback port just spawns a
    // Python process for nothing — and, on a machine with a stray listener from a
    // previous run, logs a "bind failed: Address already in use" for a feature the
    // user never set up. `setupComplete` stays false until the probe returns, so the
    // listener starts a beat late on a real install; the extension retries every event.
    property Process _proc: Process {
        running: root.enabled && !root.detached && root.setupComplete
        command: ["python3", Quickshell.shellPath("scripts/spotify-bridge.py")]

        stdout: SplitParser {
            onRead: function(line) { root._ingest(line) }
        }

        stderr: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "")
                    console.warn("SpotifyBridge[py]:", line)
            }
        }

        onRunningChanged: {
            if (running) {
                root.state = "starting"
            } else if (root.state !== "error") {
                root.state = "off"
                root.trackUri = ""
            }
        }
    }

    // ══ Detached mode (Config.spotifyBridgeDetached) ═════════════════════════
    // The listener as a process outliving Quickshell entirely, via
    // scripts/spotify-bridge-run.sh — see that file and the Config property's own
    // doc for the shape and the bug it's built to avoid repeating. This shell talks
    // to it the same way Updates.qml talks to a detached pacman transaction: launch
    // (idempotent — a flock makes a second attempt against an already-running
    // listener a silent no-op) and reattach by tailing its log, never by owning its
    // stdout directly.
    readonly property bool detached: Config.spotifyBridgeDetached

    readonly property string _cacheDir:
        Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")
    readonly property string _lockPath: root._cacheDir + "/quickshell-spotify-bridge.lock"
    readonly property string _logPath:  root._cacheDir + "/quickshell-spotify-bridge.log"

    readonly property bool wantsDetached: root.enabled && root.detached && root.setupComplete

    function _syncDetached() {
        if (!root.wantsDetached) {
            attachProc.running = false
            lockWatch.running = false
            watchDelay.stop()
            relaunchDelay.stop()
            return
        }

        // Fire-and-forget: the launcher backgrounds spotify-bridge-run.sh under
        // `setsid` and exits in milliseconds, exactly like Updates._launch(). The
        // real listener is reparented to init the instant it returns — nothing
        // Quickshell does afterwards (reload, crash, a plain `pkill quickshell`)
        // can reach it.
        detachLauncher.command = ["bash", "-c",
            'setsid bash "$0" "$1" "$2" "$3" < /dev/null > /dev/null 2>&1 & disown; exit 0',
            Quickshell.shellPath("scripts/spotify-bridge-run.sh"),
            root._lockPath, root._logPath,
            Quickshell.shellPath("scripts/spotify-bridge.py")]
        detachLauncher.running = false
        detachLauncher.running = true

        root.state = "starting"
        attachProc.running = false
        // `-n 20`, not `-n +1`: this log is a continuous stream of anchors reaching
        // back to whenever the listener first started (possibly hours), not one
        // finite run whose whole history matters the way update-run.sh's is.
        //
        // ── Not `-n 1` either — that re-anchored the playhead but not the WORDS ──
        // The listener never repeats itself; only the extension does, and it re-posts
        // the lyrics payload every ~20s (LYRICS_REPOST_MS). One line is almost always
        // an anchor, so a reloaded shell had a live playhead and a blank card for up
        // to 25s. Measured in the log: consecutive lyrics posts sit a median of 5 and
        // at most 8 lines apart, so 20 always reaches back past the last one. The
        // replay is ordered, so the anchor preceding it lands first and `hasLyrics`
        // matches. `-F` keeps following after it.
        attachProc.command = ["tail", "-n", "20", "-F", root._logPath]
        attachProc.running = true
        watchDelay.restart()
    }

    // ── A listener that dies is started again ─────────────────────────────────
    // It used to be launched once, at startup: one that died later — killed, or a
    // `pkill` after a reload had already reattached to it — stayed dead, and lyrics,
    // the playhead and the wave's Spotify repaint all went quiet until the next
    // reload (measured: the restyle hit a closed port for every change after it).
    // A SHARED flock on its lock blocks for exactly as long as the runner holds it,
    // so lockWatch exits the moment the listener does — event-driven, nothing polled.
    // Armed a beat after the launch so it can never take the lock before the runner
    // does (which would make the runner's `flock -n` refuse to start). A "ready"
    // resets the count; a listener that can't come up stops being retried at five.
    //
    // `setpriv --pdeathsig TERM`: the watcher dies with the shell. Quickshell sets no death
    // signal on its children and a `pkill` (reload-quickshell.sh) gives it no chance to stop
    // them, so a child that never writes outlives it — and this one only ever waits. Every
    // reload left one orphaned on the lock (16 of them, measured 2026-10-24). setpriv is
    // util-linux, exec's flock with the signal kept, and Process starts it from the GUI thread
    // (the death signal follows the thread that forked, which is the one that lives longest).
    property int _relaunches: 0
    property Process lockWatch: Process {
        command: ["setpriv", "--pdeathsig", "TERM", "flock", "-s", root._lockPath, "true"]
        onExited: if (root.wantsDetached) relaunchDelay.restart()
    }
    property Timer watchDelay: Timer {
        interval: 2000
        onTriggered: {
            lockWatch.running = false
            lockWatch.running = true
        }
    }
    property Timer relaunchDelay: Timer {
        interval: 1000
        onTriggered: {
            if (!root.wantsDetached) return
            if (root._relaunches >= 5) {
                console.warn("SpotifyBridge: the listener keeps exiting; not starting it again until a reload")
                return
            }
            root._relaunches++
            console.warn("SpotifyBridge: the listener exited; starting it again")
            root._syncDetached()
        }
    }

    onWantsDetachedChanged: root._syncDetached()
    Component.onCompleted:  root._syncDetached()

    property Process detachLauncher: Process { running: false }

    // No onRunningChanged resetting state to "off" here, unlike `_proc` above — a
    // stopped tail means THIS shell went away (a reload), not that the listener
    // did. The next shell's own _syncDetached() reattaches and picks the stream
    // back up; nothing was lost.
    property Process attachProc: Process {
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                if (line.trim() !== "") root._ingest(line)
            }
        }
    }

    IpcHandler {
        target: "spotify"

        function status(): string {
            if (!root.listening) return root.state
            if (!root.available) return "listening (no track)"
            return root.artist + " — " + root.title
                 + "  [" + root.position().toFixed(2) + "/" + root.duration.toFixed(2) + "s]"
                 + (root.playing ? " playing" : " paused")
        }

        function uri(): string { return root.trackUri }

        // ── Which lyrics are actually in use, and from whom ────────────────────
        // The badge on the card is one bit. This is the whole answer, because "why are
        // these not the words I expected" is a question about the provider, the uri and
        // the fallback all at once.
        function lyrics(): string {
            const parts = []
            parts.push("bridge: " + (root.hasLyrics ? "yes" : "no"))
            if (root.lastLyricsError !== "")
                parts.push("last error: " + root.lastLyricsError)
            if (root.lyricsUri !== "")
                parts.push("lyricsUri: " + root.lyricsUri)
            if (root.trackUri !== "")
                parts.push("trackUri: " + root.trackUri)
            if (root.lyrics)
                parts.push("provider: " + (root.lyrics.provider || "?")
                         + " (" + (root.lyrics.source || "?") + ")"
                         + (root.lyrics.community ? " community" : "")
                         + ", " + root.lyrics.kind
                         + ", " + (root.lyrics.lines || []).length + " lines")

            // ── Where the spaces between words came from ──────────────────────
            // Two mirror-image conventions encode syllable joins, and reading one as the
            // other renders "forever" as "for ev er" — which looks like a font or layout
            // problem and is neither. This names, per line, which one the payload used, so
            // the next report is one command instead of a guessing round.
            //
            //   text          the syllable text carries its own spacing
            //   continuations mid-word syllables marked IsPartOfWord: true
            //   endsOnly      word ENDS marked false, mid-word omitted
            //   allEnds       every syllable explicitly false
            //   none          the flag never appears; nothing is invented
            const sp = root.lyrics?.spacing
            if (sp) {
                const conv = ["plainText", "text", "continuations", "endsOnly",
                              "allEnds", "none"]
                parts.push("spacing: "
                         + conv.filter(k => sp[k] > 0)
                               .map(k => k + "=" + sp[k]).join("  "))

                // The per-line verdict alone was misleading: a line counts as
                // "continuations" on ONE flagged syllable while every other multi-syllable
                // word on it goes unmarked and comes apart. These say how widely the flag
                // is really used.
                parts.push("syllables: " + sp.syllables
                         + "  flag true=" + sp.flagTrue
                         + " false=" + sp.flagFalse
                         + " absent=" + sp.flagAbsent)
                const fields = (label, o) =>
                    label + ": " + Object.keys(o || {})
                                         .map(k => k + "×" + o[k]).join("  ")
                // Does timing predict the flag? If the line text turns out to be absent,
                // this decides whether contiguity can stand in for it.
                parts.push("timing vs flag: join tight=" + sp.joinTight
                         + " gap=" + sp.joinGap
                         + "   end tight=" + sp.endTight
                         + " gap=" + sp.endGap)
                parts.push(fields("line fields", sp.lineKeys))
                parts.push(fields("lead fields", sp.leadKeys))
                parts.push(fields("syllable fields", sp.keys))
            }

            // Deliberately reports only what THIS service holds, and does not ask
            // Lyrics what it ended up using. Lyrics already depends on SpotifyBridge;
            // reaching back the other way makes the two singletons circular, and a
            // singleton cycle is a hard load failure that cascades through every file
            // that imports either of them — invisible to the parse check.
            return parts.join("\n")
        }
    }
}
