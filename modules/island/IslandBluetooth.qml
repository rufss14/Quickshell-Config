pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── IslandBluetooth ───────────────────────────────────────────────────────────
// Bluetooth as an island page, in the Dashboard's dialect: three columns of flat cards that arrive one
// after another. Left, the loud one: the radio and the device you are using (its battery, the switch),
// over the three things you do to the radio (scan, be seen, everything else). In the middle your
// devices, one card each, lit while connected: a click connects or disconnects. On the right what a
// scan finds, with Pair.
//
// Scanning is a switch here, not something the page does by being open: discovery while a headset
// plays can make it stutter. It is held only while the switch is on and released when the page goes.
//
// What this page does not carry (renaming, forgetting, trust, codecs, sending a file, answering a
// pairing question) is the full panel's: `classicRequested` asks the card for it, and the card shows
// it by itself while BlueZ waits on an answer or a file is staged (IslandCard.btClassic).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal classicRequested()

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    readonly property var heroDev: Bt.primary
    readonly property bool heroBattery: root.heroDev !== null && Bt.hasBattery(root.heroDev)

    property bool scanWanted: false
    onScanWantedChanged: root.scanWanted ? Bt.acquireScan() : Bt.releaseScan()
    Component.onDestruction: if (root.scanWanted) Bt.releaseScan()
    // The radio going off ends the scan it was asked for.
    Connections {
        target: Bt
        function onPoweredChanged() { if (!Bt.powered) root.scanWanted = false }
    }

    // What went wrong (or right) since the page opened: a pairing that fails says so nowhere else.
    readonly property double openedAt: Date.now()
    readonly property var lastEvent: {
        const mine = Bt.events.filter(e => e.ms >= root.openedAt)
        return mine.length > 0 ? mine[0] : null
    }

    function isBusy(dev) {
        return dev !== null && (dev.state === BluetoothDeviceState.Connecting
                                || dev.state === BluetoothDeviceState.Disconnecting)
    }
    function caption(dev) {
        const parts = [Bt.stateCaption(dev)]
        if (Bt.hasBattery(dev)) parts.push(Math.round(Bt.batteryLevel(dev) * 100) + "%")
        return parts.join("  ·  ")
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ The radio ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                id: radio
                Layout.fillWidth: true
                Layout.fillHeight: true
                hero: true
                order: 0
                clip: true

                // A big faint shape behind it all; it turns while a scan runs.
                MorphShape {
                    width: radio.height * 0.8
                    height: width
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -width * 0.25
                    anchors.topMargin: -width * 0.22
                    shape: Bt.scanning ? "burst" : Bt.powered ? "hexagon" : "circle"
                    turns: false
                    fillColor: root.palette.alpha(radio.ink, 0.10)
                    NumberAnimation on rotation {
                        from: 0
                        to: 360
                        duration: Motion.spin * 12
                        loops: Animation.Infinite
                        running: Motion.ambientOn && root.visible && Bt.scanning
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXs

                    StyledText {
                        text: Translation.tr("Bluetooth").toUpperCase()
                        variant: "caption"
                        font.weight: Font.Bold
                        font.letterSpacing: 1
                        color: radio.inkDim
                    }
                    IslandBadge {
                        Layout.topMargin: Tokens.spacingSm
                        size: Tokens.iconXl * 2 + Tokens.spacingSm
                        filled: true
                        shape: root.heroDev ? "cookie9" : Bt.powered ? "hexagon" : "circle"
                        glyph: root.heroDev ? Bt.deviceGlyph(root.heroDev) : ""
                        symbol: root.heroDev ? "" : Bt.powered ? "bluetooth" : "bluetooth_disabled"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: Tokens.spacingSm
                        text: !Bt.available ? Translation.tr("No adapter")
                            : !Bt.powered   ? Translation.tr("Radio off")
                            : root.heroDev  ? (root.heroDev.name || root.heroDev.address)
                            :                 Translation.tr("Nothing connected")
                        variant: "headline"
                        font.weight: Font.DemiBold
                        color: radio.ink
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: !Bt.available ? Translation.tr("This machine has no Bluetooth radio")
                            : !Bt.powered   ? Translation.tr("Switch it on to use your devices")
                            : root.heroDev  ? (Bt.connectedCount > 1
                                               ? Translation.tr("Connected  ·  %1 more").arg(Bt.connectedCount - 1)
                                               : Bt.stateCaption(root.heroDev))
                            :                 Translation.tr("%1 paired").arg(Bt.known.length)
                        variant: "caption"
                        color: radio.inkDim
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Item { Layout.fillHeight: true }

                    // The device's battery, the Dashboard's day bar.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.heroBattery
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: "battery_full"
                            fill: 1
                            font.pixelSize: Tokens.iconMd
                            color: radio.inkDim
                        }
                        Meter {
                            Layout.fillWidth: true
                            value: root.heroBattery ? Bt.batteryLevel(root.heroDev) * radio.arrive : 0
                            accent: root.heroBattery && Bt.batteryLevel(root.heroDev) < 0.2 ? root.palette.danger : radio.ink
                        }
                        StyledText {
                            text: root.heroBattery ? Math.round(Bt.batteryLevel(root.heroDev) * 100) + "%" : ""
                            variant: "caption"
                            font.features: ({ tnum: 1 })
                            color: radio.inkDim
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.topMargin: Tokens.spacingXs
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: Bt.powered ? Translation.tr("On") : Translation.tr("Off")
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: radio.ink
                        }
                        Toggle {
                            accessibleName: Translation.tr("Bluetooth")
                            enabled: Bt.available
                            checked: Bt.adapter ? Bt.adapter.enabled : false
                            accent: root.palette.primary
                            onToggled: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
                        }
                    }
                }
            }

            // What you do to the radio.
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: actions.implicitHeight + Tokens.spacingMd * 2
                order: 1

                RowLayout {
                    id: actions
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    ChipButton {
                        Layout.fillWidth: true
                        symbol: "radar"
                        on: root.scanWanted
                        enabled: Bt.powered
                        Accessible.name: root.scanWanted ? Translation.tr("Stop scanning") : Translation.tr("Scan for devices")
                        onActivated: root.scanWanted = !root.scanWanted
                        HoverTip { text: root.scanWanted ? Translation.tr("Stop scanning") : Translation.tr("Scan for devices") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        symbol: Bt.adapter && Bt.adapter.discoverable ? "visibility" : "visibility_off"
                        on: Bt.adapter ? Bt.adapter.discoverable : false
                        enabled: Bt.powered
                        Accessible.name: Translation.tr("Visible to other devices")
                        onActivated: Bt.adapter.discoverable = !Bt.adapter.discoverable
                        HoverTip { text: Translation.tr("Visible to other devices") }
                    }
                    ChipButton {
                        Layout.fillWidth: true
                        symbol: "more_horiz"
                        Accessible.name: Translation.tr("Rename, forget, send a file")
                        onActivated: root.classicRequested()
                        HoverTip { text: Translation.tr("Rename, forget, send a file") }
                    }
                }
            }
        }

        // ══ Your devices ══════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg
                order: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingLg
                    anchors.rightMargin: Tokens.spacingLg
                    spacing: Tokens.spacingSm
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Your devices")
                        variant: "title"
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: Bt.connectedCount > 0
                            ? Translation.tr("%1 of %2 on").arg(Bt.connectedCount).arg(Bt.known.length)
                            : Translation.tr("%1 paired").arg(Bt.known.length)
                        variant: "caption"
                        emphasis: "muted"
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                PanelEmpty {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: Bt.known.length === 0
                    symbol: "bluetooth_searching"
                    title: Translation.tr("No devices yet")
                    text: Bt.powered ? Translation.tr("Scan, then pair one from the right")
                                     : Translation.tr("Switch the radio on first")
                }

                ListView {
                    id: knownList
                    anchors.fill: parent
                    visible: Bt.known.length > 0
                    clip: true
                    spacing: Tokens.spacingSm
                    boundsBehavior: Flickable.StopAtBounds
                    // ScriptModel, not the array: the list re-sorts when a device connects, and an
                    // array model would rebuild every row under the pointer.
                    model: ScriptModel { values: Bt.known }

                    delegate: PanelRow {
                        id: row
                        required property var modelData
                        readonly property var dev: row.modelData ?? null
                        width: knownList.width
                        glyph: Bt.deviceGlyph(row.dev)
                        shape: row.active ? "cookie9" : "circle"
                        title: row.dev ? (row.dev.name || row.dev.address) : ""
                        subtitle: row.dev ? root.caption(row.dev) : ""
                        active: row.dev?.connected ?? false
                        clickable: true
                        // Inert mid-flight: a second click would queue the opposite action.
                        available: Bt.powered && !root.isBusy(row.dev)
                        onActivated: Bt.toggleConnection(row.dev)

                        BusyDot { running: root.isBusy(row.dev) }
                        MaterialIcon {
                            visible: !root.isBusy(row.dev)
                            name: row.active ? "link" : "add_link"
                            font.pixelSize: Tokens.iconMd
                            color: row.inkDim
                        }
                    }
                }
                Scrollbar { flickable: knownList }
            }
        }

        // ══ Nearby ════════════════════════════════════════════════════════════
        IslandPlate {
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.fillHeight: true
            order: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Nearby")
                        variant: "title"
                        font.weight: Font.DemiBold
                    }
                    BusyDot { running: Bt.scanning }
                    StyledText {
                        visible: Bt.nearby.length > 0
                        text: String(Bt.nearby.length)
                        variant: "caption"
                        emphasis: "muted"
                        font.features: ({ tnum: 1 })
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    PanelEmpty {
                        anchors.centerIn: parent
                        width: parent.width
                        visible: Bt.nearby.length === 0
                        quiet: true
                        symbol: "radar"
                        title: Bt.scanning ? Translation.tr("Looking…") : Translation.tr("Not scanning")
                        text: !Bt.powered ? Translation.tr("The radio is off")
                            : Bt.scanning ? Translation.tr("Put the device in pairing mode")
                            :               Translation.tr("Press scan to look for devices")
                    }

                    ListView {
                        id: nearList
                        anchors.fill: parent
                        visible: Bt.nearby.length > 0
                        clip: true
                        spacing: Tokens.spacingXs
                        boundsBehavior: Flickable.StopAtBounds
                        // ScriptModel: Bt.nearby re-sorts on every signal reading while scanning.
                        model: ScriptModel { values: Bt.nearby }

                        delegate: RowLayout {
                            id: near
                            required property var modelData
                            readonly property var dev: near.modelData ?? null
                            readonly property bool pairing: near.dev?.pairing ?? false
                            width: nearList.width
                            spacing: Tokens.spacingSm

                            MaterialIcon {
                                glyph: Bt.deviceGlyph(near.dev)
                                font.pixelSize: Tokens.iconLg
                                color: root.palette.fgMuted
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: near.dev ? (near.dev.name || near.dev.address) : ""
                                variant: "label"
                                elide: Text.ElideRight
                            }
                            ChipButton {
                                symbol: near.pairing ? "close" : "add_link"
                                on: near.pairing
                                Accessible.name: near.pairing ? Translation.tr("Cancel pairing") : Translation.tr("Pair")
                                onActivated: Bt.pair(near.dev)
                                HoverTip { text: near.pairing ? Translation.tr("Cancel pairing") : Translation.tr("Pair") }
                            }
                        }
                    }
                    Scrollbar { flickable: nearList }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.lastEvent !== null
                    text: root.lastEvent ? root.lastEvent.text : ""
                    variant: "caption"
                    color: root.lastEvent && root.lastEvent.kind === "fail" ? root.palette.danger : root.palette.fgMuted
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }
    }
}
