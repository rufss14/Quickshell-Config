.pragma library

// ── medialinks.js ─────────────────────────────────────────────────────────────
// Where a song's title, artists, album and cover should TAKE you when pressed. Pure: the caller hands in what the
// player says and what the Spotify bridge knows, and gets links back; opening one is `xdg-open` in the caller.
//
//   Spotify  `spotify:` URIs, which the installed client's own handler (spotify.desktop) turns into a page in the
//            running app. NOT the MPRIS `OpenUri`: that PLAYS what it is given, and a link must only navigate.
//            Exact ids come from the bridge (the extension reads them off the track). Without it only the track
//            has an id (MPRIS carries `xesam:url`), so the artist and the album become a search for their names
//            (`spotify:search:`), which is a page of results, never a wrong one.
//   Others   the page the player says it is on (`xesam:url`, an http(s) address): a video, a SoundCloud track. The
//            channel and the "album" are not links; a YouTube channel is not an artist.
//
// An artist string joins every credit ("A, B"), and a name may hold a comma of its own ("Tyler, The Creator"), so
// without the bridge it is ONE entry, never split.
// ─────────────────────────────────────────────────────────────────────────────

var KINDS = "track|album|artist|playlist|episode|show"
var WEB   = new RegExp("^https?://open\\.spotify\\.com/(?:intl-[a-zA-Z-]+/)?(" + KINDS + ")/([A-Za-z0-9]{22})")
var URI   = new RegExp("^spotify:(" + KINDS + "):([A-Za-z0-9]{22})$")

// "https://open.spotify.com/track/<id>?si=…" → "spotify:track:<id>". "" for anything else.
function spotifyUri(url) {
    var m = WEB.exec(String(url || ""))
    return m ? "spotify:" + m[1] + ":" + m[2] : ""
}

// A well-formed Spotify uri, or "". The bridge's text is data, and it goes to a command line.
function cleanUri(uri) { return URI.test(String(uri || "")) ? String(uri) : "" }

function searchUri(text) {
    var q = String(text || "").trim().slice(0, 120)
    return q ? "spotify:search:" + encodeURIComponent(q) : ""
}

// What a link is for a uri: the spotify: uri itself, which the installed client opens IN THE APP. Never a track: a
// spotify:track: uri is played by the client when it is opened, so a track has no link (the album page is the link).
function appOf(uri) {
    var u = String(uri || "")
    if (/^spotify:search:[^\s]{1,200}$/.test(u)) return u
    var m = URI.exec(u)
    return m && m[1] !== "track" ? u : ""
}

// An address a link may open: http(s), with no whitespace or shell metacharacters.
function isWeb(url) { return /^https?:\/\/[^\s;|&$`<>"'\\]+$/.test(String(url || "")) }

// meta  { isSpotify, url, artist, album }   from the player
// extra { trackUri, albumUri, artists: [{ name, uri }] } | null   from the bridge, for THIS track only
// → { title, album, cover, artists: [{ name, link }] }   ("" is "no link")
function linksFor(meta, extra) {
    var m = meta || {}
    var x = extra || {}
    var artistName = String(m.artist || "")

    if (m.isSpotify) {
        // Every value below is a spotify: uri (or "" for nothing); see appOf.
        var album = cleanUri(x.albumUri) || searchUri([artistName, m.album].filter(Boolean).join(" "))
        var credits = []
        var given = Array.isArray(x.artists) ? x.artists : []
        for (var i = 0; i < given.length; i++) {
            var name = String((given[i] && given[i].name) || "")
            if (name !== "") credits.push({ name: name, link: cleanUri(given[i].uri) || searchUri(name) })
        }
        if (credits.length === 0 && artistName !== "") credits.push({ name: artistName, link: searchUri(artistName) })
        // The title opens the album it is on: the song itself would be played by the client.
        return { title: appOf(album), album: appOf(album), cover: appOf(album),
                 artists: credits.map(function (c) { return { name: c.name, link: appOf(c.link) } }) }
    }

    var page = isWeb(m.url) ? String(m.url) : ""
    return { title: page, album: "", cover: page, artists: artistName !== "" ? [{ name: artistName, link: "" }] : [] }
}

// The command that opens a link: a spotify: album, artist, playlist or search (the app), or an https page (the browser,
// for a video). Anything else runs nothing.
function openCommand(link) {
    var l = String(link || "")
    if (appOf(l) !== "") return ["xdg-open", l]
    return isWeb(l) && l.indexOf("https://") === 0 ? ["xdg-open", l] : []
}

// Where a link goes, for its tooltip: the app, or the browser.
function destinationOf(link) {
    var l = String(link || "")
    return appOf(l) !== "" ? "app" : isWeb(l) ? "browser" : ""
}
