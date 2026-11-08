.pragma library
.import "clockfmt.js" as ClockFmt

// ── clips.js ──────────────────────────────────────────────────────────────────
// The clips module's logic, as pure functions: the recorder's argv from the
// user's settings, which signal saves how much, the saved-clip events the hook
// appends, and the little formatters the pill, card and gallery share.
// services/Clips calls in; scripts/test-clips.js pins every function.
//
// ── recorderArgv is a trust boundary ──────────────────────────────────────────
// Every value comes from config.json, which is hand-editable. Each one is
// checked against a whitelist or clamped here, so what reaches
// gpu-screen-recorder is always something it accepts — a typo in the file
// falls back to the default rather than a recorder that refuses to start with
// the reason buried in a log. The argv goes to a process as a LIST (no shell),
// so nothing here is ever interpolated into a command line.
// ─────────────────────────────────────────────────────────────────────────────

const QUALITIES   = ["medium", "high", "very_high", "ultra"]
const CODECS      = ["auto", "h264", "hevc", "av1"]
const CONTAINERS  = ["mp4", "mkv"]
const STORAGES    = ["ram", "disk"]
// Output height cap → gpu-screen-recorder's `-s` box (it keeps the aspect ratio
// and fits inside). "original" passes nothing.
const RESOLUTIONS = { "original": "", "2160": "3840x2160", "1440": "2560x1440",
                      "1080": "1920x1080", "720": "1280x720" }
// The lengths gpu-screen-recorder can save on a signal alone (SIGRTMIN+1..6).
// Anything else saves the whole buffer (SIGUSR1).
const SAVE_LENGTHS = [10, 30, 60, 300, 600, 1800]

const BUFFER_MIN = 5,     BUFFER_MAX = 1800      // seconds; RAM-backed by default
const FPS_MIN = 10,       FPS_MAX = 360
const KBPS_MIN = 1000,    KBPS_MAX = 200000

function pick(v, list, dflt) { return list.indexOf(v) >= 0 ? v : dflt }
function clampInt(v, lo, hi, dflt) {
    const n = Math.round(Number(v))
    return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : dflt
}

// ── target ────────────────────────────────────────────────────────────────────
// What to capture, as `-w` takes it: "portal", or a monitor's connector name
// ("DP-1", "HDMI-A-1"). Anything else (an empty name, a hand-typed path) is "".
function target(name) {
    const s = String(name ?? "")
    if (s === "portal") return s
    return /^[A-Za-z0-9._-]{1,32}$/.test(s) ? s : ""
}

// A slurp region, "WxH+X+Y", or "" when it isn't one.
function region(geom) {
    const m = /^(\d{1,5})x(\d{1,5})\+(-?\d{1,5})\+(-?\d{1,5})$/.exec(String(geom ?? "").trim())
    if (!m || +m[1] < 2 || +m[2] < 2) return ""
    return m[1] + "x" + m[2] + "+" + m[3] + "+" + m[4]
}

// A window's area as a region: Hyprland's `at` / `size` (logical layout
// coordinates, the same space slurp prints), or "" when it isn't a real box.
// Capturing it records that RECTANGLE — the window moving away doesn't take the
// recording with it; the portal is the capture that follows a window.
function windowGeom(at, size) {
    if (!Array.isArray(at) || !Array.isArray(size)) return ""
    const r = v => Math.round(Number(v))
    return region(r(size[0]) + "x" + r(size[1]) + "+" + r(at[0]) + "+" + r(at[1]))
}

// ── settings ──────────────────────────────────────────────────────────────────
// The user's settings, every one validated: what the argv and the settings
// page's summaries are both built from, so the two can't disagree.
function settings(c) {
    const o = c || {}
    return {
        fps:       clampInt(o.fps, FPS_MIN, FPS_MAX, 60),
        quality:   pick(o.quality, QUALITIES, "very_high"),
        cbr:       o.bitrateMode === "cbr",
        kbps:      clampInt(o.kbps, KBPS_MIN, KBPS_MAX, 40000),
        codec:     pick(o.codec, CODECS, "auto"),
        container: pick(o.container, CONTAINERS, "mp4"),
        resolution: Object.prototype.hasOwnProperty.call(RESOLUTIONS, String(o.resolution))
                    ? String(o.resolution) : "original",
        cursor:    o.cursor !== false,
        desktop:   o.desktopAudio !== false,
        mic:       o.mic === true,
        split:     o.splitAudio === true,
        buffer:    clampInt(o.bufferSeconds, BUFFER_MIN, BUFFER_MAX, 120),
        storage:   pick(o.storage, STORAGES, "ram")
    }
}

