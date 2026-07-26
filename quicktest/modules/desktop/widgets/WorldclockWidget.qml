pragma ComponentBehavior: Bound
import QtQuick
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
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    // [{ label, offset }]. Empty is a legitimate state — a freshly placed tile has no
    // zones until the settings page adds one, and it says so rather than showing a blank.
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

    property date now: new Date()
    Timer {
        // Minutes are the finest thing displayed, so a 15s tick is already four times
        // more often than the face can change — it exists so a rollover lands promptly
        // rather than up to a minute late, not because anything needs the resolution.
        interval: 15000
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: root.now = new Date()
    }

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

    function _offsetLabel(offsetHours) {
        const sign = offsetHours < 0 ? "−" : "+"
        const a = Math.abs(offsetHours)
        const h = Math.floor(a)
        const m = Math.round((a - h) * 60)
        return "UTC" + sign + h + (m === 0 ? "" : ":" + (m < 10 ? "0" : "") + m)
    }

    // ── Empty ─────────────────────────────────────────────────────────────────
    StyledText {
        anchors.fill: parent
        visible: root.zones.length === 0
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: "Add a city in Settings → Widgets"
        variant: "caption"
        emphasis: "muted"
    }

    // ── Small: one clock, big ─────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.size === "small" && root.zones.length > 0
        spacing: 0

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.zones.length > 0 ? root._fmt(root.zoneAt(0).offset ?? 0) : ""
            font.family: Tokens.fontMono
            font.pixelSize: 40
            font.weight: Font.DemiBold
            font.letterSpacing: -1
            color: Colors.fg
            // Same guard the clock tile needs: with AM/PM the string is eight
            // characters and a fixed size would push it past the tile.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 18
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.zones.length > 0 ? (root.zoneAt(0).label ?? "") : ""
            variant: "caption"
            color: root.accent
            font.bold: true
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.zones.length > 0 ? root._dayNote(root.zoneAt(0).offset ?? 0) : ""
            variant: "caption"
            emphasis: "dim"
        }

        Item { Layout.fillHeight: true }
    }

    // ── Medium / large: a list ────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: root.size !== "small" && root.zones.length > 0
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingXs

            StyledText {
                text: "󰇧"
                variant: "caption"
                color: root.accent
            }
            StyledText {
                Layout.fillWidth: true
                text: "World clock"
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: root.shown
            RowLayout {
                id: zoneRow
                required property int index
                readonly property var zone: root.zoneAt(zoneRow.index)
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: zoneRow.zone.label ?? ""
                        variant: "body"
                        color: Colors.fg
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root._offsetLabel(zoneRow.zone.offset ?? 0)
                              + " · " + root._dayNote(zoneRow.zone.offset ?? 0)
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    text: root._fmt(zoneRow.zone.offset ?? 0)
                    font.family: Tokens.fontMono
                    variant: "body"
                    font.bold: true
                    color: Colors.fg
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
}
