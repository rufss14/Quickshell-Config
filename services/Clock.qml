pragma Singleton
import Quickshell
import QtQuick

// ── Clock ─────────────────────────────────────────────────────────────────────
// The wall clock, once.
//
// ── Why this exists ───────────────────────────────────────────────────────────
// Twelve files ran their own `Timer { interval: 1000 }` or `60000` and called
// `new Date()` in it: ClockPill, DesktopClock, ClockWidget, WorldclockWidget,
// CalendarWidget, CalendarCard, SunWidget, NotesWidget, CountdownWidget and more.
// Two costs, and the second is the one you can see:
//
//   • Wakeups. Ten independent second-timers wake the process ten times a second
//     between them, and none of them can be coalesced because nothing knows the
//     others exist.
//   • They DISAGREE. A Timer starts counting when its component is created, so two
//     clocks created 600ms apart tick 600ms apart forever. With the bar clock and the
//     desktop clock both on screen, one of them shows the new minute up to a second
//     before the other — the shell visibly contradicting itself.
//
// One timer, one `now`, and everything that displays time is by construction in step.
//
// ── Aligned to the wall clock, not to when we started ─────────────────────────
// The interval is recomputed each fire as "time until the next real boundary" rather
// than being a fixed 1000. A fixed interval inherits whatever sub-second offset the
// shell happened to launch at and keeps it forever, so a clock showing minutes would
// change at :00.4 — reliably late, and drifting further as Timer's own error
// accumulates. Re-aligning each tick also self-corrects after the process is
// suspended or the machine sleeps.
//
// ── Seconds are refcounted ────────────────────────────────────────────────────
// Most consumers only need the minute. A clock face showing seconds, or a stopwatch
// readout, calls acquireSeconds() and the shared timer moves up to one-second
// resolution for as long as anything holds a reference — same contract as SysInfo and
// HyprConfig. Nothing on screen wanting seconds means one wakeup a minute for the
// whole shell.
//
// Note this is deliberately NOT the timer for durations. Timers.qml owns the
// countdown and the stopwatch, which are anchored to absolute epochs and need 50ms
// resolution; this is for displaying what time it is.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // The current moment. Everything else here is derived from it, so a consumer that
    // wants its own format can bind to this and call toLocaleString itself.
    readonly property date now: root._now
    property date _now: new Date()

    readonly property int hours:   root._now.getHours()
    readonly property int minutes: root._now.getMinutes()
    readonly property int seconds: root._now.getSeconds()

    // Changes only when the DAY does. A calendar binding on `now` re-evaluates every
    // tick to produce the same date; this lets it re-evaluate when that can matter.
    readonly property int dayStamp:
        root._now.getFullYear() * 10000 + (root._now.getMonth() + 1) * 100 + root._now.getDate()

    // ── Second resolution, on demand ──────────────────────────────────────────
    property int _secondRefs: 0
    readonly property bool trackingSeconds: root._secondRefs > 0

    // Acquire/release in pairs — Component.onCompleted and Component.onDestruction, or
    // either side of the property that decides whether seconds are shown. Releasing
    // more than you acquired is clamped rather than allowed to go negative, because a
    // negative refcount would leave the fine timer stuck on for the rest of the session.
    function acquireSeconds() {
        root._secondRefs++
        if (root._secondRefs === 1) root._rearm()
    }
    function releaseSeconds() {
        root._secondRefs = Math.max(0, root._secondRefs - 1)
        if (root._secondRefs === 0) root._rearm()
    }

    // Milliseconds until the next boundary we care about. Minute boundaries are the
    // same instant in every timezone (offsets are whole minutes), so the modulo works
    // without any local-time conversion.
    function _msToNextBoundary() {
        const step = root.trackingSeconds ? 1000 : 60000
        const rem  = Date.now() % step
        // A tick landing exactly on the boundary would otherwise ask for a 0ms interval
        // and fire again immediately, on the same instant, forever.
        return rem === 0 ? step : step - rem
    }

    function _rearm() {
        tick.stop()
        tick.interval = root._msToNextBoundary()
        tick.start()
    }

    Timer {
        id: tick
        // One-shot and re-armed by hand: `repeat` with a bound interval would apply a
        // new interval only after the current one elapsed, which is exactly the lag
        // this is here to avoid when something acquires seconds mid-minute.
        repeat: false
        running: false
        onTriggered: {
            root._now = new Date()
            root._rearm()
        }
    }

    Component.onCompleted: root._rearm()

    // ── Formatting ────────────────────────────────────────────────────────────
    // Shared so a time reads the same in the bar as on the desktop.
    function pad(n) { return n < 10 ? "0" + n : "" + n }

    // 24h "14:05" or 12h "2:05" — the hour only, minutes appended by the caller when
    // it wants them, because several consumers style the two differently.
    function hour12(h) { const x = h % 12; return x === 0 ? 12 : x }
    function meridiem(h) { return h < 12 ? "AM" : "PM" }
}
