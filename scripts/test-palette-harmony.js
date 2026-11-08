// ── test-palette-harmony.js ───────────────────────────────────────────────────
// Tests services/palette.js's HSL helpers, harmony(), suggestAccents() and contrastGrade() —
// what the colours panel's Shuffle chip and contrast badge stand on.
//
//     bun scripts/test-palette-harmony.js     (or: node ...)
//
// Pure functions, nothing touched but a read of palette.js.
//
// ── Why this needs a test ─────────────────────────────────────────────────────
// Shuffle is random, so a bug in it shows up as "sometimes I get an unreadable accent" — one
// press in fifty, on one background. So the property that matters is checked over many draws on
// BOTH a dark and a light background: every accent clears 3:1, and every result is a real hex.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "palette.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const P = new Function(src + `
return { hexToRgb, rgbToHex, rgbToHsl, hslToRgb, harmony, partner, suggestAccents, contrast, contrastGrade };`)();

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}
const near = (a, b, eps = 1) => Math.abs(a - b) <= eps;
const isHex = v => /^#[0-9a-f]{6}$/.test(v);

// A seeded generator, so a failure here is the same failure next time.
function lcg(seed) { let s = seed >>> 0; return () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296; }

// ── HSL round trip ────────────────────────────────────────────────────────────
for (const hex of ["#ff0000", "#00ff00", "#0000ff", "#6b4f53", "#808080", "#000000", "#ffffff", "#c3a1e8"]) {
    const [h, s, l] = P.rgbToHsl(P.hexToRgb(hex));
    ok(`round trip ${hex}`, P.rgbToHex(P.hslToRgb(h, s, l)) === hex, `got ${P.rgbToHex(P.hslToRgb(h, s, l))}`);
}
ok("red is hue 0", near(P.rgbToHsl([255, 0, 0])[0], 0, 0.01));
ok("green is hue 120", near(P.rgbToHsl([0, 255, 0])[0], 120, 0.01));
ok("blue is hue 240", near(P.rgbToHsl([0, 0, 255])[0], 240, 0.01));

// ── harmony ───────────────────────────────────────────────────────────────────
ok("complementary of red is cyan", P.harmony("#ff0000", "complementary") === "#00ffff");
ok("triad of red is green", P.harmony("#ff0000", "triad") === "#00ff00");
ok("an unknown kind leaves the colour alone", P.harmony("#6b4f53", "nope") === "#6b4f53");
{
    const [, s0, l0] = P.rgbToHsl(P.hexToRgb("#6b4f53"));
    const [, s1, l1] = P.rgbToHsl(P.hexToRgb(P.harmony("#6b4f53", "split")));
    ok("harmony keeps saturation and lightness", near(s0, s1, 0.02) && near(l0, l1, 0.02));
}

// ── suggestAccents: legible on any ground, over many draws ────────────────────
for (const [name, bg, fg] of [["dark", "#101014", "#e6e1e5"], ["light", "#f6f1ec", "#1c1b1f"],
                              ["mid", "#7a7a7a", "#ffffff"], ["black", "#000000", "#ffffff"]]) {
    const rand = lcg(12345);
    let worst = 99, bad = 0;
    for (let i = 0; i < 400; i++) {
        const [a, b] = P.suggestAccents(bg, fg, rand);
        if (!isHex(a) || !isHex(b)) bad++;
        worst = Math.min(worst, P.contrast(a, bg), P.contrast(b, bg));
    }
    ok(`${name}: every suggestion is a hex`, bad === 0, `${bad} bad`);
    // A mid-grey ground cannot always reach 3:1 against white (nothing can); the floor there is
    // whatever the destination itself gives, so only the grounds that CAN are held to 3.
    const reachable = P.contrast(fg, bg) >= 3;
    ok(`${name}: accents clear 3:1`, !reachable || worst >= 2.98, `worst ${worst.toFixed(2)}`);
}
{
    const a = P.suggestAccents("#101014", "#e6e1e5", lcg(7)), b = P.suggestAccents("#101014", "#e6e1e5", lcg(7));
    ok("the same draw gives the same pair", a[0] === b[0] && a[1] === b[1]);
    const c = P.suggestAccents("#101014", "#e6e1e5", lcg(8));
    ok("a different draw gives a different pair", a[0] !== c[0] || a[1] !== c[1]);
}
ok("with no rand it still returns a pair", P.suggestAccents("#101014", "#e6e1e5").every(isHex));

// ── partner: the harmony chips ────────────────────────────────────────────────
for (const [name, bg, fg] of [["dark", "#101014", "#e6e1e5"], ["light", "#f6f1ec", "#1c1b1f"]]) {
    for (const kind of ["analogous", "split", "triad", "complementary"]) {
        let worst = 99;
        const rand = lcg(99);
        for (let i = 0; i < 200; i++) {
            const a = P.rgbToHex(P.hslToRgb(rand() * 360, 0.3 + 0.6 * rand(), 0.2 + 0.6 * rand()));
            const b = P.partner(a, bg, fg, kind);
            if (!isHex(b)) worst = -1;
            worst = Math.min(worst, P.contrast(b, bg));
        }
        ok(`${name}/${kind}: partner clears 3:1`, worst >= 2.98, `worst ${worst.toFixed(2)}`);
    }
}
ok("an accent already legible comes back as the plain harmony",
   P.partner("#c0c0ff", "#101014", "#e6e1e5", "triad") === P.harmony("#c0c0ff", "triad"));
ok("the four kinds give four different partners",
   new Set(["analogous", "split", "triad", "complementary"].map(k => P.partner("#c0a0ff", "#101014", "#e6e1e5", k))).size === 4);

// ── contrastGrade ─────────────────────────────────────────────────────────────
ok("21 is AAA", P.contrastGrade(21) === "AAA");
ok("7 is AAA", P.contrastGrade(7) === "AAA");
ok("6.9 is AA", P.contrastGrade(6.9) === "AA");
ok("4.5 is AA", P.contrastGrade(4.5) === "AA");
ok("3 is Large", P.contrastGrade(3) === "Large");
ok("2.9 is Low", P.contrastGrade(2.9) === "Low");
ok("1 is Low", P.contrastGrade(1) === "Low");

console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
