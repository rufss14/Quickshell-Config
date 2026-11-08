.pragma library

// ── xbel.js ───────────────────────────────────────────────────────────────────
// Reads the freedesktop recent-files store ($XDG_DATA_HOME/recently-used.xbel)
// for the dock's jump lists: the files each app opened last.
//
// ── The app that RECORDED an entry is not the app that opened the file ────────
// GLib writes `<bookmark:application name=… exec=…>`, and `name` is whoever made
// the record — a file manager launching a file into VS Code records itself as
// the name and `'code-oss %F'` as the exec. So an entry is matched on the FIRST
// WORD OF THE EXEC first and the name second (appsOf() hands both over, in that
// order).
//
// Regex, not an XML parser: this runs inside QML's JS engine, which has none, and
// the format is GLib's own fixed output. Entities are decoded; anything that
// doesn't match the shape is skipped rather than guessed at.
// ─────────────────────────────────────────────────────────────────────────────

function decode(s) {
    return String(s)
        .replace(/&#x([0-9a-fA-F]+);/g, (m, h) => String.fromCodePoint(parseInt(h, 16)))
        .replace(/&#([0-9]+);/g,        (m, d) => String.fromCodePoint(parseInt(d, 10)))
        .replace(/&apos;/g, "'").replace(/&quot;/g, "\"")
        .replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
}

function attr(tag, name) {
    const m = new RegExp("\\s" + name + "=\"([^\"]*)\"").exec(tag)
    return m ? decode(m[1]) : ""
}

function time(iso) {
    const t = Date.parse(iso)
    return isNaN(t) ? 0 : t
}

// [{ href, apps: [{ name, exec, time }] }], in file order.
function parse(text) {
    const out = []
    const bookmark = /<bookmark\s[^>]*>[\s\S]*?<\/bookmark>/g
    let b
    while ((b = bookmark.exec(String(text || ""))) !== null) {
        const open = /^<bookmark\s[^>]*>/.exec(b[0])[0]
        const href = attr(open, "href")
        if (!href) continue
        const fallback = Math.max(time(attr(open, "modified")), time(attr(open, "visited")))
        const apps = []
        const app = /<bookmark:application\s[^>]*\/?>/g
        let a
        while ((a = app.exec(b[0])) !== null) {
            apps.push({ name: attr(a[0], "name"), exec: attr(a[0], "exec"),
                        time: time(attr(a[0], "modified")) || fallback })
        }
        out.push({ href: href, apps: apps })
    }
    return out
}

// The names an app entry might be known by: the exec's first word (GLib wraps
// the whole exec in single quotes), then the recorded name.
function appsOf(app) {
    const exec = String(app.exec || "").trim().replace(/^'(.*)'$/, "$1")
    const first = exec.split(/\s+/)[0] || ""
    const binary = first.split("/").pop()
    return [binary, app.name]
}

// { key: [{ path, name, time }] } — newest first, `limit` per app, local files
// only, one row per file. `keyOf(names)` maps an entry's candidate names to the
// dock's key for it ("" = no app the dock knows).
function byApp(entries, keyOf, limit) {
    const out = Object.create(null)
    const seen = Object.create(null)
    for (let i = 0; i < entries.length; i++) {
        const e = entries[i]
        const m = /^file:\/\/(localhost)?(\/.*)$/.exec(e.href)
        if (!m) continue
        let path
        try { path = decodeURIComponent(m[2]) } catch (err) { continue }
        for (let j = 0; j < e.apps.length; j++) {
            const key = keyOf(appsOf(e.apps[j]))
            if (!key) continue
            const id = key + "\n" + path
            const row = { path: path, name: path.split("/").pop() || path, time: e.apps[j].time }
            if (seen[id]) {
                if (row.time > seen[id].time) seen[id].time = row.time
                continue
            }
            seen[id] = row
            if (!out[key]) out[key] = []
            out[key].push(row)
        }
    }
    for (const k in out) {
        out[k].sort((a, b) => b.time - a.time)
        out[k] = out[k].slice(0, limit)
    }
    return out
}
