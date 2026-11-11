pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── ScreenTimeWeekView ── part of ScreenTimePanel.qml; `panel` is the ScreenTimePanel it belongs to. ─────
// The last seven days as stacked bars — each day cut into the week's three biggest apps (tints of the accent,
// the biggest at the bottom) and "other" — and, under them, the last month as a strip of heat squares.
// Pointing at a bar or square reads it; clicking one picks that day (the Apps page lists it).
//
//     3h ┤        ▇
//        │  ▅     █   ▆            ┌─────┐  the day you picked sits on a plate that
//        │  █  ▃  █ ▂ █  ▇         │  ▇  │  slides along the bars on a spring
//        └──M──T──W─T─F──S──S      └─────┘
//     ● Zen Browser 9h   ● Silksong 6h   ● kitty 2h   ○ other
//     ▢▢▣▣▢▣▣▣▢▢▣▣▣▣▣   Last 30 days
//
// The bars, the legend and the squares are fixed slots read live (`ScreenTime.week[i]`), never a model rebuilt
// from the data: the data moves every 30 seconds while counting, and a rebuilt Repeater would replay every
// entrance each time.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: page
    required property var panel
    readonly property int idx: 1
    readonly property bool current: panel.page === "week"
    width: panel.pagesBox.width
    x: (page.idx - panel.pg.value) * panel.pagesBox.width
    opacity: Math.max(0, 1 - Math.abs(page.idx - panel.pg.value) * 1.4)
    visible: page.opacity > 0.01
    spacing: Tokens.spacingSm

    readonly property real weekMax: Math.max(60, ...ScreenTime.week.map(d => d.seconds))
    readonly property int chartH: Tokens.sideCardUnit * 2
    readonly property int gutter: 28
    // Where the picked day sits in the week (-1: it is further back than the week, a heat square picked it).
    readonly property int pickedIndex: ScreenTime.week.findIndex(d => d.key === panel.day)
    readonly property var weekApps: ScreenTime.weekApps
    // The rank (0-3) of the legend tile under the pointer, -1 for none: its slice is lit in every bar, the rest dim.
    property int focusRank: -1
    // The picked day's three biggest apps, for the icon strip beside its total.
    readonly property var dayTop: ScreenTime.topApps(panel.day, 3)

    // ── The week ──────────────────────────────────────────────────────────────
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: chartCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        ColumnLayout {
            id: chartCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Last 7 days")
                    variant: "caption"
                    emphasis: "dim"
                }
                StyledText {
                    visible: ScreenTime.weekAverage > 0
                    text: Translation.tr("avg %1").arg(ScreenTime.duration(ScreenTime.weekAverage))
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            Item {
                id: chart
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: page.chartH + labels.implicitHeight + Tokens.spacingSm

                // Gridlines at half and full, labelled on the left.
                Repeater {
                    model: [1.0, 0.5]
                    delegate: Item {
                        id: gridLine
                        required property real modelData
                        anchors.left: parent.left
                        anchors.right: parent.right
                        y: page.chartH * (1 - gridLine.modelData)
                        height: 1
                        StyledText {
                            id: gridLabel
                            anchors.verticalCenter: parent.verticalCenter
                            width: page.gutter
                            text: ScreenTime.short(page.weekMax * gridLine.modelData)
                            variant: "micro"
                            emphasis: "dim"
                        }
                        Rectangle {
                            anchors.left: gridLabel.right
                            anchors.leftMargin: Tokens.spacingXs
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            height: Tokens.borderWidth
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                        }
                    }
                }

                // The plate behind the picked day: it slides to a new one on a spring (a little overshoot,
                // as the page switch's indicator has), and shrinks away when the pick is off the week.
                SpringValue { id: plateX; target: Math.max(0, page.pickedIndex) * (bars.barW + bars.spacing); spec: Motion.springSpatial }
                SpringValue { id: plateOn; target: page.pickedIndex >= 0 ? 1 : 0; spec: Motion.springEffects }
                Rectangle {
                    x: bars.x + plateX.value - bars.spacing / 2
                    width: bars.barW + bars.spacing
                    height: parent.height
                    radius: Tokens.radiusSm + Tokens.spacingXs
                    color: Colors.of(QsWindow.window).alpha(panel.accent, 0.14)
                    opacity: Math.min(1, plateOn.value)
                    scale: 0.9 + 0.1 * Math.min(1, plateOn.value)
                }

                Row {
                    id: bars
                    anchors.left: parent.left
                    anchors.leftMargin: page.gutter + Tokens.spacingSm
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingXs
                    height: page.chartH
                    spacing: Tokens.spacingSm
                    readonly property real barW: (width - spacing * 6) / 7

                    Repeater {
                        model: 7
                        delegate: Item {
                            id: bar
                            required property int index
                            readonly property var day: ScreenTime.week[bar.index] ?? ({ key: "", seconds: 0, today: false, label: "" })
                            readonly property var segs: ScreenTime.segments(bar.day.key)
                            readonly property bool isPicked: bar.day.key === panel.day
                            width: bars.barW
                            height: bars.height

                            // Rises in turn each time the page comes in; the height then follows the day's total
                            // on its own spring, so a minute credited lifts the bar rather than snapping it.
                            SpringReveal { id: rise; when: page.current; delay: bar.index * Motion.stagger * 2 }
                            SpringValue { id: level; target: bar.day.seconds / page.weekMax; spec: Motion.springSpatial; epsilon: 0.0005 }
                            SpringValue { id: lift; target: barMouse.containsMouse && !bar.isPicked ? 1 : 0; spec: Motion.springSpatialFast }

                            // The empty track, so a day with nothing is still a place you can click.
                            Rectangle {
                                anchors.fill: parent
                                radius: Math.min(width / 2, Tokens.radiusSm)
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
                            }

                            // The stack: segments are plain rectangles inside a rounded clip.
                            ClippingRectangle {
                                id: stack
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: Math.max(Tokens.spacingXs, bar.height * level.value) * Math.max(0, rise.value)
                                radius: Math.min(width / 2, Tokens.radiusSm)
                                color: "transparent"
                                opacity: bar.isPicked ? 1.0 : 0.55 + 0.3 * lift.value
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                                // Nothing recorded: a hairline stub rather than a hole.
                                Rectangle {
                                    anchors.fill: parent
                                    visible: bar.segs.length === 0
                                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                                }
                                Repeater {
                                    model: bar.segs
                                    delegate: Rectangle {
                                        required property var modelData
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        height: parent.height * modelData.seconds / Math.max(1, bar.day.seconds)
                                        y: parent.height - parent.height * (modelData.from + modelData.seconds) / Math.max(1, bar.day.seconds)
                                        color: panel.tint(modelData.rank)
                                        opacity: page.focusRank < 0 || page.focusRank === modelData.rank ? 1 : 0.25
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                    }
                                }
                            }

                            // The reading, above the bar you point at or have picked.
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: Math.max(0, stack.y - height - Tokens.spacingXs)
                                opacity: (bar.isPicked || barMouse.containsMouse) && bar.day.seconds > 0 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                text: ScreenTime.short(bar.day.seconds)
                                variant: "micro"
                                font.weight: Font.DemiBold
                            }

                            MouseArea {
                                id: barMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.pick(bar.day.key)
                            }
                        }
                    }
                }

                // The week's average, dashed across the bars; it moves with the data.
                Item {
                    visible: ScreenTime.weekAverage > 0
                    anchors.left: bars.left
                    anchors.right: bars.right
                    height: 1
                    SpringValue { id: avgY; target: page.chartH - page.chartH * ScreenTime.weekAverage / page.weekMax; spec: Motion.springEffects; epsilon: 0.2 }
                    y: avgY.value
                    Row {
                        anchors.fill: parent
                        spacing: 4
                        Repeater {
                            // Clamped: mid-layout `bars` is narrower than its own margin, and a negative
                            // count logged "Model size of -4 is less than 0" each time the view opened.
                            model: Math.max(0, Math.ceil(bars.width / 8))
                            delegate: Rectangle {
                                width: 4
                                height: Tokens.borderWidth
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.45)
                            }
                        }
                    }
                }

                Row {
                    id: labels
                    anchors.top: bars.bottom
                    anchors.topMargin: Tokens.spacingXs
                    anchors.left: bars.left
                    spacing: bars.spacing
                    Repeater {
                        model: 7
                        delegate: StyledText {
                            id: dayLabel
                            required property int index
                            readonly property var day: ScreenTime.week[dayLabel.index] ?? ({ key: "", label: "" })
                            width: bars.barW
                            horizontalAlignment: Text.AlignHCenter
                            text: dayLabel.day.label.slice(0, 3)
                            variant: "caption"
                            color: dayLabel.day.key === panel.day ? panel.accent : Colors.of(QsWindow.window).fgDim
                            font.weight: dayLabel.day.key === panel.day ? Font.DemiBold : Font.Normal
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                    }
                }
            }

            // What the tints are: the week's three biggest apps and the rest, as icon tiles. Pointing at one lights its
            // slice in every bar and dims the rest.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: page.weekApps.length > 0

                Repeater {
                    model: 4
                    delegate: ScreenTimeAppTile {
                        id: key
                        required property int index
                        panel: page.panel
                        readonly property var app: page.weekApps[key.index] ?? null
                        readonly property real seconds: key.index === 3
                            ? Math.max(0, ScreenTime.week.reduce((s, d) => s + d.seconds, 0) - page.weekApps.reduce((s, a) => s + a.seconds, 0))
                            : (key.app?.seconds ?? 0)
                        rank: key.index
                        other: key.index === 3
                        appId: key.app?.app ?? ""
                        detail: ScreenTime.short(key.seconds)
                        when: page.current
                        delay: 200 + key.index * Motion.stagger * 2
                        Layout.fillWidth: key.index < 3
                        Layout.fillHeight: false
                        Layout.preferredWidth: key.index === 3 ? Tokens.sideCardUnit * 1.3 : 1
                        visible: key.index === 3 ? key.seconds > 0 : key.app !== null
                        onHoveredChanged: {
                            if (key.hovered) page.focusRank = key.index
                            else if (page.focusRank === key.index) page.focusRank = -1
                        }
                    }
                }
            }
        }
    }

    // ── The picked day ────────────────────────────────────────────────────────
    // What you pointed at or picked, with the way to its apps.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.leftMargin: Tokens.spacingSm
        spacing: Tokens.spacingSm
        StyledText {
            text: panel.dayLabel
            variant: "label"
            font.weight: Font.DemiBold
        }
        StyledText {
            Layout.fillWidth: true
            text: panel.dayRow && panel.dayRow.seconds > 0 ? "·  " + ScreenTime.duration(panel.dayRow.seconds)
                                                           : "·  " + Translation.tr("nothing recorded")
            variant: "label"
            emphasis: "dim"
            elide: Text.ElideRight
        }
        // The day's biggest apps as icons, overlapping, so a day reads without opening Apps. Each pops in.
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: -Tokens.spacingSm
            Repeater {
                model: 3
                delegate: Item {
                    id: dayIcon
                    required property int index
                    readonly property var app: page.dayTop[dayIcon.index] ?? null
                    readonly property string icon: dayIcon.app ? ScreenTime.iconOf(dayIcon.app.app) : ""
                    SpringValue { id: shown; target: dayIcon.app ? 1 : 0; spec: Motion.springSpatial }
                    width: Tokens.iconLg + Tokens.spacingMd
                    height: width
                    visible: shown.value > 0.01
                    scale: Math.max(0, shown.value)
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Colors.of(QsWindow.window).surfaceHigh
                        border.width: Tokens.borderWidth * 2
                        border.color: Colors.of(QsWindow.window).surfaceContainer
                    }
                    Image {
                        anchors.centerIn: parent
                        width: Tokens.iconMd + Tokens.spacingXs
                        height: width
                        visible: dayIcon.icon !== ""
                        source: dayIcon.icon
                        sourceSize: Qt.size(width * 2, width * 2)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        layer.enabled: Config.colorizeIcons
                        layer.effect: MonoIconEffect {}
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: dayIcon.icon === "" && dayIcon.app !== null
                        name: dayIcon.app && ScreenTime.isGame(dayIcon.app.app) ? "sports_esports" : "apps"
                        color: Colors.of(QsWindow.window).fgMuted
                        font.pixelSize: Tokens.iconMd
                    }
                }
            }
        }
        ChipButton {
            symbol: "apps"
            label: Translation.tr("Apps")
            tint: panel.accent
            enabled: panel.dayRow ? panel.dayRow.seconds > 0 : false
            onActivated: panel.go("apps")
        }
    }

    // ── The month ─────────────────────────────────────────────────────────────
    Rectangle {
        id: monthCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: monthCol.implicitHeight + panel.cardPad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        readonly property int count: ScreenTime.month.length
        readonly property int cols: monthCard.count <= 14 ? monthCard.count : Math.ceil(monthCard.count / 2)
        readonly property real cell: Math.min(Tokens.iconXl + Tokens.spacingSm,
            (grid.width - Tokens.spacingXs * (monthCard.cols - 1)) / Math.max(1, monthCard.cols))
        // The square under the pointer, read in the card's own header.
        property int hovered: -1
        readonly property var hoveredDay: monthCard.hovered >= 0 ? (ScreenTime.month[monthCard.hovered] ?? null) : null

        ColumnLayout {
            id: monthCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: panel.cardPad
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                StyledText {
                    Layout.fillWidth: true
                    text: monthCard.hoveredDay
                        ? monthCard.hoveredDay.label + " " + monthCard.hoveredDay.key.slice(5).replace("-", "/") + "  ·  "
                          + (ScreenTime.duration(monthCard.hoveredDay.seconds) || Translation.tr("nothing"))
                        : Translation.tr("Last %1 days").arg(monthCard.count)
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
                // The scale: less … more.
                Row {
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            width: Tokens.spacingMd; height: width; radius: Tokens.radiusSm
                            color: panel.heatTint(index)
                        }
                    }
                }
            }

            Flow {
                id: grid
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                Repeater {
                    model: monthCard.count
                    delegate: Item {
                        id: sq
                        required property int index
                        readonly property var day: ScreenTime.month[sq.index] ?? ({ key: "", seconds: 0 })
                        readonly property bool isPicked: sq.day.key === panel.day
                        width: monthCard.cell
                        height: monthCard.cell

                        SpringReveal { id: pop; when: page.current; delay: Math.min(sq.index * Motion.stagger / 2, Motion.staggerCap * 2); spec: Motion.springSpatial }
                        SpringValue { id: hov; target: sqMouse.containsMouse ? 1 : 0; spec: Motion.springSpatialFast }
                        scale: Math.max(0, pop.value) * (1 + 0.18 * hov.value)
                        opacity: Math.min(1, pop.value * 1.5)

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.max(Tokens.radiusSm, width / 3.2)
                            color: panel.heatTint(ScreenTime.heat(sq.day.seconds))
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                            // The picked day wears the selection ring.
                            border.width: sq.isPicked ? Tokens.borderWidth * 2 : 0
                            border.color: Colors.of(QsWindow.window).focus
                        }
                        MouseArea {
                            id: sqMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onContainsMouseChanged: {
                                if (containsMouse) monthCard.hovered = sq.index
                                else if (monthCard.hovered === sq.index) monthCard.hovered = -1
                            }
                            onClicked: panel.pick(sq.day.key)
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: Config.screenTimeKeepDays < 30
                text: Translation.tr("Only the last %1 days are kept. Settings › Screen time changes that.").arg(Config.screenTimeKeepDays)
                variant: "micro"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }
    }
}
