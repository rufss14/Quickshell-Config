.pragma library

// ── wallpaperlib.js ───────────────────────────────────────────────────────────
// What the gallery shows out of a library: search, kind filter, favourites-only, sort, and
// favourites floated to the front. Pure, so `bun scripts/test-wallpaperlib.js` exercises it; it was
// a 25-line binding inside WallpaperPanel that nothing could test.
//
// An entry is the panel's: an image is a path STRING, a scene is { id, title, type, … }. (The
// action card is added by the panel AFTER this, so it is never filtered or sorted away.)
//
//   o.images    true → entries are paths, false → scenes
//   o.search    case-insensitive; images match the file name, scenes the title or type
//   o.kind      "all" | images: "gif" | scenes: "scene" / "video"
//   o.favOnly   keep only starred entries
//   o.favs      the starred ones: file NAMES for images, scene ids for scenes (Config.wallFavorites /
//               Config.wpeFavorites)
//   o.sort      "name" (the library's own order) | "color" (the spectrum, below) | "new"  (images by file time, scenes by Workshop id —
//               ids only ever grow, so the highest is the latest subscription)
//   o.mtimes    { path: epoch seconds } for the images; a path it lacks sorts as oldest
//   o.colors    { picture path: "#rrggbb" } what each picture is mostly (scripts/wall-colors.py): an image's own
//               path, a scene's PREVIEW path. `sort: "color"` walks the spectrum with it, and a search that is
//               a colour's name ("blue") also matches what has that colour.
// ─────────────────────────────────────────────────────────────────────────────

function baseName(p) { return String(p).split("/").pop() }

function favKey(e, images) { return images ? baseName(e) : e.id }

function matchesKind(e, kind, images) {
    if (!kind || kind === "all") return true
    if (images) return kind === "gif" ? baseName(e).toLowerCase().endsWith(".gif") : true
    return String(e.type || "").toLowerCase() === kind
}

// ── Colour ────────────────────────────────────────────────────────────────────
// A picture's colour is one "#rrggbb" (its dominant vivid colour, or its average when it has none). Sorting
// goes round the hue wheel from red, then the neutrals from light to dark, then what has no colour known yet.
// Names are for the search box and the swatches: eight hues, and black / white / grey for the neutrals.
const COLORS = [
    { id: "red", hue: 0 }, { id: "orange", hue: 28 }, { id: "yellow", hue: 52 }, { id: "green", hue: 120 },
    { id: "teal", hue: 175 }, { id: "blue", hue: 220 }, { id: "purple", hue: 270 }, { id: "pink", hue: 325 }
]
const ALIASES = { gray: "grey", cyan: "teal", aqua: "teal", violet: "purple", magenta: "pink", indigo: "blue" }

function hsl(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(String(hex || ""))
    if (!m) return null
    const n = parseInt(m[1], 16)
    const r = ((n >> 16) & 255) / 255, g = ((n >> 8) & 255) / 255, b = (n & 255) / 255
    const mx = Math.max(r, g, b), mn = Math.min(r, g, b), d = mx - mn
    const l = (mx + mn) / 2
    const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1))
    let h = 0
    if (d !== 0) {
        if (mx === r) h = ((g - b) / d) % 6
        else if (mx === g) h = (b - r) / d + 2
        else h = (r - g) / d + 4
        h *= 60
        if (h < 0) h += 360
    }
    return { h: h, s: s, l: l }
}

function neutral(c) { return c.s < 0.14 || c.l < 0.1 || c.l > 0.93 }

// The number a picture sorts by: the hue for a colour, 400 plus its darkness for a neutral, 2000 when unknown.
function colorKey(hex) {
    const c = hsl(hex)
    if (!c) return 2000
    return neutral(c) ? 400 + (1 - c.l) * 100 : c.h
}

// "red" … "pink", "black" / "white" / "grey", or "" when the colour is unknown.
function colorName(hex) {
    const c = hsl(hex)
    if (!c) return ""
    if (neutral(c)) return c.l < 0.2 ? "black" : c.l > 0.8 ? "white" : "grey"
    let best = COLORS[0].id, bd = 999
    for (const k of COLORS) {
        const d = Math.min(Math.abs(c.h - k.hue), 360 - Math.abs(c.h - k.hue))
        if (d < bd) { bd = d; best = k.id }
    }
    return best
}

// The eight hues, for the swatches the search offers: [{ id, hue }].
function colorList() { return COLORS }

// What a search term means as a colour name ("gray" is "grey"), or "".
function colorWord(term) {
    const t = String(term || "").trim().toLowerCase()
    const w = ALIASES[t] || t
    return (w === "black" || w === "white" || w === "grey" || COLORS.some(k => k.id === w)) ? w : ""
}

function colorOf(e, o) {
    const key = o.images ? e : e.preview
    return (o.colors && o.colors[key]) || ""
}

function recency(e, o) {
    if (o.images) return (o.mtimes && o.mtimes[e]) || 0
    const n = Number(e.id)
    return isFinite(n) ? n : 0
}

