pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"

// ── CountdownWidget ───────────────────────────────────────────────────────────
// Days until a date. No service, no process — the whole widget is arithmetic over the
// system clock, which is why it is the cheapest tile here.
//
// ── Whole days, from midnight to midnight ─────────────────────────────────────
// The count is a difference of DATES, not of timestamps. `(target - now) / 86400000`
// would say "0 days" for something happening this evening and "1 day" for something
// happening in 25 hours — technically true, and not what anyone means by "days until".
// Both ends are normalised to local midnight first, so tomorrow is always 1 whatever
// time you look, and a daylight-saving shift in between cannot round the answer down.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    // "YYYY-MM-DD". Empty until the settings page sets one.
    readonly property string dateStr: root.opts.date ?? ""
    readonly property string label:   root.opts.label ?? ""

    // Parsed FIELD BY FIELD rather than with `new Date(str)`. A bare "2026-12-25" is
    // parsed as UTC midnight by the ES spec, so east of Greenwich the date silently
    // becomes the day before — the exact off-by-one this widget exists to get right.
    readonly property var target: {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(root.dateStr)
        if (!m) return null
        const d = new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]))
        return isNaN(d.getTime()) ? null : d
    }

    property date now: new Date()
    Timer {
        // The answer changes once a day. A minute is already far finer than needed; it
        // is here so a machine left on over midnight rolls the number over promptly.
        interval: 60000
        repeat: true
        running: root.active
        onTriggered: root.now = new Date()
    }

    readonly property int days: {
        if (root.target === null) return 0
        const a = new Date(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())
        const b = new Date(root.target.getFullYear(), root.target.getMonth(), root.target.getDate())
        // Rounded, not floored: the difference is a whole number of days only if no DST
        // boundary falls between them, and one that does leaves ±1 hour of slop.
        return Math.round((b.getTime() - a.getTime()) / 86400000)
    }

    readonly property bool past:  root.days < 0
    readonly property bool today: root.days === 0

    readonly property string headline:
        root.today ? "Today"
      : root.past  ? Math.abs(root.days) : root.days

    readonly property string caption:
        root.target === null ? ""
      : root.today ? Qt.formatDateTime(root.target, "d MMMM")
      : root.past  ? (Math.abs(root.days) === 1 ? "day ago" : "days ago")
      : (root.days === 1 ? "day to go" : "days to go")

    // ── Nothing set ───────────────────────────────────────────────────────────
    StyledText {
        anchors.fill: parent
        visible: root.target === null
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        wrapMode: Text.WordWrap
        text: "Pick a date in Settings → Widgets"
        variant: "caption"
        emphasis: "muted"
    }

    ColumnLayout {
        anchors.fill: parent
        visible: root.target !== null
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingXs

            StyledText {
                text: "󰃯"
                variant: "caption"
                color: root.accent
            }
            StyledText {
                Layout.fillWidth: true
                text: root.label !== "" ? root.label : "Countdown"
                variant: "caption"
                color: root.accent
                font.bold: true
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.headline
            font.pixelSize: root.today ? 34 : 58
            font.weight: Font.Bold
            color: root.past ? Colors.fgMuted : Colors.fg
            // A four-digit count on a small tile would otherwise run past the edge.
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 18
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.caption
            variant: "caption"
            emphasis: "muted"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            visible: !root.today && root.target !== null
            // Guarded in the EXPRESSION, not only by `visible`. An invisible item's
            // bindings still evaluate, so the visibility check alone left
            // formatDateTime being handed a null on every countdown with no date set.
            text: root.target === null
                  ? "" : Qt.formatDateTime(root.target, "ddd d MMM yyyy")
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }
    }
}
