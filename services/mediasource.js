.pragma library

// ── mediasource.js ────────────────────────────────────────────────────────────
// Where is the audio actually coming FROM — Spotify, YouTube, SoundCloud — as opposed
// to which application happens to be playing it.
//
// ── The URL first, and that ordering is the whole point ───────────────────────
// A browser playing YouTube identifies itself as THE BROWSER — desktopEntry "zen",
// identity "Zen Browser" — so app identity can only ever tell you the window, never the
// source. `xesam:url` is the one field that knows the difference between "a browser" and
// "YouTube". (Spotify, for comparison, reports desktopEntry "spotify" AND
// xesam:url "https://open.spotify.com/track/…" — either would do. The browser case is
// the one that needs this.)
//
// ── Why it lives here rather than in the media card ───────────────────────────
// It was a `readonly property var source` inside OverviewNowPlaying, and three other
// things now need the same answer: the lyrics card (which hides itself on YouTube, where
// the metadata is a video title rather than a track), the lockscreen (same rule), and the
// album colour scheme (which only follows sources that report real metadata). Copying the
// host table into each of them is how "YouTube in a PWA" ends up handled in one place and
// not the others.
// ─────────────────────────────────────────────────────────────────────────────

var HOSTS = {
    "open.spotify.com":   { id: "spotify",       name: "Spotify"       },
    "music.youtube.com":  { id: "youtube-music", name: "YouTube Music" },
    "www.youtube.com":    { id: "youtube",       name: "YouTube"       },
    "youtube.com":        { id: "youtube",       name: "YouTube"       },
    "youtu.be":           { id: "youtube",       name: "YouTube"       },
    "soundcloud.com":     { id: "soundcloud",    name: "SoundCloud"    },
    "bandcamp.com":       { id: "bandcamp",      name: "Bandcamp"      }
}

// Pull the host out of a url without a URL parser: everything between "//" and the next
// "/". A local file (file:///…) yields nothing, which is correct — a local file's source
// IS the app playing it.
function hostOf(url) {
    const after = String(url || "").indexOf("//")
    if (after < 0) return ""
    const rest = url.substring(after + 2)
    const end  = rest.indexOf("/")
    return (end >= 0 ? rest.substring(0, end) : rest).toLowerCase()
}

// { id, name } for an MPRIS player. Never null — an unknown player answers with its own
// desktop entry / identity, which is the honest answer for a local file.
function resolve(player) {
    const url = (player && player.metadata) ? (player.metadata["xesam:url"] || "") : ""

    if (url) {
        const host = hostOf(url)
        if (HOSTS[host]) return HOSTS[host]

        // bandcamp serves from <artist>.bandcamp.com.
        for (const h in HOSTS)
            if (host.length > h.length && host.indexOf("." + h, host.length - h.length - 1) >= 0)
                return HOSTS[h]
    }

    const entry = (player && player.desktopEntry) || ""
    const ident = (player && player.identity)     || ""
    return { id: entry || ident, name: ident || entry }
}

function idOf(player) { return resolve(player).id }

// ── Sources whose metadata a lyrics lookup can trust ──────────────────────────
// The lookup is keyed on artist and title. YouTube hands MPRIS the VIDEO title —
// "Artist - Song (Official Music Video) [4K]", a one-hour mix, a live stream — with the
// channel as the artist. That either misses or, worse, matches a DIFFERENT song and
// scrolls confident wrong words in time with your music.
//
// A denylist rather than an allowlist, deliberately: a local FLAC in mpv has perfectly
// good tags and would fail an allowlist for no reason. Only the sources that are known
// to lie are named.
var LYRICS_DENY = ["youtube"]

function lyricsTrusted(player) {
    return LYRICS_DENY.indexOf(idOf(player)) < 0
}

// ── Sources the shell will take its whole colour scheme from ──────────────────
// An ALLOWLIST here, and the asymmetry with LYRICS_DENY above is deliberate. Lyrics are
// a card that appears and disappears; the song scheme repaints the entire desktop, so it
// only follows sources that reliably hand over real per-track cover art. YouTube's
// "cover" is a video thumbnail — a face, a text card, a black frame — and letting that
// pick the shell's accent is exactly the thing this must not do.
//
// Extend it here, not at the call sites.
var SCHEME_SOURCES = ["spotify", "soundcloud"]

