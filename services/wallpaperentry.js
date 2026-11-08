.pragma library

// ── wallpaperentry.js ─────────────────────────────────────────────────────────
// One gallery entry, normalised.
//
// A wallpaper gallery entry is one of THREE shapes, and three views were each
// branching on it by hand:
//
//   · a STRING            — an image's absolute path
//   · a SCENE object      — { id, title, type, preview } from WallpaperEngine
//   · the ACTION card     — { action, glyph, title, caption }
//
// `WallpaperPanel` carried the same ~40-line readonly block VERBATIM in both its
// grid delegate and its list delegate, and `WallpaperPage` grew a third copy. The
// file's own comment said to share it "if this pattern comes up a third time" — it
// has. Pulling the shape logic here also means `bun` can exercise the branching
// that otherwise only shows up wrong on screen (a string asked for `.id` during a
// tab switch, a scene with no preview, an image path with no extension).
//
// ── What stays in QML ─────────────────────────────────────────────────────────
// Only the PURE description of the entry lives here. "Is this the live wallpaper"
// and "is this one applying" read the Wallpaper / WallpaperEngine / Config
// singletons and stay inline in the delegate — they are one line each and cannot
// be tested without a running shell anyway.
// ─────────────────────────────────────────────────────────────────────────────

// describe(entry) -> {
//   kind:  "action" | "scene" | "image"
//   key:   scene id  |  ""  |  absolute image path
//   name:  the title (scene / action) or the bare filename (image)
//   thumb: a file:// url for the preview, or "" (action, or a scene with no
//          preview on disk)
//   type:  scene -> "scene"/"video" (lowercased)  ·  image -> lowercased extension
//          ·  action -> ""
//   isGif: thumb points at a .gif (only images and some scene previews are)
// }
//
// A null / undefined entry describes as an image with empty everything, which is
// what the delegates want during construction and model swaps — no throw, no
// warning, just an inert tile.
function describe(entry) {
    const isObject = entry !== undefined && entry !== null && typeof entry === "object";
    const isAction = isObject && entry.action !== undefined;
    const isScene  = isObject && !isAction;

    const kind = isAction ? "action" : isScene ? "scene" : "image";

    const key = isScene  ? (entry.id ?? "")
              : isAction ? ""
              : String(entry ?? "");

    const name = isObject
        ? (entry.title ?? "")
        : String(entry ?? "").split("/").pop();

    let thumb = "";
    if (isScene) {
        const prev = entry.preview ?? "";
        thumb = prev !== "" ? "file://" + prev : "";
    } else if (kind === "image") {
        thumb = key !== "" ? "file://" + key : "";
    }

    const type = isScene ? String(entry.type ?? "").toLowerCase()
               : kind === "image" ? (key.indexOf(".") !== -1
                                     ? key.split(".").pop().toLowerCase() : "")
               : "";

    return {
        kind:  kind,
        key:   key,
        name:  name,
        thumb: thumb,
        type:  type,
        isGif: thumb.toLowerCase().endsWith(".gif"),
    };
}
