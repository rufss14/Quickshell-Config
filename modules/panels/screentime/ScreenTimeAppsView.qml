pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeAppsView ── part of ScreenTimePanel.qml; `panel` is the ScreenTimePanel it belongs to. ─────
// One day's apps, longest first. Each is a row with a wavy ring — its share of THAT day, the app's picture in
// the hole — its name, its time, a thin bar in the tint it wears on the Week page, and the share as a number.
// Tap a row and it opens a seven-day chart of that one app (one open at a time). The arrows step through the
// days (the Week page's bars and squares pick one too); the rings fill in, row after row, each time a day is opened.
//
// The rows are stable: the list of app ids is replaced only when the ORDER changes, and a row reads its seconds
// live (`dayFor(day)[app]`). The data moves every 30 seconds while counting; a model rebuilt from it would
// replay every entrance each time.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: page
    required property var panel
    readonly property int idx: 2
    readonly property bool current: panel.page === "apps"
    width: panel.pagesBox.width
    x: (page.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(page.idx - panel.pg.value) * 1.4)
    visible: page.opacity > 0.01
    spacing: Tokens.spacingSm

    readonly property int rows: 8
    readonly property var wanted: ScreenTime.topApps(panel.day, page.rows).map(a => a.app)
    property var ids: []
    function sync() { if (JSON.stringify(page.wanted) !== JSON.stringify(page.ids)) page.ids = page.wanted }
    onWantedChanged: page.sync()
    Component.onCompleted: page.sync()

    // The app whose seven days are open ("" = none).
    property string openApp: ""
    readonly property real dayTotal: panel.dayRow ? panel.dayRow.seconds : 0

    // ── Which day ─────────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        PanelButton {
            variant: "ghost"
            symbol: "chevron_left"
            enabled: panel.dayIndex > 0
            onActivated: panel.step(-1)
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: panel.dayLabel
                variant: "label"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: page.dayTotal > 0 ? ScreenTime.duration(page.dayTotal) : Translation.tr("nothing recorded")
                variant: "caption"
                emphasis: "dim"
            }
        }
        // Back to today, once you are somewhere else.
        ChipButton {
            visible: panel.picked !== ""
            symbol: "today"
            label: Translation.tr("Today")
            tint: panel.accent
            onActivated: panel.pick("")
        }
        PanelButton {
            variant: "ghost"
            symbol: "chevron_right"
            enabled: panel.dayIndex >= 0 && panel.dayIndex < ScreenTime.month.length - 1
            onActivated: panel.step(1)
        }
    }

    // ── Nothing that day ──────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: page.ids.length === 0
        spacing: Tokens.spacingSm
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Tokens.iconXl * 2
            Layout.preferredHeight: Tokens.iconXl * 2
            MorphShape {
                anchors.fill: parent
                shape: "cookie9"
                fillColor: Colors.of(QsWindow.window).surfaceHigh
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: "hourglass_empty"
                color: Colors.of(QsWindow.window).fgMuted
                font.pixelSize: Tokens.iconXl
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Translation.tr("Nothing recorded on this day")
            variant: "body"; font.weight: Font.Medium
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Config.screenTime ? Translation.tr("Apps appear here once they have had your focus.")
                                    : Translation.tr("Screen time is off, so nothing is being added.")
            variant: "caption"; emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }

    // ── The apps ──────────────────────────────────────────────────────────────
    Repeater {
        model: page.ids
        delegate: Rectangle {
            id: row
            required property int index
            required property string modelData
            readonly property real seconds: ScreenTime.dayFor(panel.day)[row.modelData] ?? 0
            readonly property real share: row.seconds / Math.max(1, page.dayTotal)
            readonly property string icon: ScreenTime.iconOf(row.modelData)
            readonly property bool game: ScreenTime.isGame(row.modelData)
            readonly property bool open: page.openApp === row.modelData
            // The tint the app wears on the Week page (the accent when it is not one of the week's three).
            readonly property int rank: ScreenTime.weekApps.findIndex(a => a.app === row.modelData)
            readonly property real longest: ScreenTime.dayFor(panel.day)[page.ids[0]] ?? 1

            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: rowCol.implicitHeight + Tokens.spacingMd * 2
            radius: Tokens.radiusCard
            // The opened row lifts from the section tone to a solid container.
            color: row.open ? Colors.of(QsWindow.window).surfaceContainer : Colors.of(QsWindow.window).section
            Behavior on color { ColorAnimation { duration: Motion.respond } }

            // Rises into place, row after row; the ring fills once the row is up.
            SpringReveal { id: rise; when: page.current; delay: row.index * Motion.stagger * 2; spec: Motion.springSpatial }
            opacity: Math.min(1, rise.value)
            transform: Translate { y: (1 - rise.value) * Tokens.spacingLg }

            // The seven days open on a spring (no overshoot: the card's height is what moves).
            SpringValue { id: openSp; target: row.open ? 1 : 0; spec: Motion.springEffects; epsilon: 0.002 }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: page.openApp = row.open ? "" : row.modelData
            }

            ColumnLayout {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Tokens.spacingMd
                anchors.leftMargin: Tokens.spacingMd
                anchors.rightMargin: panel.cardPad
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd

                    RadialGauge {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: Tokens.iconXl + Tokens.spacingLg
                        implicitHeight: Tokens.iconXl + Tokens.spacingLg
                        thickness: Tokens.spacingSm
                        wavy: true
                        accent: panel.accent
                        value: rise.value > 0.5 ? row.share : 0

                        Image {
                            anchors.centerIn: parent
                            width: Tokens.iconMd + Tokens.spacingXs
                            height: width
                            visible: row.icon !== ""
                            source: row.icon
                            sourceSize: Qt.size(width * 2, width * 2)
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            layer.enabled: Config.colorizeIcons
                            layer.effect: MonoIconEffect {}
                        }
                        MaterialIcon {
                            anchors.centerIn: parent
                            visible: row.icon === ""
                            name: row.game ? "sports_esports" : "apps"
                            color: Colors.of(QsWindow.window).fgMuted
                            font.pixelSize: Tokens.iconMd + Tokens.spacingXs
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Tokens.spacingXs
                        StyledText {
                            Layout.fillWidth: true
                            text: ScreenTime.labelOf(row.modelData)
                            variant: "label"
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: ScreenTime.duration(row.seconds)
                            variant: "caption"
                            font.family: Tokens.fontMono
                            emphasis: "dim"
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Math.round(row.share * 100) + "%"
                        variant: "title"
                        font.weight: Font.DemiBold
                        color: panel.accent
                    }
                    MaterialIcon {
                        Layout.alignment: Qt.AlignVCenter
                        name: "expand_more"
                        color: Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconMd
                        rotation: 180 * Math.min(1, openSp.value)
                    }
                }

                // Against the day's longest, in the tint it wears on the Week page.
                Meter {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    value: row.seconds / Math.max(1, row.longest)
                    accent: row.rank >= 0 ? panel.tint(row.rank) : panel.accent
                }

                // ── This app's last seven days ───────────────────────────────
                Item {
                    id: week
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: weekCol.implicitHeight * Math.max(0, openSp.value)
                    visible: openSp.value > 0.01
                    clip: true
                    opacity: Math.min(1, openSp.value * 1.5)

                    readonly property var perDay: ScreenTime.week.map(d => ScreenTime.dayFor(d.key)[row.modelData] ?? 0)
                    readonly property real peak: Math.max(60, ...week.perDay)
                    readonly property real total: week.perDay.reduce((s, v) => s + v, 0)
                    readonly property real chartH: Tokens.iconXl + Tokens.spacingMd

                    ColumnLayout {
                        id: weekCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: Tokens.spacingXs

                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Last 7 days · %1").arg(ScreenTime.duration(week.total) || Translation.tr("nothing"))
                            variant: "caption"
                            emphasis: "dim"
                        }
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            implicitHeight: week.chartH
                            readonly property real barW: (width - Tokens.spacingSm * 6) / 7
                            Repeater {
                                model: 7
                                delegate: Rectangle {
                                    id: wb
                                    required property int index
                                    readonly property real v: week.perDay[wb.index] ?? 0
                                    readonly property bool today: ScreenTime.week[wb.index]?.today ?? false
                                    x: wb.index * (parent.barW + Tokens.spacingSm)
                                    width: parent.barW
                                    // Grows with the card opening, then follows the data.
                                    height: Math.max(Tokens.spacingXs, week.chartH * wb.v / week.peak * Math.max(0, openSp.value))
                                    y: week.chartH - height
                                    radius: Math.min(width / 2, Tokens.radiusSm)
                                    color: wb.today ? panel.accent : Colors.of(QsWindow.window).alpha(panel.accent, 0.4)
                                }
                            }
                        }
                        Row {
                            spacing: Tokens.spacingSm
                            Repeater {
                                model: 7
                                delegate: StyledText {
                                    required property int index
                                    width: (weekCol.width - Tokens.spacingSm * 6) / 7
                                    horizontalAlignment: Text.AlignHCenter
                                    text: (ScreenTime.week[index]?.label ?? "").slice(0, 3)
                                    variant: "micro"
                                    emphasis: "dim"
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
