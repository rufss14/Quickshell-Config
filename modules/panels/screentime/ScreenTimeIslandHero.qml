pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeIslandHero ── part of ScreenTimePanel.qml (island form); `panel` is the ScreenTimePanel. ─────
// The page's loud card on an island, standing upright in the left column over the source rail (the wallpaper and
// colour pages' recipe; ScreenTimeHero is the wide card of the bar's and the sidebar's panel):
//
//   top     a badge that blooms and turns while it counts (a disc while off), what it is doing ("Counting",
//           the app under it), and the two tools: pause for 30 minutes / resume, and stop
//   middle  today as a big number, how it compares (pace against your usual hours, else against the other
//           days), and the goal as a bar when one is set
//   foot    the day in 24 bars (ScreenTimeDayStrip); pointing at one reads that hour out in the line above
//   off     what it would record and one loud Start pill, in place of all of that
//
// It owns nothing: the numbers are ScreenTime's; the tools write ScreenTime.pause/resume and Config.screenTime.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool on: Config.screenTime
    readonly property bool paused: hero.on && ScreenTime.paused
    readonly property bool away: hero.on && !hero.paused && ScreenTime.away
    readonly property bool live: hero.on && ScreenTime.counting
    readonly property real goal: ScreenTime.goalSeconds
    readonly property color ink: hero.palette.fgOnPrimaryContainer
    readonly property color inkDim: hero.palette.alpha(hero.palette.fgOnPrimaryContainer, 0.72)

    radius: Tokens.radiusXl
    color: hero.palette.primaryContainer

    readonly property int pauseLeft: {
        void Clock.now
        return Math.max(1, Math.ceil((ScreenTime.pausedUntil - Date.now()) / 60000))
    }
    readonly property string state1: !hero.on ? Translation.tr("Off")
        : hero.paused ? Translation.tr("Paused")
        : hero.away ? Translation.tr("You're away")
        : hero.live ? Translation.tr("Counting")
        : Translation.tr("Nothing in focus")
    readonly property string state2: !hero.on ? Translation.tr("Nothing is recorded")
        : hero.paused ? Translation.tr("%1 m left").arg(hero.pauseLeft)
        : hero.away ? Translation.tr("Paused until you're back")
        : hero.live ? ScreenTime.labelOf(ScreenTime.app)
        : ""
    // Pace, else (no earlier day has hours yet) today's total against the other days'.
    readonly property string compare: {
        const p = ScreenTime.pace
        if (p) {
            const d = ScreenTime.duration(Math.abs(p.ahead))
            return p.dir === 0 ? Translation.tr("On usual pace")
                 : p.dir > 0 ? Translation.tr("%1 ahead of usual").arg(d)
                 :             Translation.tr("%1 behind usual").arg(d)
        }
        const v = ScreenTime.versus
        if (!v) return Translation.tr("Today")
        return v.dir === 0 ? Translation.tr("About usual")
             : v.dir > 0 ? Translation.tr("%1% above usual").arg(v.pct)
             :             Translation.tr("%1% below usual").arg(v.pct)
    }
    // The line under the number: the hour you point at, else how today compares.
    readonly property string under: {
        const h = strip.hovered
        if (h < 0) return hero.compare
        const pad = n => (n < 10 ? "0" : "") + n
        return Translation.tr("%1:00 to %2:00 · %3").arg(pad(h)).arg(pad((h + 1) % 24))
                   .arg(ScreenTime.duration(ScreenTime.todayHours[h]) || Translation.tr("nothing"))
    }

    // ── Counting, or counted ──────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm
        visible: hero.on || ScreenTime.todayTotal > 0
        opacity: visible ? 1 : 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingMd
                implicitHeight: implicitWidth
                MorphShape {
                    id: badge
                    anchors.fill: parent
                    shape: hero.live ? "cookie9" : hero.paused ? "squircle" : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: hero.palette.primary
                }
                // Turns while it counts, and only with motion on.
                NumberAnimation {
                    target: badge
                    property: "rotation"
                    from: 0; to: 360
                    duration: 24000
                    loops: Animation.Infinite
                    running: hero.live && Motion.ambientOn && hero.visible
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: hero.paused ? "pause" : "hourglass_top"
                    fill: 1
                    font.pixelSize: Tokens.iconLg
                    color: hero.palette.fgOnPrimary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: hero.state1
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: hero.state2
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }
            }
            ChipButton {
                visible: hero.on
                symbol: hero.paused ? "play_arrow" : "pause"
                tint: hero.ink
                Accessible.name: hero.paused ? Translation.tr("Resume") : Translation.tr("Pause for 30 minutes")
                onActivated: hero.paused ? ScreenTime.resume() : ScreenTime.pause(30)
                HoverTip { text: hero.paused ? Translation.tr("Resume") : Translation.tr("Pause for 30 minutes"); alignEnd: true }
            }
            ChipButton {
                symbol: hero.on ? "stop" : "play_arrow"
                tint: hero.ink
                Accessible.name: hero.on ? Translation.tr("Stop counting") : Translation.tr("Start counting")
                onActivated: Config.screenTime = !Config.screenTime
                HoverTip { text: hero.on ? Translation.tr("Stop counting") : Translation.tr("Start counting"); alignEnd: true }
            }
        }

        Item { Layout.fillHeight: true; Layout.fillWidth: true }

        StyledText {
            Layout.fillWidth: true
            text: ScreenTime.duration(ScreenTime.todayTotal) || Translation.tr("Nothing yet")
            font.pixelSize: Tokens.fontDisplay * 2
            font.weight: Font.Bold
            font.features: ({ tnum: 1 })
            color: hero.ink
            elide: Text.ElideRight
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Tokens.fontDisplay
        }
        StyledText {
            Layout.fillWidth: true
            text: hero.under
            variant: "caption"
            color: hero.inkDim
            elide: Text.ElideRight
        }
        // Toward the daily goal, when there is one: past it the bar is full and the line says by how much.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: hero.goal > 0
            spacing: Tokens.spacingXs
            Meter {
                Layout.fillWidth: true
                value: hero.goal > 0 ? Math.min(1, ScreenTime.todayTotal / hero.goal) : 0
                accent: hero.ink
            }
            StyledText {
                Layout.fillWidth: true
                readonly property real d: ScreenTime.todayTotal - hero.goal
                text: d > 0 ? Translation.tr("%1 over your goal").arg(ScreenTime.duration(d))
                            : Translation.tr("%1 left of your goal").arg(ScreenTime.duration(-d) || Translation.tr("No time"))
                variant: "micro"
                color: hero.inkDim
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true; Layout.fillWidth: true }

        ScreenTimeDayStrip {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: false
            ink: hero.ink
            accent: hero.palette.primary
        }
    }

    // ── Off, and nothing recorded today ───────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd
        visible: !hero.on && ScreenTime.todayTotal <= 0

        MorphShape {
            Layout.preferredWidth: Tokens.iconXl * 2
            Layout.preferredHeight: Tokens.iconXl * 2
            shape: "circle"
            fillColor: hero.palette.primary
            MaterialIcon {
                anchors.centerIn: parent
                name: "hourglass_top"
                fill: 1
                font.pixelSize: Tokens.iconXl
                color: hero.palette.fgOnPrimary
            }
        }
        Item { Layout.fillHeight: true }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Screen time is off")
            variant: "title"
            font.weight: Font.DemiBold
            color: hero.ink
        }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Counts the app in focus while you're at the computer, kept on this computer only.")
            variant: "caption"
            color: hero.inkDim
            wrapMode: Text.Wrap
        }
        ChipButton {
            solid: true
            symbol: "play_arrow"
            label: Translation.tr("Start counting")
            onActivated: Config.screenTime = true
        }
    }
}
