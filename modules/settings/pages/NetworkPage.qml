pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../net"

// ── NetworkPage — Devices › Network ───────────────────────────────────────────
// Whatever the machine is connected through: Ethernet, Wi-Fi, or nothing yet — what the
// link is doing, the Wi-Fi radio, a speed test, and DNS.
//
// ── It follows the link (2026-10-26) ──────────────────────────────────────────
// It was "Wi-Fi", with a browser of networks first; on a machine plugged into a wall that
// meant a card saying "Wi-Fi is turned off" and the real connection in a details list
// beside it. Now the card at the top is the CONNECTION, whichever medium carries it: the
// medium's name, whether it is online, its speed, and the live rate each way (a minute of
// it), then its addresses behind their eyes. The Wi-Fi card is separate and only exists
// where there is a radio; with the radio off it says so in one line and offers the switch,
// and with Ethernet carrying the machine it says nothing needs it.
//
// The Traffic view is gone: its signal chart, throughput and per-app list are not what
// anyone opens settings for. The speed test is the one thing worth keeping, and it is
// here. (`NetworkTrafficPage.qml` resolves to this page — SettingsIndex.aliases.)
//
// ── The same browser as the bar's panel ───────────────────────────────────────
// Joining a network should not be a different act depending on where you started it,
// and two copies of that flow would drift.
//
// ── Where the numbers come from ───────────────────────────────────────────────
//   Net        NetworkManager over D-Bus: SSID, security, whether there's a route out.
//   NetStats   /proc and /sys: gateway, interface, MAC, resolv.conf, rates. Refcounted
//              to this page's lifetime.
//   SpeedTest  Cloudflare, on demand only. The one thing here that leaves the machine.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted:   NetStats.acquire()
    Component.onDestruction: NetStats.release()

    // "5 servers" says nothing you'd act on; 2 IPv4 vs 3 IPv6 does, when something
    // won't resolve. Neither number is sensitive, so it shows while addresses are masked.
    function dnsSummary(list) {
        let v4 = 0, v6 = 0
        for (const s of list) {
            if (s.indexOf(":") >= 0) v6++
            else v4++
        }
        const parts = []
        if (v4 > 0) parts.push(v4 + " IPv4")
        if (v6 > 0) parts.push(v6 + " IPv6")
        return parts.length > 0 ? parts.join("  ·  ") : "—"
    }

    // Throughput has no 100%, so it auto-scales AND says so: the peak is printed at the
    // top of each chart. The floor stops an idle link normalising 0/0 into noise.
    function peakOf(series) {
        let m = 0
        for (const v of series) m = Math.max(m, v)
        return Math.max(m, 1024)          // 1 KB/s floor
    }

    // Trailing mean of the last `n` samples — the same figure Sparkline's damping draws
    // at the newest point, so a readout using this agrees with the line beside it.
    function meanTail(series, n) {
        if (!series || series.length === 0) return 0
        let sum = 0, count = 0
        for (let i = Math.max(0, series.length - n); i < series.length; i++) {
            sum += series[i]
            count++
        }
        return count > 0 ? sum / count : 0
    }

    // The SAME scale as the speed meters, so a trace at 60% height belongs to a bar at
    // 60% of its track. The max() stops a fast link clipping before the result lands.
    readonly property real traceCeiling: Math.max(root.peakOf(SpeedTest.liveTrace),
                                                 SpeedTest.meterCeilingBps)
    readonly property int traceH: 34     // speed-test and throughput traces

    // Which medium is carrying the machine. Ethernet wins when both are up, as it does for
    // the route.
    readonly property bool viaWired: Net.wiredConnected
    readonly property bool linked:   Net.wiredConnected || Net.connected
    readonly property string mediumName: root.viaWired ? "Ethernet"
                                       : Net.connected ? Net.ssid
                                       : Net.hasLink   ? "Cable plugged in"
                                                       : "Not connected"

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     root.viaWired ? "󰈀" : Net.glyph()      // wired, or the real signal strength like the bar pill
        title:     Translation.tr("Network")
        titleTail: root.viaWired ? "· Ethernet" : Net.connected ? "· Wi-Fi" : ""
        accent:    Colors.of(QsWindow.window).primary
        subtitle: !root.linked
                    ? (Net.hasWifi ? (Net.wifiBlocked ? "Wi-Fi blocked by hardware"
                                     : !Net.wifiEnabled ? "Wi-Fi is off" : "Not connected")
                                   : "Not connected")
                : Net.online ? (root.viaWired ? "Online via Ethernet" : "Online via " + Net.ssid)
                             : "Connected, but no route to the internet"

        // ══ The connection ════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    root.viaWired ? "󰈀" : Net.glyph()
            title:    root.mediumName
            subtitle: !root.linked ? "Nothing is carrying traffic"
                    : (Net.online ? "Online" : "No internet")
                      + (root.viaWired && Net.wiredSpeedLabel() !== "" ? "  ·  " + Net.wiredSpeedLabel() : "")
                      + (!root.viaWired && Net.connected && Net.isSecured(Net.active) ? "  ·  " + Net.securityLabel(Net.active) : "")
            accent:   !root.linked ? Colors.of(QsWindow.window).fgDim
                    : Net.online ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).warning
            help:     Translation.tr("The connection you're on. Addresses are hidden until you press their eye — handy when screen-sharing.")

            // The live rate, each way: a minute of it, against a stated axis.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: NetStats.iface !== ""

                RateTrace {
                    Layout.fillWidth: true
                    glyph:   "󰇚"
                    label:   NetStats.bytes(NetStats.rxTotal) + " down"
                    history: NetStats.rxHistory
                    tint:    Colors.of(QsWindow.window).primary
                }
                RateTrace {
                    Layout.fillWidth: true
                    glyph:   "󰕒"
                    label:   NetStats.bytes(NetStats.txTotal) + " up"
                    history: NetStats.txHistory
                    tint:    Colors.of(QsWindow.window).info
                }
            }

            // The addresses, two to a row. Hidden by default: an address is the thing you
            // might be screen-sharing; each has its own eye.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 560 ? 2 : 1
                columnSpacing: Tokens.spacingXl
                rowSpacing: Tokens.spacingXs

                InfoRow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    label:  root.viaWired ? "Wired IP" : "Address"
                    value:  (root.viaWired ? Net.wiredAddress : Net.address) === "" ? "—"
                            : (root.viaWired ? Net.wiredAddress : Net.address)
                    secret: true
                }
                InfoRow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    label:  Translation.tr("Gateway")
                    value:  NetStats.gateway === "" ? "—" : NetStats.gateway
                    secret: true
                }
                InfoRow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    label: Translation.tr("Interface")
                    value: NetStats.iface === "" ? "—"
                         : NetStats.mtu > 0      ? NetStats.iface + "  ·  MTU " + NetStats.mtu
                                                 : NetStats.iface
                }
                // Hardware identity — the value that follows you between networks.
                InfoRow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    label:  "MAC"
                    value:  NetStats.mac === "" ? "—" : NetStats.mac
                    secret: true
                }
                // The Wi-Fi address as well, when Ethernet is the one carrying the machine.
                InfoRow {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: root.viaWired && Net.connected
                    label:  Translation.tr("Wi-Fi IP")
                    value:  Net.address === "" ? "—" : Net.address
                    secret: true
                }
            }
        }

        // rfkill is invisible in the panel: the toggle just refuses to move. Knowing
        // it's a function key is the difference between five seconds and a driver hunt.
        Section {
            span:     3
            visible: Net.hasWifi && Net.wifiBlocked
            glyph:    "󰤮"
            title:    Translation.tr("Radio blocked")
            subtitle: Translation.tr("A kill switch or function key holds Wi-Fi off")
            help:     Translation.tr("Hardware wins over NetworkManager: software can't turn it back on. Release the switch or press the function key.")
            accent:     Colors.of(QsWindow.window).warning
            cardBorder: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.45)
        }

        // ══ Wi-Fi ═════════════════════════════════════════════════════════════
        // Only where there is a radio. Off, it is a line and a switch, not an empty list.
        Section {
            span:     1
            visible:  Net.hasWifi
            glyph:    Net.wifiEnabled ? "󰤨" : "󰤮"
            title:    Translation.tr("Wi-Fi")
            subtitle: !Net.wifiEnabled ? "Off"
                    : Net.scanning ? "Scanning…"
                    : Net.networks.length + (Net.networks.length === 1 ? " network in range" : " networks in range")
            help:     Translation.tr("Join, forget, or connect to a hidden network.")
            accent:   Colors.of(QsWindow.window).primary

            actions: [
                BusyDot { running: Net.wifiEnabled && Net.scanning; tint: Colors.of(QsWindow.window).primary },
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Net.wifiEnabled
                    // A hardware kill switch wins over NetworkManager, so the toggle is dead
                    // until it's released — honestly disabled beats appearing to do nothing.
                    enabled: !Net.wifiBlocked
                    onToggled: Net.toggleWifi()
                }
            ]

            NetworkBrowser {
                Layout.fillWidth: true
                visible: Net.wifiEnabled
                maxRows: 5
            }

            // Off: say what that means for THIS machine, and offer the switch.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin: Tokens.spacingSm
                visible: !Net.wifiEnabled
                spacing: Tokens.spacingSm

                MaterialIcon {
                    Layout.alignment: Qt.AlignHCenter
                    name: "wifi_off"
                    variant: "display"
                    color: Colors.of(QsWindow.window).fgDim
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.viaWired ? "You're on Ethernet — nothing needs Wi-Fi"
                                        : "Turn it on to see networks"
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ══ Speed test ════════════════════════════════════════════════════════
        Section {
            span:     1
            glyph:    "󰓅"
            title:    Translation.tr("Speed test")
            subtitle: SpeedTest.running ? "Measuring…" : SpeedTest.downBps > 0 ? "Last run" : "Not run yet"
            help:     Translation.tr("What the link can carry, measured only when you press Run. It contacts a third party and moves real data, so both are named under the trace.")
            accent:   Colors.of(QsWindow.window).primary

            actions: [
                BusyDot { running: SpeedTest.running; tint: Colors.of(QsWindow.window).primary },
                ChipTray {
                    ChipButton {
                        symbol: SpeedTest.running ? "close" : "play_arrow"
                        label:  SpeedTest.running ? "Cancel" : "Run test"
                        on:     !SpeedTest.running
                        tint:   Colors.of(QsWindow.window).primary
                        onActivated: SpeedTest.running ? SpeedTest.cancel() : SpeedTest.start()
                    }
                }
            ]

            SpeedRow {
                Layout.fillWidth: true
                glyph: "󰇚"
                label: Translation.tr("Down")
                bps:   SpeedTest.downBps
                tint:  Colors.of(QsWindow.window).primary
                busy:  SpeedTest.phase === "down"
            }
            SpeedRow {
                Layout.fillWidth: true
                glyph: "󰕒"
                label: Translation.tr("Up")
                bps:   SpeedTest.upBps
                tint:  Colors.of(QsWindow.window).info
                busy:  SpeedTest.phase === "up"
            }

            // The live trace keeps its last shape afterwards, so a finished test still
            // shows whether the link was steady. Reserved height, so nothing jumps.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                ColumnLayout {
                    Layout.preferredHeight: root.traceH
                    spacing: 0
                    opacity: SpeedTest.liveTrace.length > 1 ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                    StyledText { text: NetStats.rate(root.traceCeiling); variant: "micro"; emphasis: "dim" }
                    Item { Layout.fillHeight: true }
                    StyledText { text: "0"; variant: "micro"; emphasis: "dim" }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.traceH

                    Sparkline {
                        anchors.fill: parent
                        capacity: SpeedTest.traceCapacity
                        accent: SpeedTest.phase === "up" ? Colors.of(QsWindow.window).info : Colors.of(QsWindow.window).primary
                        values: SpeedTest.liveTrace.map(v => v / root.traceCeiling)
                        sampleInterval: NetStats.rateInterval
                        gridlines: 1
                        // Lightly damped: the wobble IS the reading here.
                        damping: 2
                        opacity: SpeedTest.liveTrace.length > 1 ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: "Latency " + SpeedTest.ms(SpeedTest.latencyMs)
                        variant: "micro"
                        emphasis: "dim"
                        opacity: SpeedTest.liveTrace.length > 1 ? 0.0 : 1.0
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                    }
                }
            }

            // The only part of the shell that contacts a third party and moves real
            // data — so both facts are on the card, before you press.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: SpeedTest.phase === "error"
                    ? SpeedTest.error
                    : "Single stream via " + SpeedTest.endpoint
                      + "  ·  transfers " + SpeedTest.dataCostLabel
                color: SpeedTest.phase === "error" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                variant: "micro"
                wrapMode: Text.WordWrap
            }
        }

        // ══ DNS ═══════════════════════════════════════════════════════════════
        Section {
            span:     3
            glyph:    "󰇖"
            title:    "DNS"
            // "Automatic" and a preset look identical in resolv.conf, so this is the
            // only thing that says which one you're on.
            subtitle: Dns.activeId === "auto"   ? "From DHCP"
                    : Dns.activeId === "custom" ? "Set by hand"
                                                : Dns.presetFor(Dns.activeId).name
            accent:   Colors.of(QsWindow.window).primary
            help:     Translation.tr("Which resolver answers your lookups. Changing it reconnects the link for a moment.")
            bodySpacing: Tokens.spacingXs

            // Two columns of choices: four one-line options down the full width put
            // each name at the left edge and its address at the right.
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                columns: width >= 640 ? 2 : 1
                columnSpacing: Tokens.spacingMd
                rowSpacing: Tokens.spacingXs

                Repeater {
                    model: Dns.presets

                    DnsChoice {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        preset:   modelData
                        selected: Dns.activeId === modelData.id
                        enabled:  !Dns.busy
                        onPicked: Dns.applyPreset(modelData.id)
                    }
                }

                // Only when the profile matches no preset — a row you can't choose, only
                // arrive at.
                DnsChoice {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible:  Dns.activeId === "custom"
                    preset:   ({ id: "custom", name: "Custom", detail: Dns.configured.join(", ") })
                    selected: true
                    enabled:  false
                }
            }

            // What's resolving right now. The profile is intent, resolv.conf is fact.
            InfoRow {
                Layout.topMargin: Tokens.spacingSm
                label:   Translation.tr("In use")
                value:   NetStats.dns.length === 0 ? "—" : NetStats.dns.join("\n")
                summary: root.dnsSummary(NetStats.dns)
                secret:  true
                wrap:    true
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Dns.busy || Dns.authError || Dns.error !== ""
                spacing: Tokens.spacingSm

                BusyDot { running: Dns.busy; tint: Colors.of(QsWindow.window).primary }

                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    // The auth case names the fix: "not authorised" with no polkit
                    // agent is indistinguishable from a broken button.
                    text: Dns.busy          ? "Reconnecting…"
                        : Dns.authError     ? "Needs a polkit agent — install and start hyprpolkitagent."
                        : Dns.error !== ""  ? Dns.error
                        : "Changing DNS reconnects the link for a moment."
                    color: Dns.error !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgDim
                    variant: "caption"
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // ── RateTrace ─────────────────────────────────────────────────────────────
    // One direction of traffic: glyph, damped current rate, total, and the last minute
    // against a stated axis (peak at the top, 0 at the bottom).
    component RateTrace: RowLayout {
        id: trace

        property string glyph: ""
        property string label: ""
        property var    history: []
        property color  tint: Colors.of(QsWindow.window).primary

        readonly property real peak: root.peakOf(trace.history)

        // The DAMPED rate over the chart's own window, so the number matches the line.
        readonly property real shownRate: root.meanTail(trace.history, 4)

        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        MaterialIcon {
            glyph:  trace.glyph
            color: trace.tint
            variant: "title"
        }

        ColumnLayout {
            Layout.preferredWidth: 96
            Layout.fillHeight: false
            spacing: 0

            StyledText {
                // Unit from the peak, so it holds still while the value moves.
                text: NetStats.rateIn(trace.shownRate, trace.peak)
                variant: "body"
                font.weight: Font.DemiBold
            }
            StyledText {
                text: trace.label
                variant: "micro"
                emphasis: "dim"
            }
        }

        ColumnLayout {
            Layout.preferredHeight: root.traceH
            spacing: 0
            StyledText { text: NetStats.rateIn(trace.peak, trace.peak); variant: "micro"; emphasis: "dim" }
            Item { Layout.fillHeight: true }
            StyledText { text: "0"; variant: "micro"; emphasis: "dim" }
        }

        Sparkline {
            Layout.fillWidth: true
            Layout.preferredHeight: root.traceH
            capacity: NetStats.rateHistoryLength
            accent:   trace.tint
            values:   trace.history.map(v => v / trace.peak)
            sampleInterval: NetStats.rateInterval
            gridlines: 1
            // One second of mean: real traffic arrives in clumps, and raw samples draw a
            // sawtooth that reports "bursty" and nothing else.
            damping: 4
        }
    }

    // ── SpeedRow ──────────────────────────────────────────────────────────────
    // One direction of the speed test. Both share one ceiling, which is what makes the
    // two bars comparable at a glance (see SpeedTest.meterCeilingBps).
    component SpeedRow: RowLayout {
        id: speedRow

        property string glyph: ""
        property string label: ""
        property real   bps:   -1
        property color  tint:  Colors.of(QsWindow.window).primary
        property bool   busy:  false

        // While running: the live interface rate (damped like the trace). After: curl's
        // measurement. Both real — the row never shows a number it made up.
        readonly property real shownBps: speedRow.busy
                                       ? root.meanTail(SpeedTest.liveTrace, 2)
                                       : speedRow.bps

        spacing: Tokens.spacingMd

        MaterialIcon {
            glyph:  speedRow.glyph
            color: speedRow.tint
            variant: "title"
            opacity: speedRow.bps >= 0 || speedRow.busy ? 1.0 : 0.4
        }
        StyledText {
            Layout.preferredWidth: 40
            text: speedRow.label
            variant: "body"
            emphasis: "muted"
        }

        Meter {
            Layout.fillWidth: true
            accent: speedRow.tint
            // An un-run test is an empty track, not a fill pretending to be 0 Mbps.
            value: speedRow.shownBps < 0 ? 0 : Math.min(1, speedRow.shownBps / root.traceCeiling)

            // Chasing a live value uses `track` (never lags the data); settling on the
            // result is eased UI motion.
            Behavior on value {
                NumberAnimation {
                    duration: speedRow.busy ? Motion.track : Motion.emphasized
                    easing.type: speedRow.busy ? Motion.trackCurve : Motion.travel
                }
            }
        }

        StyledText {
            Layout.preferredWidth: 76
            horizontalAlignment: Text.AlignRight
            text: SpeedTest.mbps(speedRow.shownBps)
            variant: "body"
            font.weight: speedRow.bps >= 0 ? Font.DemiBold : Font.Normal
            emphasis: speedRow.shownBps >= 0 ? "normal" : "dim"
        }
    }
    // ── DnsChoice ─────────────────────────────────────────────────────────────
    // One resolver option: radio dot, name, what it is. Radios rather than a dropdown:
    // four options that are the whole point of the card.
    component DnsChoice: Item {
        id: choice

        property var  preset:   null
        property bool selected: false
        signal picked()

        implicitHeight: Math.max(choiceRow.implicitHeight + Tokens.spacingXs * 2, Tokens.pillHeight)
        opacity: choice.enabled ? 1.0 : 0.55

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: choice.selected ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.12)
                 : choiceHover.hovered && choice.enabled ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                                         : "transparent"
            border.width: choice.selected ? Tokens.borderWidth : 0
            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.35)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        RowLayout {
            id: choiceRow
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            MaterialIcon {
                name:  choice.selected ? "check_circle" : "radio_button_unchecked"
                fill:  choice.selected ? 1 : 0
                color: choice.selected ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconMd
            }
            StyledText {
                text: choice.preset ? choice.preset.name : ""
                variant: "body"
                font.weight: choice.selected ? Font.DemiBold : Font.Normal
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignRight
                text: choice.preset ? choice.preset.detail : ""
                variant: "micro"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        HoverHandler { id: choiceHover; enabled: choice.enabled }
        TapHandler {
            enabled: choice.enabled && !choice.selected
            onTapped: choice.picked()
        }
    }

    // ── InfoRow ───────────────────────────────────────────────────────────────
    // Label left, fact right, and — if the fact is sensitive — its own reveal button.
    //
    // Per-row reveal, not one page-wide flag: revealing your IP for someone on a call
    // shouldn't also expose your MAC. Each row re-hides when the page is rebuilt.
    component InfoRow: RowLayout {
        id: infoRow
        property string label: ""
        property string value: ""
        property color  tint:  Colors.of(QsWindow.window).fg
        property bool   wrap:  false

        // A status lamp beside the value.
        property bool   dot:   false

        property bool   secret:   false
        property bool   revealed: false

        // Shown in place of the dots while masked, when the SHAPE of the secret is worth
        // knowing (see dnsSummary).
        property string summary:  ""

        readonly property bool hasValue: infoRow.value !== "" && infoRow.value !== "—"
        readonly property bool masked:   infoRow.secret && !infoRow.revealed && infoRow.hasValue

        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd

        StyledText {
            Layout.preferredWidth: 90
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            text:     infoRow.label
            variant:  "body"
            emphasis: "muted"
        }
        Rectangle {
            visible: infoRow.dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  7
            implicitHeight: 7
            radius: width / 2
            color:  infoRow.tint
        }
        StyledText {
            Layout.fillWidth: true
            // Alignment must NOT depend on `masked`, or the text jumps vertically when a
            // wrapping row grows on reveal.
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            text:     infoRow.masked ? (infoRow.summary !== "" ? infoRow.summary : "••••••••••")
                                     : infoRow.value
            color:    infoRow.masked ? Colors.of(QsWindow.window).fgDim : infoRow.tint
            variant:  "body"
            // Masked is always one line — row height mustn't leak how many nameservers.
            wrapMode: infoRow.wrap && !infoRow.masked ? Text.WordWrap : Text.NoWrap
            elide:    infoRow.wrap && !infoRow.masked ? Text.ElideNone : Text.ElideRight
        }
        // ── The eye's slot is ALWAYS here ─────────────────────────────────────
        // `visible: false` on a Layout item REMOVES it from the layout, so a row with an
        // eye reserved space its neighbours didn't and values jumped sideways when an
        // address arrived. An always-present Item with the button hiding INSIDE it keeps
        // the geometry constant.
        Item {
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            Layout.preferredWidth:  22
            Layout.preferredHeight: 22

            PanelButton {
                capsule: true
                anchors.fill: parent
                variant:   "ghost"
                visible:   infoRow.secret && infoRow.hasValue
                glyph:     infoRow.revealed ? "󰈈" : "󰈉"      // eye / eye-off
                glyphTint: infoRow.revealed ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                onActivated: infoRow.revealed = !infoRow.revealed
            }
        }
    }
}
