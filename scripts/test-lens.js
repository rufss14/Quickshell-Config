// ── test-lens.js ──────────────────────────────────────────────────────────────
// services/lens.js — the OCR lens's geometry.   bun scripts/test-lens.js   (pure)
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "lens.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const L = new Function(src + "\nreturn { parseRegion, grimGeometry, local, place, toolbar, copyText };")();

let pass = 0, fail = 0;
function check(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) pass++; else { fail++; console.log("FAIL " + name + "\n  got:  " + g + "\n  want: " + w); }
}

check("region", L.parseRegion("100 200 300 40 DP-1\n"), { x: 100, y: 200, w: 300, h: 40, output: "DP-1" });
check("negative origin", L.parseRegion("-1920 0 50 50 HDMI-A-1").x, -1920);
check("cancelled", L.parseRegion(""), null);
check("a slip", L.parseRegion("10 10 2 30 DP-1"), null);
check("junk", L.parseRegion("10 10 30x30 DP-1"), null);
check("grim", L.grimGeometry({ x: 5, y: 6, w: 7, h: 8 }), "5,6 7x8");
check("local", L.local({ x: 2000, y: 100, w: 10, h: 10 }, 1920, 0), { x: 80, y: 100, w: 10, h: 10 });
// A 2× output: the capture is twice the region.
check("place @2x", L.place({ x: 20, y: 10, w: 100, h: 30 }, { x: 50, y: 60, w: 200, h: 100 }, 400, 200),
      { x: 60, y: 65, w: 50, h: 15 });
check("toolbar below", L.toolbar({ x: 100, y: 100, w: 200, h: 50 }, 100, 40, 1000, 800, 8, 8), { x: 150, y: 158 });
check("toolbar above", L.toolbar({ x: 100, y: 700, w: 200, h: 80 }, 100, 40, 1000, 800, 8, 8), { x: 150, y: 652 });
check("toolbar inside", L.toolbar({ x: 0, y: 10, w: 1000, h: 780 }, 100, 40, 1000, 800, 8, 8), { x: 450, y: 742 });
check("toolbar clamped", L.toolbar({ x: 980, y: 100, w: 20, h: 20 }, 100, 40, 1000, 800, 8, 8).x, 892);
const lines = [{ text: "a" }, { text: "b" }];
check("copy original", L.copyText(lines, ["x", "y"], false), "a\nb");
check("copy translation", L.copyText(lines, ["x", "y"], true), "x\ny");
check("copy mismatched", L.copyText(lines, ["x"], true), "a\nb");

console.log(pass + " passed, " + fail + " failed");
process.exit(fail ? 1 : 0);
