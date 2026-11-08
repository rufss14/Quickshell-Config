pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../config"
import "../services"

// ── ScreenTimeView ────────────────────────────────────────────────────────────
// services/ScreenTime drawn: the last seven days as STACKED bars — each day split into the
// week's three biggest apps (tints of the accent, the biggest at the bottom) and "other" —
// click one to read that day; and the picked day's apps, longest first, each with a bar
// against the day's longest. The sidebar's ScreenTimePanel and Settings › Screen time both
// show this one.
//
//     3h ┤        ▇
//        │  ▅     █   ▆
//        │  █  ▃  █ ▂ █  ▇
//        └──M──T──W─T─F──S──S
//     ● Zen Browser 9h   ● Hollow Knight: Silksong 6h   ● kitty 2h   ○ other
//     Today · 3 h 12 m
//     ◉ Zen Browser    ━━━━━━━━━━━━━━  1 h 40 m
//     ◉ Hollow Knight  ━━━━━━━         52 m
//
// ── Why stacked ───────────────────────────────────────────────────────────────
// A bar per day says how long; it does not say what on. The same seven bars, cut by app,
// answer both, and the legend under them names what the tints are — a Steam game by its
// title (ScreenTime.nameOf), not by a window class.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    // How many apps the day lists.
    property int rows: 6
    // The day being read ("" = today).
    property string picked: ""
    readonly property string day: root.picked !== "" ? root.picked : ScreenTime.todayKey
    readonly property var dayRow: ScreenTime.week.find(d => d.key === root.day) ?? null
    readonly property var apps: ScreenTime.topApps(root.day, root.rows)
    readonly property real dayTotal: root.dayRow ? root.dayRow.seconds : 0
    readonly property real longest: root.apps.length > 0 ? root.apps[0].seconds : 1
    readonly property real weekMax: Math.max(60, ...ScreenTime.week.map(d => d.seconds))

    readonly property int chartH: Tokens.sideCardUnit * 2

    // ── What the tints mean ───────────────────────────────────────────────────
    // The week's three biggest apps, whole week, so a colour stands for one app in every bar.
    readonly property var weekApps: {
        const tot = ({})
        for (const d of ScreenTime.week) {
            const m = ScreenTime.dayFor(d.key)
            for (const k in m) tot[k] = (tot[k] || 0) + m[k]
        }
        return Object.keys(tot).map(k => ({ app: k, seconds: tot[k] }))
                     .sort((a, b) => b.seconds - a.seconds).slice(0, 3)
    }
    // The accent at three strengths: monochrome-safe (the palette may well be grey), and
    // one family rather than three hues fighting for the eye.
    readonly property var tints: [1.0, 0.62, 0.36]
    function tintOf(rank) {
        return rank < 3 ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, root.tints[rank])
                        : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.20)
    }
    function rankOf(app) { return root.weekApps.findIndex(a => a.app === app) }

    // One day cut into its stack, bottom first: [{ rank, seconds, from }].
    function segments(key) {
        const day = ScreenTime.dayFor(key)
        let total = 0
        for (const k in day) total += day[k]
        const out = []
        let from = 0
        for (let i = 0; i < root.weekApps.length; i++) {
            const s = day[root.weekApps[i].app] || 0
            if (s <= 0) continue
            out.push({ rank: i, seconds: s, from: from })
            from += s
        }
        if (total - from > 0) out.push({ rank: 3, seconds: total - from, from: from })
        return out
    }

    // What an app is called in a list: a Steam game by its title, anything else by its
    // desktop entry, failing that as the window class said it.
    function label(app) {
        const g = ScreenTime.nameOf(app)
        return g !== "" ? g : (Icons.nameForAppId(app) || app)
    }

    spacing: Tokens.spacingMd

    // ── The week ──────────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: root.chartH + labels.implicitHeight + Tokens.spacingSm

        // Gridlines at half and full, labelled on the left.
        Repeater {
            model: [1.0, 0.5]
            Item {
                id: grid
                required property real modelData
                anchors.left: parent.left
                anchors.right: parent.right
                y: root.chartH * (1 - grid.modelData)
                height: 1
                Rectangle {
                    anchors.left: gridLabel.right
                    anchors.leftMargin: Tokens.spacingXs
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: Tokens.borderWidth
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                }
                StyledText {
                    id: gridLabel
                    anchors.verticalCenter: parent.verticalCenter
                    width: 28
                    text: ScreenTime.short(root.weekMax * grid.modelData)
                    variant: "micro"
                    emphasis: "dim"
                }
            }
        }

        Row {
            id: bars
            anchors.left: parent.left
            anchors.leftMargin: 28 + Tokens.spacingSm
            anchors.right: parent.right
            height: root.chartH
            spacing: Tokens.spacingSm
            readonly property real barW: (width - spacing * 6) / 7

            Repeater {
                model: ScreenTime.week
                Item {
                    id: bar
                    required property var modelData
                    required property int index
                    readonly property bool isPicked: bar.modelData.key === root.day
                    readonly property var segs: root.segments(bar.modelData.key)
                    width: bars.barW
                    height: bars.height

                    // Rises on build, in turn.
                    property real grown: 0
                    Component.onCompleted: bar.grown = 1
                    Behavior on grown {
                        SequentialAnimation {
                            PauseAnimation { duration: Math.min(bar.index * Motion.stagger, Motion.staggerCap) }
                            NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline
                                              easing.bezierCurve: Motion.emphasizedDecel }
                        }
                    }

                    // The empty track, so a day with nothing is still a place you can click.
                    Rectangle {
                        anchors.fill: parent
                        radius: Math.min(width / 2, Tokens.radiusSm)
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, barMouse.containsMouse ? 0.09 : 0.05)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    // The stack. Clipped to a rounded shape, segments are plain rectangles.
                    ClippingRectangle {
                        id: stack
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: Math.max(Tokens.spacingXs, parent.height * bar.modelData.seconds / root.weekMax) * bar.grown
                        radius: Math.min(width / 2, Tokens.radiusSm)
                        color: "transparent"
                        opacity: bar.isPicked ? 1.0 : barMouse.containsMouse ? 0.85 : 0.55
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        Behavior on height  { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                        // Nothing recorded: a hairline stub rather than a hole.
                        Rectangle {
                            anchors.fill: parent
                            visible: bar.segs.length === 0
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                        }

                        Repeater {
                            model: bar.segs
                            Rectangle {
                                required property var modelData
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: parent.height * modelData.seconds / Math.max(1, bar.modelData.seconds)
                                y: parent.height - parent.height * (modelData.from + modelData.seconds) / Math.max(1, bar.modelData.seconds)
                                color: root.tintOf(modelData.rank)
                            }
                        }
                    }

                    // The reading, above the bar you point at or have picked.
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        y: Math.max(0, stack.y - height - 2)
                        opacity: (bar.isPicked || barMouse.containsMouse) && bar.modelData.seconds > 0 ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        text: ScreenTime.short(bar.modelData.seconds)
                        variant: "micro"
                        font.weight: Font.DemiBold
                    }

                    MouseArea {
                        id: barMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.picked = bar.modelData.today ? "" : bar.modelData.key
                    }
                }
            }
        }

        // The week's average, dashed across the bars.
        Item {
            visible: ScreenTime.weekAverage > 0
            anchors.left: bars.left
            anchors.right: bars.right
            y: root.chartH - root.chartH * ScreenTime.weekAverage / root.weekMax
            height: 1
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
            Row {
                anchors.fill: parent
                spacing: 4
                Repeater {
                    // Clamped: mid-layout `bars` is narrower than its own margin, and a negative
                    // count logged "Model size of -4 is less than 0" each time the view opened.
                    model: Math.max(0, Math.ceil(bars.width / 8))
                    Rectangle {
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
                model: ScreenTime.week
                StyledText {
                    required property var modelData
                    width: bars.barW
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData.label.slice(0, 3)
                    variant: "caption"
                    color: modelData.key === root.day ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                    font.weight: modelData.key === root.day ? Font.DemiBold : Font.Normal
                }
            }
        }
    }

    // ── What the tints are ────────────────────────────────────────────────────
    Flow {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingLg
        visible: root.weekApps.length > 0

        Repeater {
            model: root.weekApps
            Row {
                required property var modelData
                required property int index
                spacing: Tokens.spacingXs
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.spacingSm + 2; height: width; radius: width / 2
                    color: root.tintOf(parent.index)
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.label(parent.modelData.app)
                    variant: "caption"
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: ScreenTime.short(parent.modelData.seconds)
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
        Row {
            spacing: Tokens.spacingXs
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Tokens.spacingSm + 2; height: width; radius: width / 2
                color: root.tintOf(3)
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Translation.tr("Other")
                variant: "caption"
                emphasis: "dim"
            }
        }
    }

    // ── The picked day ────────────────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm
        StyledText {
            text: root.dayRow?.today ?? true ? "Today" : (root.dayRow?.label ?? "") + "  " + root.day.slice(5).replace("-", "/")
            variant: "label"
            font.weight: Font.DemiBold
        }
        StyledText {
            Layout.fillWidth: true
            text: root.dayTotal > 0 ? "·  " + ScreenTime.duration(root.dayTotal) : ""
            variant: "label"
            emphasis: "dim"
        }
        StyledText {
            visible: ScreenTime.weekAverage > 0
            text: "avg " + ScreenTime.duration(ScreenTime.weekAverage)
            variant: "caption"
            emphasis: "dim"
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.apps.length === 0
        text: Translation.tr("Nothing recorded on this day.")
        variant: "caption"
        emphasis: "dim"
    }

    Repeater {
        model: root.apps
        RowLayout {
            id: appRow
            required property var modelData
            readonly property string icon: ScreenTime.nameOf(appRow.modelData.app) !== "" ? "" : Icons.pathForAppId(appRow.modelData.app)
            readonly property bool game: ScreenTime.nameOf(appRow.modelData.app) !== ""
            readonly property int rank: root.rankOf(appRow.modelData.app)
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            Item {
                Layout.preferredWidth: Tokens.iconLg
                Layout.preferredHeight: Tokens.iconLg
                Image {
                    anchors.fill: parent
                    visible: appRow.icon !== ""
                    source: appRow.icon
                    sourceSize: Qt.size(Tokens.iconLg * 2, Tokens.iconLg * 2)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: appRow.icon === ""
                    name: appRow.game ? "sports_esports" : "apps"
                    color: Colors.of(QsWindow.window).fgMuted
                    font.pixelSize: Tokens.iconLg
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    StyledText {
                        Layout.fillWidth: true
                        text: root.label(appRow.modelData.app)
                        variant: "label"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        text: ScreenTime.duration(appRow.modelData.seconds)
                        variant: "caption"
                        font.family: Tokens.fontMono
                        emphasis: "dim"
                    }
                }
                Meter {
                    Layout.fillWidth: true
                    value: appRow.modelData.seconds / root.longest
                    // The tint it wears in the chart, so a row and its slice of the bars match.
                    accent: appRow.rank >= 0 ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, root.tints[appRow.rank])
                                             : Colors.of(QsWindow.window).primary
                }
            }
        }
    }
}
