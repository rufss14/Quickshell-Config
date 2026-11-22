.pragma library

// ── streammode.js ─────────────────────────────────────────────────────────────
// The Lua StreamMode sends to Hyprland, and how it reads the answer. Logic, not
// presentation, so `bun scripts/test-streammode.js` can pin it.
//
// The rules themselves are DEFINED statically in hypr/rules.lua (switched off) and
// kept in _G.qs_stream; this only flips them. Defining a rule at runtime is the thing
// that has crashed Hyprland before (hl.bind via `hyprctl eval`), so it never does.

// ── Which streams are capturing the SCREEN ───────────────────────────────────
// `nodes` is [{ id, p }]: a PipeWire node's id and its properties, as plain data (the
// caller flattens its PwNodes, so this stays testable). Returns the INDEXES of the
// nodes that consume a screen capture, one per app, first seen first.
//
// Measured with pw-dump while Discord shared the screen (2026-11-14): the portal's
// source is `Video/Source` named `xdg-desktop-portal-hyprland` (media.name
// `xdph-streaming-<n>`), and the app's side is `Stream/Input/Video` with
// `media.role: Screen` and `node.target` = the source's id. Either mark counts: an app
// that sets no role is still found by its target, an app whose target is a driver id is
// still found by its role. A webcam is `media.role: Camera` and is never a screen.
// Portal names are matched loosely (xdg-desktop-portal-*, xdph) — not only Hyprland's.
function capturers(nodes) {
    const portal = {}
    for (const n of nodes)
        if (n.p["media.class"] === "Video/Source"
            && /^xdg-desktop-portal|^xdph/i.test(String(n.p["node.name"] || n.p["media.name"] || "")))
            portal[String(n.id)] = true
    const out = [], seen = {}
    nodes.forEach((n, i) => {
        const p = n.p
        if (p["media.class"] !== "Stream/Input/Video" || p["media.role"] === "Camera") return
        if (p["media.role"] !== "Screen" && !portal[String(p["node.target"])]) return
        const key = p["application.process.binary"] || p["application.name"] || p["node.name"] || String(n.id)
        if (seen[key]) return
        seen[key] = true
        out.push(i)
    })
    return out
}

// `on` is coerced to a literal true/false: nothing from outside is ever pasted into Lua.
function lua(on) {
    return [
        'if type(_G.qs_stream) ~= "table" then error("qs_stream missing") end',
        'for _, r in pairs(_G.qs_stream) do r:set_enabled(' + (on === true ? "true" : "false") + ') end'
    ].join("\n")
}

// hyprctl answers "ok" for anything it merely queued, so a failed Lua run is read from
// the text as well as the exit code (same test as KeyLocks).
function failed(code, out) {
    return code !== 0 || /error|expected/i.test(String(out))
}

// What stands in for hidden text: one word, the same for every string, so the length
// of a password or a street name is not a leak too. `word` is the caller's translated
// "Hidden". Empty stays empty, so "is there a place set" tests and "nothing to show"
// layouts behave the same masked or not.
function mask(text, on, word) {
    const t = text === undefined || text === null ? "" : String(text)
    return on === true && t !== "" ? (word || "Hidden") : t
}

// rules: "unknown" (not asked yet) | "ok" | "missing"
// `suspended`: stream mode is paused while a capture runs, so viewers see everything.
function status(on, rules, suspended) {
    if (suspended) return "Paused · visible to viewers"
    if (!on) return "Off"
    if (rules === "missing") return "On · capture hiding not installed"
    return rules === "ok" ? "On · hidden from capture" : "On"
}
