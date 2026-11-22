.pragma library

// ── schemes.js ────────────────────────────────────────────────────────────────
// The classic colour schemes the shell ships (Settings › Appearance › Colour schemes):
// Catppuccin, Gruvbox, Dracula, Nord, Tokyo Night, Rosé Pine, Solarized. Pure data and one
// builder, no QML, so `bun scripts/test-schemes.js` can check every palette.
//
// ── Authored as nine colours, built into the shell's sixteen ─────────────────
// A variant is { bg, fg, muted, a, b, green, yellow, magenta, cyan }. The shell reads its
// palette by SLOT, not by name (config/PaletteRoles.qml): color1 is `primary` AND `danger`,
// color4 is `focus`, color7 is the text, color2/3 are success/warning. A terminal port of a
// scheme puts its red in color1, which here would paint the whole shell red. So `a` (the
// scheme's signature accent) goes in color1 and `b` (its second accent) in color4, exactly
// where a wallpaper's palette puts its two dominant colours. The terminal wears them too,
// like it does under any wallpaper; its red is the cost.
// The bright half (9-14) is each colour lifted toward the text, which is what palette.js
// derive() does toward white; that works in a light scheme too, where it deepens the colour.
//
// A scheme with no `light` (or no `dark`) variant is simply that one: ColorScheme.wear() sets
// the shell's mode to match what it is wearing.
// ─────────────────────────────────────────────────────────────────────────────

var CLASSICS = [
    { id: "catppuccin", name: "Catppuccin",
      note: "Mocha and Latte",
      dark:  { bg: "#1e1e2e", fg: "#cdd6f4", muted: "#6c7086", a: "#cba6f7", b: "#89b4fa",
               green: "#a6e3a1", yellow: "#f9e2af", magenta: "#f5c2e7", cyan: "#94e2d5" },
      light: { bg: "#eff1f5", fg: "#4c4f69", muted: "#8c8fa1", a: "#8839ef", b: "#1e66f5",
               green: "#40a02b", yellow: "#df8e1d", magenta: "#ea76cb", cyan: "#179299" } },

    { id: "gruvbox", name: "Gruvbox",
      note: "Warm and retro",
      dark:  { bg: "#282828", fg: "#ebdbb2", muted: "#928374", a: "#fe8019", b: "#83a598",
               green: "#b8bb26", yellow: "#fabd2f", magenta: "#d3869b", cyan: "#8ec07c" },
      light: { bg: "#fbf1c7", fg: "#3c3836", muted: "#7c6f64", a: "#af3a03", b: "#076678",
               green: "#79740e", yellow: "#b57614", magenta: "#8f3f71", cyan: "#427b58" } },

    { id: "dracula", name: "Dracula",
      note: "Dracula and Alucard",
      dark:  { bg: "#282a36", fg: "#f8f8f2", muted: "#6272a4", a: "#bd93f9", b: "#8be9fd",
               green: "#50fa7b", yellow: "#f1fa8c", magenta: "#ff79c6", cyan: "#a4ffff" },
      light: { bg: "#fffbeb", fg: "#1f1f1f", muted: "#6c664b", a: "#644ac9", b: "#036a96",
               green: "#14710a", yellow: "#846e15", magenta: "#a3144d", cyan: "#036a96" } },

    { id: "nord", name: "Nord",
      note: "Cold and calm",
      dark:  { bg: "#2e3440", fg: "#d8dee9", muted: "#616e88", a: "#88c0d0", b: "#81a1c1",
               green: "#a3be8c", yellow: "#ebcb8b", magenta: "#b48ead", cyan: "#8fbcbb" } },

    { id: "tokyonight", name: "Tokyo Night",
      note: "Night and Day",
      dark:  { bg: "#1a1b26", fg: "#c0caf5", muted: "#565f89", a: "#7aa2f7", b: "#7dcfff",
               green: "#9ece6a", yellow: "#e0af68", magenta: "#bb9af7", cyan: "#73daca" },
      light: { bg: "#e1e2e7", fg: "#3760bf", muted: "#6172b0", a: "#2e7de9", b: "#007197",
               green: "#587539", yellow: "#8c6c3e", magenta: "#9854f1", cyan: "#118c74" } },

    { id: "rosepine", name: "Rosé Pine",
      note: "Rosé Pine and Dawn",
      dark:  { bg: "#191724", fg: "#e0def4", muted: "#6e6a86", a: "#c4a7e7", b: "#ebbcba",
               green: "#31748f", yellow: "#f6c177", magenta: "#eb6f92", cyan: "#9ccfd8" },
      light: { bg: "#faf4ed", fg: "#575279", muted: "#9893a5", a: "#907aa9", b: "#56949f",
               green: "#286983", yellow: "#ea9d34", magenta: "#b4637a", cyan: "#d7827e" } },

    { id: "solarized", name: "Solarized",
      note: "Dark and Light",
      dark:  { bg: "#002b36", fg: "#93a1a1", muted: "#586e75", a: "#268bd2", b: "#6c71c4",
               green: "#859900", yellow: "#b58900", magenta: "#d33682", cyan: "#2aa198" },
      light: { bg: "#fdf6e3", fg: "#586e75", muted: "#93a1a1", a: "#268bd2", b: "#6c71c4",
               green: "#859900", yellow: "#b58900", magenta: "#d33682", cyan: "#2aa198" } }
]

function _rgb(hex) {
    const h = String(hex).replace("#", "")
    return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)]
}
function _hex(c) {
    return "#" + c.map(function (v) {
        return Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")
    }).join("")
}
// `from` moved `t` of the way to `to`.
function _lift(from, to, t) {
    const a = _rgb(from), b = _rgb(to)
    return _hex([a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t])
}

// One variant → the pywal shape every other part of the shell reads
// ({ special: { background, foreground, cursor }, colors: { color0 … color15 } }).
function build(v) {
    const six = [v.a, v.green, v.yellow, v.b, v.magenta, v.cyan]
    const colors = { color0: v.bg, color7: v.fg, color8: v.muted, color15: v.fg }
    for (let i = 0; i < 6; i++) {
        colors["color" + (i + 1)] = six[i]
        colors["color" + (i + 9)] = _lift(six[i], v.fg, 0.18)
    }
    return { special: { background: v.bg, foreground: v.fg, cursor: v.fg }, colors: colors }
}

// → [{ id, name, note, builtin: true, variants: { dark, light } }], each variant a built palette or null.
// The same `variants` shape ColorScheme.presets carry, so palette.js reads both alike.
function list() {
    return CLASSICS.map(function (s) {
        return { id: s.id, name: s.name, note: s.note, builtin: true,
                 variants: { dark: s.dark ? build(s.dark) : null, light: s.light ? build(s.light) : null } }
    })
}
