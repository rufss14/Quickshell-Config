pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "weather.js" as W

// ── Weather ───────────────────────────────────────────────────────────────────
// Current conditions and a short forecast, for the desktop weather widget.
//
// ── The one service here that leaves the machine, besides SpeedTest ───────────
// It talks to Open-Meteo (open-meteo.com), chosen for three reasons that were checked
// against the live API before any of this was written:
//
//   • No API key and no account. Every alternative worth using wants one, which would
//     mean a credential in the config and a signup before the widget works at all.
//   • A separate GEOCODING endpoint, so "where am I" can be a city you TYPE rather
//     than an IP lookup. That was the user's explicit choice: nothing here ever asks a
//     third party to infer your location — the only request is a forecast for a fixed
//     coordinate you set yourself.
//   • `is_day` in the response, so the icon can be honest about night without the
//     shell having to compute sunrise.
//
// ── Fetching is on demand and cached, never a poll ────────────────────────────
// Weather changes on the order of tens of minutes, so a timer hammering an endpoint
// would be pure waste. It refreshes when the widget first appears and then at
// `refreshMins`, and only while something is actually watching (`refcount`). A desktop
// with no weather widget makes no requests, ever.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── What the widget reads ─────────────────────────────────────────────────
    property bool  ready:    false
    property bool  loading:  false
    property string error:   ""

    property real   tempC:      0
    property real   feelsC:     0
    property int    humidity:   0
    property real   windKph:    0
    property int    code:       0      // WMO weather code
    property bool   isDay:      true
    property string observedAt: ""
    property int    windDir:    0      // degrees, meteorological (where it blows FROM)
    property real   gustKph:    0
    property real   precipMm:   0      // in the current interval
    property real   uv:         0

    // ── Rain nowcast ──────────────────────────────────────────────────────────
    // The next three hours in 15-minute slots ([{ t, mm, snowCm }]), and the
    // sentence weather.js makes of them — "Light rain starting in ~20 min". Re-read
    // each minute against the clock, so the countdown moves between fetches; only a
    // changed sentence is published. null when there's nothing to say.
    property var minutely: []
    property var nowcast:  null

    function _updateNowcast() {
        const next = W.nowcast(root.minutely, Date.now())
        if (JSON.stringify(next) !== JSON.stringify(root.nowcast)) root.nowcast = next
    }
    Connections {
        target: Clock
        function onMinutesChanged() { root._updateNowcast() }
    }

    // [{ date, code, maxC, minC }] — today first.
    property var days: []

    // ── Next 24 hours ────────────────────────────────────────────────────────
    // Sliced to start at the current hour and forward — Open-Meteo returns the
    // whole day from 00:00, most of which is in the past by the afternoon. Plain
    // arrays of numbers, for a sparkline. Empty from an older cached response, so
    // consumers check length.
    property var hourlyTemps:  []
    property var hourlyPrecip: []
    property var hourlyHours:   []   // "14", "15", … for axis labels

    // ── Every hour of every forecast day ─────────────────────────────────────
    // The clock panel pages through days and shows any hour in full, so it needs the
    // whole series, not the next-24h slice above (which the desktop widget's
    // sparkline still reads). [{ date: "YYYY-MM-DD", hour, tempC, feelsC, humidity,
    // windKph, precip, code, isDay }], in order. Same request — only more columns.
    property var hours: []
    // Index into `hours` of the current hour — where "the next few hours" starts.
    property int hoursStart: 0

    function hoursFor(date) { return root.hours.filter(h => h.date === date) }

    // ── Location ──────────────────────────────────────────────────────────────
    // Held here, written by the settings page. Coordinates are the source of truth and
    // `place` is only a label: a city name would have to be re-geocoded on every fetch,
    // and the endpoint takes numbers anyway.
    property real   lat:   Config.weatherLat
    property real   lon:   Config.weatherLon
    property string place: Config.weatherPlace
    readonly property bool hasLocation: Config.weatherPlace !== ""

    // Celsius unless told otherwise. Converted for DISPLAY only — the store always
    // holds metric, so flipping the unit can't lose precision or need a refetch.
    readonly property bool metric: Config.weatherMetric

    readonly property int refreshMins: 20

    function temp(c) {
        return root.metric ? Math.round(c) : Math.round(c * 9 / 5 + 32)
    }
    readonly property string unit: root.metric ? "°C" : "°F"

    function wind(kph) {
        return root.metric ? Math.round(kph) + " km/h"
                           : Math.round(kph * 0.621371) + " mph"
    }

    // ── Refcount ──────────────────────────────────────────────────────────────
    // Same contract as NetStats and Cava: a widget acquires while it exists and
    // releases when it goes. Nothing fetches for a widget nobody has placed.
    property int _refs: 0
    // When the last successful parse landed, epoch ms. Lets a returning consumer tell
    // "loaded" from "loaded hours ago": the desktop tiles now release while a
    // fullscreen window covers them, and a game outlasts the poll by hours — `ready`
    // alone would put the forecast from before the game back on screen for another
    // full interval.
    property double _fetchedAt: 0
    function acquire() {
        root._refs++
        if (root._refs === 1) {
            if (!root.ready || Date.now() - root._fetchedAt > root.refreshMins * 60 * 1000)
                root.refresh()
            poll.start()
        }
    }
    function release() {
        root._refs = Math.max(0, root._refs - 1)
        if (root._refs === 0) poll.stop()
    }

    Timer {
        id: poll
        interval: root.refreshMins * 60 * 1000
        repeat: true
        onTriggered: root.refresh()
    }

    // Moving the pin must not leave yesterday's city on screen. Clearing `ready` first
    // is what makes the widget show its loading state rather than stale numbers for
    // somewhere you no longer live.
    onLatChanged: root._relocate()
    onLonChanged: root._relocate()
    function _relocate() {
        root.ready = false
        root.days  = []
        root.hours = []
        if (root._refs > 0) root.refresh()
    }

    // ── The fetch ─────────────────────────────────────────────────────────────
    function refresh() {
        if (!root.hasLocation || fetch.running) return
        root.loading = true
        root.error   = ""
        fetch.command = ["curl", "-fsS", "--max-time", "20", "--compressed", root._url()]
        fetch.running = true
    }

    function _url() {
        // Built from NUMBERS, so there is nothing here a hostile string could escape
        // into. `timezone=auto` makes the daily buckets line up with the user's day
        // rather than UTC's — without it "tomorrow" is wrong for half the planet.
        return "https://api.open-meteo.com/v1/forecast"
             + "?latitude="  + root.lat.toFixed(4)
             + "&longitude=" + root.lon.toFixed(4)
             + "&current=temperature_2m,relative_humidity_2m,apparent_temperature"
             + ",is_day,weather_code,wind_speed_10m"
             + ",wind_direction_10m,wind_gusts_10m,precipitation,uv_index"
             // Three hours of quarter-hour precipitation, for the nowcast.
             + "&minutely_15=precipitation,snowfall&forecast_minutely_15=12"
             // Seven days, so the large tile's forecast list fills its height with real
             // days rather than padding. Costs nothing extra — same request either way.
             // `sunrise`/`sunset` come back as local ISO timestamps under the same
             // `timezone=auto` the buckets use, so the sun tile needs no astronomy of
             // its own — which is the whole reason this endpoint was picked.
             + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             + ",sunrise,sunset"
             + ",uv_index_max,precipitation_probability_max,precipitation_sum,daylight_duration"
             // The next-24h strip the medium/large tile draws as a sparkline.
             // Same request, ~1KB more — cheaper than a second round trip.
             + "&hourly=temperature_2m,precipitation_probability"
             // The rest is for the clock panel's per-hour detail (Weather.hours).
             + ",weather_code,is_day,relative_humidity_2m,wind_speed_10m,apparent_temperature"
             + ",uv_index,wind_direction_10m,wind_gusts_10m,precipitation"
             + "&timezone=auto&forecast_days=7"
    }

    Process {
        id: fetch
        stdout: StdioCollector { id: fetchOut }
        stderr: StdioCollector { id: fetchErr }
        onExited: function (exitCode) {
            root.loading = false
            if (exitCode !== 0) {
                // Named plainly. "Weather unavailable" with no reason is the kind of
                // dead widget you can't tell from a broken one — and the overwhelmingly
                // likely cause is simply being offline.
                root.error = "Couldn't reach the weather service"
                console.warn("Weather: curl exited", exitCode, fetchErr.text.trim())
                return
            }
            root._parse(fetchOut.text)
        }
    }

    function _parse(txt) {
        try {
            const d = JSON.parse(txt)
            const c = d.current
            root.tempC      = c.temperature_2m
            root.feelsC     = c.apparent_temperature
            root.humidity   = c.relative_humidity_2m
            root.windKph    = c.wind_speed_10m
            root.code       = c.weather_code
            root.isDay      = c.is_day === 1
            root.observedAt = c.time
            root.windDir    = c.wind_direction_10m ?? 0
            root.gustKph    = c.wind_gusts_10m ?? 0
            root.precipMm   = c.precipitation ?? 0
            root.uv         = c.uv_index ?? 0

            // Local ISO times (timezone=auto), read as local — same assumption the
            // hourly block makes.
            const mq = d.minutely_15
            root.minutely = (mq && mq.time) ? mq.time.map((t, i) => ({
                t: new Date(t).getTime(),
                mm: (mq.precipitation ?? [])[i] ?? 0,
                snowCm: (mq.snowfall ?? [])[i] ?? 0
            })) : []
            root._updateNowcast()

            const out = []
            const dy = d.daily
            for (let i = 0; i < dy.time.length; i++)
                out.push({ date: dy.time[i], code: dy.weather_code[i],
                           maxC: dy.temperature_2m_max[i], minC: dy.temperature_2m_min[i],
                           // Absent from an older cached response, so consumers must
                           // tolerate "" rather than assume a timestamp is there.
                           sunrise: (dy.sunrise ?? [])[i] ?? "",
                           sunset:  (dy.sunset  ?? [])[i] ?? "",
                           uvMax:        (dy.uv_index_max ?? [])[i] ?? 0,
                           precipChance: (dy.precipitation_probability_max ?? [])[i] ?? 0,
                           precipMm:     (dy.precipitation_sum ?? [])[i] ?? 0,
                           daylightS:    (dy.daylight_duration ?? [])[i] ?? 0 })
            root.days  = out

            // Hourly: find the first bucket at or after the current hour, take 24.
            const hr = d.hourly
            if (hr && hr.time && hr.time.length > 0) {
                const nowMs = Date.now()
                let start = hr.time.findIndex(t => new Date(t).getTime() >= nowMs - 3600000)
                if (start < 0) start = 0
                root.hoursStart = start
                const end = Math.min(hr.time.length, start + 24)
                const t = [], p = [], h = []
                for (let i = start; i < end; i++) {
                    t.push(hr.temperature_2m[i])
                    p.push(hr.precipitation_probability ? (hr.precipitation_probability[i] ?? 0) : 0)
                    h.push(String(new Date(hr.time[i]).getHours()))
                }
                root.hourlyTemps  = t
                root.hourlyPrecip = p
                root.hourlyHours  = h

                // `time` is local ISO ("2026-05-19T14:00") under timezone=auto, so the
                // date and hour are read off the string rather than through Date —
                // which would re-interpret it in the machine's zone, not the place's.
                const col = (k, i) => (hr[k] ?? [])[i] ?? 0
                const all = []
                for (let i = 0; i < hr.time.length; i++)
                    all.push({ date: hr.time[i].slice(0, 10),
                               hour: parseInt(hr.time[i].slice(11, 13), 10),
                               tempC: col("temperature_2m", i),
                               feelsC: col("apparent_temperature", i),
                               humidity: col("relative_humidity_2m", i),
                               windKph: col("wind_speed_10m", i),
                               precip: col("precipitation_probability", i),
                               code: col("weather_code", i),
                               isDay: col("is_day", i) === 1,
                               uv: col("uv_index", i),
                               windDir: col("wind_direction_10m", i),
                               gustKph: col("wind_gusts_10m", i),
                               precipMm: col("precipitation", i) })
                root.hours = all
            } else {
                root.hourlyTemps = []; root.hourlyPrecip = []; root.hourlyHours = []; root.hoursStart = 0
                root.hours = []
            }

            root.ready = true
            root.error = ""
            root._fetchedAt = Date.now()
        } catch (e) {
            root.error = "Weather data was unreadable"
            console.warn("Weather: parse failed —", e)
        }
    }

    // ── Finding a place ───────────────────────────────────────────────────────
    // Used by the settings page's search box. Separate process from the forecast so a
    // search in flight can't cancel a refresh, and vice versa.
    property var    results: []
    property bool   searching: false

    function search(query) {
        const q = (query || "").trim()
        if (q === "") { root.results = []; return }
        root.searching = true
        // The query is a command ARGUMENT, and `--data-urlencode` makes curl do the
        // escaping. Building the query string by hand is how a place with a space or an
        // ampersand in its name silently returns nothing.
        geo.command = ["curl", "-fsS", "--max-time", "15", "--compressed", "--get",
                       "--data-urlencode", "name=" + q,
                       "--data-urlencode", "count=6",
                       "--data-urlencode", "language=en",
                       "--data-urlencode", "format=json",
                       "https://geocoding-api.open-meteo.com/v1/search"]
        geo.running = true
    }

    Process {
        id: geo
        stdout: StdioCollector { id: geoOut }
        onExited: function (exitCode) {
            root.searching = false
            if (exitCode !== 0) { root.results = []; return }
            try {
                const d = JSON.parse(geoOut.text)
                // An empty result set comes back with NO `results` key at all, not an
                // empty array — so `?? []` here is load-bearing, not defensive noise.
                root.results = (d.results ?? []).map(r => ({
                    name: r.name,
                    // "Lisbon, Lisbon District, Portugal" — the admin1 is what separates
                    // the Lisbon you meant from the one in Ohio.
                    detail: [r.admin1, r.country].filter(x => !!x).join(", "),
                    lat: r.latitude,
                    lon: r.longitude,
                    // Saved with the place (Config.weatherCountry) for the calendar's
                    // special dates. Checked, since it's spliced into a URL later.
                    countryCode: /^[A-Z]{2}$/.test(r.country_code ?? "") ? r.country_code : ""
                }))
            } catch (e) {
                root.results = []
            }
        }
    }

    // ── The location's country, for a place picked before it was saved ─────────
    // The settings page stores the country code with the place now. A place picked
    // earlier has none, so this looks the SAME name up once and takes the result
    // nearest the saved coordinates — never an IP lookup, same as the rest of this
    // service. A name that doesn't resolve near where you are sets nothing.
    function backfillCountry() {
        if (!root.hasLocation || (Config.weatherCountry || "") !== "" || backfill.running) return
        backfill.command = ["curl", "-fsS", "--max-time", "15", "--compressed", "--get",
                            "--data-urlencode", "name=" + root.place,
                            "--data-urlencode", "count=10",
                            "--data-urlencode", "format=json",
                            "https://geocoding-api.open-meteo.com/v1/search"]
        backfill.running = true
    }

    Process {
        id: backfill
        stdout: StdioCollector { id: backfillOut }
        onExited: function (exitCode) {
            if (exitCode !== 0) return
            try {
                let best = null, bestD = Infinity
                for (const r of (JSON.parse(backfillOut.text).results ?? [])) {
                    const d = Math.pow(r.latitude - root.lat, 2) + Math.pow(r.longitude - root.lon, 2)
                    if (d < bestD) { best = r; bestD = d }
                }
                // Within about half a degree: the same place, not a namesake abroad.
                if (best && bestD < 0.25 && /^[A-Z]{2}$/.test(best.country_code ?? ""))
                    Config.weatherCountry = best.country_code
            } catch (e) {
                console.warn("Weather: country lookup failed —", e)
            }
        }
    }

    // ── WMO weather codes ─────────────────────────────────────────────────────
    // Open-Meteo reports conditions as WMO code 4677, which is a numeric standard with
    // no text in the response at all — so the labels have to live somewhere, and this
    // is the only place that knows what a 45 is.
    //
    // Grouped rather than enumerated to 100: the standard distinguishes "slight" from
    // "moderate" freezing drizzle, and a desktop widget does not.
    function describe(c) {
        if (c === 0) return "Clear"
        if (c === 1) return "Mainly clear"
        if (c === 2) return "Partly cloudy"
        if (c === 3) return "Overcast"
        if (c === 45 || c === 48) return "Fog"
        if (c >= 51 && c <= 57) return "Drizzle"
        if (c >= 61 && c <= 67) return "Rain"
        if (c >= 71 && c <= 77) return "Snow"
        if (c >= 80 && c <= 82) return "Showers"
        if (c === 85 || c === 86) return "Snow showers"
        if (c === 95) return "Thunderstorm"
        if (c === 96 || c === 99) return "Thunderstorm, hail"
        return "—"
    }

    // Day/night matters for exactly the clear and mainly-clear cases: everything else
    // looks the same at midnight. Glyphs are cmap-verified against the shell's font.
    function glyph(c, day) {
        const d = day === undefined ? root.isDay : day
        if (c === 0) return d ? "󰖙" : "󰖔"                     // sunny / clear night
        if (c === 1 || c === 2) return d ? "󰖕" : "󰼱"          // part cloudy day / night
        if (c === 3) return "󰖐"                               // cloudy
        if (c === 45 || c === 48) return "󰖑"                  // fog
        if (c >= 51 && c <= 57) return "󰖗"                    // drizzle
        if (c >= 61 && c <= 67) return "󰖖"                    // rain
        if (c >= 71 && c <= 77) return "󰖘"                    // snow
        if (c >= 80 && c <= 82) return "󰖖"                    // showers
        if (c === 85 || c === 86) return "󰖘"
        if (c >= 95) return "󰖓"                               // thunder
        return "󰖐"
    }

    // Same code table as glyph(), naming a Fluent SVG instead.
    function iconName(c, day) {
        const d = day === undefined ? root.isDay : day
        if (c === 0) return d ? "weather-sunny" : "weather-moon"
        if (c === 1 || c === 2) return d ? "weather-partly-cloudy-day" : "weather-partly-cloudy-night"
        if (c === 3) return "weather-cloudy"
        if (c === 45 || c === 48) return "weather-fog"
        if (c >= 51 && c <= 57) return "weather-drizzle"
        if (c >= 61 && c <= 67) return "weather-rain"
        if (c >= 71 && c <= 77) return "weather-snow"
        if (c >= 80 && c <= 82) return "weather-rain"
        if (c === 85 || c === 86) return "weather-snow"
        if (c >= 95) return "weather-thunderstorm"
        return "weather-cloudy"
    }

    // Same code table again, naming a Material Symbols icon — Caelestia's set (its utils/Icons.qml
    // weatherIcons), which reads well drawn OUTLINED: clear_day, partly_cloudy_day, cloud, foggy, rainy,
    // cloudy_snowing, snowing_heavy, thunderstorm. Two differences, both on purpose: it gives every rain
    // code one `rainy` (so does this now — the finer light / heavy glyphs were noisy at 16px), and it has
    // no night, so a clear midnight drew a sun; this keeps Material's own clear_night and
    // partly_cloudy_night. Draw these at FILL 0: filled, a cloud with a moon in front of it (or rain under
    // it) closes up into one blob and the detail that names it is lost.
    //
    // clear_day, cloudy_snowing and snowing_heavy are new to the bundled font — they need
    // `python3 scripts/material-symbols-map.py --emit` once (bun scripts/test-icons.js says so).
    function symbol(c, day) {
        const d = day === undefined ? root.isDay : day
        if (c === 0 || c === 1) return d ? "clear_day" : "clear_night"
        if (c === 2) return d ? "partly_cloudy_day" : "partly_cloudy_night"
        if (c === 3) return "cloud"
        if (c === 45 || c === 48) return "foggy"
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return "rainy"
        if (c === 75 || c === 86) return "snowing_heavy"
        if (c === 71 || c === 73 || c === 77 || c === 85) return "cloudy_snowing"
        if (c >= 95) return "thunderstorm"
        return "cloud"
    }

    // A condition's colour, from the palette's semantic roles: sun warm, clear
    // night in the primary, rain in info, storms in danger, cloud and fog muted.
    // Roles rather than hues, so it follows the wallpaper like everything else.
    function tint(c, day) {
        const d = day === undefined ? root.isDay : day
        if (c === 0 || c === 1) return d ? Colors.warning : Colors.primary
        if (c === 2) return Colors.mix(d ? Colors.warning : Colors.primary, Colors.fgMuted, 0.4)
        if (c === 3 || c === 45 || c === 48) return Colors.fgMuted
        if ((c >= 51 && c <= 67) || (c >= 80 && c <= 82)) return Colors.info
        if ((c >= 71 && c <= 77) || c === 85 || c === 86) return Colors.fg
        if (c >= 95) return Colors.danger
        return Colors.fgMuted
    }

    // A temperature's colour: a blend from info (0 °C and below) to warning (30 °C
    // and above). Takes Celsius, like everything stored here.
    function tempTint(c) {
        return Colors.mix(Colors.info, Colors.warning, Math.max(0, Math.min(1, c / 30)))
    }
}
