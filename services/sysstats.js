.pragma library

// ── sysstats.js ───────────────────────────────────────────────────────────────
// The system stats pill's logic, as pure functions: which rings to draw, how a
// reading becomes a ring, and the parsers for what the kernel and procps hand
// back. services/SysInfo, services/SysStats and modules/bar/StatsHost call in;
// scripts/test-sysstats.js pins every function against real captures.
// ─────────────────────────────────────────────────────────────────────────────

// Every ring there is, in the order the settings page offers them. The CPU and
// GPU temperatures aren't rings of their own: each is an inner arc on its part's
// ring. An older list naming "cputemp"/"gputemp" just loses them (unknown names).
const METRICS = ["cpu", "gpu", "ram", "net", "swap", "disk", "diskio", "battery", "devices"]

// ── statsMetrics ──────────────────────────────────────────────────────────────
// The rings to draw, from the user's list (config.json is hand-editable): known
// names only, each once, in the given order. A ring with nothing to read here
// (`unavailable[name]` true: no GPU utilisation on NVIDIA, no swap, no battery)
// drops out — a ring stuck at 0 would claim an idle GPU or an empty battery.
function statsMetrics(list, unavailable) {
    const out = []
    const na = unavailable || {}
    for (const m of (Array.isArray(list) ? list : [])) {
        if (METRICS.indexOf(m) < 0 || out.indexOf(m) >= 0 || na[m]) continue
        out.push(m)
    }
    return out
}

// The network ring: one direction against a FIXED line speed in Mbit/s (a link
// is full duplex, so each direction has the whole line to itself).
function netRatio(rxBytes, txBytes, mbps) {
    if (!(mbps > 0)) return 0
    const bits = Math.max(rxBytes || 0, txBytes || 0) * 8
    return Math.max(0, Math.min(1, bits / (mbps * 1e6)))
}

// A rate short enough for the inside of a ring: "0", "340K", "4.2M", "12M".
function compactRate(bytesPerSec) {
    const b = bytesPerSec || 0
    if (b < 1024) return "0"
    const k = b / 1024
    if (k < 1000) return Math.round(k) + "K"
    const m = k / 1024
    if (m < 1000) return (m < 10 ? m.toFixed(1) : Math.round(m)) + "M"
    const g = m / 1024
    return (g < 10 ? g.toFixed(1) : Math.round(g)) + "G"
}

// ── page ──────────────────────────────────────────────────────────────────────
// Scroll-to-page: `size` rings at a time (0 = all), `page` wrapping either way.
function page(list, size, p) {
    const n = list.length
    if (!(size > 0) || n <= size) return { items: list, pages: 1, page: 0 }
    const pages = Math.ceil(n / size)
    const at = ((p % pages) + pages) % pages
    return { items: list.slice(at * size, at * size + size), pages: pages, page: at }
}

// ── move / reorder ────────────────────────────────────────────────────────────
// A ring dragged from `from` to `to` among the ones on screen…
function move(list, from, to) {
    if (from === to || from < 0 || from >= list.length) return list.slice()
    const out = list.slice()
    const it = out.splice(from, 1)[0]
    out.splice(Math.max(0, Math.min(out.length, to)), 0, it)
    return out
}

// …written back into the FULL list, whose other entries (a GPU ring this
// machine can't show, another page's rings) keep their places: the on-screen
// ones fill their own old slots in their new order.
function reorder(full, shownNew) {
    const shown = {}
    for (const m of shownNew) shown[m] = true
    let k = 0
    return full.map(m => shown[m] ? shownNew[k++] : m)
}

// ── parseDf ───────────────────────────────────────────────────────────────────
// `df -B1 --output=size,used <path>` → { total, used } in bytes, or null.
function parseDf(text) {
    const lines = String(text || "").trim().split("\n")
    if (lines.length < 2) return null
    const p = lines[lines.length - 1].trim().split(/\s+/).map(Number)
    if (p.length < 2 || !(p[0] > 0) || isNaN(p[1])) return null
    return { total: p[0], used: p[1] }
}

