pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
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
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    // ── Refcount, gated on `active` ───────────────────────────────────────────
    // A settings preview must not put a request on the wire; same contract the weather
    // tile follows, and the reason previews are built with `active: false`.
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

    property date now: new Date()
    Timer {
        // Minute resolution is all the arc and the countdown can show, so ticking any
        // faster would be waking the process to redraw the same pixels.
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root.now = new Date()
    }

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
    StyledText {
        anchors.fill: parent
        visible: !root.haveTimes
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: Weather.place === "" ? "Set a location in Settings → Widgets"
            : Weather.error !== ""  ? Weather.error
            : "Loading…"
        variant: "caption"
        emphasis: "muted"
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.haveTimes
        spacing: Tokens.spacingXs

        StyledText {
            Layout.fillWidth: true
            text: root.headline
            variant: "caption"
            color: root.accent
            font.bold: true
            elide: Text.ElideRight
        }

        // ── The arc ───────────────────────────────────────────────────────────
        // A half-circle from horizon to horizon with the sun on it. This is the picture
        // the tile exists for: two timestamps tell you when, the arc tells you WHERE in
        // the day you are, which is the thing a pair of numbers cannot say at a glance.
        Item {
            id: arc
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 44

            readonly property real pad: 6
            readonly property real rx: Math.max(1, (width - pad * 2) / 2)
            // The arc's own height is the smaller of the box and the radius, so a wide
            // short tile gets a flattened dome rather than one clipped at the top.
            readonly property real ry: Math.max(1, Math.min(height - 10, rx))
            readonly property real cx: width / 2
            readonly property real cy: height - 8

            // Horizon.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                y: arc.cy
                height: 1
                color: Colors.alpha(Colors.fg, 0.18)
            }

            // The dome, as dots along the path. Drawn this way rather than with a Shape
            // because it is one instantiation of a fixed count and needs no stroking,
            // joins or CurveRenderer — and dots read as a track for the sun to sit on.
            Repeater {
                model: 24
                Rectangle {
                    required property int index
                    readonly property real t: index / 23
                    width: 2; height: 2; radius: 1
                    antialiasing: true
                    color: Colors.alpha(Colors.fg, 0.30)
                    x: arc.cx - arc.rx * Math.cos(Math.PI * t) - width / 2
                    y: arc.cy - arc.ry * Math.sin(Math.PI * t) - height / 2
                }
            }

            // The sun itself. Dimmed outside daylight, because a bright marker parked
            // on the horizon at midnight reads as "the sun is up".
            Rectangle {
                width: 12; height: 12; radius: 6
                antialiasing: true
                color: root.daytime ? root.accent : Colors.alpha(root.accent, 0.35)
                x: arc.cx - arc.rx * Math.cos(Math.PI * root.progress) - width / 2
                y: arc.cy - arc.ry * Math.sin(Math.PI * root.progress) - height / 2
                Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
            }
        }

        // ── The two times ─────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            Endpoint {
                Layout.fillWidth: true
                glyph: "󰖛"
                time:  root._hhmm(root.riseAt)
                label: "Sunrise"
            }
            Endpoint {
                Layout.fillWidth: true
                glyph: "󰖚"
                time:  root._hhmm(root.setAt)
                label: "Sunset"
                alignRight: true
            }
        }
    }

    component Endpoint: ColumnLayout {
        id: ep
        property string glyph: ""
        property string time: ""
        property string label: ""
        property bool alignRight: false
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            layoutDirection: ep.alignRight ? Qt.RightToLeft : Qt.LeftToRight
            spacing: Tokens.spacingXs

            StyledText {
                text: ep.glyph
                variant: "caption"
                color: root.accent
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: ep.alignRight ? Text.AlignRight : Text.AlignLeft
                text: ep.time
                variant: "body"
                font.bold: true
                color: Colors.fg
            }
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: ep.alignRight ? Text.AlignRight : Text.AlignLeft
            text: ep.label
            variant: "caption"
            emphasis: "dim"
        }
    }
}