function filterSort(entries, o) {
    const images = !!o.images
    const s = String(o.search || "").toLowerCase()
    const favs = o.favs || []
    const isFav = e => favs.indexOf(favKey(e, images)) !== -1

    const word = colorWord(s)
    let out = entries.filter(e => {
        if (s !== "") {
            const hit = (images
                ? baseName(e).toLowerCase().includes(s)
                : String(e.title || "").toLowerCase().includes(s) || String(e.type || "").includes(s))
                || (word !== "" && colorName(colorOf(e, o)) === word)
            if (!hit) return false
        }
        if (o.favOnly && !isFav(e)) return false
        return matchesKind(e, o.kind, images)
    })

    if (o.sort === "new") {
        // decorate with the index so equal times keep the library's order, whatever the engine's sort does
        out = out.map((e, i) => ({ e: e, i: i, t: recency(e, o) }))
                 .sort((a, b) => (b.t - a.t) || (a.i - b.i))
                 .map(x => x.e)
    }

    if (o.sort === "color") {
        // The spectrum is the point: favourites do not float out of it.
        return out.map((e, i) => ({ e: e, i: i, k: colorKey(colorOf(e, o)) }))
                  .sort((a, b) => (a.k - b.k) || (a.i - b.i))
                  .map(x => x.e)
    }

    if (favs.length === 0 || o.favOnly) return out
    // filter-then-concat rather than a sort, so nothing rides on sort stability
    return out.filter(isFav).concat(out.filter(e => !isFav(e)))
}

// How many filters are narrowing the view (the toolbar's badge); search is not one, it has its own box.
function activeFilters(o) {
    return (o.favOnly ? 1 : 0) + ((o.kind && o.kind !== "all") ? 1 : 0)
}

// The kinds a source offers, for the filter menu: [{ value, label }].
function kinds(images) {
    return images
        ? [{ value: "all", label: "All" }, { value: "gif", label: "Animated" }]
        : [{ value: "all", label: "All" }, { value: "scene", label: "Scenes" }, { value: "video", label: "Videos" }]
}

// `find -printf "%T@\t%p"` rows → { path: seconds }. A row that doesn't parse is dropped.
function parseFindRow(line) {
    const i = line.indexOf("\t")
    if (i < 1) return null
    const t = parseFloat(line.slice(0, i))
    const p = line.slice(i + 1)
    return (isFinite(t) && p !== "") ? { t: t, p: p } : null
}

// What a drop onto the panel may import: the local image files among the dropped URLs, as plain paths
// (Wallpaper.addPaths copies them in). A drop is outside input, so anything that is not a file:// URL
// to a .jpg/.jpeg/.png/.gif (the library's own extensions) is dropped, a malformed %-escape included.
function dropPaths(urls) {
    const out = []
    for (const u of (urls || [])) {
        const s = String(u)
        if (!s.startsWith("file://")) continue
        let p
        try { p = decodeURIComponent(s.slice(7)) } catch (e) { continue }
        if (!p.startsWith("/") || !/\.(jpe?g|png|gif)$/i.test(p)) continue
        if (out.indexOf(p) === -1) out.push(p)
    }
    return out
}

// ── pasteKinds ────────────────────────────────────────────────────────────────
// What the clipboard (`wl-paste --list-types`) offers that the library can take: copied FILES (a file manager
// puts a text/uri-list there, filtered afterwards by dropPaths), or a PICTURE's own data. A PNG, JPEG or GIF is
// saved as it is; any other image type (WebP, BMP…) is converted to a PNG, because the library holds only
// jpg / png / gif. { files, image: the mime to read, ext: the file's, convert }.
function pasteKinds(types) {
    const t = (types || []).map(x => String(x).trim().toLowerCase()).filter(x => x !== "")
    const plain = ["image/png", "image/jpeg", "image/gif"]
    const direct = plain.find(m => t.indexOf(m) !== -1) || ""
    const image = direct || t.find(m => /^image\/(webp|bmp|tiff|avif)$/.test(m)) || ""
    return {
        files: t.indexOf("text/uri-list") !== -1,
        image: image,
        ext: image === "" ? "" : image === "image/jpeg" ? "jpg" : image === "image/gif" ? "gif" : "png",
        convert: image !== "" && direct === ""
    }
}

// ── crumbs ────────────────────────────────────────────────────────────────────
// The file browser's path as clickable steps: [{ label, path }], the first being where the path starts
// ("Home" when it is inside `home`, "/" otherwise), each later one a folder name. `url` is the folder as
// the browser holds it ("file:///a/b%20c"); a bad escape keeps the raw text rather than throwing.
function crumbs(url, home) {
    let p = String(url || "").replace(/^file:\/\//, "")
    try { p = decodeURIComponent(p) } catch (e) {}
    p = p.replace(/\/+$/, "")
    const h = String(home || "").replace(/\/+$/, "")
    const inHome = h !== "" && (p === h || p.startsWith(h + "/"))
    const out = [{ label: inHome ? "Home" : "/", path: inHome ? h : "/" }]
    const rest = (inHome ? p.slice(h.length) : p).split("/").filter(x => x !== "")
    let acc = inHome ? h : ""
    for (const seg of rest) { acc += "/" + seg; out.push({ label: seg, path: acc }) }
    return out
}
