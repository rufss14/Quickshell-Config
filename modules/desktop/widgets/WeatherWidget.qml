pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── WeatherWidget ─────────────────────────────────────────────────────────────
// Current conditions, and a short forecast at the larger sizes.
//
// It holds the Weather service's refcount for exactly as long as it exists, which is
// what makes "no weather widget ⇒ no network requests" true rather than aspirational.
// Acquire/release on Component lifetime, the same contract NetStats and Cava use.
//
// ── Layout, Material 3 Expressive (2026-10-30) ────────────────────────────────
// The temperature is the hero: block digits INSIDE a tonal shape whose form is the
// weather (a sun, a puffier cookie the cloudier it is, a clover for rain, a flake, a
// burst, a squircle for fog — morphing when it turns), the condition's glyph as a badge on
// its edge. Beside it: the condition, today's high and low, how it feels (and at medium/
// large the place and humidity/wind). Under it, at every size, the next hours as tonal
// cells — "now" on the condition's container — paged by a tap. Large adds the week as rows
// with a range bar each, placed on the week's own span. The 24h graph (HourlyChart) is no
// longer used: the user turned it down on the small tile, and every size now shares the strip.
Item {
    id: root

    required property var opts
    required property string size
    // Declared but unused here: the host passes the same property set to every widget
    // type, and an initial property with no matching declaration is an error.
    property int widgetId: -1
    property bool active: true
    // Set by the host from the widget's stored accent role. Defaults to the palette's
    // primary so a widget rendered outside the layer (a settings preview) still looks
    // right without the caller having to know about accents.
    property color accent: Colors.of(QsWindow.window).primary

    // Only a LIVE widget holds the refcount. A settings preview is `active: false` and
    // must not cause a fetch — opening a settings page should never put traffic on the
    // wire. It still renders whatever the service already holds.
    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Weather.acquire(); root._held = true }
        else if (!root.active && root._held) { Weather.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) Weather.release()

    // The whole tile's hover, for the refresh chip. A HoverHandler takes no press.
    HoverHandler { id: tileHover }

    // The condition's own colour (amber sun, blue rain, red storm — palette roles, via the
    // service), unless the tile was given an accent of its own in Settings.
    readonly property color tone:
        (root.opts.accent ?? "") !== "" ? root.accent : Weather.tint(Weather.code, Weather.isDay)

    // ── Small: the next few hours ─────────────────────────────────────────────
    // Five hours at a time, each as its condition, its hour and its temperature — what a
    // glance at the weather is for ("do I need a coat later"), which a bare curve does not
    // say. A tap moves on five hours; four pages, then back to now. A glance, not a
    // setting: not persisted.
    property int hourPage: 0
    // The page DRAWN, trailing `hourPage` by half a fade (SwapFade, as the calendar's week).
    property int viewPage: 0
    property int hourHover: -1
    // Every size has the hour strip now (2026-10-30), so every size pages it.
    function tileTap() { root.hourPage = (root.hourPage + 1) % 4 }

    readonly property var hourCells: {
        const from = Weather.hoursStart + root.viewPage * 5
        return Weather.hours.slice(from, from + 5)
    }

    readonly property bool showForecast: root.size === "large"
    readonly property bool showDetail:   root.size !== "small"

    // ── Nothing set up yet ────────────────────────────────────────────────────
    // The one state that is the user's to fix, so it says what to do rather than
    // showing a spinner that will never resolve. Short enough to fit the SMALL tile
    // without wrapping into a wall.
    WidgetEmpty {
        visible: !Weather.hasLocation
        glyph: "󰖐"
        text: root.size === "small" ? "No location set"
                                    : "Set a location in Settings → Widgets"
    }

    // ── Couldn't fetch ────────────────────────────────────────────────────────
    WidgetEmpty {
        visible: Weather.hasLocation && Weather.error !== "" && !Weather.ready
        glyph: "󰖐"
        text: Weather.error
    }

    // ── Loading, first time only ──────────────────────────────────────────────
    // A refresh over existing data leaves the numbers up: replacing a perfectly good
    // reading with a spinner every twenty minutes would be worse than a stale minute.
    StyledText {
        anchors.centerIn: parent
        visible: Weather.hasLocation && !Weather.ready && Weather.error === ""
        text: "…"
        variant: "headline"
        emphasis: "dim"
    }

    // °C / °F. A tap flips the same preference Settings → Widgets sets, so the bar's
    // weather and every other tile follow it.
    component UnitLabel: StyledText {
        id: unitLabel
        text: Weather.unit
        variant: "caption"
        color: unitMouse.containsMouse ? root.accent : Colors.of(QsWindow.window).fgMuted
        Behavior on color { ColorAnimation { duration: Motion.respond } }
        MouseArea {
            id: unitMouse
            anchors.fill: parent
            anchors.margins: -Tokens.spacingSm
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Config.weatherMetric = !Config.weatherMetric
        }
    }

    // The shape of the weather, by the glyph Weather already chose (so the WMO table stays
    // in the service). Square bar shape: a squircle, the nearest it has.
    function shapeFor(icon) {
        const i = icon || ""
        return Config.barShape ? "squircle"
             : i === "clear_day"     ? "sunny"
             : i === "clear_night"   ? "circle"
             : i.indexOf("partly") === 0 ? "cookie7"
             : i === "cloud"         ? "cookie9"
             : i === "foggy"         ? "squircle"
             : i === "rainy"         ? "clover"
             : i === "thunderstorm"  ? "burst"
             : i.indexOf("snow") >= 0 ? "cookie12"
             : "cookie9"
    }
    // The condition's colour as a container: a solid mix toward it, so the hero has a body.
    readonly property color container: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.tone, 0.24)

    // Today's high and low as one line: "↑20° ↓10°" ("" before the forecast arrives).
    readonly property string hiLo: Weather.days.length > 0
        ? "↑" + Weather.temp(Weather.days[0].maxC) + "°  ↓" + Weather.temp(Weather.days[0].minC) + "°" : ""

    // The week's span, for placing each day's range bar on one scale.
    readonly property var week: Weather.days.slice(1)
    readonly property real weekMin: root.week.length > 0 ? Math.min(...root.week.map(d => d.minC)) : 0
    readonly property real weekMax: root.week.length > 0 ? Math.max(...root.week.map(d => d.maxC)) : 1

    // ── The hero: the temperature in the weather's shape ──────────────────────
    component Hero: Item {
        id: hero
        readonly property real side: Math.min(width, height)
        readonly property string icon: Weather.symbol(Weather.code, Weather.isDay)

        MorphShape {
            anchors.centerIn: parent
            width: hero.side
            height: hero.side
            spec: Motion.springSpatialFast
            shape: root.shapeFor(hero.icon)
            fillColor: root.container

            // Rolls when the reading changes, a digit at a time.
            RollText {
                anchors.centerIn: parent
                text: Weather.temp(Weather.tempC) + "°"
                family: Tokens.fontBlock
                weight: Font.ExtraBold
                // Three characters fit the shape's waist; a fourth ("-12°", "104°") steps down.
                pixelSize: Math.round(hero.side * (text.length > 3 ? 0.24 : 0.32))
                color: Colors.of(QsWindow.window).fg
            }
        }

        // The condition's glyph, a badge on the shape's edge. The condition changing (clear →
        // rain, dusk → night) is a swap, not a cut: bound to a held copy (SwapFade).
        Item {
            id: badge
            property string shown: ""
            Component.onCompleted: badge.shown = hero.icon
            width: Math.round(hero.side * 0.4)
            height: width
            x: (hero.width + hero.side) / 2 - width * 0.85
            y: (hero.height + hero.side) / 2 - height * 0.85

            MorphShape {
                anchors.fill: parent
                shape: "circle"
                fillColor: Colors.of(QsWindow.window).surfaceContainer
                strokeColor: root.container
                strokeWidth: 2
            }
            MaterialIcon {
                id: badgeIcon
                anchors.centerIn: parent
                name: badge.shown
                fill: 1
                font.pixelSize: Math.round(badge.width * 0.58)
                color: root.tone
                SwapFade {
                    target: badgeIcon
                    key: hero.icon
                    shownKey: badge.shown
                    travel: 0
                    dip: 0.6
                    onSwapped: badge.shown = hero.icon
                }
            }
        }
    }

    // ── The reading ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: Weather.ready
        spacing: Tokens.spacingSm

        // ── Top: the hero and the facts ───────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: root.size !== "large"
            Layout.preferredHeight: root.size === "large" ? Tokens.iconXl * 4 : -1
            spacing: Tokens.spacingMd

            // On small, a fixed hero: filling the row's height left the facts ~50px wide and
            // the high/low ran off the tile's edge (2026-10-30). Medium/large have the width.
            Hero {
                Layout.fillHeight: root.size !== "small"
                Layout.preferredWidth: root.size === "small" ? Tokens.iconXl * 2 + Tokens.spacingSm : height
                Layout.preferredHeight: root.size === "small" ? Layout.preferredWidth : -1
                Layout.alignment: Qt.AlignVCenter
            }

            // Two readouts in one slot, trading places with the pointer: today's facts,
            // or the hour under it.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: root.hourHover < 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.showDetail && Weather.place !== ""
                        text: Weather.place
                        variant: "title"
                        font.weight: Font.Bold
                        color: Colors.of(QsWindow.window).fg
                        elide: Text.ElideRight
                    }
                    // Every line here elides: the column is narrow on small (~60px), and a
                    // line that can't shrink runs off the tile.
                    StyledText {
                        Layout.fillWidth: true
                        text: Weather.describe(Weather.code)
                              + (root.showDetail && root.hiLo !== "" ? "  ·  " + root.hiLo : "")
                        variant: root.showDetail ? "caption" : "label"
                        font.weight: root.showDetail ? Font.Normal : Font.DemiBold
                        color: root.showDetail ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fg
                        elide: Text.ElideRight
                    }
                    // Small: the high/low on its own line, as text (arrows included), so it
                    // can elide instead of overflowing like the icon row did.
                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.showDetail && root.hiLo !== ""
                        text: root.hiLo
                        variant: "caption"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: !root.showDetail
                        text: "Feels " + Weather.temp(Weather.feelsC) + "°"
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                    // Medium/large: one row of pills, never a second — a wrapped row ran out of
                    // the tile's bottom. The unit toggle (°C/°F) ends it.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.topMargin: Tokens.spacingXs
                        visible: root.showDetail
                        spacing: Tokens.spacingXs
                        clip: true
                        TilePill { icon: "thermostat"; text: "Feels " + Weather.temp(Weather.feelsC) + "°" }
                        TilePill { icon: "navigation"; iconRotation: Weather.windDir + 180; text: Weather.wind(Weather.windKph) }
                        TilePill {
                            visible: root.size === "large"
                            icon: "humidity_percentage"
                            text: Weather.humidity + "%"
                        }
                        Item { Layout.fillWidth: true }
                        UnitLabel {}
                    }
                }

                // The hour under the pointer: when, what, how likely rain is.
                ColumnLayout {
                    readonly property var cell: root.hourHover >= 0 ? (root.hourCells[root.hourHover] ?? null) : null
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: root.hourHover < 0 ? 0 : 1
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText {
                        Layout.fillWidth: true
                        text: parent.cell ? parent.cell.hour + ":00" : ""
                        variant: "label"
                        font.weight: Font.Bold
                        color: root.tone
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: parent.cell ? Weather.describe(parent.cell.code) : ""
                        variant: "caption"
                        emphasis: "muted"
                        elide: Text.ElideRight
                    }
                    RowLayout {
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        visible: parent.cell !== null && parent.cell.precip > 0
                        MaterialIcon { name: "umbrella"; variant: "caption"; emphasis: "dim" }
                        StyledText {
                            Layout.fillWidth: true
                            text: parent.parent.cell ? parent.parent.cell.precip + "%" : ""
                            variant: "caption"
                            emphasis: "dim"
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            TileChip {
                Layout.alignment: Qt.AlignTop
                visible: root.showDetail
                awake: tileHover.hovered
                accent: root.accent
                icon: "sync"
                onActivated: Weather.refresh()
            }
        }

        // ── The next hours ────────────────────────────────────────────────────
        // Five at a time, each a tonal cell — its hour, its condition, its temperature —
        // "now" on the condition's container. A tap moves on five hours (four pages). Hover
        // only on the strip, so a tap anywhere still reaches the tile.
        Item {
            id: hourStrip
            Layout.fillWidth: true
            Layout.fillHeight: false
            implicitHeight: Tokens.iconXl + Tokens.spacingXl + Tokens.spacingMd
            visible: root.hourCells.length > 0
            readonly property real cellW: width / 5

            SwapFade {
                target: hourRow
                key: String(root.hourPage)
                shownKey: String(root.viewPage)
                onSwapped: root.viewPage = root.hourPage
            }

            Row {
                id: hourRow
                anchors.fill: parent

                Repeater {
                    model: root.hourCells

                    Item {
                        id: hourCell
                        required property var modelData
                        required property int index
                        readonly property bool isNow: root.viewPage === 0 && hourCell.index === 0
                        readonly property bool pointed: root.hourHover === hourCell.index
                        width: hourStrip.cellW
                        height: hourStrip.height

                        SpringValue {
                            id: lift
                            spec: Motion.springSpatialFast
                            epsilon: 0.0005
                            target: hourCell.pointed ? 1.06 : 1
                        }

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingXs / 2 + 1
                            radius: Tokens.corner(Config.barShape, Tokens.radiusSm)
                            scale: lift.value
                            color: hourCell.isNow ? root.container
                                 : hourCell.pointed ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, Colors.of(QsWindow.window).fg, Tokens.stateHover)
                                 : Colors.of(QsWindow.window).surfaceHigh
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1

                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: hourCell.isNow ? "Now" : hourCell.modelData.hour
                                    font.pixelSize: Tokens.fontCaption - 2
                                    font.bold: hourCell.isNow
                                    color: hourCell.isNow ? root.tone : Colors.of(QsWindow.window).fgDim
                                }
                                MaterialIcon {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    name: Weather.symbol(hourCell.modelData.code, hourCell.modelData.isDay)
                                    fill: 1
                                    font.pixelSize: Tokens.iconLg - 2
                                    color: Weather.tint(hourCell.modelData.code, hourCell.modelData.isDay)
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Weather.temp(hourCell.modelData.tempC) + "°"
                                    variant: "caption"
                                    font.bold: true
                                    color: Colors.of(QsWindow.window).fg
                                }
                            }
                        }
                    }
                }
            }

            HoverHandler {
                onHoveredChanged: if (!hovered) root.hourHover = -1
                onPointChanged: if (hovered)
                    root.hourHover = Math.max(0, Math.min(root.hourCells.length - 1,
                                                Math.floor(point.position.x / hourStrip.cellW)))
            }
        }

        // ── Large: the week ───────────────────────────────────────────────────
        // A row per day: its name, its condition, the chance of rain when it matters, and
        // its low → high as a bar placed on the WEEK's span, so a warm day sits visibly to
        // the right of a cold one rather than every bar filling its own row.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showForecast
            spacing: Tokens.spacingXs

            Repeater {
                model: root.showForecast ? root.week : []

                TileRow {
                    id: dayRow
                    required property var modelData
                    readonly property real span: Math.max(1, root.weekMax - root.weekMin)
                    Layout.fillHeight: true
                    interactive: false

                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                        text: Qt.formatDateTime(new Date(dayRow.modelData.date), "ddd")
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fgMuted
                    }
                    MaterialIcon {
                        name: Weather.symbol(dayRow.modelData.code, true)
                        fill: 1
                        variant: "body"
                        color: Weather.tint(dayRow.modelData.code, true)
                    }
                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                        horizontalAlignment: Text.AlignRight
                        text: (dayRow.modelData.precipChance ?? 0) >= 20 ? dayRow.modelData.precipChance + "%" : ""
                        variant: "caption"
                        emphasis: "dim"
                    }
                    StyledText {
                        text: Weather.temp(dayRow.modelData.minC) + "°"
                        variant: "caption"
                        emphasis: "dim"
                    }
                    Item {
                        Layout.fillWidth: true
                        implicitHeight: Tokens.spacingSm
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.1)
                        }
                        Rectangle {
                            x: parent.width * (dayRow.modelData.minC - root.weekMin) / dayRow.span
                            width: Math.max(parent.height, parent.width * (dayRow.modelData.maxC - dayRow.modelData.minC) / dayRow.span)
                            height: parent.height
                            radius: height / 2
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0; color: Weather.tempTint(dayRow.modelData.minC) }
                                GradientStop { position: 1; color: Weather.tempTint(dayRow.modelData.maxC) }
                            }
                        }
                    }
                    StyledText {
                        text: Weather.temp(dayRow.modelData.maxC) + "°"
                        variant: "caption"
                        font.bold: true
                        color: Colors.of(QsWindow.window).fg
                    }
                }
            }
        }
    }
}
