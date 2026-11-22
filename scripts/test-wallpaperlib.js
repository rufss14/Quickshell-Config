// ── test-wallpaperlib.js ─────────────────────────────────────────────────────
// Tests for services/wallpaperlib.js, the gallery's search / filter / sort.
//
//     bun scripts/test-wallpaperlib.js
//
// Loaded the way test-wallpaperentry.js does it: the real file, `.pragma library` stripped.
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "wallpaperlib.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { filterSort, activeFilters, kinds, parseFindRow, dropPaths, crumbs, pasteKinds, colorKey, colorName, colorWord, COLORS } =
    new Function(src + "\nreturn { filterSort, activeFilters, kinds, parseFindRow, dropPaths, crumbs, pasteKinds, colorKey, colorName, colorWord, COLORS };")();

let pass = 0, fail = 0;
function check(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log("FAIL  " + name + (detail ? "  → " + detail : "")); }
}
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);

const imgs = ["/w/b.png", "/w/a.jpg", "/w/c.gif", "/w/Dune.PNG"];
const mt = { "/w/b.png": 100, "/w/a.jpg": 300, "/w/c.gif": 200 };
const scenes = [
    { id: "30", title: "Rain", type: "scene" },
    { id: "200", title: "Loop", type: "video" },
    { id: "abc", title: "Odd", type: "scene" },
    { id: "100", title: "Aurora", type: "Scene" },
];

// ── images
check("no options keeps the order", same(filterSort(imgs, { images: true }), imgs));
check("search is case-insensitive on the file name", same(filterSort(imgs, { images: true, search: "DUNE" }), ["/w/Dune.PNG"]));
check("search matches the name, not the folder", same(filterSort(imgs, { images: true, search: "w/" }), []));
check("gif kind", same(filterSort(imgs, { images: true, kind: "gif" }), ["/w/c.gif"]));
check("favourites float to the front", same(filterSort(imgs, { images: true, favs: ["c.gif", "a.jpg"] }),
    ["/w/a.jpg", "/w/c.gif", "/w/b.png", "/w/Dune.PNG"]));
check("favOnly keeps just the starred, in order", same(filterSort(imgs, { images: true, favOnly: true, favs: ["Dune.PNG", "b.png"] }),
    ["/w/b.png", "/w/Dune.PNG"]));
check("favOnly with no favourites is empty", same(filterSort(imgs, { images: true, favOnly: true, favs: [] }), []));
check("newest by file time, unknown last", same(filterSort(imgs, { images: true, sort: "new", mtimes: mt }),
    ["/w/a.jpg", "/w/c.gif", "/w/b.png", "/w/Dune.PNG"]));
check("newest without mtimes keeps the order", same(filterSort(imgs, { images: true, sort: "new" }), imgs));
check("newest, then favourites on top of it", same(filterSort(imgs, { images: true, sort: "new", mtimes: mt, favs: ["b.png"] }),
    ["/w/b.png", "/w/a.jpg", "/w/c.gif", "/w/Dune.PNG"]));
check("sort leaves the input alone", same(imgs, ["/w/b.png", "/w/a.jpg", "/w/c.gif", "/w/Dune.PNG"]));

// ── scenes
check("scene search matches the title", same(filterSort(scenes, { images: false, search: "aur" }).map(s => s.id), ["100"]));
check("scene search matches the type", same(filterSort(scenes, { images: false, search: "video" }).map(s => s.id), ["200"]));
check("scene kind video", same(filterSort(scenes, { images: false, kind: "video" }).map(s => s.id), ["200"]));
check("scene kind is case-blind", same(filterSort(scenes, { images: false, kind: "scene" }).map(s => s.id), ["30", "abc", "100"]));
check("scenes newest = highest id, non-numeric last", same(filterSort(scenes, { images: false, sort: "new" }).map(s => s.id),
    ["200", "100", "30", "abc"]));
check("scene favourites are ids", same(filterSort(scenes, { images: false, favs: ["abc"] }).map(s => s.id), ["abc", "30", "200", "100"]));