// ── recorderArgv ──────────────────────────────────────────────────────────────
// gpu-screen-recorder's command line, or null when there's nothing valid to
// capture.
//   mode    "replay"  the buffer; `out` is the folder clips land in, and a
//                     regular recording started during it (SIGRTMIN) goes there too
//           "record"  one recording; `out` is its file
//   what    target() / "region" (with `geom`, a region())
// The `-sc` hook is the runner's to add (it knows where it lives).
function recorderArgv(c, mode, what, out, geom) {
    const s = settings(c)
    const w = what === "region" ? "region" : target(what)
    if (w === "" || !out || (mode !== "replay" && mode !== "record")) return null
    const g = w === "region" ? region(geom) : ""
    if (w === "region" && g === "") return null

    const a = ["gpu-screen-recorder", "-w", w]
    if (g !== "") a.push("-region", g)
    a.push("-c", s.container, "-f", String(s.fps), "-k", s.codec)
    // Constant bitrate keeps a RAM buffer's size predictable (the man page's own
    // advice for replay); otherwise constant quality at a preset.
    if (s.cbr) a.push("-bm", "cbr", "-q", String(s.kbps))
    else       a.push("-bm", "auto", "-q", s.quality)
    if (RESOLUTIONS[s.resolution] !== "") a.push("-s", RESOLUTIONS[s.resolution])
    a.push("-cursor", s.cursor ? "yes" : "no")
    // Each -a is its own audio track; "a|b" mixes them into one.
    const sources = (s.desktop ? ["default_output"] : []).concat(s.mic ? ["default_input"] : [])
    if (s.split) for (const src of sources) a.push("-a", src)
    else if (sources.length > 0) a.push("-a", sources.join("|"))
    // A portal session remembers its choice, so the picker asks once, not per start.
    if (w === "portal") a.push("-restore-portal-session", "yes")
    if (mode === "replay") {
        a.push("-r", String(s.buffer), "-replay-storage", s.storage, "-o", out, "-ro", out)
    } else {
        a.push("-o", out)
    }
    return a
}

// ── saveCommand ───────────────────────────────────────────────────────────────
// What the runner is told to save: "save" (the whole buffer) or "save:N" for a
// length gpu-screen-recorder can cut on a signal of its own. A length it can't,
// or one no shorter than the buffer, is the whole buffer.
function saveCommand(seconds, buffer) {
    const n = Math.round(Number(seconds))
    if (!(n > 0) || n >= buffer || SAVE_LENGTHS.indexOf(n) < 0) return "save"
    return "save:" + n
}

// The lengths a clip can be cut to, shorter than the buffer (the panel's chips):
// the ones gpu-screen-recorder has a signal for. Longer is the whole buffer.
function saveLengths(buffer) {
    const b = Number(buffer) || 0
    return SAVE_LENGTHS.filter(n => n < b)
}

// ── timelineAt ────────────────────────────────────────────────────────────────
// Where "the last N seconds" sits on the HUD card's buffer timeline, as a fraction of its
// width measured BACK from now (the right edge): 0 = now, 1 = the whole buffer. A square
// root, not linear, so on a long buffer 10 s and 30 s aren't a pixel apart at the very end.
function timelineAt(seconds, buffer) {
    const b = Number(buffer) || 0, t = Number(seconds) || 0
    if (!(b > 0) || !(t > 0)) return 0
    return Math.sqrt(Math.min(1, t / b))
}

// ── parseEvents ───────────────────────────────────────────────────────────────
// The hook's log (events.jsonl): one { path, type, t } per saved file. A torn
// or foreign line is skipped, never thrown on — the file is appended to by
// another process while this reads it.
function parseEvents(text) {
    const out = []
    for (const line of String(text ?? "").split("\n")) {
        if (line.trim() === "") continue
        let e
        try { e = JSON.parse(line) } catch (err) { continue }
        if (!e || typeof e.path !== "string" || e.path === "" || !(Number(e.t) > 0)) continue
        out.push({ path: e.path, type: String(e.type ?? ""), t: Number(e.t) })
    }
    return out
}

