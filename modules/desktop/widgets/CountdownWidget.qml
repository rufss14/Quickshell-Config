pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

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
// ── Material 3 Expressive (2026-10-30) ────────────────────────────────────────
// The number of days IS the tile, so it is the hero: big block digits on a tonal shape
// whose form says where the date is — a cookie while it is coming, a burst on the day,
// a plain circle once it has passed (and the quiet tone). Small is the hero and the
// label; medium puts the date, the weeks and the repeat beside it.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property string dateStr: root.opts.date ?? ""
    readonly property string label:   root.opts.label ?? ""

    // Annual: the year in `opts.date` is ignored and the count always runs to the
    // NEXT occurrence of that month-and-day — birthdays, anniversaries. Rolls over
    // on its own the day after it lands, so it never shows a date in the past.
    readonly property bool recurring: root.opts.recurring === true

    // Parsed FIELD BY FIELD rather than with `new Date(str)`. A bare "2026-12-25" is
    // parsed as UTC midnight by the ES spec, so east of Greenwich the date silently
    // becomes the day before — the exact off-by-one this widget exists to get right.
    readonly property var target: {
        const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(root.dateStr)
        if (!m) return null
        const mon = Number(m[2]) - 1, dom = Number(m[3])
        if (root.recurring) {
            const n = root.now
            let d = new Date(n.getFullYear(), mon, dom)
            const today = new Date(n.getFullYear(), n.getMonth(), n.getDate())
            if (d.getTime() < today.getTime())
                d = new Date(n.getFullYear() + 1, mon, dom)
            return isNaN(d.getTime()) ? null : d
        }
        const d = new Date(Number(m[1]), mon, dom)
        return isNaN(d.getTime()) ? null : d
    }

    // Binds to the shared clock; minute resolution is all that's needed to notice a
    // midnight rollover and update the count.
    readonly property date now: Clock.now

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
    // "6 weeks, 2 days" — the scale a long countdown is felt in.
    readonly property string weeksLine: {
        const n = Math.abs(root.days)
        if (n < 14) return ""
        const w = Math.floor(n / 7), d = n % 7
        return w + " weeks" + (d > 0 ? ", " + d + (d === 1 ? " day" : " days") : "")
    }

    WidgetEmpty {
        visible: root.target === null
        icon: "event"
        text: Translation.tr("Pick a date in Settings → Widgets")
    }

    RowLayout {
        anchors.fill: parent
        visible: root.target !== null
        spacing: Tokens.spacingLg

        // ── The hero ──────────────────────────────────────────────────────────
        Item {
            Layout.preferredWidth: root.size === "small" ? -1 : height
            Layout.fillWidth: root.size === "small"
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: Tokens.spacingSm

                TilePill {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.size === "small"
                    icon: root.recurring ? "repeat" : "event"
                    text: root.label !== "" ? root.label : "Countdown"
                    tone: "accent"
                    accent: root.accent
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    MorphShape {
                        anchors.centerIn: parent
                        width: Math.min(parent.width, parent.height)
                        height: width
                        spec: Motion.springSpatialFast
                        shape: Config.barShape ? "squircle"
                             : root.today ? "burst" : root.past ? "circle" : "cookie9"
                        fillColor: root.past ? Colors.of(QsWindow.window).surfaceHigh
                                             : Colors.of(QsWindow.window).primaryContainer

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: -Tokens.spacingSm

                            RollText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(root.headline)
                                family: Tokens.fontBlock
                                weight: Font.ExtraBold
                                pixelSize: Math.round(parent.parent.width
                                           * (root.today ? 0.2 : text.length > 3 ? 0.26 : 0.34))
                                color: root.past ? Colors.of(QsWindow.window).fgMuted
                                                 : Colors.of(QsWindow.window).fgOnPrimaryContainer
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: !root.today
                                text: Math.abs(root.days) === 1 ? "day" : "days"
                                variant: "caption"
                                color: Colors.of(QsWindow.window).alpha(root.past
                                       ? Colors.of(QsWindow.window).fgMuted
                                       : Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.75)
                            }
                        }
                    }
                }
            }
        }

        // ── Medium: what, when, how long ──────────────────────────────────────
        ColumnLayout {
            visible: root.size !== "small"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingXs

            Item { Layout.fillHeight: true }
            StyledText {
                Layout.fillWidth: true
                text: root.label !== "" ? root.label : "Countdown"
                variant: "title"
                font.weight: Font.Bold
                color: Colors.of(QsWindow.window).fg
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.today ? "It's today" : root.caption
                variant: "label"
                emphasis: "muted"
                elide: Text.ElideRight
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacingSm
                spacing: Tokens.spacingXs
                TilePill {
                    icon: "event"
                    text: root.target === null ? "" : Qt.formatDateTime(root.target, "ddd d MMM yyyy")
                }
                TilePill {
                    visible: root.weeksLine !== ""
                    text: root.weeksLine
                }
                TilePill {
                    visible: root.recurring
                    icon: "repeat"
                    text: Translation.tr("Every year")
                    tone: "accent"
                    accent: root.accent
                }
            }
            Item { Layout.fillHeight: true }
        }
    }
}
