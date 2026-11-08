pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimePage — Sidebar & dock › Screen time ─────────────────────────────
// services/ScreenTime: whether it counts, how long it keeps what it counted, when you
// count as away, the history (components/ScreenTimeView — the sidebar panel's own view,
// with more apps), and forgetting it all.
//
// The switch in the heading is COUNTING (Config.screenTime). Whether the button stands
// on the sidebar is the Sidebar tab's chip, a separate thing: the counting runs with
// the button gone, and the button says "off" when nothing is counting.
//
// The week is what you came to read, so it stays; the two sliders and the wipe are
// under "What counts" — set once, rarely touched.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    ArmLatch {
        id: forgetLatch
        onConfirmed: ScreenTime.clear()
    }

    readonly property int daysKept: Object.keys(ScreenTime.days).length

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F051F}"
        title:     Translation.tr("Screen")
        titleTail: "time"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.screenTime ? "Off — nothing is being recorded"
                 : "Today " + (ScreenTime.duration(ScreenTime.todayTotal) || "nothing yet")
                   + (ScreenTime.weekAverage > 0 ? "  ·  " + ScreenTime.duration(ScreenTime.weekAverage) + " a day this week" : "")
                   + (ScreenTime.away ? "  ·  paused, you're away" : "")

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            checked: Config.screenTime
            onToggled: Config.screenTime = !Config.screenTime
        }

        // ══ History ═══════════════════════════════════════════════════════════
        // The week itself is the page: live, the bars grow as today's minutes do.
        Section {
            span:     3
            glyph:    "\u{F0128}"
            title:    Translation.tr("This week")
            subtitle: Config.screenTime ? "Pick a day to read it" : "Turn it on above"
            help:     Translation.tr("App names and minutes, kept on this computer only — never window titles.")
            accent:   Colors.of(QsWindow.window).primary

            ScreenTimeView {
                Layout.fillWidth: true
                Layout.fillHeight: false
                rows: 6
            }
        }

        // ══ What counts ═══════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󰔟"
            title:  Translation.tr("What counts")
            help:   Translation.tr("The focused window's app counts while you're at the machine. Idle time doesn't, unless something keeps the screen awake (a video playing). Locked time never does.")
            accent: Colors.of(QsWindow.window).primary

            SliderRow {
                label: Translation.tr("Away after")
                help:  Translation.tr("With no input for this long, you count as away and the clock stops.")
                from:  1
                to:    30
                step:  1
                value: Config.screenTimeIdleMinutes
                readout: Config.screenTimeIdleMinutes + " min"
                numberWidth: 52
                onCommit: function (v) { Config.screenTimeIdleMinutes = Math.round(v) }
            }
        }

        Section {
            span:   1
            glyph:  "󰋚"
            title:  Translation.tr("Kept")
            subtitle: root.daysKept + (root.daysKept === 1 ? " day recorded" : " days recorded")
            accent: Colors.of(QsWindow.window).primary

            actions: PanelButton {
                capsule: true
                label: forgetLatch.armed ? "Sure?" : "Forget all"
                variant: forgetLatch.armed ? "primary" : "ghost"
                accent: Colors.of(QsWindow.window).danger
                enabled: root.daysKept > 0
                onActivated: forgetLatch.trigger()
            }

            SliderRow {
                label: Translation.tr("Keep")
                help:  Translation.tr("Days older than this are dropped.")
                from:  7
                to:    90
                step:  1
                value: Config.screenTimeKeepDays
                readout: Config.screenTimeKeepDays + " days"
                numberWidth: 60
                onCommit: function (v) { Config.screenTimeKeepDays = Math.round(v) }
            }
        }
    }
}
