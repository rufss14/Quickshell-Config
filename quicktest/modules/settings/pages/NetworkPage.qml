pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../net"

// ── NetworkPage ───────────────────────────────────────────────────────────────
// Wi-Fi, with room to explain itself.
//
// ── What this has that the bar's panel doesn't ────────────────────────────────
// The same NetworkBrowser is in both, deliberately — joining a network should not be
// a different act depending on where you started it, and two copies of that flow
// would drift. What differs is the context around it, which a popup has no room for
// and no business holding open: the signal's history, what the link is carrying, and
// the addressing facts.
//
// ── Where the numbers come from ───────────────────────────────────────────────
// Two sources, because neither is sufficient:
//   Net       NetworkManager over D-Bus. Knows the SSID, the security, whether
//             there's a route out. Does NOT know dBm, bytes, gateway or DNS —
//             `WifiNetwork` exposes `signalStrength` and `security`, and that's all.
//   NetStats  /proc and /sys, via FileView. The kernel's own numbers.
//
//   SpeedTest Cloudflare, on demand only. The one thing here that leaves the machine.
//
// ── The shape of the page, and who it's for ───────────────────────────────────
// Three columns under a full-width header, divided by hairlines:
//
//     ┌───────────────┬───────────────┬───────────────┐
//     │  Networks     │  Signal       │  Advanced     │
//     │  (the list)   │  Speed test   │    charts     │
//     │               │  Details      │    addressing │
//     │               │               │    DNS        │
//     └───────────────┴───────────────┴───────────────┘
//
// Do | Know | Dig. Everything is on screen at once; nothing scrolls.
//
// ── The measurement this is built on, and the one it replaced ─────────────────
// The page is 1510 × 952. That is NOT what earlier versions of this file assumed —
// they said 750px wide, taken from SettingsCard's `implicitWidth: 980` minus the
// rail. That property is a FALLBACK whose own comment says "in practice these never
// apply": the overview anchors the card to fill the screen, so the real card is
// 1768 × 984 and the page inside it is 1510 × 952.
//
// So every "it's too stretched" fix here was aimed at half the real width, which is
// exactly why they kept not working. Three columns at ~490 each is what the actual
// geometry wants; two at ~750 was still a wall of half-empty rows.
//
// If you change SettingsCard's size or the overview's `edge`, re-derive this:
//   card  = screen - edge - (edge + 40 + spacingXl)   ×   screen - 2·edge
//   page  = card - 2·spacingXl - railWidth(210) - spacingXl
//
// Then a floor: the FIRST column you read must be readable by someone who does not
// know what dBm is. That rules out leading with a scaled logarithmic axis, however
// good the chart is. So the technical material — the dBm history, the throughput
// traces, gateway, DNS, interface, MAC — is the last column rather than the first.
// Nothing was deleted to make the page friendlier; it was ordered.
//
// That column used to be a collapsed Disclosure. It isn't any more: once the whole
// page fits on screen, a collapse toggle is a control whose only effect is to leave a
// hole. Ordering does the work a disclosure was doing.
//
// ── What is deliberately NOT here ─────────────────────────────────────────────
// Frequency band and link speed. Both need nl80211: `iw` isn't installed, sysfs
// `speed` returns EINVAL on wireless, and Quickshell puts `linkSpeed` on WiredDevice
// only. They'd be a subprocess and a guess, so they're absent rather than invented.
// Same for noise/SNR — this hardware reports the -256 "unsupported" sentinel.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Sampling runs only while this page is on screen. The page is destroyed when the
    // settings card is (see SettingsCard's Loader), so its lifetime is the signal.
    Component.onCompleted:   { NetStats.acquire(); NetApps.acquire() }
    Component.onDestruction: { NetStats.release(); NetApps.release() }

    // REMOVED: `property bool ipBlurred` — the page-wide mask flag. Each InfoRow now
    // owns its own reveal state (see InfoRow below). Note NetworkBrowser has a property
    // of the SAME NAME that is unrelated and still live: it drives the bar's Wi-Fi
    // popup eye, and this page never bound to it.

    // ── dBm onto the sparkline's 0..1 ─────────────────────────────────────────
    // This axis follows the window, and both ends are printed beside the chart.
    //
    // It used to be pinned at -90..-30, the real usable band, on the reasoning that a
    // fixed axis means the same thing every time you look at it. That reasoning is
    // sound and it produced a useless chart: a stationary laptop's signal moves about
    // 1dB, which on a 60dB axis is 1.7% of the height — a straight line, every time.
    // The honest axis was measuring a range this machine never visits.
    //
    // But a bare min/max auto-scale is the exact lie Sparkline's docstring warns about
    // — it would blow that same 1dB of noise up to full height and draw a mountain
    // range. So the span has a FLOOR: the axis can zoom in, but only to `levelSpanMin`,
    // and below that the line is allowed to look as flat as it really is.
    //
    // What keeps this honest is the labels, not the maths. The numbers at the ends of
    // the axis are the whole difference between "relative shape, ceiling stated" and
    // "unlabelled line that rescales behind your back".
    readonly property real levelSpanMin: 10       // dB — the tightest zoom allowed

    // { lo, hi } in dBm. Recomputed per sample; the history is 60 values, so this is a
    // 60-element scan once a second — cheaper than the binding that reads it.
    readonly property var levelWindow: {
        const h = NetStats.levelHistory
        if (h.length === 0) return { lo: -90, hi: -30 }

        let lo = h[0], hi = h[0]
        for (const v of h) { lo = Math.min(lo, v); hi = Math.max(hi, v) }

        if (hi - lo < root.levelSpanMin) {
            const mid = (hi + lo) / 2
            lo = mid - root.levelSpanMin / 2
            hi = mid + root.levelSpanMin / 2
        }
        return { lo: Math.round(lo), hi: Math.round(hi) }
    }

    function levelNorm(dbm) {
        const w = root.levelWindow
        return Math.max(0, Math.min(1, (dbm - w.lo) / (w.hi - w.lo)))
    }

    // ── Throughput's ceiling is a genuine problem ─────────────────────────────
    // Sparkline's fixed-axis rule assumes a BOUNDED quantity — 40% of a CPU is 40% of
    // the height because 100% exists. Bytes per second has no 100%. A fixed ceiling
    // would draw all ordinary browsing as a flat line on the floor, and auto-scaling
    // silently is exactly the lie the component warns about.
    //
    // So it auto-scales AND says so: the peak is printed next to the chart. A relative
    // shape with its ceiling stated is how every real network monitor draws this, and
    // the thing that makes it honest is the label, not the maths.
    //
    // The floor stops an idle link (all zeros) from normalising 0/0 into noise.
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

    // ── DNS, summarised ───────────────────────────────────────────────────────
    // "5 servers" is true but says nothing you'd act on. This box resolves against 2
    // IPv4 and 3 IPv6 nameservers, and THAT distinction is the one that matters when
    // something won't resolve — so the summary counts them by family rather than just
    // counting. Neither number is sensitive, so it shows while the addresses stay
    // masked.
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

    // ── The live trace's ceiling ──────────────────────────────────────────────
    // Deliberately the SAME scale as the speed meters, so a trace sitting at 60% of
    // the chart height belongs to a bar sitting at 60% of its track. Two views of one
    // measurement that disagreed about scale would be worse than one view.
    //
    // The max() is what stops it clipping mid-test: until a result exists the meter
    // ceiling is only the 100 Mbps default, and a 306 Mbps link would flatten itself
    // against the top of the chart for the whole run. Once the test finishes the
    // ladder rung is the larger of the two, and the trace snaps into agreement with
    // the bars.
    readonly property real traceCeiling: Math.max(root.peakOf(SpeedTest.liveTrace),
                                                 SpeedTest.meterCeilingBps)

    // ── The foot-of-page traffic monitor ──────────────────────────────────────
    // One combined activity trace (down + up summed), because that's what the wide
    // strip is for: "is anything happening, and how much of it", not the per-direction
    // detail the Advanced column already answers with its own axes. The two histories
    // are appended on the same tick, so index i lines up; Math.min guards the one frame
    // where one has landed and the other hasn't.
    readonly property var trafficSeries: {
        const rx = NetStats.rxHistory, tx = NetStats.txHistory
        const n = Math.min(rx.length, tx.length)
        const out = []
        for (let i = 0; i < n; i++) out.push(rx[i] + tx[i])
        return out
    }

    // ── The scale, matched to the line that's actually drawn ──────────────────
    // NOT peakOf(trafficSeries). The strip's Sparkline draws a 4-sample MEAN of this
    // data (damping: 4), so the line's real maximum is the biggest damped value, not the
    // biggest raw one. Scaling against the raw peak — a single 250ms burst to 394 KB/s
    // over an otherwise idle minute — pinned the whole line flat to the floor: its own
    // top sat at maybe a quarter height, and the idle chatter that IS the shape when
    // nothing's downloading vanished into the bottom edge. That's the "is that a graph?"
    // render.
    //
    // Taking the peak of the SAME damped series means the drawn line reaches the top of
    // the box, and a lone needle can't flatten everything behind it — it gets averaged
    // down like every other point. The window is the damping window, kept in sync by
    // hand with the Sparkline below (there's no way to read it back out).
    //
    // 2, not 4: the Advanced throughput chart averages a full second (4 × 250ms) for a
    // clean shape, but this monitor is meant to feel live, and a 1s mean lags real
    // traffic by up to a second — the line ambles where the link darts. Half a second
    // still kills the raw 250ms sawtooth but reacts about twice as fast.
    readonly property int trafficDamping: 2
    readonly property real trafficPeak: {
        const s = root.trafficSeries
        const w = root.trafficDamping
        let mx = 0
        for (let i = 0; i < s.length; i++) {
            let sum = 0, n = 0
            for (let k = Math.max(0, i - w + 1); k <= i; k++) { sum += s[k]; n++ }
            if (n > 0) mx = Math.max(mx, sum / n)
        }
        return Math.max(mx, 1024)      // 1 KB/s floor — see peakOf
    }

    // ── The apps list, capped ─────────────────────────────────────────────────
    // A tall list would fight the strip's height; the top few by connection count are
    // the ones actually moving traffic, and the rest collapse into a "+N more" line.
    readonly property int appsShown: 6
    readonly property var topApps: NetApps.apps.slice(0, root.appsShown)
    readonly property int appsMore: Math.max(0, NetApps.apps.length - root.appsShown)

    // ── An app's icon, from its process name ──────────────────────────────────
    // Icons.pathForAppId already does the hard part — Papirus, then the .desktop
    // "Icon=", then the alias table, probing each with `check: true` so a miss returns
    // "" rather than a broken-image texture. Nothing here reimplements any of that.
    //
    // What it DOES do is bridge the one mismatch: `ss` reports the BINARY name, and an
    // appId is not a binary name. Lowercasing plus dropping a "-bin"/".exe" suffix turns
    // `zen-bin` into `zen`, which the alias table then maps to `zen-browser`, and
    // `Discord` into `discord`. Deliberately no per-app entries added here — that table
    // is documented as manual maintenance and kept short on purpose.
    //
    // "" is a normal answer, not a failure: CLI programs like `claude`, and quickshell
    // itself, have no desktop entry, and the row falls back to a glyph.
    function appIconFor(procName) {
        if (!procName) return ""
        const id = procName.toLowerCase().replace(/-bin$/, "").replace(/\.exe$/, "")
        return Icons.pathForAppId(id)
    }

    Flickable {

        id: pageFlick
        anchors.fill: parent
        clip: true
        // Grows to the content, but never shorter than the viewport — that floor is what
        // lets the traffic strip's fillHeight claim the empty band under the columns
        // instead of the page just ending where the tallest column does.
        contentHeight: Math.max(page.implicitHeight, height)
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: page
            width: pageFlick.width
            // Match the Flickable's own floor: the layout has to actually BE viewport-tall
            // for a fillHeight child to have anything to fill. Left at implicitHeight it
            // would shrink back to the columns and the strip would collapse to its minimum.
            height: Math.max(implicitHeight, pageFlick.height)
            spacing: Tokens.spacingLg

            PanelHeader {
                glyph:     Net.glyph()      // real signal strength, same glyph as the bar pill
                title:     "Wi-Fi"
                titleTail: "& Network"
                accent:    Colors.focus

                subtitle: Net.wifiBlocked  ? "Blocked by hardware"
                        : !Net.wifiEnabled ? "Radio disabled"
                        : Net.connected    ? "Connected to " + Net.ssid
                        : Net.scanning     ? "Scanning…"
                        : Net.networks.length + " network"
                          + (Net.networks.length !== 1 ? "s" : "") + " found"

                BusyDot {
                    Layout.alignment: Qt.AlignVCenter
                    running: Net.wifiEnabled && Net.scanning
                }

                Toggle {
                    Layout.alignment: Qt.AlignVCenter
                    checked: Net.wifiEnabled
                    // A hardware kill switch wins over anything NetworkManager will
                    // accept, so the toggle is dead until it's released — better an
                    // honestly disabled control than one that appears to do nothing.
                    enabled: !Net.wifiBlocked
                    onToggled: Net.toggleWifi()
                }
            }

            Divider {}

            // ── Hardware kill switch ──────────────────────────────────────────
            // rfkill is invisible in the panel: the toggle just refuses to move. It's
            // usually a laptop function key or a physical switch, and knowing that is
            // the difference between a five-second fix and reinstalling a driver.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: blockedRow.implicitHeight + Tokens.spacingLg * 2
                visible: Net.wifiBlocked
                radius: Tokens.radiusSm + 2
                color:        Colors.alpha(Colors.warning, 0.10)
                border.color: Colors.alpha(Colors.warning, 0.28)
                border.width: Tokens.borderWidth

                RowLayout {
                    id: blockedRow
                    anchors.left:  parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingMd

                    StyledText { text: "󰤮"; color: Colors.warning; variant: "title" }
                    StyledText {
                        Layout.fillWidth: true
                        text: "The Wi-Fi radio is blocked in hardware — a kill switch or "
                            + "function key. Software can't turn it back on."
                        variant: "caption"
                        wrapMode: Text.WordWrap
                        opacity: 0.85
                    }
                }
            }

            // ══ The three columns ═════════════════════════════════════════════
            // The stretch was never a property of the cards, it's a property of the
            // column they're in — so the column is what splits. Two attempts missed
            // this: pairing cards inside a full-width column (which left the page one
            // column), then splitting into two (which was right in kind but sized
            // against a width half the real one — see the header).
            //
            // Do | Know | Dig, left to right. That ordering is why Networks owns a
            // column rather than being the first card in a stack.
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingXl

                // ── Left: the networks ────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    // preferredWidth 1 on every column is the even-split idiom:
                    // fillWidth distributes the SURPLUS, so equal (tiny) preferred
                    // widths divide the row evenly regardless of what the content would
                    // rather be.
                    //
                    // Measured, because "it'll be fine" is how this goes wrong quietly:
                    // in a 750px row two such columns come out 359 / 358. Delete the
                    // preferredWidth lines and the same row measures 597 / 120 — the
                    // network list's implicit width eats everything and the "split"
                    // isn't one. Don't remove them because they look redundant.
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingMd

                    StyledText { text: "Networks"; variant: "label"; emphasis: "muted" }

                    // The same browser the bar's panel shows, with more room to breathe
                    // — the popup is a glance, this is where you came to actually look.
                    NetworkBrowser {
                        Layout.fillWidth: true
                        maxRows: 8
                    }
                }

                // The spine. A hairline rather than a gap: the gap alone reads as three
                // things that happen to be near each other, the line reads as one page
                // with three panes. fillHeight is set by the component, so it matches
                // whichever column is tallest.
                Divider { orientation: Qt.Vertical }

                // ── Middle: what the link is doing ────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingMd

                    StyledText {
                        text: "Signal"
                        variant: "label"
                        emphasis: "muted"
                        visible: signalCard.visible
                    }

                    // The friendly face of the same radio the chart in Advanced plots.
                    // Bars and a word first; the numbers are a footnote.
                    Surface {
                        id: signalCard
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: signalBox.implicitHeight + Tokens.spacingLg * 2
                        // Nothing to show without an associated link. A dead readout
                        // reads as broken; absent reads as "not connected", which the
                        // header already says.
                        visible: Net.connected && NetStats.hasLevel

                        RowLayout {
                            id: signalBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            // The same glyph the bar pill shows, at size. One picture of
                            // signal strength across the shell — a second visual language
                            // for "how many bars" would be a thing to learn twice.
                            StyledText {
                                text:  Net.glyph()
                                color: Colors.focus
                                variant: "display"
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: NetStats.quality(NetStats.level)
                                    variant: "title"
                                    elide: Text.ElideRight
                                }
                                // Both numbers, small and together. The percentage is
                                // NetworkManager's normalisation of the same radio the
                                // dBm comes from — kept side by side rather than one
                                // instead of the other, because two figures for one
                                // signal need to be reconcilable when you go looking.
                                StyledText {
                                    Layout.fillWidth: true
                                    text: NetStats.level + " dBm"
                                        + (Net.strength >= 0 ? "  ·  " + Net.strength + "%" : "")
                                    variant: "caption"
                                    emphasis: "dim"
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Speed test"
                        variant: "label"
                        emphasis: "muted"
                    }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: speedBox.implicitHeight + Tokens.spacingLg * 2

                        ColumnLayout {
                            id: speedBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            SpeedRow {
                                Layout.fillWidth: true
                                glyph: "󰇚"
                                label: "Down"
                                bps:   SpeedTest.downBps
                                tint:  Colors.focus
                                busy:  SpeedTest.phase === "down"
                            }

                            SpeedRow {
                                Layout.fillWidth: true
                                glyph: "󰕒"
                                label: "Up"
                                bps:   SpeedTest.upBps
                                tint:  Colors.info
                                busy:  SpeedTest.phase === "up"
                            }

                            // ── The live trace ────────────────────────────────
                            // Only while a transfer is running, and it keeps its last
                            // shape afterwards so the finished test still shows whether
                            // the link was steady or spiky. Reserved height, not a
                            // collapsing row: appearing would shove the button down
                            // mid-press.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                // Same vertical scale as every other chart here. Shown
                                // only once there's a trace to scale — labelling an
                                // empty box is furniture pretending to be information.
                                ColumnLayout {
                                    Layout.preferredHeight: 34
                                    spacing: 0
                                    opacity: SpeedTest.liveTrace.length > 1 ? 1.0 : 0.0
                                    Behavior on opacity {
                                        NumberAnimation { duration: Motion.fast }
                                    }

                                    StyledText {
                                        text: NetStats.rate(root.traceCeiling)
                                        variant: "micro"
                                        emphasis: "dim"
                                    }
                                    Item { Layout.fillHeight: true }
                                    StyledText { text: "0"; variant: "micro"; emphasis: "dim" }
                                }

                                Item {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34

                                    Sparkline {
                                        anchors.fill: parent
                                        capacity: SpeedTest.traceCapacity
                                        accent: SpeedTest.phase === "up" ? Colors.info
                                                                         : Colors.focus
                                        values: SpeedTest.liveTrace.map(
                                                    v => v / root.traceCeiling)
                                        sampleInterval: NetStats.rateInterval
                                        gridlines: 1
                                        // Lightly damped — half the throughput chart's
                                        // window. This trace exists to show whether the
                                        // link holds steady under load, so the wobble IS
                                        // the reading and must survive; 2 samples only
                                        // takes the 250ms stairstep off it.
                                        damping: 2
                                        opacity: SpeedTest.liveTrace.length > 1 ? 1.0 : 0.0
                                        Behavior on opacity {
                                            NumberAnimation { duration: Motion.fast }
                                        }
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        text: "Press Run to measure the link"
                                        variant: "micro"
                                        emphasis: "dim"
                                        opacity: SpeedTest.liveTrace.length > 1 ? 0.0 : 1.0
                                        Behavior on opacity {
                                            NumberAnimation { duration: Motion.fast }
                                        }
                                    }
                                }
                            }

                            Divider {}

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingMd

                                StyledText {
                                    text: "Latency"
                                    variant: "body"
                                    emphasis: "muted"
                                }
                                StyledText {
                                    text: SpeedTest.ms(SpeedTest.latencyMs)
                                    variant: "body"
                                    font.weight: Font.DemiBold
                                }

                                Item { Layout.fillWidth: true }

                                BusyDot { running: SpeedTest.running }

                                PanelButton {
                                    variant: SpeedTest.running ? "normal" : "primary"
                                    label:   SpeedTest.running ? "Cancel" : "Run test"
                                    onActivated: SpeedTest.running ? SpeedTest.cancel()
                                                                   : SpeedTest.start()
                                }
                            }

                            // ── Saying where the traffic goes ─────────────────
                            // This is the only part of the shell that contacts a third
                            // party, and it moves real data to do it. Both facts sit on
                            // the face of the card rather than in a source comment — a
                            // button that quietly ships your IP somewhere and eats a
                            // tether's allowance is one you should be able to decline
                            // before pressing, not after.
                            StyledText {
                                Layout.fillWidth: true
                                text: SpeedTest.phase === "error"
                                    ? SpeedTest.error
                                    : "Single-stream via " + SpeedTest.endpoint
                                      + "  ·  transfers " + SpeedTest.dataCostLabel
                                      + (SpeedTest.hasResult
                                         ? "  ·  bars to " + SpeedTest.meterCeilingLabel : "")
                                color: SpeedTest.phase === "error" ? Colors.warning : Colors.fgDim
                                variant: "micro"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }

                    StyledText {
                        Layout.topMargin: Tokens.spacingSm
                        text: "Details"
                        variant: "label"
                        emphasis: "muted"
                    }

                    Surface {
                        Layout.fillWidth: true
                        elevation: Tokens.elevationNested
                        implicitHeight: connBox.implicitHeight + Tokens.spacingLg * 2

                        // Back to a single column, with its dividers restored. The
                        // two-up grid here was a workaround for a 750px card; at half
                        // that width a label/value pair is about as wide as its own
                        // content, which is what the grid was faking. And in one column
                        // a hairline reads as "next field" again rather than cutting
                        // between grid cells.
                        ColumnLayout {
                            id: connBox
                            anchors.left:  parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: Tokens.spacingLg
                            spacing: Tokens.spacingMd

                            // Connected and online are NOT the same claim, and this is
                            // the row that exists to say so. `online` is NetworkManager's
                            // own connectivity check, so "no internet" here is a fact,
                            // not a guess. It leads the card because it's the one row
                            // that can tell you something is wrong.
                            InfoRow {
                                label: "Status"
                                value: !Net.connected ? "Not connected"
                                     : Net.online     ? "Online"
                                                      : "Connected, no internet"
                                tint: !Net.connected ? Colors.fgDim
                                    : Net.online     ? Colors.success
                                                     : Colors.warning
                                dot: true
                            }

                            Divider {}

                            InfoRow {
                                label: "Network"
                                value: Net.connected ? Net.ssid : "—"
                            }

                            Divider {}

                            InfoRow {
                                label: "Security"
                                value: !Net.connected ? "—"
                                     : Net.isSecured(Net.active) ? Net.securityLabel(Net.active)
                                                                 : "Open"
                                tint: Net.connected && !Net.isSecured(Net.active)
                                      ? Colors.warning : Colors.fg
                            }

                            Divider {}

                            // Hidden by default: an address is the one thing on this
                            // page you might be screen-sharing when you open it.
                            InfoRow {
                                label:  "Address"
                                value:  Net.address === "" ? "—" : Net.address
                                secret: true
                            }
                        }
                    }
                }

                // ── Right: Advanced ───────────────────────────────────────────
                // Everything that needs you to already know what it means, DNS changer
                // included — it's the one control here that assumes you know what a
                // resolver is, so it belongs with the dBm and the MTU rather than beside
                // the friendly bars.
                Divider { orientation: Qt.Vertical }

                // ── Not a Disclosure any more ─────────────────────────────────
                // It was one so the page could open approachable and keep the dBm out of
                // your face — but the COLUMN already does that job. "Advanced" is a
                // place now, third of three, and you read past it or you don't. A
                // collapse toggle on a column that always fits on screen was a control
                // whose only function was to leave a hole where the column had been.
                //
                // The cost, stated plainly: content is no longer lazily built, so both
                // charts bind and repaint from the moment the page opens. That laziness
                // was the Disclosure's real value. It's affordable here because the page
                // is destroyed when you leave it (SettingsCard's Loader) and NetStats is
                // refcounted to that lifetime — nothing samples for a page you're not
                // looking at, which was always the expensive half.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    spacing: Tokens.spacingMd

                    StyledText { text: "Advanced"; variant: "label"; emphasis: "muted" }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingLg

                        // Stacked, not two-up. They sat side by side while Advanced was
                        // full width; it's now one column of the page's own split, so
                        // pairing them inside it would be a split inside a split — two
                        // ~170px charts, which is not a chart. The two still read against
                        // each other, just vertically: same 60s window, aligned x-axes,
                        // so a throughput dip and a signal dip still line up.
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingLg

                            // ── Signal history ────────────────────────────────
                            Surface {
                                Layout.fillWidth: true
                                elevation: Tokens.elevationNested
                                implicitHeight: histBox.implicitHeight + Tokens.spacingLg * 2
                                visible: Net.connected && NetStats.hasLevel

                                ColumnLayout {
                                    id: histBox
                                    anchors.left:  parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.spacingLg
                                    spacing: Tokens.spacingMd

                                    StyledText {
                                        text: "Signal history"
                                        variant: "caption"
                                        emphasis: "muted"
                                    }

                                    // The axis, stated — read vertically, beside the line
                                    // it scales. The two numbers used to sit at opposite
                                    // ends of a horizontal row, which read as "it went
                                    // from -55 to -57 over the last minute" rather than
                                    // as a y-axis. Stacked against the chart's edges,
                                    // they can only mean the top and the bottom.
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Tokens.spacingSm

                                        ColumnLayout {
                                            Layout.preferredHeight: 52
                                            spacing: 0

                                            StyledText {
                                                text: root.levelWindow.hi + " dBm"
                                                variant: "micro"
                                                emphasis: "dim"
                                            }
                                            Item { Layout.fillHeight: true }
                                            StyledText {
                                                text: root.levelWindow.lo + " dBm"
                                                variant: "micro"
                                                emphasis: "dim"
                                            }
                                        }

                                        Sparkline {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 52
                                            capacity: NetStats.levelHistoryLength
                                            values: NetStats.levelHistory.map(
                                                        v => root.levelNorm(v))
                                            // The chart this glide was built for: one
                                            // sample a second across 60 slots is a ~5px
                                            // lurch, by far the most visible stepping on
                                            // the page.
                                            sampleInterval: NetStats.levelInterval
                                            gridlines: 1
                                            // NOT damped. The signal barely moves as it
                                            // is — this axis is already zoomed to a 10dB
                                            // window to make 1dB visible at all, and
                                            // averaging would erase the very changes the
                                            // zoom exists to show.
                                        }
                                    }

                                    StyledText {
                                        Layout.alignment: Qt.AlignRight
                                        text: "last " + NetStats.levelHistoryLength + "s"
                                        variant: "micro"
                                        emphasis: "dim"
                                    }
                                }
                            }

                            // ── Throughput ────────────────────────────────────
                            // What the link is carrying right now, as opposed to what
                            // the speed test says it could. Different question, so a
                            // different card — but the same minute, which is why it sits
                            // directly under the signal on a shared x-axis.
                            Surface {
                                Layout.fillWidth: true
                                elevation: Tokens.elevationNested
                                implicitHeight: rateBox.implicitHeight + Tokens.spacingLg * 2
                                visible: NetStats.iface !== ""

                                ColumnLayout {
                                    id: rateBox
                                    anchors.left:  parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Tokens.spacingLg
                                    spacing: Tokens.spacingMd

                                    StyledText {
                                        text: "Throughput"
                                        variant: "caption"
                                        emphasis: "muted"
                                    }

                                    RateTrace {
                                        Layout.fillWidth: true
                                        glyph:   "󰇚"
                                        label:   "Down"
                                        rate:    NetStats.rxRate
                                        history: NetStats.rxHistory
                                        tint:    Colors.focus
                                    }

                                    Divider {}

                                    RateTrace {
                                        Layout.fillWidth: true
                                        glyph:   "󰕒"
                                        label:   "Up"
                                        rate:    NetStats.txRate
                                        history: NetStats.txHistory
                                        tint:    Colors.info
                                    }
                                }
                            }
                        }

                        // ── Addressing ────────────────────────────────────────
                        Surface {
                            Layout.fillWidth: true
                            elevation: Tokens.elevationNested
                            implicitHeight: advBox.implicitHeight + Tokens.spacingLg * 2

                            // One column again — Advanced now occupies half the page, so
                            // the two-up grid that fixed the 750px card would just be
                            // two cramped 150px cells.
                            //
                            // DNS is NOT here any more: it moved to its own card on the
                            // right, where it can be changed rather than only read.
                            ColumnLayout {
                                id: advBox
                                anchors.left:  parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.spacingLg
                                spacing: Tokens.spacingMd

                                InfoRow {
                                    label:  "Gateway"
                                    value:  NetStats.gateway === "" ? "—" : NetStats.gateway
                                    secret: true
                                }

                                Divider {}

                                // The interface name and MTU aren't secrets — they say
                                // nothing about you that a screenshot of this page
                                // doesn't already say. No eye (but the slot is still
                                // reserved, so the values stay aligned with the rows
                                // that have one).
                                InfoRow {
                                    label: "Interface"
                                    value: NetStats.iface === "" ? "—"
                                         : NetStats.mtu > 0      ? NetStats.iface
                                                                 + "  ·  MTU " + NetStats.mtu
                                                                 : NetStats.iface
                                }

                                Divider {}

                                // The MAC is hardware identity — the one value here that
                                // follows you between networks, so it hides too.
                                InfoRow {
                                    label:  "MAC"
                                    value:  NetStats.mac === "" ? "—" : NetStats.mac
                                    secret: true
                                }
                            }
                        }

                        // ── DNS ───────────────────────────────────────────────
                        // Inside Advanced, not beside it. It's the one control on this
                        // page that assumes you know what a resolver is — the same bar
                        // the dBm axis and the MTU had to clear.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText { text: "DNS"; variant: "label"; emphasis: "muted" }
                            Item { Layout.fillWidth: true }
                            // Where the CURRENT servers come from. "Automatic" and a
                            // preset look identical in resolv.conf, so this is the only
                            // thing on the card that says which one you're actually on.
                            StyledText {
                                text: Dns.activeId === "auto"   ? "from DHCP"
                                    : Dns.activeId === "custom" ? "custom"
                                                                : Dns.presetFor(Dns.activeId).name
                                variant: "micro"
                                emphasis: "dim"
                            }
                        }

                        Surface {
                            Layout.fillWidth: true
                            elevation: Tokens.elevationNested
                            implicitHeight: dnsBox.implicitHeight + Tokens.spacingLg * 2

                            ColumnLayout {
                                id: dnsBox
                                anchors.left:  parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.spacingLg
                                spacing: Tokens.spacingSm

                            Repeater {
                                model: Dns.presets

                                DnsChoice {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    preset:   modelData
                                    selected: Dns.activeId === modelData.id
                                    enabled:  !Dns.busy
                                    onPicked: Dns.applyPreset(modelData.id)
                                }
                            }

                            // Shown only when the profile matches no preset — a row you
                            // can't choose, only arrive at (someone set servers by hand,
                            // or set IPv4 without IPv6).
                            DnsChoice {
                                Layout.fillWidth: true
                                visible:  Dns.activeId === "custom"
                                preset:   ({ id: "custom", name: "Custom",
                                             detail: Dns.configured.join(", ") })
                                selected: true
                                enabled:  false
                            }

                            Divider {}

                            // What's actually resolving right now, whatever the profile
                            // says. These are the values from resolv.conf — the profile
                            // is intent, this is fact, and they disagree between an
                            // apply and a reconnect.
                            InfoRow {
                                Layout.alignment: Qt.AlignTop
                                label:   "In use"
                                value:   NetStats.dns.length === 0 ? "—"
                                                                   : NetStats.dns.join("\n")
                                summary: root.dnsSummary(NetStats.dns)
                                secret:  true
                                wrap:    true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                BusyDot { running: Dns.busy }

                                StyledText {
                                    Layout.fillWidth: true
                                    // Three states, three different things to say. The
                                    // auth one names the actual fix, because "not
                                    // authorised" on a machine with no polkit agent is
                                    // indistinguishable from a broken button.
                                    text: Dns.busy      ? "Reconnecting…"
                                        : Dns.authError ? "Needs a polkit agent — install "
                                                        + "and start hyprpolkitagent."
                                        : Dns.error !== "" ? Dns.error
                                        : "Changing DNS reconnects the link for a moment."
                                    color: Dns.error !== "" ? Colors.warning : Colors.fgDim
                                    variant: "micro"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                    }
                }
            }

            Divider {}

            // ══ Traffic ═══════════════════════════════════════════════════════
            // The full-width foot of the page: what the link has carried since it came
            // up, and whether anything's flowing right now. It's the reason the page
            // fills its height instead of ending where the tallest column does — the
            // three columns stay compact at the top and this claims the band beneath.
            //
            // Why a wide strip works where tall columns didn't: a throughput trace
            // auto-scales to its own peak (see Sparkline), so it uses the full height
            // whether the link is busy or idle — the signal chart can't, it's pinned to
            // a real dBm band and sits flat. A tall, wide box is exactly what this chart
            // wants and exactly what that one didn't. Combined down+up here, one trace:
            // the per-direction detail is the Advanced column's job, this is the glance.
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                visible: NetStats.iface !== ""

                StyledText { text: "Traffic"; variant: "label"; emphasis: "muted" }
                Item { Layout.fillWidth: true }
                StyledText {
                    text: "peak " + NetStats.rate(root.trafficPeak)
                    variant: "micro"
                    emphasis: "dim"
                }
            }

            Surface {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // A floor tall enough that the trace reads as a graph even on a screen
                // where fillHeight has little slack to hand it — the first cut sat at
                // 128 and, when the columns nearly filled the viewport, that left a
                // sliver you could barely see. On a roomy screen fillHeight takes it well
                // past this.
                Layout.minimumHeight: 172
                elevation: Tokens.elevationNested
                visible: NetStats.iface !== ""

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingLg
                    spacing: Tokens.spacingXl

                    // ── Session totals ────────────────────────────────────────
                    // On the left, under the short Networks column — the numbers fill the
                    // space that list left empty. The graph is the headline and belongs
                    // where the page's other charts already are (the right), so these read
                    // as its caption rather than sitting in front of it.
                    ColumnLayout {
                        // fillWidth: false is LOAD-BEARING, not redundant. A Layout nested
                        // in another Layout defaults fillWidth to TRUE, so without this the
                        // column ignores preferredWidth, swells to ~1400px, and leaves the
                        // graph a 6px sliver on the right with a dead gap in the middle —
                        // measured, that was the "graph doesn't extend" bug. Pinned false,
                        // it holds 190 and the graph takes the rest.
                        Layout.fillWidth: false
                        Layout.preferredWidth: 190
                        Layout.fillHeight: true
                        spacing: Tokens.spacingMd

                        StyledText {
                            text: "This session"
                            variant: "caption"
                            emphasis: "muted"
                        }

                        TrafficTotal {
                            glyph: "󰇚"
                            label: "Downloaded"
                            total: NetStats.rxTotal
                            tint:  Colors.focus
                        }
                        TrafficTotal {
                            glyph: "󰕒"
                            label: "Uploaded"
                            total: NetStats.txTotal
                            tint:  Colors.info
                        }

                        Item { Layout.fillHeight: true }

                        StyledText {
                            Layout.fillWidth: true
                            // Honest about the window: the kernel counts from the link
                            // coming up, not from when this page opened. On a box that's
                            // been up for days that's a days-long total, which is the more
                            // useful number anyway.
                            text: "Counted since the connection came up."
                            variant: "micro"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }

                    Divider { orientation: Qt.Vertical }

                    // ── The live activity trace ───────────────────────────────
                    // The wide half, on the right, where it has room to actually be a
                    // graph. fillWidth + fillHeight so it takes everything the totals
                    // column and the strip's height don't.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Sparkline {
                            anchors.fill: parent
                            capacity: NetStats.rateHistoryLength
                            accent:   Colors.focus
                            values:   root.trafficSeries.map(v => v / root.trafficPeak)
                            sampleInterval: NetStats.rateInterval
                            gridlines: 3
                            // A half-second mean (2 × 250ms) — lighter than the Advanced
                            // throughput chart's second, so this reads as live rather than
                            // smoothed, while still taking the raw 250ms sawtooth off.
                            // MUST match root.trafficDamping — the scale above is the peak
                            // of this same damped series, so if they drift the line stops
                            // reaching the top.
                            damping: root.trafficDamping
                        }

                        StyledText {
                            anchors.centerIn: parent
                            text: "Waiting for traffic…"
                            variant: "micro"
                            emphasis: "dim"
                            visible: root.trafficSeries.length <= 1
                        }
                    }

                    Divider { orientation: Qt.Vertical }

                    // ── Active apps ───────────────────────────────────────────
                    // The sources of that traffic: which apps are on the network and what
                    // each is moving, busiest first. Real bandwidth, from the TCP_INFO byte
                    // counters `ss -i` exposes without root — see NetApps, including why
                    // this is a live rate rather than a per-app session total.
                    //
                    // fillWidth:false for the same reason the totals column carries it: a
                    // nested Layout defaults it true and would swallow the graph.
                    ColumnLayout {
                        Layout.fillWidth: false
                        Layout.preferredWidth: 220
                        Layout.fillHeight: true
                        spacing: Tokens.spacingSm

                        StyledText {
                            text: "Active apps"
                            variant: "caption"
                            emphasis: "muted"
                        }

                        Repeater {
                            model: root.topApps

                            RowLayout {
                                id: appRow
                                required property var modelData
                                readonly property string iconPath:
                                    root.appIconFor(appRow.modelData.name)

                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                // A permanently reserved 16px cell, exactly like InfoRow's
                                // eye: an icon that resolves for some apps and not others
                                // must not shift the names beside it into two different
                                // left edges. The glyph stands in when there's no icon.
                                Item {
                                    Layout.preferredWidth:  16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter

                                    Image {
                                        anchors.fill: parent
                                        source:  appRow.iconPath
                                        visible: appRow.iconPath !== ""
                                        sourceSize.width:  16
                                        sourceSize.height: 16
                                        fillMode: Image.PreserveAspectFit
                                        smooth: true
                                        // Untinted — these are the apps' own marks.
                                    }
                                    StyledText {
                                        anchors.centerIn: parent
                                        visible: appRow.iconPath === ""
                                        text:  "󰛳"              // md-network, cmap-verified
                                        color: Colors.focus
                                        variant: "micro"
                                        opacity: 0.7
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    text: appRow.modelData.name
                                    variant: "body"
                                    elide: Text.ElideRight
                                }

                                // Down + up combined, right now. A rate rather than a
                                // session total on purpose — see NetApps: a total would be
                                // read as a share of the session figure on the left, and it
                                // can never be one.
                                //
                                // An idle app reads "0 B/s" and dims. That's honest: it
                                // holds connections but moved nothing this sample.
                                StyledText {
                                    readonly property real total: appRow.modelData.rxRate
                                                                + appRow.modelData.txRate
                                    text: NetStats.rate(total)
                                    variant: "micro"
                                    emphasis: total > 0 ? "normal" : "dim"
                                }
                            }
                        }

                        StyledText {
                            visible: root.appsMore > 0
                            text: "+" + root.appsMore + " more"
                            variant: "micro"
                            emphasis: "dim"
                        }

                        StyledText {
                            visible: NetApps.apps.length === 0
                            text: "No active connections"
                            variant: "micro"
                            emphasis: "dim"
                        }

                        Item { Layout.fillHeight: true }

                        // The one caveat worth surfacing: QUIC has no per-socket counters,
                        // so a QUIC-heavy app under-reports here. Kept short — a live rate
                        // makes no claim to be a share of the session figure, so this only
                        // has to scope what's measured, not explain a mismatch.
                        StyledText {
                            Layout.fillWidth: true
                            text: "Live rate, TCP only."
                            variant: "micro"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }
        }
    }


    // The page scrolls on a small screen; on this one it doesn't, and the bar

    // hides itself when the content fits (see Scrollbar.scrollable). Declared as

    // a SIBLING of the Flickable, never a child — a Flickable reparents its

    // children into contentItem, so a scrollbar inside one scrolls away.

    Scrollbar { flickable: pageFlick }

    // ── DnsChoice ─────────────────────────────────────────────────────────────
    // One resolver option: a radio dot, a name, and what it is.
    //
    // Radio rather than a dropdown because there are four of them and they're the whole
    // point of the card — a dropdown would hide three-quarters of the content to save a
    // row of space this column has going spare.
    component DnsChoice: Item {
        id: choice

        property var  preset:   null
        property bool selected: false
        signal picked()

        implicitHeight: Math.max(choiceRow.implicitHeight + Tokens.spacingSm * 2,
                                 Tokens.pillHeight)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: choice.selected ? Colors.alpha(Colors.focus, 0.12)
                 : choiceHover.hovered && choice.enabled ? Colors.alpha(Colors.fg, 0.06)
                                                         : "transparent"
            border.width: choice.selected ? Tokens.borderWidth : 0
            border.color: Colors.alpha(Colors.focus, 0.35)
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

            StyledText {
                text:  choice.selected ? "󰄲" : "󰄱"      // checked / unchecked circle
                color: choice.selected ? Colors.focus : Colors.fgDim
                variant: "body"
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
        opacity: choice.enabled ? 1.0 : 0.55
    }

    // ── RateTrace ─────────────────────────────────────────────────────────────
    // One direction of traffic: glyph, current rate, and the shape of the last minute
    // against a stated axis.
    //
    // The axis used to be one "peak 1.2 MB/s" caption off to the right, which named the
    // ceiling without showing where it was. Now the peak sits at the top of the chart
    // and 0 at the bottom, with a gridline at the halfway mark — the same vertical
    // treatment as the signal chart above it, so both read the same way round.
    component RateTrace: RowLayout {
        id: trace

        property string glyph: ""
        property string label: ""
        property real   rate:  0
        property var    history: []
        property color  tint: Colors.focus

        readonly property real peak: root.peakOf(trace.history)

        // ── The number matches the line ───────────────────────────────────────
        // The readout shows the DAMPED rate, not the raw 250ms sample, over the same
        // window the chart is damped by. Two reasons, and the second is the important
        // one:
        //   · Raw, the digits redraw 4× a second over an idle swing measured at
        //     316 B/s → 5.4 KB/s. That's a flicker, not a reading.
        //   · The chart beside it is already a 4-sample mean. A readout showing the
        //     instantaneous value would sit at a number the line next to it does not
        //     pass through, and you'd have no way to tell which was lying.
        readonly property real shownRate: root.meanTail(trace.history, 4)

        spacing: Tokens.spacingMd

        StyledText {
            text:  trace.glyph
            color: trace.tint
            variant: "title"
        }

        ColumnLayout {
            Layout.preferredWidth: 86
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

        // The scale, read vertically against the chart's edges.
        ColumnLayout {
            Layout.preferredHeight: 34
            spacing: 0

            StyledText {
                text: NetStats.rateIn(trace.peak, trace.peak)
                variant: "micro"
                emphasis: "dim"
            }
            Item { Layout.fillHeight: true }
            StyledText {
                text: "0"
                variant: "micro"
                emphasis: "dim"
            }
        }

        Sparkline {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            capacity: NetStats.rateHistoryLength
            accent:   trace.tint
            values:   trace.history.map(v => v / trace.peak)
            sampleInterval: NetStats.rateInterval
            gridlines: 1
            // Damped, and this is the chart the damping was added for: real traffic
            // arrives in clumps, so raw 250ms samples draw a sawtooth that reports
            // "bursty" and nothing else. Four samples is one second of mean — enough to
            // let the shape through, short enough that a real transfer still shows up
            // as a step rather than a slow ramp.
            damping: 4
        }
    }

    // ── TrafficTotal ────────────────────────────────────────────────────────
    // A cumulative counter in the traffic strip: glyph, the byte total big, the
    // direction small. The number is the point here — unlike a rate, it doesn't move
    // every frame — so it gets the weight and the label is the footnote.
    component TrafficTotal: RowLayout {
        id: tt

        property string glyph: ""
        property string label: ""
        property real   total: 0
        property color  tint:  Colors.focus

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        StyledText {
            text:  tt.glyph
            color: tt.tint
            variant: "title"
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: NetStats.bytes(tt.total)
                variant: "title"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledText {
                text: tt.label
                variant: "micro"
                emphasis: "dim"
            }
        }
    }

    // ── SpeedRow ──────────────────────────────────────────────────────────────
    // One direction of the speed test: what it measured, and how that looks against
    // the shared ceiling. Both directions use the SAME ceiling — that's what makes the
    // two bars comparable at a glance, which is most of why they're bars at all. See
    // SpeedTest.meterCeilingBps for how the ceiling is chosen and why it isn't fixed.
    component SpeedRow: RowLayout {
        id: speedRow

        property string glyph: ""
        property string label: ""
        property real   bps:   -1
        property color  tint:  Colors.focus
        property bool   busy:  false

        spacing: Tokens.spacingMd

        StyledText {
            text:  speedRow.glyph
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

        // While this direction is running, the row shows the live interface rate; once
        // curl reports, it shows the measurement. Both are real — the live figure is
        // what the NIC is doing this instant, the final one is curl's average over the
        // transfer — so the row never displays a number it made up, and never sits at
        // zero for four seconds pretending nothing is happening.
        //
        // The live figure is DAMPED over the same 2-sample window as the trace beside
        // it, for the same reason the throughput readout is: raw, it's a 250ms sample
        // and both the bar and the digits twitch four times a second.
        readonly property real shownBps: speedRow.busy
                                       ? root.meanTail(SpeedTest.liveTrace, 2)
                                       : speedRow.bps

        Meter {
            Layout.fillWidth: true
            accent: speedRow.tint
            // An un-run test is an empty track, not a zero-length fill pretending to be
            // a result of 0 Mbps.
            value: speedRow.shownBps < 0 ? 0
                 : Math.min(1, speedRow.shownBps / root.traceCeiling)

            // ── Two different animations, because these are two different jobs ────
            // Settling on the final result is UI motion: a discrete change, eased,
            // scaled by the user's preference like everything else.
            //
            // Following the live rate is NOT. It's a bar chasing a live value, which is
            // exactly the case Motion.track exists for and explicitly names ("a
            // spectrum bar following audio"). It gets track's near-instant 60ms: enough
            // to take the 250ms stairstep off the bar, far too short to lag behind the
            // data. Using `emphasized` here would leave the bar still travelling when
            // the next sample landed — it would never catch up, and the number beside it
            // would disagree with it the whole way.
            //
            // Previously this had NO animation while busy, on the reasoning that easing
            // would "smear the jitter". That confused smoothing the MOTION with
            // smoothing the DATA: track doesn't hide a spike, it just stops the bar
            // teleporting to it.
            Behavior on value {
                NumberAnimation {
                    duration: speedRow.busy ? Motion.track : Motion.emphasized
                    easing.type: speedRow.busy ? Motion.trackCurve : Easing.OutCubic
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

    // ── InfoRow ───────────────────────────────────────────────────────────────
    // Label left, fact right, and — if the fact is sensitive — its own reveal button.
    // Local to this page for now; it moves to components/ the moment a second page
    // wants it.
    //
    // ── Why each row hides itself ─────────────────────────────────────────────
    // This used to be one page-wide `ipBlurred` flag behind a single eye, so revealing
    // your IP also revealed the gateway, the DNS servers and the MAC. That's backwards
    // for the case the masking exists for: you're screen-sharing, someone asks for your
    // local IP, and the only way to show it is to expose your hardware address too.
    // Per-row state means each reveal costs exactly what it reveals.
    //
    // Each row also re-hides itself: `revealed` is local state on a row that's rebuilt
    // when the page is, so nothing stays unmasked across a close/open by accident.
    component InfoRow: RowLayout {
        id: infoRow
        property string label: ""
        property string value: ""
        property color  tint:  Colors.fg
        property bool   wrap:  false

        // A status lamp beside the value. Only Status uses it: the dot's job is to make
        // one row scannable, and a dot on every row is a dot on none.
        property bool   dot:   false

        // Masked until asked for, with a per-row eye.
        property bool   secret:   false
        property bool   revealed: false

        // Shown in place of the dots while masked, when the shape of the secret is
        // worth knowing even though its contents aren't (see dnsSummary).
        property string summary:  ""

        readonly property bool hasValue: infoRow.value !== "" && infoRow.value !== "—"
        readonly property bool masked:   infoRow.secret && !infoRow.revealed
                                      && infoRow.hasValue

        Layout.fillWidth: true
        spacing: Tokens.spacingMd

        StyledText {
            Layout.preferredWidth: 90
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            text:    infoRow.label
            variant: "body"
        }
        Rectangle {
            visible: infoRow.dot
            Layout.alignment: Qt.AlignVCenter
            implicitWidth:  7
            implicitHeight: 7
            radius: 3.5
            color:  infoRow.tint
        }
        StyledText {
            Layout.fillWidth: true
            // Alignment must NOT depend on `masked`. A wrapping row is short when
            // masked and tall when revealed, and if this flipped VCenter→Top on reveal
            // the text would jump vertically at the same moment the row grew.
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            text:     infoRow.masked ? (infoRow.summary !== "" ? infoRow.summary
                                                               : "••••••••••")
                                     : infoRow.value
            color:    infoRow.masked ? Colors.fgDim : infoRow.tint
            variant:  "body"
            // A masked value is always one line, whatever it's hiding — so it must not
            // wrap even when the real value would. Otherwise the row's height depends on
            // how many nameservers you have, which is a fact the mask is meant to be
            // keeping.
            wrapMode: infoRow.wrap && !infoRow.masked ? Text.WordWrap : Text.NoWrap
            elide:    infoRow.wrap && !infoRow.masked ? Text.ElideNone : Text.ElideRight
        }
        // ── The eye's slot is ALWAYS here ─────────────────────────────────────
        // A reserved 22px cell, present on every row whether or not that row has a
        // secret. This is the actual fix for "the reveal buttons shift everything", and
        // the two previous attempts missed it by looking at the button instead of the
        // row:
        //
        //  · `visible: false` on a Layout item doesn't just hide it, it REMOVES it from
        //    the layout. So a row with an eye reserved 22px that its neighbours didn't,
        //    every value text in the card was a different width, and the moment
        //    hasValue flipped (an address arriving, a gateway resolving) the text under
        //    the cursor jumped 22px sideways. An Item that's always present and a button
        //    that hides INSIDE it keeps the geometry constant.
        //  · It is NOT the glyph widths: 󰈈 and 󰈉 both measure 14.234px in this font,
        //    identical to three decimals. That was a plausible guess and it was wrong.
        //
        // Height is pinned too, so a row can't change height by revealing.
        Item {
            Layout.alignment: infoRow.wrap ? Qt.AlignTop : Qt.AlignVCenter
            Layout.preferredWidth:  22
            Layout.preferredHeight: 22

            PanelButton {
                anchors.fill: parent
                variant:   "ghost"
                visible:   infoRow.secret && infoRow.hasValue
                glyph:     infoRow.revealed ? "󰈈" : "󰈉"      // eye / eye-off
                glyphTint: infoRow.revealed ? Colors.info : Colors.fgDim
                onActivated: infoRow.revealed = !infoRow.revealed
            }
        }
    }
}
