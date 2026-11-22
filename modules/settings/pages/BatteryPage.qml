pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"
import "../../../services"

// ── BatteryPage — Devices › Battery ───────────────────────────────────────────
// Charge, health, and the power profile.
//
// SettingsIndex only lists this view when a laptop battery is actually present, so on
// a desktop it doesn't exist rather than showing a page of em-dashes.
//
// ── The charge is a ring, not a glyph and a number ────────────────────────────
// It was a 52px battery glyph beside a big figure: the glyph said the same thing as
// the number, less precisely, and the number alone never said how full "62%" feels.
// The ring IS the proportion, the figure sits inside it, and the state and time left
// read as its caption. It breathes while charging and stops when the cable comes out.
//
// ── On not shelling out ───────────────────────────────────────────────────────
// Quickshell exposes power-profiles-daemon natively: `PowerProfiles.profile` is a
// read/WRITE D-Bus property, so setting it is an assignment and the change comes back
// on its own — including when something ELSE changes it. No `powerprofilesctl`
// get/list/set polling.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var dev: UPower.displayDevice

    // UPower reports a 0–1 fraction; everything below wants whole percent.
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0
    // `devState`, not `state`: Item already has a `state`, and shadowing it with an
    // int is a trap qmllint only sometimes catches.
    readonly property int devState: root.dev ? root.dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: root.devState === UPowerDeviceState.Charging
                                  || root.devState === UPowerDeviceState.PendingCharge
    readonly property bool full: root.devState === UPowerDeviceState.FullyCharged

    readonly property string stateText:
          root.full     ? Translation.tr("Fully charged")
        : root.charging ? Translation.tr("Charging")
        : root.devState === UPowerDeviceState.Discharging ? Translation.tr("On battery")
        : Translation.tr("Not charging")

    // Low battery is the shell's one genuine "something is wrong" moment.
    readonly property color chargeAccent:
          root.charging  ? Colors.of(QsWindow.window).primary
        : root.pct <= 15 ? Colors.of(QsWindow.window).danger
        : Colors.of(QsWindow.window).fg

    function fmtTime(secs) {
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m"
    }

    // How long until it is full, or empty. Empty while UPower has no estimate yet (right after a
    // cable change), so no line says "unknown remaining".
    readonly property string timeText: {
        if (!root.dev || root.full) return ""
        const secs = root.charging ? root.dev.timeToFull : root.dev.timeToEmpty
        if (!secs || secs <= 0) return ""
        return (root.charging ? Translation.tr("%1 until full") : Translation.tr("%1 remaining")).arg(root.fmtTime(secs))
    }
    readonly property string drawText: root.dev
        ? (root.charging ? Translation.tr("Drawing %1 W") : Translation.tr("Using %1 W")).arg(Math.abs(root.dev.changeRate).toFixed(1))
        : ""

    readonly property var profiles: PowerSaver.profilesOk && PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    // TabStrip's shape. The values are PowerProfile enum INTS, which is why its
    // `current`/`picked` are `var` — see ChipRow's note on the same trap.
    readonly property var profileSegments: root.profiles.map(p => ({
        value: p,
        label: p === PowerProfile.PowerSaver  ? Translation.tr("Power saver")
             : p === PowerProfile.Performance ? Translation.tr("Performance")
             :                                  Translation.tr("Balanced"),
        // Every name here has an icons.js fallback, so a machine without the
        // Material Symbols font gets a glyph rather than a "?".
        icon:  p === PowerProfile.PowerSaver  ? "battery_full"
             : p === PowerProfile.Performance ? "speed"
             :                                  "equalizer"
    }))

    // Room for three icon-and-label segments in a row's control slot.
    readonly property int modeWidth: Tokens.fieldHeight * 13

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "󰁽"
        title:     Translation.tr("Battery")
        titleTail: root.dev ? Math.round(root.pct) + "%" : ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.stateText + (root.timeText !== "" ? "  ·  " + root.timeText : "")

        // ══ Charge and health ═════════════════════════════════════════════════
        // The live subject: the ring is the charge, the lines beside it are the cell's state
        // and its health. Both are readings of the same battery, so they share one card.
        Section {
            id: chargeCard
            hero: true

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXl

                RadialGauge {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth:  120
                    implicitHeight: 120
                    thickness: 11
                    value:  root.pct / 100
                    // The card is primaryContainer, so the ring draws in its ink; only the
                    // low-battery state keeps its own colour.
                    accent: root.pct <= 15 && !root.charging
                            ? Colors.of(QsWindow.window).danger : chargeCard.ink

                    // Charging is the one state that is going somewhere, so the ring
                    // breathes while it does. The only idle motion in settings, and it
                    // stops the instant the cable comes out.
                    SequentialAnimation on opacity {
                        running: root.charging && Config.motionEnabled
                        loops: Animation.Infinite
                        alwaysRunToEnd: true
                        NumberAnimation { to: 0.55; duration: 900; easing.type: Motion.inOut }
                        NumberAnimation { to: 1.0;  duration: 900; easing.type: Motion.inOut }
                    }
                    onOpacityChanged: if (!root.charging) opacity = 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: -2

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Math.round(root.pct)
                            variant: "display"
                            font.bold: true
                            color: chargeCard.ink
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("percent")
                            variant: "micro"
                            color: chargeCard.inkDim
                        }
                    }
                }

                // The reading in two columns where the card is wide (what it is doing, then what
                // the cell is like), one under the other where it is not.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.alignment: Qt.AlignVCenter
                    columns: width >= 460 ? 2 : 1
                    columnSpacing: Tokens.spacingXl
                    rowSpacing: Tokens.spacingMd

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.alignment: Qt.AlignTop
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs

                        StyledText {
                            text:  root.stateText
                            color: chargeCard.ink
                            variant: "title"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.timeText !== "" ? root.timeText : root.drawText
                            variant: "body"
                            color: chargeCard.inkDim
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.timeText !== "" && root.drawText !== ""
                            text: root.drawText
                            variant: "body"
                            color: chargeCard.inkDim
                            elide: Text.ElideRight
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        Layout.alignment: Qt.AlignTop
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        // Health is the one number here about the battery's FUTURE, so it gets a
                        // bar: 100% is a new cell and the shortfall is the reading.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            visible: root.dev && root.dev.healthSupported
                            spacing: Tokens.spacingMd

                            HelpTip { text: Translation.tr("How much of the battery's original capacity is left.") }

                            StyledText {
                                text: Translation.tr("Health")
                                variant: "caption"
                                color: chargeCard.inkDim
                            }
                            Meter {
                                Layout.fillWidth: true
                                value: root.dev && root.dev.healthSupported
                                       ? root.dev.healthPercentage / 100 : 0
                                accent: root.dev && root.dev.healthPercentage < 70
                                        ? Colors.of(QsWindow.window).warning : chargeCard.ink
                            }
                            StyledText {
                                text: root.dev && root.dev.healthSupported
                                      ? Math.round(root.dev.healthPercentage) + "%" : ""
                                variant: "title"
                                font.weight: Font.DemiBold
                                color: chargeCard.ink
                            }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            visible: !(root.dev && root.dev.healthSupported)
                            text: Translation.tr("This battery doesn't report its health.")
                            variant: "caption"
                            color: chargeCard.inkDim
                            wrapMode: Text.WordWrap
                        }

                        FactRow {
                            visible: !!root.dev && root.dev.energyCapacity > 0
                            key:   Translation.tr("Capacity")
                            value: root.dev ? root.dev.energyCapacity.toFixed(1) + " Wh" : ""
                            ink:    chargeCard.ink
                            inkDim: chargeCard.inkDim
                        }
                    }
                }
            }
        }

        // ══ Power mode ════════════════════════════════════════════════════════
        // Mutually exclusive modes as a connected choice: the selection moves between them.
        // The system's profile and the shell's own costs (battery saver) are separate things, so
        // they are separate groups, side by side.
        Section {
            grouped:  true
            symbol:   "speed"
            title:    Translation.tr("Power mode")

            SettingRow {
                label:  Translation.tr("Profile")
                detail: PowerSaver.profilesOk ? Translation.tr("How hard the machine may work")
                    : Translation.tr("Needs power-profiles-daemon (or tuned-ppd), which isn't running on this machine")
                help:   Translation.tr("Trades battery life against how hard the machine will work.")
                wrapDetail: true

                TabStrip {
                    // A SettingRow's control slot is a plain Item: size by implicitWidth.
                    implicitWidth: root.modeWidth
                    connected: true
                    accent:  Colors.of(QsWindow.window).primary
                    model:   root.profileSegments
                    enabled: PowerSaver.profilesOk
                    current: PowerSaver.profilesOk ? PowerProfiles.profile : -1
                    // A plain assignment: `profile` is a writable D-Bus property and the
                    // daemon's reply drives the selection back through the binding.
                    onPicked: function (v) { if (PowerSaver.profilesOk) PowerProfiles.profile = v }
                }
            }
        }

        // ══ Battery saver ═════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "battery_charging_full"
            title:    Translation.tr("Battery saver")
            subtitle: PowerSaver.active ? Translation.tr("On now") : ""

            SettingRow {
                label:  Translation.tr("Rest the shell")
                detail: PowerSaver.active ? Translation.tr("Ambient effects are resting") : Translation.tr("Everything runs")
                help:   Translation.tr("Rests the cava background, wallpaper effects, floating cookies and the beat clock, and caps Wallpaper Engine at 30 fps. Animations stay.")

                TabStrip {
                    implicitWidth: root.modeWidth
                    connected: true
                    accent:  Colors.of(QsWindow.window).primary
                    model: [
                        { value: "auto", label: Translation.tr("On battery"), icon: "battery_charging_full" },
                        { value: "on",   label: Translation.tr("Always"),     icon: "bolt" },
                        { value: "off",  label: Translation.tr("Never"),      icon: "block" }
                    ]
                    current: Config.powerSaver
                    onPicked: function (v) { Config.powerSaver = v }
                }
            }
        }
    }

    component FactRow: RowLayout {
        id: factRow
        property string key:   ""
        property string value: ""
        property color  ink:    Colors.of(QsWindow.window).fg
        property color  inkDim: Colors.of(QsWindow.window).fgDim

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        StyledText {
            Layout.fillWidth: true
            text:     factRow.key
            variant:  "caption"
            color:    factRow.inkDim
        }
        StyledText {
            text:    factRow.value
            variant: "caption"
            color:   factRow.ink
        }
    }
}
