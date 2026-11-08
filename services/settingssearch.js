.pragma library

// ── settingssearch.js ─────────────────────────────────────────────────────────
// Ranking for the settings search. Pure functions over plain data — no QML, no
// service, no I/O — so `bun scripts/test-settingssearch.js` can pin the behaviour.
//
// This is in a .js for the reason CLAUDE.md gives: a ranking buried in a QML
// expression inside a page cannot be tested, and "the search feels wrong" is
// exactly the kind of complaint that needs cases rather than opinions.
//
// ── What it ranks over ────────────────────────────────────────────────────────
// Two kinds of record, deliberately mixed in one result list:
//
//   page     one per settings page. Carries `keywords`, which is where the terms
//            that should find a page WITHOUT being its name live — including every
//            name the page used to have, so a rename never strands someone who
//            knew the old word ("hyprland" still finds Window manager).
//   section  a card on a page, and
//   row      one setting inside a card. Both come from settings-index.json, which
//            is generated from the page sources by scripts/build-settings-index.py.
//
// A page match and a row match answer different questions ("where do I go" vs
// "where is this one thing"), and which the user meant is not knowable from the
// query — so both are shown, ordered by how well they matched rather than by kind.
// ─────────────────────────────────────────────────────────────────────────────

// Fold to a comparable form. Case and punctuation are noise in a settings query:
// "wi-fi", "WiFi" and "wi fi" are the same intent, and a user typing "nightlight"
// should find "Night light".
function norm(s) {
    return String(s == null ? "" : s)
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, " ")
        .trim();
}

// The same, with spaces removed — so "nightlight" matches "night light" and
// "wifi" matches "wi fi" without needing either spelling in the data.
function squash(s) {
    return norm(s).replace(/ /g, "");
}

// ── Scoring one field ─────────────────────────────────────────────────────────
// Higher is better; 0 means no match. The tiers matter more than the numbers:
// an exact title beats a prefix beats a word-start beats a substring, and a hit
// in the title always beats the same hit in a description.
function scoreField(field, q, qSquashed) {
    const f = norm(field);
    if (!f) return 0;

    if (f === q) return 100;
    if (f.startsWith(q)) return 80;

    // Start of any word: "scale" matching "Text scale". Much stronger than a bare
    // substring, which would also fire on "escalate".
    const words = f.split(" ");
    for (const w of words) {
        if (w === q) return 75;
        if (w.startsWith(q)) return 60;
    }

    if (f.includes(q)) return 35;

    // Space-insensitive fallback, so "nightlight" finds "Night light".
    const fSquashed = f.replace(/ /g, "");
    if (qSquashed.length >= 3 && fSquashed.includes(qSquashed)) return 30;

    return 0;
}

// Every query token has to hit SOMETHING, which is what makes multi-word queries
// narrow rather than widen. "bar radius" should not return every row containing
// "bar" — the AND is the whole point of typing the second word.
//
// `titleOnly` is the one-letter case. A single letter is a substring of nearly
// every record, so a normal search for "s" returned two dozen equal-scored hits in
// alphabetical order — a list that reads as random. One letter is someone starting
// to type a NAME, so it only counts where a word of the title begins.
function scoreEntry(entry, tokens, titleOnly) {
    // Weights, not raw scores: a title hit is worth more than the same hit in a
    // detail line, and keywords sit between (they are deliberate synonyms, so a
    // match is meaningful, but they are not what the thing is called).
    const fields = titleOnly ? [[entry.title, 1.0]] : [
        [entry.title, 1.0],
        [entry.section, 0.55],
        [entry.page, 0.5],
        [entry.keywords, 0.45],
        [entry.detail, 0.35],
    ];

    let total = 0;
    for (const t of tokens) {
        const tSquashed = squash(t);
        let best = 0;
        for (const [value, weight] of fields) {
            if (!value) continue;
            let raw = scoreField(value, t, tSquashed);
            if (titleOnly && raw < 60) raw = 0;     // below word-start tier
            const s = raw * weight;
            if (s > best) best = s;
        }
        // One token matched nothing at all — the entry is not a result.
        if (best === 0) return 0;
        total += best;
    }

    // A row is a more specific answer than the page containing it, so when both
    // match equally the row wins. Sections sit between.
    const kindBonus = entry.kind === "row" ? 6 : entry.kind === "section" ? 3 : 0;
    return total / tokens.length + kindBonus;
}

