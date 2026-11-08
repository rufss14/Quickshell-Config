// ── test-displays.js ──────────────────────────────────────────────────────────
// services/displays.js. `node scripts/test-displays.js` (or bun).
// The monitor JSON is the shape `hyprctl monitors -j` prints on Hyprland 0.56.2 here.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "displays.js"), "utf8").replace(/^\s*\.pragma\s+library\s*$/m, "");
const D = new Function(src + "\nreturn { parseMonitors, parseMode, dedupeModes, logical, snapPosition, normalise, spec, changed, problem, validName };")();

let pass = 0, fail = 0;
function eq(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { pass++; return; }
    fail++; console.log(`FAIL ${name}\n  got:  ${g}\n  want: ${w}`);
}

const LIVE = JSON.stringify([
    { id: 0, name: "DP-2", description: "AOC 24G2", width: 1920, height: 1080, refreshRate: 165.00301, x: 0, y: 0,
      scale: 1, transform: 0, vrr: false, disabled: false,
      availableModes: ["1920x1080@165.00Hz", "1920x1080@144.00Hz", "1920x1080@60.00Hz", "1920x1080@59.94Hz", "1280x720@60.00Hz", "junk"] },
    { id: 1, name: "HDMI-A-1", description: "Dell", width: 1680, height: 1050, refreshRate: 59.954, x: 1920, y: 0,
      scale: 1, transform: 0, vrr: false, disabled: false, availableModes: ["1680x1050@59.95Hz"] },
    { id: 2, name: "bad name; rm -rf", width: 1, height: 1 }
]);
const M = D.parseMonitors(LIVE);

eq("parse: names, bad one dropped", M.map(m => m.name), ["DP-2", "HDMI-A-1"]);
eq("parse: geometry", [M[1].x, M[1].width, M[1].refresh], [1920, 1680, 59.954]);
eq("parse: garbage", [D.parseMonitors("nope"), D.parseMonitors("{}")], [[], []]);
eq("modes: junk dropped, 59.94 folded into 60, biggest first", M[0].modes.map(m => m.label),
   ["1920 × 1080 · 165 Hz", "1920 × 1080 · 144 Hz", "1920 × 1080 · 60 Hz", "1280 × 720 · 60 Hz"]);
eq("modes: the faster of two 60s kept", M[0].modes[2].refresh, 60);
eq("mode: parse", D.parseMode("2560x1440@143.97Hz"), { width: 2560, height: 1440, refresh: 143.97, label: "2560 × 1440 · 144 Hz" });
eq("mode: reject", [D.parseMode("2560x1440"), D.parseMode("2560x1440@60Hz;x")], [null, null]);

eq("logical: scale 2 halves", D.logical({ width: 2560, height: 1440, scale: 2, transform: 0 }), { w: 1280, h: 720 });
eq("logical: a quarter turn swaps", D.logical({ width: 1920, height: 1080, scale: 1, transform: 1 }), { w: 1080, h: 1920 });
eq("logical: flipped (4) does not swap", D.logical({ width: 1920, height: 1080, scale: 1, transform: 4 }), { w: 1920, h: 1080 });

// Drag the Dell around the AOC (1920×1080 at 0,0). The Dell is 1680×1050.
eq("snap: dropped to the right, near the top → flush right, top-aligned",
   D.snapPosition(M, "HDMI-A-1", 1950, 20, 48), { x: 1920, y: 0 });
eq("snap: dropped to the left → flush left",
   D.snapPosition(M, "HDMI-A-1", -1700, 10, 48), { x: -1680, y: 0 });
eq("snap: dropped below, near the left edge → under it, left-aligned",
   D.snapPosition(M, "HDMI-A-1", 30, 1100, 48), { x: 0, y: 1080 });
eq("snap: never overlaps — dropped on top of the AOC goes beside or below",
   (p => !(p.x < 1920 && p.x + 1680 > 0 && p.y < 1080 && p.y + 1050 > 0))(D.snapPosition(M, "HDMI-A-1", 100, 100, 48)), true);
eq("snap: top beats bottom when both are in reach",
   D.snapPosition(M, "HDMI-A-1", 1920, 40, 48), { x: 1920, y: 0 });
eq("snap: bottom-aligned when only the bottom is in reach",
   D.snapPosition(M, "HDMI-A-1", 1925, 70, 48), { x: 1920, y: 30 });
eq("snap: free along the side when nothing is in reach",
   D.snapPosition(M, "HDMI-A-1", 1925, 400, 48), { x: 1920, y: 400 });
eq("snap: alone on the layout → origin", D.snapPosition([M[0]], "DP-2", 500, 500, 48), { x: 0, y: 0 });

eq("normalise: shifts to 0,0", D.normalise([{ name: "a", x: -1680, y: 0, disabled: false }, { name: "b", x: 0, y: 0, disabled: false }]).map(m => [m.x, m.y]),
   [[0, 0], [1680, 0]]);
eq("spec: only what's written", D.spec(M)[0], { name: "DP-2", width: 1920, height: 1080, refresh: 165.00301, x: 0, y: 0, scale: 1, transform: 0, vrr: false });
eq("spec: disabled", D.spec([{ ...M[0], disabled: true }, M[1]])[0], { name: "DP-2", disabled: true });
eq("changed: same", D.changed(M, M.map(m => ({ ...m }))), false);
eq("changed: moved", D.changed(M, [M[0], { ...M[1], y: 30 }]), true);
eq("changed: a shift of the whole layout is not a change", D.changed(M, M.map(m => ({ ...m, x: m.x - 100 }))), false);
eq("problem: all off", D.problem(M.map(m => ({ ...m, disabled: true }))) !== "", true);
eq("problem: fine", D.problem(M), "");

console.log(`${pass} passed, ${fail} failed`);
if (fail) process.exit(1);