// ── parseDiskstats / diskDelta ────────────────────────────────────────────────
// /proc/diskstats → { name: { read, write, ioMs } }, cumulative, WHOLE disks
// only. Partitions would count every byte twice (sda and sda1), and loop, ram,
// zram and dm devices are either not disks or a disk already counted under
// them. Sectors in this file are always 512 bytes, whatever the hardware's.
const WHOLE_DISK = /^(sd[a-z]+|hd[a-z]+|vd[a-z]+|xvd[a-z]+|nvme\d+n\d+|mmcblk\d+)$/
function parseDiskstats(text) {
    const out = {}
    for (const line of String(text || "").split("\n")) {
        const f = line.trim().split(/\s+/)
        if (f.length < 14 || !WHOLE_DISK.test(f[2])) continue
        out[f[2]] = { read: Number(f[5]) * 512, write: Number(f[9]) * 512, ioMs: Number(f[12]) }
    }
    return out
}

// Two readings `dtMs` apart → { read, write } in bytes/s summed over disks, and
// `util`: the busiest disk's share of the interval spent doing I/O (iostat's
// %util), with that disk's name as `busiest`. That's the disk ring — it has a real 100%, where a byte rate doesn't.
// null until there are two readings to subtract.
function diskDelta(prev, cur, dtMs) {
    if (!prev || !cur || !(dtMs > 0)) return null
    let read = 0, write = 0, util = 0, busiest = ""
    for (const k in cur) {
        const a = prev[k], b = cur[k]
        if (!a) continue
        read  += Math.max(0, b.read  - a.read)
        write += Math.max(0, b.write - a.write)
        const u = Math.max(0, b.ioMs - a.ioMs) / dtMs
        if (busiest === "" || u > util) { util = u; busiest = k }
    }
    return { read: read * 1000 / dtMs, write: write * 1000 / dtMs, util: Math.min(1, util), busiest: busiest }
}

// ── alertStep ─────────────────────────────────────────────────────────────────
// One reading through a sustained-threshold alarm. `state` is { since, on } (the
// time the reading first crossed, 0 while below). The alarm comes on once the
// reading has stayed at or over `threshold` for `sustainMs` — a compile's spike
// isn't an alarm, a stuck process is — and goes off only once it drops below
// `release` (under the threshold), so a reading hovering on the line doesn't
// flap. `fired` is true on exactly the step it came on: notify then, once.
function alertStep(state, value, threshold, release, now, sustainMs) {
    const s = state || { since: 0, on: false }
    if (value >= threshold) {
        const since = s.since || now
        const on = s.on || now - since >= sustainMs
        return { since: since, on: on, fired: on && !s.on }
    }
    if (value < release) return { since: 0, on: false, fired: false }
    return { since: s.on ? s.since : 0, on: s.on, fired: false }
}

// ── fitSections ───────────────────────────────────────────────────────────────
// The hover card is capped at the pill's own length, so it can't always show
// everything. Sections in priority order (their order on the card) → which to
// show: each goes in if it still fits under `room` with `spacing` before it; one
// that doesn't is skipped and a smaller one after it may still fit. The first
// (the header) is always shown. A height < 0 is a section with nothing to show.
function fitSections(heights, spacing, room) {
    const out = []
    let used = 0
    for (let i = 0; i < heights.length; i++) {
        const h = heights[i]
        if (!(h >= 0)) { out.push(false); continue }
        const need = (used > 0 ? spacing : 0) + h
        if (i === 0 || used + need <= room) {
            out.push(true)
            used += need
        } else out.push(false)
    }
    return out
}

// ── Hardware names ────────────────────────────────────────────────────────────
// What the hover card names each part: "GPU — AMD Radeon RX 6700 XT". The raw
// strings come from scripts/hw-names.sh; the tidying is here so it can be tested.

// "AMD Ryzen 5 5600X 6-Core Processor" → "AMD Ryzen 5 5600X";
// "Intel(R) Core(TM) i7-9700K CPU @ 3.60GHz" → "Intel Core i7-9700K".
function cleanCpuName(raw) {
    return String(raw || "")
        .replace(/\((R|TM|tm|r)\)/g, "")
        .replace(/\s+CPU\s+@.*$/, "")
        .replace(/\s+@\s+[\d.]+\s*GHz$/i, "")
        .replace(/\s+\d+-Core\s+Processor$/i, "")
        .replace(/\s+Processor$/i, "")
        .replace(/\s+/g, " ")
        .trim()
}

