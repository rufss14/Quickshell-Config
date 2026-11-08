.pragma library

// ── launcher.js ───────────────────────────────────────────────────────────────
// The launcher's brain: which apps match what you typed, in what order, and what
// Enter means right now. Pure functions over plain data — no QML, no I/O — so
// `bun scripts/test-launcher.js` can pin the behaviour. "The launcher put the wrong
// app first" is a complaint that needs cases, not opinions, and a ranking buried in
// a QML expression inside a panel cannot be tested at all.
//
// ── How a match is scored ─────────────────────────────────────────────────────
// Every field of an app is scored against the query on one 0–100 TIER scale:
//
//     exact 100 · prefix 90 · word start 80 · initials 70 · substring 60 · fuzzy 10–30
//
// and the field decides how much of it counts: the NAME at full weight, the generic
// name ("Web Browser") and keywords at half, the executable's name in between, the
// comment only on a word start. So "browser" finds Firefox through its generic name
// without ever outranking an app actually called Browser, and "vsc" finds Visual
// Studio Code by its initials.
//
// ── What history may and may not do ───────────────────────────────────────────
// Pins and launch history (frecency) add a bonus, but it is capped under one tier's
// width: they decide the order WITHIN a quality of match, never across it. Without
// that cap, an app you launched forty times outranks the one you typed exactly.
// ─────────────────────────────────────────────────────────────────────────────

// ── Tunables ──────────────────────────────────────────────────────────────────
const W_NAME = 10, W_GENERIC = 5, W_KEYWORD = 5, W_EXEC = 7, W_COMMENT = 2
const MIN_FUZZY_LEN = 3           // two letters as a subsequence match nearly anything
const BONUS_CAP = 90              // must stay under one tier (10 × the W_NAME step)
const PIN_BONUS = 30
const HALF_LIFE_DAYS = 21         // a launch counts half as much three weeks on
const HISTORY_MAX = 300
const PENALTY_MAX = 9             // a kind's tie-break, never a tier (W_NAME × one step = 100)

// ── Text scoring ──────────────────────────────────────────────────────────────
function _words(s) {
    const out = []
    const re = /[^\s\-_.:/()]+/g
    let m
    while ((m = re.exec(s)) !== null) out.push({ at: m.index, text: m[0] })
    return out
}

// Score `q` (already lowercase, no spaces) against `text` (lowercase). Returns
// { tier, ranges } — tier 0 for no match; ranges are [start, end) spans in `text`.
function scoreText(text, q) {
    if (!text || !q) return { tier: 0, ranges: [] }
    if (text === q) return { tier: 100, ranges: [[0, text.length]] }
    if (text.startsWith(q)) return { tier: 90, ranges: [[0, q.length]] }

    const words = _words(text)
    for (const w of words)
        if (w.text.startsWith(q)) return { tier: 80, ranges: [[w.at, w.at + q.length]] }

    // Initials: "vsc" → Visual Studio Code. Needs 2+ words, or a one-word name would
    // match its own first letter.
    if (words.length >= q.length && q.length >= 2) {
        let ok = true
        for (let i = 0; i < q.length && ok; i++) ok = words[i].text[0] === q[i]
        if (ok) return { tier: 70, ranges: q.split("").map((_, i) => [words[i].at, words[i].at + 1]) }
    }

    const sub = text.indexOf(q)
    if (sub >= 0) return { tier: 60, ranges: [[sub, sub + q.length]] }

    if (q.length >= MIN_FUZZY_LEN) {
        const pos = []
        let from = 0
        for (let i = 0; i < q.length; i++) {
            const at = text.indexOf(q[i], from)
            if (at < 0) return { tier: 0, ranges: [] }
            pos.push(at)
            from = at + 1
        }
        const gaps = pos[pos.length - 1] - pos[0] + 1 - q.length
        // Spans merge so the highlight is a few runs, not one box per letter.
        const ranges = []
        for (const p of pos) {
            const last = ranges[ranges.length - 1]
            if (last && last[1] === p) last[1] = p + 1
            else ranges.push([p, p + 1])
        }
        return { tier: Math.max(10, 30 - gaps), ranges: ranges }
    }
    return { tier: 0, ranges: [] }
}

