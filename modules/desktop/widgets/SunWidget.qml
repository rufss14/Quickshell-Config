pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../../config"
import "../../../components"
import "../../../services"

// ── SunWidget ─────────────────────────────────────────────────────────────────
// Sunrise, sunset, and where the day currently sits between them.
//
// The times come from the SAME forecast request the weather tile makes — Open-Meteo
// returns `sunrise`/`sunset` in the daily block under `timezone=auto`, so they are
// already local and this tile computes no astronomy. Placing a sun tile and a weather
// tile therefore costs one request between them, not two: the service is refcounted and
// both hold the same one.
//
// It shares the weather service's location, deliberately. Two independently configured
// locations on one desktop is a bug factory, and "sunset here" is the only question this
// answers.
//
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// The day as a drawn arc: a faint track for the whole sky, a thick accent stroke for the
// part of it the sun has crossed, and the sun itself as the expressive "sunny" shape
// riding the arc on a spring (a plain disc at night, waiting at the horizon). Sunrise and
// sunset are pills at the arc's two feet. Large adds daylight (and tomorrow's change) and
// tonight's moon, drawn at its phase.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Weather.acquire(); root._held = true }
        else if (!root.active && root._held) { Weather.release(); root._held = false }
    }
    Component.onCompleted: root._sync()
    onActiveChanged: root._sync()
    Component.onDestruction: if (root._held) Weather.release()

    readonly property var day: Weather.days.length > 0 ? Weather.days[0] : null
    readonly property bool haveTimes:
        root.day !== null && root.day.sunrise !== "" && root.day.sunset !== ""

    // Open-Meteo emits "2026-07-24T05:41" — no zone suffix, because `timezone=auto`
    // already put it in the location's own time. `new Date()` on that string parses it
    // as LOCAL, which is what we want and is only correct because the shell and the
    // configured place are normally the same place. Named here so it is a known
    // assumption rather than a silent one.
    function _at(iso) { return iso === "" ? null : new Date(iso) }

    readonly property var riseAt: root.haveTimes ? root._at(root.day.sunrise) : null
    readonly property var setAt:  root.haveTimes ? root._at(root.day.sunset)  : null

    // Binds to the shared clock; minute resolution is all the arc and countdown need,
    // and the shared timer avoids waking the process to redraw identical pixels.
    readonly property date now: Clock.now

    // How far through the daylight span we are, 0..1. Clamped rather than extrapolated:
    // before dawn and after dusk the marker parks at the horizon instead of running off
    // the end of the arc.
    readonly property real progress: {
        if (!root.haveTimes) return 0
        const a = root.riseAt.getTime(), b = root.setAt.getTime()
        if (b <= a) return 0
        return Math.max(0, Math.min(1, (root.now.getTime() - a) / (b - a)))
    }
    readonly property bool daytime:
        root.haveTimes && root.now >= root.riseAt && root.now <= root.setAt

    function _hhmm(d) { return d === null ? "—" : Qt.formatDateTime(d, "HH:mm") }

    // ── Day length, and which way it's trending ───────────────────────────────
    // "Yesterday" isn't in the forecast (days[0] is today, the rest are ahead), so
    // the trend is measured against TOMORROW instead — same question answered:
    // are the days getting longer or shorter, and by how much.
    function _spanMins(riseIso, setIso) {
        if (riseIso === "" || setIso === "") return 0
        return Math.round((new Date(setIso).getTime()
                         - new Date(riseIso).getTime()) / 60000)
    }
    readonly property int dayMins:
        root.haveTimes ? root._spanMins(root.day.sunrise, root.day.sunset) : 0
    readonly property int tomorrowMins: {
        const d = Weather.days.length > 1 ? Weather.days[1] : null
        return d ? root._spanMins(d.sunrise, d.sunset) : 0
    }
    readonly property int trendMins:
        root.tomorrowMins > 0 ? root.tomorrowMins - root.dayMins : 0

    function _hm(mins) {
        const a = Math.abs(mins)
        const h = Math.floor(a / 60), m = a % 60
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }

    // ── Moon phase ────────────────────────────────────────────────────────────
    // Pure arithmetic off a known new moon (2000-01-06 18:14 UTC) and the mean
    // synodic month. Good to a few hours, which is all a phase name needs.
    readonly property real moonAge: {
        const synodic = 29.530588853
        const ref = Date.UTC(2000, 0, 6, 18, 14) / 86400000
        const now = root.now.getTime() / 86400000
        return ((now - ref) % synodic + synodic) % synodic
    }
    readonly property int moonLit:
        Math.round((1 - Math.cos(2 * Math.PI * root.moonAge / 29.530588853)) / 2 * 100)
    readonly property string moonName: {
        const a = root.moonAge
        if (a < 1.85)  return "New moon"
        if (a < 5.54)  return "Waxing crescent"
        if (a < 9.23)  return "First quarter"
        if (a < 12.9)  return "Waxing gibbous"
        if (a < 16.6)  return "Full moon"
        if (a < 20.3)  return "Waning gibbous"
        if (a < 24.0)  return "Last quarter"
        if (a < 27.7)  return "Waning crescent"
        return "New moon"
    }

    // The next event and how long until it. This is the one line most people actually
    // read on a tile like this, so it leads.
    readonly property string headline: {
        if (!root.haveTimes) return ""
        const target = root.daytime ? root.setAt
                     : (root.now < root.riseAt ? root.riseAt : null)
        if (target === null) return "Sunrise tomorrow"
        const mins = Math.max(0, Math.round((target.getTime() - root.now.getTime()) / 60000))
        const h = Math.floor(mins / 60), m = mins % 60
        const span = h > 0 ? h + "h " + m + "m" : m + "m"
        return (root.daytime ? "Sunset in " : "Sunrise in ") + span
    }

    // ── Nothing to show ───────────────────────────────────────────────────────
    readonly property bool waxing: root.moonAge < 29.530588853 / 2

    WidgetEmpty {
        visible: !root.haveTimes
        icon: "light_mode"
        text: Weather.place === "" ? "Set a location in Settings → Widgets"
            : Weather.error !== ""  ? Weather.error
            : "Loading…"
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.haveTimes
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   root.daytime ? "light_mode" : "dark_mode"
            shape:  root.daytime ? "sunny" : "circle"
            title:  root.headline
            accent: root.accent
        }

        // ── The arc ───────────────────────────────────────────────────────────
        Item {
            id: arc
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 44

            readonly property real body: Tokens.iconLg + Tokens.spacingXs
            readonly property real rx: Math.max(1, (width - arc.body) / 2)
            readonly property real ry: Math.max(1, Math.min(height - arc.body / 2 - 2, rx))
            readonly property real cx: width / 2
            readonly property real cy: height - 2

            // The sun's place, 0..1 along the sky, sprung so a wake or a new day glides.
            SpringValue {
                id: sunAt
                spec: Motion.springSpatialSlow
                epsilon: 0.0005
                target: root.daytime ? root.progress : (root.now < root.riseAt ? 0 : 1)
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer

                // The horizon.
                ShapePath {
                    strokeColor: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                    strokeWidth: 1
                    fillColor: "transparent"
                    startX: 0; startY: arc.cy
                    PathLine { x: arc.width; y: arc.cy }
                }
                // The whole sky.
                ShapePath {
                    strokeColor: Colors.of(QsWindow.window).alpha(root.accent, 0.22)
                    strokeWidth: 3
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: arc.cx; centerY: arc.cy
                        radiusX: arc.rx; radiusY: arc.ry
                        startAngle: 180; sweepAngle: 180
                    }
                }
                // What the sun has crossed today.
                ShapePath {
                    strokeColor: root.daytime ? root.accent : "transparent"
                    strokeWidth: 6
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    PathAngleArc {
                        centerX: arc.cx; centerY: arc.cy
                        radiusX: arc.rx; radiusY: arc.ry
                        startAngle: 180; sweepAngle: 180 * sunAt.value
                    }
                }
            }

            MorphShape {
                width: arc.body
                height: arc.body
                x: arc.cx - arc.rx * Math.cos(Math.PI * sunAt.value) - width / 2
                y: arc.cy - arc.ry * Math.sin(Math.PI * sunAt.value) - height / 2
                spec: Motion.springSpatialFast
                shape: root.daytime && !Config.barShape ? "sunny" : "circle"
                fillColor: root.daytime ? root.accent : Colors.of(QsWindow.window).surfaceHigh
                strokeColor: root.daytime ? "transparent" : Colors.of(QsWindow.window).alpha(root.accent, 0.5)
                strokeWidth: 1.5
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            TilePill { icon: "wb_twilight"; text: "Rise " + root._hhmm(root.riseAt) }
            Item { Layout.fillWidth: true }
            TilePill { icon: "bedtime"; text: "Set " + root._hhmm(root.setAt) }
        }

        // ── Large: the length of the day, and the moon ────────────────────────
        TileRow {
            visible: root.size === "large" && root.dayMins > 0
            interactive: false
            MaterialIcon { name: "schedule"; variant: "caption"; emphasis: "dim" }
            StyledText { Layout.fillWidth: true; text: "Daylight"; variant: "label"; color: Colors.of(QsWindow.window).fg }
            StyledText {
                text: root._hm(root.dayMins)
                variant: "label"
                font.weight: Font.DemiBold
                color: Colors.of(QsWindow.window).fg
            }
            StyledText {
                visible: root.trendMins !== 0
                text: (root.trendMins > 0 ? "+" : "−") + root._hm(root.trendMins)
                variant: "caption"
                color: root.trendMins > 0 ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgMuted
            }
        }
        TileRow {
            visible: root.size === "large"
            interactive: false
            // Tonight's moon at its phase: a lit disc with the shadow disc slid across it,
            // from the left while it waxes (lit on the right) and the right while it wanes.
            Item {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: Tokens.iconMd
                implicitHeight: implicitWidth
                clip: true
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Colors.of(QsWindow.window).fg
                }
                Rectangle {
                    width: parent.width
                    height: parent.height
                    radius: width / 2
                    color: Colors.of(QsWindow.window).surfaceHigh
                    x: (root.waxing ? -1 : 1) * parent.width * (root.moonLit / 100) * 1.05
                }
            }
            StyledText { Layout.fillWidth: true; text: root.moonName; variant: "label"; color: Colors.of(QsWindow.window).fg }
            StyledText { text: root.moonLit + "% lit"; variant: "caption"; emphasis: "dim" }
        }
    }
}
