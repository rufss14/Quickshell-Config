// ── steam-scan.js ────────────────────────────────────────────────────────────
// Evaluated INSIDE a Steam window by steam-live.py (Runtime.evaluate, awaitPromise). Walks the
// page's stylesheets and resolves to a JSON string of every declaration that contains a colour
// literal in Steam's cool hues, so steam-accent.py can re-emit it in the palette's colours.
//
// A sheet from another origin refuses `cssRules` — and the THEME's own sheets are exactly that
// (`<link href="https://millennium.host/…/Steam.css">`), so its literals (the green button, the
// filter input's tint) were invisible to a plain walk. Those are fetched and re-parsed as a
// constructed, same-origin sheet, then walked by the same code.
//
//   { sig, rules: [{ w: ["@media …"], s: selector, p: property, v: value, c: [[r,g,b,a,text]] }] }
//
// `v` has each matched colour replaced by \u0001N\u0001 (N indexes `c`); colours outside the cool
// hues stay in the text, so a gradient keeps its other stops. `sig` is the number of top-level
// rules: cheap to recompute, and what tells steam-live.py that Steam's stylesheets changed.
//
// Only a coarse prefilter lives here (cool hue, not a grey) so the answer isn't every colour in
// Steam; which tint becomes the accent and which a neutral is decided in Python, where it can be
// tuned without rescanning. Sheets that are ours (the override itself, Millennium's Quick CSS —
// which carries it too) are skipped, or a rescan would read our own output back — and so is every
// sheet Millennium injects for the theme (see OURS).
(async () => {
    // Sheets that are not Steam's. Ours (the override, Millennium's Quick CSS which carries it) must not be
    // read back, and neither must the colours Millennium injects FOR the theme: `RootColors` is the
    // theme's variables at their values when the window loaded — reading it made an `!important`
    // override of `--color-darker` pinned to a stale palette, which then beat every later push.
    const OURS = new Set(["quicktest-steam", "MillenniumQuickCss", "RootColors", "SystemAccentColorInject"]);
    const skip = ss => ss.ownerNode && (OURS.has(ss.ownerNode.id) || String(ss.ownerNode.id).startsWith("Millennium"));
    const COLOUR = /#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{4}|[0-9a-fA-F]{3})(?![0-9a-zA-Z_-])|rgba?\(\s*[\d.]+\s*[,\s]\s*[\d.]+\s*[,\s]\s*[\d.]+\s*(?:[,/]\s*[\d.]+%?\s*)?\)/g;

    function parse(text) {
        let r, g, b, a = 1;
        if (text[0] === "#") {
            let h = text.slice(1);
            if (h.length <= 4) h = h.split("").map(c => c + c).join("");
            r = parseInt(h.slice(0, 2), 16); g = parseInt(h.slice(2, 4), 16); b = parseInt(h.slice(4, 6), 16);
            if (h.length === 8) a = parseInt(h.slice(6, 8), 16) / 255;
        } else {
            const n = text.match(/[\d.]+%?/g).map(x => x.endsWith("%") ? parseFloat(x) / 100 : parseFloat(x));
            [r, g, b] = n;
            if (n.length > 3) a = n[3];
        }
        return [r, g, b, Math.round(a * 1000) / 1000];
    }

    function cool(r, g, b) {
        const mx = Math.max(r, g, b), mn = Math.min(r, g, b);
        if (mx - mn < 3) return false;                     // a grey (same cut as steam-accent.TINT_MIN_SPREAD)
        const d = mx - mn;
        let h = mx === r ? ((g - b) / d) % 6 : mx === g ? (b - r) / d + 2 : (r - g) / d + 4;
        h = (h * 60 + 360) % 360;
        return h >= 70 && h <= 270;
    }

    const WRAP = { CSSMediaRule: "@media ", CSSSupportsRule: "@supports ", CSSContainerRule: "@container " };
    const rules = [], seen = new Set();
    let sig = 0;

    function walk(list, w) {
        for (const r of list) {
            const kind = r.constructor && r.constructor.name;
            if (kind === "CSSStyleRule") {
                const style = r.style;
                for (const p of style) {
                    const v = style.getPropertyValue(p);
                    if (!v || (v.indexOf("#") < 0 && v.indexOf("rgb") < 0)) continue;
                    const c = [];
                    const nv = v.replace(COLOUR, m => {
                        const col = parse(m);
                        if (!cool(col[0], col[1], col[2])) return m;
                        c.push(col.concat(m));
                        return "\u0001" + (c.length - 1) + "\u0001";
                    });
                    if (!c.length) continue;
                    const key = w.join("|") + "\u0002" + r.selectorText + "\u0002" + p + "\u0002" + nv;
                    if (seen.has(key)) continue;
                    seen.add(key);
                    rules.push({ w: w, s: r.selectorText, p: p, v: nv, c: c });
                }
            } else if (WRAP[kind] && r.cssRules) {
                walk(r.cssRules, w.concat(WRAP[kind] + r.conditionText));
            } else if (kind === "CSSLayerBlockRule" && r.cssRules) {
                walk(r.cssRules, w.concat("@layer " + r.name));
            }
        }
    }

    const refused = [];
    for (const ss of document.styleSheets) {
        if (skip(ss)) continue;
        let list;
        try { list = ss.cssRules; } catch (e) { if (ss.href) refused.push(ss.href); continue; }   // another origin
        sig += list.length;
        walk(list, []);
    }
    for (const href of refused) {
        try {
            const text = await (await fetch(href)).text();
            const own = new CSSStyleSheet();
            own.replaceSync(text);
            sig += own.cssRules.length;
            walk(own.cssRules, []);
        } catch (e) { /* unreachable or unparseable: leave that sheet as it is */ }
    }
    return JSON.stringify({ sig: sig, rules: rules });
})()