// Events newer than `seen` (a `t`), oldest first. By time, not by line count:
// the hook trims the file, and a count would then point at the wrong line.
function newEvents(events, seen) {
    return events.filter(e => e.t > seen)
}

// ── Formatting ────────────────────────────────────────────────────────────────
// A buffer length in words: "45s", "2 min", "1 min 30s".
function span(secs) {
    const t = Math.max(0, Math.round(Number(secs) || 0))
    if (t < 60) return t + "s"
    const m = Math.floor(t / 60), s = t % 60
    return m + " min" + (s > 0 ? " " + s + "s" : "")
}

// How long ago: "just now", "4 min ago", "3 h ago", "2 d ago".
function age(ms, now) {
    const d = Math.max(0, (now - ms) / 1000)
    if (d < 60)    return "just now"
    if (d < 3600)  return Math.floor(d / 60) + " min ago"
    if (d < 86400) return Math.floor(d / 3600) + " h ago"
    return Math.floor(d / 86400) + " d ago"
}

// A constant-bitrate buffer's size in MiB (video only), or -1 when the size
// isn't fixed (constant quality varies with what's on screen).
function bufferMiB(c) {
    const s = settings(c)
    return s.cbr ? Math.round(s.kbps * 1000 / 8 * s.buffer / 1048576) : -1
}

// "1440p · 60 fps · H.264" — the settings in one line.
function summary(c) {
    const s = settings(c)
    const res = s.resolution === "original" ? "Native" : s.resolution + "p"
    const codec = { auto: "Auto codec", h264: "H.264", hevc: "HEVC", av1: "AV1" }[s.codec]
    return res + " · " + s.fps + " fps · " + codec
}

// Which audio is recorded, in words.
function audioText(c) {
    const s = settings(c)
    if (!s.desktop && !s.mic) return "No audio"
    const what = s.desktop && s.mic ? "Desktop + mic" : s.desktop ? "Desktop audio" : "Microphone"
    return what + (s.desktop && s.mic && s.split ? " · separate tracks" : "")
}

// ── Trimming ──────────────────────────────────────────────────────────────────
// The handles' positions (0..1 of the clip) as seconds, or null when the span is
// too short to be a clip. Rounded to a tenth — the cut is keyframe-snapped anyway.
function trimSpan(a, b, duration) {
    const d = Number(duration)
    if (!(d > 0)) return null
    const lo = Math.max(0, Math.min(a, b)), hi = Math.min(1, Math.max(a, b))
    const start = Math.round(lo * d * 10) / 10, end = Math.round(hi * d * 10) / 10
    return end - start >= 0.5 ? { start: start, end: end } : null
}

// ── The library's filters and sorting ─────────────────────────────────────────
// What a file is, from its name: an edit (the editor's -trim/-edit, a GIF), a
// clip (the buffer's Replay_…), or a recording (Recording_…, the recorder's
// Video_… from a recording during the buffer). A renamed file is a clip unless
// it says otherwise — Medal's library treats everything you kept as a clip.
function clipKind(name, ext) {
    const n = String(name ?? "")
    if (ext === "gif" || /-(trim|edit)(-\d+)?$/.test(n)) return "edit"
    if (/(^|_)(Recording|Video)_\d/.test(n) || /^(Recording|Video)_/.test(n)) return "recording"
    return "clip"
}

// `filter`: "all" | "today" | "favourites" | "clip" | "recording" | "edit"; `favs`: paths.
// `sort`: "newest" | "oldest" | "longest" | "largest". `game`: "" for every game, else one
// `gameOf` name. `now`: ms, for "today". A new array, never the input.
function libraryView(list, query, filter, favs, sort, game, now) {
    const q = String(query ?? "").trim().toLowerCase()
    const fav = Array.isArray(favs) ? favs : []
    const g = String(game ?? "")
    const out = (Array.isArray(list) ? list : []).filter(c =>
        (q === "" || String(c.name).toLowerCase().indexOf(q) >= 0)
        && (g === "" || gameOf(c.name) === g)
        && (filter === "favourites" ? fav.indexOf(c.path) >= 0
            : filter === "today" ? isToday(c.mtime, now)
            : filter === "clip" || filter === "recording" || filter === "edit" ? clipKind(c.name, c.ext) === filter
            : true))
    const by = { oldest:  (a, b) => a.mtime - b.mtime,
                 longest: (a, b) => b.duration - a.duration || b.mtime - a.mtime,
                 largest: (a, b) => b.size - a.size || b.mtime - a.mtime }[sort]
             || ((a, b) => b.mtime - a.mtime)
    return out.sort(by)
}

