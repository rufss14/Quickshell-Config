.pragma library

// ── bt.js ─────────────────────────────────────────────────────────────────────
// Bluetooth logic as pure functions: signal strength, low-battery hysteresis,
// rename validation, and reading a Bluetooth card's profiles out of pactl.
// services/Bt, services/BtBridge and services/Audio call in;
// scripts/test-bt.js pins every function.
// ─────────────────────────────────────────────────────────────────────────────

// ── Signal ────────────────────────────────────────────────────────────────────
// RSSI in dBm → 0..4 bars, or -1 when there's no reading. BlueZ only reports RSSI
// while discovering, and drops it when a device stops advertising, so "unknown" is
// a real, common state and must not render as "no signal".
// The steps are the usual Bluetooth ones: -60 is in the room, -90 is the edge.
function signalBars(rssi) {
    if (typeof rssi !== "number" || !isFinite(rssi)) return -1
    if (rssi >= -60) return 4
    if (rssi >= -70) return 3
    if (rssi >= -80) return 2
    if (rssi >= -90) return 1
    return 0
}

// Nearby order: closest first, by BARS rather than raw dBm — RSSI jitters by a few
// dB per advertisement, and sorting on it reshuffled the list under the pointer.
// Unknown signal sinks below every reading; ties go by name.
function compareNearby(a, b) {
    return (b.bars - a.bars) || String(a.name).localeCompare(String(b.name))
}

// ── Low battery ───────────────────────────────────────────────────────────────
// One warning per threshold per discharge. `last` is the threshold already warned
// at (1 = none yet); the state resets once the level climbs `release` above `low`,
// i.e. after a charge — not on every ±1% wobble a headset reports near the line.
// A device that turns up already below `critical` gets the critical warning alone.
function batteryAlert(level, last, low, release) {
    const rel = release === undefined ? 0.05 : release
    const crit = low / 2
    if (typeof level !== "number" || !isFinite(level)) return { alert: "", last: last }
    if (level > low + rel) return { alert: "", last: 1 }
    if (level <= crit && last > crit) return { alert: "critical", last: crit }
    if (level <= low && last > low)  return { alert: "low", last: low }
    return { alert: "", last: last }
}

// ── Rename ────────────────────────────────────────────────────────────────────
// BlueZ's Alias: what the user typed, trimmed. "" is valid — BlueZ resets the alias
// to the device's own name. Control characters are refused (they came from a text
// field, but a name is shown in notifications and the OSD), and so is anything over
// the 248-byte Bluetooth name limit. null = refuse.
function cleanAlias(text) {
    const s = String(text ?? "").trim()
    if (/[\u0000-\u001f\u007f]/.test(s)) return null
    let bytes = 0
    for (const ch of s) {
        const c = ch.codePointAt(0)
        bytes += c < 0x80 ? 1 : c < 0x800 ? 2 : c < 0x10000 ? 3 : 4
    }
    return bytes > 248 ? null : s
}

// ── Codecs ────────────────────────────────────────────────────────────────────
// bluez5's codec ids, spelled the way people know them. One table, used for the
// sink's live codec (Audio) and the codec chips (the card's profiles below).
const CODECS = {
    sbc: "SBC", sbc_xq: "SBC-XQ", aac: "AAC", ldac: "LDAC", lc3: "LC3", lc3plus_h3: "LC3plus",
    aptx: "aptX", aptx_hd: "aptX HD", aptx_ll: "aptX LL", aptx_ll_duplex: "aptX LL",
    faststream: "FastStream", faststream_duplex: "FastStream",
    msbc: "mSBC", cvsd: "CVSD", opus_05: "Opus", opus_g: "Opus", lc3_swb: "LC3-SWB"
}
function codecLabel(id) {
    const c = String(id || "").toLowerCase()
    return c === "" ? "" : (CODECS[c] ?? c.toUpperCase())
}