// The GPU's product name. Vulkan's deviceName is the marketing one ("AMD Radeon
// RX 6700 XT (RADV NAVI22)" — the driver's own suffix dropped); `vk` is
// ["TYPE|name", …] from `vulkaninfo --summary`, and a discrete card beats an
// integrated one, either beats the CPU renderer (llvmpipe). Without Vulkan, lspci's
// line names the chip FAMILY ("…[AMD/ATI] Navi 22 [Radeon RX 6700/6700 XT/…]"),
// which is the best there is: vendor + the bracketed product list.
function gpuName(vk, pci) {
    const rank = t => /DISCRETE/.test(t) ? 0 : /INTEGRATED/.test(t) ? 1 : /VIRTUAL/.test(t) ? 2 : 9
    let best = null
    for (const line of (vk || [])) {
        const bar = line.indexOf("|")
        if (bar < 0) continue
        const t = line.slice(0, bar), name = line.slice(bar + 1).trim()
        if (rank(t) > 2 || name === "") continue
        if (!best || rank(t) < best.r) best = { r: rank(t), name: name }
    }
    if (best) return best.name.replace(/\s*\([^()]*\)\s*$/, "").trim()
    const p = String(pci || "").trim()
    if (p === "") return ""
    const vendor = /NVIDIA/i.test(p) ? "NVIDIA" : /AMD|ATI/.test(p) ? "AMD" : /Intel/i.test(p) ? "Intel" : ""
    const brackets = p.match(/\[([^\]]+)\]/g) || []
    const product = brackets.length > 0 ? brackets[brackets.length - 1].slice(1, -1) : p
    if (/^(AMD\/ATI|AMD|NVIDIA|Intel)$/.test(product)) return p
    return (vendor && product.indexOf(vendor) !== 0 ? vendor + " " : "") + product
}

// ── Device batteries ──────────────────────────────────────────────────────────
// The "devices" ring: the charge of everything battery-powered that ISN'T the
// laptop — Bluetooth and wireless peripherals. Two sources, one shape
// ({ key, name, kind, level 0..1, charging }): UPower's peripherals (Bluetooth via
// BlueZ, and anything with a kernel power_supply — Logitech, controllers), mapped
// in services/DeviceBatteries; and OpenRazer, for Razer devices mainline can't read.

// A peripheral's kind → its glyph. Unknown kinds get a plain battery.
const KIND_GLYPHS = {
    mouse:      "\u{F037D}",   // 󰍽 mouse
    keyboard:   "\u{F030C}",   // 󰌌 keyboard
    headset:    "\u{F02CE}",   // 󰋎 headset
    headphones: "\u{F02CB}",   // 󰋋 headphones
    speaker:    "\u{F04C3}",   // 󰓃 speaker
    gamepad:    "\u{F0EB5}",   // 󰺵 controller
    phone:      "\u{F011C}",   // 󰄜 cellphone
    tablet:     "\u{F04F6}",   // 󰓶 tablet
    pen:        "\u{F03EA}",   // 󰏪 pen
    watch:      "\u{F0589}",   // 󰖉 watch
    bluetooth:  "\u{F00AF}",   // 󰂯 bluetooth
}
function kindGlyph(kind) { return KIND_GLYPHS[kind] || "\u{F0079}" }   // 󰁹 battery

// OpenRazer's getDeviceType → our kind.
function razerKind(type) {
    const t = String(type || "").toLowerCase()
    if (t === "mouse") return "mouse"
    if (t === "keyboard" || t === "keypad") return "keyboard"
    if (t === "headset") return "headset"
    if (t === "speaker") return "speaker"
    if (t === "controller" || t === "gamepad") return "gamepad"
    return ""
}

// scripts/razer-batteries.py's JSON → devices. Hand-rolled output from a daemon
// we don't control, so every field is checked. A 0% reading is dropped: OpenRazer
// answers 0 for a wireless device that's asleep or out of range, and a ring stuck
// at empty would say the mouse is dead when it's only idle.
function parseRazer(text) {
    let list
    try { list = JSON.parse(String(text || "")) } catch (e) { return [] }
    if (!Array.isArray(list)) return []
    const out = []
    for (const d of list) {
        if (!d || typeof d !== "object" || typeof d.serial !== "string" || d.serial === "") continue
        const pct = Number(d.battery)
        if (!(pct > 0)) continue
        const dpi = Array.isArray(d.dpi) ? Number(d.dpi[0]) : NaN
        const low = Number(d.lowBattery)
        out.push({
            key: "razer:" + d.serial,
            name: typeof d.name === "string" && d.name.trim() !== "" ? d.name.trim() : "Razer device",
            kind: razerKind(d.type),
            level: Math.min(1, pct / 100),
            charging: d.charging === true,
            // The card's details; null where the device can't say (or said nonsense).
            dpi:      Number.isInteger(dpi) && dpi > 0 && dpi <= 100000 ? dpi : null,
            pollRate: Number.isInteger(d.pollRate) && d.pollRate > 0 && d.pollRate <= 10000 ? d.pollRate : null,
            firmware: typeof d.firmware === "string" && d.firmware.trim() !== "" ? d.firmware.trim().slice(0, 32) : null,
            idleTime: Number.isInteger(d.idleTime) && d.idleTime > 0 ? d.idleTime : null,
            lowAt:    low > 0 && low < 100 ? low / 100 : null,
        })
    }
    return out
}

