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
const { filterSort, activeFilters, kinds, parseFindRow, dropPaths } =
    new Function(src + "\nreturn { filterSort, activeFilters, kinds, parseFindRow, dropPaths };")();

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

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
