// ── test-palette-contrast.js ──────────────────────────────────────────────────
// Tests services/palette.js's contrast()/legible() — the floor that keeps the
// shell's accent roles visible on a hue-ordered pywal ramp.
//
//     bun scripts/test-palette-contrast.js     (or: node ...)
//
// Safe to run: pure functions, no files touched beyond reading palette.js.
//
// ── Why this needs a test ─────────────────────────────────────────────────────
// The failure it prevents is invisible in code review and only shows up on SOME
// wallpapers: `Colors.primary` is pywal's color1, the ramp is ordered by hue, and
// on one real palette color1 landed at contrast 2.52 against the background — the
// lowest of all sixteen. Every active state in the shell rendered in the least
// visible colour available. A regression here would not throw; it would just make
// the bar quietly hard to read again, on one wallpaper, weeks later.
//
// The two properties that matter are opposites, so both are pinned: a palette
// that is ALREADY legible must come back byte-identical (or every theme gets
// silently washed out), and one that is not must clear the bar.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "..", "services", "palette.js"), "utf8")
    .replace(/^\s*\.pragma\s+library\s*$/m, "");
const { contrast, legible, luminance } = new Function(
    src + "\nreturn { contrast, legible, luminance };")();

let pass = 0, fail = 0;
function ok(name, cond, detail) {
    if (cond) pass++;
    else { fail++; console.log(`  FAIL  ${name}${detail ? "\n          " + detail : ""}`); }
}
const near = (a, b, eps = 0.02) => Math.abs(a - b) < eps;

// ── contrast ──────────────────────────────────────────────────────────────────
ok("black/white is 21:1", near(contrast("#000000", "#ffffff"), 21, 0.1));
ok("a colour against itself is 1:1", near(contrast("#6B4F53", "#6B4F53"), 1));
ok("contrast is symmetric",
   near(contrast("#200d1d", "#CA9C6D"), contrast("#CA9C6D", "#200d1d")));

// The measured case that started all this.
ok("pywal color1 on that background really is ~2.52",
   near(contrast("#6B4F53", "#200d1d"), 2.52, 0.05),
   `got ${contrast("#6B4F53", "#200d1d").toFixed(2)}`);

// ── legible: leaves good palettes alone ───────────────────────────────────────
// The important half. Lifting a palette that did not need it would wash out every
// theme in the shell to chase a problem it does not have.
const tokyo = ["#f7768e", "#7aa2f7", "#e0af68", "#9ece6a", "#bb9af7"];
for (const c of tokyo) {
    ok(`tokyonight ${c} is untouched`,
       legible(c, "#15161e", 4.5, "#a9b1d6") === c);
}
ok("a colour exactly at target is untouched", (() => {
    const c = "#AD7885";                       // measured 5.10 on this bg
    return legible(c, "#200d1d", 4.5, "#c7c2c6") === c;
})());

// ── legible: lifts what needs lifting ─────────────────────────────────────────
const bg = "#200d1d", fg = "#c7c2c6";
for (const c of ["#6B4F53", "#B24B3D", "#956466"]) {
    const out = legible(c, bg, 4.5, fg);
    ok(`${c} is lifted past the floor`, contrast(out, bg) >= 4.5,
       `got ${contrast(out, bg).toFixed(2)}`);
    ok(`${c} is lifted MINIMALLY (not overshot)`, contrast(out, bg) < 4.5 + 0.25,
       `got ${contrast(out, bg).toFixed(2)} — bisection should stop at the bar`);
    ok(`${c} actually changed`, out !== c);
    ok(`${c} got lighter, not darker`, luminance(out) > luminance(c));
}

// Hue is preserved by walking toward the foreground rather than to white: the
// lifted colour must not be closer to grey than the destination is.
ok("hue is preserved (does not race to white)", (() => {
    const out = legible("#6B4F53", bg, 4.5, fg);
    const [r, g, b] = [1, 3, 5].map(i => parseInt(out.substr(i, 2), 16));
    return r > b && r > g;      // #6B4F53 is warm; the lift must stay warm
})());

// ── Degenerate inputs must return a colour, never NaN ─────────────────────────
// A NaN channel becomes "#NaN…" and every surface painted with it goes black,
// which is the one outcome worse than low contrast.
const weird = [
    ["black on black", legible("#000000", "#000000", 4.5, "#ffffff")],
    ["destination too dark", legible("#111111", "#000000", 4.5, "#222222")],
    ["empty input", legible("", "#000000", 4.5, "#ffffff")],
    ["8-digit QML colour", legible("#ff6B4F53", bg, 4.5, fg)],
];
for (const [name, out] of weird) {
    ok(`${name} returns a valid hex`, /^#[0-9a-f]{6}$/i.test(out), `got ${out}`);
}

// QML stringifies a translucent colour as #aarrggbb; parsing it as rgb would
// silently yield a different colour. The alpha is dropped, not misread.
ok("#aarrggbb parses as its rgb half",
   legible("#ff6B4F53", bg, 4.5, fg) === legible("#6B4F53", bg, 4.5, fg));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
