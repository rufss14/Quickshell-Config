pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../../config"
import "../../../components"

// ── BluetoothPage ─────────────────────────────────────────────────────────────
// Adapters, paired devices, and pairing new ones.
//
// ── This page is a view; Quickshell.Bluetooth does the work ───────────────────
// The native `Bluetooth` singleton tracks BlueZ over D-Bus, event-driven — adapters,
// devices, connection state and battery all update themselves with nothing polling.
// There is deliberately no service wrapper: unlike Audio (which exists to filter the
// PipeWire registry) there is no logic to centralise, and a wrapper would just be a
// second name for the same objects. If a bar module ever wants Bluetooth, the shared
// bits get extracted then.
//
// ── Two adapters, so an adapter picker ────────────────────────────────────────
// This machine has two controllers (a CSR dongle and the Intel AX210), both named
// after the hostname, so `defaultAdapter` alone would silently talk to whichever BlueZ
// prefers. The selection is held as the adapter's DBUS PATH and the adapter DERIVED
// from it — the same file-not-index lesson as the settings rail: there is no assignment
// to break, and if the chosen adapter vanishes (dongle unplugged) the page falls back
// to the default by itself.
//
// ── The honest limit: pairing has no agent ────────────────────────────────────
// Quickshell exposes pair()/cancelPair() but no BlueZ pairing agent, so devices that
// require a passkey confirmation (some keyboards, some phones) cannot complete here —
// they will sit in "pairing" and then fail. Headphones, speakers, mice and most
// gamepads pair without one. Not hidden: worth knowing before blaming the device.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── Adapter selection: derived, never assigned ────────────────────────────
    property string adapterPath: ""            // "" = follow the system default

    readonly property var adapters: Bluetooth.adapters.values
    readonly property var adapter: {
        const list = root.adapters
        if (root.adapterPath !== "")
            for (let i = 0; i < list.length; i++)
                if (list[i].dbusPath === root.adapterPath) return list[i]
        return Bluetooth.defaultAdapter
    }

    readonly property bool powered: root.adapter
        && root.adapter.state === BluetoothAdapterState.Enabled

    // ── Device lists ──────────────────────────────────────────────────────────
    // Reads of dev.paired / dev.connected inside these bindings register as QML
    // dependencies, so a device pairing or connecting re-sorts the lists on its own.
    //
    // "Known" is paired OR bonded rather than paired alone: BlueZ keeps the two flags
    // subtly distinct (bonding is the stored key), and a device with either is one
    // you own, not one to re-pair.
    readonly property var known: {
        const out = []
        if (!root.adapter) return out
        const list = root.adapter.devices.values
        for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (d.paired || d.bonded) out.push(d)
        }
        out.sort((a, b) => (b.connected - a.connected)
                        || (a.name || a.address).localeCompare(b.name || b.address))
        return out
    }

    // Everything in radio range that isn't ours. Devices that never sent a name show
    // as their address and sink to the bottom — a wall of bare MACs above the one
    // device you're actually trying to pair is how scanning UIs become unusable.
    readonly property var nearby: {
        const out = []
        if (!root.adapter) return out
        const list = root.adapter.devices.values
        for (let i = 0; i < list.length; i++) {
            const d = list[i]
            if (!d.paired && !d.bonded) out.push(d)
        }
        out.sort((a, b) => {
            const an = a.name && a.name !== a.address, bn = b.name && b.name !== b.address
            if (an !== bn) return an ? -1 : 1
            return (a.name || a.address).localeCompare(b.name || b.address)
        })
        return out
    }

    readonly property int connectedCount: {
        let n = 0
        for (const d of root.known) if (d.connected) n++
        return n
    }

    // ── Leaving the page stops the scan ───────────────────────────────────────
    // Discovery is the one costly thing here — it keeps the radio actively probing
    // and floods the device list. Same contract as the Sound page's meters: a page
    // nobody is looking at asks the hardware for nothing. Never started automatically
    // either; the Scan button is the user's.
    onVisibleChanged: if (!root.visible && root.adapter) root.adapter.discovering = false
    Component.onDestruction: if (root.adapter) root.adapter.discovering = false

    // ── BlueZ icon names → glyphs ─────────────────────────────────────────────
    // `icon` is a freedesktop icon name ("audio-headset", "input-mouse", …). Substring
    // matches because BlueZ has several variants per family. Every glyph below is
    // cmap-verified against the shipped font, not assumed.
    function deviceGlyph(dev) {
        const i = dev.icon || ""
        if (i.includes("headset") || i.includes("headphone")) return "󰋋"
        if (i.includes("mouse"))    return "󰍽"
        if (i.includes("keyboard")) return "󰌌"
        if (i.includes("phone"))    return "󰄜"
        if (i.includes("gaming") || i.includes("joypad")) return "󰊖"
        if (i.includes("computer")) return "󰌢"
        if (i.includes("watch"))    return "󰖗"
        if (i.includes("display") || i.includes("tv")) return "󰠹"
        if (i.includes("audio"))    return "󰓃"
        return "󰂯"
    }

    function stateCaption(dev) {
        if (dev.pairing) return "Pairing…"
        switch (dev.state) {
        case BluetoothDeviceState.Connecting:    return "Connecting…"
        case BluetoothDeviceState.Disconnecting: return "Disconnecting…"
        case BluetoothDeviceState.Connected:     return "Connected"
        default: return "Paired"
        }
    }

    // `battery` has not been exercised against a real device on this machine (nothing
    // with battery reporting is paired yet), so the scale — 0..1 vs 0..100 — is
    // unverified. Normalising covers both rather than betting on one.
    function batteryLevel(dev) {
        const b = dev.battery
        return Math.max(0, Math.min(1, b > 1 ? b / 100 : b))
    }

    // ── Activity feed ─────────────────────────────────────────────────────────
    // Pairing failures surface ONLY as terminal warnings from Quickshell — a pair
    // attempt that times out leaves the page looking as if nothing happened, which is
    // how "Page Timeout" ended up being discovered in a log instead of on screen. The
    // API carries no error detail into QML, but a pairing that ENDS without the paired
    // flag is detectable, so the feed reports the failure and the likely causes the
    // moment it happens. Connections and disconnections are logged for the same
    // reason: this strip is the page's answer to "did that click do anything".
    property var events: []                  // [{ t, text, kind }] newest first

    function logEvent(text, kind) {
        root.events = [{
            t: Qt.formatTime(new Date(), "HH:mm:ss"),
            text: text,
            kind: kind
        }].concat(root.events).slice(0, 50)
    }

    // One Connections per device on the selected adapter. Instantiator rather than a
    // Repeater because there is nothing visual to parent; switching adapter rebuilds
    // the set, and a device vanishing destroys its watcher with it.
    Instantiator {
        model: root.adapter ? root.adapter.devices : null
        delegate: Connections {
            id: watcher
            required property var modelData
            target: watcher.modelData

            function onPairingChanged() {
                const d = watcher.modelData
                const who = d.name || d.address
                if (d.pairing) {
                    root.logEvent("Pairing with " + who + "…", "info")
                } else if (!d.paired) {
                    // Ended without the flag = failed or cancelled. The phone hint is
                    // the agent limit from the header comment, said where it helps.
                    let msg = "Pairing with " + who
                            + " failed — check it's in pairing mode and in range."
                    if ((d.icon || "").includes("phone"))
                        msg += " Phones also ask for a confirmation this page can't"
                             + " show; try starting the pairing from the phone."
                    root.logEvent(msg, "fail")
                }
            }
            function onPairedChanged() {
                const d = watcher.modelData
                root.logEvent((d.name || d.address)
                    + (d.paired ? " paired" : " unpaired"), d.paired ? "ok" : "info")
            }
            function onConnectedChanged() {
                const d = watcher.modelData
                root.logEvent((d.name || d.address)
                    + (d.connected ? " connected" : " disconnected"),
                    d.connected ? "ok" : "info")
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     root.powered ? (root.connectedCount > 0 ? "󰂱" : "󰂯") : "󰂲"
            title:     "Bluetooth"
            titleTail: root.adapter ? root.adapter.adapterId : ""
            accent:    Colors.focus
            subtitle: !root.adapter
                    ? "No Bluetooth adapter"
                    : !root.powered
                    ? "Bluetooth is off"
                    : root.connectedCount + " connected  ·  "
                      + root.known.length + " paired"
                      + (root.adapter.discovering ? "  ·  scanning" : "")
        }

        Divider {}

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXl
            visible: !root.adapter
            text: "No Bluetooth adapter was found, or BlueZ isn't running."
            variant: "body"
            emphasis: "dim"
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.adapter !== null && root.adapter !== undefined
            spacing: Tokens.spacingXl

            // ══ Adapter ═══════════════════════════════════════════════════════
            ColumnLayout {
                // Even-split idiom: fillWidth distributes the surplus, so equal tiny
                // preferred widths divide the row regardless of content (see SoundPage).
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                StyledText { text: "Adapter"; variant: "label"; emphasis: "muted" }

                // The picker only exists when there is a choice to make.
                Surface {
                    Layout.fillWidth: true
                    visible: root.adapters.length > 1
                    elevation: Tokens.elevationNested
                    implicitHeight: adapterCol.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: adapterCol
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: root.adapters
                            delegate: Rectangle {
                                id: adRow
                                required property var modelData
                                readonly property bool active:
                                    root.adapter && root.adapter.dbusPath === adRow.modelData.dbusPath

                                Layout.fillWidth: true
                                implicitHeight: Tokens.pillHeight + Tokens.spacingSm
                                radius: Tokens.radiusXs
                                color: adRow.active ? Colors.alpha(Colors.focus, 0.16)
                                     : adHover.containsMouse ? Colors.surfaceHigh : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin:  Tokens.spacingSm
                                    anchors.rightMargin: Tokens.spacingSm
                                    spacing: Tokens.spacingSm

                                    StyledText {
                                        text: "󰂯"
                                        variant: "caption"
                                        color: adRow.active ? Colors.focus : Colors.fgDim
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        // Both controllers here carry the hostname as
                                        // their name, so the id is what tells them apart.
                                        text: adRow.modelData.adapterId
                                        variant: "caption"
                                        emphasis: adRow.active ? "normal" : "dim"
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        visible: adRow.active
                                        text: "󰄬"
                                        variant: "caption"
                                        color: Colors.focus
                                    }
                                }

                                MouseArea {
                                    id: adHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.adapterPath = adRow.modelData.dbusPath
                                }
                            }
                        }
                    }
                }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    implicitHeight: togglesCol.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: togglesCol
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingMd

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: "Power"; variant: "caption" }
                                StyledText {
                                    text: root.adapter
                                        ? BluetoothAdapterState.toString(root.adapter.state)
                                        : ""
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                            Toggle {
                                checked: root.adapter ? root.adapter.enabled : false
                                accent: Colors.focus
                                onToggled: if (root.adapter)
                                    root.adapter.enabled = !root.adapter.enabled
                            }
                        }

                        Divider {}

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd
                            // Meaningless on a powered-off radio, so the row says why
                            // it's disabled instead of just being dead.
                            opacity: root.powered ? 1.0 : 0.4

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: "Discoverable"; variant: "caption" }
                                StyledText {
                                    text: "Other devices can find this machine"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                            Toggle {
                                enabled: root.powered
                                checked: root.adapter ? root.adapter.discoverable : false
                                accent: Colors.focus
                                onToggled: if (root.adapter)
                                    root.adapter.discoverable = !root.adapter.discoverable
                            }
                        }

                        Divider {}

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd
                            opacity: root.powered ? 1.0 : 0.4

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText { text: "Accept pairing"; variant: "caption" }
                                StyledText {
                                    text: "Let devices start pairing with this machine"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                            Toggle {
                                enabled: root.powered
                                checked: root.adapter ? root.adapter.pairable : false
                                accent: Colors.focus
                                onToggled: if (root.adapter)
                                    root.adapter.pairable = !root.adapter.pairable
                            }
                        }
                    }
                }
            }

            // ══ My devices ════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                StyledText { text: "My devices"; variant: "label"; emphasis: "muted" }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.known.length === 0
                    text: root.powered
                        ? "Nothing paired yet — scan on the right to add a device."
                        : "Turn Bluetooth on to see your devices."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: root.known
                    delegate: Surface {
                        id: devRow
                        required property var modelData

                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: devBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: devBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingSm

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd

                                StyledText {
                                    text: root.deviceGlyph(devRow.modelData)
                                    variant: "body"
                                    color: devRow.modelData.connected ? Colors.focus : Colors.fgDim
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: devRow.modelData.name || devRow.modelData.address
                                        variant: "caption"
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root.stateCaption(devRow.modelData)
                                            + "  ·  " + devRow.modelData.address
                                        variant: "caption"
                                        emphasis: "dim"
                                        color: devRow.modelData.connected ? Colors.success : Colors.fgDim
                                        elide: Text.ElideRight
                                    }
                                }

                                BusyDot {
                                    running: devRow.modelData.state === BluetoothDeviceState.Connecting
                                          || devRow.modelData.state === BluetoothDeviceState.Disconnecting
                                    tint: Colors.focus
                                }

                                PanelButton {
                                    variant: devRow.modelData.connected ? "ghost" : "normal"
                                    label: devRow.modelData.connected ? "Disconnect" : "Connect"
                                    enabled: root.powered
                                          && devRow.modelData.state !== BluetoothDeviceState.Connecting
                                          && devRow.modelData.state !== BluetoothDeviceState.Disconnecting
                                    onActivated: devRow.modelData.connected
                                        ? devRow.modelData.disconnect()
                                        : devRow.modelData.connect()
                                }

                                // Forget unpairs AND deletes the stored key — the device
                                // must be re-paired to come back, so it's a small ghost
                                // target, not a peer of Connect.
                                PanelButton {
                                    variant: "ghost"
                                    glyph: "󰅖"
                                    onActivated: devRow.modelData.forget()
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                visible: devRow.modelData.batteryAvailable
                                spacing: Tokens.spacingMd

                                StyledText {
                                    text: Math.round(root.batteryLevel(devRow.modelData) * 100) + "%"
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                                Meter {
                                    Layout.fillWidth: true
                                    value: root.batteryLevel(devRow.modelData)
                                    accent: root.batteryLevel(devRow.modelData) < 0.2
                                          ? Colors.danger : Colors.focus
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText { text: "Trusted"; variant: "caption" }
                                    StyledText {
                                        text: "Reconnects without asking"
                                        variant: "caption"
                                        emphasis: "dim"
                                    }
                                }
                                Toggle {
                                    checked: devRow.modelData.trusted
                                    accent: Colors.focus
                                    onToggled: devRow.modelData.trusted = !devRow.modelData.trusted
                                }
                            }
                        }
                    }
                }
            }

            // ══ Nearby ════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.fillHeight: true
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    StyledText { text: "Nearby"; variant: "label"; emphasis: "muted" }
                    BusyDot {
                        running: root.adapter ? root.adapter.discovering : false
                        tint: Colors.focus
                    }
                    Item { Layout.fillWidth: true }

                    PanelButton {
                        variant: root.adapter && root.adapter.discovering ? "primary" : "normal"
                        accent: Colors.focus
                        glyph: "󰐷"
                        label: root.adapter && root.adapter.discovering ? "Stop" : "Scan"
                        enabled: root.powered
                        onActivated: root.adapter.discovering = !root.adapter.discovering
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.nearby.length === 0
                    text: !root.powered
                        ? "Turn Bluetooth on to scan."
                        : root.adapter && root.adapter.discovering
                        ? "Nothing found yet — put the device in pairing mode."
                        : "Scan to look for devices in pairing mode."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                // ── Plain Item around the Flickable ───────────────────────────
                // A scan can surface dozens of addresses; this is the one list on the
                // page that genuinely needs to scroll. Scrollbar reparents itself to
                // flickable.parent and anchors across it, so that parent must not be a
                // Layout (the anchors-in-layout warning, third time this cycle).
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 120

                    Flickable {
                        id: nearbyPane
                        anchors.fill: parent
                        contentHeight: nearbyCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: nearbyCol
                            width: nearbyPane.width
                            spacing: Tokens.spacingSm

                            Repeater {
                                model: root.nearby
                                delegate: Surface {
                                    id: nearRow
                                    required property var modelData

                                    Layout.fillWidth: true
                                    elevation: Tokens.elevationNested
                                    implicitHeight: nearBox.implicitHeight + Tokens.spacingMd * 2

                                    RowLayout {
                                        id: nearBox
                                        anchors.left:  parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin:  Tokens.spacingLg
                                        anchors.rightMargin: Tokens.spacingLg
                                        spacing: Tokens.spacingMd

                                        StyledText {
                                            text: root.deviceGlyph(nearRow.modelData)
                                            variant: "caption"
                                            emphasis: "dim"
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: nearRow.modelData.name || nearRow.modelData.address
                                                variant: "caption"
                                                // A bare address is a device that hasn't
                                                // said who it is; dimmed so named lead.
                                                emphasis: nearRow.modelData.name ? "normal" : "dim"
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                visible: (nearRow.modelData.name || "") !== ""
                                                      && nearRow.modelData.name !== nearRow.modelData.address
                                                text: nearRow.modelData.address
                                                variant: "caption"
                                                emphasis: "dim"
                                            }
                                        }
                                        BusyDot { running: nearRow.modelData.pairing; tint: Colors.focus }

                                        PanelButton {
                                            variant: "ghost"
                                            label: nearRow.modelData.pairing ? "Cancel" : "Pair"
                                            onActivated: {
                                                if (nearRow.modelData.pairing) {
                                                    nearRow.modelData.cancelPair()
                                                } else {
                                                    // Trusted BEFORE pairing, the same order
                                                    // bluetoothctl users are told to use:
                                                    // without it a paired device still asks
                                                    // permission on every reconnect attempt,
                                                    // which reads as "keeps disconnecting".
                                                    nearRow.modelData.trusted = true
                                                    nearRow.modelData.pair()
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Scrollbar { flickable: nearbyPane }
                }
            }
        }

        // ── Activity strip ────────────────────────────────────────────────────
        // The full-width band idiom the other pages use (Network's traffic, Sound's
        // spectrum). See the feed comment up top for why it exists: without it, a failed
        // pairing looks like nothing happened.
        Surface {
            Layout.fillWidth: true
            Layout.preferredHeight: 200
            visible: root.adapter !== null && root.adapter !== undefined
            elevation: Tokens.elevationNested

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    StyledText { text: "Activity"; variant: "label"; emphasis: "muted" }
                    StyledText {
                        Layout.fillWidth: true
                        text: "Pairing and connection events since the page opened"
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                    PanelButton {
                        variant: "ghost"
                        label: "Clear"
                        visible: root.events.length > 0
                        onActivated: root.events = []
                    }
                }

                // Plain Item wrapper — Scrollbar anchors across flickable.parent, which
                // therefore must not be a Layout.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: eventsPane
                        anchors.fill: parent
                        contentHeight: eventsCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: eventsCol
                            width: eventsPane.width
                            spacing: 2

                            StyledText {
                                visible: root.events.length === 0
                                text: "Nothing yet — pair or connect something and it shows up here."
                                variant: "caption"
                                emphasis: "dim"
                            }

                            Repeater {
                                model: root.events
                                delegate: RowLayout {
                                    id: evRow
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Tokens.spacingMd

                                    StyledText {
                                        text: evRow.modelData.t
                                        variant: "caption"
                                        emphasis: "dim"
                                        font.family: Tokens.fontMono
                                    }
                                    StyledText {
                                        text: evRow.modelData.kind === "fail" ? "󰅖"
                                            : evRow.modelData.kind === "ok"   ? "󰄬" : "󰋽"
                                        variant: "caption"
                                        color: evRow.modelData.kind === "fail" ? Colors.danger
                                             : evRow.modelData.kind === "ok"   ? Colors.success
                                             : Colors.fgDim
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: evRow.modelData.text
                                        variant: "caption"
                                        emphasis: evRow.modelData.kind === "info" ? "dim" : "normal"
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }
                        }
                    }
                    Scrollbar { flickable: eventsPane }
                }
            }
        }
    }
}
