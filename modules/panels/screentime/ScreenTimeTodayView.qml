pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeTodayView ── part of ScreenTimePanel.qml; `panel` is the ScreenTimePanel it belongs to. ───
// The glance: three stat tiles (the daily average, the week with its seven days as a sparkline, the busiest day),
// what is in focus right now (its icon on a cookie, its time today, how long this stretch has run), and today
// cut by app as one capsule of beads, the biggest first, over icon tiles that name them. The beads' widths ride
// springs and grow in from nothing each time the page slides in; pointing at a tile lights its bead.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: page
    required property var panel
    readonly property int idx: 0
    readonly property bool current: panel.page === "today"
    width: panel.pagesBox.width
    x: (page.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(page.idx - panel.pg.value) * 1.4)
    visible: page.opacity > 0.01
    spacing: Tokens.spacingSm

    // ── What the tiles say ────────────────────────────────────────────────────
    readonly property real weekTotal: ScreenTime.week.reduce((s, d) => s + d.seconds, 0)
    readonly property var best: ScreenTime.week.reduce((b, d) => d.seconds > b.seconds ? d : b, ({ seconds: 0, label: "" }))
    readonly property var tiles: [
        { value: ScreenTime.duration(ScreenTime.weekAverage) || "—", caption: Translation.tr("per day") },
        { value: ScreenTime.duration(page.weekTotal) || "—",         caption: Translation.tr("this week") },
        { value: ScreenTime.duration(page.best.seconds) || "—",
          caption: page.best.seconds > 0 ? Translation.tr("best · %1").arg(page.best.label) : Translation.tr("best day") }
    ]

    // The bead under the pointer's tile (0-3), -1 for none: the others dim.
    property int focusRank: -1

    // How long the app in focus has had it, in seconds; Clock ticks once a minute, which is all a minutes readout needs.
    readonly property real stretch: {
        void Clock.now
        return ScreenTime.stretchStart > 0 ? (Date.now() - ScreenTime.stretchStart) / 1000 : 0
    }

    // Today's three biggest apps, and the day cut against them: slot 0-2 are those apps, slot 3 the rest.
    readonly property var shareApps: ScreenTime.topApps(ScreenTime.todayKey, 3)
    readonly property var segs: ScreenTime.segments(ScreenTime.todayKey, page.shareApps)
    readonly property real total: Math.max(1, ScreenTime.todayTotal)
    function shareOf(slot) { return (page.segs.find(s => s.rank === slot)?.seconds ?? 0) / page.total }

    // ── Tiles ─────────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        Repeater {
            model: 3
            delegate: Rectangle {
                id: tile
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredWidth: tile.index === 1 ? 1.5 : 1
                implicitHeight: tileCol.implicitHeight + panel.cardPad * 2
                radius: Tokens.radiusCard
                color: Colors.of(QsWindow.window).section

                // Rises into place one after another, each time the page comes in.
                SpringReveal { id: rise; when: page.current; delay: tile.index * Motion.stagger * 2; spec: Motion.springSpatial }
                opacity: Math.min(1, rise.value)
                transform: Translate { y: (1 - rise.value) * Tokens.spacingLg }

                // The week tile's seven days, oldest left, today in the accent: it says the shape of the week where
                // the number says only the sum. Rises with the tile.
                Item {
                    id: sparkBox
                    visible: tile.index === 1
                    anchors.right: parent.right
                    anchors.rightMargin: panel.cardPad
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: panel.cardPad
                    width: Tokens.spacingSm * 7 + Tokens.spacingXs * 6
                    height: Tokens.iconLg
                    readonly property real peak: Math.max(60, ...ScreenTime.week.map(d => d.seconds))
                    Repeater {
                        model: 7
                        delegate: Rectangle {
                            id: spark
                            required property int index
                            readonly property var day: ScreenTime.week[spark.index] ?? ({ seconds: 0, today: false })
                            SpringValue { id: sh; target: spark.day.seconds / sparkBox.peak; spec: Motion.springSpatial; epsilon: 0.0005 }
                            readonly property real h: Math.max(Tokens.spacingXs, (sparkBox.height - Tokens.spacingXs) * Math.max(0, sh.value) * Math.min(1, rise.value) + Tokens.spacingXs)
                            x: spark.index * (Tokens.spacingSm + Tokens.spacingXs)
                            y: sparkBox.height - spark.h
                            width: Tokens.spacingSm
                            height: spark.h
                            radius: width / 2
                            color: spark.day.today ? panel.accent : Colors.of(QsWindow.window).alpha(panel.accent, 0.35)
                        }
                    }
                }

                ColumnLayout {
                    id: tileCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: panel.cardPad
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: page.tiles[tile.index].value
                        variant: "title"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: page.tiles[tile.index].caption
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ── Right now ─────────────────────────────────────────────────────────────
    Rectangle {
        id: now
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Config.screenTime
        implicitHeight: nowCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        readonly property bool live: ScreenTime.counting
        readonly property string app: ScreenTime.app
        readonly property string icon: ScreenTime.iconOf(now.app)
        readonly property real today: ScreenTime.todayFor(now.app)

        ColumnLayout {
            id: nowCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                // The app on a cookie, full size. It morphs to a disc when nothing counts.
                Item {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Tokens.iconXl * 2
                    Layout.preferredHeight: Tokens.iconXl * 2
                    MorphShape {
                        anchors.fill: parent
                        shape: now.live ? "cookie9" : "circle"
                        fillColor: now.live ? Colors.of(QsWindow.window).alpha(panel.accent, 0.22)
                                            : Colors.of(QsWindow.window).surfaceHigh
                    }
                    Image {
                        anchors.centerIn: parent
                        width: Tokens.iconXl
                        height: Tokens.iconXl
                        visible: now.live && now.icon !== ""
                        source: now.live ? now.icon : ""
                        sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        layer.enabled: Config.colorizeIcons
                        layer.effect: MonoIconEffect {}
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !(now.live && now.icon !== "")
                        name: !now.live ? (ScreenTime.away ? "bedtime" : "hourglass_empty")
                                        : ScreenTime.isGame(now.app) ? "sports_esports" : "apps"
                        color: now.live ? panel.accent : Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconXl
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: now.live ? ScreenTime.labelOf(now.app)
                            : ScreenTime.away ? Translation.tr("You're away") : Translation.tr("Nothing in focus")
                        variant: "title"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: now.live ? Translation.tr("%1 today").arg(ScreenTime.duration(now.today) || Translation.tr("just started"))
                            : ScreenTime.away ? Translation.tr("Counting resumes when you're back")
                            : Translation.tr("Counts once a window has focus")
                        variant: "label"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: now.live
                        text: Translation.tr("This stretch: %1").arg(ScreenTime.duration(page.stretch) || Translation.tr("just started"))
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                // A live dot that breathes while it counts.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: Tokens.spacingMd
                    Layout.preferredHeight: Tokens.spacingMd
                    radius: width / 2
                    color: panel.accent
                    visible: now.live
                    SequentialAnimation on opacity {
                        running: now.live && Motion.ambientOn
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.25; duration: Motion.glide * 2; easing.type: Motion.ambient }
                        NumberAnimation { from: 0.25; to: 1; duration: Motion.glide * 2; easing.type: Motion.ambient }
                    }
                }
            }

            // This app's part of the day: what it has against everything today.
            Meter {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: now.live && ScreenTime.todayTotal > 0
                value: now.today / Math.max(1, ScreenTime.todayTotal)
                accent: panel.accent
            }
        }
    }

    // ── Today, by app ─────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: shareCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: shareCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingMd

            StyledText {
                text: ScreenTime.todayTotal > 0 ? Translation.tr("Today, by app") : Translation.tr("Nothing recorded today yet")
                variant: "caption"
                emphasis: "dim"
            }

            // Beads: one capsule per slot, each as wide as its share of the day.
            Item {
                id: beads
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: Tokens.spacingXl

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                }
                Row {
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: 4
                        delegate: Rectangle {
                            id: bead
                            required property int index
                            readonly property real share: page.shareOf(bead.index)
                            SpringReveal { id: grow; when: page.current; delay: bead.index * Motion.stagger * 3; spec: Motion.springEffects }
                            SpringValue { id: w; target: bead.share * beads.width; spec: Motion.springEffects; epsilon: 0.3 }
                            width: Math.max(0, w.value * Math.min(1, grow.value) - Tokens.spacingXs)
                            height: beads.height
                            radius: height / 2
                            visible: width > 1
                            color: panel.tint(bead.index)
                            opacity: page.focusRank < 0 || page.focusRank === bead.index ? 1 : 0.25
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }
                    }
                }
            }

            // What the beads are: today's three biggest apps and the rest, as icon tiles (the week's own).
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: ScreenTime.todayTotal > 0

                Repeater {
                    model: 4
                    delegate: ScreenTimeAppTile {
                        id: key
                        required property int index
                        panel: page.panel
                        readonly property var app: page.shareApps[key.index] ?? null
                        rank: key.index
                        other: key.index === 3
                        appId: key.app?.app ?? ""
                        detail: Math.round(page.shareOf(key.index) * 100) + "%"
                        when: page.current
                        delay: 200 + key.index * Motion.stagger * 2
                        Layout.fillWidth: key.index < 3
                        Layout.fillHeight: false
                        Layout.preferredWidth: key.index === 3 ? Tokens.sideCardUnit * 1.3 : 1
                        visible: key.index === 3 ? page.shareOf(3) > 0 : key.app !== null
                        onHoveredChanged: {
                            if (key.hovered) page.focusRank = key.index
                            else if (page.focusRank === key.index) page.focusRank = -1
                        }
                    }
                }
            }
        }
    }
}