// ── The index ─────────────────────────────────────────────────────────────────
// The executable's name: first word of Exec that isn't `env`, a VAR=value, or a
// flag — `/usr/bin/code --unity-launch %F` → "code". Lets "code" find an app whose
// NAME is Visual Studio Code, and "gnome-terminal" find "Terminal".
function execName(execString) {
    // Quoted runs stay whole: "/opt/My App/run" is one word.
    const toks = String(execString || "").match(/"[^"]*"|'[^']*'|\S+/g) || []
    for (const t of toks) {
        const bare = t.replace(/^["']|["']$/g, "")
        if (bare === "" || bare === "env" || bare.includes("=") || bare.startsWith("-")
            || bare.startsWith("%")) continue
        return bare.split("/").pop().toLowerCase()
    }
    return ""
}

// One flat, lowercased record per visible app — built once when the application list
// changes, so a keystroke only scores strings and never re-reads QObject properties.
// `entries` are plain { id, name, genericName, comment, keywords, execString,
// noDisplay } objects (the service copies them out of DesktopEntry).
//
// Shell actions ride the same index (services/ShellActions): `kind: "action"` and a
// `penalty` under one tier, so an app and an action matching equally well list the app
// first — but a better match still wins across kinds, and history lifts a habit.
function buildIndex(entries) {
    const out = []
    for (const e of entries || []) {
        if (!e || e.noDisplay || !e.id) continue
        out.push({
            id:      e.id,
            name:    String(e.name || e.id),
            lname:   String(e.name || e.id).toLowerCase(),
            generic: String(e.genericName || "").toLowerCase(),
            comment: String(e.comment || "").toLowerCase(),
            keywords: (e.keywords || []).map(k => String(k).toLowerCase()),
            exec:    execName(e.execString),
            idl:     String(e.id).toLowerCase().replace(/\.desktop$/, ""),
            kind:    e.kind || "app",
            penalty: Math.max(0, Math.min(PENALTY_MAX, Number(e.penalty) || 0))
        })
    }
    return out
}

// ── One token against one record ──────────────────────────────────────────────
// The best score any field gives, and the spans to light up — which are only ever
// in the displayed name, so a hit that came from a keyword highlights nothing.
function _scoreToken(rec, q) {
    const name = scoreText(rec.lname, q)
    let score = name.tier * W_NAME
    let ranges = name.ranges

    // Only a word start or better on the other fields: a fuzzy hit in a generic name
    // or an exec path is noise that would crowd out real name matches.
    const other = (text, weight) => {
        const t = scoreText(text, q)
        if (t.tier >= 80 && t.tier * weight > score) { score = t.tier * weight; ranges = [] }
    }
    other(rec.generic, W_GENERIC)
    for (const k of rec.keywords) other(k, W_KEYWORD)
    other(rec.exec, W_EXEC)
    other(rec.idl, W_EXEC)
    // The comment is prose: a word start only, at a flat tier.
    if (_words(rec.comment).some(w => w.text.startsWith(q)) && 80 * W_COMMENT > score) {
        score = 80 * W_COMMENT
        ranges = []
    }
    return { score: score, ranges: ranges }
}

function _mergeRanges(rs) {
    rs.sort((a, b) => a[0] - b[0])
    const out = []
    for (const r of rs) {
        const last = out[out.length - 1]
        if (last && r[0] <= last[1]) last[1] = Math.max(last[1], r[1])
        else out.push([r[0], r[1]])
    }
    return out
}

// ── History (frecency) ────────────────────────────────────────────────────────
// { id: { n, last } } — launches and when. The file is hand-editable, so only
// well-formed records survive a read.
function cleanHistory(raw) {
    const out = {}
    if (!raw || typeof raw !== "object" || Array.isArray(raw)) return out
    for (const id of Object.keys(raw)) {
        const r = raw[id]
        if (id === "__proto__" || !r || typeof r !== "object") continue
        if (!Number.isFinite(r.n) || r.n < 1 || !Number.isFinite(r.last)) continue
        out[id] = { n: Math.min(Math.floor(r.n), 100000), last: r.last }
    }
    return out
}

function frecency(rec, now) {
    if (!rec) return 0
    const ageDays = Math.max(0, (now - rec.last) / 86400000)
    return 40 * Math.log(1 + rec.n) * Math.pow(0.5, ageDays / HALF_LIFE_DAYS)
}

// A new history with one more launch of `id`. Trimmed to the strongest HISTORY_MAX so
// a year of one-off launches can't grow the file without bound.
function recordLaunch(history, id, now) {
    if (!id) return history
    const next = Object.assign({}, history)
    const old = next[id]
    next[id] = { n: (old ? old.n : 0) + 1, last: now }
    const ids = Object.keys(next)
    if (ids.length > HISTORY_MAX) {
        ids.sort((a, b) => frecency(next[b], now) - frecency(next[a], now))
        const kept = {}
        for (const k of ids.slice(0, HISTORY_MAX)) kept[k] = next[k]
        return kept
    }
    return next
}

// ── Search ────────────────────────────────────────────────────────────────────
// `ctx`: { pinned: [id…], history: {…}, now: ms, limit: n }.
// Returns [{ id, name, score, ranges }] best first; [] for an empty query (the
// launcher at rest shows nothing but the field).
//
// More than one word is an AND: "visual code" needs both to match somewhere, so
// the order you type them in doesn't matter. The whole phrase is also tried against
// the name, so an exact multi-word name wins as a name.
function search(index, query, ctx) {
    const q = String(query || "").trim().toLowerCase()
    if (q === "") return []
    const pinned = new Set((ctx && ctx.pinned) || [])
    const history = (ctx && ctx.history) || {}
    const now = (ctx && ctx.now) || 0
    const limit = (ctx && ctx.limit) || 50
    const toks = q.split(/\s+/)

    const hits = []
    for (const rec of index) {
        let score = 0
        let ranges = []

        if (toks.length > 1) {
            const phrase = scoreText(rec.lname, q)
            let sum = 0
            let all = true
            const rs = []
            for (const t of toks) {
                const s = _scoreToken(rec, t)
                if (s.score === 0) { all = false; break }
                sum += s.score
                for (const r of s.ranges) rs.push(r)
            }
            if (all) { score = sum / toks.length; ranges = _mergeRanges(rs) }
            if (phrase.tier * W_NAME > score) { score = phrase.tier * W_NAME; ranges = phrase.ranges }
        } else {
            const s = _scoreToken(rec, q)
            score = s.score
            ranges = s.ranges
        }
        if (score === 0) continue

        // Closer in length = more likely what you meant: "fire" → Firefox before
        // Firefox Developer Edition. Under 10 so it never crosses a tier.
        score += Math.min(9, 9 * q.length / rec.lname.length)

        const bonus = Math.min(BONUS_CAP, (pinned.has(rec.id) ? PIN_BONUS : 0)
                                          + frecency(history[rec.id], now))
        hits.push({ id: rec.id, name: rec.name, kind: rec.kind,
                    score: score + bonus - rec.penalty, ranges: ranges })
    }

    hits.sort((a, b) => b.score - a.score || a.name.localeCompare(b.name))
    return hits.slice(0, limit)
}

// At most `caps[kind]` hits of each kind (a kind with no cap is unlimited), order kept:
// the shell's actions answer alongside apps without crowding them out.
function capKinds(hits, caps) {
    const seen = {}
    const out = []
    for (const h of hits || []) {
        const k = h.kind || "app"
        const cap = caps && caps[k]
        seen[k] = (seen[k] || 0) + 1
        if (cap === undefined || seen[k] <= cap) out.push(h)
    }
    return out
}

// The name with its matched spans wrapped for StyledText's rich text. Escaped, because
// a desktop entry's Name is somebody else's string going into markup.
function highlight(name, ranges, open, close) {
    const esc = s => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    if (!ranges || ranges.length === 0) return esc(name)
    let out = ""
    let at = 0
    for (const [a, b] of ranges) {
        if (a < at || b > name.length) continue
        out += esc(name.slice(at, a)) + open + esc(name.slice(a, b)) + close
        at = b
    }
    return out + esc(name.slice(at))
}

// ── Modes ─────────────────────────────────────────────────────────────────────
// Which character, typed at the start of an empty field, starts which mode. Explicit
// on purpose: a launcher that guesses "this looks like a shell command" is one that
// eventually runs something you meant to launch.
function modeFor(ch) {
    return ch === ">" ? "run" : ch === "?" ? "ask" : ch === "+" ? "pkg"
         : ch === ";" ? "clip" : ch === ":" ? "emoji" : ""
}

// ── What Enter does ───────────────────────────────────────────────────────────
// ONE answer, shared by the field, the list and the root key handler (they used to
// each decide, and the field's copy swallowed Enter for everything but an app).
//   s: { mode, text, chatting, results, calc }
// Returns "run" | "ask" | "launch" | "copy" | "install" | "pick" | "".
function enterAction(s) {
    const text = String(s.text || "").trim()
    if (s.mode === "run" && text !== "") return "run"
    // `+`: Enter installs the picked package — only ever a package the list showed.
    if (s.mode === "pkg") return s.results > 0 ? "install" : ""
    // `;` and `:` pick from a list (clipboard history, emoji): Enter takes the selected one.
    if (s.mode === "clip" || s.mode === "emoji") return s.results > 0 ? "pick" : ""
    // In a chat Enter always sends the next turn; an answer is copied from its own
    // bubble, never by a key that also has to mean "send".
    if (s.chatting && text !== "") return "ask"
    if (s.mode === "ask" && text !== "") return "ask"
    if (s.results > 0) return "launch"
    if (s.calc) return "copy"
    return ""
}

// ── History, one entry out ────────────────────────────────────────────────────
// "Forget this app": a new history without `id`, so a row you never want lifted can be put
// back to plain match order without wiping everything you've learned.
function forget(history, id) {
    if (!id || !history || !history[id]) return history
    const next = Object.assign({}, history)
    delete next[id]
    return next
}

// ── Web shortcuts ─────────────────────────────────────────────────────────────
// `yt cats` → YouTube's search for "cats". The first word is the shortcut's key and has to
// be followed by something to search for, so typing just `yt` still finds the app Yt-whatever.
// The list is the user's (Config.launcherWebShortcuts): { key, name, url } with "%s" for the
// query. Validated here, at the trust boundary: it ends in xdg-open, so only http(s) with a
// %s survives, and a key is a short lowercase word (it must be typable as the first word).
const KEY_OK = /^[a-z0-9]{1,12}$/
const URL_OK = /^https?:\/\/[^\s]*%s[^\s]*$/

function cleanShortcuts(raw) {
    const out = []
    const seen = new Set()
    for (const r of Array.isArray(raw) ? raw : []) {
        if (!r || typeof r !== "object") continue
        const key = String(r.key || "").trim().toLowerCase()
        const url = String(r.url || "").trim()
        if (!KEY_OK.test(key) || !URL_OK.test(url) || seen.has(key)) continue
        seen.add(key)
        out.push({ key: key, name: String(r.name || "").trim() || key, url: url })
    }
    return out
}

// The shortcut `text` asks for, with the query and the finished address, or null.
function webShortcut(text, shortcuts) {
    const m = /^(\S+)\s+(\S[\s\S]*)$/.exec(String(text || "").trim())
    if (!m) return null
    const key = m[1].toLowerCase()
    const sc = (shortcuts || []).find(x => x.key === key)
    if (!sc) return null
    const query = m[2].trim()
    const enc = encodeURIComponent(query)
    return { key: sc.key, name: sc.name, query: query, url: sc.url.replace("%s", () => enc) }
}

// ── Grouping ──────────────────────────────────────────────────────────────────
// Results arrive in rank order across kinds. Grouping keeps that order WITHIN a kind and
// orders the kinds by where each first appears, so the best match still comes first and
// Enter still opens it. A header is only worth its row when there are two groups or more:
// `groupFirst` is set on the first row of each group only then.
const GROUP_NAMES = { app: "Apps", action: "Actions", setting: "Settings", web: "Web",
                      package: "Packages", clip: "Clipboard", emoji: "Emoji" }

function groupResults(results) {
    const order = []
    const byKind = {}
    for (const r of results || []) {
        const k = r.kind || "app"
        if (!byKind[k]) { byKind[k] = []; order.push(k) }
        byKind[k].push(r)
    }
    const multi = order.length > 1
    const out = []
    for (const k of order) {
        byKind[k].forEach((r, i) => out.push(Object.assign({}, r, {
            group: GROUP_NAMES[k] || k, groupFirst: multi && i === 0 })))
    }
    return out
}

// The height of the list body for `rows` (grouped): the first `maxRows` rows, each with
// its group header if it opens a group, a gap between rows, padding top and bottom.
// o: { rowH, gap, headerH, maxRows, pad }. 0 for no rows.
function bodyHeight(rows, o) {
    const n = Math.min((rows || []).length, o.maxRows)
    if (n === 0) return 0
    let h = o.pad * 2 + (n - 1) * o.gap
    for (let i = 0; i < n; i++) h += o.rowH + (rows[i].groupFirst ? o.headerH : 0)
    return h
}

// ── Clipboard (`;`) ───────────────────────────────────────────────────────────
// `items`: [{ label, text }] newest first (the service makes them from its entries — an
// image is text "image"). Every word must appear somewhere in the text, case-blind.
// Returns [{ i, ranges }] — i indexes `items`; ranges are spans of the LABEL to light up.
// No query: the newest `limit`, which is what you want from a history.
function searchClip(items, query, limit) {
    const toks = String(query || "").trim().toLowerCase().split(/\s+/).filter(t => t !== "")
    const out = []
    for (let i = 0; i < (items || []).length && out.length < limit; i++) {
        const text = String(items[i].text || "").toLowerCase()
        if (!toks.every(t => text.includes(t))) continue
        const label = String(items[i].label || "").toLowerCase()
        const rs = []
        for (const t of toks) {
            const at = label.indexOf(t)
            if (at >= 0) rs.push([at, at + t.length])
        }
        out.push({ i: i, ranges: _mergeRanges(rs) })
    }
    return out
}

// ── Emoji (`:`) ───────────────────────────────────────────────────────────────
// `list`: [[char, name, group]]; `recents`: [char…] newest first. Every word of the query
// must start a word of the name (best) or sit inside it, or start a word of the group
// ("animal" lists the animals). No query: your recents, then the top of the list so a
// fresh install still has something to show. Returns [{ i, ranges }] (ranges: the name).
function searchEmoji(list, query, recents, limit) {
    const toks = String(query || "").trim().toLowerCase().split(/\s+/).filter(t => t !== "")
    const rank = new Map()
    ;(recents || []).forEach((c, k) => rank.set(c, k))
    if (toks.length === 0) {
        const out = []
        for (const c of recents || []) {
            const i = list.findIndex(e => e[0] === c)
            if (i >= 0 && out.length < limit) out.push({ i: i, ranges: [] })
        }
        for (let i = 0; i < list.length && out.length < limit; i++)
            if (!rank.has(list[i][0])) out.push({ i: i, ranges: [] })
        return out
    }
    const hits = []
    for (let i = 0; i < list.length; i++) {
        const name = list[i][1].toLowerCase()
        const words = _words(name)
        const group = list[i][2].toLowerCase()
        let score = 0
        const rs = []
        let all = true
        for (const t of toks) {
            const w = words.find(x => x.text.startsWith(t))
            if (w) { score += (w.text === t ? 4 : 3) + (w.at === 0 ? 1 : 0); rs.push([w.at, w.at + t.length]); continue }
            const at = name.indexOf(t)
            if (at >= 0) { score += 1; rs.push([at, at + t.length]); continue }
            if (_words(group).some(x => x.text.startsWith(t))) { score += 0.5; continue }
            all = false
            break
        }
        if (all) hits.push({ i: i, score: score - name.length / 1000 + (rank.has(list[i][0]) ? 2 - rank.get(list[i][0]) / 100 : 0),
                             ranges: _mergeRanges(rs) })
    }
    hits.sort((a, b) => b.score - a.score || a.i - b.i)
    return hits.slice(0, limit).map(h => ({ i: h.i, ranges: h.ranges }))
}

// A recents list with `c` moved to the front, capped.
function pushRecent(recents, c, cap) {
    return [c].concat((recents || []).filter(x => x !== c)).slice(0, cap)
}
