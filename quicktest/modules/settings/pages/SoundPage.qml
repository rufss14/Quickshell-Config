pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../../config"
import "../../../components"
import "../../../services"

// ── SoundPage ─────────────────────────────────────────────────────────────────
// Output, input, and what each application is playing through them.
//
// ── This page is a view; the service does the work ────────────────────────────
// Everything here comes from the Audio singleton, which the bar's VolumePill and the
// equaliser already use. No PipeWire is touched directly — in particular this page does
// NOT declare its own PwObjectTracker. Audio already tracks every node in the registry,
// and it must: a PwNode's `properties` and `audio` are empty until something tracks it,
// so filtering by media.class before tracking matches nothing and the registry reads as
// literally empty. That trap is written up in Audio.qml; the fix belongs there, once,
// rather than in every page that wants a device list.
//
// ── Three columns: Output | Input | Applications ──────────────────────────────
// The same reasoning as NetworkPage, and the same measured geometry (the page is
// ~1510 wide, not the ~750 the SettingsCard fallback implies — see NetworkPage's header
// for the derivation). Devices and per-app streams stacked in one column would be a
// wall of half-empty rows; side by side they each get a readable width.
//
// Output and Input are the same shape deliberately — a master slider, then the devices
// you can send it to — because they ARE the same question asked twice, and giving them
// two different layouts would make you learn it twice.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Wheel steps. 5% is small enough to fine-tune and large enough that a normal flick
    // crosses the range, which is what the bar pill already uses.
    readonly property real wheelStep: 0.05

    // ── Peak meters ───────────────────────────────────────────────────────────────
    // PwNodePeakMonitor is a native Quickshell type: point it at a node, set enabled,
    // read `peak`. No cava, no subprocess, no polling.
    //
    // Every monitor on this page is gated on `root.visible`, because enabling one asks
    // PipeWire to keep streaming peak data for that node. A settings page nobody is
    // looking at has no business doing that, and with a monitor per app the cost scales
    // with what's playing.
    readonly property bool metering: root.visible && Audio.ready

    // ── Linear amplitude → a bar you can read ─────────────────────────────────────
    // `peak` is linear amplitude, and plotting it linearly makes a useless meter: music
    // mastered at a comfortable −20 dBFS reads as 0.1, so the bar sits almost flat and
    // only twitches on the loudest transients. Hearing is logarithmic, so the meter is
    // too — −60 dBFS (near silence) to 0 dBFS (full scale) mapped across the bar.
    function meterLevel(peak) {
        if (!peak || peak <= 0) return 0
        const db = 20 * Math.log10(peak)
        return Math.max(0, Math.min(1, (db + 60) / 60))
    }

    // ── Spectrum ──────────────────────────────────────────────────────────────
    // Cava is refcounted and runs only while something holds a reference — the same
    // contract VisualizerPill honours. Held only while this page is on screen, so
    // opening Settings on another page doesn't start an audio analyser.
    //
    // 32 is the service's own barCount and its maximum: resample only ever DOWNsamples,
    // because upsampling would invent data. A strip this wide can use all of them.
    readonly property int spectrumBarCount: Cava.barCount
    readonly property var spectrumBars: Cava.bars

    property bool _cavaHeld: false
    function _syncCava() {
        const want = root.visible
        if (want === root._cavaHeld) return
        if (want) Cava.acquire()
        else      Cava.release()
        root._cavaHeld = want
    }
    onVisibleChanged: {
        root._syncCava()
        // Leaving the page must stop the loopback. A mic playing into your output with
        // no visible control anywhere is the one failure mode this feature can have.
        if (!root.visible) MicTest.stop()
    }
    Component.onCompleted: root._syncCava()
    Component.onDestruction: {
        // Without this a destroyed page leaks its reference and pins cava on forever.
        if (root._cavaHeld) Cava.release()
        MicTest.stop()
    }

    // ── Device facts ──────────────────────────────────────────────────────────
    // Straight from the node's PipeWire properties — no subprocess, nothing polled.
    //
    // Deliberately absent: sample rate and bit depth. Those live in the node's `Format`
    // param (S24LE / 48000 on this machine), and PwNode exposes `properties`, not
    // `params` — so reading them would mean shelling out to pw-dump. Not worth a
    // subprocess for two lines of text; flagged here so it isn't mistaken for an
    // oversight.
    function deviceFacts(node) {
        if (!node) return []
        const p = node.properties || {}
        const out = []

        const add = (label, value) => { if (value) out.push({ label: label, value: String(value) }) }

        // Plain words over the vendor's own strings. "audio.channels = 2" is exact and
        // means nothing to most people; "Stereo (2 channels)" is the same fact in
        // language you already have. Same for the ALSA path, which is a routing detail
        // presented here as what it physically is.
        const ch = parseInt(p["audio.channels"])
        add("Sound",      ch === 1 ? "Mono (1 channel)"
                        : ch === 2 ? "Stereo (2 channels)"
                        : ch > 2   ? "Surround (" + ch + " channels)" : "")
        add("Mode",       p["device.profile.description"])
        add("Connection", root.connectionOf(node))
        add("Hardware",   p["alsa.card_name"])

        // "16384/48000" — frames over rate. Shown in ms because frames are meaningless
        // without the rate beside them, and it's the BUFFER CEILING, not the latency you
        // are currently getting, so it's labelled as such rather than as "Latency" —
        // calling it latency would have people reading it as their actual delay.
        const lat = p["node.max-latency"]
        if (lat && String(lat).indexOf("/") > 0) {
            const parts = String(lat).split("/")
            const frames = parseFloat(parts[0]), rate = parseFloat(parts[1])
            if (rate > 0) add("Buffer limit", Math.round(frames / rate * 1000) + " ms")
        }
        return out
    }

    // How the device is physically attached, in words rather than in an ALSA path.
    // `api.alsa.path` encodes this (hdmi:1, iec958:2, front:0) but says it in a form
    // that only helps if you already know what it means.
    function connectionOf(node) {
        if (!node) return ""
        const p = node.properties || {}
        const hay = ((p["api.alsa.path"] || "") + " " + (node.name || "")).toLowerCase()

        if (hay.indexOf("hdmi") >= 0)   return "HDMI (screen or TV)"
        if (hay.indexOf("iec958") >= 0) return "Digital / optical (S-PDIF)"
        if (hay.indexOf("usb") >= 0)    return "USB"
        if (hay.indexOf("bluez") >= 0)  return "Bluetooth"
        if (p["device.api"] === "alsa") return "Built-in (analog)"
        return ""
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        PanelHeader {
            glyph:     Audio.glyph(Audio.volume, Audio.muted)
            title:     "Sound"
            titleTail: Audio.sink ? Audio.labelFor(Audio.sink) : ""
            accent:    Colors.focus

            subtitle: !Audio.ready
                    ? "PipeWire not available"
                    : Audio.muted
                      ? "Muted"
                      : Math.round(Audio.volume * 100) + "% output  ·  "
                        + Audio.streams.length + " app"
                        + (Audio.streams.length !== 1 ? "s" : "") + " playing"
        }

        Divider {}

        // Nothing below this means anything without a running PipeWire. An empty page
        // that says why beats three columns of dead controls.
        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXl
            visible: !Audio.ready
            text: "PipeWire isn't running, or hasn't published a default sink yet."
            variant: "body"
            emphasis: "dim"
            horizontalAlignment: Text.AlignHCenter
        }

        RowLayout {
            Layout.fillWidth: true
            visible: Audio.ready
            spacing: Tokens.spacingXl

            // ══ Output ════════════════════════════════════════════════════════
            ColumnLayout {
                // The even-split idiom: fillWidth distributes the SURPLUS, so equal tiny
                // preferred widths divide the row evenly regardless of what the content
                // would rather be. Without these the longest device name decides the
                // column widths. (NetworkPage measured this: 597/120 without, 359/358
                // with.)
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                StyledText { text: "Output"; variant: "label"; emphasis: "muted" }

                LevelCard {
                    Layout.fillWidth: true
                    glyph:  Audio.glyph(Audio.volume, Audio.muted)
                    label:  Audio.sink ? Audio.labelFor(Audio.sink) : "No output device"
                    level:  Audio.volume
                    isMuted: Audio.muted
                    node:   Audio.sink
                    onSetLevel: function(v) { Audio.setVolume(v) }
                    onStepLevel: function(d) { Audio.stepVolume(d * root.wheelStep) }
                    onToggled: Audio.toggleMute()
                }

                // ── Balance ───────────────────────────────────────────────────
                // Only for a device with a front L/R pair — on mono, or a layout we
                // don't claim to understand, there is nothing to balance and a dead
                // slider would be worse than no slider.
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: Audio.canBalance
                    implicitHeight: balBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: balBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        readonly property real balance: Audio.balanceOf(Audio.sink)

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            StyledText { text: "Balance"; variant: "label"; emphasis: "muted" }
                            Item { Layout.fillWidth: true }

                            // Centre is the state you almost always want to be in, so it
                            // gets a word rather than a number — and the reset only
                            // appears when there's something to reset, so the row isn't
                            // carrying a permanently-dead button.
                            StyledText {
                                visible: Math.abs(balBox.balance) < 0.01
                                text: "Centred"
                                variant: "caption"
                                emphasis: "dim"
                            }

                            PanelButton {
                                variant: "ghost"
                                visible: Math.abs(balBox.balance) >= 0.01
                                label: Math.round(Math.abs(balBox.balance) * 100)
                                     + "% " + (balBox.balance < 0 ? "left" : "right")
                                     + "  ·  Centre"
                                onActivated: Audio.centreBalance(Audio.sink)
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            StyledText { text: "L"; variant: "caption"; emphasis: "dim" }

                            ValueSlider {
                                Layout.fillWidth: true
                                // −1..+1 folded onto the slider's 0..1. The notch marks
                                // centre, so returning to it by hand is possible without
                                // hunting for the exact pixel.
                                value:   (balBox.balance + 1) / 2
                                maximum: 1.0
                                notchAt: 0.5
                                accent:  Colors.focus
                                onMoved: function(v) { Audio.setBalance(Audio.sink, v * 2 - 1) }
                                onScrolled: function(d) {
                                    Audio.setBalance(Audio.sink,
                                                     balBox.balance + d * root.wheelStep)
                                }
                            }

                            StyledText { text: "R"; variant: "caption"; emphasis: "dim" }
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacingSm
                    text: "Devices"
                    variant: "label"
                    emphasis: "muted"
                    visible: Audio.sinks.length > 0
                }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: Audio.sinks.length > 0
                    implicitHeight: sinkBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: sinkBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        Repeater {
                            model: Audio.sinks

                            DeviceRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node:     modelData
                                selected: modelData === Audio.sink
                                onPicked: Audio.setDefaultSink(modelData)
                            }
                        }
                    }
                }
            }

            Divider { orientation: Qt.Vertical }

            // ══ Input ═════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                StyledText { text: "Input"; variant: "label"; emphasis: "muted" }

                LevelCard {
                    Layout.fillWidth: true
                    glyph:  Audio.micMuted ? "󰍭" : "󰍬"        // mic-off / mic
                    label:  Audio.source ? Audio.labelFor(Audio.source) : "No input device"
                    level:  Audio.micVolume
                    isMuted: Audio.micMuted
                    tint:   Colors.info
                    node:   Audio.source
                    onSetLevel: function(v) { Audio.setMicVolume(v) }
                    onStepLevel: function(d) {
                        Audio.setMicVolume(Audio.micVolume + d * root.wheelStep)
                    }
                    onToggled: Audio.toggleMicMute()
                }

                StyledText {
                    Layout.topMargin: Tokens.spacingSm
                    text: "Devices"
                    variant: "label"
                    emphasis: "muted"
                    visible: Audio.sources.length > 0
                }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: Audio.sources.length > 0
                    implicitHeight: sourceBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: sourceBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        Repeater {
                            model: Audio.sources

                            DeviceRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node:     modelData
                                selected: modelData === Audio.source
                                tint:     Colors.info
                                onPicked: Audio.setDefaultSource(modelData)
                            }
                        }
                    }
                }

                // Recording apps live under Input rather than with playback: "what is
                // listening to me" is a different question from "what is making noise",
                // and it's the one worth being able to answer at a glance.
                // ── Microphone test ───────────────────────────────────────────
                // Plays your mic back to you. The meter above says the device is
                // receiving signal; only your ears can say whether it sounds right.
                Surface {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacingSm
                    elevation: Tokens.elevationNested
                    implicitHeight: micTestBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: micTestBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingMd

                            StyledText {
                                Layout.fillWidth: true
                                text: "Microphone test"
                                variant: "label"
                                emphasis: "muted"
                            }

                            // Counts down while running, so the auto-stop is visible
                            // rather than the test just ending on its own.
                            StyledText {
                                visible: MicTest.running
                                text: MicTest.remaining + "s"
                                variant: "caption"
                                emphasis: "dim"
                            }

                            PanelButton {
                                variant: MicTest.running ? "primary" : "normal"
                                accent:  Colors.info
                                glyph:   MicTest.running ? "󰓛" : "󰋋"   // stop / headphones
                                label:   MicTest.running ? "Stop" : "Listen"
                                onActivated: MicTest.toggle()
                            }
                        }

                        // ── The mic's own spectrum ────────────────────────────
                        // Its OWN cava instance on the input device — not the shared
                        // output one, which would show whatever music is playing rather
                        // than your voice. Runs only while the test does.
                        Spectrum {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 46
                            visible: MicTest.running
                            levels:   micCava.bars
                            barCount: micCava.barCount
                            barGap:   3
                            accent:   Colors.info
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: MicTest.running
                                ? "You're hearing your microphone. Stops itself after "
                                  + MicTest.limitSeconds + "s."
                                : "Play your microphone back through the output, so you "
                                  + "can hear how you actually sound."
                            variant: "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }

                        // Only while it matters. A feedback warning sitting there
                        // permanently is one you stop reading.
                        StyledText {
                            Layout.fillWidth: true
                            visible: MicTest.running
                            text: "󰀪  On speakers this will howl — headphones only."
                            color: Colors.warning
                            variant: "caption"
                            wrapMode: Text.WordWrap
                        }
                    }
                }

                StyledText {
                    Layout.topMargin: Tokens.spacingSm
                    text: "Recording"
                    variant: "label"
                    emphasis: "muted"
                    visible: Audio.recordingApps.length > 0
                }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: Audio.recordingApps.length > 0
                    implicitHeight: recBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: recBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingMd

                        // One row per APP, not per stream — see Audio.recordingApps.
                        Repeater {
                            model: Audio.recordingApps

                            Item {
                                id: recEntry
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: recRow.implicitHeight

                                // Watches every one of the app's streams. Metering only
                                // the first would read flat whenever the live stream
                                // happened to be another one.
                                PeakGroup {
                                    id: recPeaks
                                    nodes:  recEntry.modelData.nodes
                                    active: root.metering
                                }

                                RowLayout {
                                    id: recRow
                                    anchors.left:  parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Tokens.spacingMd

                                    StyledText {
                                        text: "󰍬"
                                        color: Colors.info
                                        variant: "body"
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: Audio.labelFor(recEntry.modelData.node)
                                        variant: "body"
                                        elide: Text.ElideRight
                                    }

                                    // Only for apps holding more than one stream, so the
                                    // usual row stays clean and the badge means something
                                    // when it does appear.
                                    StyledText {
                                        visible: recEntry.modelData.count > 1
                                        text: "×" + recEntry.modelData.count
                                        variant: "caption"
                                        emphasis: "dim"
                                    }

                                    // Fixed width rather than filling: it sits beside the
                                    // name, and a meter that resized with the longest app
                                    // name would jitter as the list changes.
                                    Meter {
                                        Layout.preferredWidth: 56
                                        implicitHeight: 4
                                        value:  root.meterLevel(recPeaks.peak)
                                        accent: Colors.alpha(Colors.info, 0.75)
                                        fillDuration: Motion.track
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Divider { orientation: Qt.Vertical }

            // ══ Applications ══════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.alignment: Qt.AlignTop
                spacing: Tokens.spacingMd

                StyledText { text: "Applications"; variant: "label"; emphasis: "muted" }

                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    implicitHeight: appBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: appBox
                        anchors.left:  parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingLg

                        Repeater {
                            model: Audio.streams

                            StreamRow {
                                required property var modelData
                                Layout.fillWidth: true
                                node: modelData
                            }
                        }

                        // Silence is the common case, and an empty card reads as broken
                        // without a word in it.
                        StyledText {
                            Layout.fillWidth: true
                            visible: Audio.streams.length === 0
                            text: "Nothing is playing."
                            variant: "body"
                            emphasis: "dim"
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: "Per-app volume is a PipeWire stream property — it follows the "
                        + "app, not this page, and survives closing the settings."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ══ Bottom strip: device facts flanking a live spectrum ═══════════════
        // The same shape as NetworkPage's traffic strip, for the same reason: the three
        // columns above are compact and top-aligned, so without this the page is mostly
        // empty below the fold. The strip claims that band and fills the height.
        Divider { Layout.topMargin: Tokens.spacingSm; visible: Audio.ready }

        RowLayout {
            Layout.fillWidth: true
            visible: Audio.ready
            spacing: Tokens.spacingMd

            // "Signal" was jargon — it named the engineering concept rather than the
            // thing you're looking at. The title now says what it is and the line under
            // it says what it's for, because this strip is otherwise the least
            // self-explanatory part of the page.
            // fillWidth FALSE plus an explicit spacer below, rather than letting this
            // column absorb the surplus. Measured: with fillWidth here the controls
            // landed at x=760/1021 and the button ended at 1264 in a 1510 row — 246px of
            // dead space after it, and gaps scattered between every item. With the
            // spacer they sit flush right, trailing gap 0.
            ColumnLayout {
                Layout.fillWidth: false
                spacing: 0

                StyledText { text: "Live audio"; variant: "label"; emphasis: "muted" }
                StyledText {
                    text: Cava.hasData
                        ? "A live picture of the sound coming out of your computer."
                        : "Nothing is playing right now — start some audio to see it move."
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            // Everything after this sits hard against the right edge.
            Item { Layout.fillWidth: true }

            // ── Desktop visualiser ────────────────────────────────────────────
            // The same spectrum, pinned behind your windows (CavaBG). It could only be
            // reached by left-clicking the bar's visualiser pill, which is undiscoverable
            // — and only findable at all if that module is even on your bar.
            //
            // Config, not UiState: this is a preference now and survives a restart.
            StyledText {
                Layout.leftMargin: Tokens.spacingLg
                text: "Show on desktop"
                variant: "caption"
                emphasis: "muted"
            }
            Toggle {
                checked: Config.cavaBg
                accent:  Colors.focus
                onToggled: Config.cavaBg = !Config.cavaBg
            }

            // ── Restart audio ─────────────────────────────────────────────────
            // Two-step, because this drops audio for a second or two and apps holding a
            // stream may not recover it on their own. An accidental click here is a real
            // cost, so it costs a second click.
            PanelButton {
                id: restartBtn
                Layout.leftMargin: Tokens.spacingLg
                variant: restartBtn.armed ? "primary" : "normal"
                accent:  Colors.warning
                glyph:   "󰜉"                                  // md-restart
                label:   Audio.restarting ? "Restarting…"
                       : restartBtn.armed ? "Sure? Audio will cut out"
                                          : "Restart audio"

                property bool armed: false

                onActivated: {
                    if (Audio.restarting) return
                    if (restartBtn.armed) {
                        restartBtn.armed = false
                        Audio.restartStack()
                    } else {
                        restartBtn.armed = true
                    }
                }

                // Disarms itself, so a button left armed doesn't fire on an unrelated
                // click a minute later.
                Timer {
                    running: restartBtn.armed
                    interval: 4000
                    onTriggered: restartBtn.armed = false
                }
            }
        }

        Surface {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 190
            visible: Audio.ready
            elevation: Tokens.elevationNested

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingLg

                // ── Output facts ──────────────────────────────────────────────
                // `Layout.fillWidth: false` is LOAD-BEARING, not redundant: a Layout
                // nested in another Layout defaults fillWidth to true, which silently
                // overrides preferredWidth. On NetworkPage that starved the graph to
                // 6px while a side column took 1415. Do not "tidy" these away.
                DeviceFacts {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 250
                    Layout.fillHeight: true
                    title: "Output"
                    node:  Audio.sink
                    tint:  Colors.focus
                }

                Divider { orientation: Qt.Vertical }

                // ── Spectrum ──────────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingSm

                    Spectrum {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        levels:   root.spectrumBars
                        barCount: root.spectrumBarCount
                        barGap:   4
                        accent:   Colors.focus
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: "What's playing through " + (Audio.sink ? Audio.labelFor(Audio.sink) : "the output")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                Divider { orientation: Qt.Vertical }

                // ── Input facts ───────────────────────────────────────────────
                DeviceFacts {
                    Layout.fillWidth: false
                    Layout.preferredWidth: 250
                    Layout.fillHeight: true
                    title: "Input"
                    node:  Audio.source
                    tint:  Colors.info
                }
            }
        }
    }

    // ── Microphone spectrum ───────────────────────────────────────────────────
    // A second cava, on the INPUT device. The shared Cava singleton analyses the default
    // output, so pointing the mic test at it would draw whatever music happens to be
    // playing — during a loopback test that's especially misleading, since your voice
    // would be in there too and you couldn't tell which bars were which.
    //
    // Tied to MicTest.running, so no process exists unless a test is actually underway.
    CavaStream {
        id: micCava
        source:  Audio.source ? Audio.source.name : ""
        running: MicTest.running
    }

    // ── Route picker ──────────────────────────────────────────────────────────
    // One menu for the whole page rather than one per row: a ContextMenu per app row
    // would build a menu for every stream whether or not anyone ever opens one, and they
    // would all be competing to paint above each other.
    //
    // The stream is held here while the menu is open, because ContextMenu.triggered only
    // carries a string key. The key is the sink's NAME — stable, and already what the
    // move takes.
    property var _routeStream: null

    function openRouteMenu(anchorItem, stream) {
        root._routeStream = stream
        const current = Audio.sinkOf(stream)

        routeMenu.items = Audio.sinks.map(s => ({
            key: s.name,
            // Short name + profile, not the 60-character description. The profile is
            // what actually distinguishes two outputs on the same card, so dropping it
            // would make them indistinguishable.
            label: Audio.shortLabelFor(s)
                 + (Audio.profileOf(s) ? "  ·  " + Audio.profileOf(s) : "")
                 + (s === current ? "   ✓" : ""),
            // The device KIND, not a checkbox — the tick moved into the label so this
            // slot can say what sort of output it is.
            glyph: Audio.deviceGlyph(s),
            tint:  s === current ? Colors.focus : Colors.fg
        }))

        // Scene coordinates: the menu is parented to the page, not to the button.
        const p = anchorItem.mapToItem(root, 0, anchorItem.height)
        routeMenu.openAt(p.x, p.y)
    }

    ContextMenu {
        id: routeMenu
        anchors.fill: parent
        // Measured, not estimated. The longest real label here — "HD-Audio Generic  ·
        // Digital Stereo (IEC958)   ✓" — renders at ~316px at fontLabel (12px). The menu
        // spends ~53px on column margins, the glyph and its gaps, so 400 leaves the label
        // ~327px and it fits without eliding. The default 200 cut it roughly in half.
        //
        // A first attempt at 330 still elided; the arithmetic is why this is a measured
        // number rather than a round one that looked generous.
        menuWidth: 400

        onTriggered: function(key) {
            const sink = Audio.sinks.filter(s => s.name === key)[0]
            if (sink && root._routeStream) Audio.moveStream(root._routeStream, sink)
            root._routeStream = null
        }
    }

    // ══ Components ════════════════════════════════════════════════════════════

    // ── DeviceFacts ───────────────────────────────────────────────────────────
    // What a device actually is, in the strip's side columns. Output and input use the
    // same component because they're the same question — and because the day they get
    // two different layouts is the day you have to read both to know which is which.
    component DeviceFacts: ColumnLayout {
        id: facts

        property string title: ""
        property var    node:  null
        property color  tint:  Colors.focus

        readonly property var rows: root.deviceFacts(facts.node)

        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            StyledText { text: facts.title; variant: "label"; emphasis: "muted" }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            StyledText {
                text:  Audio.deviceGlyph(facts.node)
                color: facts.tint
                variant: "body"
            }
            StyledText {
                Layout.fillWidth: true
                // Short name here too: this card is 250px wide, and the full description
                // is up to 60 characters.
                text: facts.node ? Audio.shortLabelFor(facts.node) : "None"
                color: facts.tint
                variant: "body"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }

        Repeater {
            model: facts.rows

            RowLayout {
                id: factRow
                required property var modelData
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                StyledText {
                    Layout.preferredWidth: 78
                    text: factRow.modelData.label
                    variant: "caption"
                    emphasis: "dim"
                }
                StyledText {
                    Layout.fillWidth: true
                    text: factRow.modelData.value
                    variant: "caption"
                    elide: Text.ElideRight
                }
            }
        }

        // Pushes the rows to the top so both side columns align on their first line
        // regardless of how many facts each device happens to publish.
        Item { Layout.fillHeight: true }
    }

    // ── RoutePill ─────────────────────────────────────────────────────────────
    // "Playing to <device>", as a pill you can click to change it. The device glyph does
    // the heavy lifting for a beginner: "HD-Audio Generic" says nothing about where the
    // sound comes out, but a headphone or screen icon does.
    component RoutePill: Item {
        id: pill

        property var sink: null
        signal picked()

        implicitHeight: Tokens.pillHeight

        Rectangle {
            anchors.left:   parent.left
            anchors.top:    parent.top
            anchors.bottom: parent.bottom
            // Hugs its content instead of stretching the row's full width — a pill that
            // spans the column reads as a text field, not a button.
            width: Math.min(parent.width, pillRow.implicitWidth + Tokens.spacingMd * 2)
            radius: Tokens.radiusPill

            color: pillHover.hovered ? Colors.alpha(Colors.focus, 0.22)
                                     : Colors.alpha(Colors.focus, 0.12)
            border.width: Tokens.borderWidth
            border.color: Colors.alpha(Colors.focus, pillHover.hovered ? 0.55 : 0.30)
            Behavior on color { ColorAnimation { duration: Motion.respond } }

            RowLayout {
                id: pillRow
                anchors.fill: parent
                anchors.leftMargin:  Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingMd
                spacing: Tokens.spacingSm

                StyledText {
                    text:  Audio.deviceGlyph(pill.sink)
                    color: Colors.focus
                    variant: "caption"
                }
                StyledText {
                    Layout.fillWidth: true
                    // shortLabelFor, never labelFor: the full description runs to 60
                    // characters and would blow the pill apart.
                    // "Not connected", not "Default output": a null sink means this
                    // stream is linked to no output at all, and naming the default would
                    // be a guess dressed up as a fact.
                    text: pill.sink ? Audio.shortLabelFor(pill.sink) : "Not connected"
                    variant: "caption"
                    elide: Text.ElideRight
                }
                StyledText {
                    text:  "󰅀"                                  // chevron-down
                    color: Colors.fgDim
                    variant: "caption"
                }
            }

            HoverHandler { id: pillHover }
            TapHandler { onTapped: pill.picked() }
        }
    }

    // ── PeakGroup ─────────────────────────────────────────────────────────────
    // The loudest of several nodes, as one level. An app can hold more than one capture
    // stream (Discord: microphone plus game audio), and only one of them may be live, so
    // a row that meters a single stream reads flat at exactly the wrong moment.
    //
    // ── Peak-hold with decay, not a plain max ─────────────────────────────────
    // Each monitor reports independently and they don't tick in step, so taking the raw
    // maximum of whatever arrived last makes the bar flicker between streams. Instead
    // each update decays the held value and takes the max against the new sample:
    // fast attack, gradual release. That's the standard ballistic for an audio meter,
    // and it happens to be exactly what merging several sources needs.
    component PeakGroup: Item {
        id: pg

        property var  nodes:  []
        property bool active: false
        property real peak:   0

        function note(v) { pg.peak = Math.max(v, pg.peak * 0.75) }

        // Nothing is arriving to decay it, so it would otherwise freeze at its last
        // value and the row would keep showing a level after the page closed.
        onActiveChanged: if (!pg.active) pg.peak = 0

        Repeater {
            model: pg.nodes

            Item {
                id: pgSlot
                required property var modelData

                // pgSlot.modelData, not `parent.modelData`: PwNodePeakMonitor is a plain
                // QObject, so it has no visual `parent` to reach through.
                PwNodePeakMonitor {
                    node:    pgSlot.modelData
                    enabled: pg.active
                    onPeakChanged: pg.note(peak)
                }
            }
        }
    }

    // ── LevelCard ─────────────────────────────────────────────────────────────
    // A master level: mute button, device name, percentage, slider. Output and input are
    // the same control with different wiring, so they're the same component — the day
    // they diverge visually is the day someone has to look twice to tell which is which.
    component LevelCard: Surface {
        id: card

        property string glyph:   ""
        property string label:   ""
        property real   level:   0
        property bool   isMuted: false
        property color  tint:    Colors.focus

        // The node to meter. Null disables the meter entirely — the card is still a
        // perfectly good volume control without one.
        property var node: null

        signal setLevel(real value)
        signal stepLevel(int delta)
        signal toggled()

        PwNodePeakMonitor {
            id: cardPeak
            node:    card.node
            enabled: root.metering && card.node !== null
        }

        elevation: Tokens.elevationNested
        implicitHeight: levelBox.implicitHeight + Tokens.spacingLg * 2

        ColumnLayout {
            id: levelBox
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

                PanelButton {
                    variant:   "ghost"
                    glyph:     card.glyph
                    glyphTint: card.isMuted ? Colors.fgDim : card.tint
                    onActivated: card.toggled()
                }

                StyledText {
                    Layout.fillWidth: true
                    text: card.label
                    variant: "body"
                    elide: Text.ElideRight
                    opacity: card.isMuted ? 0.55 : 1.0
                }

                StyledText {
                    text: card.isMuted ? "muted" : Math.round(card.level * 100) + "%"
                    variant: "body"
                    font.weight: Font.DemiBold
                    emphasis: card.isMuted ? "dim" : "normal"
                }
            }

            ValueSlider {
                Layout.fillWidth: true
                value:   card.level
                maximum: 1.0
                accent:  card.isMuted ? Colors.fgDim : card.tint
                onMoved:    function(v) { card.setLevel(v) }
                onScrolled: function(d) { card.stepLevel(d) }
            }

            // Signal, directly under the control that sets it. The slider says how loud
            // this is ALLOWED to be; the meter says whether anything is actually coming
            // through — which is the question a mute button can't answer, since muted
            // and merely silent look identical.
            Meter {
                Layout.fillWidth: true
                visible: card.node !== null
                implicitHeight: 4
                value:  card.isMuted ? 0 : root.meterLevel(cardPeak.peak)
                accent: Colors.alpha(card.tint, 0.75)
                // Live signal, so `track` timing: at the default 150ms each peak is
                // still easing toward the previous one when the next arrives, and the
                // bar smears into a vague midpoint instead of showing the audio.
                fillDuration: Motion.track
            }
        }
    }

    // ── DeviceRow ─────────────────────────────────────────────────────────────
    // One selectable device. Radio rather than a dropdown for the same reason the DNS
    // presets are radios: there are two or three of them and they're the point of the
    // card, so hiding them behind a menu saves a row of space to cost a click.
    component DeviceRow: Item {
        id: dev

        property var   node:     null
        property bool  selected: false
        property color tint:     Colors.focus
        signal picked()

        implicitHeight: Math.max(devRow.implicitHeight + Tokens.spacingSm * 2,
                                 Tokens.pillHeight)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: dev.selected      ? Colors.alpha(dev.tint, 0.12)
                 : devHover.hovered  ? Colors.alpha(Colors.fg, 0.06)
                                     : "transparent"
            border.width: dev.selected ? Tokens.borderWidth : 0
            border.color: Colors.alpha(dev.tint, 0.35)
            Behavior on color { ColorAnimation { duration: Motion.fast } }
        }

        RowLayout {
            id: devRow
            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin:  Tokens.spacingMd
            anchors.rightMargin: Tokens.spacingMd
            spacing: Tokens.spacingMd

            StyledText {
                text:  dev.selected ? "󰄲" : "󰄱"        // checked / unchecked circle
                color: dev.selected ? dev.tint : Colors.fgDim
                variant: "body"
            }

            StyledText {
                Layout.fillWidth: true
                text: dev.node ? Audio.labelFor(dev.node) : ""
                variant: "body"
                font.weight: dev.selected ? Font.DemiBold : Font.Normal
                elide: Text.ElideRight
            }
        }

        HoverHandler { id: devHover }
        TapHandler {
            enabled: !dev.selected
            onTapped: dev.picked()
        }
    }

    // ── StreamRow ─────────────────────────────────────────────────────────────
    // One application's playback: its icon, its name, its own volume.
    //
    // The icon comes from Audio.iconPathFor, which already resolves a PipeWire node to a
    // desktop icon and rejects the generic "some audio thing" names apps routinely
    // declare — a row showing the generic audio icon tells you nothing about WHICH app it
    // belongs to, which is the only thing the row exists to say.
    component StreamRow: ColumnLayout {
        id: stream

        property var node: null

        // levelOf, not audio.volume — the same "loudest channel" measure the writes use,
        // so a panned stream's slider doesn't drift when you drag it. See Audio.qml.
        readonly property real  vol:      Audio.levelOf(stream.node)
        readonly property bool  isMuted:  stream.node?.audio?.muted ?? false
        readonly property string iconPath: stream.node ? Audio.iconPathFor(stream.node) : ""

        // Native read: linkGroups updates itself when the graph changes, so this row
        // re-labels on its own after a move — including a move made from outside the
        // shell. Nothing polls.
        readonly property var routedTo: Audio.sinkOf(stream.node)

        spacing: Tokens.spacingSm

        PwNodePeakMonitor {
            id: streamPeak
            node:    stream.node
            enabled: root.metering && stream.node !== null
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingMd

            // Reserved slot, so apps that resolve an icon and apps that don't still line
            // their names up on one left edge.
            Item {
                Layout.preferredWidth:  18
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter

                Image {
                    anchors.fill: parent
                    source:  stream.iconPath
                    visible: stream.iconPath !== ""
                    sourceSize.width:  18
                    sourceSize.height: 18
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }
                // A fixed glyph, NOT Audio.iconFor(). That returns the icon NAME the app
                // declared ("audio-x-generic"), not a glyph — its docstring says an empty
                // return means the caller falls back to a glyph, and rendering the name
                // itself would print the literal string in the row.
                StyledText {
                    anchors.centerIn: parent
                    visible: stream.iconPath === ""
                    text:  "󰕾"                                // md-volume_high
                    color: Colors.focus
                    variant: "body"
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: stream.node ? Audio.labelFor(stream.node) : ""
                variant: "body"
                elide: Text.ElideRight
                opacity: stream.isMuted ? 0.55 : 1.0
            }

            StyledText {
                text: stream.isMuted ? "muted" : Math.round(stream.vol * 100) + "%"
                variant: "caption"
                emphasis: "dim"
            }

            PanelButton {
                variant:   "ghost"
                glyph:     stream.isMuted ? "󰝟" : "󰕾"      // muted / speaker
                glyphTint: stream.isMuted ? Colors.fgDim : Colors.fg
                onActivated: Audio.toggleNodeMute(stream.node)
            }
        }

        // ── Where this app plays ──────────────────────────────────────────────
        // Only worth a control when there's somewhere else to send it: with one output
        // this is a button that can only tell you what you already know.
        // ── Where this app plays ──────────────────────────────────────────────
        // A filled pill rather than a ghost button: this is the row's only control that
        // carries INFORMATION as well as an action — it's telling you where the sound is
        // going — so it has to be readable at a glance rather than fading into the row.
        RoutePill {
            id: routeBtn
            Layout.fillWidth: true
            visible: Audio.sinks.length > 1
            sink: stream.routedTo
            onPicked: root.openRouteMenu(routeBtn, stream.node)
        }

        Meter {
            Layout.fillWidth: true
            implicitHeight: 3
            value:  stream.isMuted ? 0 : root.meterLevel(streamPeak.peak)
            accent: Colors.alpha(Colors.focus, 0.6)
            fillDuration: Motion.track
        }

        ValueSlider {
            Layout.fillWidth: true
            value:   stream.vol
            maximum: 1.0
            accent:  stream.isMuted ? Colors.fgDim : Colors.focus
            // allowBoost false: the slider tops out at 100%, so it can't be used to
            // push a stream past unity and clip it. Audio.setNodeVolume takes the flag
            // because the equaliser wants boost; a settings page does not.
            onMoved:    function(v) { Audio.setNodeVolume(stream.node, v, false) }
            onScrolled: function(d) {
                Audio.setNodeVolume(stream.node,
                                    stream.vol + d * root.wheelStep, false)
            }
        }
    }
}