// "Razer Viper Ultimate (Wireless)" → "Razer Viper Ultimate": a wireless mouse
// charging on its cable shows up twice (the dongle's device and the cable's), and
// the suffix is all that tells them apart.
const LINK_SUFFIX = /\s*\((Wireless|Wired|Receiver|Dongle)\)\s*$/i
function deviceBaseName(name) {
    return String(name || "").replace(LINK_SUFFIX, "").trim()
}
// …and what that suffix said: "wireless", "wired", or "" when the name doesn't say.
function deviceLink(name) {
    const m = String(name || "").match(LINK_SUFFIX)
    if (!m) return ""
    return /^wired$/i.test(m[1]) ? "wired" : "wireless"
}

// Every source's devices as one list: one entry per device (by base name — a
// charging copy wins, and its level), lowest charge first so [0] is the ring's.
function mergeDevices(lists) {
    const byName = {}
    const order = []
    for (const list of (lists || [])) for (const d of (list || [])) {
        if (!d || !(d.level >= 0)) continue
        const name = deviceBaseName(d.name) || d.name || "Device"
        const k = name.toLowerCase()
        const e = Object.assign({}, d, {
            name: name, kind: d.kind || "", level: Math.min(1, d.level), charging: !!d.charging,
            link: deviceLink(d.name)
        })
        if (!(k in byName)) { byName[k] = e; order.push(k); continue }
        const had = byName[k]
        if (e.charging && !had.charging) byName[k] = e
        else if (e.charging === had.charging && e.level > had.level) byName[k] = e
    }
    return order.map(k => byName[k])
                .sort((a, b) => a.level - b.level || a.name.localeCompare(b.name))
}

// Low, for the card's warning colour: at or under `threshold` and not charging.
function deviceLow(d, threshold) { return !!d && !d.charging && d.level <= threshold }

// A device's name as its kind ("Mouse"), for the card's header: the model is right
// beside it, so the part name says what it is, the way "GPU — …" does.
const KIND_LABELS = { mouse: "Mouse", keyboard: "Keyboard", headset: "Headset",
                      headphones: "Headphones", speaker: "Speaker", gamepad: "Controller",
                      phone: "Phone", tablet: "Tablet", pen: "Pen", watch: "Watch" }
function kindLabel(kind) { return KIND_LABELS[kind] || "Device" }

// What the card lists under a device's charge bar, one { glyph, text } per fact it
// knows: how it's connected, DPI and polling, when it sleeps, when it warns, its
// firmware. Only what the source actually reported — UPower's devices have none of
// these, so theirs is just the link.
function deviceRows(d) {
    if (!d) return []
    const rows = []
    if (d.charging && d.link === "wired")      rows.push({ glyph: "\u{F06A5}", text: "Charging on its cable" })   // 󰚥 power-plug
    else if (d.charging)                        rows.push({ glyph: "\u{F140B}", text: "Charging" })                // 󱐋 lightning-bolt
    else if (d.link === "wireless")             rows.push({ glyph: "\u{F05A9}", text: "Wireless" })                // 󰖩 wifi
    if (d.dpi || d.pollRate)
        rows.push({ glyph: "\u{F04FE}",                                                                           // 󰓾 target
                    text: [d.dpi ? d.dpi + " DPI" : "", d.pollRate ? d.pollRate + " Hz" : ""].filter(x => x).join(" · ") })
    if (d.idleTime) {
        const m = Math.round(d.idleTime / 60)
        rows.push({ glyph: "\u{F04B2}", text: "Sleeps after " + (m >= 1 ? m + " min" : d.idleTime + " s") })  // 󰒲 sleep
    }
    if (d.lowAt)    rows.push({ glyph: "\u{F0083}", text: "Low at " + Math.round(d.lowAt * 100) + "%" })        // 󰂃 battery-alert
    if (d.firmware) rows.push({ glyph: "\u{F061A}", text: "Firmware " + d.firmware })                         // 󰘚 chip
    return rows
}
