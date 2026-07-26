pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

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

    // [{ date, code, maxC, minC }] — today first.
    property var days: []

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
    function acquire() {
        root._refs++
        if (root._refs === 1) {
            if (!root.ready) root.refresh()
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
             // Seven days, so the large tile's forecast list fills its height with real
             // days rather than padding. Costs nothing extra — same request either way.
             // `sunrise`/`sunset` come back as local ISO timestamps under the same
             // `timezone=auto` the buckets use, so the sun tile needs no astronomy of
             // its own — which is the whole reason this endpoint was picked.
             + "&daily=weather_code,temperature_2m_max,temperature_2m_min"
             + ",sunrise,sunset"
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

            const out = []
            const dy = d.daily
            for (let i = 0; i < dy.time.length; i++)
                out.push({ date: dy.time[i], code: dy.weather_code[i],
                           maxC: dy.temperature_2m_max[i], minC: dy.temperature_2m_min[i],
                           // Absent from an older cached response, so consumers must
                           // tolerate "" rather than assume a timestamp is there.
                           sunrise: (dy.sunrise ?? [])[i] ?? "",
                           sunset:  (dy.sunset  ?? [])[i] ?? "" })
            root.days  = out
            root.ready = true
            root.error = ""
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
                    lon: r.longitude
                }))
            } catch (e) {
                root.results = []
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
}