// ── A Bluetooth card's profiles ───────────────────────────────────────────────
// PipeWire's bluez5 device offers one profile per (mode, codec): `a2dp-sink-aac`,
// `headset-head-unit-msbc`, … plus a codec-less `a2dp-sink` / `headset-head-unit`
// meaning "the best one". So a single `pactl -f json list cards` read answers both
// questions the hero asks — music or calls, and which codec — and a single
// `set-card-profile` changes either.
//
//   music   a2dp-sink*, bap-sink*          high quality, output only
//   calls   headset-head-unit*, bap-duplex*  the headset's mic on, low quality
const MODES = [
    [/^a2dp-sink(?:-(.+))?$/,         "music"],
    [/^bap-sink(?:-(.+))?$/,          "music"],
    [/^headset-head-unit(?:-(.+))?$/, "calls"],
    [/^bap-duplex(?:-(.+))?$/,        "calls"],
]

function profileKind(name) {
    const n = String(name || "")
    if (n === "off") return { kind: "off", codec: "" }
    for (const [re, kind] of MODES) {
        const m = n.match(re)
        if (m) return { kind: kind, codec: m[1] || "" }
    }
    return { kind: "other", codec: "" }
}

// The card PipeWire made for a MAC: bluez_card.AA_BB_CC_DD_EE_FF.
function cardName(address) {
    return "bluez_card." + String(address || "").toUpperCase().replace(/:/g, "_")
}

// `pactl -f json list cards` → this device's card, or null.
//   { card, active, kind, codec, music, calls, codecs: [{ profile, codec, label }] }
// `codecs` are the AVAILABLE codec-specific profiles of the ACTIVE mode, in
// PipeWire's priority order. `codec` is the active one ("" for a codec-less profile
// — the live sink's `api.bluez5.codec` says which it picked).
// Output from a subprocess, so every field is checked; garbage in → null out.
function parseCard(text, address) {
    let list
    try { list = JSON.parse(String(text || "")) } catch (e) { return null }
    if (!Array.isArray(list)) return null
    const want = cardName(address)
    const card = list.find(c => c && typeof c === "object" && c.name === want)
    if (!card || typeof card.profiles !== "object" || card.profiles === null) return null

    const active = typeof card.active_profile === "string" ? card.active_profile : ""
    const act = profileKind(active)
    const out = { card: want, active: active, kind: act.kind, codec: act.codec,
                  music: false, calls: false, codecs: [] }

    const entries = Object.keys(card.profiles).map(name => {
        const p = card.profiles[name] || {}
        return Object.assign({ name: name, available: p.available !== false,
                               priority: typeof p.priority === "number" ? p.priority : 0 },
                             profileKind(name))
    }).filter(e => e.available)
      .sort((a, b) => b.priority - a.priority)

    for (const e of entries) {
        if (e.kind === "music") out.music = true
        if (e.kind === "calls") out.calls = true
        if (e.kind === act.kind && e.codec !== "")
            out.codecs.push({ profile: e.name, codec: e.codec, label: codecLabel(e.codec) })
    }
    return out
}

// The profile that switches to `kind` — the codec-less "best" one when PipeWire
// offers it, otherwise that mode's highest-priority codec profile. "" if none.
function profileFor(text, address, kind) {
    let list
    try { list = JSON.parse(String(text || "")) } catch (e) { return "" }
    const card = Array.isArray(list) ? list.find(c => c && c.name === cardName(address)) : null
    if (!card || typeof card.profiles !== "object" || card.profiles === null) return ""
    let best = "", bestPri = -Infinity
    for (const name of Object.keys(card.profiles)) {
        const p = card.profiles[name] || {}
        if (p.available === false) continue
        const k = profileKind(name)
        if (k.kind !== kind) continue
        if (k.codec === "") return name
        const pri = typeof p.priority === "number" ? p.priority : 0
        if (pri > bestPri) { best = name; bestPri = pri }
    }
    return best
}

// ── Addresses ─────────────────────────────────────────────────────────────────
function validAddress(s) {
    return /^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$/.test(String(s || ""))
}

// ── File transfers ────────────────────────────────────────────────────────────
// A transfer's progress, 0..1; unknown size → 0 until it completes.
function transferFraction(t) {
    if (!t) return 0
    if (t.status === "complete") return 1
    return t.size > 0 ? Math.max(0, Math.min(1, t.sent / t.size)) : 0
}
