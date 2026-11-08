pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../components"
import "karaoke.js" as KJ

// ── Karaoke ───────────────────────────────────────────────────────────────────
// Sing along and the lyrics light up — and it is a GAME, osu!'s shape on lyric lines: each line you
// sing is judged PERFECT / GREAT / GOOD / MISS, the good ones build a combo, the song ends with an
// accuracy and a rank (SS, S, A, B, C, F), and the result is kept per song with its cover
// (KaraokeScores). It listens to the microphone while a song with
// synced lyrics plays, and says when you are singing the line that is on — by TIMING
// (you are voicing while the line is on) and, where a speech model is installed, by the
// WORDS (what you sang, set against the lines around now). The decisions are
// services/karaoke.js (`bun scripts/test-karaoke.js`); this holds the process, the clock
// and the state.
//
//   toggle() / active     start or stop listening. Never persisted and never started by
//                         anything but a click or an IPC call: the microphone is not
//                         something a saved preference should open.
//   blocker()             why it can't run, or "" (the pattern Discord.pressBlocker set)
//   status                what it is doing, in words, for the card
//   lit 0..1              how lit you are right now (raw), `glow` the same, smoothed
//   score / streak / best the song's running score
//
// It lives in the media panel (the header chip, the strip on the lyrics card, the Settings
// tab) and in the lyrics card's underlines. It was a sidebar cell first; that was removed.
//
// ── What listens ──────────────────────────────────────────────────────────────
// scripts/karaoke.py, only while on: pw-record → levels (and Vosk's words). No audio is
// written anywhere. It is a real input stream, so the shell's microphone indicator shows it.
//
// ── Headphones, or it won't run ───────────────────────────────────────────────
// A microphone hears the song unless it is in your ears, and a cell lit by the music is a
// match that means nothing. PipeWire names the form factor; unknown counts as not
// headphones (refuse, don't guess), and Config.karaokeSkipHeadphoneCheck is the way past a
// device that reports wrong.
//
// ── The lyrics ────────────────────────────────────────────────────────────────
// Asked for through Lyrics.loadFor, exactly as the lyrics card asks, so it needs no card on
// screen. Their clock is a MediaPosition (the same one every lyrics surface uses) plus
// Lyrics.offset, the user's own nudge.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ On / off ══════════════════════════════════════════════════════════════
    property bool active: false
    function toggle() { if (root.active) root.stop(); else root.start() }
    function start() {
        if (root.active) return
        if (root.blocked !== "") { root.notice = root.blocked; noticeTimer.restart(); return }
        root.active = true
    }
    // Why a click did nothing, for a few seconds — a disabled button says nothing, and this one is
    // never disabled.
    property string notice: ""
    Timer { id: noticeTimer; interval: 4500; onTriggered: root.notice = "" }
    function stop()   { root.active = false }
    function reset()  {
        root.session = KJ.sessionNew(); root.sung = ({}); root.result = null; root._finished = false
        root._warmup = ({}); root.heldAtEnd = false
        root.runValid = true; root.runWhy = ""; root.joinNotice = false
        root._runChecked = false; root._runStartPos = -1
        root._takeMods()
    }
    function dismissResult() { root.result = null }

    // ── Did this run start from the start? ───────────────────────────────────
    // A score is for a whole song, so a run ranks only if it BEGAN at the start (KJ.startedFromStart) and
    // was not skipped about in. Joining mid-song says so (`joinNotice`, the media panel shows it) and
    // offers to restart from the beginning; the run is unranked until then, and its results say why.
    property bool runValid: true
    property string runWhy: ""             // "" | "late" (joined part-way) | "skipped" (a seek mid-run)
    property bool joinNotice: false
    property bool _runChecked: false
    // Where the song was when the run began. NOT where it was when the lyrics finally arrived: a slow
    // lookup at the start of a song must not read as "joined late".
    property real _runStartPos: -1
    function dismissJoinNotice() { root.joinNotice = false }

    // Restart the song from the top, held, 3-2-1, then play. A fresh run: it can rank.
    property int countdown: 0              // 3, 2, 1 while counting; 0 otherwise
    property bool countdownGo: false       // the "GO!" beat after it
    readonly property bool canRestart: root.player ? (root.player.canSeek ?? false) : false
    function restartWithCountdown() {
        const p = root.player
        if (!p || !p.canSeek) return
        root.reset()
        root._resetLive()
        if (p.canPause) p.pause()
        p.position = 0
        // The clock learns of the seek only when the player echoes it back; until then it still holds
        // the old position, and the first level tick would read it as the run beginning mid-song and
        // put the warning straight back up. So both are told now.
        if (root._clock) root._clock.pos = 0
        root._runStartPos = 0
        root.countdownGo = false
        root.countdown = 3
        countdownTimer.restart()
    }
    function _cancelCountdown() {
        countdownTimer.stop()
        goTimer.stop()
        root.countdown = 0
        root.countdownGo = false
    }
    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown > 0) return
            countdownTimer.stop()
            root.countdown = 0
            root.countdownGo = true
            goTimer.restart()
            if (root.player && root.player.canPlay) root.player.play()
        }
    }
    Timer { id: goTimer; interval: 900; onTriggered: root.countdownGo = false }

    // ── What the results screen does next ────────────────────────────────────
    // Play the song again from the start. (A seek back into a finished song is a new run: `_level`.)
    function replay() {
        const p = root.player
        root.result = null
        if (!p) return
        if (p.canSeek) p.position = 0
        if (p.canPlay) p.play()
    }
    // On to the next song — by the user's hand: while Karaoke is on the player is held at the end of a
    // song (karaokeStayAtEnd) and never moves on by itself.
    function next() {
        const p = root.player
        root.result = null
        if (p && p.canGoNext) p.next()
    }
    readonly property bool canNext: root.player ? (root.player.canGoNext ?? false) : false

    // ── The grace period (karaoke.js, "A grace period when a song starts too fast") ──
    // Until this SONG TIME, a line that starts is a warm-up: a miss in it is not counted. Set on every
    // seek, which includes the first position of a run and of a song.
    property real graceUntil: 0
    property var _warmup: ({})              // line index → true: judged as a warm-up
    // Seconds until the first line, while there is grace and a line to be ready for; else 0. For the HUD.
    readonly property real getReadyIn: {
        if (!root.active || !Lyrics.hasSynced || root._finished) return 0
        const pos = root.position
        if (pos >= root.graceUntil) return 0
        const next = KJ.nextSingableStart(root.lines, pos)
        return next > pos && next - pos <= KJ.GRACE_S ? next - pos : 0
    }

    // Held at the end of the song (karaokeStayAtEnd), so the player does not roll on into the next one.
    property bool heldAtEnd: false

    // ── The game's state, for the HUD and the results screen ─────────────────
    readonly property real accuracy: KJ.accuracy(root.session)
    readonly property string rank: root.session.count > 0 ? KJ.rankFor(root.accuracy) : ""
    readonly property int combo: root.session.streak
    readonly property int maxCombo: root.session.best
    readonly property int gameScore: root.session.score
    // A line was judged: "perfect" | "great" | "good" | "miss", its points (0..1), and the combo after it.
    signal lineScored(string judgment, real points, int combo)
    // A word was taken (the combo is per WORD) and what the combo is now; or a combo of `was` was cut.
    signal wordHit(int combo)
    signal comboBroken(int was)
    // ── Mods ─────────────────────────────────────────────────────────────────
    // The mods THIS run was begun with (karaoke.js MODS: HD Hidden Lyrics, HR Hard Rock, TH Time-Hell), taken
    // from Config when a run starts and held: switching one on mid-song would change the rules under a score.
    // `rules` is what they set (windows, thresholds, strictness); `modMult` the multiplier on the SCORE, for
    // what actually earned (Hard Rock does nothing without words to be strict about).
    property var mods: []
    readonly property var rules: KJ.rules(root.mods)
    readonly property real modMult: KJ.modMultiplier(KJ.effectiveMods(root.mods, root.wordsActive))
    // Hidden Lyrics is one control with three positions: 0 off, 1 HD, 2 HD+.
    readonly property int hiddenLevel: Math.max(0, Math.min(2, Math.round(Number(Config.karaokeModHidden) || 0)))
    readonly property var modsWanted: KJ.modList({ hidden: root.hiddenLevel, hr: Config.karaokeModHardRock, th: Config.karaokeModTimeHell })
    function cycleHidden() { Config.karaokeModHidden = (root.hiddenLevel + 1) % 3 }
    // Has the setting moved since this run began? (It takes effect on the next run.)
    readonly property bool modsPending: root.active && root.modsWanted.join("+") !== root.mods.join("+")
    // Hidden Lyrics, for the lyrics card: "" (shown), "partial" (HD: only the line being sung is shown) or
    // "all" (HD+: nothing is — the underlines of the words you hit still draw).
    readonly property string hideMode: root.active ? KJ.hideModeOf(root.mods) : ""
    function _takeMods() { root.mods = root.modsWanted }
    // For the settings rows and the badges.
    readonly property var modTable: KJ.MODS
    readonly property var modOrder: KJ.MOD_ORDER
    readonly property real modsWantedMult: KJ.modMultiplier(KJ.effectiveMods(root.modsWanted, true))
    function modsMult(str) { return KJ.modMultiplier(KJ.modsOf(str)) }
    // What a mod is called on screen (HD+ for the code HDP), and a list or stored string as one line.
    function modLabel(code) { return KJ.modLabel(code) }
    function modsText(listOrString) { return KJ.modsText(listOrString) }

    // A finished run, for the results screen: KJ.result's fields plus artist, title, album, art, `reason`
    // ("ended" only is ever shown), `newBest` and `previousBest`. null when there is none to show.
    property var result: null

    // ══ Can it run ════════════════════════════════════════════════════════════
    property bool _probed: false
    property bool hasPwRecord: false
    property bool hasVosk: false

    readonly property bool headphones: KJ.isHeadphones(Audio.sink ? Audio.sink.properties : null)
    readonly property string blocked: {
        if (!root._probed) return ""
        if (!root.hasPwRecord) return "Needs pw-record (it ships with pipewire)"
        if (!Config.karaokeSkipHeadphoneCheck && !root.headphones)
            return "Put headphones on — the mic would hear the song"
        return ""
    }
    function blocker() { return root.blocked }

    // ── The language ─────────────────────────────────────────────────────────
    // A speech model is for ONE language, so the song's has to be known: detected from its lyrics'
    // function words or script (KJ.detectLanguage, once per song — this binding only moves when the
    // lyrics do), or pinned in Config.karaokeLanguage. A song in a language there is no model table
    // entry for (Japanese, say) turns the WORDS off and says so: the English model listening to it
    // would produce nonsense, and timing alone is honest.
    readonly property var _detect: Lyrics.hasSynced ? KJ.detectLanguage(root.lines) : null
    readonly property string detectedLanguage: root._detect ? root._detect.lang : ""
    // Did detection beat the runner-up clearly? (A song of mixed languages, or a few words, is not sure.)
    readonly property bool languageSure: root._detect ? root._detect.sure : false
    readonly property string pinnedLanguage: KJ.LANGS[Config.karaokeLanguage] ? Config.karaokeLanguage : ""
    readonly property string language: root.pinnedLanguage !== "" ? root.pinnedLanguage
                                     : root.detectedLanguage !== "" ? root.detectedLanguage : "en"
    // Is there a language to work in? Nothing to judge it by yet (no lyrics) counts as yes: English until
    // told otherwise.
    readonly property bool languageOk: root.pinnedLanguage !== "" || !Lyrics.hasSynced || root.detectedLanguage !== ""
    readonly property string languageName: KJ.LANGS[root.language].native
    // The choices the settings row cycles through: auto, then each language.
    readonly property var languageChoices: [""].concat(KJ.LANG_ORDER)
    function languageLabel(code) { return code === "" ? "Auto" : KJ.LANGS[code].native }
    function cycleLanguage() {
        const i = root.languageChoices.indexOf(Config.karaokeLanguage)
        Config.karaokeLanguage = root.languageChoices[(i + 1) % root.languageChoices.length]
    }
    // A change of language needs the other model: the helper starts again with it, and is told the
    // new grammar.
    onLanguageChanged: {
        root._cover = null
        if (helper.running && root.wordsWanted) { root._cycling = true; cycle.restart() }
    }

    // The speech model for that language, best candidate first: Config's path (one path for every
    // language, as it always was), else the user's data directory, then where a package puts one
    // (KJ.modelDirsFor). The ONE place a path is made (CLAUDE.md: a user-facing path is "" in Config and
    // resolved by its service); ~ is expanded here. The helper takes the first that exists.
    // `scripts/karaoke-model.sh <language>` fetches one into the first place.
    readonly property var modelDirs: {
        const home = Quickshell.env("HOME") || ""
        const given = Config.karaokeModelDir
        const data = Quickshell.env("XDG_DATA_HOME") || (home + "/.local/share")
        return KJ.modelDirsFor(root.language, given !== "" ? given.replace(/^~(?=\/|$)/, home) : "", data)
    }

    readonly property string scriptPath: Quickshell.shellPath("scripts/karaoke.py")

    // ── Having the language's model, and fetching it ─────────────────────────
    // Is there a model in any of those places? Asked of the disk, not of the helper: the helper only knows
    // while it runs, and the Settings row has to offer the download BEFORE Sing along is switched on. Assumed
    // there until the answer comes, so the row doesn't flash. A path in Config (karaokeModelDir) is the
    // user's own business: nothing here fetches into it.
    property bool modelPresent: true
    property bool _modelChecked: false
    readonly property bool modelMissing: root.hasVosk && root._modelChecked && !root.modelPresent
    readonly property bool canInstall: Config.karaokeModelDir === ""
    onModelDirsChanged: if (root._probed) modelCheck.running = true
    Process {
        id: modelCheck
        command: ["sh", "-c", 'for d; do [ -d "$d" ] && exit 0; done; exit 1', "sh"].concat(root.modelDirs)
        onExited: function (code) {
            const had = root.modelPresent
            root.modelPresent = code === 0
            root._modelChecked = true
            // It arrived while listening: the helper starts again with it.
            if (!had && root.modelPresent && helper.running && root.wordsWanted) { root._cycling = true; cycle.restart() }
        }
    }

    // scripts/karaoke-model.sh <language>: the one place that knows the model's name, URL and where it goes
    // (and refuses a download that is not a model). A button in Settings runs it; nothing else does.
    property bool installing: false
    property string installNote: ""
    function installModel() {
        if (root.installing || !root.canInstall) return
        root.installing = true
        root.installNote = ""
        modelInstall.code = KJ.LANGS[root.language].model
        modelInstall.running = true
    }
    Process {
        id: modelInstall
        property string code: ""
        command: ["bash", Quickshell.shellPath("scripts/karaoke-model.sh"), code]
        stderr: StdioCollector { id: installErr }
        onExited: function (exitCode) {
            root.installing = false
            if (exitCode === 0) { modelCheck.running = true; return }
            // curl's progress bar shares stderr: the last line the script or curl itself said.
            const said = installErr.text.split(/[\r\n]+/).filter(s => /karaoke-model|curl:|refusing|not a Vosk/.test(s))
            root.installNote = "Download failed" + (said.length ? ": " + said[said.length - 1].replace(/^karaoke-model:\s*/, "") : "")
        }
    }

    Component.onCompleted: probe.running = true
    Process {
        id: probe
        command: ["python3", root.scriptPath, "--probe"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const p = JSON.parse(text)
                    root.hasPwRecord = !!p.pwRecord
                    root.hasVosk = !!p.vosk
                } catch (e) { }
                root._probed = true
                modelCheck.running = true
            }
        }
    }

    // ══ The microphone ════════════════════════════════════════════════════════
    // The helper restarts when the default source changes (a headset plugged in mid-song).
    readonly property string _target: Audio.source ? (Audio.source.name || "") : ""
    property bool _cycling: false
    on_TargetChanged: if (helper.running) { root._cycling = true; cycle.restart() }
    Timer { id: cycle; interval: 300; onTriggered: root._cycling = false }

    property bool listening: false
    property bool wordsReady: false
    property string wordsReason: ""
    property string error: ""
    readonly property bool wordsWanted: Config.karaokeWords && root.languageOk
    readonly property bool wordsActive: root.wordsWanted && root.wordsReady

    // Dying on its own happens: Vosk can abort the whole process (its C++ side raises a fatal error
    // that no Python handler can catch), and PipeWire can drop the stream. It is started again, a
    // few times a minute at most; past that it says so rather than flap.
    property var _deaths: []
    function _died() {
        const now = Date.now()
        root._deaths = root._deaths.filter(t => now - t < 60000).concat([now])
        if (root._deaths.length > 3) { root.error = "The microphone keeps stopping"; return }
        root._cycling = true
        cycle.restart()
    }
    // A change to the words setting changes what the helper must be started with.
    onWordsWantedChanged: if (helper.running) { root._cycling = true; cycle.restart() }

    Process {
        id: helper
        // The control channel (grammar commands). Left on: it is only ever the INITIAL value that
        // matters, and nothing here turns it off (CLAUDE.md, Process.stdinEnabled).
        stdinEnabled: true
        running: root.active && root.blocked === "" && root._probed && !root._cycling
        command: ["python3", root.scriptPath, "--target", root._target].concat(
            root.wordsWanted && root.hasVosk ? root.modelDirs.reduce((a, d) => a.concat(["--model", d]), []) : [])
        stdout: SplitParser { onRead: function (line) { root._onLine(line) } }
        onRunningChanged: {
            if (running) { root.error = ""; return }
            root.listening = false
            root.wordsReady = false
            root._resetLive()
        }
        onExited: function (code) {
            // Ended without being asked (not a stop, not a deliberate restart): start it again.
            if (root.active && !root._cycling && root.error === "") root._died()
        }
    }

    // ══ Telling it what to listen for ═════════════════════════════════════════
    // The words of the lines around now (karaoke.js grammarFor): measured on the real model, it
    // recovers lines free-form recognition mishears, and hears them sooner. Sent when the song
    // gets within a line or two of what the loaded grammar covers; the helper applies it in a gap
    // between lines (never mid-sentence) and says so.
    property var _cover: null            // { lo, hi } of the grammar last SENT
    property bool _grammarFailed: false  // the helper could not build one: free-form, and don't retry
    // The words the model has no word for (the helper reports them with each grammar): folded the way the
    // tallies' words are, {word: true}. Nothing in the vocabulary can ever be heard sung, so they are free
    // (karaoke.js "Words the recogniser cannot hear"). Forgotten when the helper starts, since a different
    // model has a different vocabulary.
    property var _oov: ({})
    function _addOov(list) {
        const next = Object.assign({}, root._oov)
        for (const w of list) for (const t of KJ.words(String(w))) next[t] = true
        root._oov = next
    }
    property string grammarNote: ""

    function _send(obj) { if (helper.running) helper.write(JSON.stringify(obj) + "\n") }

    function _syncGrammar() {
        if (!root.wordsActive || root._grammarFailed || !Lyrics.hasSynced || root.lines.length === 0) return
        const at = Math.max(0, root._idx)
        if (!KJ.grammarStale(root._cover, at, root.lines.length)) return
        const g = KJ.grammarFor(root.lines, at, root.language)
        root._cover = { lo: g.lo, hi: g.hi }
        root._send({ type: "grammar", phrases: g.phrases })
    }
    onWordsActiveChanged: { root._cover = null; if (root.wordsActive) root._syncGrammar() }
    onLinesChanged: { root._cover = null; root._syncGrammar() }

    function _onLine(line) {
        let m
        try { m = JSON.parse(line) } catch (e) { return }
        if (!m) return
        if (m.type === "ready") {
            root.listening = true
            root.wordsReady = !!m.words
            root.wordsReason = m.reason || ""
            root._cover = null
            root._oov = ({})
            root._grammarFailed = false
            root._deaths = []
            root._syncGrammar()
        } else if (m.type === "grammar") {
            // A grammar that could not be built leaves free-form recognition running: say so, and
            // do not ask again (it would fail the same way every line).
            if (m.ok === false) { root._grammarFailed = true; root.grammarNote = String(m.reason || "") }
            else root.grammarNote = ""
            if (Array.isArray(m.oov) && m.oov.length > 0) root._addOov(m.oov)
        } else if (m.type === "level") {
            root._level(Number(m.rms), m.voicing === undefined ? undefined : Number(m.voicing))
        } else if (m.type === "text") {
            root._heard(String(m.text || ""), !!m.final)
        } else if (m.type === "error") {
            root.error = String(m.msg || "The microphone failed")
        }
    }

    // ══ The song ══════════════════════════════════════════════════════════════
    Loader {
        id: clockLoader
        active: root.active
        sourceComponent: MediaPosition { active: true }
    }
    readonly property var _clock: clockLoader.item
    readonly property var player: root._clock ? root._clock.player : null
    readonly property bool playing: root._clock ? root._clock.playing : false
    // Where the song is, on the lyrics' own corrected clock.
    readonly property real position: (root._clock ? root._clock.pos : 0) + Lyrics.offset

    // Two different questions. WHICH LYRICS TO ASK FOR changes with anything about the track
    // (Lyrics.trackIdFor: the source, a Spotify URI that arrives after the title…). WHETHER IT IS A
    // NEW SONG is only its artist and title: a metadata field turning up late is not a new song,
    // and wiping what you have sung on one would take the underlines with it.
    readonly property string _trackId: Lyrics.trackIdFor(root.player)
    readonly property string _songKey: (root.player ? (root.player.trackArtist ?? "") + "::" + (root.player.trackTitle ?? "") : "")
    on_TrackIdChanged: if (root.active) { root._songMaybeChanged(); root._requestLyrics() }
    on_SongKeyChanged: if (root.active) root._songMaybeChanged()

    // ══ Which song, and its game ══════════════════════════════════════════════
    property string _songHeld: ""        // the song the session, the sung memory and the snapshot belong to
    property var _memory: ({})           // song key → what was sung there, for the last few songs
    property var _meta: ({ artist: "", title: "", album: "", art: "" })
    // The held song's lyrics as of the last level tick. A song that ends is finished AFTER the player has
    // moved on, by which time Lyrics.lines is the next song's — so the finish reads these.
    property var _snapLines: []
    property var _snapFor: null
    property int _snapTotal: 0
    property bool _finished: false

    function _snapMeta() {
        const p = root.player
        if (!p) return
        root._meta = { artist: p.trackArtist ?? "", title: p.trackTitle ?? "", album: p.trackAlbum ?? "",
                       art: AlbumArt.hiRes(p.trackArtUrl ?? "") }
    }
    // Refreshed while the held song is the one playing (its cover often arrives after its title).
    Timer {
        interval: 1000
        repeat: true
        running: root.active && root._songHeld !== "" && root._songHeld === root._songKey
        onTriggered: root._snapMeta()
    }

    // A different song is on. Called from the very handler that asks for its lyrics, BEFORE it does,
    // so what is read of the old song is still the old song's. Nothing playing (an empty key) changes
    // nothing: the underlines stay up and the run stays open.
    function _songMaybeChanged() {
        const key = root._songKey
        if (key === "" || key === "::" || key === root._songHeld) return
        if (root._songHeld !== "") {
            root._finishSong("changed")
            const mem = Object.assign({}, root._memory)
            mem[root._songHeld] = root.sung
            const keys = Object.keys(mem)
            if (keys.length > 8) delete mem[keys[0]]
            root._memory = mem
        }
        root._songHeld = key
        root.sung = root._memory[key] ?? ({})
        root.session = KJ.sessionNew()
        root.result = null
        root._finished = false
        root._snapLines = []
        root._snapFor = null
        root._snapTotal = 0
        root._warmup = ({})
        root.heldAtEnd = false
        root.runValid = true
        root.runWhy = ""
        root.joinNotice = false
        root._runChecked = false
        root._runStartPos = -1
        root._takeMods()
        root._cancelCountdown()
        root._resetLive()
        root._cover = null
        root._snapMeta()
    }

    // ── Lines not to be counted (karaoke.js "Lines that are not to be counted") ─────────────────
    // The song, as the scores key it; "" with nothing playing.
    readonly property string songId: root.player ? KJ.songKey(root.player.trackArtist ?? "", root.player.trackTitle ?? "") : ""
    // Lines the user marked (right-click on a lyric) — kept per song, matched against these lyrics.
    readonly property var skipped: KJ.skipSet(root.lines, KaraokeScores.skipsFor(root.songId))
    readonly property int skippedCount: Object.keys(root.skipped).length
    function toggleSkip(idx) {
        if (root.songId === "" || idx < 0 || idx >= root.lines.length) return
        KaraokeScores.toggleSkip(root.songId, KJ.skipMark(root.lines, idx))
    }
    function clearSkips() { KaraokeScores.clearSkips(root.songId) }
    // Duets: which lines overlap which in time. One singer takes one voice, so a line of a pair that was not
    // sung is excused when the other was.
    readonly property var _overlaps: KJ.overlapMap(root.lines)
    function _excused(idx) { return !!root.skipped[idx] || KJ.overlapExcused(root._overlaps, root.sung, idx) }
    // What the lyrics card dims: lines left out, by the user or by the duet rule. { index: true }
    readonly property var uncounted: {
        const out = Object.assign({}, root.skipped)
        for (const k of Object.keys(root._overlaps)) if (root.active && KJ.overlapExcused(root._overlaps, root.sung, Number(k)) && Number(k) < root._idx) out[k] = true
        return out
    }

    // A judged line: into the session, and out to whoever draws it. `idx` is its line, `tally` what was
    // sung of it. A MISS in a warm-up line (the grace period) is dropped, not counted.
    function _add(lr, idx, tally) {
        if (root._warmup[idx] && lr.judgment === "miss") return
        // A duet's other voice: you took one of the two, and a miss on the other is not counted.
        if (lr.judgment === "miss" && KJ.overlapExcused(root._overlaps, root.sung, idx)) return
        // Without a recogniser the words are not heard one by one, so the line moves the combo: a line
        // that is not a miss adds its words to it, a miss breaks it.
        if (!root.wordsActive) {
            if (lr.judgment === "miss") root._breakCombo()
            else { root.session = KJ.sessionCombo(root.session, root.session.streak + lr.words); root.wordHit(root.session.streak) }
        }
        root.session = KJ.sessionAdd(root.session, lr, root.modMult)
        root.lineScored(lr.judgment, lr.points, root.session.streak)
    }

    function _breakCombo() {
        const was = root.session.streak
        if (was === 0) return
        root.session = KJ.sessionBreak(root.session)
        root.comboBroken(was)
    }

    // The run is over: the song ended, the song changed, or it was switched off. A run that covers
    // enough of the song is recorded (KaraokeScores) whatever ended it; only a song that played out
    // to its end gets the results screen (`result`) — the others are saved quietly.
    function _finishSong(reason) {
        if (root._finished || root._songHeld === "") return
        root._settle(Infinity)
        // The line still being sung when the song runs out is judged too.
        if (reason === "ended" || KJ.songDone(root._snapLines, root._lastPos, 0.2)) {
            const lr = KJ.lineResult(root._cur, root.wordsActive, root.rules)
            if (lr) root._add(lr, root._idx, root._cur)
        }
        const res0 = KJ.result(root.session, root._snapTotal, root.wordsActive, root.mods)
        if (res0.lines === 0) return                      // nothing was judged: nothing to keep or show
        root._finished = true
        res0.ranked = res0.ranked && root.runValid
        const res = Object.assign({}, res0, { reason: reason, newBest: false, previousBest: null,
                                              why: root.runValid ? "" : root.runWhy,
                                              artist: root._meta.artist, title: root._meta.title,
                                              album: root._meta.album, art: root._meta.art })
        if (res0.ranked) {
            const rec = KaraokeScores.record(res0, root._meta)
            res.newBest = rec.newBest
            res.previousBest = rec.previousBest
        }
        if (reason === "ended") root.result = res
    }

    // The song stopped at its end (a player that stops rather than moving on).
    onPlayingChanged: if (root.active && !root.playing && !root._finished
                          && KJ.songDone(root._snapLines, root._lastPos, 0.2)) root._finishSong("ended")
    onPlayerChanged: if (root.active) root._requestLyrics()
    function _requestLyrics() { if (root.player) Lyrics.loadFor(root.player) }
    onActiveChanged: {
        // Switched off: a run that covered enough of the song is kept — BEFORE the live state is cleared.
        if (!root.active) { root._finishSong("stopped"); root._cancelCountdown(); root.joinNotice = false }
        root.error = ""
        root._deaths = []
        root._cover = null
        if (root.active) { root._songHeld = ""; root._memory = ({}); root.reset() }
        root._resetLive()
    }
    // The clock only exists once `active` builds it, so the first request waits for the player.

    // ══ What it hears, set against the lines ═════════════════════════════════
    property var _gate: KJ.gateNew()
    property real _lastMs: 0
    property int _idx: -1
    property var _cur: KJ.tallyNew("")
    property var _next: KJ.tallyNew("")
    // The lines just left, kept a moment more: what you sang of them lands after the song has
    // moved on (the recogniser's lag), and each is scored once its grace has settled. More than one in
    // a fast song, where the next line is on before the last has been sung out. Oldest first.
    property var _pendings: []             // [{ tally, at, idx }]
    // Which lyric word the next sound belongs to (karaoke.js, "a forward-only cursor").
    property var _matcher: KJ.matcherNew()
    property real _lastPos: 0              // where the song clock was at the last level
    property real _voicedAt: 0             // when the gate last said "voiced"
    property string lastHeard: ""          // the recogniser's latest words, for `status`
    // A hit counts while you are, or just were, actually voicing. The recogniser can put a word
    // to a click or a breath (measured: a stray "one" on quiet noise); the voice gate cannot.
    readonly property int voiceHoldMs: 800

    property var session: KJ.sessionNew()
    property real level: 0
    property bool voiced: false
    property real lit: 0
    property bool onLine: false

    // ── Smoothed, for everything that draws it ────────────────────────────────
    // `lit` jumps (a word lands, you breathe); anything that animated straight off it either
    // flickered at the level rate (~33 Hz) or, with a fixed-length Behavior retargeted that
    // often, never settled. This follows it once per FRAME — quick to light (50 ms), slow to
    // fade (280 ms), the shape of a held note — and sleeps when there is nothing to follow.
    property real glow: 0
    FrameAnimation {
        running: root.active && (root.lit > 0.001 || root.glow > 0.001)
        onTriggered: {
            const dt = Math.min(0.05, frameTime)
            const tau = root.lit > root.glow ? 0.05 : 0.28
            const next = root.glow + (root.lit - root.glow) * (1 - Math.exp(-dt / tau))
            root.glow = Math.abs(next - root.lit) < 0.002 ? root.lit : next
        }
    }

    // What you sang, line by line, for the whole song: line index → per-word flags. The lyrics card
    // underlines from THIS, so a line keeps its marks after the song moves on (they used to be
    // read off the current line alone and vanished the moment it changed). A new object on every
    // change, so a binding on it sees it. A seek drops the lines from where it landed on, so a line
    // sung again starts clean.
    property var sung: ({})
    function _setSung(updates) {
        const next = Object.assign({}, root.sung)
        for (const k of Object.keys(updates)) next[k] = updates[k]
        root.sung = next
    }
    function _dropSungFrom(line) {
        const next = {}
        let changed = false
        for (const k of Object.keys(root.sung)) {
            if (Number(k) >= line) changed = true
            else next[k] = root.sung[k]
        }
        if (changed) root.sung = next
    }

    readonly property int score: KJ.percent(root.session)
    readonly property int streak: root.session.streak
    readonly property int best: root.session.best
    readonly property int linesScored: root.session.count

    readonly property var lines: Lyrics.lines

    function _resetLive() {
        root._gate = KJ.gateNew()
        root._lastMs = 0
        root._idx = -1
        root._cur = KJ.tallyNew("")
        root._next = KJ.tallyNew("")
        root._pendings = []
        root._matcher = KJ.matcherNew()
        root._lastPos = 0
        root._voicedAt = 0
        root.lastHeard = ""
        root.level = 0
        root.voiced = false
        root.lit = 0
        root.glow = 0
        root.onLine = false
    }

    function _textAt(i) { return i >= 0 && i < root.lines.length ? KJ.lineText(root.lines[i]) : "" }

    // Settle the lines left a moment ago, once each one's grace is over.
    function _settle(now) {
        if (root._pendings.length === 0 || !root._pendings.some(p => now >= p.at)) return
        const due = root._pendings.filter(p => now >= p.at)
        root._pendings = root._pendings.filter(p => now < p.at)
        for (const pending of due) {
            if (root.skipped[pending.idx]) continue       // marked as not to be sung
            // The line is over: did it leave the combo alive? (Only a line whose last word went unsung,
            // with nothing later sung either, ends it — a skipped word in the middle cut it already.)
            if (root.wordsActive && !KJ.comboSurvives(pending.tally, root.sung, pending.idx, root._oov, root._excused)) root._breakCombo()
            const lr = KJ.lineResult(KJ.withFree(pending.tally, root._oov), root.wordsActive, root.rules)
            if (lr) root._add(lr, pending.idx, pending.tally)
        }
    }

    // `seek`: the song jumped (a real seek, a new track, the start) rather than walked on. A walk
    // keeps what you sang; a seek drops the lines from where it landed, so one sung again starts clean.
    function _moveTo(idx, now, seek) {
        const from = root._idx
        if (!seek && from >= 0 && idx > from) {
            // Walking on: the line just sung waits out its grace, and the live one is either the one
            // that was "next" or, if lines were skipped (overlapping timings), a fresh one.
            // Its grace (KJ.settleAfter: longer for a short line), and never ending before an earlier line's,
            // so lines are judged in order.
            const last = root._pendings.length > 0 ? root._pendings[root._pendings.length - 1].at : 0
            root._pendings = root._pendings.concat([{ tally: root._cur, idx: from,
                at: Math.max(last, now + KJ.settleAfter(root.lines, from, root.rules)) }])
            root._cur = idx === from + 1 ? root._next : KJ.tallyNew(root._textAt(idx))
        } else {
            root._pendings = []
            root._cur = KJ.tallyNew(root._textAt(idx))
            root._dropSungFrom(idx)
        }
        root._next = KJ.tallyNew(root._textAt(idx + 1))
        root._idx = idx
        // A line that starts inside the grace period (or that you joined part-way through) is a warm-up.
        if (idx >= 0 && idx < root.lines.length && KJ.inGrace(root.lines[idx].t, root.graceUntil)) root._warmup[idx] = true
        root._matcher = KJ.matcherSync(root._matcher, idx)
        root._syncGrammar()
    }

    function _level(rms, voicing) {
        const now = Date.now()
        const dt = root._lastMs > 0 ? Math.min(200, now - root._lastMs) : 0
        root._lastMs = now

        root._gate = KJ.gateStep(root._gate, rms, now, voicing)
        root.level = rms
        root.voiced = root._gate.voiced
        if (root.voiced) root._voicedAt = now

        // Where the run began, the first time there is a position; checked against the start of the song
        // as soon as there are lyrics to know where that is — even while paused, so the warning is up
        // before you sing a word.
        if (root.player && root._runStartPos < 0) root._runStartPos = root.position
        if (!root._runChecked && root.player && Lyrics.hasSynced && root._runStartPos >= 0) {
            root._runChecked = true
            if (!KJ.startedFromStart(root.lines, root._runStartPos)) {
                root.runValid = false
                root.runWhy = "late"
                root.joinNotice = true
            }
        }

        // Nothing to compare with — or the song isn't running: the mic is heard, not scored.
        if (!root.player || !root.playing || !Lyrics.hasSynced) {
            root.onLine = false
            root.lit = 0
            return
        }
        const pos = root.position
        // The lyrics of the held song, kept for its finish (see _finishSong).
        if (root._songKey === root._songHeld && root._snapFor !== root.lines) {
            root._snapFor = root.lines
            root._snapLines = root.lines
            root._snapTotal = KJ.singableCount(root.lines, root.skipped)
        }
        // Held at the end of the song, so the player does not roll on into the next one while the results
        // are up. BEFORE the finished check below: a song that finished early (its last line sung out
        // well before the track ends) must still be stopped when the track does. Margin: the clock can
        // lag the audio a little, and a pause that lands after the next track has begun is no pause.
        const clk = root._clock
        if (root.heldAtEnd && clk && clk.pos < clk.length - 5) root.heldAtEnd = false       // restarted
        if (Config.karaokeStayAtEnd && !root.heldAtEnd && clk && clk.length > 10
            && clk.pos >= clk.length - 1.2 && (root.player.canPause ?? false)) {
            root.heldAtEnd = true
            root.player.pause()
            root._finishSong("ended")
            root.onLine = false
            root.lit = 0
            return
        }
        if (root._finished) {
            // Over. Nothing more is judged — unless the song is back inside itself (seeked back, or
            // replayed): that is a new run of it.
            if (KJ.songDone(root.lines, pos, 0.2)) { root.onLine = false; root.lit = 0; return }
            root.session = KJ.sessionNew()
            root.sung = ({})
            root.result = null
            root._finished = false
            root._takeMods()
            root._resetLive()
        }
        // Which line, steadily: a small step back in the song clock is not a seek (KJ.stepLine says why).
        let step = KJ.stepLine(root._idx, Lyrics.lineAt(pos), pos, root._lastPos)
        if (step.seek && root._idx >= 0) {
            // A seek in the middle of a run. Back to the very start is a fresh run (it can rank); anywhere
            // else the run is no longer the song sung through, and says so.
            if (KJ.startedFromStart(root.lines, pos)) {
                root.reset()
                root._resetLive()
                root._runStartPos = pos
                step = { idx: Lyrics.lineAt(pos), seek: true }
            } else if (root.runValid) {
                root.runValid = false
                root.runWhy = "skipped"
            }
        }
        const idx = step.idx
        const seek = step.seek
        // A seek — the first position of a run or of a song included — starts the grace period.
        if (seek) root.graceUntil = pos + KJ.GRACE_S
        root._lastPos = pos
        if (idx !== root._idx) root._moveTo(idx, now, seek)
        root._settle(now)
        // The last line has been sung out, and a beat has passed for its last words to land.
        if (KJ.songDone(root.lines, pos, 1.5)) { root._finishSong("ended"); root.onLine = false; root.lit = 0; return }

        root.onLine = idx >= 0 && KJ.inWindow(root.lines, idx, pos, root.rules)
        if (root.onLine) root._cur = KJ.tallyTime(root._cur, dt, root.voiced)
        root.lit = KJ.lit(root._cur, root.voiced, root.onLine, root.wordsActive)
    }

    // What the recogniser has heard of the utterance so far. Each word goes to the NEXT lyric word
    // after the last one taken (see karaoke.js) — so words you sang once light one word, and a
    // following line that repeats them stays dark until you sing it. Only lines the song has got
    // to (lineOpen) can be lit; and only while you are voicing.
    function _heard(text, isFinal) {
        if (!root.wordsActive || root._idx < 0) return
        const clean = KJ.stripUnk(text)
        root.lastHeard = clean.trim()
        const heard = KJ.words(clean)
        if (heard.length === 0 && !isFinal) return
        const pos = root.position
        const ctx = []
        // A line the user marked is all "free": nothing in it is a candidate, and it holds nothing up.
        const free = (i, t) => root.skipped[i] ? t.words.map(() => true) : KJ.freeFlags(t.words, root._oov)
        for (const p of root._pendings) ctx.push({ line: p.idx, words: p.tally.words, flags: p.tally.flags, free: free(p.idx, p.tally), open: true })
        ctx.push({ line: root._idx, words: root._cur.words, flags: root._cur.flags, free: free(root._idx, root._cur), open: true })
        ctx.push({ line: root._idx + 1, words: root._next.words, flags: root._next.flags, free: free(root._idx + 1, root._next),
                   open: KJ.lineOpen(root.lines, root._idx + 1, pos, root.rules) })
        // Not voicing: the words are still counted as taken (so they are not found later, when you
        // are), but nothing is lit.
        const voicing = Date.now() - root._voicedAt <= root.voiceHoldMs
        const r = KJ.matcherHear(root._matcher, voicing ? ctx : [], heard, isFinal, root.rules.strictWords)
        root._matcher = r.m
        if (r.hits.length === 0) return
        const touched = {}
        for (const h of r.hits) {
            const at = root._pendings.findIndex(p => p.idx === h.line)
            if (at >= 0) {
                const p = root._pendings[at]
                const marked = { tally: KJ.tallyMark(p.tally, h.w), at: p.at, idx: p.idx }
                root._pendings = root._pendings.map((q, n) => n === at ? marked : q)
                touched[h.line] = marked.tally.flags
            } else if (h.line === root._idx) {
                root._cur = KJ.tallyMark(root._cur, h.w)
                touched[h.line] = root._cur.flags
            } else if (h.line === root._idx + 1) {
                root._next = KJ.tallyMark(root._next, h.w)
                touched[h.line] = root._next.flags
            }
        }
        root._setSung(touched)

        // The combo is per word: the run of lit words ending at the furthest word just taken. A run that
        // comes out no longer than the combo was — with a combo worth losing — was cut by a skipped word.
        let last = r.hits[0]
        for (const h of r.hits) if (h.line > last.line || (h.line === last.line && h.w > last.w)) last = h
        const was = root.session.streak
        const run = KJ.comboRun(root.sung, root.lines, last.line, last.w, root._oov, root._excused)
        if (run <= was && was >= 3) root.comboBroken(was)
        root.session = KJ.sessionCombo(root.session, run)
        root.wordHit(run)
    }

    // ══ In words, for the card ═══════════════════════════════════════════════
    readonly property string status: {
        if (!root.active) return root.blocked !== "" ? root.blocked : "Off"
        if (root.blocked !== "") return root.blocked
        if (root.error !== "") return root.error
        if (!root.listening) return "Starting the microphone…"
        if (!root.player) return "Nothing is playing"
        if (!Lyrics.hasSynced)
            return Lyrics.state === "loading" || Lyrics.state === "idle" ? "Finding the lyrics…" : "No synced lyrics for this song"
        if (!root.playing) return "Paused"
        // Said where it is seen: a song with no model for its language is judged on timing alone, which
        // cannot tell the words from a hum.
        if (root.wordsWanted && root.modelMissing) return "Timing only \u2014 no " + root.languageName + " model"
        return "Listening"
    }
    // One line for the media panel's header subtitle, where SongRec says "Listening…" too: what it
    // is doing, and the song's score once there is one. A click that couldn't start it speaks here
    // for a few seconds instead of doing nothing.
    readonly property string headline: {
        if (!root.active) return root.notice
        const lead = root.glow > 0.35 ? "Singing" : root.status
        if (root.linesScored === 0) return lead
        return lead + "  \u00b7  " + root.accuracy.toFixed(1) + "%" + (root.combo >= 2 ? "  \u00d7" + root.combo : "")
    }

    // How a match is judged right now, and — if the words are wanted but can't be — why not.
    readonly property string mode: root.wordsActive ? "Words and timing" : "Timing only"
    readonly property string modeNote: {
        if (!Config.karaokeWords) return ""
        if (!root.languageOk) return "Words aren't supported for this song's language yet"
        if (root.wordsActive) return ""
        if (!root.hasVosk) return "Words need python-vosk and a speech model"
        if (root.modelMissing || (root.listening && root.wordsReason !== ""))
            return "No " + root.languageName + " speech model \u2014 "
                 + (root.canInstall ? "download it below" : "none found in the folder set in Config")
        return ""
    }

    IpcHandler {
        target: "karaoke"
        function on(): void     { root.start() }
        function off(): void    { root.stop() }
        function toggle(): void { root.toggle() }
        function reset(): void  { root.reset() }
        function status(): string {
            return "on=" + root.active + " status=" + root.status + " mode=" + root.mode
                 + " lit=" + root.lit.toFixed(2) + " glow=" + root.glow.toFixed(2) + " voiced=" + root.voiced
                 + " line=" + root._idx + " acc=" + root.accuracy.toFixed(1) + "% rank=" + (root.rank || "-")
                 + " combo=" + root.combo + " maxCombo=" + root.maxCombo + " gameScore=" + root.gameScore
                 + " finished=" + root._finished + " result=" + (root.result ? root.result.rank : "none")
                 + " mods=" + (KJ.modsText(root.mods) || "none") + " x" + root.modMult.toFixed(2)
                 + (root.modsPending ? " (setting changed: next run)" : "")
                 + " runValid=" + root.runValid + (root.runWhy !== "" ? "(" + root.runWhy + ")" : "")
                 + " join=" + root.joinNotice + " countdown=" + root.countdown
                 + " heldAtEnd=" + root.heldAtEnd + " getReadyIn=" + root.getReadyIn.toFixed(1)
                 + " warmup=[" + Object.keys(root._warmup).join(",") + "]"
                 + " song=\"" + root._songHeld + "\" total=" + root._snapTotal + " streak=" + root.streak
                 + " best=" + root.best + " scored=" + root.linesScored
                 + " lang=" + root.language + (root.pinnedLanguage !== "" ? "(pinned)" : "(auto, detected="
                     + (root.detectedLanguage || "none") + (root.detectedLanguage !== "" && !root.languageSure ? ", unsure" : "") + ")")
                 + " headphones=" + root.headphones + " vosk=" + root.hasVosk
                 + " model=" + root.modelDirs.join(":") + (root.blocked !== "" ? " blocked=" + root.blocked : "")
                 // What it is hearing and where it has put it: if underlines go missing, `sung` says whether
                 // the memory still has them (line:lit/total), and `grammar` whether the helper has one.
                 + " heard=\"" + root.lastHeard + "\""
                 + " cursor=" + root._matcher.line + ":" + root._matcher.w
                 + " sung=[" + Object.keys(root.sung).map(k => k + ":" + root.sung[k].filter(x => x).length + "/" + root.sung[k].length).join(",") + "]"
                 + " grammar=" + (root._cover ? root._cover.lo + ".." + root._cover.hi : "none")
                 + " unhearable=" + Object.keys(root._oov).length
                 + (root._grammarFailed ? " grammarFailed=" + root.grammarNote : "")
                 + " deaths=" + root._deaths.length + (root.error !== "" ? " error=" + root.error : "")
        }
    }
}
