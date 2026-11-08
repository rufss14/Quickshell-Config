.pragma library

// ── inactivity.js ─────────────────────────────────────────────────────────────
// The rules behind the Inactivity panel: "after N minutes without input, do X".
// Everything that can be decided without Wayland, Hyprland or a Process lives here, so
// `bun scripts/test-inactivity.js` can exercise it — the service (Inactivity.qml) only
// watches the idle clock and carries the verdict out.
//
// ── A rule ────────────────────────────────────────────────────────────────────
//   { id, enabled, minutes, action, command }
// `action` is one of ACTIONS' keys. `command` is the user's own text for the "command"
// action — kept as typed (it is what the field shows) and turned into an argv by
// parseCommand() only when the rule fires. Never handed to a shell.
//
// ── Why minutes, and why a floor ──────────────────────────────────────────────
// A sub-minute idle timeout is indistinguishable from a broken machine (Lock.qml's
// autolock clamps the same way), and a stored timeout that is NaN or negative would
// make an IdleMonitor report idle at once — i.e. lock, or power off, the moment the
// shell loads. So a bad number is clamped, never trusted: this is the trust boundary
// between config.json (a hand-editable file) and the thing that suspends the machine.
// ─────────────────────────────────────────────────────────────────────────────

var MIN_MINUTES = 1
var MAX_MINUTES = 720
var MAX_RULES = 8

// A destructive action doesn't fire at its timeout: the monitor trips WARN_SECONDS early,
// a notification says so, and any input in that window cancels it. The rule's minutes
// stay the time you are idle for, warning included.
var WARN_SECONDS = 30

// The things a rule can do. `symbol` is a Material Symbols name (all already in the
// bundled font); `destructive` actions are the ones that can lose unsaved work — they
// warn first (see warns()).
var ACTIONS = {
    lock:      { label: "Lock",        symbol: "lock",           destructive: false },
    screenoff: { label: "Screen off",  symbol: "monitor", destructive: false },
    suspend:   { label: "Suspend",     symbol: "bedtime",        destructive: false },
    hibernate: { label: "Hibernate",   symbol: "nights_stay",    destructive: false },
    logout:    { label: "Log out",     symbol: "logout",         destructive: true  },
    poweroff:  { label: "Power off",   symbol: "power_settings_new", destructive: true },
    command:   { label: "Run command", symbol: "terminal",       destructive: false }
}

// Panel order: the gentle ones first.
var ACTION_ORDER = ["lock", "screenoff", "suspend", "hibernate", "logout", "poweroff", "command"]

function warns(action) { return isAction(action) && ACTIONS[action].destructive }

// What the IdleMonitor is told: the rule's timeout, less the warning window for an
// action that warns. MIN_MINUTES (60 s) keeps it positive.
function monitorSeconds(rule) {
    return rule.minutes * 60 - (warns(rule.action) ? WARN_SECONDS : 0)
}

function warningTitle(rule) {
    return (rule.action === "logout" ? "Logging out" : "Powering off") + " in " + WARN_SECONDS + " s"
}

function isAction(a) { return Object.prototype.hasOwnProperty.call(ACTIONS, a) }

function clampMinutes(m) {
    const n = Math.round(Number(m))
    if (!isFinite(n)) return MIN_MINUTES
    return Math.max(MIN_MINUTES, Math.min(MAX_MINUTES, n))
}

// A fresh id for a new rule: one the list doesn't use yet.
function nextId(rules) {
    let n = 1
    const used = new Set(rules.map(r => r.id))
    while (used.has("r" + n)) n++
    return "r" + n
}

// One rule, made safe — or null when it is not a rule at all. An unknown action is
// dropped rather than defaulted: silently turning a typo into "Lock" (or worse) is
// the wrong direction to fail.
function normalizeRule(r) {
    if (!r || typeof r !== "object" || !isAction(r.action)) return null
    return {
        id:      typeof r.id === "string" && r.id !== "" ? r.id : "",
        enabled: r.enabled !== false,
        minutes: clampMinutes(r.minutes),
        action:  r.action,
        command: typeof r.command === "string" ? r.command : ""
    }
}

// The whole list, made safe: junk dropped, ids made unique, capped, and ordered by
// timeout (stable) so the panel reads as a timeline.
function normalizeRules(list) {
    if (!Array.isArray(list)) return []
    const out = []
    for (const raw of list) {
        const r = normalizeRule(raw)
        if (!r) continue
        if (r.id === "" || out.some(o => o.id === r.id)) r.id = nextId(out)
        out.push(r)
        if (out.length >= MAX_RULES) break
    }
    return out
        .map((r, i) => ({ r, i }))
        .sort((a, b) => a.r.minutes - b.r.minutes || a.i - b.i)
        .map(x => x.r)
}

// A new rule for the "Add" button: the next sensible step after what's there — later
// than every existing rule, gentler action first.
function newRule(rules) {
    const last = rules.reduce((m, r) => Math.max(m, r.minutes), 0)
    const used = new Set(rules.map(r => r.action))
    const action = ACTION_ORDER.find(a => a !== "command" && !used.has(a)) || "lock"
    return { id: nextId(rules), enabled: true, minutes: clampMinutes(last === 0 ? 10 : last + 10),
             action, command: "" }
}

// ── The old setting ───────────────────────────────────────────────────────────
// Before this panel, Lock › auto-lock was `lockIdleEnabled` + `lockIdleMinutes`. It
// becomes a "Lock" rule exactly once; the caller decides "once" (Config.inactivityMigrated).
// Off stays off: the rule is created disabled, so nothing starts locking by upgrading.
function fromLegacyLock(enabled, minutes) {
    return [{ id: "r1", enabled: !!enabled, minutes: clampMinutes(minutes), action: "lock", command: "" }]
}

// ── Custom command → argv ─────────────────────────────────────────────────────
// Whitespace-separated words, with "double" and 'single' quotes to keep spaces in one
// word and a backslash to escape the next character outside single quotes. That is
// all: no variables, no globbing, no pipes — an argv, because a rule fires unattended
// and "what exactly runs" must be readable off the field. Returns null for an empty
// command or an unterminated quote (the rule then does nothing, and says so).
function parseCommand(text) {
    const s = String(text ?? "")
    const argv = []
    let cur = "", has = false, quote = ""
    for (let i = 0; i < s.length; i++) {
        const c = s[i]
        if (quote === "'") {
            if (c === "'") quote = ""; else cur += c
        } else if (quote === '"') {
            if (c === '"') quote = ""
            else if (c === "\\" && i + 1 < s.length) cur += s[++i]
            else cur += c
        } else if (c === "'" || c === '"') {
            quote = c; has = true
        } else if (c === "\\" && i + 1 < s.length) {
            cur += s[++i]; has = true
        } else if (/\s/.test(c)) {
            if (has) { argv.push(cur); cur = ""; has = false }
        } else {
            cur += c; has = true
        }
    }
    if (quote !== "") return null
    if (has) argv.push(cur)
    return argv.length > 0 ? argv : null
}

// ── Words for the panel and the IPC ───────────────────────────────────────────
function duration(minutes) {
    const h = Math.floor(minutes / 60), m = minutes % 60
    if (h === 0) return m + " min"
    return m === 0 ? h + " h" : h + " h " + m + " min"
}

function actionLabel(rule) {
    if (rule.action === "command") {
        const argv = parseCommand(rule.command)
        return argv ? argv[0] : "Run command"
    }
    return ACTIONS[rule.action].label
}

function describe(rule) {
    return actionLabel(rule) + " after " + duration(rule.minutes)
}
