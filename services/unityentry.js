.pragma library

// ── unityentry.js ─────────────────────────────────────────────────────────────
// Reads apps' own launcher state — a badge count, a progress bar, "I need
// attention" — from the com.canonical.Unity.LauncherEntry.Update broadcast that
// Firefox (downloads), Chromium, Telegram, Discord and most KDE apps emit, as
// `dbus-monitor` prints it. That's the one D-Bus listener every system has (the
// shell can't subscribe to an arbitrary signal itself, and dbus-python isn't a
// dependency).
//
// dbus-monitor's text is line-oriented with no terminator, so this is a small
// state machine: a header line opens an Update, then `string "<app uri>"`, then
// an `array [` of `dict entry( string "<key>" variant <type> <value> )`. The
// update is complete when that array's `]` closes — depth-tracked, so an array
// INSIDE a variant (a quicklist, say) can't end it early. Any other header line
// abandons whatever was in progress.
//
// An Update carries only what CHANGED, so apply() merges into the app's state.
// ─────────────────────────────────────────────────────────────────────────────

function _value(type, raw) {
    const v = String(raw).trim()
    if (type === "boolean") return v === "true"
    if (type === "string")  return v.replace(/^"(.*)"$/, "$1")
    if (/^(double|u?int(16|32|64)|byte)$/.test(type)) {
        const n = Number(v)
        return isNaN(n) ? null : n
    }
    return null
}

// "application://firefox.desktop" → "firefox"
function appIdOf(uri) {
    return String(uri || "").replace(/^application:\/\//, "").replace(/\.desktop$/, "")
}

function createParser() {
    let open = false     // inside an Update
    let uri = null
    let depth = 0
    let key = null
    let props = {}

    function reset() { open = false; uri = null; depth = 0; key = null; props = {} }

    return {
        // One line of dbus-monitor output in; a finished { app, props } out, or null.
        feed: function (line) {
            const s = String(line)
            if (/^(signal|method call|method return|error) /.test(s)) {
                reset()
                open = /interface=com\.canonical\.Unity\.LauncherEntry; member=Update\b/.test(s)
                return null
            }
            if (!open) return null

            if (/\barray \[\s*$/.test(s)) {
                // A variant's own array (depth > 1) swallows its key's value.
                if (depth >= 1 && key !== null) key = null
                depth++
                return null
            }
            if (/^\s*\]\s*$/.test(s)) {
                depth--
                if (depth === 0 && uri !== null) {
                    const out = { app: appIdOf(uri), props: props }
                    reset()
                    return out
                }
                return null
            }
            const str = /^\s*string "(.*)"\s*$/.exec(s)
            if (str) {
                if (depth === 0 && uri === null) uri = str[1]
                else if (depth === 1 && key === null) key = str[1]
                return null
            }
            const vr = /^\s*variant\s+(\w+)\s+(.*)$/.exec(s)
            if (vr && depth === 1 && key !== null) {
                const v = _value(vr[1], vr[2])
                if (v !== null) props[key] = v
                key = null
            }
            return null
        }
    }
}

// Merge one update into { appId: state }, returning a NEW map (bindings see it).
// state: { count, countVisible, progress, progressVisible, urgent }, clamped.
function apply(entries, update) {
    const next = Object.assign(Object.create(null), entries)
    const prev = entries[update.app] || { count: 0, countVisible: false,
                                          progress: 0, progressVisible: false, urgent: false }
    const p = update.props
    const s = Object.assign({}, prev)
    if (typeof p["count"] === "number")            s.count = Math.max(0, Math.floor(p["count"]))
    if (typeof p["count-visible"] === "boolean")   s.countVisible = p["count-visible"]
    if (typeof p["progress"] === "number")         s.progress = Math.max(0, Math.min(1, p["progress"]))
    if (typeof p["progress-visible"] === "boolean") s.progressVisible = p["progress-visible"]
    if (typeof p["urgent"] === "boolean")          s.urgent = p["urgent"]
    next[update.app] = s
    return next
}
