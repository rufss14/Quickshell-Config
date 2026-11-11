pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/bt.js" as B

// ── BluetoothPanel ────────────────────────────────────────────────────────────
// The bar's Bluetooth popup, on the panel recipe:
//
//   [ᛒ] Bluetooth Devices                      [ radar | eye | ⚙ ]  (power)
//   ┌ a question from the pairing agent — confirm this code, type this PIN ┐
//   ┌ a file waiting for a device / files being sent                      ┐
//   [ Devices · 3 | Nearby · 2 ]
//   ┌ hero — the connected device: battery, codec, music/calls, volume, output ┐
//   Connected   ·  other live devices          (tap a row = connect/disconnect)
//   Paired      ·  the rest                    (⋯ = rename, trust, forget)
//
// ── Scanning and pairing live here too ───────────────────────────────────────
// Scanning is a HOLD on Bt that exists only while the Nearby tab is on screen, and
// pairing works for every kind of device now: BtBridge runs a BlueZ agent, and when
// it has a question — "does 482913 match your phone?", "type this PIN" — it opens
// this panel and the question sits on top until it's answered (or BlueZ gives up).
//
// ── The hero is the device you're using ──────────────────────────────────────
// Like the wallpaper panel's hero shows what's on screen, this shows what's
// connected, and for an audio device what you reach for once it IS: volume, "play
// through this", Music vs Calls (the headset's mic), and the codec. The PipeWire
// side is Audio's; this only binds and calls.
//
// ── Sending files ────────────────────────────────────────────────────────────
// Drop a file on the panel, or press Send on a screenshot toast: the file is
// STAGED (BtBridge.staged) and the panel asks which device. Only devices that
// advertise Object Push are offered. Needs bluez-obex; without it the card says so.
//
// ── Everything real is in the services ───────────────────────────────────────
// Bt (devices, pairing order, scan count, feed), BtBridge (agent, RSSI, OBEX),
// Audio (sink, volume, card profiles). The panel shows things and calls functions.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: 535

    // The layout reports its own height; nothing here is hand-summed.
    readonly property int margin: Tokens.spacingXl
    implicitHeight: content.implicitHeight + root.margin * 2

    readonly property color accent: Config.moduleAccent("bluetooth", Colors.of(QsWindow.window).primary)

    // How much of a list shows before it scrolls. A list that grows without limit
    // turns a popup into a full-height column, and PanelHost's ceiling would CLIP it
    // rather than scroll it.
    readonly property int listMaxH: 300

    readonly property bool hasAdapter: Bt.adapter !== null && Bt.adapter !== undefined
    readonly property bool live: root.hasAdapter && Bt.powered

    // ══ Selection ═════════════════════════════════════════════════════════════
    property string view: "devices"          // devices | nearby
    // The address whose row has its actions open — one at a time, so the list
    // never becomes a wall of buttons.
    property string expanded: ""

    // ── Scanning follows the Nearby tab ──────────────────────────────────────
    // Being on the tab IS asking to scan; the header's radar pauses it. Dropped the
    // moment the tab changes or the panel closes (the panel lives behind a Loader,
    // so closing destroys it).
    property bool scanPaused: false
    readonly property bool scanHeld: root.view === "nearby" && !root.scanPaused
    onScanHeldChanged: root.scanHeld ? Bt.acquireScan() : Bt.releaseScan()
    Component.onDestruction: if (root.scanHeld) Bt.releaseScan()

    // Only what happened while this panel was open: the feed is session-long, and a
    // pairing failure from an hour ago isn't news.
    readonly property double openedAt: Date.now()
    readonly property var recentEvents:
        Bt.events.filter(e => e.ms >= root.openedAt).slice(0, 2)

    // ── The hero ──────────────────────────────────────────────────────────────
    readonly property var heroDev: Bt.primary
    readonly property string heroAddress: root.heroDev ? root.heroDev.address : ""
    readonly property var heroSink: root.heroAddress !== "" ? Audio.bluetoothSinkFor(root.heroAddress) : null
    readonly property bool heroIsOutput: root.heroSink !== null && Audio.sink === root.heroSink
    // The card's modes and codecs — only once Audio has read the card for THIS device.
    readonly property var heroCard: Audio.btCard && Audio.btCardAddress === root.heroAddress
                                    ? Audio.btCard : null

    // A profile switch recreates the sink node, so a new node is exactly when the
    // card's state is worth reading again. No polling.
    onHeroAddressChanged: Audio.watchBluetoothCard(root.heroAddress)
    onHeroSinkChanged:    Audio.watchBluetoothCard(root.heroAddress)
    Component.onCompleted: Audio.watchBluetoothCard(root.heroAddress)

    // Everything else, split by state. The hero device isn't repeated below it.
    readonly property var otherConnected: Bt.known.filter(d => d.connected && d !== root.heroDev)
    readonly property var pairedOnly:     Bt.known.filter(d => !d.connected)

    // ── Sending ───────────────────────────────────────────────────────────────
    readonly property string staged: BtBridge.staged
    readonly property string shareBlocker: BtBridge.shareBlocker()
    readonly property var receivers: Bt.known.filter(d => BtBridge.canReceive(d.address))

    function openSettings() {
        // Closing first: the settings window can open over this, and a popup left
        // open underneath is found still there afterwards.
        UiState.closePanel("bluetooth")
        UiState.openSettingsTo("BluetoothPage.qml")
    }

    function nameOf(address) {
        const d = Bt.deviceFor(address)
        return d ? (d.name || d.address) : address
    }

    function batteryText(dev) {
        return Math.round(Bt.batteryLevel(dev) * 100) + "%"
    }
    function batteryTint(dev) {
        return Bt.batteryLevel(dev) < 0.2 ? Colors.of(QsWindow.window).danger : root.accent
    }

    // "482913" → "482 913": two halves are what you compare against a phone's screen.
    function spaced(code) {
        const s = String(code || "")
        return s.length === 6 ? s.slice(0, 3) + " " + s.slice(3) : s
    }

    // ── A group heading inside a list ─────────────────────────────────────────
    component GroupLabel: RowLayout {
        id: gl
        property string text: ""
        property int    count: 0
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.topMargin: Tokens.spacingSm
        spacing: Tokens.spacingSm
        StyledText {
            text: gl.text
            variant: "caption"
            font.weight: Font.DemiBold
            emphasis: "dim"
        }
        StyledText {
            text: gl.count
            variant: "caption"
            emphasis: "dim"
            opacity: 0.6
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Tokens.borderWidth
            color: Colors.of(QsWindow.window).outline
        }
    }

    // ── Signal: four rising bars, hidden while there's no reading ─────────────
    component SignalBars: Item {
        id: sig
        property int bars: -1                 // bt.js signalBars
        visible: sig.bars >= 0
        implicitWidth:  Tokens.spacingSm * 4 + Tokens.spacingXs * 3
        implicitHeight: Tokens.spacingXs * 5
        Row {
            anchors.bottom: parent.bottom
            spacing: Tokens.spacingXs
            Repeater {
                model: 4
                delegate: Rectangle {
                    required property int index
                    anchors.bottom: parent.bottom
                    width:  Tokens.spacingSm
                    height: Tokens.spacingXs * (index + 2)
                    radius: Tokens.spacingXs / 2
                    color: index < sig.bars ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.15)
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }
            }
        }
    }

    // ── An accent-washed card: the hero, the prompt, the send card ────────────
    component WashCard: Rectangle {
        id: wash
        default property alias body: washCol.data
        property color tint: root.accent
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: washCol.implicitHeight + Tokens.spacingLg * 2
        // Tonal, like every panel's hero: the section ground leaning to the tint, no outline.
        radius: Tokens.radiusXl
        color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).section, wash.tint, 0.20)
        ColumnLayout {
            id: washCol
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd
        }
    }

    // ── The big glyph chip ────────────────────────────────────────────────────
    component GlyphChip: Item {
        id: chip
        property string glyph: ""
        property string symbol: ""
        property color  tint: root.accent
        Layout.alignment: Qt.AlignVCenter
        implicitWidth:  Tokens.iconXl + Tokens.spacingXl
        implicitHeight: implicitWidth
        MorphShape {
            anchors.fill: parent
            shape: Config.barShape ? "squircle" : "cookie9"
            fillColor: chip.tint
        }
        MaterialIcon {
            anchors.centerIn: parent
            visible: chip.symbol === ""
            glyph: chip.glyph
            variant: "headline"
            color: Colors.of(QsWindow.window).fgOnPrimary
        }
        MaterialIcon {
            anchors.centerIn: parent
            visible: chip.symbol !== ""
            name: chip.symbol
            fill: 1
            font.pixelSize: Tokens.iconLg
            color: Colors.of(QsWindow.window).fgOnPrimary
        }
    }

    // ── A device you own ──────────────────────────────────────────────────────
    // The row IS the connect/disconnect button — which one applies is never
    // ambiguous. The ⋯ opens the rarer actions under it: rename, trust, forget
    // (armed, since it deletes the pairing key), and the address, which is how you
    // tell two identical controllers apart.
    //
    // `dev` is null-guarded throughout: a delegate the ScriptModel is removing can
    // still evaluate a binding with its modelData already gone.
    component DeviceRow: Surface {
        id: row
        required property var modelData
        readonly property var dev: row.modelData ?? null
        readonly property bool isOn: row.dev?.connected ?? false
        readonly property string address: row.dev?.address ?? ""

        // Mid-flight: connecting or disconnecting. Inert while it lasts, because a
        // second tap would queue the opposite action against a state about to change.
        readonly property bool busy:
               row.dev !== null
            && (row.dev.state === BluetoothDeviceState.Connecting
                || row.dev.state === BluetoothDeviceState.Disconnecting)
        readonly property bool actionable: Bt.powered && !row.busy && row.dev !== null
        readonly property bool open: row.address !== "" && root.expanded === row.address

        Layout.fillWidth: true
        Layout.fillHeight: false
        elevation: Tokens.elevationNested
        castsShadow: false
        cornerRadius: Tokens.radiusCard
        implicitHeight: rowCol.implicitHeight + Tokens.spacingMd * 2

        // Connected is carried by the tile: the tonal ground leans to the accent. Hover adds a lighter
        // lean. No outline, like every panel's rows; the open row keeps one so its actions read as its own.
        color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).section, root.accent,
                       row.isOn ? 0.22 : (rowHover.hovered && row.actionable ? 0.08 : 0))
        borderColor: row.open ? Colors.of(QsWindow.window).alpha(root.accent, 0.45) : "transparent"
        Behavior on color       { ColorAnimation { duration: Motion.standard } }
        Behavior on borderColor { ColorAnimation { duration: Motion.standard } }

        ArmLatch {
            id: forgetLatch
            onConfirmed: {
                root.expanded = ""
                if (row.dev) row.dev.forget()
            }
        }

        HoverHandler {
            id: rowHover
            cursorShape: row.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        }
        // UNDER the content, not a TapHandler over it: the ⋯, the field and the
        // action buttons accept their own clicks, so a tap on them never reaches this.
        MouseArea {
            anchors.fill: parent
            enabled: row.actionable
            onClicked: Bt.toggleConnection(row.dev)
        }

        ColumnLayout {
            id: rowCol
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                MaterialIcon {
                    Layout.leftMargin: Tokens.spacingXs
                    glyph:  Bt.deviceGlyph(row.dev)
                    variant: "body"
                    color: row.isOn ? root.accent : Colors.of(QsWindow.window).fgDim
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: row.dev ? (row.dev.name || row.dev.address) : ""
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: !row.dev ? ""
                            : Bt.stateCaption(row.dev) + (row.dev.trusted ? "" : "  ·  not trusted")
                        variant: "caption"
                        color: row.isOn ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgDim
                        elide: Text.ElideRight
                    }
                }

                // Battery: a short meter and the number — the number is what you
                // read, the meter is what you notice.
                RowLayout {
                    visible: row.dev !== null && Bt.hasBattery(row.dev)
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    Meter {
                        Layout.preferredWidth: Tokens.iconXl
                        implicitHeight: Tokens.spacingXs * 2
                        value:  row.dev ? Bt.batteryLevel(row.dev) : 0
                        accent: row.dev ? root.batteryTint(row.dev) : Colors.of(QsWindow.window).fgDim
                    }
                    StyledText {
                        text: row.dev ? root.batteryText(row.dev) : ""
                        variant: "caption"
                        color: row.dev && Bt.batteryLevel(row.dev) < 0.2 ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                    }
                }

                BusyDot {
                    running: row.busy
                    tint:    root.accent
                }

                PanelButton {
                    variant: row.open ? "primary" : "ghost"
                    accent:  root.accent
                    symbol:  "more_horiz"
                    onActivated: {
                        forgetLatch.disarm()
                        root.expanded = row.open ? "" : row.address
                    }
                }
            }

            // ── The rarer actions ─────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: row.open ? actions.implicitHeight : 0
                visible: Layout.preferredHeight > 0
                clip: true
                Behavior on Layout.preferredHeight {
                    NumberAnimation {
                        duration: Motion.spatial
                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                    }
                }

                ColumnLayout {
                    id: actions
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.top:   parent.top
                    spacing: Tokens.spacingSm

                    // Rename: BlueZ's alias. Committed on Enter or on leaving the
                    // field; empty gives the device its own name back.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        InputField {
                            id: renameField
                            Layout.fillWidth: true
                            // Only built while open, so the seed is the name as of now.
                            seed: row.dev ? row.dev.name : ""
                            placeholder: row.dev ? (row.dev.deviceName || row.dev.address) : ""
                            invalid: false
                            onCommitted: (value) => {
                                if (row.dev && !Bt.rename(row.dev, value)) renameField.invalid = true
                                else renameField.invalid = false
                            }
                        }

                        PanelButton {
                            variant: row.dev && row.dev.trusted ? "primary" : "normal"
                            accent:  root.accent
                            symbol:  "verified_user"
                            symbolFill: row.dev && row.dev.trusted ? 1 : 0
                            label:   Translation.tr("Trusted")
                            onActivated: if (row.dev) row.dev.trusted = !row.dev.trusted
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        StyledText {
                            Layout.fillWidth: true
                            Layout.leftMargin: Tokens.spacingXs
                            text: row.address
                            variant: "caption"
                            emphasis: "dim"
                            font.family: Tokens.fontMono
                            elide: Text.ElideRight
                        }

                        // Unpairs AND deletes the stored key — click once to arm.
                        PanelButton {
                            variant: forgetLatch.armed ? "primary" : "ghost"
                            accent:  Colors.of(QsWindow.window).danger
                            symbol:  "delete"
                            label:   forgetLatch.armed ? "Really forget?" : "Forget"
                            onActivated: forgetLatch.trigger()
                        }
                    }
                }
            }
        }
    }

    // ══ Dropping a file on the panel stages it ═══════════════════════════════
    // Local files only (file://); the scheme is checked before anything else, and
    // the helper checks it's a readable regular file before obexd ever sees it.
    DropArea {
        id: drop
        anchors.fill: parent
        onDropped: (ev) => {
            const u = ev.hasUrls ? String(ev.urls[0]) : ""
            if (!u.startsWith("file:///")) return
            BtBridge.stage(decodeURIComponent(u.slice("file://".length)))
            ev.acceptProposedAction()
        }
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: Tokens.spacingSm
        z: 10
        visible: opacity > 0
        opacity: drop.containsDrag ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).alpha(root.accent, 0.14)
        border.width: Tokens.borderWidth * 2
        border.color: Colors.of(QsWindow.window).alpha(root.accent, 0.6)
        Column {
            anchors.centerIn: parent
            spacing: Tokens.spacingSm
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: "upload_file"
                fill: 1
                font.pixelSize: Tokens.iconXl
                color: root.accent
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Translation.tr("Drop to send over Bluetooth")
                variant: "label"
                color: root.accent
            }
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Anchored top/left/right — NOT fill. The card animates its height around this,
    // and anchoring to fill would re-lay-out the whole column on every frame.
    ColumnLayout {
        id: content
        anchors.top:   parent.top
        anchors.left:  parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingMd

        // ══ Header ════════════════════════════════════════════════════════════
        PanelHeader {
            glyph:     Bt.glyph              // the same adapter glyph the bar pill shows
            title:     Translation.tr("Bluetooth")
            titleTail: root.view === "nearby" ? "Nearby" : "Devices"
            accent:    root.accent

            subtitle: !root.hasAdapter ? "No adapter"
                    : !Bt.powered      ? "Radio off"
                    : root.view === "nearby"
                      ? (Bt.scanning ? "Scanning" : "Scan paused")
                        + "  ·  " + Bt.nearby.length + " found"
                    : (Bt.connectedCount > 0 ? Bt.connectedCount + " connected  ·  " : "")
                        + Bt.known.length + " paired  ·  " + Bt.adapter.adapterId

            ActionGroup {
                groupShown: root.hasAdapter

                // Scan: jumps to Nearby from anywhere; on Nearby it pauses and
                // resumes. Filled while the radio is actually discovering — which
                // may be the settings page's scan, and that's the truth either way.
                PanelButton {
                    variant: Bt.scanning ? "primary" : "ghost"
                    accent:  root.accent
                    symbol:  "radar"
                    enabled: Bt.powered
                    onActivated: {
                        if (root.view !== "nearby") { root.view = "nearby"; root.scanPaused = false }
                        else                          root.scanPaused = !root.scanPaused
                    }
                }
                // Discoverable: whether OTHER devices can find this machine — what
                // you need when pairing is started from the phone's side.
                PanelButton {
                    variant: Bt.adapter && Bt.adapter.discoverable ? "primary" : "ghost"
                    accent:  root.accent
                    symbol:  Bt.adapter && Bt.adapter.discoverable ? "visibility" : "visibility_off"
                    enabled: Bt.powered
                    onActivated: Bt.adapter.discoverable = !Bt.adapter.discoverable
                }
                PanelButton {
                    variant: "ghost"
                    accent:  root.accent
                    symbol:  "settings"
                    onActivated: root.openSettings()
                }
            }

            Toggle {
                Layout.alignment: Qt.AlignVCenter
                accent:  root.accent
                enabled: root.hasAdapter
                checked: Bt.adapter ? Bt.adapter.enabled : false
                // Ask BlueZ and let the reply drive the switch back through the
                // binding. Flipping a local flag optimistically is how a blocked or
                // failed toggle ends up with the UI lying about the radio.
                onToggled: if (Bt.adapter) Bt.adapter.enabled = !Bt.adapter.enabled
            }
        }

        // ══ The pairing agent's question ══════════════════════════════════════
        // On top of everything, on either tab: BlueZ is waiting on it.
        WashCard {
            id: promptCard
            readonly property var p: BtBridge.prompt
            readonly property string kind: promptCard.p ? promptCard.p.kind : ""
            readonly property string who: promptCard.p ? root.nameOf(promptCard.p.address) : ""
            readonly property bool asksCode: promptCard.kind === "pin" || promptCard.kind === "passkey"
            readonly property bool showsCode:
                promptCard.kind === "confirm" || promptCard.kind.startsWith("display-")
            readonly property bool answerable: promptCard.kind !== "" && !promptCard.kind.startsWith("display-")
            visible: promptCard.p !== null
            tint: Colors.of(QsWindow.window).warning

            // A new question clears the last one's typing.
            onPChanged: codeField.clear()

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                GlyphChip {
                    tint: Colors.of(QsWindow.window).warning
                    symbol: promptCard.kind === "service" ? "lock_open" : "link"
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    StyledText {
                        Layout.fillWidth: true
                        text: promptCard.kind === "confirm"   ? "Pair with " + promptCard.who + "?"
                            : promptCard.kind === "authorize" ? promptCard.who + " wants to pair"
                            : promptCard.kind === "service"   ? promptCard.who + " wants " + (promptCard.p?.service ?? "")
                            : promptCard.kind === "pin"       ? "PIN for " + promptCard.who
                            : promptCard.kind === "passkey"   ? "Passkey for " + promptCard.who
                            : "Type this on " + promptCard.who
                        variant: "title"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: promptCard.kind === "confirm"   ? "Check the same number shows on the device."
                            : promptCard.kind === "authorize" ? "It started the pairing itself."
                            : promptCard.kind === "service"   ? "It isn't trusted, so BlueZ is asking first."
                            : promptCard.kind === "pin"       ? "Often 0000 or 1234 — check the device's manual."
                            : promptCard.kind === "passkey"   ? "The six digits the device shows."
                            : promptCard.kind === "display-passkey"
                              ? "Then press Enter on it." + (promptCard.p?.entered > 0
                                    ? "  " + promptCard.p.entered + " of 6 typed" : "")
                            : "Then press Enter on it."
                        variant: "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // The code, big, to compare or copy.
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                visible: promptCard.showsCode
                text: root.spaced(promptCard.kind === "display-pin"
                                  ? (promptCard.p?.pin ?? "") : (promptCard.p?.passkey ?? ""))
                variant: "display"
                font.family: Tokens.fontBlock
                font.letterSpacing: Tokens.spacingXs
                color: Colors.of(QsWindow.window).warning
            }

            InputField {
                id: codeField
                Layout.fillWidth: true
                visible: promptCard.asksCode
                mono: true
                placeholder: promptCard.kind === "pin" ? "PIN" : "6 digits"
                onAccepted: (value) => BtBridge.answer(promptCard.p.id, true, value)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: promptCard.answerable
                spacing: Tokens.spacingSm

                Item { Layout.fillWidth: true }
                PanelButton {
                    variant: "ghost"
                    accent:  Colors.of(QsWindow.window).warning
                    label:   promptCard.kind === "service" ? "Deny" : "Reject"
                    onActivated: BtBridge.answer(promptCard.p.id, false, "")
                }
                // A service request from an untrusted device comes back on every
                // connect; trusting it is what makes the question stop.
                PanelButton {
                    visible: promptCard.kind === "service"
                    variant: "normal"
                    accent:  Colors.of(QsWindow.window).warning
                    label:   Translation.tr("Always allow")
                    onActivated: {
                        const d = Bt.deviceFor(promptCard.p.address)
                        if (d) d.trusted = true
                        BtBridge.answer(promptCard.p.id, true, "")
                    }
                }
                PanelButton {
                    variant: "primary"
                    accent:  Colors.of(QsWindow.window).warning
                    symbol:  "check"
                    label:   promptCard.kind === "service" ? "Allow"
                           : promptCard.kind === "authorize" ? "Accept" : "Pair"
                    enabled: !promptCard.asksCode || codeField.text !== ""
                    onActivated: BtBridge.answer(promptCard.p.id, true, codeField.text)
                }
            }
        }

        // ══ A file waiting for a device ═══════════════════════════════════════
        WashCard {
            id: sendCard
            visible: root.staged !== ""

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg

                GlyphChip { symbol: "upload_file" }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    StyledText {
                        Layout.fillWidth: true
                        text: "Send " + root.staged.split("/").pop()
                        variant: "title"
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.shareBlocker !== "" ? root.shareBlocker
                            : root.receivers.length > 0 ? "Pick a device — it'll ask to accept."
                            : "None of your paired devices accepts files. Pair your phone first."
                        variant: "caption"
                        color: root.shareBlocker !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                        wrapMode: Text.WordWrap
                    }
                }
                PanelButton {
                    variant: "ghost"
                    accent:  root.accent
                    symbol:  "close"
                    onActivated: BtBridge.unstage()
                }
            }

            Flow {
                Layout.fillWidth: true
                visible: root.shareBlocker === "" && root.receivers.length > 0
                spacing: Tokens.spacingSm
                Repeater {
                    model: ScriptModel { values: root.receivers }
                    delegate: PanelButton {
                        required property var modelData
                        variant: "normal"
                        accent:  root.accent
                        glyph:   Bt.deviceGlyph(modelData)
                        label:   modelData ? (modelData.name || modelData.address) : ""
                        onActivated: BtBridge.sendFile(modelData.address, root.staged)
                    }
                }
            }
        }

        // ══ Transfers ═════════════════════════════════════════════════════════
        Repeater {
            model: ScriptModel { values: BtBridge.transfers }

            delegate: RowLayout {
                id: tr
                required property var modelData
                readonly property bool done: tr.modelData.status === "complete"
                readonly property bool failed: tr.modelData.status === "error"
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                MaterialIcon {
                    name: tr.done ? "check_circle" : tr.failed ? "error" : "upload"
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: tr.done ? Colors.of(QsWindow.window).success : tr.failed ? Colors.of(QsWindow.window).danger : root.accent
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs
                    StyledText {
                        Layout.fillWidth: true
                        text: tr.modelData.name + "  →  " + root.nameOf(tr.modelData.address)
                        variant: "caption"
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    Meter {
                        Layout.fillWidth: true
                        visible: !tr.done && !tr.failed
                        implicitHeight: Tokens.spacingXs * 2
                        value: B.transferFraction(tr.modelData)
                        accent: root.accent
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: tr.failed ? tr.modelData.error
                            : tr.done ? "Sent"
                            : tr.modelData.status === "queued" ? "Waiting for the device to accept…"
                            : tr.modelData.status === "connecting" ? "Connecting…"
                            : Math.round(B.transferFraction(tr.modelData) * 100) + "%"
                        variant: "caption"
                        color: tr.failed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                        elide: Text.ElideRight
                    }
                }
                PanelButton {
                    variant: "ghost"
                    accent:  root.accent
                    symbol:  "close"
                    onActivated: (tr.done || tr.failed)
                        ? BtBridge.dismissTransfer(tr.modelData.id)
                        : BtBridge.cancelTransfer(tr.modelData.id)
                }
            }
        }

        // ══ Off / no hardware ═════════════════════════════════════════════════
        // Two different nothings: no adapter is permanent, radio-off is one tap.
        PanelEmpty {
            visible: !root.live
            quiet: true
            symbol: "bluetooth_disabled"
            title: root.hasAdapter ? Translation.tr("Bluetooth is off") : Translation.tr("No Bluetooth adapter")
            text: root.hasAdapter ? Translation.tr("Turn the radio on to see your devices.")
                                  : Translation.tr("This machine has no Bluetooth adapter, or its driver isn't loaded.")
        }
        PanelButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Tokens.spacingMd
            visible: !root.live && root.hasAdapter
            capsule: true
            variant: "primary"
            accent:  root.accent
            symbol:  "power_settings_new"
            label:   Translation.tr("Turn on")
            onActivated: Bt.adapter.enabled = true
        }

        // ══ Devices │ Nearby ═════════════════════════════════════════════════
        SegmentSwitch {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: implicitHeight
            visible: root.live
            accent:  root.accent
            current: root.view
            model: [
                { value: "devices", label: Bt.known.length > 0 ? "Devices  ·  " + Bt.known.length : "Devices",
                  icon: "devices" },
                { value: "nearby",  label: Bt.nearby.length > 0 ? "Nearby  ·  " + Bt.nearby.length : "Nearby",
                  icon: "bluetooth_searching" }
            ]
            onPicked: (value) => { root.view = value; root.scanPaused = false; root.expanded = "" }
        }

        // ══ Views ═════════════════════════════════════════════════════════════
        // Both exist; the one on show sets the height, and a switch crossfades and
        // slides a short way toward its tab's side — the clock panel's move.
        Item {
            id: views
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.live
            Layout.preferredHeight: root.view === "nearby" ? nearbyView.implicitHeight
                                                           : devicesView.implicitHeight

            // ══ DEVICES ═══════════════════════════════════════════════════════
            ColumnLayout {
                id: devicesView
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.top:   parent.top
                spacing: Tokens.spacingSm

                readonly property bool on: root.view === "devices"
                opacity: on ? 1 : 0
                visible: opacity > 0
                enabled: on
                transform: Translate {
                    x: devicesView.on ? 0 : -Tokens.spacingXl
                    Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                // ── Hero — the device you're using ────────────────────────────
                WashCard {
                    id: hero
                    visible: root.heroDev !== null

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingLg

                        GlyphChip { glyph: root.heroDev ? Bt.deviceGlyph(root.heroDev) : "" }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs

                            StyledText {
                                Layout.fillWidth: true
                                text: root.heroDev ? (root.heroDev.name || root.heroDev.address) : ""
                                variant: "title"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            // State, then the audio facts: codec, and whether the
                            // system is playing through it right now.
                            StyledText {
                                Layout.fillWidth: true
                                text: {
                                    if (!root.heroDev) return ""
                                    const parts = [Bt.stateCaption(root.heroDev)]
                                    const codec = Audio.bluetoothCodecOf(root.heroSink)
                                    if (codec !== "") parts.push(codec)
                                    if (root.heroIsOutput) parts.push("Playing here")
                                    return parts.join("  ·  ")
                                }
                                variant: "caption"
                                color: Colors.of(QsWindow.window).success
                                elide: Text.ElideRight
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                visible: root.heroDev !== null && Bt.hasBattery(root.heroDev)
                                spacing: Tokens.spacingSm
                                MaterialIcon {
                                    name: "battery_full"
                                    fill: 1
                                    font.pixelSize: Tokens.iconSm
                                    color: root.heroDev ? root.batteryTint(root.heroDev) : Colors.of(QsWindow.window).fgDim
                                }
                                Meter {
                                    Layout.fillWidth: true
                                    implicitHeight: Tokens.spacingXs * 2
                                    value:  root.heroDev ? Bt.batteryLevel(root.heroDev) : 0
                                    accent: root.heroDev ? root.batteryTint(root.heroDev) : Colors.of(QsWindow.window).fgDim
                                }
                                StyledText {
                                    text: root.heroDev ? root.batteryText(root.heroDev) : ""
                                    variant: "caption"
                                    emphasis: "dim"
                                }
                            }
                        }

                        ActionGroup {
                            // Play through this: only for a device PipeWire has a
                            // sink for. Filled when it's already the output.
                            PanelButton {
                                visible: root.heroSink !== null
                                variant: root.heroIsOutput ? "primary" : "ghost"
                                accent:  root.accent
                                symbol:  "speaker"
                                symbolFill: root.heroIsOutput ? 1 : 0
                                onActivated: Audio.setDefaultSink(root.heroSink)
                            }
                            PanelButton {
                                variant: "ghost"
                                accent:  root.accent
                                symbol:  "link_off"
                                enabled: root.heroDev !== null
                                         && root.heroDev.state === BluetoothDeviceState.Connected
                                onActivated: root.heroDev.disconnect()
                            }
                        }
                    }

                    // ── Its volume ────────────────────────────────────────────
                    // The sink's own level, not the system default's — so it's
                    // right even while something else is the output.
                    RowLayout {
                        id: volRow
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.heroSink !== null && (root.heroSink.audio ?? null) !== null
                        spacing: Tokens.spacingMd

                        readonly property bool muted: root.heroSink?.audio?.muted ?? false
                        readonly property real level: Audio.levelOf(root.heroSink)

                        PanelButton {
                            variant: "ghost"
                            accent:  root.accent
                            symbol:  volRow.muted ? "volume_off" : "volume_up"
                            onActivated: Audio.toggleNodeMute(root.heroSink)
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            value:   volRow.level
                            accent:  volRow.muted ? Colors.of(QsWindow.window).fgDim : root.accent
                            onMoved:    (v) => Audio.setNodeVolume(root.heroSink, v, false)
                            onScrolled: (d) => Audio.setNodeVolume(root.heroSink,
                                              Audio.steppedLevel(volRow.level, d > 0), false)
                        }
                        StyledText {
                            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
                            horizontalAlignment: Text.AlignRight
                            text: volRow.muted ? "muted" : Math.round(volRow.level * 100) + "%"
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }

                    // ── Music or calls, and the codec ─────────────────────────
                    // One card read (Audio.btCard) answers both. Music is A2DP —
                    // full quality, no mic. Calls is HFP — the headset's mic on, at
                    // phone-call quality. Codec chips only when there's a choice.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.heroCard !== null && root.heroCard.music && root.heroCard.calls
                        spacing: Tokens.spacingMd

                        StyledText {
                            Layout.preferredWidth: Tokens.iconXl * 2
                            text: Translation.tr("Mode")
                            variant: "caption"
                            emphasis: "dim"
                        }
                        ChipRow {
                            Layout.fillWidth: true
                            accent:  root.accent
                            current: root.heroCard ? root.heroCard.kind : ""
                            model: [
                                { value: "music", label: "Music",  glyph: "󰎈" },
                                { value: "calls", label: "Calls",  glyph: "󰍬" }
                            ]
                            onPicked: (v) => Audio.setBluetoothMode(v)
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.heroCard !== null && root.heroCard.codecs.length > 1
                        spacing: Tokens.spacingMd

                        StyledText {
                            Layout.preferredWidth: Tokens.iconXl * 2
                            text: Translation.tr("Codec")
                            variant: "caption"
                            emphasis: "dim"
                        }
                        ChipRow {
                            Layout.fillWidth: true
                            accent:  root.accent
                            // The active codec-specific profile; a codec-less "best"
                            // profile lights nothing, and the caption above names
                            // what it picked.
                            current: root.heroCard ? root.heroCard.active : ""
                            model: root.heroCard
                                ? root.heroCard.codecs.map(c => ({ value: c.profile, label: c.label }))
                                : []
                            onPicked: (v) => Audio.setBluetoothCodec(v)
                        }
                    }
                }

                // ── Nothing paired ────────────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.topMargin: Tokens.spacingSm
                    visible: Bt.known.length === 0
                    spacing: Tokens.spacingMd
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Nothing paired yet.")
                        variant: "caption"
                        emphasis: "dim"
                    }
                    PanelButton {
                        variant: "primary"
                        accent:  root.accent
                        symbol:  "bluetooth_searching"
                        label:   Translation.tr("Find devices")
                        onActivated: { root.view = "nearby"; root.scanPaused = false }
                    }
                }

                // ── The rest, grouped ─────────────────────────────────────────
                // A plain Item around the Flickable, not a Layout: Scrollbar
                // reparents itself to flickable.parent and anchors across it.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: root.otherConnected.length + root.pairedOnly.length > 0
                    implicitHeight: Math.min(deviceList.contentHeight, root.listMaxH)

                    Flickable {
                        id: deviceList
                        anchors.fill: parent
                        clip: true
                        contentHeight: deviceCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        ColumnLayout {
                            id: deviceCol
                            width: deviceList.width
                            spacing: Tokens.spacingSm

                            GroupLabel {
                                visible: root.otherConnected.length > 0
                                text: Translation.tr("Connected")
                                count: root.otherConnected.length
                            }
                            // ScriptModel: a connect moves ONE row between groups
                            // instead of rebuilding every row (and its open ⋯ strip).
                            Repeater {
                                model: ScriptModel { values: root.otherConnected }
                                delegate: DeviceRow {}
                            }

                            GroupLabel {
                                visible: root.pairedOnly.length > 0
                                text: Translation.tr("Paired")
                                count: root.pairedOnly.length
                            }
                            Repeater {
                                model: ScriptModel { values: root.pairedOnly }
                                delegate: DeviceRow {}
                            }
                        }
                    }

                    // Sibling of the Flickable, never a child: a Flickable reparents
                    // its children into contentItem, so a scrollbar inside one
                    // scrolls away with what it measures.
                    Scrollbar { flickable: deviceList }
                }
            }

            // ══ NEARBY ════════════════════════════════════════════════════════
            ColumnLayout {
                id: nearbyView
                anchors.left:  parent.left
                anchors.right: parent.right
                anchors.top:   parent.top
                spacing: Tokens.spacingSm

                readonly property bool on: root.view === "nearby"
                opacity: on ? 1 : 0
                visible: opacity > 0
                enabled: on
                transform: Translate {
                    x: nearbyView.on ? 0 : Tokens.spacingXl
                    Behavior on x { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
                }
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                // ── Nothing found ─────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.topMargin: Tokens.spacingLg
                    Layout.bottomMargin: Tokens.spacingSm
                    visible: Bt.nearby.length === 0
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "bluetooth_searching"
                        font.pixelSize: Tokens.iconXl
                        color: Bt.scanning ? root.accent : Colors.of(QsWindow.window).fgDim
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Bt.scanning ? "Looking for devices in pairing mode…"
                                          : "Scan paused — press the radar to resume."
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Bt.nearby.length > 0
                    implicitHeight: Math.min(nearList.contentHeight, root.listMaxH)

                    Flickable {
                        id: nearList
                        anchors.fill: parent
                        clip: true
                        contentHeight: nearCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: contentHeight > height

                        ColumnLayout {
                            id: nearCol
                            width: nearList.width
                            spacing: Tokens.spacingSm

                            // ScriptModel, not the array: Bt.nearby re-sorts on every
                            // RSSI flush while scanning, and an array model would
                            // rebuild every row each time — mid-click on Pair.
                            Repeater {
                                model: ScriptModel { values: Bt.nearby }

                                delegate: Surface {
                                    id: nearRow
                                    required property var modelData
                                    readonly property var dev: nearRow.modelData ?? null
                                    readonly property bool pairing: nearRow.dev?.pairing ?? false

                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    elevation: Tokens.elevationNested
                                    castsShadow: false
                                    cornerRadius: Tokens.radiusPill
                                    implicitHeight: nearBox.implicitHeight + Tokens.spacingMd * 2
                                    borderColor: nearRow.pairing
                                        ? Colors.of(QsWindow.window).alpha(root.accent, 0.45)
                                        : Colors.of(QsWindow.window).outlineFor(nearRow.elevation)
                                    Behavior on borderColor { ColorAnimation { duration: Motion.standard } }

                                    RowLayout {
                                        id: nearBox
                                        anchors.left:  parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: Tokens.spacingMd
                                        spacing: Tokens.spacingMd

                                        MaterialIcon {
                                            Layout.leftMargin: Tokens.spacingXs
                                            glyph: Bt.deviceGlyph(nearRow.dev)
                                            variant: "body"
                                            color: nearRow.pairing ? root.accent : Colors.of(QsWindow.window).fgDim
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: nearRow.dev ? (nearRow.dev.name || nearRow.dev.address) : ""
                                                variant: "caption"
                                                font.weight: Font.DemiBold
                                                // A nameless row is a pairing attempt whose
                                                // name hasn't landed yet — dim until it does.
                                                emphasis: nearRow.dev?.deviceName ? "normal" : "dim"
                                                elide: Text.ElideRight
                                            }
                                            // Connected-but-unpaired is real (a speaker
                                            // that accepted a connection without bonding),
                                            // and it's why a Pair can say "already connected".
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: !nearRow.dev ? ""
                                                    : nearRow.dev.connected ? "Connected, not paired"
                                                    : nearRow.dev.address
                                                variant: "caption"
                                                emphasis: "dim"
                                                font.family: nearRow.dev?.connected ? Tokens.fontFamily : Tokens.fontMono
                                                elide: Text.ElideRight
                                            }
                                        }

                                        SignalBars { bars: nearRow.dev ? BtBridge.barsOf(nearRow.dev.address) : -1 }

                                        BusyDot { running: nearRow.pairing; tint: root.accent }

                                        // Trust → pair → connect, or cancel; the order is Bt's.
                                        PanelButton {
                                            variant: nearRow.pairing ? "ghost" : "normal"
                                            accent:  root.accent
                                            symbol:  nearRow.pairing ? "close" : "add_link"
                                            label:   nearRow.pairing ? "Cancel" : "Pair"
                                            onActivated: Bt.pair(nearRow.dev)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Scrollbar { flickable: nearList }
                }

                // ── What just happened ────────────────────────────────────────
                // Since this panel opened only. A pairing that fails is otherwise
                // silent — the row just stops saying "Pairing…".
                Repeater {
                    model: root.recentEvents

                    delegate: RowLayout {
                        id: ev
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.topMargin: Tokens.spacingXs
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            Layout.alignment: Qt.AlignTop
                            name: ev.modelData.kind === "fail" ? "error"
                                : ev.modelData.kind === "ok"   ? "check_circle" : "info"
                            fill: 1
                            font.pixelSize: Tokens.iconSm
                            color: ev.modelData.kind === "fail" ? Colors.of(QsWindow.window).danger
                                 : ev.modelData.kind === "ok"   ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).fgDim
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            text: ev.modelData.text
                            variant: "caption"
                            emphasis: ev.modelData.kind === "info" ? "dim" : "normal"
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                // Why pairing might not work, or — when it will — how to start one
                // from the other side.
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    Layout.topMargin: Tokens.spacingXs
                    readonly property string blocker: BtBridge.agentBlocker()
                    text: blocker !== ""
                        ? "Pairing agent: " + blocker + ". Devices that need a code won't pair."
                        : "Pairing codes appear here. To pair from your phone, turn on the eye so it can find this machine."
                    variant: "caption"
                    color: blocker !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                    opacity: blocker !== "" ? 1 : 0.7
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
