import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── ClockPill ─────────────────────────────────────────────────────────────────
// Digital time (with seconds) over the date, and — once a location is set in
// Config.weatherPlace/Lat/Lon — the current temperature beside it. Click opens
// the clock panel.
//
// Was an analog face + "ddd, MMM dd" + "HH:mm" in a row. Replaced on request
// with a bigger digital readout; the analog Canvas is gone with it rather than
// kept behind a toggle nobody asked for.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property color accent: Colors.of(QsWindow.window).primary

    property bool active: false
    // The bar's hero (Config.moduleHero; BarGroupRow sets it): its chip is primaryContainer,
    // so the text goes to the colour made for that ground.
    property bool hero: false
    readonly property color _onHero: Colors.of(QsWindow.window).fgOnPrimaryContainer
    signal toggled()

    implicitWidth:  pill.width
    implicitHeight: Config.barPillHeight

    readonly property date now: Clock.now

    // Seconds tick, for the same reason the old analog face needed it: the
    // shell's shared clock only ticks once a minute unless something holds it
    // open for a face that shows seconds. Weather is refcounted the same way
    // (services/Weather.qml) — a no-op if Config.weatherPlace is unset.
    Component.onCompleted:   { Clock.acquireSeconds(); Weather.acquire() }
    Component.onDestruction: { Clock.releaseSeconds(); Weather.release() }

    IconButton {
        id: pill
        container: false
        height: Config.barPillHeight
        width:  Math.ceil(content.implicitWidth) + Tokens.pillPadding * 2

        squareMode: Config.barShape
        active:     root.active
        // Time over date fills the pill: an underline inside it struck through the date.
        markGap:    -(Tokens.borderChrome + Tokens.spacingXs)
        onClicked:  root.toggled()

        Row {
            id: content
            anchors.centerIn: parent
            spacing: Tokens.spacingMd

            Column {
                id: dateTimeColumn
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                BarLabel {
                    text: Qt.formatDateTime(root.now, "HH:mm:ss")
                    // "display" (Tokens.fontDisplay) was sized for a face on its
                    // own, not a line sharing the pill's fixed height with a date
                    // underneath it — that's what grew the whole pill. "label" is
                    // the biggest variant two stacked lines actually fit inside
                    // Config.barPillHeight at. BarLabel's tabular digits keep the
                    // seconds from shifting the chip's width every tick.
                    color: root.hero ? root._onHero : root.accent
                }
                StyledText {
                    text: Qt.formatDateTime(root.now, "dddd, MMMM d")
                    variant: "micro"
                    sizeScale: Config.barFontScale
                    color: root.hero ? Colors.of(QsWindow.window).alpha(root._onHero, 0.78)
                                     : Colors.of(QsWindow.window).fgDim
                }
            }

            // Hidden until a location is set — Weather.hasLocation is false by
            // default and there's no settings page wired up for it yet, so this
            // stays invisible on an untouched config rather than showing "—".
            //
            // A plain Item, sized to the full two-line block, with the actual row
            // CENTRED inside it — rather than anchoring the row itself straight to
            // `content`'s vertical centre. Both should land the same place, but the
            // row is shorter than the clock's two lines, and `anchors.verticalCenter`
            // on a direct child of a Row positioner sitting next to a taller sibling
            // wasn't actually landing on centre. Doing it one level down, inside an
            // ordinary Item, removes any question of how Row treats a sibling's own
            // cross-axis anchor.
            Item {
                width:  weatherRow.implicitWidth
                height: dateTimeColumn.height
                visible: Weather.ready && Weather.hasLocation

                Row {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs

                    // Icon and text differ in font size ("title"+iconScale vs "body"), so
                    // top-aligning them (Row's default) left the shorter temperature text
                    // sitting high with dead space under it, out of line with the icon.
                    // Centering both against the row itself lines them up regardless of
                    // which one is taller.
                    // The font's weather symbol (Weather.symbol — drawn outlined, its note says
                    // why), in the same tint the Fluent icon wore — or, as the hero, the chip's own
                    // text colour: `info` on primaryContainer all but vanished (2026-10-31).
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name:  Weather.symbol(Weather.code)
                        fill:  0
                        font.pixelSize: Math.round(Tokens.fontTitle * Config.barIconScale)
                        color: root.hero ? root._onHero : Colors.of(QsWindow.window).info
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    BarLabel {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.temp(Weather.tempC) + Weather.unit
                        color: root.hero ? root._onHero : Colors.of(QsWindow.window).fg
                    }
                }
            }
        }
    }
}
