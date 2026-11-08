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
//   o.sort      "name" (the library's own order) | "new"  (images by file time, scenes by Workshop id —
//               ids only ever grow, so the highest is the latest subscription)
//   o.mtimes    { path: epoch seconds } for the images; a path it lacks sorts as oldest
// ─────────────────────────────────────────────────────────────────────────────

function baseName(p) { return String(p).split("/").pop() }

function favKey(e, images) { return images ? baseName(e) : e.id }

function matchesKind(e, kind, images) {
    if (!kind || kind === "all") return true
    if (images) return kind === "gif" ? baseName(e).toLowerCase().endsWith(".gif") : true
    return String(e.type || "").toLowerCase() === kind
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

    let out = entries.filter(e => {
        if (s !== "") {
            const hit = images
                ? baseName(e).toLowerCase().includes(s)
                : String(e.title || "").toLowerCase().includes(s) || String(e.type || "").includes(s)
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
