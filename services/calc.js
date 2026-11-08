.pragma library

// ── calc.js ───────────────────────────────────────────────────────────────────
// The launcher's calculator: arithmetic and unit conversion typed into the search
// field.
//
// ── Why a parser and not eval() ───────────────────────────────────────────────
// `eval()` on the launcher's search box would hand arbitrary JavaScript, running with
// the shell's own privileges, to anything that can put text in that field — and the
// field is one keybind away at all times. It would also be WRONG rather than merely
// unsafe: `Files` is a valid JS expression (it's just an identifier), so evaluating
// every query would throw for most app searches and quietly succeed for some.
//
// This is a tokeniser and a recursive-descent parser over a fixed grammar. Anything
// outside it doesn't parse, and not parsing is the normal case — most queries are app
// names.
//
// ── It is a .js file so it can be tested ──────────────────────────────────────
// Same reason services/palette.js is: `node -e` can exercise this directly, which a
// QML expression buried in a panel cannot be. `.pragma library` means one shared
// instance with no QML engine bindings — it is pure functions and holds no state.
// ─────────────────────────────────────────────────────────────────────────────

// ── Tokeniser ─────────────────────────────────────────────────────────────────
function _tokenise(src) {
    const out = []
    let i = 0
    while (i < src.length) {
        const c = src[i]

        if (c === " " || c === "\t") { i++; continue }

        if (/[0-9.]/.test(c)) {
            let j = i
            while (j < src.length && /[0-9.]/.test(src[j])) j++
            const text = src.slice(i, j)
            // "1.2.3" tokenises as one run of digits-and-dots; Number() gives NaN and
            // the parse fails, which is what should happen.
            const v = Number(text)
            if (isNaN(v)) return null
            out.push({ t: "num", v: v })
            i = j
            continue
        }

        if (/[a-zA-Z_]/.test(c)) {
            let j = i
            while (j < src.length && /[a-zA-Z_0-9]/.test(src[j])) j++
            out.push({ t: "word", v: src.slice(i, j).toLowerCase() })
            i = j
            continue
        }

        if ("+-*/%^()".indexOf(c) >= 0) { out.push({ t: "op", v: c }); i++; continue }

        // Convenience aliases for the characters people actually type on a keyboard
        // that has them.
        if (c === "×") { out.push({ t: "op", v: "*" }); i++; continue }
        if (c === "÷") { out.push({ t: "op", v: "/" }); i++; continue }

        return null    // anything else is not an expression
    }
    return out
}

// ── Grammar ───────────────────────────────────────────────────────────────────
//   expr   := term (('+' | '-') term)*
//   term   := unary (('*' | '/' | '%') unary)*
//   unary  := ('-' | '+') unary | power
//   power  := atom ('^' unary)?          right-associative, binds tighter than unary
//   atom   := number | constant | func '(' expr ')' | '(' expr ')'

const _CONSTS = { pi: Math.PI, e: Math.E, tau: Math.PI * 2 }

const _FUNCS = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs,
    sin: Math.sin, cos: Math.cos, tan: Math.tan,
    asin: Math.asin, acos: Math.acos, atan: Math.atan,
    ln: Math.log, log: function (x) { return Math.log(x) / Math.LN10 },
    log2: Math.log2, exp: Math.exp,
    floor: Math.floor, ceil: Math.ceil, round: Math.round,
    sign: Math.sign
}

