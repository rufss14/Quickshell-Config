// ── test-steam-scan.js ───────────────────────────────────────────────────────
// Tests for scripts/steam-scan.js against a FAKE stylesheet model — no Steam, no browser.
//
//     bun scripts/test-steam-scan.js      (or: node scripts/test-steam-scan.js)
//
// The scanner is an expression meant for Runtime.evaluate, so it is run here with `document`
// supplied. Rule kinds are told apart by constructor name, as the real CSSOM does, so the fakes
// are classes of the same names.
// ─────────────────────────────────────────────────────────────────────────────
import { readFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const here = dirname(fileURLToPath(import.meta.url));
const src = readFileSync(join(here, "steam-scan.js"), "utf8");
const expr = src.slice(src.indexOf("(async () =>"));      // drop the header comment (a `return` before it would ASI)

let passed = 0, failed = 0;
function check(name, ok, detail) { if (ok) passed++; else { failed++; console.log("FAIL:", name, detail ?? ""); } }

class CSSStyleRule { constructor(sel, decls) { this.selectorText = sel; const s = Object.keys(decls); s.getPropertyValue = p => decls[p]; this.style = s; } }
class CSSMediaRule { constructor(cond, rules) { this.conditionText = cond; this.cssRules = rules; } }
class CSSSupportsRule { constructor(cond, rules) { this.conditionText = cond; this.cssRules = rules; } }
class CSSLayerBlockRule { constructor(name, rules) { this.name = name; this.cssRules = rules; } }
class CSSKeyframesRule { constructor() { this.cssRules = [new CSSStyleRule("from", { color: "#1a9fff" })]; } }
const sheet = (rules, id) => ({ cssRules: rules, ownerNode: id ? { id } : null });
class CSSStyleSheetFake { constructor() { this.cssRules = []; } replaceSync(text) { this.cssRules = FETCHED[text] ?? []; } }
let FETCHED = {};             // fetched text → the rules it "parses" to
let fetches = [];
const fetchFake = async href => { fetches.push(href); if (!(href in REMOTE)) throw new Error("unreachable"); return { text: async () => REMOTE[href] }; };
let REMOTE = {};
const scan = async (sheets, remote = {}) => {
    REMOTE = remote; fetches = [];
    FETCHED = Object.fromEntries(Object.entries(remote).map(([h, txt]) => [txt, txt === "THEME" ? [new CSSStyleRule(".green", { "background-color": "#5c7e10" })] : []]));
    return JSON.parse(await new Function("document", "fetch", "CSSStyleSheet", "return " + expr)({ styleSheets: sheets }, fetchFake, CSSStyleSheetFake));
};

// ── what is picked ───────────────────────────────────────────────────────────
await (async () => {
    const r = await scan([sheet([
        new CSSStyleRule(".tab", { "border-bottom-color": "#1a9fff", color: "#c6d4df", "background-color": "#22242a", outline: "none" }),
        new CSSStyleRule(".grey", { color: "#8f8f8f", background: "#ff0000", fill: "#000" }),
        new CSSStyleRule(".mixed", { "background-image": "linear-gradient(to right, #1a9fff, #ff0000 40%, rgba(34, 36, 42, .6))" }),
    ])]);
    const by = p => r.rules.filter(x => x.p === p);
    check("a saturated blue is found", by("border-bottom-color").length === 1 && by("border-bottom-color")[0].c[0][4] === "#1a9fff");
    check("a slate text colour is found", by("color").some(x => x.s === ".tab" && x.c[0][4] === "#c6d4df"));
    check("a navy surface is found", by("background-color").length === 1);
    check("a grey is not", !by("color").some(x => x.s === ".grey"));
    const near = (await scan([sheet([new CSSStyleRule(".near", { "background-color": "#212124", color: "#dfe3e6" }),
                                      new CSSStyleRule(".flat", { color: "#212123" })])])).rules;
    check("a near-grey with a 3+ level tint is found", near.some(x => x.s === ".near" && x.p === "background-color") && near.some(x => x.p === "color" && x.s === ".near"));
    check("a 2-level tint is not", !near.some(x => x.s === ".flat"));
    check("a red is not", !by("background").length);
    check("pure black is not", !by("fill").length);
    const g = by("background-image")[0];
    check("a gradient keeps its other stops and marks only the cool ones",
          g && g.v === "linear-gradient(to right, \u00010\u0001, #ff0000 40%, \u00011\u0001)" && g.c.length === 2, JSON.stringify(g));
    check("rgba() parsed with its alpha", g && g.c[1][0] === 34 && g.c[1][3] === 0.6, JSON.stringify(g && g.c));
    check("a declaration with no colour is skipped", !by("outline").length);
    check("sig counts top-level rules", r.sig === 3, r.sig);
})();

// ── wrappers ─────────────────────────────────────────────────────────────────
await (async () => {
    const inner = new CSSStyleRule(".x", { color: "#1a9fff" });
    const r = await scan([sheet([
        new CSSMediaRule("(min-width: 600px)", [new CSSSupportsRule("(display:grid)", [inner])]),
        new CSSLayerBlockRule("base", [new CSSStyleRule(".y", { color: "#1a9fff" })]),
        new CSSKeyframesRule(),
    ])]);
    const x = r.rules.find(q => q.s === ".x"), y = r.rules.find(q => q.s === ".y");
    check("@media then @supports are kept, outermost first",
          x && JSON.stringify(x.w) === JSON.stringify(["@media (min-width: 600px)", "@supports (display:grid)"]), JSON.stringify(x));
    check("@layer is kept", y && JSON.stringify(y.w) === JSON.stringify(["@layer base"]));
    check("keyframes are not walked", !r.rules.some(q => q.s === "from"));
})();

// ── what is skipped, and what can't be read ──────────────────────────────────
await (async () => {
    const rule = () => new CSSStyleRule(".z", { color: "#1a9fff" });
    check("our own sheet and Millennium's Quick CSS are never scanned",
          (await scan([sheet([rule()], "quicktest-steam"), sheet([rule()], "MillenniumQuickCss")])).rules.length === 0);
    const colours = () => sheet([new CSSStyleRule(":root", { "--color-darker": "#1c292a" })]);
    check("the theme's injected colours (RootColors) and Millennium's other sheets are never scanned",
          (await scan([sheet(colours().cssRules, "RootColors"), sheet(colours().cssRules, "SystemAccentColorInject"),
                sheet(colours().cssRules, "MillenniumSomething")])).rules.length === 0);
    check("…while the same declaration in one of Steam's own sheets is", (await scan([colours()])).rules.length === 1);
    const blocked = href => ({ get cssRules() { throw new Error("SecurityError"); }, ownerNode: null, href });
    check("a cross-origin sheet with no URL is skipped, the rest still scanned", (await scan([blocked(""), sheet([rule()])])).rules.length === 1);
    check("the same declaration in two sheets is reported once", (await scan([sheet([rule()]), sheet([rule()])])).rules.length === 1);

    // the theme's own sheets are another origin: fetched and read as if they were ours
    const T = "https://millennium.host/v1/themes/simply-dark/Steam.css";
    const r = await scan([blocked(T), sheet([rule()])], { [T]: "THEME" });
    check("a refused sheet is fetched and its literals found", fetches.length === 1 && fetches[0] === T
          && r.rules.some(q => q.s === ".green" && q.c[0][4] === "#5c7e10"), JSON.stringify([fetches, r.rules.map(q => q.s)]));
    check("…alongside the readable sheets'", r.rules.some(q => q.s === ".z"));
    check("…and counted in the signature, so a theme update shows", r.sig === 1 + 1, r.sig);
    const down = await scan([blocked(T), sheet([rule()])], {});
    check("an unreachable sheet is left alone, the rest still scanned", down.rules.length === 1 && fetches.length === 1);
})();

console.log(`${passed} passed` + (failed ? `, ${failed} failed` : ""));
process.exit(failed ? 1 : 0);
