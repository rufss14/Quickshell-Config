pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "alarms.js" as AL
import "timers.js" as TM

// ── Timers ────────────────────────────────────────────────────────────────────
// The countdown timer, the stopwatch, and time-of-day alarms — all owned here rather
// than in the overview's TimerCard, for two reasons:
//
//   • The card is instantiated PER SCREEN (Variants over the monitors). Left in the
//     card, a two-monitor setup would run two ticks, write the same state file from two
//     writers, and fire every "timer finished" / alarm notification twice. One singleton
//     ticks once, writes once, notifies once.
//   • An alarm has to be able to fire when the overview is CLOSED. A singleton is always
//     alive; a card is only reliably around while you're looking at it.
//
// ── Added 2026-10-18 ──────────────────────────────────────────────────────────
//   · a countdown PAUSES (`pauseTimer` / `resumeTimer`: the time left is banked) and EXTENDS (`extendTimer`:
//     +1 / +5 min; `timerSpan` is what the ring is a fraction of, so it grows with it);
//   · a focus (Pomodoro) cycle rides the countdown (`startPomodoro`, `pomoSkip`; the phases are services/
//     timers.js `pomoNext`): finishing a phase starts the next, so the sidebar's ring follows it for free;
//   · an alarm that fires RINGS (`ringing`) until it is dismissed or snoozed (`snoozeAlarm`), and the sidebar
//     button says so.
//
// ── Persisted, and resumed from the wall clock ────────────────────────────────
// State lives in a JsonStore (statePath), so a reload or a reboot doesn't lose a running
// timer, a stopwatch, or your alarms. Everything is anchored to absolute epoch
// timestamps (timerEnd, swStart, an alarm's `at`), never to an accumulated tick count —
// so on load we recompute against Date.now() and a timer that would have finished while
// the machine was off comes back FINISHED, a stopwatch comes back with the real elapsed,
// and an alarm whose moment passed while we were down is quietly disarmed rather than
// firing late.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // Which face the card shows — persisted so it reopens where you left it.
    property string mode: "timer"       // "timer" | "stopwatch" | "alarm" | "focus"

    // True once the persisted state has been read (or confirmed absent). The card can
    // gate on it, and tests wait for it before acting.
    readonly property bool ready: store.ready

    // ══ Timer — counts down ═══════════════════════════════════════════════════
    property int setH: 0
    property int setM: 5
    property int setS: 0

    property double timerEnd:     0     // epoch ms; 0 = not running
    property bool   timerRunning: false
    property bool   timerDone:    false
    property int    timerRemain:  0     // seconds, for display
    // Paused: the time left is banked (ms) and the end is nobody's until it resumes.
    property bool   timerPaused:  false
    property int    timerLeftMs:  0
    // How long THIS run is, in seconds — what the ring is a fraction of. Not `timerTotal` (the length you
    // dialled in): a +5 min extension grows it, and a focus phase has a length of its own.
    property int    timerSpan:    0

    readonly property int timerTotal: root.setH * 3600 + root.setM * 60 + root.setS

    function bumpSet(unit, delta) {
        const max = unit === 0 ? 23 : 59
        const cur = unit === 0 ? root.setH : unit === 1 ? root.setM : root.setS
        const val = Math.max(0, Math.min(max, cur + delta))
        if (unit === 0)      root.setH = val
        else if (unit === 1) root.setM = val
        else                 root.setS = val
        root._persist()
    }
    // The dial: set the whole length in seconds (a turn of the cookie). Not while one runs.
    function setTimerLength(secs) {
        if (root.timerRunning || root.timerPaused) return
        const t = Math.max(0, Math.min(23 * 3600 + 59 * 60 + 59, Math.floor(secs)))
        root.setH = Math.floor(t / 3600)
        root.setM = Math.floor((t % 3600) / 60)
        root.setS = t % 60
        root._persist()
    }
    function readSet(unit) {
        return unit === 0 ? root.setH : unit === 1 ? root.setM : root.setS
    }

    // Begin a countdown of `secs`, whatever it is for (the dialled length, a focus phase).
    function _begin(secs) {
        root.timerEnd     = Date.now() + secs * 1000
        root.timerRemain  = secs
        root.timerSpan    = secs
        root.timerDone    = false
        root.timerPaused  = false
        root.timerLeftMs  = 0
        root.timerRunning = true
    }
    function startTimer() {
        if (root.timerTotal <= 0) return
        root.pomoOn = false
        root._begin(root.timerTotal)
        root._persist()
    }
    // Stopping cancels whatever the countdown was doing — including a focus cycle riding it.
    function stopTimer() {
        root.timerRunning = false
        root.timerEnd     = 0
        root.timerRemain  = 0
        root.timerSpan    = 0
        root.timerDone    = false
        root.timerPaused  = false
        root.timerLeftMs  = 0
        root.pomoOn       = false
        root._persist()
    }
    function pauseTimer() {
        if (!root.timerRunning) return
        root.timerLeftMs  = Math.max(0, root.timerEnd - Date.now())
        root.timerRemain  = Math.ceil(root.timerLeftMs / 1000)
        root.timerRunning = false
        root.timerEnd     = 0
        root.timerPaused  = true
        root._persist()
    }
    function resumeTimer() {
        if (!root.timerPaused) return
        root.timerEnd     = Date.now() + root.timerLeftMs
        root.timerPaused  = false
        root.timerLeftMs  = 0
        root.timerRunning = true
        root._persist()
    }
    // +N seconds on a running or paused countdown.
    function extendTimer(secs) {
        if (!root.timerRunning && !root.timerPaused) return
        const e = TM.extend(root.timerSpan, root.timerRemain, secs)
        root.timerSpan = e.span
        if (root.timerRunning) root.timerEnd += Math.max(0, secs) * 1000
        else root.timerLeftMs += Math.max(0, secs) * 1000
        root.timerRemain = e.remain
        root._persist()
    }

    // Set the duration and start in one call — the desktop timer tile's quick-set
    // chips, which otherwise had no way to put a length on the clock at all (the
    // steppers only live in the overview card). `startTimer()` persists.
    function startTimerFor(secs) {
        const s = Math.max(0, Math.floor(secs))
        root.setH = Math.floor(s / 3600)
        root.setM = Math.floor((s % 3600) / 60)
        root.setS = s % 60
        root.startTimer()
    }

    // ══ Focus — a Pomodoro cycle on the countdown ════════════════════════════
    // `pomoOn` while a cycle runs; `pomoPhase` "focus" | "short" | "long"; `pomoCycle` the focus sessions
    // completed. The countdown fields do the counting (so a pause, an extension and the sidebar ring all
    // work); finishing a phase starts the next one (`_pomoAdvance`) instead of ending in "done".
    property bool   pomoOn:    false
    property string pomoPhase: "focus"
    property int    pomoCycle: 0
    property int    pomoFocus: TM.POMO_DEFAULTS.focus      // minutes
    property int    pomoShort: TM.POMO_DEFAULTS.short
    property int    pomoLong:  TM.POMO_DEFAULTS.long
    property int    pomoEvery: TM.POMO_DEFAULTS.every      // a long break after this many sessions
    readonly property var pomoCfg: ({ focus: root.pomoFocus, short: root.pomoShort, long: root.pomoLong, every: root.pomoEvery })
    readonly property string pomoLabel: root.pomoPhase === "focus" ? "Focus" : root.pomoPhase === "long" ? "Long break" : "Short break"
    readonly property int pomoSession: TM.pomoSession(root.pomoPhase, root.pomoCycle, root.pomoEvery)

    function setPomo(key, v) {
        const c = TM.pomoClean(Object.assign({}, root.pomoCfg, ({ [key]: v })))
        root.pomoFocus = c.focus; root.pomoShort = c.short; root.pomoLong = c.long; root.pomoEvery = c.every
        root._persist()
    }
    function startPomodoro() {
        const f = TM.pomoStart(root.pomoCfg)
        root.pomoOn = true
        root.pomoPhase = f.phase
        root.pomoCycle = f.cycle
        root._begin(f.seconds)
        root._persist()
    }
    function _pomoAdvance() {
        const n = TM.pomoNext(root.pomoPhase, root.pomoCycle, root.pomoCfg)
        root.pomoPhase = n.phase
        root.pomoCycle = n.cycle
        root._begin(n.seconds)
        const say = TM.pomoNotice(n)
        Sfx.play("timer")
        root._notify("normal", say.title, say.body)
        root._persist()
    }
    // Skip to the next phase now (a break you do not want, a session cut short).
    function pomoSkip() { if (root.pomoOn) root._pomoAdvance() }

    // ══ Stopwatch — counts up ═════════════════════════════════════════════════
    property double swStart:   0        // epoch ms of the current run
    property double swAccum:   0        // ms banked across pauses
    property bool   swRunning: false
    property int    swElapsed: 0        // ms, for display
    property var    laps:      []

    function startStopwatch() {
        root.swStart   = Date.now()
        root.swRunning = true
        root._persist()
    }
    function pauseStopwatch() {
        root.swAccum   += Date.now() - root.swStart
        root.swElapsed  = root.swAccum
        root.swRunning  = false
        root._persist()
    }
    function resetStopwatch() {
        root.swRunning = false
        root.swStart   = 0
        root.swAccum   = 0
        root.swElapsed = 0
        root.laps      = []
        root._persist()
    }
    function lap() {
        if (!root.swRunning) return
        root.laps = [root.swElapsed].concat(root.laps)   // newest first
        root._persist()
    }

    // ══ Alarms ════════════════════════════════════════════════════════════════
    // [{ id, h, m, enabled, at, days }] — `at` is the next-occurrence epoch. `days` is a weekday
    // bitmask (alarms.js; bit 0 = Sunday): 0 is a one-shot, which disarms itself when it fires (it stays
    // in the list, toggled off, to re-arm); anything else re-arms for its next day, and stays on.
    property var alarms: []
    property int _alarmSeq: 0

    readonly property bool _anyAlarmArmed: {
        for (let i = 0; i < root.alarms.length; i++) if (root.alarms[i].enabled || (root.alarms[i].snoozeAt || 0) > 0) return true
        return false
    }

    function _nextOccurrence(h, m, days) {
        return AL.nextOccurrence(h, m, AL.cleanMask(days), Date.now())
    }

    function addAlarm(h, m, days) {
        const a = { id: "a" + (root._alarmSeq++), h: h, m: m,
                    enabled: true, at: root._nextOccurrence(h, m, days), days: AL.cleanMask(days) }
        const list = root.alarms.slice()
        list.push(a)
        list.sort((x, y) => (x.h * 60 + x.m) - (y.h * 60 + y.m))
        root.alarms = list
        root._persist()
    }
    function removeAlarm(id) {
        root.alarms = root.alarms.filter(a => a.id !== id)
        root._persist()
    }
    function toggleAlarm(id) {
        root.alarms = root.alarms.map(a => {
            if (a.id !== id) return a
            const en = !a.enabled
            // Re-arming recomputes the next occurrence, so an alarm you toggle back on
            // fires at its NEXT time, not a stale one in the past.
            return { id: a.id, h: a.h, m: a.m, enabled: en, days: a.days || 0,
                     at: en ? root._nextOccurrence(a.h, a.m, a.days) : a.at }
        })
        root._persist()
    }

    // Set which weekdays an alarm repeats on (alarms.js bitmask, 0 = once). A turned-on alarm re-aims at
    // its next matching moment, so unticking today's weekday moves it past today at once.
    function setAlarmDays(id, mask) {
        const days = AL.cleanMask(mask)
        root.alarms = root.alarms.map(a => a.id !== id ? a
            : Object.assign({}, a, { days: days, at: a.enabled ? root._nextOccurrence(a.h, a.m, days) : a.at }))
        root._persist()
    }

    // The alarm that is ringing now ({ id, h, m }) until it is dismissed or snoozed — the sidebar button and
    // the panel say so; a notification alone is easy to miss. Not persisted: a reload silences it.
    property var ringing: null
    function _fireAlarm(a) {
        root.ringing = { id: a.id, h: a.h, m: a.m }
        Sfx.play("alarm")
        root._notify("critical", "Alarm", root.pad(a.h) + ":" + root.pad(a.m))
    }
    function dismissAlarm() { root.ringing = null }
    // It goes off again in `minutes` (alarms.js is untouched: `snoozeAt` is checked beside the schedule, which
    // carries on as it was — a repeating alarm still rings tomorrow).
    function snoozeAlarm(minutes) {
        const r = root.ringing
        root.ringing = null
        if (!r) return
        const at = Date.now() + Math.max(1, minutes) * 60000
        root.alarms = root.alarms.map(a => a.id === r.id ? Object.assign({}, a, { snoozeAt: at }) : a)
        root._persist()
    }

    // ══ Notifications ═════════════════════════════════════════════════════════
    Process { id: notifyProc; running: false }
    function _notify(urgency, title, body) {
        notifyProc.command = ["notify-send", "--app-name=Quickshell",
                              "--urgency=" + urgency, title, body]
        notifyProc.running = false
        notifyProc.running = true
    }

    // ══ Ticks ═════════════════════════════════════════════════════════════════
    // Tick for the running timer/stopwatch readouts. Only runs while one of them is going —
    // an idle card wakes nothing. The stopwatch shows hundredths, so it keeps 50ms; a
    // countdown only shows whole seconds, so it ticks at 200ms.
    Timer {
        interval: root.swRunning ? 50 : 200
        repeat: true
        running: root.timerRunning || root.swRunning
        onTriggered: {
            if (root.timerRunning) {
                const left = Math.round((root.timerEnd - Date.now()) / 1000)
                if (left <= 0 && root.pomoOn) {
                    root._pomoAdvance()                        // a focus phase ended: the next begins
                } else if (left <= 0) {
                    root.timerRemain  = 0
                    root.timerRunning = false
                    root.timerEnd     = 0
                    root.timerDone    = true
                    Sfx.play("timer")
                    root._notify("critical", "Timer finished", root.clockString(root.timerSpan > 0 ? root.timerSpan : root.timerTotal))
                    root._persist()
                } else {
                    root.timerRemain = left
                }
            }
            if (root.swRunning)
                root.swElapsed = root.swAccum + (Date.now() - root.swStart)
        }
    }

    // Coarse tick just for alarms — a second's resolution is plenty for a wall-clock
    // alarm, and it runs only while at least one alarm is armed.
    Timer {
        interval: 1000
        repeat: true
        running: root._anyAlarmArmed
        onTriggered: root._checkAlarms()
    }

    function _checkAlarms() {
        const now = Date.now()
        let fired = false
        const list = root.alarms.map(a => {
            // A snooze is checked beside the schedule, not instead of it.
            const snoozed = (a.snoozeAt || 0) > 0
            if (snoozed && now >= a.snoozeAt) {
                root._fireAlarm(a)
                fired = true
                return Object.assign({}, a, { snoozeAt: 0 })
            }
            if (a.enabled && now >= a.at) {
                root._fireAlarm(a)
                fired = true
                // A repeating alarm is on again for its next day; a one-shot is spent.
                return a.days ? { id: a.id, h: a.h, m: a.m, enabled: true, days: a.days,
                                  at: root._nextOccurrence(a.h, a.m, a.days), snoozeAt: a.snoozeAt || 0 }
                              : { id: a.id, h: a.h, m: a.m, enabled: false, days: 0, at: a.at, snoozeAt: a.snoozeAt || 0 }
            }
            return a
        })
        if (fired) { root.alarms = list; root._persist() }
    }

    // ══ Formatting ════════════════════════════════════════════════════════════
    // Shared by the card and the notifications, so a duration reads the same everywhere.
    function pad(n) { return n < 10 ? "0" + n : "" + n }

    function clockString(totalSeconds) {
        let s = totalSeconds
        const h = Math.floor(s / 3600); s -= h * 3600
        const m = Math.floor(s / 60);   s -= m * 60
        return (h > 0 ? root.pad(h) + ":" : "") + root.pad(m) + ":" + root.pad(s)
    }

    // The stopwatch shows hundredths — the whole reason to reach for one.
    function lapString(ms) {
        const hundredths = Math.floor(ms / 10)
        const cs = hundredths % 100
        let s = Math.floor(hundredths / 100)
        const h = Math.floor(s / 3600); s -= h * 3600
        const m = Math.floor(s / 60);   s -= m * 60
        return (h > 0 ? root.pad(h) + ":" : "") + root.pad(m) + ":" + root.pad(s)
             + "." + root.pad(cs)
    }

    // ══ Persistence ═══════════════════════════════════════════════════════════
    property bool _loading: false
    // Set once the user has actively changed anything — the signal that live state is
    // authoritative and a late disk-load must not overwrite it (see onLoaded).
    property bool _touched: false

    JsonStore {
        id: store
        path: Quickshell.statePath("timers.json")
        onLoaded: {
            root._loading = true

            // ── A late load must NOT stomp live state ─────────────────────────
            // Normally this fires at startup before anything is running, and restores the
            // saved timer/stopwatch/alarms. But the read is asynchronous, and if it lands
            // AFTER the user has already started something, applying the (now stale) disk
            // state would silently stop a running timer. Once the user has touched
            // anything, the live state wins and simply persists over the file.
            // Flush now the store is ready: a mutation before the load couldn't write and
            // would otherwise be lost until the next one.
            if (root._touched) { root._loading = false; root._persist(); return }

            const v = store.value ?? ({})
            const now = Date.now()

            root.mode      = v.mode ?? root.mode
            root.setH      = v.setH ?? root.setH
            root.setM      = v.setM ?? root.setM
            root.setS      = v.setS ?? root.setS
            root._alarmSeq = v.alarmSeq ?? 0
            root.laps      = Array.isArray(v.laps) ? v.laps : []
            root.swAccum   = v.swAccum ?? 0
            const pc = TM.pomoClean(v.pomo)
            root.pomoFocus = pc.focus; root.pomoShort = pc.short; root.pomoLong = pc.long; root.pomoEvery = pc.every

            // ── Timer: resume, or come back finished if its moment passed ──────
            root.timerEnd = v.timerEnd ?? 0
            root.timerSpan = v.timerSpan ?? 0
            // A focus cycle comes back where it was; one whose phase ended while we were down is simply over.
            root.pomoPhase = v.pomoPhase === "short" || v.pomoPhase === "long" ? v.pomoPhase : "focus"
            root.pomoCycle = Math.max(0, Math.floor(Number(v.pomoCycle) || 0))
            root.pomoOn = v.pomoOn === true && ((v.timerRunning && root.timerEnd > now) || v.timerPaused === true)
            if (v.timerPaused === true) {
                // Paused stays paused, with what was left.
                root.timerRunning = false
                root.timerEnd     = 0
                root.timerPaused  = true
                root.timerLeftMs  = Math.max(0, Number(v.timerLeftMs) || 0)
                root.timerDone    = false
                root.timerRemain  = Math.ceil(root.timerLeftMs / 1000)
            } else if (v.timerRunning && root.timerEnd > now) {
                root.timerRunning = true
                root.timerDone    = false
                root.timerPaused  = false
                root.timerRemain  = Math.max(1, Math.round((root.timerEnd - now) / 1000))
            } else if (v.timerRunning && root.timerEnd > 0) {
                // Finished while we were down — show done, but don't fire a notification
                // for a moment that has already passed.
                root.timerRunning = false
                root.timerEnd     = 0
                root.timerDone    = true
                root.timerRemain  = 0
            } else {
                root.timerRunning = false
                root.timerDone    = v.timerDone ?? false
                root.timerRemain  = 0
            }

            // ── Stopwatch: a running one kept measuring wall time ──────────────
            if (v.swRunning) {
                root.swStart   = v.swStart ?? now
                root.swRunning = true
                root.swElapsed = root.swAccum + (now - root.swStart)
            } else {
                root.swStart   = 0
                root.swRunning = false
                root.swElapsed = root.swAccum
            }

            // ── Alarms: disarm any whose time slipped past while we were down ──
            const src = Array.isArray(v.alarms) ? v.alarms : []
            // A repeating one just moves to its next day, without a word.
            root.alarms = src.map(a => {
                if (!a) return a
                const days = AL.cleanMask(a.days)
                // A snooze that came due while we were down is dropped, not rung late.
                a = Object.assign({}, a, { snoozeAt: (a.snoozeAt || 0) > now ? a.snoozeAt : 0 })
                if (a.enabled && a.at <= now)
                    return days ? { id: a.id, h: a.h, m: a.m, enabled: true, days: days, at: root._nextOccurrence(a.h, a.m, days) }
                                : { id: a.id, h: a.h, m: a.m, enabled: false, days: 0, at: a.at }
                return Object.assign({}, a, { days: days })
            })

            root._loading = false
        }
    }

    function _persist() {
        if (root._loading) return
        // Any persist is a user action (mutators and the running tick call it, onLoaded
        // never does), so it marks live state authoritative — even if the store isn't
        // ready yet to actually write.
        root._touched = true
        if (!store.ready) return
        store.value = {
            mode: root.mode,
            setH: root.setH, setM: root.setM, setS: root.setS,
            timerEnd: root.timerEnd, timerRunning: root.timerRunning, timerDone: root.timerDone,
            timerPaused: root.timerPaused, timerLeftMs: root.timerLeftMs, timerSpan: root.timerSpan,
            pomoOn: root.pomoOn, pomoPhase: root.pomoPhase, pomoCycle: root.pomoCycle, pomo: root.pomoCfg,
            swStart: root.swStart, swAccum: root.swAccum, swRunning: root.swRunning,
            laps: root.laps,
            alarms: root.alarms, alarmSeq: root._alarmSeq
        }
    }

    onModeChanged: if (!root._loading) root._persist()
}
