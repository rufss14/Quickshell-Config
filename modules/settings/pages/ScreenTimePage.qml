pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimePage — Apps & tools › Screen time ───────────────────────────────
// services/ScreenTime: whether it counts, how long it keeps what it counted, when you
// count as away, the history (components/ScreenTimeView — the sidebar panel's own view,
// with more apps), and forgetting it all.
//
// The switch is COUNTING (Config.screenTime), in the week's own card. Whether the button stands
// on the sidebar is the Sidebar tab's chip, a separate thing: the counting runs with
// the button gone, and the button says "off" when nothing is counting.
//
// The week is what you came to read, so it is the loud card; the two sliders and the wipe
// are grouped rows under it, set once and rarely touched.
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

        grouped:   true
        glyph:     "\u{F051F}"
        title:     Translation.tr("Screen")
        titleTail: "time"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.screenTime ? Translation.tr("Off, nothing is being recorded")
                 : Translation.tr("Today %1").arg(ScreenTime.duration(ScreenTime.todayTotal) || Translation.tr("nothing yet"))
                   + (ScreenTime.weekAverage > 0 ? "  ·  " + Translation.tr("%1 a day this week").arg(ScreenTime.duration(ScreenTime.weekAverage)) : "")
                   + (ScreenTime.away ? "  ·  " + Translation.tr("paused, you're away") : "")

        // ══ History ═══════════════════════════════════════════════════════════
        // The week itself is the page: live, the bars grow as today's minutes do. The chart
        // draws in the palette's primary tints, which would vanish on the loud card, so it sits
        // on a lifted well inside it (a picture's canvas).
        Section {
            id: weekHero
            hero:     true
            title:    Translation.tr("This week")
            subtitle: Config.screenTime ? Translation.tr("Pick a day to read it") : Translation.tr("Switch it on to start counting")
            help:     Translation.tr("App names and minutes, kept on this computer only, never window titles.")

            // The master switch says what it is and which way it is set.
            actions: [
                StyledText {
                    Layout.alignment: Qt.AlignVCenter
                    text: Config.screenTime ? Translation.tr("Counting") : Translation.tr("Not counting")
                    variant: "label"
                    color: weekHero.inkDim
                },
                Toggle {
                    accent:  Colors.of(QsWindow.window).primary
                    accessibleName: Translation.tr("Screen time")
                    checked: Config.screenTime
                    onToggled: Config.screenTime = !Config.screenTime
                }
            ]

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                // Concentric with the card: its radius less the card's padding.
                radius: Tokens.radiusXl - weekHero.padding
                color: Colors.of(QsWindow.window).surfaceHigh
                implicitHeight: view.implicitHeight + Tokens.spacingLg * 2

                ScreenTimeView {
                    id: view
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingLg
                    rows: 6
                }
            }
        }

        // ══ What counts ═══════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "hourglass_empty"
            title:   Translation.tr("What counts")
            help:    Translation.tr("The focused window's app counts while you're at the machine. Idle time doesn't, unless something keeps the screen awake (a video playing). Locked time never does.")

            SliderRow {
                label: Translation.tr("Away after")
                help:  Translation.tr("With no input for this long, you count as away and the clock stops.")
                from:  1
                to:    30
                step:  1
                value: Config.screenTimeIdleMinutes
                readout: ScreenTime.duration(Config.screenTimeIdleMinutes * 60)
                numberWidth: 52
                onCommit: function (v) { Config.screenTimeIdleMinutes = Math.round(v) }
            }

            SliderRow {
                label: Translation.tr("Daily goal")
                help:  Translation.tr("A limit for the day, in hours. The panel draws a ring round today's card toward it and counts the days you stayed under. Off: no ring, and the run is just days in a row.")
                from:  0
                to:    960
                step:  15
                value: Config.screenTimeGoalMinutes
                readout: Config.screenTimeGoalMinutes === 0 ? Translation.tr("Off") : ScreenTime.duration(Config.screenTimeGoalMinutes * 60)
                numberWidth: 72
                onCommit: function (v) { Config.screenTimeGoalMinutes = Math.round(v) }
            }
        }

        Section {
            grouped:  true
            symbol:   "history"
            title:    Translation.tr("Kept")
            subtitle: root.daysKept === 1 ? Translation.tr("1 day recorded") : Translation.tr("%1 days recorded").arg(root.daysKept)

            actions: PanelButton {
                capsule: true
                label: forgetLatch.armed ? Translation.tr("Sure?") : Translation.tr("Forget all")
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
                readout: Translation.tr("%1 days").arg(Config.screenTimeKeepDays)
                numberWidth: 60
                onCommit: function (v) { Config.screenTimeKeepDays = Math.round(v) }
            }
        }
    }
}
