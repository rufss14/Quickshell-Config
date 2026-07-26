import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../config"
import "../../../components"

// ── BatteryPage ───────────────────────────────────────────────────────────────
// Charge, health, and the power profile.
//
// SettingsCard only lists this page when a laptop battery is actually present, so
// on a desktop it doesn't exist rather than showing a page of em-dashes.
//
// ── On not shelling out ───────────────────────────────────────────────────────
// The obvious build of the profile selector runs `powerprofilesctl get`, parses
// `powerprofilesctl list` with sed, and re-runs both after every `set` to find out
// whether it worked. Quickshell exposes power-profiles-daemon natively:
// `PowerProfiles.profile` is a read/WRITE property on the D-Bus interface, so
// setting it is an assignment and the change signal comes back on its own. That's
// three processes and a text parser replaced with two bindings — and it stays
// correct when something *else* changes the profile, which the polling version
// only noticed if you happened to press a button.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var dev: UPower.displayDevice

    // UPower reports a 0–1 fraction; everything below wants whole percent.
    readonly property real pct:   root.dev ? root.dev.percentage * 100 : 0
    // `devState`, not `state`: Item already has a `state` (the QML state-machine
    // name), and shadowing it with an int is the same trap ValueSlider documents for
    // `enabled`. qmllint catches this one; it does not catch all of them.
    readonly property int devState: root.dev ? root.dev.state : UPowerDeviceState.Unknown

    readonly property bool charging: root.devState === UPowerDeviceState.Charging
                                  || root.devState === UPowerDeviceState.PendingCharge
    readonly property bool full: root.devState === UPowerDeviceState.FullyCharged

    readonly property string stateText:
          root.full     ? "Fully charged"
        : root.charging ? "Charging"
        : root.devState === UPowerDeviceState.Discharging ? "On battery"
        : "Not charging"

    // Low battery is the shell's one genuine "something is wrong" moment, so it
    // takes `danger`. On a monochrome pywal palette danger and primary resolve to
    // the same colour — that's the palette's doing, not a mistake here.
    readonly property color chargeAccent:
          root.charging ? Colors.focus
        : root.pct <= 15 ? Colors.danger
        : Colors.fg

    function fmtTime(secs) {
        if (!secs || secs <= 0) return "—"
        const h = Math.floor(secs / 3600)
        const m = Math.floor((secs % 3600) / 60)
        return (h > 0 ? h + "h " : "") + m + "m"
    }

    readonly property var profiles: PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        PanelHeader {
            glyph:     "󰁽"
            title:     "Battery"
            titleTail: root.dev ? Math.round(root.pct) + "%" : ""
            subtitle:  root.stateText
        }

        Divider {}

        // ══ Charge ════════════════════════════════════════════════════════════
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingLg

            // The Nerd Font battery glyphs are a contiguous run: 󰁺 (10%) through
            // 󰂁 (90%) and 󰁹 (full), so the level glyph is arithmetic rather than a
            // ten-branch switch. Charging and critical have their own.
            StyledText {
                text: {
                    if (root.charging)  return "󰂄"
                    if (root.pct <= 5)  return "󰂃"
                    const r = Math.round(root.pct / 10)
                    return String.fromCodePoint(r >= 10 ? 0xF0079 : 0xF0079 + r)
                }
                color: root.chargeAccent
                font.family: Tokens.fontFamily
                font.pixelSize: 52
                Behavior on color { ColorAnimation { duration: Motion.standard } }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Math.round(root.pct) + "%"
                    variant: "display"
                    font.bold: true
                }
                StyledText {
                    text:  root.stateText
                    color: root.chargeAccent
                    variant: "body"
                }
            }
        }

        // ══ Detail ════════════════════════════════════════════════════════════
        Surface {
            Layout.fillWidth: true
            elevation: Tokens.elevationNested
            implicitHeight: detail.implicitHeight + Tokens.spacingLg * 2

            ColumnLayout {
                id: detail
                anchors.left:   parent.left
                anchors.right:  parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                FactRow {
                    key:   "Time remaining"
                    value: root.charging
                        ? root.fmtTime(root.dev ? root.dev.timeToFull : 0) + " to full"
                        : root.fmtTime(root.dev ? root.dev.timeToEmpty : 0) + " left"
                }
                FactRow {
                    key:   "Health"
                    value: (root.dev && root.dev.healthSupported)
                        ? Math.round(root.dev.healthPercentage) + "%"
                        : "—"
                }
                FactRow {
                    key:   "Capacity"
                    value: root.dev ? root.dev.energyCapacity.toFixed(1) + " Wh" : "—"
                }
                FactRow {
                    key:   "Rate"
                    value: root.dev ? Math.abs(root.dev.changeRate).toFixed(1) + " W" : "—"
                }
            }
        }

        // ══ Power profile ═════════════════════════════════════════════════════
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            text: "Power mode"
            variant: "label"
            emphasis: "muted"
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            Repeater {
                model: root.profiles

                Rectangle {
                    id: profileButton
                    required property var modelData

                    readonly property bool selected: PowerProfiles.profile === profileButton.modelData

                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: Tokens.radiusSm

                    // A segmented control, so the selected segment is `focus` (where
                    // you are), not `primary` (a thing to press). Same reasoning as
                    // the settings rail.
                    color: profileButton.selected ? Colors.alpha(Colors.focus, 0.16)
                         : profileHover.hovered   ? Colors.alpha(Colors.fg, 0.06)
                         :                          Colors.surfaceFor(Tokens.elevationNested)

                    border.width: Tokens.borderWidth
                    border.color: profileButton.selected
                        ? Colors.alpha(Colors.focus, 0.40)
                        : Colors.outlineFor(Tokens.elevationNested)

                    Behavior on color        { ColorAnimation { duration: Motion.respond } }
                    Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                    StyledText {
                        anchors.centerIn: parent
                        // The service's own toString gives "power-saver"; this is the
                        // only place that maps it to something a person reads.
                        text: profileButton.modelData === PowerProfile.PowerSaver  ? "Power saver"
                            : profileButton.modelData === PowerProfile.Performance ? "Performance"
                            :                                                        "Balanced"
                        color: profileButton.selected ? Colors.focus : Colors.fg
                        variant: "body"
                        font.weight: profileButton.selected ? Font.DemiBold : Font.Normal
                    }

                    HoverHandler { id: profileHover; cursorShape: Qt.PointingHandCursor }
                    // A plain assignment: `profile` is a writable D-Bus property, and
                    // the daemon's reply drives `selected` back through the binding.
                    TapHandler { onTapped: PowerProfiles.profile = profileButton.modelData }
                }
            }
        }

        Item { Layout.fillHeight: true }
    }

    component FactRow: RowLayout {
        id: factRow

        property string key:   ""
        property string value: ""

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        StyledText {
            Layout.preferredWidth: 130
            text:     factRow.key
            variant:  "caption"
            emphasis: "dim"
        }
        StyledText {
            Layout.fillWidth: true
            text:    factRow.value
            variant: "caption"
        }
    }
}
