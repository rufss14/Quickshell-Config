pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.UPower
import "../../config"
import "../../components"
import "../../services"

// ── IslandPower ───────────────────────────────────────────────────────────────
// Batteries and power on an island (2026-11-15, one of the user's new pages; the bottom-right island):
//
//   left    the loud card: this computer's battery (charge large, charging or not, how long until full or empty,
//           the watts) or, on a desktop, that it runs on mains; whether the battery saver is resting the effects
//   right   every other battery (headset, mouse, controller, phone…) as a ring each, the lowest first and in the
//           danger tone at or under 15% (services/DeviceBatteries); under them the power profile and the battery
//           saver as option cards
//
// The power profile needs power-profiles-daemon (PowerSaver.profilesOk): without it the cards are off and say so.
// Everything real is UPower, DeviceBatteries (held while this shows), PowerSaver and Config.powerSaver.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    Component.onCompleted: DeviceBatteries.acquire()
    Component.onDestruction: DeviceBatteries.release()

    // ── This computer ─────────────────────────────────────────────────────────
    readonly property var dev: UPower.displayDevice
    readonly property bool laptop: root.dev !== null && (root.dev.isLaptopBattery ?? false)
    readonly property real pct: root.dev ? root.dev.percentage * 100 : 0
    readonly property int devState: root.dev ? root.dev.state : UPowerDeviceState.Unknown
    readonly property bool charging: root.devState === UPowerDeviceState.Charging || root.devState === UPowerDeviceState.PendingCharge
    readonly property bool full: root.devState === UPowerDeviceState.FullyCharged
    function span(secs) {
        if (!secs || secs <= 0) return ""
        const h = Math.floor(secs / 3600), m = Math.floor((secs % 3600) / 60)
        return h > 0 ? Translation.tr("%1 h %2 min").arg(h).arg(m) : Translation.tr("%1 min").arg(m)
    }

    function kindIcon(kind) {
        return ({ mouse: "mouse", keyboard: "keyboard", headset: "headphones", headphones: "headphones",
                  speaker: "speaker", gamepad: "gamepad", phone: "smartphone", tablet: "tablet" })[kind] ?? "battery_full"
    }

    readonly property var profiles: PowerSaver.profilesOk && PowerProfiles.hasPerformanceProfile
        ? [PowerProfile.PowerSaver, PowerProfile.Balanced, PowerProfile.Performance]
        : [PowerProfile.PowerSaver, PowerProfile.Balanced]

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ This computer, loud ═══════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: !root.laptop ? "power" : root.charging ? "battery_charging_full" : "battery_full"
                        shape: root.charging ? "cookie9" : root.laptop && root.pct <= 15 ? "burst" : "squircle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.laptop ? Translation.tr("Battery") : Translation.tr("Mains power")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: !root.laptop ? Translation.tr("No battery in this computer")
                                : root.full ? Translation.tr("Fully charged")
                                : root.charging ? Translation.tr("Charging")
                                : Translation.tr("On battery")
                            variant: "caption"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                    }
                }

                Item { Layout.fillHeight: true; Layout.fillWidth: true }

                // The charge, as a ring with the number in it (or the plug on a desktop).
                RadialGauge {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Tokens.iconXl * 4
                    Layout.preferredHeight: Tokens.iconXl * 4
                    thickness: Tokens.spacingMd
                    wavy: root.charging && Motion.ambientOn
                    value: root.laptop ? root.pct / 100 : 1
                    accent: root.laptop && root.pct <= 15 && !root.charging ? root.palette.danger : root.palette.primary
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.laptop
                        text: Math.round(root.pct) + "%"
                        font.pixelSize: Tokens.fontDisplay
                        font.weight: Font.Bold
                        font.features: ({ tnum: 1 })
                        color: hero.ink
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: !root.laptop
                        name: "power"
                        font.pixelSize: Tokens.iconXl
                        color: hero.ink
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    visible: text !== ""
                    text: !root.laptop || !root.dev ? ""
                        : root.charging ? (root.span(root.dev.timeToFull) !== "" ? Translation.tr("Full in %1").arg(root.span(root.dev.timeToFull)) : "")
                        : (root.span(root.dev.timeToEmpty) !== "" ? Translation.tr("%1 left").arg(root.span(root.dev.timeToEmpty)) : "")
                    variant: "caption"
                    color: hero.inkDim
                }

                Item { Layout.fillHeight: true; Layout.fillWidth: true }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: "bolt"
                        fill: PowerSaver.active ? 1 : 0
                        color: hero.ink
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: PowerSaver.active ? Translation.tr("Battery saver is resting the effects")
                            : PowerSaver.quiet ? Translation.tr("Effects resting for Game Mode")
                            : Translation.tr("Effects running")
                        variant: "caption"
                        color: hero.inkDim
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        // ══ Right ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── Every other battery ────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            text: Translation.tr("Devices")
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: DeviceBatteries.lowest && DeviceBatteries.lowest.level <= DeviceBatteries.lowThreshold && !DeviceBatteries.lowest.charging
                                  ? Translation.tr("%1 is low").arg(DeviceBatteries.lowest.name) : ""
                            variant: "caption"
                            color: root.palette.danger
                            elide: Text.ElideRight
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Column {
                            anchors.centerIn: parent
                            visible: DeviceBatteries.devices.length === 0
                            spacing: Tokens.spacingXs
                            MorphShape {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Tokens.iconXl * 1.5
                                height: width
                                shape: "cookie9"
                                turns: false
                                fillColor: root.palette.plate
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "headphones"
                                    color: root.palette.fgMuted
                                }
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Translation.tr("No wireless devices report a battery")
                                variant: "caption"
                                emphasis: "muted"
                            }
                        }

                        Flickable {
                            anchors.fill: parent
                            visible: DeviceBatteries.devices.length > 0
                            contentWidth: ringsRow.implicitWidth
                            contentHeight: height
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.HorizontalFlick

                            Row {
                                id: ringsRow
                                height: parent.height
                                spacing: Tokens.spacingSm
                                Repeater {
                                    model: DeviceBatteries.devices
                                    delegate: Rectangle {
                                        id: devCard
                                        required property var modelData
                                        required property int index
                                        readonly property bool low: devCard.modelData.level <= DeviceBatteries.lowThreshold && !devCard.modelData.charging
                                        width: Tokens.spacingXl * 8
                                        height: ringsRow.height
                                        radius: Tokens.radiusCard
                                        color: root.palette.plate
                                        PopIn { id: dpop; active: true; index: devCard.index }
                                        opacity: dpop.opacity
                                        scale: dpop.scale

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.margins: Tokens.spacingMd
                                            spacing: Tokens.spacingXs
                                            RadialGauge {
                                                Layout.alignment: Qt.AlignHCenter
                                                Layout.preferredWidth: Math.min(devCard.width - Tokens.spacingMd * 2, devCard.height * 0.5)
                                                Layout.preferredHeight: Layout.preferredWidth
                                                thickness: Tokens.spacingSm
                                                value: devCard.modelData.level
                                                accent: devCard.low ? root.palette.danger : root.palette.primary
                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    name: devCard.modelData.charging ? "bolt" : root.kindIcon(devCard.modelData.kind)
                                                    fill: 1
                                                    color: devCard.low ? root.palette.danger : root.palette.fg
                                                }
                                            }
                                            Item { Layout.fillHeight: true }
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: Math.round(devCard.modelData.level * 100) + "%"
                                                font.pixelSize: Tokens.fontTitle
                                                font.weight: Font.Bold
                                                font.features: ({ tnum: 1 })
                                                color: devCard.low ? root.palette.danger : root.palette.fg
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                horizontalAlignment: Text.AlignHCenter
                                                text: devCard.modelData.name !== "" ? devCard.modelData.name : devCard.modelData.kind
                                                variant: "caption"
                                                emphasis: "muted"
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Profile and saver ──────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: powerCol.implicitHeight + Tokens.spacingMd * 2
                order: 2

                ColumnLayout {
                    id: powerCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    StyledText {
                        text: PowerSaver.profilesOk ? Translation.tr("Power profile") : Translation.tr("Power profile needs power-profiles-daemon")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        enabled: PowerSaver.profilesOk
                        opacity: enabled ? 1 : 0.45
                        Repeater {
                            model: root.profiles
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                label: modelData === PowerProfile.PowerSaver ? Translation.tr("Saver")
                                     : modelData === PowerProfile.Performance ? Translation.tr("Performance")
                                     : Translation.tr("Balanced")
                                symbol: modelData === PowerProfile.PowerSaver ? "battery_full"
                                      : modelData === PowerProfile.Performance ? "speed" : "equalizer"
                                shape: modelData === PowerProfile.PowerSaver ? "clover"
                                     : modelData === PowerProfile.Performance ? "burst" : "cookie9"
                                on: PowerSaver.profilesOk && PowerProfiles.profile === modelData
                                onActivated: if (PowerSaver.profilesOk) PowerProfiles.profile = modelData
                            }
                        }
                    }
                    StyledText {
                        text: Translation.tr("Battery saver")
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs
                        Repeater {
                            model: [{ v: "auto", t: Translation.tr("On battery"), s: "cookie9", i: "battery_full" },
                                    { v: "on",   t: Translation.tr("Always"),     s: "sunny",   i: "bolt" },
                                    { v: "off",  t: Translation.tr("Never"),      s: "circle",  i: "power" }]
                            delegate: OptionCard {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                label: modelData.t
                                symbol: modelData.i
                                shape: modelData.s
                                on: Config.powerSaver === modelData.v
                                onActivated: Config.powerSaver = modelData.v
                            }
                        }
                    }
                }
            }
        }
    }
}