// ── degenerate input
check("empty library", same(filterSort([], { images: true, search: "x", sort: "new" }), []));
check("undefined search/kind/favs are fine", same(filterSort(imgs, { images: true, search: undefined, kind: undefined, favs: undefined }), imgs));
check("a scene with no title or type does not throw", same(filterSort([{ id: "1" }], { images: false, search: "a" }), []));

// ── helpers
check("activeFilters counts favOnly and a kind", activeFilters({ favOnly: true, kind: "gif" }) === 2);
check("activeFilters: all is none", activeFilters({ favOnly: false, kind: "all" }) === 0 && activeFilters({}) === 0);
check("kinds differ by source", kinds(true).length === 2 && kinds(false).length === 3 && kinds(true)[0].value === "all");
check("parseFindRow", same(parseFindRow("1730000000.5\t/w/a b.png"), { t: 1730000000.5, p: "/w/a b.png" }));
check("parseFindRow keeps a tab in the name", parseFindRow("5\t/w/a\tb.png").p === "/w/a\tb.png");
check("parseFindRow drops junk", parseFindRow("/w/a.png") === null && parseFindRow("x\t/w/a.png") === null && parseFindRow("5\t") === null);

// ── drops
check("dropPaths decodes %-escapes", same(dropPaths(["file:///home/u/My%20Pic.PNG"]), ["/home/u/My Pic.PNG"]));
check("dropPaths keeps only the library's extensions", same(dropPaths(["file:///a/x.txt", "file:///a/y.jpeg", "file:///a/z.GIF", "file:///a/w.webp"]), ["/a/y.jpeg", "/a/z.GIF"]));
check("dropPaths refuses non-file URLs", same(dropPaths(["https://x.test/a.png", "ftp://h/a.png", "/a/b.png"]), []));
check("dropPaths survives a bad escape", same(dropPaths(["file:///a/%E0%A4%A.png", "file:///a/ok.png"]), ["/a/ok.png"]));
check("dropPaths de-duplicates", same(dropPaths(["file:///a/x.png", "file:///a/x.png"]), ["/a/x.png"]));
check("dropPaths on nothing", same(dropPaths(undefined), []) && same(dropPaths([]), []));
check("dropPaths drops a relative path", same(dropPaths(["file://a/b.png"]), []));

// ── crumbs
check("crumbs inside home start at Home", same(crumbs("file:///home/u/Pictures/Art", "/home/u"),
    [{ label: "Home", path: "/home/u" }, { label: "Pictures", path: "/home/u/Pictures" }, { label: "Art", path: "/home/u/Pictures/Art" }]));
check("crumbs of home itself", same(crumbs("file:///home/u", "/home/u"), [{ label: "Home", path: "/home/u" }]));
check("crumbs outside home start at /", same(crumbs("file:///mnt/disk/x", "/home/u"),
    [{ label: "/", path: "/" }, { label: "mnt", path: "/mnt" }, { label: "disk", path: "/mnt/disk" }, { label: "x", path: "/mnt/disk/x" }]));
check("crumbs of the root", same(crumbs("file:///", "/home/u"), [{ label: "/", path: "/" }]));
check("crumbs decode escapes", crumbs("file:///home/u/My%20Pics", "/home/u")[1].label === "My Pics");
check("crumbs: /home/user2 is not inside /home/u", crumbs("file:///home/user2/a", "/home/u")[0].label === "/");
check("crumbs survive a bad escape", crumbs("file:///home/u/%E0%A4%A", "/home/u").length === 2);
check("crumbs with no home", crumbs("file:///a/b", "")[0].label === "/");

