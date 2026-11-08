pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── AlbumArt ──────────────────────────────────────────────────────────────────
// The current cover's palette: a fill, an accent, and a text colour. The media cards
// dress themselves from this instead of from the shell's pywal palette.
//
// This exists because of a specific problem: the wallpaper is monochrome, so every
// accent in the shell is a shade of grey. The album cover is the ONE place real colour
// enters the overlay — so the media surfaces take their colour from the music, and
// re-theme themselves with every track.
//
// ── Always falls back ─────────────────────────────────────────────────────────
// Every role below resolves through `ready`. No art, a 404, a broken image, Pillow
// missing — any of those and the card is simply drawn in the pywal palette, exactly as
// it was before. A cover failing to load must never leave a card unstyled, so the
// script is written to always print JSON and always exit 0 (see scripts/album-colors.py);
// there is no error path that reaches here as a crash.
//
// Cached by URL: re-playing a track, or scrubbing within one, costs nothing. The work
// only happens when the cover actually changes.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Set by whoever is showing media. "" clears back to the shell palette.
    property string source: ""

    // The playing source's id (spotify, youtube, …), set alongside `source`. Only used
    // for the brand fallback below.
    property string sourceId: ""

    // ── Brand fallback for grey covers ────────────────────────────────────────
    // A genuinely monochrome cover extracts to a grey accent — there is no colour in it
    // to find. Rather than let the media cards go grey (which is the whole thing we're
    // trying to escape), fall back to the SOURCE's brand palette: a black-and-white
    // Spotify cover still gets Spotify green.
    //
    // Only triggers when the cover is actually colourless (the script reports the raw
    // saturation) AND we know the source. A colourful cover always wins — the art is the
    // point; the brand colour is the safety net.
    readonly property real _greyThreshold: 0.15
    readonly property var _brand: ({
        "spotify":       { bg: "#191414", accent: "#1DB954" },
        "youtube":       { bg: "#0F0F0F", accent: "#FF0000" },
        "youtube-music": { bg: "#030303", accent: "#FF0000" },
        "soundcloud":    { bg: "#1A1A1A", accent: "#FF5500" },
        "bandcamp":      { bg: "#1A2A30", accent: "#629AA9" }
    })

    // A source's brand palette ({ bg, accent }), or null for one with no brand here. For a
    // surface that themes itself for a source (the media panel on YouTube) — it reads the
    // brand from this one table rather than keeping a second copy of the colour.
    function brandOf(id) { return root._brand[id] || null }

    property bool  ready: false
    property color bgRaw:     Colors.surface
    property color accentRaw: Colors.primary
    property color fgRaw:     Colors.fg

    // ── The roles the cards actually read ─────────────────────────────────────
    readonly property color bg:     root.ready ? root.bgRaw     : Colors.surface
    readonly property color accent: root.ready ? root.accentRaw : Colors.focus
    readonly property color fg:     root.ready ? root.fgRaw     : Colors.fg

    readonly property color fgMuted: Colors.alpha(root.fg, 0.70)
    readonly property color fgDim:   Colors.alpha(root.fg, 0.35)

    function alpha(c, a) { return Colors.alpha(c, a) }

    // ── Bigger artwork for DISPLAY ────────────────────────────────────────────
    // Spotify hands MPRIS the 640px variant of a cover. The id is the same across sizes —
    // only the prefix differs — so the 1400px original is one string swap away:
    //
    //   ab67616d00001e02…   300 ×  300
    //   ab67616d0000b273…   640 ×  640   ← what MPRIS gives us
    //   ab67616d000082c1…  1400 × 1400   ← what we actually want to draw
    //
    // Anything that isn't a recognised Spotify url passes straight through — a local
    // file, a podcast thumbnail, some other player's art. Never rewrite a url you don't
    // understand.
    //
    // Deliberately used for DISPLAY ONLY. The palette extraction still runs on whatever
    // MPRIS gave us: downloading 437KB instead of 89KB to work out six swatches from a
    // 64×64 thumbnail would be pure waste.
    function hiRes(url) {
        if (!url) return ""
        return url.indexOf("ab67616d0000b273") >= 0
            ? url.replace("ab67616d0000b273", "ab67616d000082c1")
            : url
    }

    property var _cache: ({})       // url → { bg, accent, fg, sat }
    property string _pending: ""

    readonly property string scriptPath:
        Qt.resolvedUrl("../scripts/album-colors.py").toString().replace("file://", "")

    // Publish an extraction to the roles, substituting the source's brand palette when the
    // cover is colourless. Kept out of the two call sites so the brand rule lives once.
    function _publish(d) {
        const brand = root._brand[root.sourceId]
        if (d.sat < root._greyThreshold && brand) {
            root.bgRaw     = brand.bg
            root.accentRaw = brand.accent
            root.fgRaw     = "#F2F2F2"          // legible on any of the dark brand grounds
        } else {
            root.bgRaw     = d.bg
            root.accentRaw = d.accent
            root.fgRaw     = d.fg
        }
        root.ready = true
    }

    onSourceChanged: root._resolve()

    function _resolve() {
        const url = root.source

        if (!url) {
            root.ready = false
            return
        }

        const hit = root._cache[url]
        if (hit) {
            root._publish(hit)
            return
        }

        // Don't clear `ready` here. The previous track's colours stay up until the new
        // ones arrive (~200ms), so the card cross-fades from one album to the next
        // instead of blinking through the grey fallback on every single track change.
        root._pending = url
        proc.command  = ["python3", root.scriptPath, url]
        proc.running  = true
    }

    Process {
        id: proc

        property string out: ""

        stdout: SplitParser {
            onRead: function(line) { proc.out += line }
        }

        onExited: {
            const text = proc.out
            const url  = root._pending
            proc.out = ""

            if (url !== root.source) return      // the track moved on while we were working

            try {
                const d = JSON.parse(text)
                if (!d.ok) {
                    // Not worth a warning: a track with no cover is ordinary, and this
                    // path is the designed fallback, not a malfunction.
                    root.ready = false
                    return
                }

                // Cache the RAW extraction (including saturation) — the brand fallback is
                // resolved at publish time against the current source, not baked in.
                const raw = { bg: d.bg, accent: d.accent, fg: d.fg, sat: d.sat ?? 1 }
                root._cache[url] = raw
                root._publish(raw)
            } catch (e) {
                console.warn("AlbumArt: could not parse palette —", e)
                root.ready = false
            }
        }
    }
}
