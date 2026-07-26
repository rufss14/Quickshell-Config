pragma ComponentBehavior: Bound
import QtQuick
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
    property color accent: Colors.primary

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

    readonly property bool showForecast: root.size === "large"
    readonly property bool showDetail:   root.size !== "small"

    // ── Nothing set up yet ────────────────────────────────────────────────────
    // The one state that is the user's to fix, so it says what to do rather than
    // showing a spinner that will never resolve.
    ColumnLayout {
        anchors.fill: parent
        visible: !Weather.hasLocation
        spacing: Tokens.spacingSm

        Item { Layout.fillHeight: true }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "󰖐"
            font.pixelSize: 28
            color: Colors.fgDim
        }
        StyledText {
            Layout.fillWidth: true
            // Short enough to fit the SMALL tile without wrapping into a wall. The
            // first version spelled out the full settings path and rendered as five
            // cramped lines on a 168px square.
            text: root.size === "small" ? "No location set"
                                        : "Set a location in Settings → Widgets"
            variant: "caption"
            emphasis: "dim"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Item { Layout.fillHeight: true }
    }

    // ── Couldn't fetch ────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: Weather.hasLocation && Weather.error !== "" && !Weather.ready
        spacing: Tokens.spacingSm

        Item { Layout.fillHeight: true }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: "󰖐"
            font.pixelSize: 28
            color: Colors.fgDim
        }
        StyledText {
            Layout.fillWidth: true
            text: Weather.error
            variant: "caption"
            emphasis: "dim"
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
        Item { Layout.fillHeight: true }
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

    // ── The reading ───────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        visible: Weather.ready
        spacing: 0

        // ── Small: stacked ────────────────────────────────────────────────────
        // Side by side, a 168px tile gives the condition ~70px and it elides to
        // "Partly clo…". Stacked, the same words get the full width.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.size === "small"
            spacing: 0

            Item { Layout.fillHeight: true }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Weather.glyph(Weather.code, Weather.isDay)
                font.pixelSize: 34
                color: root.accent
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 1
                StyledText {
                    text: Weather.temp(Weather.tempC)
                    font.pixelSize: 34
                    font.weight: Font.Bold
                    color: Colors.fg
                }
                StyledText {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: 4
                    text: Weather.unit
                    variant: "caption"
                    emphasis: "muted"
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: Weather.describe(Weather.code)
                variant: "caption"
                emphasis: "muted"
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Item { Layout.fillHeight: true }
        }

        // ── Medium / large: side by side ──────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: root.size !== "small"
            spacing: Tokens.spacingMd

            StyledText {
                text: Weather.glyph(Weather.code, Weather.isDay)
                font.pixelSize: 42
                color: root.accent
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2

                RowLayout {
                    spacing: 1
                    StyledText {
                        text: Weather.temp(Weather.tempC)
                        font.pixelSize: 38
                        font.weight: Font.Bold
                        color: Colors.fg
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignTop
                        Layout.topMargin: 4
                        text: Weather.unit
                        variant: "caption"
                        emphasis: "muted"
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Weather.describe(Weather.code)
                    variant: "caption"
                    emphasis: "muted"
                    elide: Text.ElideRight
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXs
            visible: root.showDetail
            text: Weather.place
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.showDetail
            text: "Feels " + Weather.temp(Weather.feelsC) + "°  ·  "
                  + Weather.humidity + "%  ·  " + Weather.wind(Weather.windKph)
            variant: "caption"
            emphasis: "dim"
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true; visible: !root.showForecast }

        // ── Forecast, large only ──────────────────────────────────────────────
        // Skips index 0: that is today, and today's high/low sits directly beneath the
        // current temperature it would be repeating.
        Divider { Layout.fillWidth: true; Layout.topMargin: Tokens.spacingMd; visible: root.showForecast }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacingSm
            visible: root.showForecast
            spacing: Tokens.spacingXs

            Repeater {
                model: root.showForecast ? Math.max(0, Weather.days.length - 1) : 0

                RowLayout {
                    required property int index
                    readonly property var day: Weather.days[index + 1]
                    Layout.fillWidth: true
                    // Rows share the leftover height instead of stacking at the top
                    // over a block of nothing — measured at 352x352, a 3-row forecast
                    // left roughly 40% of the tile empty.
                    Layout.fillHeight: true
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.preferredWidth: 34
                        text: Qt.formatDateTime(new Date(parent.day.date), "ddd")
                        variant: "caption"
                        emphasis: "muted"
                    }
                    StyledText {
                        text: Weather.glyph(parent.day.code, true)
                        variant: "body"
                        color: Colors.fgMuted
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: Weather.temp(parent.day.maxC) + "°"
                        variant: "caption"
                        color: Colors.fg
                    }
                    StyledText {
                        text: Weather.temp(parent.day.minC) + "°"
                        variant: "caption"
                        emphasis: "dim"
                    }
                }
            }
        }
    }
}