function schemeEligible(player) {
    return SCHEME_SOURCES.indexOf(idOf(player)) >= 0
}

// ── Which player is "the" player ──────────────────────────────────────────────
// Pinned first, then whatever is actually playing, then stickily whatever we had.
// Never null-out a working choice just because nothing is playing: pausing a track must
// not blank the card.
//
// A pin naming something that is not running falls through rather than showing nothing —
// a closed browser silencing the card for whatever else IS playing is the worse failure.
//
// ── Why this is a function and not a property ─────────────────────────────────
// The media card owned this rule, and the card is inside the overview, which is
// lazy-loaded. So the answer to "what is playing" only existed while the overlay was
// OPEN. That is fine for a card — a card nobody is looking at needs no player — and
// completely wrong for the album colour scheme, which has to follow the music whether
// or not anything is on screen.
//
// It is not a singleton either, because the choice is not global: `pin` is a per-card
// setting (a desktop tile can be pinned to a different player than the overview). The
// RULE is shared; the answer is per-caller. AlbumScheme passes no pin — the desktop's
// colour follows what is playing, not what some tile is displaying.
function pickPlayer(players, current, pin) {
    var all = players || []

    if (pin) {
        for (var p = 0; p < all.length; p++)
            if (all[p].identity === pin) return all[p]
    }

    for (var i = 0; i < all.length; i++)
        if (all[i].isPlaying) return all[i]

    // Nothing playing — keep the current one if it still exists.
    for (var j = 0; j < all.length; j++)
        if (all[j] === current) return current

    return all.length > 0 ? all[0] : null
}

// ── An icon for "who am I turning the volume up on" ────────────────────────────
// The scroll-to-volume OSD wants to say WHICH player it just adjusted, not just that
// something changed. Real brand glyphs where the codebase's Nerd Font actually ships
// one (verified against CodeNewRomanNerdFontMono's own cmap — guessing a codepoint here
// fails silently as a blank tile, not an error); a generic note for everything else,
// same as Spotify would look like before this existed.
var SOURCE_GLYPH = {
    "spotify":       "",   // fa-spotify
    "youtube":       "󰗃",   // md-youtube
    "youtube-music": "󰗃",   // md-youtube — no distinct brand mark for the music app
    "soundcloud":    "",   // fa-soundcloud
    "bandcamp":      ""    // fa-bandcamp
}

var SOURCE_GLYPH_FALLBACK = ""   // fa-music

function sourceGlyph(player) {
    return SOURCE_GLYPH[idOf(player)] || SOURCE_GLYPH_FALLBACK
}

// ── Which window is showing this video ────────────────────────────────────────
// A browser names its window after the ACTIVE tab, so the window whose title contains
// the player's track title is the one showing it ("(825) FNAF Lore Explained! - YouTube
// — Zen Browser"). That is the only link between an MPRIS player and a window: MPRIS
// carries no window id, and the title is the one field both sides spell the same.
//
// Firefox-family browsers can also pop the video into its own window, titled exactly
// "Picture-in-Picture" — the video and nothing else, so it beats the whole browser
// window when there is one. It is only taken when it belongs to the same browser: the
// matched tab window's class, or failing that the player's desktop entry.
//
// `tops` are Hyprland toplevels (title, wayland.appId). Returns one with a `wayland`
// handle (the thing a capture needs), or null — which includes "the video is in a
// background tab", where no window shows it and nothing honest can be captured.
function videoWindow(tops, title, desktopEntry) {
    const want = String(title || "").trim().toLowerCase()
    if (!want) return null

    const entry = String(desktopEntry || "").toLowerCase()
    const classOf = t => String((t.wayland && t.wayland.appId) || "").toLowerCase()

    var tab = null, pip = null
    for (var i = 0; i < (tops || []).length; i++) {
        const t = tops[i]
        if (!t || !t.wayland) continue
        const name = String(t.title || "").toLowerCase()
        if (!tab && name.indexOf(want) >= 0) tab = t
        else if (!pip && name === "picture-in-picture") pip = t
    }

    const browser = tab ? classOf(tab) : entry
    if (pip && browser && classOf(pip) === browser) return pip
    return tab
}

