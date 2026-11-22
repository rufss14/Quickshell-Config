pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../../config"
import "../../../components"
import "../../../services"

// ── BluetoothPage — Devices › Bluetooth ───────────────────────────────────────
// Your devices, and adding one.
//
// ── Simpler ───────────────────────────────────────────────────────────────────
// Six cards (adapter, pairing, nearby, devices, alerts, activity) were the whole of what
// BlueZ and the shell can do laid out at once. What you open this page for is two
// things: connect or disconnect something you own, and add something new. So:
//   · your devices are TILES — the device, its state and battery, one tap to connect or
//     disconnect it; hover for trust and forget
//   · Scan (the header) opens a Nearby card under them for as long as it looks
//   · everything that is a setting is two groups of rows under them: how this machine
//     is seen and pairs, and what it says about your devices
// The session activity feed is gone from the page (the panel still has it); the latest
// line of it is the subtitle of the card it is about.
//
// ── This page is a view; Bt and Quickshell.Bluetooth do the work ──────────────
// The native `Bluetooth` singleton tracks BlueZ over D-Bus, event-driven. Which
// adapter, which devices are ours, and which glyph is a headset live in services/Bt
// — shared with the bar's pill and panel, so a fix can't land on one and miss the
// other. Discovery, pairing and the activity feed live in Bt too. Scanning is the one
// costly thing: this page takes a hold on it only while its Scan chip is on, and
// leaving the page lets go.
//
// ── The honest limit: pairing has no agent unless the shell's is on ───────────
// Quickshell exposes pair()/cancelPair() but no BlueZ pairing agent of its own; the
// shell's (BtBridge) asks in the panel. Without it, devices that need a passkey
// confirmation (some keyboards, some phones) sit in "pairing" and then fail.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property bool hasAdapter: Bt.adapter !== null && Bt.adapter !== undefined

    // ── Scanning is a hold on Bt, not a write to the adapter ──────────────────
    // The panel's Nearby tab scans too. Writing `discovering` from here would let
    // leaving this page stop a scan the panel is still showing (and vice versa), so
    // the cookie flips this page's hold and Bt scans while anyone holds.
    property bool scanHeld: false
    onScanHeldChanged: root.scanHeld ? Bt.acquireScan() : Bt.releaseScan()
    onVisibleChanged: if (!root.visible) root.scanHeld = false
    Component.onDestruction: if (root.scanHeld) Bt.releaseScan()

    // Keyed on dbusPath: adapters come and go when a dongle is unplugged, and an index
    // would silently point at a different one. Index loop, not `.map` — Bt.adapters is
    // a model's `values`, which the service itself only ever indexes.
    // Labelled "Adapter N", not hci0: the kernel's name is jargon, and every adapter
    // reports the host's own name, so the name tells two of them apart no better.
    readonly property var adapterChips: {
        const list = Bt.adapters, out = []
        for (let i = 0; i < list.length; i++)
            out.push({ value: list[i].dbusPath, label: Translation.tr("Adapter %1").arg(i + 1) })
        return out
    }
    readonly property string adapterLabel: {
        const list = Bt.adapters
        for (let i = 0; i < list.length; i++)
            if (Bt.adapter && list[i].dbusPath === Bt.adapter.dbusPath)
                return Translation.tr("Adapter %1").arg(i + 1)
        return ""
    }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     Bt.powered ? (Bt.connectedCount > 0 ? "󰂱" : "󰂯") : "󰂲"
        title:     Translation.tr("Bluetooth")
        titleTail: Bt.adapter && Bt.adapters.length > 1 ? root.adapterLabel : ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle: !root.hasAdapter
                ? "No Bluetooth adapter"
                : !Bt.powered
                ? "Bluetooth is off"
                : Bt.connectedCount + " connected  ·  " + Bt.known.length + " paired"
                  + (Bt.scanning ? "  ·  scanning" : "")

        actions: [
            ChipTray {
                visible: root.hasAdapter
                ChipButton {
                    symbol:  "bluetooth_searching"
                    label:   Bt.scanning ? "Stop" : "Scan"
                    on:      Bt.scanning
                    tint:    Colors.of(QsWindow.window).primary
                    enabled: Bt.powered
                    iconAngle: Bt.scanning ? scanSpin.angle : 0
                    onActivated: root.scanHeld = !root.scanHeld

                    // Turns while it looks — "still scanning" is not a still icon.
                    QtObject {
                        id: scanSpin
                        property real angle: 0
                        NumberAnimation on angle {
                            running: Bt.scanning
                            from: 0; to: 360
                            duration: 2400
                            loops: Animation.Infinite
                        }
                    }
                }
            },
            StyledText {
                visible: root.hasAdapter
                Layout.alignment: Qt.AlignVCenter
                text: Bt.powered ? Translation.tr("On") : Translation.tr("Off")
                variant: "caption"
                emphasis: "dim"
            },
            Toggle {
                accent: Colors.of(QsWindow.window).primary
                accessibleName: Translation.tr("Bluetooth")
                enabled: root.hasAdapter
                checked: Bt.adapter ? Bt.adapter.enabled : false
                onToggled: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
            }
        ]

        Section {
            visible: !root.hasAdapter
            symbol:   "bluetooth_disabled"
            title:    Translation.tr("No adapter")
            subtitle: Translation.tr("No Bluetooth adapter was found, or BlueZ isn't running.")
            accent:   Colors.of(QsWindow.window).primary
        }

        // ══ Your devices ══════════════════════════════════════════════════════
        // The tiles are one tool body, so they sit in the group as a single segment.
        Section {
            grouped:  true
            fullRow:  true
            visible: root.hasAdapter
            symbol:   "devices"
            title:    Translation.tr("My devices")
            subtitle: Bt.known.length === 0 ? Translation.tr("Nothing paired yet")
                    : Bt.events.length > 0 ? Bt.events[0].text
                    : Translation.tr("Tap one to connect or disconnect it")

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: Bt.known.length === 0
                text: Bt.powered ? Translation.tr("Press Scan, put a device in pairing mode, and it shows up under Nearby")
                                 : Translation.tr("Turn Bluetooth on to see your devices")
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 640 ? 3 : 2
                uniformCellWidths: true
                columnSpacing: Tokens.spacingMd
                rowSpacing: Tokens.spacingMd

                Repeater {
                    model: Bt.known

                    Rectangle {
                        id: dev
                        required property var modelData

                        readonly property bool transitioning:
                               dev.modelData.state === BluetoothDeviceState.Connecting
                            || dev.modelData.state === BluetoothDeviceState.Disconnecting
                        readonly property bool on: dev.modelData.connected
                        readonly property bool hot: devHover.hovered
                        readonly property real battery: dev.modelData.batteryAvailable ? Bt.batteryLevel(dev.modelData) : -1

                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        // A lone device is a tile, not a banner across the card.
                        Layout.maximumWidth: 320
                        Layout.alignment: Qt.AlignLeft | Qt.AlignTop
                        // One badge and two lines: nothing under them to leave empty.
                        implicitHeight: Tokens.iconXl + Tokens.spacingLg * 2
                        radius: Tokens.radiusCard
                        // Connected is the state, so the tile carries it: the accent
                        // washes into the fill, as a QuickToggleTile does.
                        color: dev.on ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh,
                                                Colors.of(QsWindow.window).primary, 0.22)
                                      : dev.hot ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh,
                                                  Colors.of(QsWindow.window).fg, 0.07)
                                                : Colors.of(QsWindow.window).surfaceHigh
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                        opacity: Bt.powered ? 1.0 : 0.5
                        scale: devTap.pressed ? 0.98 : 1.0
                        Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.overshoot } }

                        StateLayer {
                            id: devRipple
                            anchors.fill: parent
                            layerColor: Colors.of(QsWindow.window).primary
                            hoverOpacity: 0
                            pressOpacity: 0.18
                            radius: dev.radius
                        }

                        HoverHandler { id: devHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: devTap
                            enabled: Bt.powered && !dev.transitioning
                            onPressedChanged: if (pressed) devRipple.press(point.position.x, point.position.y)
                                              else devRipple.release()
                            onTapped: Bt.toggleConnection(dev.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingMd
                            spacing: Tokens.spacingMd

                            ShapeBox {
                                implicitWidth:  Tokens.iconXl + Tokens.spacingMd
                                implicitHeight: Tokens.iconXl + Tokens.spacingMd
                                fallback:    "rounded"
                                fillColor:   Colors.of(QsWindow.window).alpha(dev.on ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim,
                                                                              dev.on ? 0.26 : 0.14)
                                Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    glyph: Bt.deviceGlyph(dev.modelData)
                                    variant: "title"
                                    color: dev.on ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: dev.modelData.name || dev.modelData.address
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Bt.stateCaption(dev.modelData)
                                        + (dev.battery >= 0 ? "  ·  " + Math.round(dev.battery * 100) + "%" : "")
                                    variant: "caption"
                                    color: dev.on ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgDim
                                    elide: Text.ElideRight
                                }
                            }

                            BusyDot { running: dev.transitioning; tint: Colors.of(QsWindow.window).primary }
                        }

                        // Battery, when the device reports one: a hairline on the tile's lower edge.
                        Meter {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.leftMargin: dev.radius
                            anchors.rightMargin: dev.radius
                            anchors.bottomMargin: Tokens.spacingSm
                            height: 3
                            visible: dev.battery >= 0
                            value:  Math.max(0, dev.battery)
                            accent: dev.battery >= 0 && dev.battery < 0.2 ? Colors.of(QsWindow.window).danger
                                                                          : Colors.of(QsWindow.window).primary
                        }

                        // Trust and forget: small, out of the way, only under the pointer.
                        ChipTray {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Tokens.spacingSm
                            opacity: dev.hot ? 1 : 0
                            visible: opacity > 0.01
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            ChipButton {
                                symbol: "verified_user"
                                on:     dev.modelData.trusted
                                tint:   Colors.of(QsWindow.window).primary
                                // A trusted device reconnects without asking.
                                onActivated: dev.modelData.trusted = !dev.modelData.trusted
                            }
                            // Forget unpairs AND deletes the stored key.
                            ChipButton {
                                symbol: "delete"
                                tint:   Colors.of(QsWindow.window).danger
                                onActivated: dev.modelData.forget()
                            }
                        }
                    }
                }
            }
        }

        // ══ Nearby ════════════════════════════════════════════════════════════
        // Only while there is something to say: scanning, or devices found.
        Section {
            grouped:  true
            visible: root.hasAdapter && (Bt.scanning || Bt.nearby.length > 0)
            symbol:   "bluetooth_searching"
            title:    Translation.tr("Nearby")
            subtitle: Bt.nearby.length === 0 ? Translation.tr("Put the device in pairing mode")
                                            : Translation.tr("%1 found").arg(Bt.nearby.length)

            Repeater {
                model: Bt.nearby

                Item {
                    id: nearRow
                    required property var modelData

                    Layout.fillWidth: true
                    implicitHeight: Math.max(nearBox.implicitHeight, Tokens.pillHeight)

                    RowLayout {
                        id: nearBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Tokens.spacingMd

                        MaterialIcon {
                            glyph: Bt.deviceGlyph(nearRow.modelData)
                            variant: "body"
                            emphasis: "dim"
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: nearRow.modelData.name || nearRow.modelData.address
                                variant: "body"
                                font.weight: Font.Medium
                                // A nameless row is a pairing attempt whose name
                                // hasn't landed yet — dim until it does.
                                emphasis: nearRow.modelData.deviceName ? "normal" : "dim"
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: !!nearRow.modelData.deviceName
                                text: nearRow.modelData.address
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }
                        BusyDot { running: nearRow.modelData.pairing; tint: Colors.of(QsWindow.window).primary }

                        ChipTray {
                            ChipButton {
                                label:  nearRow.modelData.pairing ? "Cancel" : "Pair"
                                symbol: nearRow.modelData.pairing ? "close" : "add"
                                on:     !nearRow.modelData.pairing
                                tint:   Colors.of(QsWindow.window).primary
                                // Trust → pair → connect, or cancel — the order is Bt's.
                                onActivated: Bt.pair(nearRow.modelData)
                            }
                        }
                    }
                }
            }
        }

        // ══ How this machine is seen ══════════════════════════════════════════
        // What the machine allows. They are independent switches, not a set to pick from,
        // so each is its own row you tap anywhere on.
        Section {
            grouped:  true
            visible: root.hasAdapter
            symbol:   "tune"
            title:    Translation.tr("Connection")
            subtitle: Bt.adapter ? BluetoothAdapterState.toString(Bt.adapter.state) : ""
            help:     BtBridge.shareBlocker() === ""
                      ? Translation.tr("Sending files works: drop one on the Bluetooth panel, or press Send on a screenshot.")
                      : Translation.tr("Sending files needs %1. Install it and obexd starts on demand.").arg(BtBridge.shareBlocker())

            // Only when there's a choice to make.
            ChipRow {
                Layout.fillHeight: false
                visible: Bt.adapters.length > 1
                accent:  Colors.of(QsWindow.window).primary
                model:   root.adapterChips
                current: Bt.adapter ? Bt.adapter.dbusPath : ""
                onPicked: function (v) { Config.btAdapter = v }
            }

            // A switch the adapter can't use right now dims rather than vanishing.
            SettingRow {
                rowTap:  true
                enabled: Bt.powered
                opacity: enabled ? 1 : 0.4
                label:   Translation.tr("Discoverable")
                detail:  Bt.adapter && Bt.adapter.discoverable ? Translation.tr("Others can find this machine")
                                                               : Translation.tr("Hidden from other devices")
                help:    Translation.tr("Others can find this machine.")
                onTapped: if (Bt.adapter) Bt.adapter.discoverable = !Bt.adapter.discoverable

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Bt.adapter ? Bt.adapter.discoverable : false
                    onToggled: if (Bt.adapter) Bt.adapter.discoverable = !Bt.adapter.discoverable
                }
            }
            SettingRow {
                rowTap:  true
                enabled: Bt.powered
                opacity: enabled ? 1 : 0.4
                label:   Translation.tr("Accept pairing")
                detail:  Bt.adapter && Bt.adapter.pairable ? Translation.tr("Devices may start pairing")
                                                           : Translation.tr("Pairing only from this machine")
                help:    Translation.tr("Devices may start pairing.")
                onTapped: if (Bt.adapter) Bt.adapter.pairable = !Bt.adapter.pairable

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Bt.adapter ? Bt.adapter.pairable : false
                    onToggled: if (Bt.adapter) Bt.adapter.pairable = !Bt.adapter.pairable
                }
            }
            SettingRow {
                rowTap:  true
                enabled: BtBridge.agentBlocker() === ""
                opacity: enabled ? 1 : 0.4
                label:   Translation.tr("Pairing agent")
                detail:  BtBridge.agentBlocker() === ""
                         ? Translation.tr("Asks you in the Bluetooth panel when a device shows a code or wants a PIN")
                         : BtBridge.agentBlocker()
                wrapDetail: true
                onTapped: Config.btAgent = !Config.btAgent

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.btAgent
                    onToggled: Config.btAgent = !Config.btAgent
                }
            }
        }

        // ══ What it says about your devices ═══════════════════════════════════
        Section {
            grouped:  true
            visible: root.hasAdapter
            symbol:   "notifications"
            title:    Translation.tr("Alerts")

            SettingRow {
                rowTap:  true
                label:   Translation.tr("Announce connections")
                detail:  Translation.tr("A card on connect and drop")
                onTapped: Config.btConnectOsd = !Config.btConnectOsd

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.btConnectOsd
                    onToggled: Config.btConnectOsd = !Config.btConnectOsd
                }
            }
            SettingRow {
                rowTap:  true
                label:   Translation.tr("Low battery warnings")
                detail:  Config.btBatteryWarn ? Translation.tr("Warns at %1%").arg(Config.btBatteryLow)
                                              : Translation.tr("Off")
                help:    Translation.tr("A notification at the threshold, and again at half of it, once each per charge.")
                onTapped: Config.btBatteryWarn = !Config.btBatteryWarn

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.btBatteryWarn
                    onToggled: Config.btBatteryWarn = !Config.btBatteryWarn
                }
            }
            SettingRow {
                rowTap:  true
                label:   Translation.tr("Battery ring on the bar")
                detail:  Translation.tr("Lowest battery, around the icon")
                onTapped: Config.btPillBattery = !Config.btPillBattery

                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.btPillBattery
                    onToggled: Config.btPillBattery = !Config.btPillBattery
                }
            }

            // Depends on the warnings switch: dimmed while that is off.
            SliderRow {
                enabled: Config.btBatteryWarn
                label: Translation.tr("Warn at")
                from:  Config.btBatteryLowMin
                to:    Config.btBatteryLowMax
                step:  5
                value: Config.btBatteryLow
                readout: Config.btBatteryLow + "%"
                onCommit: function (v) { Config.btBatteryLow = Math.round(v) }
            }
        }
    }
}
