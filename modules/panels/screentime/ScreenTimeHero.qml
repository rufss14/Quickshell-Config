pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeHero ── part of ScreenTimePanel.qml; `panel` is the ScreenTimePanel it belongs to. ─────────
// Today as the panel's subject, above the pages (so it is there on all three). Redone 2026-11-08 (round 3):
//
//   Row 1  an M3E badge (a wavy ring toward the daily goal round a shape that turns while it counts), the state
//          — "Counting · kitty", "Paused · 24 m left", "You're away" — and Pause (30 minutes, resumes by
//          itself) and Stop. Off, the badge is a disc and the one button is Start.
//   Row 2  a BIG number, tap it to cycle today → this stretch → this week (the number slides and fades, the
//          badge morphs to that stat's own shape, three dots say where you are); beside it the top app on a
//          plate with its time. Under the number, the line reads out the bar you point at below.
//   Row 3  the day strip: 24 bars, one per hour (ScreenTimeDayStrip).
//   Row 4  chips on springs: pace ("40 m ahead of usual pace", from the hourly numbers; "43% above usual" until
//          there are earlier days with hours), yesterday, the daily goal with − and + (or "Set a daily goal"),
//          and the run of days kept to it.
//
// A top app that is a Steam game lays its header picture behind the card's right side (Gamemode's art finder).
// It owns nothing: the numbers are ScreenTime's; the buttons write ScreenTime.pause/resume and Config.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property bool on: Config.screenTime
    readonly property bool paused: hero.on && ScreenTime.paused
    readonly property bool away: hero.on && !hero.paused && ScreenTime.away
    readonly property bool live: hero.on && ScreenTime.counting
    readonly property string topApp: ScreenTime.topToday
    readonly property var versus: ScreenTime.versus
    readonly property var pace: ScreenTime.pace
    readonly property real goal: ScreenTime.goalSeconds
    readonly property bool over: hero.on && hero.goal > 0 && ScreenTime.todayTotal > hero.goal
    readonly property color ink: hero.live ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                           : Colors.of(QsWindow.window).fg

    Layout.fillWidth: true
    implicitHeight: heroCol.implicitHeight + panel.cardPad * 2
    radius: Tokens.radiusXl
    color: hero.live ? Colors.of(QsWindow.window).primaryContainer : Colors.of(QsWindow.window).section
    Behavior on color { ColorAnimation { duration: Motion.standard } }

    // ── The stat the big number shows ─────────────────────────────────────────
    // `mode` is what was asked for, `shown` what is on screen: they differ for the half-second the number is
    // out of sight, so the swap happens while it cannot be seen.
    property int mode: 0
    property int shown: 0
    readonly property var _modeShapes: ["cookie9", "sunny", "clover"]
    readonly property real stretch: {
        void Clock.now
        return ScreenTime.stretchStart > 0 ? (Date.now() - ScreenTime.stretchStart) / 1000 : 0
    }
    readonly property real weekTotal: ScreenTime.week.reduce((s, d) => s + d.seconds, 0)
    readonly property string statValue: hero.shown === 1 ? (hero.live ? (ScreenTime.duration(hero.stretch) || Translation.tr("Just started")) : "—")
                                      : hero.shown === 2 ? (ScreenTime.duration(hero.weekTotal) || "—")
                                      :                    (ScreenTime.duration(ScreenTime.todayTotal) || Translation.tr("Nothing yet"))
    readonly property string statCaption: hero.shown === 1 ? (hero.live ? Translation.tr("This stretch · %1").arg(ScreenTime.labelOf(ScreenTime.app))
                                                                       : Translation.tr("This stretch"))
                                        : hero.shown === 2 ? Translation.tr("This week")
                                        :                    Translation.tr("Today")
    function cycle() {
        let m = hero.mode
        do { m = (m + 1) % 3 } while (m === 1 && !hero.live)
        hero.mode = m
        flip.restart()
    }
    // Without motion there is nothing to hide the swap behind: do it at once.
    onModeChanged: if (!Config.motionEnabled) hero.shown = hero.mode

    // ── Lines ─────────────────────────────────────────────────────────────────
    readonly property int pauseLeft: {
        void Clock.now
        return Math.max(1, Math.ceil((ScreenTime.pausedUntil - Date.now()) / 60000))
    }
    readonly property string _line: {
        if (!hero.on) return Translation.tr("Screen time is off")
        if (hero.paused) return Translation.tr("Paused · %1 m left").arg(hero.pauseLeft)
        if (hero.away) return Translation.tr("You're away · paused")
        if (hero.live) return Translation.tr("Counting · %1").arg(ScreenTime.labelOf(ScreenTime.app))
        return Translation.tr("Nothing in focus")
    }
    // Pace, else (no earlier day has hours yet) today's total against the other days'.
    readonly property var _pace: {
        const p = hero.pace
        if (p) {
            const d = ScreenTime.duration(Math.abs(p.ahead))
            return { dir: p.dir, text: p.dir === 0 ? Translation.tr("On usual pace")
                                     : p.dir > 0 ? Translation.tr("%1 ahead of usual pace").arg(d)
                                     :             Translation.tr("%1 behind usual pace").arg(d) }
        }
        const v = hero.versus
        if (!v) return null
        return { dir: v.dir, text: v.dir === 0 ? Translation.tr("About usual")
                                 : v.dir > 0 ? Translation.tr("%1% above usual").arg(v.pct)
                                 :             Translation.tr("%1% below usual").arg(v.pct) }
    }
    readonly property string _goalText: {
        if (!hero.on || hero.goal <= 0) return ""
        const d = ScreenTime.todayTotal - hero.goal
        return d > 0 ? Translation.tr("%1 over your goal").arg(ScreenTime.duration(d))
                     : Translation.tr("%1 left of your goal").arg(ScreenTime.duration(-d) || Translation.tr("No time"))
    }
    readonly property string _streakText: {
        const n = ScreenTime.streak
        if (!hero.on || n < 2) return ""
        return hero.goal > 0 ? Translation.tr("%1 days under goal").arg(n) : Translation.tr("%1 days in a row").arg(n)
    }
    // The line under the number: the hour you point at, else what the number is.
    readonly property string _under: {
        const h = strip.hovered
        if (h < 0) return hero.statCaption
        const pad = n => (n < 10 ? "0" : "") + n
        return pad(h) + ":00 – " + pad((h + 1) % 24) + ":00 · "
             + (ScreenTime.duration(ScreenTime.todayHours[h]) || Translation.tr("nothing"))
    }

    // The goal in 30-minute steps; at the bottom a step turns it off, and from off the first tap picks a goal near
    // the week's average (an hour at least), so it starts somewhere sensible.
    function nudgeGoal(dir) {
        const cur = Config.screenTimeGoalMinutes
        const next = cur + dir * 30
        Config.screenTimeGoalMinutes = next < 30 ? 0 : Math.min(960, next)
    }
    function startGoal() {
        Config.screenTimeGoalMinutes = Math.min(960, Math.max(60, Math.ceil(ScreenTime.weekAverage / 1800) * 30))
    }

    // The top app's header picture, when it is a Steam game. Asked for from a handler, never a binding.
    function _askArt() {
        const id = ScreenTime.steamIdOf(hero.topApp)
        if (id !== "") Gamemode.requestArt(id)
    }
    onTopAppChanged: hero._askArt()
    Component.onCompleted: hero._askArt()
    readonly property string art: Gamemode.artPaths[ScreenTime.steamIdOf(hero.topApp)] ?? ""

    ClippingRectangle {
        anchors.fill: parent
        radius: hero.radius
        color: "transparent"
        opacity: hero.on && artImg.status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.slow } }
        Image {
            id: artImg
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * 0.6
            fillMode: Image.PreserveAspectCrop
            horizontalAlignment: Image.AlignLeft
            sourceSize.width: 720
            source: hero.art !== "" ? "file://" + hero.art : ""
        }
        Rectangle {
            anchors.fill: artImg
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: hero.color }
                GradientStop { position: 0.7; color: Colors.of(QsWindow.window).alpha(hero.color, 0) }
            }
        }
    }

    ColumnLayout {
        id: heroCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: panel.cardPad
        spacing: Tokens.spacingMd

        // ── Row 1: the badge, the state, Pause and Stop ───────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            // A disc at rest, a squircle while away or paused, and while it counts a shape that follows the stat on
            // show, turning slowly (a RotationAnimator: render thread, the outline is not rebuilt). Starting sends two
            // rings off it. The wavy ring round it is the daily goal; it turns to the warning colour once passed.
            Item {
                id: badge
                Layout.alignment: Qt.AlignVCenter
                Layout.preferredWidth: Tokens.iconXl * 1.5 + Tokens.spacingMd
                Layout.preferredHeight: Tokens.iconXl * 1.5 + Tokens.spacingMd

                RadialGauge {
                    anchors.fill: parent
                    visible: hero.on && hero.goal > 0
                    thickness: Tokens.spacingSm
                    wavy: true
                    accent: hero.over ? Colors.of(QsWindow.window).warning : panel.accent
                    value: hero.goal > 0 ? Math.min(1, ScreenTime.todayTotal / hero.goal) : 0
                }
                Repeater {
                    model: 2
                    delegate: Rectangle {
                        id: ring
                        required property int index
                        anchors.centerIn: parent
                        width: parent.width
                        height: width
                        radius: width / 2
                        color: "transparent"
                        border.width: Tokens.borderWidth * 2
                        border.color: panel.accent
                        opacity: 0
                        SequentialAnimation {
                            id: ringAnim
                            PauseAnimation { duration: ring.index * Motion.respond * 2 }
                            ParallelAnimation {
                                NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.6; duration: Motion.ripple; easing.type: Motion.travel }
                                NumberAnimation { target: ring; property: "opacity"; from: 0.55; to: 0; duration: Motion.ripple }
                            }
                        }
                        Connections {
                            target: Config
                            function onScreenTimeChanged() { if (Config.screenTime && Config.motionEnabled) ringAnim.restart() }
                        }
                    }
                }
                Item {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    RotationAnimator on rotation {
                        running: hero.live && Motion.ambientOn
                        from: 0; to: 360
                        duration: Motion.glide * 40
                        loops: Animation.Infinite
                    }
                    MorphShape {
                        anchors.fill: parent
                        shape: hero.live ? hero._modeShapes[hero.mode] : hero.on ? "squircle" : "circle"
                        fillColor: hero.live ? panel.accent : Colors.of(QsWindow.window).surfaceHigh
                    }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: !hero.on ? "hourglass_empty" : hero.paused ? "pause_circle" : hero.away ? "bedtime" : "hourglass_top"
                    fill: hero.live ? 1 : 0
                    font.pixelSize: Tokens.iconLg
                    color: hero.live ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fgMuted
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                text: hero._line
                variant: "label"
                font.weight: Font.Medium
                color: hero.ink
                elide: Text.ElideRight
            }

            // Pause: not for a while — counting resumes by itself after 30 minutes. Stop is the real off switch and
            // keeps what was counted.
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                visible: hero.on
                variant: "normal"
                accent: panel.accent
                symbol: hero.paused ? "play_arrow" : "pause"
                onActivated: hero.paused ? ScreenTime.resume() : ScreenTime.pause(30)
            }
            PanelButton {
                Layout.alignment: Qt.AlignVCenter
                capsule: true
                variant: hero.on ? "normal" : "primary"
                accent: panel.accent
                symbol: hero.on ? "power_settings_new" : "play_arrow"
                label: hero.on ? Translation.tr("Stop") : Translation.tr("Start")
                onActivated: Config.screenTime = !Config.screenTime
            }
        }

        // ── Off: what it would do ─────────────────────────────────────────────
        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !hero.on
            text: Translation.tr("Counts the app in focus, only while you're here. Kept on this computer, never window titles.")
            variant: "caption"
            color: hero.ink
            opacity: 0.72
            wrapMode: Text.WordWrap
        }

        // ── Row 2: the big number, and the top app ────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: hero.on
            spacing: Tokens.spacingLg

            // Tap to cycle. The number leaves upward and the next arrives from below.
            Item {
                id: numBox
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                implicitHeight: numCol.implicitHeight
                Accessible.role: Accessible.Button
                Accessible.name: hero.statCaption + ": " + hero.statValue
                Accessible.onPressAction: hero.cycle()

                ColumnLayout {
                    id: numCol
                    width: parent.width
                    spacing: 0
                    transform: Translate { id: numShift }
                    StyledText {
                        id: num
                        Layout.fillWidth: true
                        text: hero.statValue
                        font.pixelSize: Math.round(Tokens.fontDisplay * 1.8)
                        font.weight: Font.DemiBold
                        color: hero.ink
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: hero._under
                            variant: "label"
                            color: hero.ink
                            opacity: 0.8
                            elide: Text.ElideRight
                        }
                        // Where you are among the three stats.
                        Row {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: Tokens.spacingXs
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    id: dot
                                    required property int index
                                    readonly property bool cur: hero.mode === dot.index
                                    SpringValue { id: dw; target: dot.cur ? Tokens.spacingLg : Tokens.spacingXs * 2; spec: Motion.springSpatialFast }
                                    width: dw.value
                                    height: Tokens.spacingXs * 2
                                    radius: height / 2
                                    color: Colors.of(QsWindow.window).alpha(hero.ink, dot.cur ? 0.85 : 0.3)
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                }
                            }
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: hero.cycle()
                }

                SequentialAnimation {
                    id: flip
                    ParallelAnimation {
                        NumberAnimation { target: numCol; property: "opacity"; to: 0; duration: Motion.fast; easing.type: Motion.exitCurve }
                        NumberAnimation { target: numShift; property: "y"; to: -Tokens.spacingLg; duration: Motion.fast; easing.type: Motion.exitCurve }
                    }
                    ScriptAction { script: { hero.shown = hero.mode; numShift.y = Tokens.spacingLg } }
                    ParallelAnimation {
                        NumberAnimation { target: numCol; property: "opacity"; to: 1; duration: Motion.standard; easing.type: Motion.travel }
                        NumberAnimation { target: numShift; property: "y"; to: 0; duration: Motion.standard; easing.type: Motion.travel }
                    }
                }
            }

            // The top app on a plate, with its time under it. It pops in when there is one.
            ColumnLayout {
                id: topBox
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                visible: pop.value > 0.01
                spacing: Tokens.spacingXs
                SpringReveal { id: pop; when: hero.on && hero.topApp !== ""; spec: Motion.springSpatial }
                opacity: Math.min(1, pop.value)
                scale: 0.8 + 0.2 * Math.min(1.1, pop.value)

                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.iconXl * 2
                    Layout.preferredHeight: Tokens.iconXl * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).alpha(hero.ink, 0.12)
                    readonly property string icon: ScreenTime.iconOf(hero.topApp)
                    Image {
                        anchors.centerIn: parent
                        width: Tokens.iconXl
                        height: Tokens.iconXl
                        visible: parent.icon !== ""
                        source: parent.icon
                        sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        layer.enabled: Config.colorizeIcons
                        layer.effect: MonoIconEffect {}
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: parent.icon === ""
                        name: ScreenTime.isGame(hero.topApp) ? "sports_esports" : "apps"
                        color: hero.ink
                        font.pixelSize: Tokens.iconXl
                    }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: Tokens.iconXl * 2 + Tokens.spacingLg
                    text: Translation.tr("Top · %1").arg(ScreenTime.short(ScreenTime.todayFor(hero.topApp)))
                    variant: "micro"
                    font.weight: Font.Medium
                    color: hero.ink
                    elide: Text.ElideRight
                }
            }
        }

        // ── Row 3: the day, hour by hour ──────────────────────────────────────
        ScreenTimeDayStrip {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: hero.on
            ink: hero.ink
            accent: panel.accent
        }

        // ── Row 4: chips ──────────────────────────────────────────────────────
        // The wrapper's height rides a spring, so the card grows for them rather than jumping.
        Item {
            id: chipBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            readonly property bool any: hero.on
            implicitHeight: chipH.value
            clip: true
            SpringValue { id: chipH; target: chipBox.any ? chips.implicitHeight : 0; spec: Motion.springEffects; epsilon: 0.5 }
            Component.onCompleted: chipH.jump(chipBox.any ? chips.implicitHeight : 0)

            Flow {
                id: chips
                width: parent.width
                spacing: Tokens.spacingSm

                // Ahead of usual is tinted (a stronger day); behind or level is neutral: no verdict in a colour.
                ScreenTimeChip {
                    shown: hero.on && hero._pace !== null
                    symbol: hero._pace && hero._pace.dir > 0 ? "arrow_upward" : hero._pace && hero._pace.dir < 0 ? "arrow_downward" : "remove"
                    text: hero._pace ? hero._pace.text : ""
                    ink: hero.ink
                    plate: hero._pace && hero._pace.dir > 0 ? Colors.of(QsWindow.window).alpha(panel.accent, 0.32)
                                                            : Colors.of(QsWindow.window).alpha(hero.ink, 0.12)
                }
                ScreenTimeChip {
                    shown: hero.on && ScreenTime.yesterday > 0
                    symbol: "history"
                    text: Translation.tr("Yesterday %1").arg(ScreenTime.duration(ScreenTime.yesterday))
                    ink: hero.ink
                    plate: Colors.of(QsWindow.window).alpha(hero.ink, 0.12)
                }
                // The goal: − and + move it in 30-minute steps; with none set, one tap picks a start.
                ScreenTimeChip {
                    shown: hero.on
                    symbol: "timer"
                    stepper: hero.goal > 0
                    tappable: hero.goal <= 0
                    text: hero.goal > 0 ? hero._goalText : Translation.tr("Set a daily goal")
                    ink: hero.ink
                    plate: hero.over ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.36)
                                     : Colors.of(QsWindow.window).alpha(hero.ink, 0.12)
                    onStepped: dir => hero.nudgeGoal(dir)
                    onTapped: hero.startGoal()
                }
                ScreenTimeChip {
                    shown: hero._streakText !== ""
                    symbol: "bolt"
                    text: hero._streakText
                    ink: hero.ink
                    plate: Colors.of(QsWindow.window).alpha(hero.ink, 0.12)
                }
            }
        }
    }
}