function _parse(toks) {
    let p = 0
    const peek = () => (p < toks.length ? toks[p] : null)
    const isOp = (v) => { const t = peek(); return t && t.t === "op" && t.v === v }

    function expr() {
        let left = term()
        if (left === null) return null
        for (;;) {
            if (isOp("+"))      { p++; const r = term(); if (r === null) return null; left += r }
            else if (isOp("-")) { p++; const r = term(); if (r === null) return null; left -= r }
            else return left
        }
    }

    function term() {
        let left = unary()
        if (left === null) return null
        for (;;) {
            if (isOp("*"))      { p++; const r = unary(); if (r === null) return null; left *= r }
            else if (isOp("/")) { p++; const r = unary(); if (r === null) return null; left /= r }
            else if (isOp("%")) { p++; const r = unary(); if (r === null) return null; left %= r }
            else return left
        }
    }

    function unary() {
        if (isOp("-")) { p++; const v = unary(); return v === null ? null : -v }
        if (isOp("+")) { p++; return unary() }
        return power()
    }

    function power() {
        const base = atom()
        if (base === null) return null
        if (isOp("^")) {
            p++
            // Right-associative, and the exponent goes through unary() so `2^-1`
            // parses. `2^3^2` is 2^(3^2) = 512, which is the mathematical reading.
            const ex = unary()
            return ex === null ? null : Math.pow(base, ex)
        }
        return base
    }

    function atom() {
        const t = peek()
        if (t === null) return null

        if (t.t === "num") { p++; return t.v }

        if (t.t === "word") {
            if (_CONSTS[t.v] !== undefined) { p++; return _CONSTS[t.v] }
            if (_FUNCS[t.v] !== undefined) {
                const fn = _FUNCS[t.v]
                p++
                if (!isOp("(")) return null
                p++
                const arg = expr()
                if (arg === null || !isOp(")")) return null
                p++
                return fn(arg)
            }
            return null    // an unknown word — an app name, most likely
        }

        if (isOp("(")) {
            p++
            const v = expr()
            if (v === null || !isOp(")")) return null
            p++
            return v
        }
        return null
    }

    const v = expr()
    // Trailing tokens mean it only PARTLY parsed ("firefox 2" must not become 2).
    if (v === null || p !== toks.length) return null
    return v
}

// ── Units ─────────────────────────────────────────────────────────────────────
// Everything linear is expressed as a factor to one base unit per dimension, so a
// conversion is (value × from) ÷ to. Temperature is not linear-through-zero and is
// handled separately below.
const _UNITS = {
    // length → metres
    mm: ["len", 0.001], cm: ["len", 0.01], m: ["len", 1], km: ["len", 1000],
    in: ["len", 0.0254], inch: ["len", 0.0254], inches: ["len", 0.0254],
    ft: ["len", 0.3048], foot: ["len", 0.3048], feet: ["len", 0.3048],
    yd: ["len", 0.9144], mi: ["len", 1609.344], mile: ["len", 1609.344],
    miles: ["len", 1609.344],

    // mass → grams
    mg: ["mass", 0.001], g: ["mass", 1], kg: ["mass", 1000],
    oz: ["mass", 28.349523125], lb: ["mass", 453.59237], lbs: ["mass", 453.59237],
    st: ["mass", 6350.29318], t: ["mass", 1000000],

    // data → bytes. Decimal (kb = 1000) and binary (kib = 1024) are distinct, because
    // conflating them is the entire reason anyone looks this up.
    b: ["data", 1],
    kb: ["data", 1e3], mb: ["data", 1e6], gb: ["data", 1e9], tb: ["data", 1e12],
    kib: ["data", 1024], mib: ["data", 1048576], gib: ["data", 1073741824],
    tib: ["data", 1099511627776],

    // time → seconds
    ms: ["time", 0.001], s: ["time", 1], sec: ["time", 1], secs: ["time", 1],
    min: ["time", 60], mins: ["time", 60], h: ["time", 3600], hr: ["time", 3600],
    hrs: ["time", 3600], day: ["time", 86400], days: ["time", 86400],
    week: ["time", 604800], weeks: ["time", 604800],

    // speed → metres/second
    kmh: ["speed", 1 / 3.6], mph: ["speed", 0.44704], kts: ["speed", 0.514444],

    // angle → degrees
    deg: ["angle", 1], rad: ["angle", 180 / Math.PI]
}

const _TEMPS = { c: 1, celsius: 1, f: 1, fahrenheit: 1, k: 1, kelvin: 1 }