// ── Game names ────────────────────────────────────────────────────────────────
// The runner names a clip after the window it was cut in (scripts/clips-run.py `window_label`):
// "<Game>_Replay_2026-10-18_21-41-05", "<Game>_Recording_…", "<Game>_Video_…". The game is what
// stands before the kind marker; a file without one (the recorder's own name, a rename) has none.
// Shown as the library's game filter.
function gameOf(name) {
    const m = /^(.+?)_(Replay|Recording|Video)_\d{4}-\d{2}-\d{2}/.exec(String(name ?? ""))
    return m ? m[1].replace(/-/g, " ") : ""
}

// The games in a library, most clips first: [{ game, count }].
function gamesOf(list) {
    const n = {}
    for (const c of (Array.isArray(list) ? list : [])) {
        const g = gameOf(c.name)
        if (g !== "") n[g] = (n[g] || 0) + 1
    }
    return Object.keys(n).map(g => ({ game: g, count: n[g] }))
        .sort((a, b) => b.count - a.count || (a.game < b.game ? -1 : 1))
}

// Same calendar day as `now` (both ms), in local time.
function isToday(ms, now) {
    const a = new Date(Number(ms) || 0), b = new Date(Number(now) || Date.now())
    return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
}

// ── Clip it, and what comes next ──────────────────────────────────────────────
// "Clip it + N more seconds": press at the moment, keep recording N seconds, then save. The
// recorder can only cut on signal a few fixed lengths, so the plan is: wait `delay`, ask for the
// smallest signal length that covers `before + after` (or the whole buffer), and — when that is more
// than wanted — have the runner cut the head off the saved file to exactly `keep` seconds
// (clips-lib.py headtrim, a stream copy: keyframe-snapped, so a touch long, never short).
//   before   seconds already in the buffer to keep (0 = all of it)
//   after    seconds to keep recording (clamped to 1..buffer-1; 0 or less = no wait)
// → { delay, command, keep, want } — `command` as saveCommand's, `keep` 0 = no trim.
// With the whole buffer asked for, the result is the last `buffer` seconds ending `after` from now:
// the oldest `after` seconds fall off, because a buffer can't hold more than its length.
const AHEAD_MAX = 120
function aheadPlan(before, after, buffer) {
    const buf = Math.max(1, Math.round(Number(buffer) || 0))
    const a = Math.round(Number(after) || 0)
    if (!(a > 0)) return { delay: 0, command: saveCommand(before, buf), keep: 0, want: 0 }
    const wait = Math.max(1, Math.min(AHEAD_MAX, buf - 1, a))
    const b = Number(before) > 0 ? Math.min(Math.round(Number(before)), buf) : buf
    const want = Math.min(b + wait, buf)
    const cover = SAVE_LENGTHS.find(n => n >= want && n < buf)
    return { delay: wait, command: cover ? "save:" + cover : "save", keep: cover && cover > want ? want : 0, want: want }
}

// ── Presets ───────────────────────────────────────────────────────────────────
// One click sets the whole recording profile. Every preset names the same keys, so "which preset is
// this" (matchPreset) is a plain comparison; a setting not named here (the capture target, the
// folder, the container, the cursor) is left alone. The keys are `settings()`'s; the panel maps them
// back to Config.clips*.
const PRESET_KEYS = ["fps", "quality", "cbr", "codec", "resolution", "buffer", "desktop", "mic", "split"]
var PRESETS = [
    { id: "game", label: "Game", hint: "60 fps · 2 min · desktop + mic",
      v: { fps: 60, quality: "very_high", cbr: false, codec: "auto", resolution: "original", buffer: 120,
           desktop: true, mic: true, split: false } },
    { id: "tutorial", label: "Tutorial", hint: "30 fps · 1080p · your voice",
      v: { fps: 30, quality: "high", cbr: false, codec: "auto", resolution: "1080", buffer: 60,
           desktop: false, mic: true, split: false } },
    { id: "light", label: "Light", hint: "720p · 30 fps · small files",
      v: { fps: 30, quality: "medium", cbr: false, codec: "auto", resolution: "720", buffer: 60,
           desktop: true, mic: false, split: false } },
    { id: "max", label: "Max", hint: "Native · 60 fps · ultra",
      v: { fps: 60, quality: "ultra", cbr: false, codec: "auto", resolution: "original", buffer: 120,
           desktop: true, mic: true, split: false } }
]