// ── The entry point ───────────────────────────────────────────────────────────
// `entries` is the merged list of page/section/row records. Returns a new array,
// highest score first, capped at `limit`. Ties break on title so the order is
// stable rather than dependent on the input order — a result list that reshuffles
// between keystrokes is unusable even when the contents are right.
function search(entries, query, limit) {
    const q = norm(query);
    if (!q) return [];

    const tokens = q.split(" ").filter(t => t.length > 0);
    if (tokens.length === 0) return [];

    const titleOnly = q.replace(/ /g, "").length === 1;

    const scored = [];
    for (const e of entries) {
        const s = scoreEntry(e, tokens, titleOnly);
        if (s > 0) scored.push({ entry: e, score: s });
    }

    scored.sort(function (a, b) {
        if (b.score !== a.score) return b.score - a.score;
        return norm(a.entry.title) < norm(b.entry.title) ? -1 : 1;
    });

    const out = [];
    const max = limit == null ? 20 : limit;
    for (let i = 0; i < scored.length && i < max; i++) out.push(scored[i].entry);
    return out;
}

// Merge the page catalogue with the generated index into one flat list, resolving
// each generated entry's `file` to the page's display name and section.
//
// The join is here rather than in the generator on purpose: the page's NAME lives
// in the catalogue, and baking it into the JSON would make a rename require
// regenerating the index — two sources of truth for one string, which is the drift
// the generator exists to prevent.
function buildEntries(pages, indexEntries) {
    const byFile = {};
    const out = [];

    for (const p of pages || []) {
        byFile[p.file] = p;
        out.push({
            kind: "page",
            file: p.file,
            title: p.label,
            detail: p.detail,
            keywords: p.keywords,
            // `page` is the rail page a view belongs to (SettingsIndex); `section`
            // is the older flat catalogue's group, kept so either shape works.
            group: p.page || p.section,
        });
    }

    for (const e of indexEntries || []) {
        const p = byFile[e.file];
        // A generated entry for a page that is not currently available — the Wi-Fi
        // rows on a machine with no adapter — must not be searchable, or the result
        // navigates to a page the rail does not have.
        if (!p) continue;
        out.push({
            kind: e.kind,
            file: e.file,
            title: e.title,
            detail: e.detail,
            section: e.section,
            page: p.label,
            group: p.page || p.section,
        });
    }

    return out;
}

// ── Grouping for display ──────────────────────────────────────────────────────
// Ranked results, folded by the view they live on. A flat list repeated
// "Integrations › Discord" on seven lines in a row; grouped, the page is said once
// and its rows sit under it. Groups keep the order of their BEST result (the input
// is already sorted), rows keep theirs within a group.
//
// A page-kind result doesn't become a row — it marks the group (`pageHit`), since
// "this page matched" is what the group header already is.
function groupResults(results) {
    const groups = [];
    const byFile = {};
    for (const r of results || []) {
        let g = byFile[r.file];
        if (!g) {
            g = {
                file: r.file,
                page: r.kind === "page" ? r.title : r.page,
                group: r.group,
                pageHit: false,
                rows: [],
            };
            byFile[r.file] = g;
            groups.push(g);
        }
        if (r.kind === "page") g.pageHit = true;
        else g.rows.push(r);
    }
    return groups;
}

// ── Which part of a title to highlight ────────────────────────────────────────
// { before, match, after }, splitting `text` around the longest query token found
// in it (case-insensitive). No hit — a keyword or space-insensitive match — gives
// the whole text as `before` and an empty `match`, so the caller draws it plain.
// Returned as parts, never markup: escaping belongs to whoever renders it.
function splitMatch(text, query) {
    const s = String(text == null ? "" : text);
    const lower = s.toLowerCase();
    const tokens = String(query == null ? "" : query).toLowerCase()
        .split(/[^a-z0-9]+/).filter(t => t.length > 0)
        .sort((a, b) => b.length - a.length);
    for (const t of tokens) {
        const i = lower.indexOf(t);
        if (i >= 0)
            return { before: s.slice(0, i), match: s.slice(i, i + t.length), after: s.slice(i + t.length) };
    }
    return { before: s, match: "", after: "" };
}

// Both spellings, so this file works as an ES module under bun (the test) and as
// a QML `.import` (the service), which uses the bare names.
if (typeof module !== "undefined" && module.exports) {
    module.exports = { norm, squash, scoreField, scoreEntry, search, buildEntries,
                       groupResults, splitMatch };
}
