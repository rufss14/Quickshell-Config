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
          root.full     ? "Fully charged"
        : root.charging ? "Charging"
        : root.devState === UPowerDeviceState.Discharging ? "On battery"
        : "Not charging"

    // Low battery is the shell's one genuine "something is wrong" moment.
    readonly property color chargeAccent:
          root.charging  ? Colors.of(QsWindow.window).primary
        : root.pct <= 15 ? Colors.of(QsWindow.window).danger
        : Colors.of(QsWindow.window).fg

    function fmtTime(secs) {
        if (!secs || secs <= 0) return "—"
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m"
    }

    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    // TabStrip's shape. The values are PowerProfile enum INTS, which is why its
    // `current`/`picked` are `var` — see ChipRow's note on the same trap.
    readonly property var profileSegments: root.profiles.map(p => ({
        value: p,
        label: p === PowerProfile.PowerSaver  ? "Power saver"
             : p === PowerProfile.Performance ? "Performance"
             :                                  "Balanced",
        // Every name here has an icons.js fallback, so a machine without the
        // Material Symbols font gets a glyph rather than a "?".
        icon:  p === PowerProfile.PowerSaver  ? "battery_full"
             : p === PowerProfile.Performance ? "speed"
             :                                  "equalizer"
    }))

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰁽"
        title:     Translation.tr("Battery")
        titleTail: root.dev ? Math.round(root.pct) + "%" : ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  root.stateText + (root.dev
                   ? "  ·  " + (root.charging
                                ? root.fmtTime(root.dev.timeToFull) + " until full"
                                : root.fmtTime(root.dev.timeToEmpty) + " remaining")
                   : "")

        // ══ Charge ════════════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󱈑"
            title:  Translation.tr("Charge")
            accent: Colors.of(QsWindow.window).primary
            subtitle: root.dev
                ? (root.charging ? "Drawing " : "Using ")
                  + Math.abs(root.dev.changeRate).toFixed(1) + " W"
                : ""

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
                    accent: root.chargeAccent

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
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: "percent"
                            variant: "micro"
                            emphasis: "dim"
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs

                    StyledText {
                        text:  root.stateText
                        color: root.chargeAccent
                        variant: "title"
                        font.weight: Font.DemiBold
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.charging
                            ? root.fmtTime(root.dev ? root.dev.timeToFull : 0) + " until full"
                            : root.fmtTime(root.dev ? root.dev.timeToEmpty : 0) + " remaining"
                        variant: "body"
                        emphasis: "muted"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ══ The cell itself ═══════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰁹"
            title:    Translation.tr("Health")
            accent:   Colors.of(QsWindow.window).info
            help:     Translation.tr("How much of the battery's original capacity is left.")

            // Health is the one number here about the battery's FUTURE, so it gets a
            // bar: 100% is a new cell and the shortfall is the reading.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.dev && root.dev.healthSupported
                spacing: Tokens.spacingMd

                Meter {
                    Layout.fillWidth: true
                    value: root.dev && root.dev.healthSupported
                           ? root.dev.healthPercentage / 100 : 0
                    accent: root.dev && root.dev.healthPercentage < 70
                            ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).info
                }
                StyledText {
                    text: root.dev && root.dev.healthSupported
                          ? Math.round(root.dev.healthPercentage) + "%" : "—"
                    variant: "title"
                    font.weight: Font.DemiBold
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: !(root.dev && root.dev.healthSupported)
                text: Translation.tr("This battery doesn't report its health.")
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            FactRow {
                key:   "Capacity"
                value: root.dev ? root.dev.energyCapacity.toFixed(1) + " Wh" : "—"
            }
            FactRow {
                key:   "Draw"
                value: root.dev ? Math.abs(root.dev.changeRate).toFixed(1) + " W" : "—"
            }
        }

        // ══ Power mode ════════════════════════════════════════════════════════
        // A segmented control, not pills: three mutually exclusive modes, and the
        // selection slides between them so the change is a move rather than a blink.
        Section {
            span:     2
            glyph:    "󰓅"
            title:    Translation.tr("Power mode")
            accent:   Colors.of(QsWindow.window).primary
            help:     Translation.tr("Trades battery life against how hard the machine will work.")

            TabStrip {
                Layout.fillWidth: true
                accent:  Colors.of(QsWindow.window).primary
                model:   root.profileSegments
                current: PowerProfiles.profile
                // A plain assignment: `profile` is a writable D-Bus property and the
                // daemon's reply drives the selection back through the binding.
                onPicked: function (v) { PowerProfiles.profile = v }
            }
        }

        // ══ Battery saver (services/PowerSaver) ═══════════════════════════════
        // The shell's own costs, separate from the system's power profile above.
        Section {
            span:     2
            glyph:    "󰂃"
            title:    Translation.tr("Battery saver")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: PowerSaver.active ? "On — ambient effects are resting" : "Off"
            help:     Translation.tr("Rests the cava background, wallpaper effects, floating cookies and the beat clock, and caps Wallpaper Engine at 30 fps. Animations stay.")

            TabStrip {
                Layout.fillWidth: true
                accent:  Colors.of(QsWindow.window).primary
                model: [
                    { value: "auto", label: "On battery", icon: "battery_charging_full" },
                    { value: "on",   label: "Always",     icon: "bolt" },
                    { value: "off",  label: "Never",      icon: "block" }
                ]
                current: Config.powerSaver
                onPicked: function (v) { Config.powerSaver = v }
            }
        }
    }

    component FactRow: RowLayout {
        id: factRow
        property string key:   ""
        property string value: ""

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        StyledText {
            Layout.fillWidth: true
            text:     factRow.key
            variant:  "caption"
            emphasis: "dim"
        }
        StyledText {
            text:    factRow.value
            variant: "caption"
        }
    }
}