function _toCelsius(v, u) {
    if (u === "f" || u === "fahrenheit") return (v - 32) * 5 / 9
    if (u === "k" || u === "kelvin")     return v - 273.15
    return v
}
function _fromCelsius(v, u) {
    if (u === "f" || u === "fahrenheit") return v * 9 / 5 + 32
    if (u === "k" || u === "kelvin")     return v + 273.15
    return v
}

// ── Formatting ────────────────────────────────────────────────────────────────
// Trims float noise (0.1 + 0.2 must not read as 0.30000000000000004) without
// pretending to a precision the number hasn't got.
function _format(v) {
    if (!isFinite(v)) return v > 0 ? "∞" : (v < 0 ? "-∞" : "undefined")
    if (Number.isInteger(v) && Math.abs(v) < 1e15) return String(v)

    const a = Math.abs(v)
    // Very large or very small numbers are unreadable in full, so they go exponential
    // rather than becoming a wall of zeroes.
    if (a >= 1e12 || (a > 0 && a < 1e-6)) return v.toExponential(6).replace(/e([+-])/, "e$1")

    let s = v.toPrecision(12)
    if (s.indexOf(".") >= 0) s = s.replace(/0+$/, "").replace(/\.$/, "")
    return s
}

// ── The entry point ───────────────────────────────────────────────────────────
// Returns null when the text is not an expression — which is the common case, and is
// NOT an error. Otherwise { value, display, detail }.
//
// A bare number returns null too: typing "5" into a launcher is not a sum you want
// answered, and showing "5 = 5" above the app list is noise.
function evaluate(text) {
    const src = String(text || "").trim()
    if (src === "") return null

    // ── Unit conversion: "<expr> <unit> to <unit>" ────────────────────────────
    // Split on the LAST " to " / " in " so the left side can itself be arithmetic
    // ("2*3 km to mi").
    const conv = src.match(/^(.+?)\s*([a-zA-Z°]+)\s+(?:to|in|as)\s+([a-zA-Z°]+)\s*$/)
    if (conv) {
        const amount = _evalExpr(conv[1])
        if (amount !== null) {
            const from = conv[2].toLowerCase().replace("°", "")
            const to   = conv[3].toLowerCase().replace("°", "")

            if (_TEMPS[from] !== undefined && _TEMPS[to] !== undefined) {
                const out = _fromCelsius(_toCelsius(amount, from), to)
                return { value: out,
                         display: _format(out) + "°" + to.charAt(0).toUpperCase(),
                         detail: _format(amount) + "°" + from.charAt(0).toUpperCase()
                                 + " converted" }
            }

            const f = _UNITS[from], t = _UNITS[to]
            // Same dimension only: "10 km to kg" is a typo, not a question, and
            // answering it with a number would be worse than not answering.
            if (f && t && f[0] === t[0]) {
                const out = amount * f[1] / t[1]
                return { value: out,
                         display: _format(out) + " " + to,
                         detail: _format(amount) + " " + from + " converted" }
            }
        }
        return null
    }

    const v = _evalExpr(src)
    if (v === null) return null

    // A bare number is not a calculation. Requiring an operator, a function or a
    // constant is what keeps the result row from appearing for "5" or for a version
    // number someone pasted.
    if (!/[+\-*/%^()]|[a-zA-Z]/.test(src)) return null

    return { value: v, display: _format(v), detail: src }
}

function _evalExpr(src) {
    // Thousands separators come off HERE, before tokenising, and only between digits.
    // Skipping them inside the tokeniser (the first attempt) split "1,234" into two
    // adjacent number tokens, which then failed to parse as trailing input — so a
    // pasted spreadsheet figure silently stopped being a calculation at all.
    const toks = _tokenise(String(src).replace(/(\d),(?=\d)/g, "$1"))
    if (toks === null || toks.length === 0) return null
    let v = null
    try { v = _parse(toks) } catch (e) { return null }
    if (v === null || typeof v !== "number" || isNaN(v)) return null
    return v
}
