// ── clockfmt ──────────────────────────────────────────────────────────────────
// One way to write a duration on screen. Was copied into TimerWidget, MediaController and
// three JS files, and the copies drifted (MediaController ran past an hour as "75:00").
//
//   clock(65)    → "1:05"
//   clock(3725)  → "1:02:05"      (an hour or more: h:mm:ss, minutes padded)
//   clock(0)     → "0:00"
//   clock(-3)    → "0:00"
//   clock(59.9)  → "0:59"         (fractions floor, like a stopwatch's whole seconds)

function pad2(n) { return n < 10 ? "0" + n : "" + n }

function clock(secs) {
    const s = Math.max(0, Math.floor(Number(secs) || 0))
    const h = Math.floor(s / 3600)
    const m = Math.floor((s % 3600) / 60)
    const r = s % 60
    return (h > 0 ? h + ":" + pad2(m) : m) + ":" + pad2(r)
}
