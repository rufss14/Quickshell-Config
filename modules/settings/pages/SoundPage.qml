pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
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
// ── Two columns of cards ──────────────────────────────────────────────────────
// Output and Applications on the left, Input and the microphone test on the right.
// Output and Input keep the SAME shape deliberately — a master level, then the
// devices you can send it to — because they are the same question asked twice, and
// giving them two layouts would make you learn it twice.
//
// ── Levels are the media panel's fat slider, with a live hairline under it ────
// Each level is a ThickSlider (the one the media panel uses for a player's volume) and,
// for the two devices, a thin Meter under it that follows the live peak — so "muted",
// "silent" and "playing" still read as three different states, as the wavy slider they
// replaced made them, without a wobbling track to aim at.
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

    // meterLevel() itself moved to Audio.qml — the bar's volume pill needed the
    // same -60..0dB mapping for its own peak-driven wave.

    // Leaving the page must stop the loopback. A mic playing into your output with no
    // visible control anywhere is the one failure mode the mic test can have.
    //
    // (The overhaul removed the page's decorative live-spectrum strip, and with it the
    // Cava hold that existed only to feed it — the desktop visualiser below has its own
    // consumer. It also removed the per-device "facts" rows: channel count, ALSA card
    // name, buffer ceiling — detail nobody changes anything based on.)
    onVisibleChanged: if (!root.visible) MicTest.stop()
    Component.onDestruction: MicTest.stop()

    SettingsPage {
        anchors.fill: parent
        bento:   true

        glyph:     Audio.glyph(Audio.volume, Audio.muted)
        title:     Translation.tr("Sound")
        titleTail: Audio.sink ? Audio.shortLabelFor(Audio.sink) : ""
        accent:    Colors.of(QsWindow.window).primary

        // ── Restart audio ─────────────────────────────────────────────────────
        // Two-step, because this drops audio for a second or two and apps holding a
        // stream may not recover it on their own. It's a recovery action for the whole
        // audio stack, so it lives in the header rather than inside a card.
        actions: ChipTray {
            ChipButton {
                ArmLatch {
                    id: restartLatch
                    onConfirmed: Audio.restartStack()
                }

                on:     restartLatch.armed
                tint:   restartLatch.armed ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).primary
                symbol: "restart_alt"
                label:  Audio.restarting ? "Restarting…"
                      : restartLatch.armed ? "Sure? Audio will cut out"
                      : "Restart audio"

                onActivated: {
                    if (Audio.restarting) return
                    restartLatch.trigger()
                }
            }
        }

        subtitle: !Audio.ready
        ? "PipeWire not available"
        : Audio.muted
        ? "Muted"
        : Math.round(Audio.volume * 100) + "% output  ·  "
        + Audio.streams.length + " app"
        + (Audio.streams.length !== 1 ? "s" : "") + " playing"

        // Nothing below this means anything without a running PipeWire. An empty page
        // that says why beats a column of dead controls.
        StyledText {
            id: noAudio
            // The page body is a BentoGrid: without a span this was one sixth-wide cell, and
            // the centred line spilled off the page's left edge.
            property int span: 3
            Layout.columnSpan: parent && parent.spanFor ? parent.spanFor(noAudio) : 1
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacingXl
            wrapMode: Text.WordWrap
            visible: !Audio.ready
            text: Translation.tr("PipeWire isn't running, or hasn't published a default sink yet.")
            variant: "body"
            emphasis: "dim"
            horizontalAlignment: Text.AlignHCenter
        }

        // ══ The grid ══════════════════════════════════════════════════════════
        // Output, Input and the mic test are one row of equal tiles — three cards
        // about three devices, which is what the page is for. Applications takes two
        // columns because it is a LIST and a list wants a run, and the visualiser sits
        // beside it. Recording spans the width and is usually not there at all: it
        // renders only while something holds the microphone open.
        //
        // (It was two hand-balanced columns, paired by measured height — Output ~490px
        // against Input ~400 — which is a sum that goes stale the first time either
        // card gains a row. The grid balances itself.)

        Section {
            span:     1
            visible: Audio.ready
            glyph:    "󰕾"
            title:    Translation.tr("Output")
            subtitle: Audio.sinks.length > 1 ? Audio.sinks.length + " devices" : ""
            help:     Translation.tr("Where sound goes, and how loud. Click the speaker to mute; scroll over the level to step it.")

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
            //
            // No longer its own Surface: stacked in one column that would be a card
            // inside a card. It is a row of this section like any other.
            Divider { visible: Audio.canBalance }

            ColumnLayout {
                id: balBox
                Layout.fillWidth: true
                visible: Audio.canBalance
                spacing: Tokens.spacingSm

                readonly property real balance: Audio.balanceOf(Audio.sink)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    StyledText { text: "Balance"; variant: "body"; font.weight: Font.Medium }
                    Item { Layout.fillWidth: true }

                    // Centre is the state you almost always want to be in, so it
                    // gets a word rather than a number — and the reset only
                    // appears when there's something to reset, so the row isn't
                    // carrying a permanently-dead button.
                    StyledText {
                        visible: Math.abs(balBox.balance) < 0.01
                        text: Translation.tr("Centred")
                        variant: "caption"
                        emphasis: "dim"
                    }

                    PanelButton {
                        capsule: true
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
                        accent:  Colors.of(QsWindow.window).primary
                        onMoved: function(v) { Audio.setBalance(Audio.sink, v * 2 - 1) }
                        onScrolled: function(d) {
                            Audio.setBalance(Audio.sink,
                            balBox.balance + d * root.wheelStep)
                        }
                    }

                    StyledText { text: "R"; variant: "caption"; emphasis: "dim" }
                }
            }

            Divider { visible: Audio.sinks.length > 0 }

            ColumnLayout {
                Layout.fillWidth: true
                visible: Audio.sinks.length > 0
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

        Section {
            span:     1
            visible: Audio.ready
            glyph:    "󰍬"
            title:    Translation.tr("Input")
            subtitle: Audio.sources.length > 1 ? Audio.sources.length + " devices" : ""
            help:     Translation.tr("What the machine can hear. Test plays your microphone back through the output, so you hear how you actually sound — headphones only, or it howls.")
            accent:   Colors.of(QsWindow.window).primary

            LevelCard {
                Layout.fillWidth: true
                glyph:  Audio.micMuted ? "󰍭" : "󰍬"        // mic-off / mic
                label:  Audio.source ? Audio.labelFor(Audio.source) : "No input device"
                level:  Audio.micVolume
                isMuted: Audio.micMuted
                tint:   Colors.of(QsWindow.window).primary
                node:   Audio.source
                onSetLevel: function(v) { Audio.setMicVolume(v) }
                onStepLevel: function(d) {
                    Audio.setMicVolume(Audio.micVolume + d * root.wheelStep)
                }
                onToggled: Audio.toggleMicMute()
            }

            Divider { visible: Audio.sources.length > 0 }

            ColumnLayout {
                Layout.fillWidth: true
                visible: Audio.sources.length > 0
                spacing: Tokens.spacingSm

                Repeater {
                    model: Audio.sources

                    DeviceRow {
                        required property var modelData
                        Layout.fillWidth: true
                        node:     modelData
                        selected: modelData === Audio.source
                        tint:     Colors.of(QsWindow.window).primary
                        onPicked: Audio.setDefaultSource(modelData)
                    }
                }
            }

            Divider {}

            // ── Hear yourself ─────────────────────────────────────────────────
            // The microphone test, as a row of the card it tests rather than a card
            // of its own. Its own cava instance on the input device — not the shared
            // output one, which would show the music rather than your voice — runs
            // only while the test does.
            SettingRow {
                label:  Translation.tr("Test")
                detail: MicTest.running ? "Listening — stops in " + MicTest.remaining + "s"
                                        : "Hear yourself as others do"
                PanelButton {
                    capsule: true
                    variant: MicTest.running ? "primary" : "normal"
                    accent:  Colors.of(QsWindow.window).primary
                    glyph:   MicTest.running ? "󰓛" : "󰋋"   // stop / headphones
                    label:   MicTest.running ? "Stop" : "Listen"
                    onActivated: MicTest.toggle()
                }
            }
            Spectrum {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                visible: MicTest.running
                levels:   micCava.bars
                barCount: micCava.barCount
                barGap:   3
                accent:   Colors.of(QsWindow.window).primary
            }
            // Only while it matters. A feedback warning sitting there permanently is
            // one you stop reading.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: MicTest.running
                text: Translation.tr("On speakers this will howl — headphones only.")
                color: Colors.of(QsWindow.window).warning
                variant: "caption"
                wrapMode: Text.WordWrap
            }

        }

        Section {
            span:     2
            visible: Audio.ready
            glyph:    "󱕷"
            title:    Translation.tr("Applications")
            subtitle: Audio.streams.length === 0 ? "Nothing playing"
                    : Audio.streams.length + (Audio.streams.length === 1 ? " playing" : " playing")
            help:     Translation.tr("Per-app volume, and which device each one plays on. It is a PipeWire stream property — it follows the app, not this page.")
            bodySpacing: Tokens.spacingMd

            ColumnLayout {
                id: appBox
                Layout.fillWidth: true
                spacing: Tokens.spacingMd

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
                    text: Translation.tr("Start something and it shows up here")
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }

        Section {
            span:     1
            visible: Audio.ready
            glyph:    "󰺣"
            title:    Translation.tr("Desktop visualiser")
            subtitle: Config.cavaBg ? "Behind your windows" : "Off"
            help:     Translation.tr("A live spectrum of what's playing, pinned behind your windows.")

            // ── Desktop visualiser ────────────────────────────────────────────
            // The same spectrum, pinned behind your windows (CavaBG). It could only be
            // reached by left-clicking the bar's visualiser pill, which is
            // undiscoverable — and only findable at all if that module is even on your
            // bar.
            //
            // Config, not UiState: this is a preference now and survives a restart.
            // The card's own switch, in its heading.
            actions: Toggle {
                checked: Config.cavaBg
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBg = !Config.cavaBg
            }

            // Three renderers over the one analyser — see CavaBG.qml. Shown only
            // once the background is actually on; a style picker for a spectrum
            // you can't see is noise.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: Config.cavaBg
                spacing: Tokens.spacingXs

                TabStrip {
                    Layout.fillWidth: true
                    accent: Colors.of(QsWindow.window).primary
                    model: [
                        { value: "bars", label: "Bars",     icon: "bar_chart" },
                        { value: "wave", label: "Waveform", icon: "equalizer" },
                        { value: "dots", label: "Dots",     icon: "more_horiz" },
                        { value: "ring", label: "Ring",     icon: "radio_button_unchecked" }
                    ]
                    current: Config.cavaBgStyle
                    onPicked: function(v) { Config.cavaBgStyle = v }
                }

                Fader {
                    Layout.topMargin: Tokens.spacingXs
                    label:  Translation.tr("Intensity")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0.5; to: 3.0; step: 0.1
                    value:   Config.cavaBgIntensity
                    readout: Config.cavaBgIntensity.toFixed(1) + "×"
                    onCommit: function(v) { Config.cavaBgIntensity = Math.round(v * 10) / 10 }
                }

                // ── What it listens to, and its extras (2026-10-31, the user's picks) ──
                SettingRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    label:  Translation.tr("Music only")
                    detail: Config.cavaBgMusicOnly ? "The player's own sound — calls and alerts don't move it"
                                                   : "Everything you hear"
                    Toggle {
                        checked: Config.cavaBgMusicOnly
                        accent:  Colors.of(QsWindow.window).primary
                        onToggled: Config.cavaBgMusicOnly = !Config.cavaBgMusicOnly
                    }
                }
                SettingRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Config.cavaBgStyle === "bars" || Config.cavaBgStyle === "ring"
                    label:  Translation.tr("Peak caps")
                    detail: Translation.tr("A cap over each bar that holds, then falls")
                    Toggle {
                        checked: Config.cavaBgPeaks
                        accent:  Colors.of(QsWindow.window).primary
                        onToggled: Config.cavaBgPeaks = !Config.cavaBgPeaks
                    }
                }
                SettingRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    label:  Translation.tr("Glow")
                    detail: Translation.tr("A soft light round it, in its colour")
                    Toggle {
                        checked: Config.cavaBgGlow
                        accent:  Colors.of(QsWindow.window).primary
                        onToggled: Config.cavaBgGlow = !Config.cavaBgGlow
                    }
                }
                SettingRow {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: Config.cavaBgStyle === "ring"
                    label:  Translation.tr("Album cover")
                    detail: Translation.tr("The cover inside the ring while music plays")
                    Toggle {
                        checked: Config.cavaBgRingCover
                        accent:  Colors.of(QsWindow.window).primary
                        onToggled: Config.cavaBgRingCover = !Config.cavaBgRingCover
                    }
                }

                // ── Its colours (2026-10-31) ──────────────────────────────────
                // A blend of 1–5 (the user: "more colors from the scheme"): tap a swatch to add
                // it, numbered in the order they blend; tap a numbered one to take it out. Full,
                // a tap swaps the last one. Album is the cover's accent.
                StyledText { Layout.topMargin: Tokens.spacingSm; text: "Colours"; variant: "caption"; emphasis: "dim" }
                StyledText {
                    Layout.fillWidth: true
                    text: "Tap up to " + Config.cavaBgBlendMax + " — they blend in the order you pick them"
                    variant: "caption"
                    color: Colors.of(QsWindow.window).fgDim
                    wrapMode: Text.WordWrap
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: Config.cavaBgColors
                        CavaSwatch {
                            required property var modelData
                            choice: modelData
                            order: Config.cavaBlendClean(Config.cavaBgBlend).indexOf(modelData.id) + 1
                            onPicked: {
                                const b = Config.cavaBlendClean(Config.cavaBgBlend).slice()
                                const i = b.indexOf(modelData.id)
                                if (i >= 0) { if (b.length > 1) b.splice(i, 1) }
                                else if (b.length < Config.cavaBgBlendMax) b.push(modelData.id)
                                else b[b.length - 1] = modelData.id
                                Config.cavaBgBlend = b
                            }
                        }
                    }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm
                    ChipRow {
                        visible: Config.cavaBlendClean(Config.cavaBgBlend).length > 1
                        accent: Colors.of(QsWindow.window).primary
                        model: Config.cavaBgStyle === "ring"
                            ? [{ value: "across", label: "Round the ring" }, { value: "up", label: "Circle to tips" }]
                            : [{ value: "across", label: "Left to right" }, { value: "up", label: "Base to tips" }]
                        current: Config.cavaBgBlendDir === "up" ? "up" : "across"
                        onPicked: function(v) { Config.cavaBgBlendDir = v }
                    }
                    ChipButton {
                        label:  Translation.tr("Whole scheme")
                        symbol: "auto_awesome"
                        tint:   Colors.of(QsWindow.window).primary
                        onActivated: {
                            Config.cavaBgBlend = Config.cavaBgWholeScheme
                            Config.cavaBgBlendDir = "across"
                        }
                    }
                }
                Fader {
                    Layout.topMargin: Tokens.spacingXs
                    label:  Translation.tr("Opacity")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0.2; to: 1.0; step: 0.05
                    value:   Config.cavaBgOpacity
                    readout: Math.round(Config.cavaBgOpacity * 100) + "%"
                    onCommit: function(v) { Config.cavaBgOpacity = v }
                }
            }
        }

        Section {
            span:     3
            visible: Audio.ready && Audio.recordingApps.length > 0
            glyph:    "󰑊"
            title:    Translation.tr("Recording")
            subtitle: Translation.tr("Applications holding the microphone open.")
            accent:   Colors.of(QsWindow.window).primary

            ColumnLayout {
                id: recBox
                Layout.fillWidth: true
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

                            MaterialIcon {
                                glyph: "󰍬"
                                color: Colors.of(QsWindow.window).primary
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
                                value:  Audio.meterLevel(recPeaks.peak)
                                accent: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.75)
                                fillDuration: Motion.track
                            }
                        }
                    }
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
            tint:  s === current ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
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
        property color  tint:    Colors.of(QsWindow.window).primary

        // The node to meter. Null disables the meter entirely — the card is still a
        // perfectly good volume control without one.
        property var node: null

        signal setLevel(real value)
        signal stepLevel(int delta)
        signal toggled()

        PwNodePeakMonitor {
            id: cardPeak
            node:    card.node
            enabled: root.metering && card.node !== null && Audio.hasKnownChannels(card.node)
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
                    capsule: true
                    variant:   "ghost"
                    glyph:     card.glyph
                    glyphTint: card.isMuted ? Colors.of(QsWindow.window).fgDim : card.tint
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

            // ── How loud it may be, and whether anything is coming through ─────
            // Two things a mute button cannot tell apart: the fat slider is the ceiling
            // you set, the hairline under it is the live peak. Muted is a dim slider and
            // a flat line; silence is a lit slider and a flat line.
            ThickSlider {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                value:   card.level
                maximum: 1.0
                accent:  card.isMuted ? Colors.of(QsWindow.window).fgDim : card.tint
                onMoved:    function(v) { card.setLevel(v) }
                onScrolled: function(d) { card.stepLevel(d) }
            }
            Meter {
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                value:  card.isMuted ? 0 : Audio.meterLevel(cardPeak.peak)
                accent: card.tint
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
        property color tint:     Colors.of(QsWindow.window).primary
        signal picked()

        implicitHeight: Math.max(devRow.implicitHeight + Tokens.spacingSm * 2,
                                 Tokens.pillHeight)

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusSm
            color: dev.selected      ? Colors.of(QsWindow.window).alpha(dev.tint, 0.12)
                 : devHover.hovered  ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                                     : "transparent"
            border.width: dev.selected ? Tokens.borderWidth : 0
            border.color: Colors.of(QsWindow.window).alpha(dev.tint, 0.35)
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

            // A radio mark, not a checkbox: one device is the default, never several.
            MaterialIcon {
                name:  dev.selected ? "check_circle" : "radio_button_unchecked"
                fill:  dev.selected ? 1 : 0
                color: dev.selected ? dev.tint : Colors.of(QsWindow.window).fgDim
                font.pixelSize: Tokens.iconMd
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
    // ── One line per app ──────────────────────────────────────────────────────
    // Icon, name, where it plays, its level and mute, side by side. It was three lines
    // (name, route, slider), and three apps took most of the page.
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
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: stream.iconPath === ""
                    glyph:  "󰕾"                                // md-volume_high
                    color: Colors.of(QsWindow.window).primary
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

            RoutePill {
                id: routeBtn
                Layout.preferredWidth: 150
                visible: Audio.sinks.length > 1
                sink: stream.routedTo
                onPicked: root.openRouteMenu(routeBtn, stream.node)
            }

            ThickSlider {
                Layout.preferredWidth: 220
                Layout.preferredHeight: 26
                Layout.fillWidth: false
                value:   stream.vol
                maximum: 1.0
                accent:  stream.isMuted ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).primary
                // allowBoost false: the slider tops out at 100%, so it can't be used to
                // push a stream past unity and clip it. Audio.setNodeVolume takes the flag
                // because the equaliser wants boost; a settings page does not.
                onMoved:    function(v) { Audio.setNodeVolume(stream.node, v, false) }
                onScrolled: function(d) {
                    Audio.setNodeVolume(stream.node,
                                        stream.vol + d * root.wheelStep, false)
                }
            }

            StyledText {
                Layout.preferredWidth: 40
                horizontalAlignment: Text.AlignRight
                text: stream.isMuted ? "muted" : Math.round(stream.vol * 100) + "%"
                variant: "caption"
                emphasis: "dim"
            }

            PanelButton {
                capsule: true
                variant:   "ghost"
                glyph:     stream.isMuted ? "󰝟" : "󰕾"      // muted / speaker
                glyphTint: stream.isMuted ? Colors.of(QsWindow.window).fgDim : Colors.of(QsWindow.window).fg
                onActivated: Audio.toggleNodeMute(stream.node)
            }
        }
    }
    // One colour for the desktop spectrum's blend (Config.cavaBgColors): its colour (the
    // cover's for Album), and its place in the blend when it's in it (`order`, 1-based; 0 = not).
    component CavaSwatch: Rectangle {
        id: sw
        property var choice: ({ id: "", label: "" })
        property int order: 0
        signal picked()
        implicitWidth: Tokens.iconXl
        implicitHeight: Tokens.iconXl
        radius: Tokens.radiusSm
        color: sw.choice.id === "album" ? AlbumArt.accent
             : Colors.of(QsWindow.window).role(sw.choice.id, Colors.of(QsWindow.window).ramp3)
        border.width: sw.order > 0 ? 2 : Tokens.borderWidth
        border.color: sw.order > 0 ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).outline
        // Its place in the blend: a small badge, legible on any swatch.
        Rectangle {
            visible: sw.order > 0
            anchors.centerIn: parent
            width: Tokens.iconSm
            height: Tokens.iconSm
            radius: width / 2
            color: Colors.of(QsWindow.window).fg
            StyledText {
                anchors.centerIn: parent
                text: sw.order
                variant: "caption"
                color: Colors.of(QsWindow.window).base
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: sw.picked()
        }
    }
}
