pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/weather.js" as W
import "../../services/ics.js" as Ics
import "../../services/holidays.js" as H
import "../../services/dayfacts.js" as Facts
import "../../services/dayplan.js" as Plan
import "../../services/quickadd.js" as Quick
import "../../services/alarms.js" as AL
import "../../services/worldclock.js" as Z

// ── ClockPanel ────────────────────────────────────────────────────────────────
// The clock pill's panel, in two pages, in the recipe the wallpaper, media and colours
// panels wear: a SegmentSwitch for the page, ChipTrays for the actions, flat cards (a
// ground for the content, not a frame round it), pill fields, springs, and every page
// arriving in a cascade (ViewEnter on the cards, PopIn on what is inside them).
//
//   ┌ header (optional) ─────────────────────────────────────────────┐
//   [ Weather | Calendar ]                       [ ↺ Now ] [ °C ⟳ ]
//   ┌ ring │ the hour ─────────────────────────────────────────────┐
//   │      ·  ☁  ☁  ·                 TODAY · NOW                  │
//   │   ·   23:30:41   ·              ☀ 16°                        │
//   │    21  22  now  ↑28° 00         Clear · feels 15°            │
//   │                                 ↑ 28° at 15:00   ↓ 13° at 05:00
//   └───────────────────────────────────────────────────────────────┘
//   ┌ the week, each day a range bar ───────────────────────────────┐
//   (☂ Rain in ~20 min ▁▃▆)  (● Air 29 Fair · ✿ Grass)  (◠ 07:38 ━●─ 20:12)
//
//   ┌ the time, the day ──────────┐ ┌ the month ──────────────────────┐
//   ├ reminders ──────────────────┤ ├ agenda ─────────────────────────┤
//
// ── The header card is a module setting ───────────────────────────────────────
// Config.clockPanelHeader() (Settings → Bar → the Clock module). On, the panel
// opens with the PanelHeader every bar panel uses; off, it goes straight to the
// page switch. The switch row carries back-to-now, the unit and refresh either way,
// so the header never has to own an action.
//
// ── One day on the ring, and which day is never implied ───────────────────────
// The ring holds the 24 hours of ONE day: today's 00–23, or the day picked in the
// week strip. Two earlier versions ran past midnight (a day ahead from now, then
// today and tomorrow together) and read as misleading. Today's past hours are dim;
// any other day is muted; the detail column states the day in words ("TODAY ·
// NOW", "MONDAY · 12:00"). The day's highest and lowest hours are marked on the
// ring and named — with their times — in the column; clicking either turns to it.
//
// Everything is a view over services: Clock, Weather (hours, days, nowcast, the
// condition icons and tints), AirQuality, Calendar, Reminders; non-fetching logic is
// in weather.js and ics.js (tested). The only state here is what's SELECTED: the day,
// where the ring rests, the page, and a calendar day.
//
// ── The ring ──────────────────────────────────────────────────────────────────
// The hours on a horizontal ring seen from slightly above, projected with real
// perspective (ring.project): the near arc is lower, larger and labelled, the
// sides fade, the far side passes behind the time. The hour at the FRONT is the
// hour the detail column describes.
//   · Drag sideways; the column scrubs live. Fling and it coasts; either way it
//     springs onto the nearest hour. Click an hour, or scroll, to turn it; click
//     the time or "Now" to return.
//   · It never drifts on its own, so the front always means something, and at rest
//     nothing animates — the FrameAnimation runs only while a fling coasts. Resting
//     on now, it steps forward with the clock on the hour.
//   · It spins in to where it rests whenever the page is shown (arrive()).
// Markers are positioned by script, not a 3D transform, so the text stays upright.
//
// ── Arriving, every time ──────────────────────────────────────────────────────
// `weatherOn` / `calendarOn` turn true when the page is shown (and once the panel has
// finished being created — `opened`), and each ViewEnter / PopIn in the page plays then,
// so a tab switch is a cascade and not a swap. `lead` holds the very first one back for
// the dock's own opening pause, then drops to 0 so a later tab switch is immediate.
//
// ── The Calendar page is built when first visited ─────────────────────────────
// Its month pager (49 pages, each a 42-cell grid), reminders and agenda are models that
// stay empty until `calendarSeen`: a panel opened on Weather — nearly always — never pays
// for roughly a thousand items it does not show.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: 660
    readonly property int margin: Tokens.spacingLg + 2
    implicitHeight: content.implicitHeight + root.margin * 2

    readonly property color accent: Config.moduleAccent("clock", Colors.of(QsWindow.window).primary)
    // How much another day recedes, everywhere it appears.
    readonly property real otherDay: 0.5

    Component.onCompleted: {
        Clock.acquireSeconds(); Weather.acquire(); AirQuality.acquire(); Calendar.acquire()
        // After creation, not during it: a ViewEnter / PopIn plays when its `active` TURNS true,
        // and a page that starts out shown would otherwise simply be there.
        Qt.callLater(function () { root.opened = true })
        root.refreshBars()
        root.syncAlarmIds()
    }
    Component.onDestruction: {
        Clock.releaseSeconds(); Weather.release(); AirQuality.release(); Calendar.release()
        if (root.clocksSeen) WorldClock.release()
    }

    readonly property date now: Clock.now
    // Keyed to dayStamp, not `now` — `now` ticks every second while this is open.
    readonly property double todayMs: {
        Clock.dayStamp
        const n = new Date()
        return new Date(n.getFullYear(), n.getMonth(), n.getDate()).getTime()
    }
    readonly property string todayDate: Weather.days[0]?.date ?? ""

    // ══ Arriving ══════════════════════════════════════════════════════════════
    property bool opened: false
    // Held for Motion.emphasized first: that's the Accordion's own open pause, and the stagger
    // should play as the content fades in, not behind it. Zero once that has passed.
    property int lead: Motion.emphasized
    Timer {
        running: true
        interval: Motion.emphasized + Motion.spatial * 2
        onTriggered: root.lead = 0
    }

    readonly property bool weatherOn:  root.opened && root.view === "weather"
    readonly property bool calendarOn: root.opened && root.view === "calendar"
    readonly property bool clocksOn:   root.opened && root.view === "clocks"
    // Latches: the Calendar page's heavy models are built from the first visit on.
    property bool calendarSeen: false
    // False for a moment after the Calendar page is shown, so its reminders cascade in WITH the
    // page, but a reminder added later (the whole list is rebuilt) just appears.
    property bool calSettled: false
    Timer {
        id: calSettle
        interval: Motion.emphasized + Motion.spatial * 2
        onTriggered: root.calSettled = true
    }
    // The Clocks page's lists are built from the first visit too, and WorldClock is only asked for
    // offsets (one `date` run) then.
    property bool clocksSeen: false
    onClocksOnChanged: {
        // A planning cursor does not outlive the page: coming back, it is now.
        if (!root.clocksOn) root.planMs = -1
        if (!root.clocksOn || root.clocksSeen) return
        root.clocksSeen = true
        WorldClock.acquire()
    }
    onCalendarOnChanged: {
        if (!root.calendarOn) return
        root.calendarSeen = true
        root.calSettled = false
        calSettle.restart()
    }

    // ══ Selection ═════════════════════════════════════════════════════════════
    property string view:      "weather"   // weather | calendar
    property int    dayIndex:  0           // into Weather.days — the day on the ring
    property double pickedDay: -1          // local-midnight ms clicked on the grid; -1 = upcoming

    // Put day `i` on the ring and rest on its anchor: now on today, midday otherwise.
    function setDay(i) {
        const n = Weather.days.length
        if (n === 0) return
        root.dayIndex = Math.max(0, Math.min(i, n - 1))
        weatherView.ring.snapToSlot(root.anchorFor(root.dayIndex), true)
    }

    function backToNow() {
        root.pickedDay = -1
        calendarView.monthPager.goToday()
        root.setDay(0)
    }

    function pickDay(y, m, d) {
        const ms = new Date(y, m, d).getTime()
        root.selectDay(ms === root.pickedDay ? -1 : ms, ms)
    }
    // Make `ms` the picked day (-1 = none) and let the forecast follow it, as far as it reaches.
    function selectDay(pick, ms) {
        root.pickedDay = pick
        const i = Weather.days.findIndex(x => x.date === Qt.formatDate(new Date(ms), "yyyy-MM-dd"))
        if (i >= 0) root.setDay(i)
    }

    // ══ The Clocks page ═══════════════════════════════════════════════════════
    // Both cards are as tall as the month's, so the three pages are one height.
    readonly property real pageBoxH: calendarView.monthPager.pageH + Tokens.spacingMd * 2

    // The planner: -1 is now; otherwise the instant the rows are showing (dragged to on a ribbon).
    property double planMs: -1
    // The ribbons' window and where now / the cursor sit in it. The window moves only on the hour.
    readonly property double nowMs: { Clock.minutes; return Date.now() }
    readonly property double winStart: Z.windowStart(root.nowMs)
    readonly property real planFrac: ((root.planMs > 0 ? root.planMs : root.nowMs) - root.winStart) / Z.WINDOW_MS
    // The alarm that rings next (of those that are on).
    readonly property var nextAlarm: {
        Timers.alarms
        const on = Timers.alarms.filter(a => a.enabled).sort((x, y) => x.at - y.at)
        return on.length > 0 ? on[0] : null
    }

    property string zoneQuery: ""
    property string zoneError: ""
    readonly property var zoneMatches: {
        WorldClock.allZones
        return WorldClock.search(root.zoneQuery)
    }
    function addZone(zone) {
        root.zoneError = WorldClock.add(zone)
        if (root.zoneError !== "") return
        root.zoneQuery = ""
        clocksView.zoneField.clear()
    }

    property string alarmText: ""
    property int    alarmDays: 0
    property string alarmError: ""
    function addAlarm() {
        const t = Ics.parseTime(root.alarmText)
        if (!t) { root.alarmError = "That isn't a time"; return }
        if (Timers.alarms.length >= 12) { root.alarmError = "That's plenty of alarms — remove one first"; return }
        Timers.addAlarm(t.h, t.m, root.alarmDays)
        root.alarmText = ""
        clocksView.alarmField.clear()
    }
    // The alarms' ids, in order: the list's model. Timers replaces its whole array on every toggle, and a
    // model of the alarms themselves would rebuild every row (and lose the switch's animation); ids
    // change only when one is added or removed, and each row reads its own alarm.
    property var alarmIds: []
    function syncAlarmIds() {
        const ids = Timers.alarms.map(a => a.id)
        if (JSON.stringify(ids) !== JSON.stringify(root.alarmIds)) root.alarmIds = ids
    }
    Connections {
        target: Timers
        function onAlarmsChanged() { root.syncAlarmIds() }
    }
    // Something ringing within the hour, for the tab's lit icon.
    readonly property bool alarmSoon: {
        Clock.minutes
        return Timers.alarms.some(a => a.enabled && a.at - Date.now() < 3600000)
    }

    // ══ Keys ══════════════════════════════════════════════════════════════════
    // Handed over by the dock (EscapeGuard → `handleKey`) only while no text field has focus.
    //   anywhere   Tab / Shift+Tab, 1 2 3: the page · T or Home: back to now
    //   weather    ← →: the hour · ↑ ↓: the day
    //   calendar   ← →: a day · ↑ ↓: a week · PgUp PgDn: a month · N: a new event
    readonly property var pages: ["weather", "calendar", "clocks"]

    function goPage(i) { root.view = root.pages[(i + root.pages.length) % root.pages.length] }

    function movePick(days) {
        const d = new Date(root.agendaFrom)
        const ms = new Date(d.getFullYear(), d.getMonth(), d.getDate() + days).getTime()
        root.selectDay(ms, ms)
        calendarView.monthPager.goToDay(ms)
    }

    function handleKey(e) {
        if (e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        const k = e.key
        if (k === Qt.Key_Tab)     { root.goPage(root.pages.indexOf(root.view) + 1); return true }
        if (k === Qt.Key_Backtab) { root.goPage(root.pages.indexOf(root.view) - 1); return true }
        if (k >= Qt.Key_1 && k < Qt.Key_1 + root.pages.length) { root.goPage(k - Qt.Key_1); return true }
        if (k === Qt.Key_T || k === Qt.Key_Home) { root.backToNow(); return true }

        if (root.view === "weather") {
            if (k === Qt.Key_Left || k === Qt.Key_Right) {
                const n = root.ringHours.length
                if (n > 0) weatherView.ring.snapToSlot(Math.max(0, Math.min(n - 1, root.slot + (k === Qt.Key_Right ? 1 : -1))))
                return true
            }
            if (k === Qt.Key_Up || k === Qt.Key_Down) { root.setDay(root.dayIndex + (k === Qt.Key_Down ? 1 : -1)); return true }
        } else if (root.view === "calendar" && root.calView === "month") {
            if (k === Qt.Key_Left)  { root.movePick(-1); return true }
            if (k === Qt.Key_Right) { root.movePick(1);  return true }
            if (k === Qt.Key_Up)    { root.movePick(-7); return true }
            if (k === Qt.Key_Down)  { root.movePick(7);  return true }
            if (k === Qt.Key_PageUp)   { calendarView.monthPager.step(-1); return true }
            if (k === Qt.Key_PageDown) { calendarView.monthPager.step(1);  return true }
            if (k === Qt.Key_N || k === Qt.Key_Insert) { if (Calendar.localWritable) root.openEditor("", root.agendaFrom); return true }
        }
        return false
    }

    // Escape leaves the event editor before it closes the panel.
    function handleEscape() {
        if (root.calView !== "edit") return false
        root.calView = "month"
        return true
    }

    // ══ Weather ═══════════════════════════════════════════════════════════════
    readonly property var    day:     Weather.days[root.dayIndex] ?? null
    readonly property string dayDate: root.day ? root.day.date : ""
    readonly property bool   onToday: root.dayDate !== "" && root.dayDate === root.todayDate

    // The ring's hours — the chosen day's 24, and nothing past its midnight:
    // [{ index, hour }], `hour` copied so a delegate never indexes into an array
    // that was replaced under it.
    readonly property var ringHours: {
        const hs = Weather.hours
        if (hs.length === 0 || root.dayDate === "") return []
        const out = []
        for (let i = 0; i < hs.length; i++)
            if (hs[i].date === root.dayDate) out.push({ index: i, hour: hs[i] })
        return out
    }

    function slotOf(hour) { return root.ringHours.findIndex(x => x.hour.hour === hour) }
    function anchorFor(i) {
        const k = root.slotOf(i === 0 ? Clock.hours : 12)
        return k < 0 ? 0 : k
    }

    // The current hour's slot, or -1 while another day is on the ring.
    readonly property int nowSlot: root.onToday ? root.slotOf(Clock.hours) : -1

    // The day's warmest and coolest hours, as slots.
    readonly property int maxSlot: {
        let k = -1
        for (let i = 0; i < root.ringHours.length; i++)
            if (k < 0 || root.ringHours[i].hour.tempC > root.ringHours[k].hour.tempC) k = i
        return k
    }
    readonly property int minSlot: {
        let k = -1
        for (let i = 0; i < root.ringHours.length; i++)
            if (k < 0 || root.ringHours[i].hour.tempC < root.ringHours[k].hour.tempC) k = i
        return k
    }

    // The slot being described: the one at the front while it moves, else the locked one.
    readonly property int  slot: weatherView.ring.interacting ? weatherView.ring.frontSlot : weatherView.ring.lockedSlot
    readonly property var  frontHour: root.ringHours[Math.min(root.slot, root.ringHours.length - 1)]?.hour ?? null
    readonly property bool describingNow: root.nowSlot >= 0 && root.slot === root.nowSlot

    // At rest on the present. Reads the SETTLED position only, never "is it moving":
    // tying it to motion flipped it on every scroll notch and spring.
    readonly property bool atNow: root.dayIndex === 0
                               && (root.nowSlot < 0 || weatherView.ring.lockedSlot === root.nowSlot)
                               && root.pickedDay < 0 && calendarView.monthPager.atToday

    // Resting on now when the hour turns over: step forward with the clock. Also
    // catches the first data arriving after the panel opened.
    property int _lastNow: -1
    onNowSlotChanged: {
        if (root.nowSlot >= 0 && !weatherView.ring.interacting
                && (root._lastNow < 0 || weatherView.ring.lockedSlot === root._lastNow))
            weatherView.ring.snapToSlot(root.nowSlot, root._lastNow < 0)
        root._lastNow = root.nowSlot
    }

    readonly property var detail: {
        if (!Weather.ready) return null
        // The current hour on today is "now": the live observation, not the forecast.
        if (root.describingNow)
            return { tempC: Weather.tempC, feelsC: Weather.feelsC, humidity: Weather.humidity,
                     windKph: Weather.windKph, windDir: Weather.windDir,
                     precip: Weather.hourlyPrecip[0] ?? 0, precipMm: Weather.precipMm,
                     uv: Weather.uv, code: Weather.code, isDay: Weather.isDay,
                     hour: Clock.hours, date: root.todayDate }
        return root.frontHour
    }

    function dayShort(date) {
        if (date === root.todayDate) return "Today"
        return Qt.formatDate(new Date(date + "T12:00:00"), "ddd")
    }
    function dayWord(date) {
        const i = Weather.days.findIndex(x => x.date === date)
        if (i === 0) return "Today"
        if (i === 1) return "Tomorrow"
        return Qt.formatDate(new Date(date + "T12:00:00"), "dddd")
    }

    // The palette's pass/caution/alarm roles for a UV or air-quality band. Wording
    // comes from weather.js; this is only which colour that wording wears.
    function uvTint(uv) {
        return uv < 3 ? Colors.of(QsWindow.window).success : uv < 6 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).danger
    }
    function aqiTint(aqi) {
        return aqi <= 40 ? Colors.of(QsWindow.window).success : aqi <= 60 ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).danger
    }

    // The sun, for the day on the ring: 0..1 through the daylight, or -1 outside it
    // or on any day but today. Per MINUTE (Clock.minutes), not per second: the sun does not
    // move a pixel in a second, and this object was being rebuilt — and every text bound to
    // it re-evaluated — sixty times a minute for nothing.
    readonly property var sun: {
        Clock.minutes
        const d = root.day
        if (!d || !d.sunrise || !d.sunset) return null
        const rise = new Date(d.sunrise).getTime(), set = new Date(d.sunset).getTime()
        const t = Date.now()
        const frac = root.onToday && t >= rise && t <= set ? (t - rise) / (set - rise) : -1
        return { rise: d.sunrise.slice(11, 16), set: d.sunset.slice(11, 16), frac: frac,
                 left: frac >= 0 ? W.duration((set - t) / 1000) : "",
                 length: d.daylightS > 0 ? W.duration(d.daylightS) : "" }
    }

    // The week's coolest and warmest, so each day's range bar sits where it belongs on ONE scale.
    readonly property var weekRange: {
        const ds = Weather.days
        if (ds.length === 0) return { lo: 0, hi: 1 }
        let lo = ds[0].minC, hi = ds[0].maxC
        for (let i = 1; i < ds.length; i++) { lo = Math.min(lo, ds[i].minC); hi = Math.max(hi, ds[i].maxC) }
        return { lo: lo, hi: hi > lo ? hi : lo + 1 }
    }

    // ── The day's rain, hour by hour ──────────────────────────────────────────
    // What the hourly forecast means, in words (weather.js planner, tested): on today, how long the
    // weather you are in lasts; on any other day, its wet stretches.
    readonly property string rainPlan: {
        if (!Weather.ready || root.dayDate === "") return ""
        if (root.onToday) {
            const w = W.dryWindow(Weather.hours, root.todayDate, Clock.hours)
            return w ? w.text : ""
        }
        return W.rainSpans(root.ringHours.map(x => x.hour)).text
    }
    // The hour before sunset, for the day on the ring. Per minute: it goes live and then over.
    readonly property var golden: {
        Clock.minutes
        return root.day ? W.goldenHour(root.day.sunrise, root.day.sunset, root.onToday ? Date.now() : -1) : null
    }

    // ── The rain, quarter hour by quarter hour ────────────────────────────────
    // Weather.nowcast already says it in words; the bars are the same slots (weather.js, tested).
    // Replaced only when the picture changes — a fresh array each minute would rebuild every
    // bar and replay its spring for nothing.
    property var nowcastBars: []
    function refreshBars() {
        const next = W.bars(Weather.minutely, Date.now(), 12)
        if (JSON.stringify(next) !== JSON.stringify(root.nowcastBars)) root.nowcastBars = next
    }
    Connections {
        target: Clock
        function onMinutesChanged() { root.refreshBars() }
    }
    Connections {
        target: Weather
        function onMinutelyChanged() { root.refreshBars() }
    }
    // Something worth looking at on the Weather tab while on the other.
    readonly property bool rainSoon: Weather.nowcast !== null && Weather.nowcast.state !== "dry"

    // ══ Calendar ══════════════════════════════════════════════════════════════
    // The Calendar page: months scrolling downwards, the special dates of your
    // weather location's country, and your own events. Dates come from the Calendar
    // service (Nager.Date, classified by holidays.js); events are a local .ics file.
    // This page only collects a draft and hands it over — the service validates and
    // writes.
    property string calView: "month"      // month | edit

    // Your events' colour: a palette role, the accent if it isn't one.
    readonly property color eventColor: Colors.of(QsWindow.window).role(Config.calendarLocalColor, root.accent)

    // The colour of an event's source: yours, or a subscribed feed's own (Calendar.feeds).
    function sourceColor(source) {
        return Colors.of(QsWindow.window).role(Calendar.feedRole(source), root.eventColor)
    }

    // How loudly a special date is marked — the same scale the month grid uses.
    function specialTint(kind) {
        return kind === "national" ? Colors.of(QsWindow.window).warning
             : kind === "regional" ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).warning, Colors.of(QsWindow.window).fgMuted, 0.45)
             :                       Colors.of(QsWindow.window).info
    }
    function specialIcon(kind) {
        return kind === "national" ? "celebration" : kind === "regional" ? "flag" : "star"
    }

    // The agenda starts at the picked day, or today, and looks three weeks ahead: the
    // first day always, later days only when they hold a special date or an event.
    readonly property double agendaFrom: root.pickedDay >= 0 ? root.pickedDay : root.todayMs
    readonly property var agenda: {
        Calendar.occurrences
        Calendar.special
        const s = new Date(root.agendaFrom)
        const out = []
        for (let k = 0; k < 21; k++) {
            const day = new Date(s.getFullYear(), s.getMonth(), s.getDate() + k)
            const y = day.getFullYear(), m = day.getMonth(), d = day.getDate()
            const items = Calendar.eventsOn(y, m, d)
            const specials = Calendar.specialOn(y, m, d)
            if (k === 0 || items.length > 0 || specials.length > 0)
                out.push({ day: day.getTime(), items: items, specials: specials })
        }
        return out
    }

    function dayTitle(ms) {
        const diff = Math.round((ms - root.todayMs) / 86400000)
        const rel = diff === 0 ? "Today" : diff === 1 ? "Tomorrow" : diff === -1 ? "Yesterday"
                  : Qt.formatDate(new Date(ms), "dddd")
        return rel + "  ·  " + Qt.formatDate(new Date(ms), "d MMM")
    }

    // "Implantação da República · 5 Oct · in 22 days"
    readonly property string nextSpecialText: {
        const n = Calendar.nextSpecial
        if (!n) return ""
        const days = Math.round((n.day - root.todayMs) / 86400000)
        return n.entries[0].name + "  ·  " + Qt.formatDate(new Date(n.day), "d MMM") + "  ·  "
             + (days === 0 ? "today" : days === 1 ? "tomorrow" : "in " + days + " days")
    }

    // The next TIMED event, running now or inside a day and a half (ics.js, tested). Per minute.
    readonly property var nextUp: {
        Clock.minutes
        return Ics.nextUp(Calendar.occurrences, Date.now(), 36 * 3600000)
    }

    // Week, and the moon, for the Calendar page's date line. Keyed to the day.
    readonly property var dayFacts: {
        Clock.dayStamp
        const n = Date.now()
        return { week: Facts.isoWeek(n), moon: Facts.moon(n) }
    }

    // ── The day strip ─────────────────────────────────────────────────────────
    // The agenda's day laid out on 24 hours (dayplan.js, tested): the timed events as bars, in lanes
    // when they overlap, "now" on today, and a line saying whether you are free. Follows the picked day.
    readonly property var dayBox: {
        const d = new Date(root.agendaFrom)
        return Plan.dayBounds(d.getFullYear(), d.getMonth(), d.getDate())
    }
    readonly property var dayOcc: {
        Calendar.occurrences
        const d = new Date(root.agendaFrom)
        return Calendar.eventsOn(d.getFullYear(), d.getMonth(), d.getDate())
    }
    readonly property var dayStrip: Plan.layout(root.dayOcc, root.dayBox.start, root.dayBox.end, 2)
    readonly property real nowFrac: {
        Clock.minutes
        return Plan.nowFraction(Date.now(), root.dayBox.start, root.dayBox.end)
    }
    readonly property string stripLabel: {
        Clock.minutes
        const hm = (ms) => Qt.formatTime(new Date(ms), "HH:mm")
        const n = root.dayStrip.length
        if (root.agendaFrom === root.todayMs) {
            const st = Plan.status(root.dayOcc, Date.now())
            if (st.busy) return "Busy until " + hm(st.until)
            if (st.until !== null) return "Free until " + hm(st.until)
            return n > 0 ? "Free for today" : "Nothing timed today"
        }
        if (n === 0) return "Nothing timed"
        const span = root.dayBox.end - root.dayBox.start
        return n + (n === 1 ? " event" : " events") + " · from " + hm(root.dayBox.start + root.dayStrip[0].start * span)
    }

    readonly property string headerSubtitle: {
        if (root.view === "clocks") {
            const on = Timers.alarms.filter(a => a.enabled).length
            return (WorldClock.zones.length === 0 ? "Just here" : (WorldClock.zones.length + 1) + " places")
                 + "  ·  " + (on === 0 ? "no alarms on" : on + (on === 1 ? " alarm on" : " alarms on"))
        }
        if (root.view === "calendar") {
            const parts = [Qt.formatDate(root.now, "dddd, d MMMM")]
            const today = Calendar.specialOn(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())
            if (today.length) parts.push(today[0].name)
            return parts.join("  ·  ")
        }
        return Weather.hasLocation ? Weather.place : "No location set"
    }

    // ── Reminders' quick-add ──────────────────────────────────────────────────
    // The field and the "when" chips write here; Reminders.add/addAt validate. "At…"
    // takes a typed time on the agenda's day (the picked day, or today).
    readonly property int maxReminders: 30
    property string reminderText:  ""
    property string reminderWhen:  "hour"     // "" | hour | evening | tomorrow | at
    property string reminderTime:  ""
    property string reminderError: ""

    // The "when" chip steps through these, one per click — a row of five chips was a whole line of the
    // card for a choice made once in a while.
    readonly property var whenChoices: [
        { value: "hour",     label: "In 1 h"   },
        { value: "evening",  label: "Tonight"  },
        { value: "tomorrow", label: "Tomorrow" },
        { value: "at",       label: "At…"      },
        { value: "",         label: "No time"  }
    ]
    readonly property string whenLabel: (root.whenChoices.find(c => c.value === root.reminderWhen) ?? root.whenChoices[0]).label
    // ── What the line says ────────────────────────────────────────────────────
    // The text is read as you type (quickadd.js, tested). A day or a time in it makes it an EVENT
    // (or, by the chip, a reminder at that moment); no day or time, and it is the plain reminder it
    // always was, timed by the "when" chip. `quickKind` is the chip's choice; a repeat has no
    // reminder form, so it forces an event.
    property string quickKind: "event"
    property string quickFlash: ""
    readonly property var quick: {
        Clock.minutes
        return Quick.parse(root.reminderText, Date.now())
    }
    readonly property bool quickParsed: root.reminderText.trim() !== "" && root.quick.start !== null
    readonly property string quickAs: root.quick.repeat !== "" ? "event" : root.quickKind
    readonly property string quickPreview: {
        if (!root.quickParsed) return ""
        if (!root.quick.ok) return "Add a title"
        return (root.quickAs === "event" ? "Event" : "Reminder") + "  ·  " + Quick.describe(root.quick, Date.now())
    }
    Timer { id: quickFlashTimer; interval: 2400; onTriggered: root.quickFlash = "" }

    function _hm(ms) { const d = new Date(ms); return Clock.pad(d.getHours()) + ":" + Clock.pad(d.getMinutes()) }

    // Enter, or the check: what the line says if it says a moment, else the plain reminder.
    function submitQuick() {
        if (!root.quickParsed) { root.addReminder(); return }
        const q = root.quick
        if (!q.ok) { root.reminderError = "Add a title"; return }
        const d = new Date(q.start)
        const dayMs = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
        let err
        if (root.quickAs === "event") {
            err = Calendar.saveLocal({ uid: "", summary: q.summary, location: "", day: dayMs, allDay: q.allDay,
                                       startTime: q.allDay ? "" : root._hm(q.start),
                                       endTime:   q.allDay ? "" : root._hm(q.end), repeat: q.repeat })
        } else {
            // A reminder with a day and no hour goes off at nine.
            err = Reminders.addDue(q.summary, q.allDay ? dayMs + 9 * 3600000 : q.start)
        }
        root.reminderError = err
        if (err !== "") return
        root.quickFlash = (root.quickAs === "event" ? "Added to your calendar" : "Reminder set") + "  ·  " + Quick.describe(q, Date.now())
        quickFlashTimer.restart()
        root.reminderText = ""
        calendarView.reminderField.clear()
        // Show it: the month and the agenda turn to the day it landed on.
        if (root.quickAs === "event") { root.pickedDay = dayMs; calendarView.monthPager.goToDay(dayMs) }
    }

    function cycleWhen() {
        const i = root.whenChoices.findIndex(c => c.value === root.reminderWhen)
        root.reminderWhen = root.whenChoices[(i + 1) % root.whenChoices.length].value
        root.reminderError = ""
        if (root.reminderWhen === "at") Qt.callLater(() => calendarView.reminderTimeField.forceFocus())
    }

    function addReminder() {
        root.reminderError = root.reminderWhen === "at"
            ? Reminders.addAt(root.reminderText, root.agendaFrom, root.reminderTime)
            : Reminders.add(root.reminderText, root.reminderWhen)
        if (root.reminderError !== "") return
        root.reminderText = ""
        root.reminderTime = ""
        calendarView.reminderField.clear()
        calendarView.reminderTimeField.clear()
    }

    // ── The editor's draft ────────────────────────────────────────────────────
    // Plain properties the fields write per keystroke. Nothing is checked until
    // Save, and then by Ics.validateEvent — so nothing half-typed reaches the file.
    property string draftUid:      ""
    property double draftDay:      0
    property bool   draftAllDay:   false
    property string draftSummary:  ""
    property string draftStart:    ""
    property string draftEnd:      ""
    property string draftLocation: ""
    property string draftRepeat:   ""
    property string draftError:    ""

    // uid "" → a new event on `dayMs`; otherwise your event with that UID. A repeating
    // event opens on its FIRST day, because the series is what's being edited.
    function openEditor(uid, dayMs) {
        const ev = uid !== "" ? Calendar.localEvent(uid) : null
        if (ev) {
            const s = new Date(ev.start)
            root.draftUid      = ev.uid
            root.draftDay      = new Date(s.getFullYear(), s.getMonth(), s.getDate()).getTime()
            root.draftAllDay   = ev.allDay
            root.draftSummary  = ev.summary
            root.draftLocation = ev.location
            root.draftStart    = ev.allDay ? "" : Qt.formatTime(s, "HH:mm")
            root.draftEnd      = ev.allDay ? "" : Qt.formatTime(new Date(ev.end), "HH:mm")
            root.draftRepeat   = ev.rrule ? ev.rrule.freq : ""
        } else {
            // The next whole hour, an hour long — the likeliest thing to be adding.
            const h = Math.min(22, Clock.hours + 1)
            root.draftUid      = ""
            root.draftDay      = dayMs
            root.draftAllDay   = false
            root.draftSummary  = ""
            root.draftLocation = ""
            root.draftStart    = Clock.pad(h) + ":00"
            root.draftEnd      = Clock.pad(h + 1) + ":00"
            root.draftRepeat   = ""
        }
        root.draftError = ""
        calendarView.deleteLatch.disarm()
        // setText, not seed: re-opening on the same values must still fill the boxes.
        calendarView.titleField.setText(root.draftSummary)
        calendarView.startField.setText(root.draftStart)
        calendarView.endField.setText(root.draftEnd)
        calendarView.locationField.setText(root.draftLocation)
        root.calView = "edit"
        // The month turns to the event's own, so its day is there to be seen.
        calendarView.monthPager.goToDay(root.draftDay)
        Qt.callLater(() => calendarView.titleField.forceFocus())
    }

    // The date is chosen on the month beside the editor, not typed or stepped.
    function setDraftDay(y, m, d) { root.draftDay = new Date(y, m, d).getTime() }

    function saveDraft() {
        root.draftError = Calendar.saveLocal({
            uid: root.draftUid, summary: root.draftSummary, location: root.draftLocation,
            day: root.draftDay, allDay: root.draftAllDay,
            startTime: root.draftStart, endTime: root.draftEnd, repeat: root.draftRepeat
        })
        if (root.draftError === "") root.calView = "month"
    }

    function deleteDraft() {
        root.draftError = Calendar.deleteLocal(root.draftUid)
        if (root.draftError === "") root.calView = "month"
    }

    // The refresh glyph turns while anything is fetching. `pulse`, not a switchable
    // duration: it's a busy signal, and a still icon says nothing.
    property real refreshPhase: 0
    readonly property bool refreshing: Weather.loading || AirQuality.loading || Calendar.loading
    NumberAnimation on refreshPhase {
        running: root.refreshing
        from: 0; to: 360
        duration: Motion.pulse * 2
        loops: Animation.Infinite
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Anchored top/left/right, not fill — the card animates its height around this.
    ColumnLayout {
        id: content
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingMd

        // ── Header card — a Clock module setting ──────────────────────────────
        PanelHeader {
            visible: Config.clockPanelHeader()
            Layout.fillHeight: false
            Layout.bottomMargin: Tokens.spacingXs
            glyph:     "󰃭"
            symbol:    root.view === "calendar" ? "calendar_month" : root.view === "clocks" ? "public" : "partly_cloudy_day"
            title:     Translation.tr("Clock")
            titleTail: root.view === "calendar" ? "& Calendar" : root.view === "clocks" ? "& World" : "& Weather"
            accent:    root.accent
            subtitle:  root.headerSubtitle
        }

        // ══ Pages │ back to now │ unit, refresh ═══════════════════════════════
        RowLayout {
            id: topRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            // 0: the gaps belong to the Now slot and the tray, so the one before Now can shrink
            // away with it.
            spacing: 0
            opacity: 0
            ViewEnter { target: topRow; active: root.opened; delay: root.lead; rise: Tokens.spacingMd }

            // `lit`: an icon filled in the accent while NOT the chosen page — something is live
            // over there (rain on its way; a reminder overdue or an event under way).
            SegmentSwitch {
                Layout.fillWidth: true
                Layout.fillHeight: false
                accent:  root.accent
                current: root.view
                model: [
                    { value: "weather",  label: "Weather",  icon: "partly_cloudy_day", lit: root.rainSoon },
                    { value: "calendar", label: "Calendar", icon: "calendar_month",
                      lit: Reminders.overdueCount > 0 || (root.nextUp !== null && root.nextUp.live) },
                    { value: "clocks",   label: "Clocks",   icon: "public", lit: root.alarmSoon }
                ]
                onPicked: (value) => root.view = value
            }

            // ── Back to now ───────────────────────────────────────────────────
            // Opens beside the switch, which gives up exactly the room it takes. What made
            // the row shake was never the resize: `atNow` flipped on every scroll notch and
            // settling spring, and each flip restarted the width animation. It now only
            // reacts once `atNow` has HELD for a moment, so a scroll passes straight through
            // now, and the width eases on one curve. The gap before it scales with it, so
            // closing doesn't jump by a spacing.
            Item {
                id: nowHolder
                property real reveal: nowHolder.shown ? 1 : 0
                Behavior on reveal {
                    NumberAnimation {
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                    }
                }
                visible: reveal > 0
                clip: true
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                // The tray's height, not the chip's: the clip must leave room for the chip's lean.
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                Layout.preferredWidth:  (nowButton.implicitWidth + Tokens.spacingSm + Tokens.spacingXs) * reveal

                property bool shown: false
                Timer {
                    id: nowSettle
                    interval: Motion.emphasized
                    onTriggered: nowHolder.shown = !root.atNow
                }
                Connections {
                    target: root
                    function onAtNowChanged() { nowSettle.restart() }
                }

                // The chip owns its own scale (the lean), so the arrival sits on a wrapper.
                Item {
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width:  nowButton.implicitWidth
                    height: nowButton.implicitHeight
                    opacity: nowHolder.shown ? 1 : 0
                    scale:   nowHolder.shown ? 1 : 0.85
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                    Behavior on scale {
                        NumberAnimation {
                            duration: Motion.spatial
                            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                        }
                    }

                    ChipButton {
                        id: nowButton
                        symbol:  "history"
                        label:   Translation.tr("Now")
                        on:      true
                        tint:    root.accent
                        enabled: nowHolder.shown
                        onActivated: root.backToNow()
                    }
                }
            }

            // Its own tray, beside the switch — not joined to it. The unit stays on both pages (the
            // Calendar's today card shows a temperature too), which also keeps the switch the same
            // width on a tab change.
            ChipTray {
                Layout.leftMargin: Tokens.spacingSm

                ChipButton {
                    label:   Weather.metric ? "°C" : "°F"
                    labelVariant: "title"
                    tint:    root.accent
                    onActivated: Config.weatherMetric = !Config.weatherMetric
                }
                ChipButton {
                    symbol:  "refresh"
                    tint:    root.accent
                    iconAngle: root.refreshing ? root.refreshPhase : 0
                    enabled: !root.refreshing
                    onActivated: { Weather.refresh(); AirQuality.refresh(); Calendar.refresh() }
                }
            }
        }

        // ══ Views ═════════════════════════════════════════════════════════════
        // Both exist; the one on show sets the height. A switch crossfades and
        // slides a short way toward the side its tab is on.
        Item {
            id: views
            Layout.fillWidth: true
            Layout.preferredHeight: root.view === "calendar" ? calendarView.implicitHeight
                                  : root.view === "clocks"   ? clocksView.implicitHeight
                                  :                            weatherView.implicitHeight

            // ══ WEATHER — ClockWeatherView.qml ══
            ClockWeatherView { id: weatherView; panel: root }

            // ══ CALENDAR — ClockCalendarView.qml ══
            ClockCalendarView { id: calendarView; panel: root }

            // ══ CLOCKS — ClockClocksView.qml ══
            ClockClocksView { id: clocksView; panel: root }

        }
    }
}
