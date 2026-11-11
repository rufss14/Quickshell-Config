pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "screentime"

// ── ScreenTimePanel ───────────────────────────────────────────────────────────
// Beside the sidebar's Screen time module (SidePanelDock). Redone 2026-11-08 in the shell's Material 3
// Expressive dialect, the Game Mode and Audio Mixer panels' shape: a hero, a SegmentSwitch, and pages that
// slide past each other on one spring.
//
//   Hero    (always) today as the subject — an M3E shape that turns while it counts, the total, what is in
//           focus, chips for today against usual and the top app (a Steam game's picture behind the card), and
//           the Start / Stop button. While tracking is off the hero IS the switch: what it would record, and Start.
//   Today   the daily average, the week, the busiest day; what is in focus now; today cut by app
//   Week    seven stacked bars (a plate on the picked day), the legend, and the last month as heat squares
//   Apps    one day's apps with a wavy ring each — its share of that day — and arrows to step through the days
//
// The title row on top is `Config.screentimePanelHeader()` — Settings › Bar › Screen time, like Game Mode's.
//
// ── It owns no state ──────────────────────────────────────────────────────────
// Everything real is services/ScreenTime (+ screentime.js, `bun scripts/test-screentime.js`); this shows it.
// The one thing the panel itself holds is WHICH DAY you are reading (`picked`, "" = today), shared by the Week
// page, which picks it, and the Apps page, which lists it.
//
// ── Height ────────────────────────────────────────────────────────────────────
// The pages box is as tall as the page you are on, within the room the dock has (past that the page scrolls),
// and follows it on a spring with no overshoot. Tracking off and nothing recorded: the hero alone.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // Reached by the page files in screentime/.
    property alias pagesBox: pagesBox
    property alias pg: pg

    // The room the dock has for this panel (SidePanelDock sets it). 0 = not told yet, no limit.
    property real maxHeight: 0

    implicitWidth: Tokens.sideCardUnit * 9
    readonly property int margin: Tokens.spacingXl
    readonly property int cardPad: Tokens.spacingMd + Tokens.spacingXs
    implicitHeight: mainCol.implicitHeight + root.margin * 2

    readonly property color accent: Colors.of(QsWindow.window).primary

    // Something to read: it is counting, or it has counted.
    readonly property bool hasData: Config.screenTime || Object.keys(ScreenTime.days).length > 0

    // ── The page, and the spring the pages ride ──────────────────────────────
    property string page: "today"
    readonly property var _pageOrder: ["today", "week", "apps"]
    SpringValue { id: pg; target: root._pageOrder.indexOf(root.page); spec: Motion.springSpatial }
    function go(p) { root.page = p }

    // ── Which day ─────────────────────────────────────────────────────────────
    property string picked: ""
    readonly property string day: root.picked !== "" ? root.picked : ScreenTime.todayKey
    readonly property int dayIndex: ScreenTime.month.findIndex(d => d.key === root.day)
    readonly property var dayRow: root.dayIndex >= 0 ? ScreenTime.month[root.dayIndex] : null
    readonly property string dayLabel: !root.dayRow ? ""
        : root.dayRow.today ? Translation.tr("Today")
        : root.dayRow.label + "  " + root.day.slice(5).replace("-", "/")
    // Today is "" rather than its key, so a panel left open past midnight still means "today".
    function pick(key) { root.picked = key === ScreenTime.todayKey ? "" : key }
    function step(delta) {
        const d = ScreenTime.month[root.dayIndex + delta]
        if (d) root.pick(d.key)
    }

    // ── Colours the pages share ───────────────────────────────────────────────
    // The accent at three strengths for an app's slice (monochrome-safe — the palette may well be grey — and one
    // family rather than three hues fighting for the eye); the rest in a neutral.
    readonly property var _tints: [1.0, 0.62, 0.36]
    function tint(rank) {
        const c = Colors.of(QsWindow.window)
        return rank < 3 ? c.alpha(c.primary, root._tints[rank]) : c.alpha(c.fg, 0.20)
    }
    // A day's heat square, 0 (nothing) … 4 (the busiest quarter).
    readonly property var _heat: [0.28, 0.5, 0.75, 1.0]
    function heatTint(level) {
        const c = Colors.of(QsWindow.window)
        return level <= 0 ? c.alpha(c.fg, 0.07) : c.alpha(c.primary, root._heat[Math.min(3, level - 1)])
    }

    ColumnLayout {
        id: mainCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingSm

        // ── Header (Settings › Bar › Screen time hides it) ────────────────────
        PanelHeader {
            id: header
            Layout.fillHeight: false
            visible: Config.screentimePanelHeader()
            symbol: "hourglass_top"
            title: Translation.tr("Screen")
            titleTail: Translation.tr("time")
            accent: root.accent
            subtitle: !Config.screenTime ? Translation.tr("Off — nothing is being recorded")
                : ScreenTime.weekAverage > 0 ? Translation.tr("%1 a day this week").arg(ScreenTime.duration(ScreenTime.weekAverage))
                : Translation.tr("Counting from now")

            ActionGroup {
                PanelButton {
                    variant: "ghost"
                    symbol: "settings"
                    onActivated: UiState.openSettingsTo("ScreenTimePage.qml")
                }
            }
        }

        ScreenTimeHero {
            id: hero
            panel: root
        }

        // ── Pages ─────────────────────────────────────────────────────────────
        // The switch opens out under the hero once there is something to read (a spring on its height).
        Item {
            id: tabs
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: pageSwitch.implicitHeight * Math.max(0, tabsOn.value)
            visible: tabsOn.value > 0.01
            clip: true
            SpringValue { id: tabsOn; target: root.hasData ? 1 : 0; spec: Motion.springEffects }
            opacity: Math.min(1, tabsOn.value)

            SegmentSwitch {
                id: pageSwitch
                anchors.left: parent.left
                anchors.right: parent.right
                accent: root.accent
                model: [
                    { value: "today", label: Translation.tr("Today"), icon: "today" },
                    { value: "week",  label: Translation.tr("Week"),  icon: "calendar_month" },
                    { value: "apps",  label: Translation.tr("Apps"),  icon: "apps" },
                ]
                current: root.page
                onPicked: function (value) { root.page = value }
            }
        }

        Item {
            id: pagesBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            clip: true
            visible: root.hasData || hv.value > 0.5
            // As tall as the page you are on, within the room the dock has: past that the page scrolls. It
            // follows the page on a spring (no overshoot — a panel that bounces its own size reads as a glitch),
            // so a short page never leaves empty room under it.
            readonly property real wanted: root.hasData
                ? [todayPage, weekPage, appsPage][Math.max(0, root._pageOrder.indexOf(root.page))].implicitHeight : 0
            readonly property real chrome: root.margin * 2 + hero.height + mainCol.spacing * 2
                                           + tabs.height + (header.visible ? header.height + mainCol.spacing : 0)
            readonly property real room: root.maxHeight > 0 ? Math.max(Tokens.sideCardUnit * 3, root.maxHeight - pagesBox.chrome)
                                                            : 100000
            implicitHeight: Math.min(hv.value, pagesBox.room)
            SpringValue { id: hv; target: pagesBox.wanted; spec: Motion.springEffects; epsilon: 0.5 }
            Component.onCompleted: hv.jump(pagesBox.wanted)

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: hv.value
                interactive: hv.value > pagesBox.height + 1
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ScreenTimeTodayView { id: todayPage; panel: root }
                ScreenTimeWeekView  { id: weekPage;  panel: root }
                ScreenTimeAppsView  { id: appsPage;  panel: root }
            }
        }
    }
}
