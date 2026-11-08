pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import QtQuick.Shapes
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/weather.js" as W
import "../../services/ics.js" as Ics
import "../../services/holidays.js" as H
import "../../services/dayfacts.js" as Facts
import "../../services/dayplan.js" as Plan
import "../../services/quickadd.js" as Quick
import "../../services/alarms.js" as AL
import "../../services/worldclock.js" as Z

// ClockWeatherView — ClockPanel's weather page, moved into its own file (2026-11-08). Reads and writes
// the panel's state through `panel` (was `root`).
// ══ WEATHER ═══════════════════════════════════════════════════════
ColumnLayout {
    id: weatherView
    // The panel that owns the state and the actions (ClockPanel.qml's root).
    required property var panel
    // Reached into by the panel (keys, the editor, clearing fields).
    property alias ring: ring

    anchors.left:  parent.left
    anchors.right: parent.right
    anchors.top:   parent.top
    spacing: Tokens.spacingMd

    readonly property bool on: panel.view === "weather"
    opacity: on ? 1 : 0
    visible: opacity > 0
    transform: Translate {
        x: weatherView.on ? 0 : -Tokens.spacingXl
        Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
    }
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // ── No location ───────────────────────────────────────────────
    // Search and pick right here — it used to redirect to the Widgets
    // settings page, which meant leaving the panel just to type a city
    // name. Same geocode lookup and Config writes WidgetsPage's own
    // Weather section uses.
    Rectangle {
        id: placeCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !Weather.hasLocation
        implicitHeight: placeCol.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: placeCard; active: panel.weatherOn; delay: panel.lead; rise: Tokens.spacingMd }

        ColumnLayout {
            id: placeCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                MaterialIcon { name: "location_off"; variant: "label"; color: Colors.of(QsWindow.window).fgDim }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Set a location to see the forecast")
                    variant: "label"
                    emphasis: "dim"
                }
                StyledText {
                    visible: Weather.searching
                    text: "…"
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            InputField {
                id: citySearchField
                Layout.fillWidth: true
                implicitHeight: Tokens.iconXl + Tokens.spacingMd
                cornerRadius: implicitHeight / 2
                icon: "search"
                placeholder: Translation.tr("City name, then Enter")
                // A network request — fired on Enter, not per keystroke.
                onAccepted: function (value) { Weather.search(value) }
            }

            Repeater {
                model: Weather.results

                delegate: Item {
                    id: res
                    required property int index
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: resCol.implicitHeight + Tokens.spacingSm * 2

                    PopIn { id: resPop; active: panel.weatherOn; index: res.index }
                    opacity: resPop.opacity
                    scale:   resPop.scale

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusSm
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                        opacity: resHover.hovered ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    }
                    HoverHandler { id: resHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        onTapped: {
                            Config.weatherLat     = res.modelData.lat
                            Config.weatherLon     = res.modelData.lon
                            Config.weatherPlace   = res.modelData.name
                            // The calendar's special dates follow this.
                            Config.weatherCountry = res.modelData.countryCode
                            Weather.results = []
                            citySearchField.clear()
                        }
                    }

                    ColumnLayout {
                        id: resCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingMd
                        spacing: 0
                        StyledText { text: res.modelData.name; variant: "caption" }
                        StyledText { text: res.modelData.detail; variant: "caption"; emphasis: "dim" }
                    }
                }
            }
        }
    }

    // ══ Ring │ the hour ═══════════════════════════════════════════
    Rectangle {
        id: heroCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: heroRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: heroCard; active: panel.weatherOn; delay: panel.lead; rise: Tokens.spacingMd }

        RowLayout {
            id: heroRow
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingXl

            Item {
                id: ring
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.max(ring.extent, heroDetail.implicitHeight)

                // ── Geometry ──────────────────────────────────────────
                readonly property int  count: Math.max(1, panel.ringHours.length)
                readonly property real step: 360 / ring.count
                readonly property real markW: Tokens.iconXl + Tokens.spacingXs
                readonly property real markH: Math.round(Tokens.fontMicro * 1.4 + Tokens.iconMd + Tokens.fontCaption * 1.4)

                // Looking down on the ring at `tilt`, from `camera` away — the
                // shape of the scene, not spacing, so they live here.
                readonly property real tilt:   18 * Math.PI / 180

                // ── Room between hours ────────────────────────────────
                // The radius is whichever is larger: the box's own width, or
                // the radius that holds neighbouring front hours `gap` apart.
                // Past the box's edge the sides are clipped — they've faded out
                // by then. The front's perspective scale doesn't depend on the
                // radius (the camera sits a fixed multiple of it away), which is
                // what lets the spacing be solved for without a loop.
                readonly property real gap: markW + Tokens.spacingLg
                readonly property real frontScale: 4 / (4 - Math.cos(tilt))
                readonly property real radius: Math.max(width / 2 - markW / 2,
                                                        gap * count / (2 * Math.PI) / frontScale)
                readonly property real camera: radius * 4
                clip: true
                readonly property real sFront: camera / (camera - radius * Math.cos(tilt))
                // What you can actually SEE runs from the time's top edge down to
                // the near marker's bottom — the far side has faded out long
                // before. The row takes `extent` as its height; `cy` centres it.
                readonly property real reachUp:   face.height / 2
                readonly property real reachDown: radius * Math.sin(tilt) * sFront + markH * sFront / 2
                readonly property real extent:    reachUp + reachDown + Tokens.spacingSm * 2
                readonly property real cy:        height / 2 - (reachDown - reachUp) / 2

                // → { x, y, s, depth } for a point on the ring at `deg` (0 = front).
                function project(deg) {
                    const t = deg * Math.PI / 180
                    const X = ring.radius * Math.sin(t), Z = ring.radius * Math.cos(t)
                    const s = ring.camera / (ring.camera - Z * Math.cos(ring.tilt))
                    return { x: ring.width / 2 + X * s, y: ring.cy + Z * Math.sin(ring.tilt) * s,
                             s: s, depth: Math.cos(t) }
                }

                // ── Motion ────────────────────────────────────────────
                // Degrees, unbounded. Slot k sits at k·step + ringAngle from the front.
                property real ringAngle: -90
                property real velocity: 0          // °/ms
                property bool dragging: false
                property bool coasting: false
                property bool wheeling: false
                property int  lockedSlot: 0

                readonly property bool interacting: dragging || coasting || wheeling || snap.running
                readonly property int  frontSlot: ((Math.round(-ringAngle / step) % count) + count) % count

                function snapToSlot(k, slow) {
                    let t = -k * ring.step
                    t += Math.round((ring.ringAngle - t) / 360) * 360
                    if (!Config.motionEnabled) {
                        snap.stop()
                        ring.ringAngle = t
                        ring.lockedSlot = k
                        return
                    }
                    snap.duration = slow ? Motion.spatialSlow : Motion.spatial
                    snap.to = t
                    snap.restart()
                }
                function settle() {
                    const n = panel.ringHours.length
                    ring.snapToSlot(n === 0 ? 0 : Math.min(ring.frontSlot, n - 1))
                }
                function grab() {
                    snap.stop()
                    ring.coasting = false
                    ring.velocity = 0
                }

                // The spin in: a quarter turn behind where it rests (now, on today),
                // then onto it on the slow spring. On opening, and every time the
                // page is shown again.
                function arrive() {
                    if (!Config.motionEnabled) return
                    const k = panel.onToday && panel.nowSlot >= 0 ? panel.nowSlot : ring.lockedSlot
                    snap.stop()
                    ring.coasting = false
                    ring.velocity = 0
                    ring.ringAngle = -k * ring.step - 90
                    ring.snapToSlot(k, true)
                }

                NumberAnimation {
                    id: snap
                    target: ring
                    property: "ringAngle"
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring
                    onFinished: ring.lockedSlot = ring.frontSlot
                }

                SequentialAnimation {
                    id: introSpin
                    PauseAnimation { duration: panel.lead }
                    ScriptAction { script: ring.arrive() }
                }
                Connections {
                    target: panel
                    function onWeatherOnChanged() { if (panel.weatherOn) introSpin.restart() }
                }

                // Only while a fling coasts — at rest nothing runs.
                FrameAnimation {
                    running: ring.coasting
                    onTriggered: {
                        const dt = frameTime * 1000
                        ring.ringAngle += ring.velocity * dt
                        ring.velocity *= Math.pow(0.995, dt)
                        if (Math.abs(ring.velocity) < 0.02) {
                            ring.coasting = false
                            ring.settle()
                        }
                    }
                }

                // ── Hours ─────────────────────────────────────────────
                Repeater {
                    model: Weather.ready ? panel.ringHours : []

                    delegate: Item {
                        id: mark
                        required property int index
                        required property var modelData

                        readonly property var  h: modelData.hour
                        readonly property var  p: ring.project(index * ring.step + ring.ringAngle)
                        readonly property real near: (p.depth + 1) / 2
                        readonly property bool focused: index === panel.slot
                        readonly property bool isNow: index === panel.nowSlot
                        readonly property bool past: panel.onToday && h.hour < Clock.hours
                        readonly property bool isMax: index === panel.maxSlot
                        readonly property bool isMin: index === panel.minSlot && panel.minSlot !== panel.maxSlot
                        // Where the ring wraps from 23 back to 00, 00 names the day;
                        // its neighbours drop their numbers so the word has room.
                        readonly property bool dayStart: h.hour === 0
                        readonly property bool besideStart: h.hour === 23 || h.hour === 1

                        width:  ring.markW
                        height: ring.markH
                        x: p.x - width / 2
                        y: p.y - height / 2
                        // Far side behind the time (z 0), near arc in front of it.
                        z: p.depth
                        scale: p.s
                        // Steep, so the sides — where the perspective stacks
                        // neighbours on top of each other — are already gone.
                        // Today's past hours recede; so does every hour of
                        // another day.
                        opacity: Math.pow(mark.near, 4)
                                 * (mark.past ? 0.4 : panel.onToday ? 1 : panel.otherDay + 0.25)
                        visible: opacity > 0.04

                        Column {
                            anchors.centerIn: parent
                            spacing: 0

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: mark.isNow    ? "now"
                                    : mark.dayStart ? panel.dayShort(mark.h.date)
                                    : Clock.pad(mark.h.hour)
                                variant: "micro"
                                font.bold: mark.focused || mark.dayStart || mark.isNow
                                color: mark.focused ? panel.accent
                                     : mark.dayStart ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                                opacity: mark.dayStart || mark.isNow ? (mark.near > 0.6 ? 1 : 0)
                                       : mark.besideStart && !mark.focused ? 0
                                       : mark.near > 0.85 ? 1 : 0
                            }
                            MaterialIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: Weather.symbol(mark.h.code, mark.h.isDay)
                                fill: 0
                                font.pixelSize: Tokens.iconMd
                                color: panel.onToday ? Weather.tint(mark.h.code, mark.h.isDay)
                                                    : Colors.of(QsWindow.window).mix(Weather.tint(mark.h.code, mark.h.isDay), Colors.of(QsWindow.window).fgDim, 0.5)
                            }
                            // The day's high and low wear an arrow and their
                            // colour; every other hour stays plain.
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: (mark.isMax ? "↑" : mark.isMin ? "↓" : "") + Weather.temp(mark.h.tempC) + "°"
                                variant: "caption"
                                font.bold: mark.focused || mark.isMax || mark.isMin
                                color: mark.focused ? panel.accent
                                     : mark.isMax   ? Colors.of(QsWindow.window).warning
                                     : mark.isMin   ? Colors.of(QsWindow.window).info
                                     : Colors.of(QsWindow.window).fg
                                opacity: mark.near > 0.65 || mark.isMax || mark.isMin ? 1 : 0
                            }
                        }

                        // The focus: a short accent stroke under the hour.
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.bottom
                            width:  mark.focused && !ring.interacting ? Tokens.spacingLg : 0
                            height: Tokens.spacingXs
                            radius: height / 2
                            color:  panel.accent
                            Behavior on width {
                                NumberAnimation {
                                    duration: Motion.spatial
                                    easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                }
                            }
                        }
                    }
                }

                // ── The time ──────────────────────────────────────────
                Column {
                    id: face
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.top
                    anchors.verticalCenterOffset: ring.cy
                    spacing: 0

                    FontMetrics { id: bigMetrics;   font.family: Tokens.fontBlock; font.pixelSize: Tokens.fontNumeralMd; font.weight: Font.Bold }
                    FontMetrics { id: smallMetrics; font.family: Tokens.fontBlock; font.pixelSize: Tokens.fontTitle }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        RollText {
                            text: Qt.formatDateTime(panel.now, "HH:mm")
                            family:    Tokens.fontBlock
                            pixelSize: Tokens.fontNumeralMd
                            weight:    Font.Bold
                        }
                        RollText {
                            // Shares the big digits' baseline.
                            y: bigMetrics.ascent - smallMetrics.ascent
                            text: ":" + Qt.formatDateTime(panel.now, "ss")
                            family:    Tokens.fontBlock
                            pixelSize: Tokens.fontTitle
                            color:     panel.accent
                        }
                    }
                    StyledText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDate(panel.now, "ddd, d MMM")
                            + (Weather.hasLocation && !Config.clockPanelHeader() ? "  ·  " + Weather.place : "")
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                // ── Input ─────────────────────────────────────────────
                MouseArea {
                    id: spin
                    anchors.fill: parent
                    z: 2
                    hoverEnabled: true

                    function overFace(x, y) {
                        return Math.abs(x - ring.width / 2) < face.width / 2
                            && Math.abs(y - ring.cy) < face.height / 2
                    }

                    cursorShape: ring.dragging ? Qt.ClosedHandCursor
                               : (spin.overFace(mouseX, mouseY) && !panel.atNow) ? Qt.PointingHandCursor
                               : Qt.OpenHandCursor

                    property real lastX: 0
                    property real lastT: 0
                    property real travelled: 0

                    onPressed: (mouse) => {
                        ring.grab()
                        spin.lastX = mouse.x
                        spin.lastT = Date.now()
                        spin.travelled = 0
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return
                        const dx = mouse.x - spin.lastX
                        const t = Date.now()
                        spin.travelled += Math.abs(dx)
                        if (spin.travelled > Tokens.spacingSm) ring.dragging = true
                        if (ring.dragging) {
                            // Sideways distance as arc length at the front, so the
                            // hour under the pointer keeps pace with it.
                            const d = dx / (ring.radius * ring.sFront) * 180 / Math.PI
                            ring.ringAngle += d
                            const v = d / Math.max(1, t - spin.lastT)
                            ring.velocity = Math.max(-1.5, Math.min(1.5, ring.velocity * 0.6 + v * 0.4))
                        }
                        spin.lastX = mouse.x
                        spin.lastT = t
                    }
                    onReleased: (mouse) => {
                        if (!ring.dragging) {
                            if (spin.overFace(mouse.x, mouse.y)) {
                                if (!panel.atNow) panel.backToNow()
                                return
                            }
                            // The nearest hour under the pointer, preferring the near side.
                            let best = -1, bestDepth = -2
                            for (let k = 0; k < panel.ringHours.length; k++) {
                                const p = ring.project(k * ring.step + ring.ringAngle)
                                const hit = Math.abs(mouse.x - p.x) < ring.markW * p.s / 2
                                         && Math.abs(mouse.y - p.y) < ring.markH * p.s / 2
                                if (hit && p.depth > bestDepth) { best = k; bestDepth = p.depth }
                            }
                            if (best >= 0) ring.snapToSlot(best)
                            else ring.settle()
                            return
                        }
                        ring.dragging = false
                        // Held still before letting go: no fling.
                        if (Date.now() - spin.lastT > 80) ring.velocity = 0
                        if (Math.abs(ring.velocity) > 0.05 && Config.motionEnabled) ring.coasting = true
                        else ring.settle()
                    }
                    onCanceled: {
                        ring.dragging = false
                        ring.settle()
                    }
                }

                WheelHandler {
                    onWheel: (event) => {
                        ring.grab()
                        ring.wheeling = true
                        const delta = event.angleDelta.x !== 0 ? event.angleDelta.x : event.angleDelta.y
                        // One hour per notch.
                        ring.ringAngle -= delta / 120 * ring.step
                        wheelRest.restart()
                    }
                }
                Timer {
                    id: wheelRest
                    // The pause after the last notch that counts as "done scrolling".
                    interval: Motion.trail
                    onTriggered: { ring.wheeling = false; ring.settle() }
                }
            }

            // ── The hour being described ──────────────────────────────
            ColumnLayout {
                id: heroDetail
                visible: Weather.hasLocation
                Layout.preferredWidth: Tokens.iconXl * 7
                Layout.fillWidth: false
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                // WHICH hour, in words — the day is never left to be inferred.
                StyledText {
                    Layout.fillWidth: true
                    visible: panel.detail !== null
                    text: panel.detail
                        ? panel.dayWord(panel.detail.date).toUpperCase() + "  ·  "
                          + (panel.describingNow ? "NOW" : Clock.pad(panel.detail.hour) + ":00")
                        : ""
                    variant: "micro"
                    font.bold: true
                    font.letterSpacing: Tokens.borderWidth
                    color: panel.onToday ? panel.accent : Colors.of(QsWindow.window).fgMuted
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    opacity: panel.onToday ? 1 : panel.otherDay + 0.3
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                    RowLayout {
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            visible: panel.detail !== null
                            name: panel.detail ? Weather.symbol(panel.detail.code, panel.detail.isDay) : ""
                            fill: 0
                            font.pixelSize: Tokens.fontNumeralMd
                            color: panel.detail ? Weather.tint(panel.detail.code, panel.detail.isDay) : Colors.of(QsWindow.window).fgDim
                            Behavior on color { ColorAnimation { duration: Motion.spatial } }
                        }
                        RollText {
                            text: panel.detail ? Weather.temp(panel.detail.tempC) + "°" : "—"
                            family:    Tokens.fontBlock
                            pixelSize: Tokens.fontNumeralMd
                            weight:    Font.Bold
                            color:     panel.detail ? Weather.tempTint(panel.detail.tempC) : Colors.of(QsWindow.window).fgDim
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: panel.detail     ? Weather.describe(panel.detail.code)
                                                + "  ·  feels " + Weather.temp(panel.detail.feelsC) + "°"
                            : Weather.loading ? "Loading…" : Weather.error
                        variant: "label"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // ── The day's high and low, and when ──────────────
                    // Each is a way to that hour: click and the ring turns to it.
                    Row {
                        visible: panel.maxSlot >= 0
                        spacing: Tokens.spacingLg

                        Repeater {
                            model: [
                                { slot: panel.maxSlot, arrow: "↑", tint: Colors.of(QsWindow.window).warning },
                                { slot: panel.minSlot, arrow: "↓", tint: Colors.of(QsWindow.window).info }
                            ]

                            delegate: Row {
                                id: extreme
                                required property var modelData
                                readonly property var h: panel.ringHours[extreme.modelData.slot]?.hour ?? null
                                visible: !!h
                                spacing: Tokens.spacingXs

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: extreme.h ? extreme.modelData.arrow + " " + Weather.temp(extreme.h.tempC) + "°" : ""
                                    variant: "label"
                                    font.family: Tokens.fontBlock
                                    font.weight: Font.Bold
                                    color: extreme.modelData.tint
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: extreme.h ? "at " + Clock.pad(extreme.h.hour) + ":00" : ""
                                    variant: "caption"
                                    color: extremeHover.hovered ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                                }

                                HoverHandler { id: extremeHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler   { onTapped: ring.snapToSlot(extreme.modelData.slot) }
                            }
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.topMargin: Tokens.spacingSm
                        visible: panel.detail !== null
                        columns: 2
                        rowSpacing: Tokens.spacingXs
                        columnSpacing: Tokens.spacingLg

                        // The arrow points where the wind is GOING: the reported
                        // direction is where it comes from, so it turns 180°.
                        ClockFact {
                            pops: true; popActive: panel.weatherOn; popIndex: 0; popDelay: panel.lead + Motion.respond
                            icon: "navigation"
                            iconRotation: panel.detail ? panel.detail.windDir + 180 : 0
                            tint: Colors.of(QsWindow.window).fgMuted
                            text: panel.detail ? Weather.wind(panel.detail.windKph) : ""
                            sub:  panel.detail ? W.compass(panel.detail.windDir) : ""
                        }
                        ClockFact {
                            pops: true; popActive: panel.weatherOn; popIndex: 1; popDelay: panel.lead + Motion.respond
                            icon: "humidity_percentage"
                            tint: Colors.of(QsWindow.window).info
                            text: panel.detail ? Math.round(panel.detail.humidity) + "%" : ""
                        }
                        ClockFact {
                            pops: true; popActive: panel.weatherOn; popIndex: 2; popDelay: panel.lead + Motion.respond
                            icon: "umbrella"
                            tint: panel.detail && panel.detail.precip >= 30 ? Colors.of(QsWindow.window).info : Colors.of(QsWindow.window).fgDim
                            text: panel.detail ? Math.round(panel.detail.precip) + "%" : ""
                            sub:  panel.detail && panel.detail.precipMm > 0 ? panel.detail.precipMm.toFixed(1) + " mm" : ""
                        }
                        ClockFact {
                            pops: true; popActive: panel.weatherOn; popIndex: 3; popDelay: panel.lead + Motion.respond
                            icon: "light_mode"
                            tint: panel.detail ? panel.uvTint(panel.detail.uv ?? 0) : Colors.of(QsWindow.window).fgDim
                            text: panel.detail ? "UV " + Math.round(panel.detail.uv ?? 0) : ""
                            sub:  panel.detail ? W.uvLevel(panel.detail.uv ?? 0) : ""
                        }
                    }
                }
            }
        }
    }

    // ══ The day's rain ═════════════════════════════════════════════
    // One bar a hour for the day on the ring: how likely rain is, tinted when it is wet
    // enough to matter, the hour the ring is on lit. Hover reads an hour; click turns the
    // ring to it. The words beside it are the planner's: "Dry until 17:00".
    Rectangle {
        id: rainCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Weather.hasLocation && panel.ringHours.length > 0
        readonly property int pad: Tokens.spacingSm
        implicitHeight: Tokens.iconLg + rainCard.pad * 2
        radius: Math.min(Tokens.radiusCard, implicitHeight / 2)
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: rainCard; active: panel.weatherOn; delay: panel.lead + Motion.respond; rise: Tokens.spacingMd }

        PopIn { id: rainPop; active: panel.weatherOn; delay: panel.lead + Motion.respond * 2 }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Tokens.spacingLg
            anchors.rightMargin: Tokens.spacingLg
            anchors.topMargin: rainCard.pad
            anchors.bottomMargin: rainCard.pad
            spacing: Tokens.spacingLg

            MaterialIcon {
                name: "umbrella"
                fill: 1
                font.pixelSize: Tokens.iconSm
                color: Colors.of(QsWindow.window).info
            }
            StyledText {
                // As wide as the longest thing it can say (three wet stretches, or an hour read
                // out with its amount) — sized for "Dry until…" alone, the rest was cut off.
                Layout.preferredWidth: Math.max(rainMetrics.advanceWidth, rainMetricsLong.advanceWidth, rainMetricsHour.advanceWidth)
                text: chart.hover >= 0 && panel.ringHours[chart.hover]
                    ? Clock.pad(panel.ringHours[chart.hover].hour.hour) + ":00  ·  "
                      + Math.round(panel.ringHours[chart.hover].hour.precip) + "%"
                      + (panel.ringHours[chart.hover].hour.precipMm > 0 ? "  ·  " + panel.ringHours[chart.hover].hour.precipMm.toFixed(1) + " mm" : "")
                    : panel.rainPlan
                variant: "caption"
                font.weight: Font.DemiBold
                elide: Text.ElideRight

                TextMetrics {
                    id: rainMetrics
                    font.pixelSize: Tokens.fontCaption
                    font.weight: Font.DemiBold
                    text: Translation.tr("Dry until tomorrow 03:00")
                }
                TextMetrics {
                    id: rainMetricsLong
                    font.pixelSize: Tokens.fontCaption
                    font.weight: Font.DemiBold
                    text: Translation.tr("Rain 08:00–10:00 · 15:00–16:00 …")
                }
                TextMetrics {
                    id: rainMetricsHour
                    font.pixelSize: Tokens.fontCaption
                    font.weight: Font.DemiBold
                    text: "23:00  ·  100%  ·  12.5 mm"
                }
            }

            Item {
                id: chart
                Layout.fillWidth: true
                Layout.fillHeight: true
                property int hover: -1
                readonly property real slotW: chart.width / Math.max(1, panel.ringHours.length)

                Repeater {
                    model: panel.ringHours

                    delegate: Item {
                        id: rb
                        required property int index
                        required property var modelData
                        readonly property var  h: modelData.hour
                        readonly property real p: Math.max(0, Math.min(1, (h.precip || 0) / 100))
                        readonly property bool wet: W.isWet(h)
                        readonly property bool past: panel.onToday && h.hour < Clock.hours
                        readonly property bool focused: rb.index === panel.slot

                        x: rb.index * chart.slotW
                        width: chart.slotW
                        height: chart.height

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            width: Math.max(2, rb.width - Tokens.spacingXs)
                            height: Math.max(2, rb.p * chart.height * Math.min(1.04, rainPop.arrive))
                            radius: Math.min(width / 2, Tokens.spacingXs + 1)
                            color: rb.focused ? panel.accent
                                 : rb.wet     ? Colors.of(QsWindow.window).info
                                 :              Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.22)
                            opacity: rb.past ? 0.45 : 1
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }

                        HoverHandler {
                            cursorShape: Qt.PointingHandCursor
                            onHoveredChanged: {
                                if (hovered) chart.hover = rb.index
                                else if (chart.hover === rb.index) chart.hover = -1
                            }
                        }
                        TapHandler { onTapped: ring.snapToSlot(rb.index) }
                    }
                }
            }
        }
    }

    // ══ The week ══════════════════════════════════════════════════
    // A wash slides between the days on a spring (SegmentSwitch's indicator, for
    // days), and each day carries its range on ONE scale for the whole week, with
    // the temperature right now marked on today's.
    Rectangle {
        id: weekCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Weather.hasLocation && Weather.days.length > 0
        readonly property int pad: Tokens.spacingSm
        implicitHeight: weekRow.implicitHeight + weekCard.pad * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: weekCard; active: panel.weatherOn; delay: panel.lead + Motion.respond * 2; rise: Tokens.spacingMd }

        // One tile's width: the tiles share the row equally.
        readonly property real tileW: weekRow.width / Math.max(1, Weather.days.length)

        Rectangle {
            id: dayWash
            y: weekCard.pad
            height: weekRow.height
            radius: Tokens.radiusSm
            color: Colors.of(QsWindow.window).alpha(panel.accent, 0.16)

            x:     weekCard.pad + panel.dayIndex * weekCard.tileW
            width: weekCard.tileW
            // Set once there is real geometry, so the wash doesn't glide in from the edge.
            property bool settled: false
            Component.onCompleted: Qt.callLater(function () { dayWash.settled = true })
            Behavior on x {
                enabled: dayWash.settled
                SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.1 }
            }
            Behavior on width {
                enabled: dayWash.settled
                SpringAnimation { spring: 4.0; damping: 0.40; epsilon: 0.1 }
            }
            Behavior on color { ColorAnimation { duration: Motion.standard } }
        }

        RowLayout {
            id: weekRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: weekCard.pad
            spacing: 0

            Repeater {
                model: Weather.days

                delegate: Item {
                    id: dayCol
                    required property int index
                    required property var modelData
                    readonly property bool chosen: panel.dayIndex === index
                    readonly property bool isToday: index === 0

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: dayStack.implicitHeight + Tokens.spacingMd

                    PopIn { id: dayPop; active: panel.weatherOn; index: dayCol.index; delay: panel.lead + Motion.respond * 3 }

                    // A day that is neither the one on the ring nor today steps back.
                    property real base: dayCol.chosen || dayCol.isToday || dayHover.hovered ? 1 : panel.otherDay + 0.15
                    Behavior on base { NumberAnimation { duration: Motion.standard } }
                    opacity: dayCol.base * dayPop.opacity

                    // Leans toward the pointer, like the chips do.
                    property real lean: dayHover.hovered && !dayCol.chosen ? 1.05 : 1
                    Behavior on lean { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }
                    scale: dayCol.lean * dayPop.scale

                    Column {
                        id: dayStack
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingXs

                        StyledText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: panel.dayShort(dayCol.modelData.date)
                            variant: "caption"
                            font.weight: dayCol.chosen || dayCol.isToday ? Font.DemiBold : Font.Normal
                            color: dayCol.chosen ? panel.accent : Colors.of(QsWindow.window).fg
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: Weather.symbol(dayCol.modelData.code, true)
                                fill: 0
                                font.pixelSize: Tokens.iconLg
                                color: Weather.tint(dayCol.modelData.code, true)
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: dayCol.modelData.precipChance >= 20
                                text: Math.round(dayCol.modelData.precipChance) + "%"
                                variant: "micro"
                                font.bold: true
                                color: Colors.of(QsWindow.window).info
                            }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: Tokens.spacingSm
                            StyledText {
                                id: dayMax
                                text: Weather.temp(dayCol.modelData.maxC) + "°"
                                variant: "label"
                                font.family: Tokens.fontBlock
                                font.weight: Font.Bold
                                color: Weather.tempTint(dayCol.modelData.maxC)
                            }
                            StyledText {
                                anchors.baseline: dayMax.baseline
                                text: Weather.temp(dayCol.modelData.minC) + "°"
                                variant: "caption"
                                font.family: Tokens.fontBlock
                                emphasis: "dim"
                            }
                        }

                        // ── The day's range, on the week's scale ──────
                        // It grows in on the tile's own spring (`arrive` overshoots
                        // a little, so the bar settles rather than stops).
                        Item {
                            id: range
                            anchors.horizontalCenter: parent.horizontalCenter
                            width:  Math.round(dayCol.width * 0.62)
                            height: Tokens.spacingSm
                            clip: true

                            readonly property real span: panel.weekRange.hi - panel.weekRange.lo
                            readonly property real lo: (dayCol.modelData.minC - panel.weekRange.lo) / range.span
                            readonly property real hi: (dayCol.modelData.maxC - panel.weekRange.lo) / range.span
                            readonly property real grow: Math.min(1.04, dayPop.arrive)

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                            }
                            Rectangle {
                                x: range.lo * range.width
                                width: Math.max(range.height, (range.hi - range.lo) * range.width) * range.grow
                                height: parent.height
                                radius: height / 2
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0; color: Weather.tempTint(dayCol.modelData.minC) }
                                    GradientStop { position: 1; color: Weather.tempTint(dayCol.modelData.maxC) }
                                }
                            }
                            // Right now, on today's bar: a bead, ringed in the card's colour so it
                            // reads over the gradient.
                            Rectangle {
                                visible: dayCol.isToday && Weather.ready
                                readonly property real at: Math.max(range.lo, Math.min(range.hi,
                                    (Weather.tempC - panel.weekRange.lo) / range.span))
                                width: range.height
                                height: width
                                radius: width / 2
                                x: Math.max(0, Math.min(range.width - width, at * range.width - width / 2))
                                color: Colors.of(QsWindow.window).fg
                                border.width: Tokens.borderWidth
                                border.color: Colors.of(QsWindow.window).surfaceContainer
                                opacity: range.grow >= 1 ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                            }
                        }
                    }

                    HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { onTapped: panel.setDay(dayCol.index) }
                }
            }
        }
    }

    // ══ Outdoors ══════════════════════════════════════════════════
    // Rain, air and pollen are current-only; the sun follows the day on the ring.
    // A Flow, so a narrow panel wraps a pill rather than clipping one.
    Flow {
        id: footer
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Weather.hasLocation
        spacing: Tokens.spacingSm

        // The next three hours, a bar a quarter hour. A dry spell shows no bars: stubs
        // would say it was raining a little.
        ClockPill {
            id: rainPill
            visible: Weather.nowcast !== null
            popActive: panel.weatherOn; popIndex: 0; popDelay: panel.lead + Motion.respond * 4
            dim: panel.onToday ? 1 : panel.otherDay + 0.2

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: !Weather.nowcast || Weather.nowcast.state === "dry" ? "umbrella"
                    : Weather.nowcast.kind === "snow" ? "cloudy_snowing" : "rainy"
                fill: 0
                font.pixelSize: Tokens.iconSm
                color: Weather.nowcast && Weather.nowcast.state !== "dry"
                       ? Colors.of(QsWindow.window).info : Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Weather.nowcast ? Weather.nowcast.short : ""
                variant: "caption"
                font.weight: Font.DemiBold
            }
            Row {
                id: bars
                anchors.verticalCenter: parent.verticalCenter
                visible: Weather.nowcast !== null && Weather.nowcast.state !== "dry"
                spacing: Tokens.borderWidth * 2
                readonly property real full: Tokens.iconMd

                Repeater {
                    model: panel.nowcastBars

                    delegate: Item {
                        id: bar
                        required property int index
                        required property var modelData
                        width: Tokens.spacingXs + 1
                        height: bars.full
                        PopIn { id: barPop; active: panel.weatherOn && rainPill.visible; index: bar.index; cap: 12; delay: panel.lead + Motion.respond * 4 }

                        Rectangle {
                            anchors.bottom: parent.bottom
                            width: parent.width
                            // A dry slot is a dot on the baseline, a wet one rises with the rain.
                            height: Math.max(width, Math.min(bars.full, bars.full * bar.modelData.v * barPop.arrive))
                            radius: width / 2
                            color: bar.modelData.v > 0
                                   ? (bar.modelData.snow ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).info)
                                   : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                        }
                    }
                }
            }
        }

        // Air: a dot in the band's colour, then the pollen.
        ClockPill {
            visible: (AirQuality.ready && AirQuality.aqi >= 0) || AirQuality.pollenCovered
            popActive: panel.weatherOn; popIndex: 1; popDelay: panel.lead + Motion.respond * 4

            Rectangle {
                visible: AirQuality.ready && AirQuality.aqi >= 0
                anchors.verticalCenter: parent.verticalCenter
                width:  Tokens.spacingSm + Tokens.spacingXs
                height: width
                radius: width / 2
                color:  panel.aqiTint(AirQuality.aqi)
            }
            StyledText {
                visible: AirQuality.ready && AirQuality.aqi >= 0
                anchors.verticalCenter: parent.verticalCenter
                text: "Air " + Math.round(AirQuality.aqi)
                variant: "caption"
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: AirQuality.ready && AirQuality.aqi >= 0
                anchors.verticalCenter: parent.verticalCenter
                text: AirQuality.level
                variant: "caption"
                emphasis: "dim"
            }
            MaterialIcon {
                visible: AirQuality.pollenCovered
                anchors.verticalCenter: parent.verticalCenter
                name: "local_florist"
                fill: 1
                font.pixelSize: Tokens.iconSm
                color: AirQuality.pollen.length ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                visible: AirQuality.pollenCovered
                anchors.verticalCenter: parent.verticalCenter
                text: AirQuality.pollen.length ? AirQuality.pollen[0].name + " pollen" : "No pollen"
                variant: "caption"
                emphasis: "dim"
            }
        }

        // Daylight: sunrise ━━●── sunset, the sun where it is now.
        ClockPill {
            visible: panel.sun !== null
            popActive: panel.weatherOn; popIndex: 2; popDelay: panel.lead + Motion.respond * 4

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "wb_twilight"
                fill: 1
                font.pixelSize: Tokens.iconSm
                color: Colors.of(QsWindow.window).warning
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.sun ? panel.sun.rise : ""
                variant: "caption"
                font.family: Tokens.fontBlock
                emphasis: "dim"
            }
            Item {
                id: sunRail
                anchors.verticalCenter: parent.verticalCenter
                width:  Tokens.iconXl * 3
                height: Tokens.spacingSm + Tokens.spacingXs

                // The sun travels to where it is each time the page is shown.
                property real drawn: panel.weatherOn && panel.sun ? Math.max(0, panel.sun.frac) : 0
                Behavior on drawn {
                    NumberAnimation {
                        duration: Motion.spatialSlow
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: Tokens.borderWidth * 2
                    radius: height / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.12)
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.sun !== null && panel.sun.frac >= 0
                    width: parent.width * sunRail.drawn
                    height: Tokens.borderWidth * 2
                    radius: height / 2
                    color: Colors.of(QsWindow.window).warning
                }
                Rectangle {
                    visible: panel.sun !== null && panel.sun.frac >= 0
                    anchors.verticalCenter: parent.verticalCenter
                    width:  parent.height
                    height: width
                    radius: width / 2
                    color:  Colors.of(QsWindow.window).warning
                    x: parent.width * sunRail.drawn - width / 2
                }
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: panel.sun ? panel.sun.set : ""
                variant: "caption"
                font.family: Tokens.fontBlock
                emphasis: "dim"
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: !panel.sun ? ""
                    : panel.sun.left !== "" ? panel.sun.left + " left"
                    : panel.sun.length
                variant: "caption"
                emphasis: "dim"
            }
        }

        // The hour before sunset, when the light goes low and warm.
        ClockPill {
            visible: panel.golden !== null && !panel.golden.over
            popActive: panel.weatherOn; popIndex: 3; popDelay: panel.lead + Motion.respond * 4
            dim: panel.golden && panel.golden.live ? 1 : 0.9

            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "sunny"
                fill: 1
                font.pixelSize: Tokens.iconSm
                color: Colors.of(QsWindow.window).warning
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: !panel.golden ? ""
                    : panel.golden.live ? "Golden hour now"
                    : "Golden hour"
                variant: "caption"
                font.weight: Font.DemiBold
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: !panel.golden ? ""
                    : panel.golden.live ? "until " + panel.golden.end
                    : panel.golden.start + "–" + panel.golden.end
                variant: "caption"
                font.family: Tokens.fontBlock
                emphasis: "dim"
            }
        }
    }
}