// The preset whose values are exactly what the user has now (settings() of Config), or null.
function matchPreset(c) {
    const s = settings(c)
    return PRESETS.find(p => PRESET_KEYS.every(k => p.v[k] === s[k])) ?? null
}

// ── Recording limits ──────────────────────────────────────────────────────────
// "Stop after…" for a recording you might forget about: a time or a size. `limitHit` says which
// one tripped (or "").
var RECORD_LIMITS = [
    { id: "off", label: "No limit",  seconds: 0,    bytes: 0 },
    { id: "5m",  label: "5 min",     seconds: 300,  bytes: 0 },
    { id: "10m", label: "10 min",    seconds: 600,  bytes: 0 },
    { id: "30m", label: "30 min",    seconds: 1800, bytes: 0 },
    { id: "1g",  label: "1 GB",      seconds: 0,    bytes: 1073741824 },
    { id: "2g",  label: "2 GB",      seconds: 0,    bytes: 2147483648 },
    { id: "4g",  label: "4 GB",      seconds: 0,    bytes: 4294967296 }
]
function limitOf(id) { return RECORD_LIMITS.find(l => l.id === id) ?? RECORD_LIMITS[0] }
function limitHit(id, elapsedSecs, bytes) {
    const l = limitOf(id)
    if (l.seconds > 0 && Number(elapsedSecs) >= l.seconds) return "time"
    if (l.bytes > 0 && Number(bytes) >= l.bytes) return "size"
    return ""
}

// ── What a buffer costs ───────────────────────────────────────────────────────
// A constant-bitrate buffer's size is exact (bufferMiB). Constant quality varies with the picture, so
// this is a ROUGH figure for a 1080p60 desktop — only used before the recorder is running, to warn
// that a buffer won't fit; once it runs the real number is the recorder's resident memory.
const QUALITY_KBPS = { medium: 8000, high: 15000, very_high: 25000, ultra: 40000 }
function estimateBufferMiB(c) {
    const s = settings(c)
    if (s.storage !== "ram") return 0
    const kbps = s.cbr ? s.kbps : (QUALITY_KBPS[s.quality] || 25000)
    return Math.round(kbps * 1000 / 8 * s.buffer / 1048576)
}