// ── colour
check("colorName: pure hues", colorName("#ff0000") === "red" && colorName("#00ff00") === "green" && colorName("#0000ff") === "blue");
check("colorName: in-between hues land on the nearest", colorName("#ff7f00") === "orange" && colorName("#ffd400") === "yellow" && colorName("#8000ff") === "purple" && colorName("#ff1493") === "pink");
check("colorName: neutrals", colorName("#101010") === "black" && colorName("#f2f2f2") === "white" && colorName("#808080") === "grey");
check("colorName: unknown", colorName("") === "" && colorName("nope") === "" && colorName(undefined) === "");
check("colorWord: names and aliases", colorWord("Blue") === "blue" && colorWord(" gray ") === "grey" && colorWord("cyan") === "teal");
check("colorWord: not a colour", colorWord("dune") === "" && colorWord("") === "");
check("colorKey: red first, then round the wheel", colorKey("#ff0000") < colorKey("#ffd400") && colorKey("#ffd400") < colorKey("#00ff00") && colorKey("#00ff00") < colorKey("#0000ff"));
check("colorKey: neutrals after every hue, light to dark", colorKey("#ff1493") < colorKey("#f2f2f2") && colorKey("#f2f2f2") < colorKey("#404040"));
check("colorKey: unknown is last", colorKey("") > colorKey("#000000"));
const cols = { "/w/b.png": "#0000ff", "/w/a.jpg": "#ff0000", "/w/c.gif": "#00ff00", "/w/Dune.PNG": "#202020" };
check("sort by colour walks the spectrum", same(filterSort(imgs, { images: true, sort: "color", colors: cols }), ["/w/a.jpg", "/w/c.gif", "/w/b.png", "/w/Dune.PNG"]));
check("sort by colour does not float favourites", same(filterSort(imgs, { images: true, sort: "color", colors: cols, favs: ["b.png"] }), ["/w/a.jpg", "/w/c.gif", "/w/b.png", "/w/Dune.PNG"]));
check("a picture with no colour known sorts last", same(filterSort(["/w/x.png", "/w/a.jpg"], { images: true, sort: "color", colors: cols }), ["/w/a.jpg", "/w/x.png"]));
check("searching a colour name finds that colour", same(filterSort(imgs, { images: true, search: "blue", colors: cols }), ["/w/b.png"]));
check("a colour word still matches a file name", same(filterSort(["/w/blue-sky.png", "/w/a.jpg"], { images: true, search: "blue", colors: cols }), ["/w/blue-sky.png"]));
check("scenes colour by their preview", same(filterSort([{ id: "1", title: "A", type: "scene", preview: "/p/1.jpg" }, { id: "2", title: "B", type: "scene", preview: "/p/2.jpg" }],
    { images: false, search: "red", colors: { "/p/1.jpg": "#ff0000", "/p/2.jpg": "#0000ff" } }).map(e => e.id), ["1"]));
check("a non-colour search is unchanged by the colours", same(filterSort(imgs, { images: true, search: "dune", colors: cols }), ["/w/Dune.PNG"]));
check("eight hues, each named once", COLORS.length === 8 && new Set(COLORS.map(c => c.id)).size === 8);

// ── paste
check("paste: a PNG is taken as it is", same(pasteKinds(["image/png", "text/html"]), { files: false, image: "image/png", ext: "png", convert: false }));
check("paste: a JPEG keeps its type", same(pasteKinds(["image/jpeg"]), { files: false, image: "image/jpeg", ext: "jpg", convert: false }));
check("paste: PNG beats the other image types", pasteKinds(["image/webp", "image/png"]).image === "image/png");
check("paste: a WebP alone is converted to PNG", same(pasteKinds(["image/webp"]), { files: false, image: "image/webp", ext: "png", convert: true }));
check("paste: copied files are seen", pasteKinds(["text/uri-list", "x-special/gnome-copied-files"]).files === true);
check("paste: files and a picture at once", pasteKinds(["text/uri-list", "image/png"]).files && pasteKinds(["text/uri-list", "image/png"]).image === "image/png");
check("paste: text only offers nothing", same(pasteKinds(["text/plain", "UTF8_STRING"]), { files: false, image: "", ext: "", convert: false }));
check("paste: nothing at all", same(pasteKinds([]), { files: false, image: "", ext: "", convert: false }) && pasteKinds(undefined).image === "");
check("paste: types are matched whatever their case", pasteKinds(["Image/PNG\n"]).image === "image/png");
check("paste: an SVG is not taken", pasteKinds(["image/svg+xml"]).image === "");

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
