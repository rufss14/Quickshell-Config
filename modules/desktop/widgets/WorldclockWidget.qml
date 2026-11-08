pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── WorldclockWidget ──────────────────────────────────────────────────────────
// What time it is somewhere else.
//
// ── Offsets, not zone names ───────────────────────────────────────────────────
// A zone is stored as `{ label, offset }` where offset is hours from UTC, and the time
// is computed arithmetically. That is a real limitation and it is a deliberate one:
// JavaScript's Date has no zone conversion of its own, and the honest alternatives are
// `Intl.DateTimeFormat` with a `timeZone` option — which needs Qt built with full ICU,
// something this shell cannot assume of the machine it lands on — or shelling out to
// `TZ=… date` once per zone per minute, which is a subprocess storm for a clock.
//
// The cost of the choice: a zone crossing a daylight-saving boundary is an hour wrong
// until its offset is edited. The label is free text for the same reason — "New York"
// is the user's word for the offset they picked, not a database lookup.
//
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// Every city is a small dial — the desktop clock's twelve-petal cookie, LIGHT (the
// accent's container) while it is day there and dark at night — so the eye reads
// "awake or asleep" before it reads a digit. The offset is said from HERE ("+8h,
// tomorrow"), which is the question a world clock answers, rather than as UTC±.
// Small: one city, big. Medium: three side by side. Large: up to six rows.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var zones: root.opts.zones ?? []
    readonly property bool hour24: root.opts.hour24 !== false

    // Small shows ONE zone; there is no room for a list, and three rows of 9px text is
    // not a clock. Medium and large show as many as fit.
    readonly property int shown:
        root.size === "small" ? Math.min(1, root.zones.length)
      : root.size === "medium" ? Math.min(3, root.zones.length)
      : Math.min(6, root.zones.length)

    // ── Which city leads ──────────────────────────────────────────────────────
    // At small only one clock fits, so a tap walks to the next city — otherwise the
    // other zones you configured are simply unreachable on that size. At medium and
    // large it rotates the list, which is still useful when you have more cities than
    // rows. Transient: the tile comes back on the first city, which is the one the
    // settings page shows at the top.
    property int lead: 0
    readonly property int leadSafe:
        root.zones.length === 0 ? 0 : ((root.lead % root.zones.length) + root.zones.length) % root.zones.length

    function tileTap() {
        if (root.zones.length < 2) return
        root.lead = (root.leadSafe + 1) % root.zones.length
    }

    // The zone at display position `i`, counting from whichever one currently leads.
    function zoneAt(i) {
        if (root.zones.length === 0) return null
        return root.zones[(root.leadSafe + i) % root.zones.length]
    }

    // Minutes are the finest display granularity, so the shared minute-ticking clock
    // provides all the precision needed.
    readonly property date now: Clock.now

    // UTC-plus-offset, expressed as a local Date whose *displayed* fields are the target
    // zone's. Formatting it with Qt.formatDateTime would re-apply the machine's own
    // offset, so the fields are read back with the getUTC* accessors instead.
    function _timeAt(offsetHours) {
        return new Date(root.now.getTime() + offsetHours * 3600000)
    }

    function _fmt(offsetHours) {
        const d = root._timeAt(offsetHours)
        const h = d.getUTCHours()
        const m = d.getUTCMinutes()
        const mm = (m < 10 ? "0" : "") + m
        if (root.hour24) return ((h < 10 ? "0" : "") + h) + ":" + mm
        const h12 = (h % 12) === 0 ? 12 : (h % 12)
        return h12 + ":" + mm + " " + (h < 12 ? "AM" : "PM")
    }

    // "Today" / "Tomorrow" / "Yesterday" relative to the machine's own date — the thing
    // that actually matters about a distant clock is whether it is even the same day.
    function _dayNote(offsetHours) {
        const there = root._timeAt(offsetHours)
        const delta = there.getUTCDate() - root.now.getDate()
        // Month rollovers make the raw difference large; only the sign is meaningful.
        const d = delta > 1 ? -1 : delta < -1 ? 1 : delta
        return d > 0 ? "Tomorrow" : d < 0 ? "Yesterday" : "Today"
    }

    // Roughly: is it daytime in that zone right now? A blunt 6am–6pm window — this
    // is a "sun's up / sun's down" hint beside a clock, not an ephemeris, and the
    // sun tile is where real sunrise/sunset lives.
    function _isDayThere(offsetHours) {
        const h = root._timeAt(offsetHours).getUTCHours()
        return h >= 6 && h < 18
    }
    function _dayGlyph(offsetHours) {
        return root._isDayThere(offsetHours) ? "󰖙" : "󰖔"
    }

    function _offsetLabel(offsetHours) {
        const sign = offsetHours < 0 ? "−" : "+"
        const a = Math.abs(offsetHours)
        const h = Math.floor(a)
        const m = Math.round((a - h) * 60)
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m)
    }

    // ── Empty ─────────────────────────────────────────────────────────────────
    // The offset from the local clock, in words: "+8h", "−4:30", "Same time".
    function _rel(offsetHours) {
        const local = -root.now.getTimezoneOffset() / 60
        const d = offsetHours - local
        if (Math.abs(d) < 0.01) return "Same time"
        const a = Math.abs(d), h = Math.floor(a), m = Math.round((a - h) * 60)
        return (d < 0 ? "−" : "+") + h + (m === 0 ? "h" : ":" + (m < 10 ? "0" : "") + m)
    }
    function _relLine(offsetHours) {
        const note = root._dayNote(offsetHours)
        return root._rel(offsetHours) + (note === "Today" ? "" : " · " + note.toLowerCase())
    }

    WidgetEmpty {
        visible: root.zones.length === 0
        icon: "public"
        text: Translation.tr("Add a city in Settings → Widgets")
    }

    // ── Small: one city ───────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "small" && root.zones.length > 0
        spacing: Tokens.spacingXs
        readonly property real off: root.zones.length > 0 ? (root.zoneAt(0).offset ?? 0) : 0

        MiniDial {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            Layout.preferredWidth: height
            offset: parent.off
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.zones.length > 0 ? (root.zoneAt(0).label ?? "") : ""
            variant: "label"
            font.weight: Font.DemiBold
            color: Colors.of(QsWindow.window).fg
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root._fmt(parent.off) + "  ·  " + root._relLine(parent.off)
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }
    }

    // ── Medium: side by side ──────────────────────────────────────────────────
    RowLayout {
        anchors.fill: parent
        visible: root.size === "medium" && root.zones.length > 0
        spacing: Tokens.spacingMd

        Repeater {
            model: root.size === "medium" ? root.shown : 0
            ColumnLayout {
                id: col
                required property int index
                readonly property var zone: root.zoneAt(col.index)
                readonly property real off: col.zone?.offset ?? 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                MiniDial {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingMd
                    Layout.preferredHeight: Layout.preferredWidth
                    offset: col.off
                }
                Item { Layout.fillHeight: true }
                RollText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root._fmt(col.off)
                    family: Tokens.fontMono
                    pixelSize: Tokens.fontTitle
                    weight: Font.Bold
                    color: Colors.of(QsWindow.window).fg
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: col.zone?.label ?? ""
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: Colors.of(QsWindow.window).fgMuted
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root._relLine(col.off)
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
            }
        }
    }

    // ── Large: rows ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "large" && root.zones.length > 0
        spacing: Tokens.spacingSm

        WidgetHeader {
            icon:   "public"
            shape:  "cookie12"
            title:  Translation.tr("World clock")
            accent: root.accent
        }

        Repeater {
            model: root.size === "large" ? root.shown : 0
            TileRow {
                id: zoneRow
                required property int index
                readonly property var zone: root.zoneAt(zoneRow.index)
                readonly property real off: zoneRow.zone?.offset ?? 0
                interactive: false

                MiniDial {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                    Layout.preferredHeight: Layout.preferredWidth
                    Layout.topMargin: Tokens.spacingXs
                    Layout.bottomMargin: Tokens.spacingXs
                    offset: zoneRow.off
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: zoneRow.zone?.label ?? ""
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fg
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root._relLine(zoneRow.off)
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                RollText {
                    Layout.alignment: Qt.AlignVCenter
                    text: root._fmt(zoneRow.off)
                    family: Tokens.fontMono
                    pixelSize: Tokens.fontTitle
                    weight: Font.Bold
                    color: Colors.of(QsWindow.window).fg
                }
            }
        }

        Item { Layout.fillHeight: true }
        StyledText {
            Layout.fillWidth: true
            visible: root.zones.length > root.shown
            text: "+" + (root.zones.length - root.shown) + " more"
            variant: "caption"
            emphasis: "dim"
        }
    }

    // A city's clock face: the desktop clock's cookie with its two hands, light by day
    // there and dark by night.
    component MiniDial: Item {
        id: md
        property real offset: 0
        readonly property date at: root._timeAt(md.offset)
        readonly property bool day: root._isDayThere(md.offset)
        readonly property real r: Math.min(width, height) / 2

        MorphShape {
            anchors.fill: parent
            turns: false
            spec: Motion.springSpatial
            shape: Config.barShape ? "squircle" : "cookie12"
            fillColor: md.day ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).surfaceHigh
        }
        // Hour, then minute: each a rounded bar with its round end on the pivot.
        Repeater {
            model: [
                { len: 0.46, w: 0.2,  hour: true },
                { len: 0.7,  w: 0.13, hour: false }
            ]
            Rectangle {
                id: hand
                required property var modelData
                readonly property real len: md.r * hand.modelData.len
                width: Math.max(2, md.r * hand.modelData.w)
                height: hand.len + width / 2
                radius: width / 2
                antialiasing: true
                x: md.width / 2 - width / 2
                y: md.height / 2 - hand.len
                color: hand.modelData.hour
                       ? (md.day ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg)
                       : (md.day ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fgMuted)
                transform: Rotation {
                    origin.x: hand.width / 2
                    origin.y: hand.len
                    angle: hand.modelData.hour
                           ? (md.at.getUTCHours() % 12) * 30 + md.at.getUTCMinutes() * 0.5
                           : md.at.getUTCMinutes() * 6
                }
            }
        }
    }
}