// ── Why isn't it clipping ─────────────────────────────────────────────────────
// The recorder's last words, as a sentence about what to DO — it says "failed to create context",
// which is true and no help. → { text, fix } or null for words it doesn't know (the caller then
// shows the recorder's own). `fix` names what the panel can offer: "portal" | "target" | "codec".
function explainError(msg) {
    const m = String(msg ?? "")
    if (m === "") return null
    if (/cap_sys_admin|kms.?server|operation not permitted|permission denied|EPERM/i.test(m))
        return { text: "The recorder isn't allowed to capture the screen directly. Give gsr-kms-server its capability "
                     + "(sudo setcap cap_sys_admin+ep $(which gsr-kms-server)) or capture through the portal.", fix: "portal" }
    if (/portal/i.test(m))
        return { text: "The screen-share portal didn't answer. Check xdg-desktop-portal-hyprland is running.", fix: "portal" }
    if (/(monitor|output|display|connector)/i.test(m) && /(not found|no such|invalid|failed|unknown|couldn't)/i.test(m))
        return { text: "The monitor it captures isn't there any more. Pick another capture target.", fix: "target" }
    if (/(vaapi|nvenc|vulkan|encoder|hevc|av1)/i.test(m) && /(fail|not supported|unsupported|couldn't|cannot|can't)/i.test(m))
        return { text: "Your GPU can't encode with that codec. Set the codec to Auto or H.264.", fix: "codec" }
    return null
}

// What is wrong, worst first: [{ id, level: "error"|"warn", text, fix }]. Everything it needs is in
// `ctx` so it is a plain function of facts the service already has:
//   probed, installed, wanted (clipping is switched on), buffering, gaveUp, error (the recorder's),
//   target ("" = focused, a connector name, or "portal"), screens ([names]), kms (true | false |
//   null = unknown), memAvailMiB (0 = unknown), diskFreeMiB (0 = unknown), opts (Config's clips*).
function diagnose(ctx) {
    const c = ctx || {}
    const out = []
    const push = (id, level, text, fix) => out.push({ id: id, level: level, text: text, fix: fix || "" })
    if (!c.probed) return out
    if (!c.installed) {
        push("missing", "error", "gpu-screen-recorder isn't installed (sudo pacman -S gpu-screen-recorder).", "install")
        return out
    }
    const failing = c.wanted && !c.buffering && (c.gaveUp || String(c.error ?? "") !== "")
    if (c.wanted && c.target && c.target !== "portal" && Array.isArray(c.screens) && c.screens.length > 0
        && c.screens.indexOf(c.target) < 0)
        push("target", "error", "The monitor it captures (" + c.target + ") isn't connected. Pick another capture target.", "target")
    if (failing) {
        const why = explainError(c.error)
        if (why) push("explained", "error", why.text, why.fix)
        else if (c.kms === false && c.target !== "portal")
            push("kms", "error", "The recorder may not have permission to capture the screen "
                 + "(gsr-kms-server has no cap_sys_admin). Capture through the portal, or give it the capability.", "portal")
        else push("failed", "error", (c.gaveUp ? "It kept failing and stopped: " : "It failed to start: ")
                                    + (String(c.error ?? "") || "no reason given"), "")
    }
    const need = estimateBufferMiB(c.opts)
    if (c.wanted && need > 0 && c.memAvailMiB > 0 && need > c.memAvailMiB * 0.6)
        push("ram", "warn", "The replay buffer wants about " + need + " MB of RAM and only " + c.memAvailMiB
             + " MB are free. Shorten it or keep it on disk (Settings › Clips).", "buffer")
    if (c.diskFreeMiB > 0 && c.diskFreeMiB < 500)
        push("disk", "error", "Only " + c.diskFreeMiB + " MB are free where clips are saved — a recording would fail late.", "folder")
    else if (c.diskFreeMiB > 0 && c.diskFreeMiB < 4096)
        push("disk", "warn", "Only " + (Math.round(c.diskFreeMiB / 102.4) / 10) + " GB are free where clips are saved.", "folder")
    return out.sort((a, b) => (a.level === b.level ? 0 : a.level === "error" ? -1 : 1))
}

// ── Opening a folder in a FILE MANAGER ────────────────────────────────────────
// `gio open <folder>` opens whatever the machine has as its inode/directory handler, and on some
// setups that is a terminal file browser (a `cd` in a terminal window). The user wants Nautilus, so
// the shell names the file manager itself: the preferred one if it is installed, else the first
// installed of a known list, else (none known) `gio open` as before. Each knows how to open a
// folder and, where it can, how to open one WITH a file selected.
//   argv(dir, select) → the command; `select` "" = just the folder.
var FILE_MANAGERS = [
    { id: "nautilus",   label: "Files (Nautilus)", bin: "nautilus",
      argv: function (dir, sel) { return sel ? ["nautilus", "--select", sel] : ["nautilus", "--new-window", dir] } },
    { id: "dolphin",    label: "Dolphin",          bin: "dolphin",
      argv: function (dir, sel) { return sel ? ["dolphin", "--select", sel] : ["dolphin", "--new-window", dir] } },
    { id: "thunar",     label: "Thunar",           bin: "thunar",
      argv: function (dir, sel) { return ["thunar", dir] } },
    { id: "nemo",       label: "Nemo",             bin: "nemo",
      argv: function (dir, sel) { return ["nemo", dir] } },
    { id: "pcmanfm-qt", label: "PCManFM-Qt",       bin: "pcmanfm-qt",
      argv: function (dir, sel) { return ["pcmanfm-qt", dir] } },
    { id: "pcmanfm",    label: "PCManFM",          bin: "pcmanfm",
      argv: function (dir, sel) { return ["pcmanfm", dir] } },
    { id: "caja",       label: "Caja",             bin: "caja",
      argv: function (dir, sel) { return ["caja", dir] } }
]

// The file manager to use: `pref` ("" = automatic) if it is installed, else the first installed in the
// list's order, else "" (nothing known: the caller falls back to `gio open`). `installed`: ids.
function pickFileManager(pref, installed) {
    var have = Array.isArray(installed) ? installed : []
    if (pref && have.indexOf(pref) >= 0 && FILE_MANAGERS.some(function (f) { return f.id === pref })) return pref
    for (var i = 0; i < FILE_MANAGERS.length; i++)
        if (have.indexOf(FILE_MANAGERS[i].id) >= 0) return FILE_MANAGERS[i].id
    return ""
}

// The argv to show `dir` (and `select`, a file inside it) in file manager `id`; null for an unknown one
// or a path that isn't absolute — it goes to a process as a list, never through a shell.
function fileManagerArgv(id, dir, select) {
    var fm = FILE_MANAGERS.find(function (f) { return f.id === id })
    var d = String(dir || ""), sel = String(select || "")
    if (!fm || d.charAt(0) !== "/" || (sel !== "" && sel.charAt(0) !== "/")) return null
    return fm.argv(d, sel)
}

// ── Names a person would say ──────────────────────────────────────────────────
// "Replay_2026-10-11_02-22-38-trim" is the recorder's bookkeeping, not what the clip is. For the
// library's tiles: { title, time, tag } —
//   "Elden-Ring_Replay_2026-10-11_21-41-05"  → Elden Ring · 21:41
//   "Replay_2026-10-11_02-22-38"             → Replay · 02:22        (a Recording_… is "Recording")
//   "Replay_…-trim" / "-edit" / a GIF        → the same, tagged "Trimmed" / "Edited" / "GIF"
//   a name you gave it ("Poor Raiden")       → that, with the file's own time
// `time` is "HH:MM" (from the name's stamp, else the file's mtime in local time). The file's real name
// is never changed — this is only how it is shown.
function prettyName(name, ext, mtime) {
    var n = String(name ?? ""), tag = ""
    var t = /-(trim|edit)(-\d+)?$/.exec(n)
    if (t) { tag = t[1] === "trim" ? "Trimmed" : "Edited"; n = n.slice(0, t.index) }
    if (String(ext ?? "").toLowerCase() === "gif") tag = "GIF"
    var pad = function (v) { return (v < 10 ? "0" : "") + v }
    var d = new Date(Number(mtime) || 0)
    var time = pad(d.getHours()) + ":" + pad(d.getMinutes())
    var m = /^(?:(.+?)_)?(Replay|Recording|Video)_\d{4}-\d{2}-\d{2}_(\d{2})-(\d{2})-\d{2}$/.exec(n)
    if (m) {
        return { title: m[1] ? m[1].replace(/-/g, " ") : (m[2] === "Replay" ? "Replay" : "Recording"),
                 time: m[3] + ":" + m[4], tag: tag }
    }
    return { title: n, time: time, tag: tag }
}

// The library as days: [{ key, label, clips }] in the order given. "Today", "Yesterday", a weekday
// for the last week, then "12 October" (and the year when it isn't this one). `byDay` false (a sort by
// length or size) is one group with no label — a day heading over a list that isn't in day order lies.
var MONTHS = ["January", "February", "March", "April", "May", "June", "July", "August", "September",
              "October", "November", "December"]
var WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
function dayLabel(ms, now) {
    var d = new Date(Number(ms) || 0), n = new Date(Number(now) || Date.now())
    var day = function (x) { return new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime() }
    var diff = Math.round((day(n) - day(d)) / 86400000)
    if (diff === 0) return "Today"
    if (diff === 1) return "Yesterday"
    if (diff > 1 && diff < 7) return WEEKDAYS[d.getDay()]
    return d.getDate() + " " + MONTHS[d.getMonth()] + (d.getFullYear() === n.getFullYear() ? "" : " " + d.getFullYear())
}
function groupByDay(list, now, byDay) {
    var src = Array.isArray(list) ? list : []
    if (!byDay) return src.length ? [{ key: "all", label: "", clips: src }] : []
    var out = []
    for (var i = 0; i < src.length; i++) {
        var d = new Date(Number(src[i].mtime) || 0)
        var key = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
        if (out.length === 0 || out[out.length - 1].key !== key)
            out.push({ key: key, label: dayLabel(src[i].mtime, now), clips: [] })
        out[out.length - 1].clips.push(src[i])
    }
    return out
}

// A position as an editor reads it: "1:05.3".
function stamp(secs) {
    const t = Math.max(0, Number(secs) || 0)
    const tenths = Math.floor((t - Math.floor(t)) * 10)
    return ClockFmt.clock(t) + "." + tenths
}
