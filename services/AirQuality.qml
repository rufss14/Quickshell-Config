pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "weather.js" as W

// ── AirQuality ────────────────────────────────────────────────────────────────
// Current air quality and pollen for the weather location, from Open-Meteo's
// air-quality API — the same provider as Weather, for the same reasons (no key, no
// account, a fixed coordinate you chose rather than an IP lookup).
//
// A separate service because it's a separate endpoint on a slower cadence: the
// model updates hourly, so this refreshes every 60 minutes, and only while something
// on screen holds it (the same refcount contract as Weather).
//
// Pollen is Europe-only. Elsewhere every pollen value comes back null, which is
// "not covered" — `pollenCovered` false, and the panel says nothing — never "none".
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property bool   ready:   false
    property bool   loading: false
    property string error:   ""

    property real aqi:   -1      // European AQI
    property real pm25:  -1      // μg/m³
    property real pm10:  -1
    readonly property string level: W.aqiLevel(root.aqi)
    readonly property real   ratio: W.aqiRatio(root.aqi)

    property bool pollenCovered: false
    property var  pollen: []     // [{ name, grains }], most first, only species present

    readonly property int refreshMins: 60

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

    // A new place must not show the old one's air.
    Connections {
        target: Weather
        function onLatChanged() { root._relocate() }
        function onLonChanged() { root._relocate() }
    }
    function _relocate() {
        root.ready = false
        root.aqi = -1
        root.pollen = []
        root.pollenCovered = false
        if (root._refs > 0) root.refresh()
    }

    function refresh() {
        if (!Weather.hasLocation || fetch.running) return
        root.loading = true
        root.error = ""
        // Built from NUMBERS, like Weather._url(): nothing here a string could escape into.
        fetch.command = ["curl", "-fsS", "--max-time", "20", "--compressed",
            "https://air-quality-api.open-meteo.com/v1/air-quality"
            + "?latitude="  + Weather.lat.toFixed(4)
            + "&longitude=" + Weather.lon.toFixed(4)
            + "&current=european_aqi,pm2_5,pm10"
            + ",alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,olive_pollen,ragweed_pollen"
            + "&timezone=auto"]
        fetch.running = true
    }

    Process {
        id: fetch
        stdout: StdioCollector { id: fetchOut }
        stderr: StdioCollector { id: fetchErr }
        onExited: function (exitCode) {
            root.loading = false
            if (exitCode !== 0) {
                root.error = "Couldn't reach the air quality service"
                console.warn("AirQuality: curl exited", exitCode, fetchErr.text.trim())
                return
            }
            try {
                const c = JSON.parse(fetchOut.text).current
                root.aqi  = isFinite(c.european_aqi) && c.european_aqi !== null ? c.european_aqi : -1
                root.pm25 = isFinite(c.pm2_5) && c.pm2_5 !== null ? c.pm2_5 : -1
                root.pm10 = isFinite(c.pm10)  && c.pm10  !== null ? c.pm10  : -1
                const p = W.pollen(c)
                root.pollenCovered = p.covered
                root.pollen = p.items
                root.ready = true
            } catch (e) {
                root.error = "Air quality data was unreadable"
                console.warn("AirQuality: parse failed —", e)
            }
        }
    }
}
