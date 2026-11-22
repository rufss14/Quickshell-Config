.pragma library

// ── queuemodel.js ─────────────────────────────────────────────────────────────
// The Spotify queue as the media page draws it. Pure: what the extension reports in, rows and moves out.
//
//   parseQueue   the extension's `queue` message → a clean object. Everything in it is data from another process:
//                strings are cut, counts capped, unknown fields dropped, and an image address is only taken in the
//                two shapes Spotify uses.
//   moveTo       a row dragged to a place → the new order AND the move Spotify is asked for (an item and the item it
//                goes before, or after when it goes last). Spotify's own queue API takes exactly that.
//   runs         the rows in groups as Spotify keeps them: what was queued by hand, what the album or playlist
//                continues with, what autoplay adds.
//   creditFor    who put a row in the queue, as a name, in a Jam.
// ─────────────────────────────────────────────────────────────────────────────

var MAX_ROWS = 40
var IMAGE = /^spotify:image:([A-Za-z0-9]{20,64})$/
var CDN = /^https:\/\/i\.scdn\.co\/image\/[A-Za-z0-9]+$/

function text(v, n) { return typeof v === "string" ? v.slice(0, n || 200) : "" }

// "spotify:image:<id>" (what the player's metadata holds) → the CDN address; an https CDN address is kept; else "".
function imageUrl(v) {
    var s = String(v || "")
    var m = IMAGE.exec(s)
    if (m) return "https://i.scdn.co/image/" + m[1]
    return CDN.test(s) ? s : ""
}

function row(r) {
    if (!r || typeof r !== "object") return null
    var uri = text(r.uri, 100)
    if (uri === "") return null
    var p = text(r.provider, 16)
    return {
        uid: text(r.uid, 64),
        uri: uri,
        title: text(r.title),
        artist: text(r.artist),
        album: text(r.album),
        image: imageUrl(r.image),
        by: text(r.by, 80),
        // "queue" is what a person added; "context" what the album or playlist goes on with; "autoplay" Spotify's own.
        provider: p === "queue" || p === "autoplay" ? p : "context",
        durationMs: Math.max(0, Math.min(Number(r.durationMs) || 0, 86400000))
    }
}

function jam(j) {
    if (!j || typeof j !== "object") return null
    var members = []
    var given = Array.isArray(j.members) ? j.members.slice(0, 32) : []
    for (var i = 0; i < given.length; i++) {
        var m = given[i] || {}
        var name = text(m.name, 80)
        if (name === "") continue
        members.push({ id: text(m.id, 80), username: text(m.username, 80), name: name, image: imageUrl(m.image),
                       you: m.you === true, host: m.host === true })
    }
    return { members: members, youHost: j.youHost === true, queueOnly: j.queueOnly === true, active: j.active !== false,
             volumeControl: j.volumeControl === true, volumeAvailable: j.volumeAvailable === true, link: text(j.link, 300) }
}

function parseQueue(msg) {
    var d = msg && typeof msg === "object" ? msg : {}
    var next = []
    var given = Array.isArray(d.next) ? d.next.slice(0, MAX_ROWS) : []
    for (var i = 0; i < given.length; i++) {
        var r = row(given[i])
        if (r) next.push(r)
    }
    return {
        rev: text(String(d.rev === undefined ? "" : d.rev), 40),
        current: row(d.current),
        next: next,
        more: Math.max(0, Math.min(Number(d.more) || 0, 100000)),
        context: text(d.context, 120),
        liked: d.liked === true,
        dj: d.dj === true,
        jam: jam(d.jam)
    }
}

// Move `uid` so that it stands at `toIndex` of the list WITHOUT it (0 = first, length = last).
// → null when nothing changes, else { list, uid, anchor, where }: where is "before" the anchor's uid, or "after"
// it when the row went last. A row with no uid can't be addressed and is never moved.
function moveTo(list, uid, toIndex) {
    var from = -1
    for (var i = 0; i < list.length; i++) if (list[i].uid !== "" && list[i].uid === uid) { from = i; break }
    if (from < 0) return null
    var rest = list.slice(0, from).concat(list.slice(from + 1))
    var to = Math.max(0, Math.min(Math.round(toIndex), rest.length))
    if (to === from) return null
    var out = rest.slice(0, to).concat([list[from]], rest.slice(to))
    if (rest.length === 0) return null
    var before = to < rest.length
    return { list: out, uid: uid, anchor: before ? rest[to].uid : rest[rest.length - 1].uid, where: before ? "before" : "after" }
}

// [{ provider, from, to }]: runs of the same provider, in order, over indexes [from, to).
function runs(list) {
    var out = []
    for (var i = 0; i < list.length; i++) {
        var last = out.length ? out[out.length - 1] : null
        if (last && last.provider === list[i].provider) last.to = i + 1
        else out.push({ provider: list[i].provider, from: i, to: i + 1 })
    }
    return out
}

// The name of whoever queued a row, in a Jam: the member whose username (or id) is the row's `by`. "" outside a Jam or
// for a row nobody added. "you" is for the viewer's own.
function creditFor(row, jamInfo) {
    if (!row || row.by === "" || !jamInfo) return ""
    var ms = jamInfo.members || []
    for (var i = 0; i < ms.length; i++)
        if (ms[i].username === row.by || ms[i].id === row.by) return ms[i].you ? "you" : ms[i].name
    return ""
}
