pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"

// ── EqualizerPanel ────────────────────────────────────────────────────────────
// The audio mixer, in the Game Mode panel's Material 3 Expressive dialect (redone 2026-11-07; three earlier
// attempts were turned down — see docs/small-features.md — and the user then named the Game Mode panel as the look
// to copy). Three pages of a SegmentSwitch that slide past each other on one spring:
//
//   Mixer    the output as a hero: an M3E shape that swells with the sound (tap it to mute), the device, the level
//            and a thick fader, and one tap between outputs; then a ChannelCard per playing app — its orb is its
//            meter, then the fader, the output it plays through, and a pin that keeps it as it is (MixerMemory)
//   Devices  every output and input as a DeviceCard (tap = default; "Play apps here"; Options: a volume limit,
//            balance), the pinned apps, and Boost / per-output volume memory / Restart audio
//   Input    the microphone, a "hear yourself" test, and which apps are recording you
//
// The title row on top is `Config.mixerPanelHeader()` — Settings › Bar › Volume, like the Game Mode panel's. The
// switches the header used to carry (Boost, Restart audio) live on the Devices page, so nothing is lost with it off.
//
// ── It owns no state ──────────────────────────────────────────────────────────
// A view over the Audio service (native PipeWire: volume is read from a property and written by assigning one,
// PipeWire pushes — no timer, no subprocess) and MixerMemory (pins). Routing, codec and the mic test are the
// service's too (Audio.moveStream, bluetoothCodecOf, MicTest); this file only shows them.
//
// ── Two things the first attempt got wrong ────────────────────────────────────
// 1. Room. SidePanelDock cuts the panel to the room it has (`maxHeight`), so a list taller than that was simply
//    clipped and only the first app showed. The pages now sit in a Flickable no taller than the room.
// 2. The shell's own sound effects. Each cue is a `pw-play` process, which shows up as a playback stream for a few
//    hundred ms on every hover and keystroke. Bound straight to Audio.streams, the app list was rebuilt (and every
//    row's entrance replayed) with each one — a glitch whenever the sound effects were on. They are filtered
//    out here, and the list is a ScriptModel keyed by node id, so an app starting or stopping adds or removes
//    ITS row and nothing else moves.
//
// ── Meters cost, so they follow the page ──────────────────────────────────────
// A PwNodePeakMonitor asks PipeWire to keep streaming peak data for its node. Every meter is enabled only while its
// page is showing, and the dock's Loader tears the panel down on close.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    implicitWidth: Tokens.sideCardUnit * 12
    readonly property int margin: Tokens.spacingXl
    readonly property int cardPad: Tokens.spacingMd + Tokens.spacingXs
    implicitHeight: mainCol.implicitHeight + root.margin * 2

    // The room the dock has for this panel (SidePanelDock sets it). 0 = not told yet, no limit.
    property real maxHeight: 0

    readonly property color accent: Colors.of(QsWindow.window).primary
    readonly property color info: Colors.of(QsWindow.window).info

    property string page: "mixer"
    readonly property var _pageOrder: ["mixer", "devices", "input"]
    SpringValue { id: pg; target: root._pageOrder.indexOf(root.page); spec: Motion.springSpatial }

    // Output past 100%. Off by default; kept across reloads (Config.mixerBoost), and so is a boosted level
    // (Audio.qml restores it above 100% only while this is on). A boosted sink clips: turning it off pulls the
    // output back to 100% (onBoostChanged).
    readonly property bool boost: Config.mixerBoost
    readonly property real maxLevel: root.boost ? Math.round(Audio.boostCeiling * 100) : 100

    ArmLatch {
        id: restartLatch
        onConfirmed: Audio.restartStack()
    }

    // Turning boost off while the output is above unity would leave the slider pinned at full with the real
    // level out of reach of it.
    onBoostChanged: if (!root.boost && Audio.volume > 1) Audio.setVolume(1, false)

    // A loopback on speakers howls, and MicTest only stops itself after a minute. The panel closing is a good
    // moment to not leave it running.
    Component.onDestruction: MicTest.stop()

    // The apps playing, without the shell's own cues (see the header).
    readonly property var _apps: Audio.streams.filter(n => Audio.appIdFor(n) !== "pw-play")

    // ── App presentation ──────────────────────────────────────────────────────
    // Icon resolution lives in the Icons service (Audio.iconPathFor delegates to it): declared icon name →
    // desktop-entry lookup by process binary → "". The glyph below is the LAST resort, for an app that resolves
    // to no icon at all — it still names the app rather than saying "audio", which is the point.
    function glyphFor(node) {
        const n = Audio.labelFor(node).toLowerCase()
        if (n.includes("firefox") || n.includes("zen"))                              return "󰈹"
        if (n.includes("chrome") || n.includes("chromium"))                           return "󰊯"
        if (n.includes("spotify"))                                                    return "󰓇"
        if (n.includes("mpv"))                                                        return "󰎁"
        if (n.includes("vlc"))                                                        return "󰕼"
        if (n.includes("discord") || n.includes("vesktop") || n.includes("vencord"))  return "󰙯"
        if (n.includes("telegram"))                                                   return "󰔁"
        if (n.includes("steam"))                                                      return "󰓓"
        if (n.includes("lutris"))                                                     return "󰊗"
        if (n.includes("obs"))                                                        return "󰐋"
        if (n.includes("zoom") || n.includes("teams"))                                return "󰤅"
        return "󰓃"
    }

    // ── Route picker ──────────────────────────────────────────────────────────
    // One menu for the whole panel, not one per card: a ContextMenu per card would build a menu for every stream
    // whether or not anyone opens one. The stream is held here while it's open because `triggered` only carries a
    // string key — the sink's NAME, which is stable and is what the move takes.
    property var _routeStream: null

    function openRouteMenu(anchorItem, stream) {
        root._routeStream = stream
        const current = Audio.sinkOf(stream)

        routeMenu.items = Audio.sinks.map(s => ({
            key: s.name,
            // Short name + profile, not the 60-character description. The profile is what distinguishes two
            // outputs on the same card.
            label: Audio.shortLabelFor(s)
                 + (Audio.profileOf(s) ? "  ·  " + Audio.profileOf(s) : "")
                 + (s === current ? "   ✓" : ""),
            glyph: Audio.deviceGlyph(s),
            tint:  s === current ? Colors.of(QsWindow.window).info : Colors.of(QsWindow.window).fg
        }))

        const p = anchorItem.mapToItem(root, 0, anchorItem.height)
        routeMenu.openAt(p.x, p.y)
    }

    // The pinned apps, newest first, for the Devices page.
    readonly property var _pins: Object.keys(MixerMemory.apps)
        .map(k => Object.assign({ key: k }, MixerMemory.apps[k]))
        .sort((a, b) => b.at - a.at)
    function _pinLine(rec) {
        const sink = rec.sink !== "" ? Audio.sinks.find(s => s.name === rec.sink) : null
        return Math.round(rec.level * 100) + "%" + (rec.muted ? " · muted" : "")
             + (rec.sink !== "" ? " · " + (sink ? Audio.shortLabelFor(sink) : "output not connected") : "")
    }

    readonly property string _subtitle: !Audio.ready ? "PipeWire unavailable"
        : restartLatch.armed ? "Tap again to restart audio — output will cut out"
        : Audio.restarting ? "Restarting audio…"
        : Audio.muted ? "Output muted"
        : Math.round(Audio.volume * 100) + "%  ·  " + Audio.shortLabelFor(Audio.sink) + "  ·  "
          + (root._apps.length === 1 ? "1 app playing" : root._apps.length + " apps playing")

    ColumnLayout {
        id: mainCol
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.margin
        spacing: Tokens.spacingSm

        // ── Header (Settings › Bar › Volume hides it) ─────────────────────────
        PanelHeader {
            id: header
            Layout.fillHeight: false
            visible: Config.mixerPanelHeader()
            symbol: "volume_up"
            title: Translation.tr("Audio")
            titleTail: Translation.tr("Mixer")
            accent: root.accent
            subtitle: root._subtitle
        }

        // ── Pages ─────────────────────────────────────────────────────────────
        // A dot on Input says an app is recording you, from any page (`lit`).
        SegmentSwitch {
            id: tabs
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: implicitHeight
            accent: root.accent
            model: [
                { value: "mixer",   label: "Mixer",   icon: "tune" },
                { value: "devices", label: "Devices", icon: "speaker" },
                { value: "input",   label: "Input",   icon: "mic", lit: Audio.recordingApps.length > 0 }
            ]
            current: root.page
            onPicked: function (value) { root.page = value }
        }

        Item {
            id: pagesBox
            Layout.fillWidth: true
            Layout.fillHeight: false
            clip: true
            // As tall as the page you are on, within the room the dock has: past that the page scrolls. It
            // follows the page on a spring (no overshoot — a panel that bounces its own size reads as a glitch).
            readonly property real wanted: [mixerPage, devicesPage, inputPage][Math.max(0, root._pageOrder.indexOf(root.page))].implicitHeight
            readonly property real chrome: root.margin * 2 + tabs.height + mainCol.spacing
                                           + (header.visible ? header.height + mainCol.spacing : 0)
            readonly property real room: root.maxHeight > 0 ? Math.max(Tokens.sideCardUnit * 3, root.maxHeight - pagesBox.chrome)
                                                            : 100000
            implicitHeight: Math.min(hv.value, pagesBox.room)
            SpringValue { id: hv; target: pagesBox.wanted; spec: Motion.springEffects; epsilon: 0.5 }
            Component.onCompleted: hv.jump(pagesBox.wanted)

            Flickable {
                id: pageFlick
                anchors.fill: parent
                contentWidth: width
                contentHeight: hv.value
                interactive: hv.value > pagesBox.height + 1
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                // ══ MIXER ═════════════════════════════════════════════════════
                ColumnLayout {
                    id: mixerPage
                    readonly property int idx: 0
                    width: pagesBox.width
                    x: (mixerPage.idx - pg.value) * pagesBox.width
                    opacity: Math.max(0, 1 - Math.abs(mixerPage.idx - pg.value) * 1.4)
                    visible: mixerPage.opacity > 0.01
                    spacing: Tokens.spacingSm

                    // ── Hero: the output ──────────────────────────────────────
                    Rectangle {
                        id: hero
                        Layout.fillWidth: true
                        implicitHeight: heroCol.implicitHeight + root.cardPad * 2
                        radius: Tokens.radiusXl
                        // Neutral: the shape and the fader carry the accent. A filled accent card reads very loud
                        // on a saturated wallpaper.
                        color: Colors.of(QsWindow.window).section

                        readonly property real heard: Audio.meterLevel(sinkPeak.peak)
                        // Holds for a beat after the signal drops, so a quiet passage does not flap the shape.
                        property bool audible: false
                        property bool clip: false
                        Timer { id: heroHold; interval: 1200; onTriggered: hero.audible = false }
                        Timer { id: heroClip; interval: 1500; onTriggered: hero.clip = false }

                        PwNodePeakMonitor {
                            id: sinkPeak
                            node: Audio.sink
                            enabled: mixerPage.visible && Audio.ready && Audio.hasKnownChannels(Audio.sink)
                            onPeakChanged: {
                                if (Audio.muted) return
                                if (sinkPeak.peak > 0.02) { hero.audible = true; heroHold.restart() }
                                if (sinkPeak.peak >= 0.95) { hero.clip = true; heroClip.restart() }
                            }
                        }

                        ColumnLayout {
                            id: heroCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.cardPad
                            spacing: Tokens.spacingMd

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingLg

                                // The output as a shape: a disc when muted, a nine-petal cookie at rest, a
                                // sunburst while sound comes out — and it swells with the level. Tap it to mute.
                                Item {
                                    Layout.alignment: Qt.AlignVCenter
                                    Layout.preferredWidth: Tokens.iconXl * 2 + Tokens.spacingMd
                                    Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingMd
                                    SpringValue { id: heroPress; target: heroTap.pressed ? 1 : 0; spec: Motion.springSpatialFast }
                                    scale: (1 - heroPress.value * 0.08) + (hero.audible && !Audio.muted ? hero.heard * 0.14 : 0)
                                    Behavior on scale { NumberAnimation { duration: Motion.track } }

                                    MorphShape {
                                        anchors.fill: parent
                                        shape: Audio.muted ? "circle" : hero.audible ? "sunny" : "cookie9"
                                        fillColor: Audio.muted ? Colors.of(QsWindow.window).surfaceHigh : root.accent
                                    }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        glyph: Audio.glyph(Audio.volume, Audio.muted)
                                        fill: Audio.muted ? 0 : 1
                                        font.pixelSize: Tokens.iconXl
                                        color: Audio.muted ? Colors.of(QsWindow.window).fgMuted : Colors.of(QsWindow.window).fgOnPrimary
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { id: heroTap; enabled: Audio.ready; onTapped: Audio.toggleMute() }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: Tokens.spacingXs

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: false
                                        spacing: Tokens.spacingSm

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            spacing: 0
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Audio.shortLabelFor(Audio.sink)
                                                variant: "title"
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Audio.muted ? "Muted — tap the shape to unmute"
                                                    : root._apps.length === 0 ? "Nothing playing"
                                                    : root._apps.length === 1 ? "1 app playing" : root._apps.length + " apps playing"
                                                variant: "caption"
                                                emphasis: "dim"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Badge {
                                            visible: Audio.bluetoothCodecOf(Audio.sink) !== ""
                                            label: Audio.bluetoothCodecOf(Audio.sink)
                                            tint: root.accent
                                        }
                                        Badge {
                                            visible: Audio.capOf(Audio.sink) > 0
                                            label: "Limit " + Math.round(Audio.capOf(Audio.sink) * 100) + "%"
                                            tint: Colors.of(QsWindow.window).warning
                                        }

                                        RollText {
                                            Layout.alignment: Qt.AlignVCenter
                                            text: Audio.muted ? "Muted" : Math.round(Audio.volume * 100) + "%"
                                            family: Tokens.fontMono
                                            pixelSize: Tokens.fontTitle + Tokens.spacingMd
                                            weight: Font.DemiBold
                                            color: hero.clip ? Colors.of(QsWindow.window).danger
                                                 : Audio.volume > 1 ? Colors.of(QsWindow.window).warning
                                                 : Colors.of(QsWindow.window).fg
                                        }
                                    }

                                    ValueSlider {
                                        Layout.fillWidth: true
                                        thickness: Tokens.spacingMd
                                        value: Audio.volume * 100
                                        maximum: root.maxLevel
                                        // A limit shows as the tick, in place of the unity one: that's the point
                                        // the fader can't pass. Unity matters only while boosting.
                                        notchAt: Audio.capOf(Audio.sink) > 0 ? Audio.capOf(Audio.sink) * 100
                                                                             : (root.maxLevel > 100 ? 100 : 0)
                                        accent: Audio.muted ? Colors.of(QsWindow.window).fgDim : root.accent
                                        onMoved: function (v) { Audio.setVolume(v / 100, root.boost) }
                                        onScrolled: function (d) { Audio.setVolume((Audio.volume * 100 + d * 5) / 100, root.boost) }
                                    }
                                }
                            }

                            // ── Play through: one tap between outputs ─────────
                            Flow {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                visible: Audio.sinks.length > 1
                                spacing: Tokens.spacingSm

                                Repeater {
                                    model: Audio.sinks
                                    delegate: Rectangle {
                                        id: sinkChip
                                        required property var modelData
                                        readonly property bool on: sinkChip.modelData === Audio.sink
                                        implicitHeight: Tokens.iconMd + Tokens.spacingMd * 2
                                        implicitWidth: Math.min(chipRow.implicitWidth + Tokens.spacingLg * 2, hero.width * 0.46)
                                        radius: height / 2
                                        color: sinkChip.on ? Colors.of(QsWindow.window).alpha(root.accent, 0.22)
                                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, chipHover.hovered ? 0.12 : 0.07)
                                        border.width: sinkChip.on ? Tokens.borderWidth : 0
                                        border.color: root.accent
                                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                                        RowLayout {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            width: Math.min(implicitWidth, sinkChip.width - Tokens.spacingLg * 2)
                                            spacing: Tokens.spacingSm
                                            MaterialIcon {
                                                glyph: Audio.deviceGlyph(sinkChip.modelData)
                                                fill: sinkChip.on ? 1 : 0
                                                font.pixelSize: Tokens.iconMd
                                                color: sinkChip.on ? root.accent : Colors.of(QsWindow.window).fgMuted
                                            }
                                            StyledText {
                                                Layout.fillWidth: true
                                                text: Audio.shortLabelFor(sinkChip.modelData)
                                                variant: "caption"
                                                font.weight: Font.DemiBold
                                                color: sinkChip.on ? root.accent : Colors.of(QsWindow.window).fg
                                                elide: Text.ElideRight
                                            }
                                        }
                                        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: Audio.setDefaultSink(sinkChip.modelData) }
                                    }
                                }
                            }
                        }
                    }

                    // ── The apps ──────────────────────────────────────────────
                    // Without PipeWire neither the list nor the empty card below shows: no
                    // heading over nothing (the panel's subtitle already says why).
                    Heading {
                        visible: Audio.ready
                        text: root._apps.length > 0 ? "Playing now · " + root._apps.length : "Playing now"
                    }

                    // Nothing playing: a quiet card rather than a bare line.
                    Rectangle {
                        Layout.fillWidth: true
                        visible: Audio.ready && root._apps.length === 0
                        implicitHeight: emptyRow.implicitHeight + root.cardPad * 2
                        radius: Tokens.radiusCard
                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                        RowLayout {
                            id: emptyRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.cardPad
                            spacing: Tokens.spacingMd
                            Item {
                                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingLg
                                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg
                                MorphShape {
                                    anchors.fill: parent
                                    shape: "cookie9"
                                    fillColor: Colors.of(QsWindow.window).surfaceHigh
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "volume_mute"
                                    font.pixelSize: Tokens.iconLg
                                    color: Colors.of(QsWindow.window).fgMuted
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText { text: "Nothing is playing"; variant: "body"; font.weight: Font.DemiBold }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("An app gets its own card here the moment it makes sound.")
                                    variant: "caption"; emphasis: "dim"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    Repeater {
                        model: ScriptModel { values: root._apps; objectProp: "id" }
                        delegate: Item {
                            id: appRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: card.implicitHeight

                            // A new app fades in; the others stay exactly where they are.
                            opacity: 0
                            Component.onCompleted: opacity = 1
                            Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                            ChannelCard {
                                id: card
                                width: parent.width
                                node: appRow.modelData
                                metering: mixerPage.visible && Audio.ready
                                label: Audio.labelFor(appRow.modelData)
                                subLabel: Audio.sinkOf(appRow.modelData) ? "→ " + Audio.shortLabelFor(Audio.sinkOf(appRow.modelData)) : ""
                                iconPath: Audio.iconPathFor(appRow.modelData)
                                glyph: root.glyphFor(appRow.modelData)
                                accent: root.info
                                shape: "cookie7"
                                level: Audio.levelOf(appRow.modelData) * 100
                                muted: appRow.modelData.audio?.muted ?? false
                                maximum: root.maxLevel
                                pinnable: MixerMemory.keyOf(appRow.modelData) !== ""
                                pinned: MixerMemory.pinned(appRow.modelData)

                                // Only when there's somewhere else to send it.
                                RoutePill {
                                    id: routePill
                                    visible: Audio.sinks.length > 1
                                    sink: Audio.sinkOf(appRow.modelData)
                                    accent: root.info
                                    onPicked: root.openRouteMenu(routePill, appRow.modelData)
                                }

                                onToggled: {
                                    const was = card.muted
                                    Audio.toggleNodeMute(appRow.modelData)
                                    MixerMemory.note(appRow.modelData, { muted: !was })
                                }
                                // Same boost switch as the output: past 100% a stream clips, so it's opt-in here too.
                                onSetLevel: function (v) {
                                    Audio.setNodeVolume(appRow.modelData, v / 100, root.boost)
                                    MixerMemory.note(appRow.modelData, { level: v / 100 })
                                }
                                onPinToggled: {
                                    if (card.pinned) MixerMemory.unpin(appRow.modelData)
                                    else MixerMemory.pin(appRow.modelData)
                                }
                            }
                        }
                    }
                }

                // ══ DEVICES ═══════════════════════════════════════════════════
                ColumnLayout {
                    id: devicesPage
                    readonly property int idx: 1
                    width: pagesBox.width
                    x: (devicesPage.idx - pg.value) * pagesBox.width
                    opacity: Math.max(0, 1 - Math.abs(devicesPage.idx - pg.value) * 1.4)
                    visible: devicesPage.opacity > 0.01
                    spacing: Tokens.spacingSm

                    Heading { text: Translation.tr("Output") }
                    Repeater {
                        model: Audio.sinks

                        ColumnLayout {
                            id: sinkItem
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Tokens.spacingXs

                            property bool editing: false
                            readonly property real cap: Audio.capOf(sinkItem.modelData)
                            // Balance needs a front L/R pair, which a mono or surround device lacks.
                            readonly property bool canBalance: Audio.canBalanceNode(sinkItem.modelData)

                            DeviceCard {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                node: sinkItem.modelData
                                current: Audio.sink
                                isSink: true
                                cap: sinkItem.cap
                                editing: sinkItem.editing
                                canMove: root._apps.some(s => Audio.sinkOf(s) !== sinkItem.modelData)
                                onPicked: Audio.setDefaultSink(sinkItem.modelData)
                                onMoveHere: Audio.moveAllStreams(sinkItem.modelData)
                                onOptionsToggled: sinkItem.editing = !sinkItem.editing
                            }

                            // ── Options for this output ───────────────────────
                            // Opened by the "Options" button; grows open rather than appearing. Presets rather
                            // than a slider: a limit is a decision ("keep my headphones under 60%"), not a
                            // quantity.
                            Rectangle {
                                id: optionsCard
                                Layout.fillWidth: true
                                Layout.preferredHeight: sinkItem.editing ? optionsCol.implicitHeight + root.cardPad * 2 : 0
                                opacity: sinkItem.editing ? 1 : 0
                                visible: optionsCard.Layout.preferredHeight > 0.5 || sinkItem.editing
                                clip: true
                                radius: Tokens.radiusCard
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
                                border.width: Tokens.borderWidth
                                border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                Behavior on Layout.preferredHeight { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                                ColumnLayout {
                                    id: optionsCol
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: root.cardPad
                                    spacing: Tokens.spacingMd

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: false
                                        spacing: Tokens.spacingSm
                                        StyledText { text: "Maximum volume"; variant: "caption"; font.weight: Font.DemiBold }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("Volume can't go above this on this output.")
                                            variant: "caption"; emphasis: "dim"
                                        }
                                        ChipRow {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            accent: Colors.of(QsWindow.window).warning
                                            current: sinkItem.cap > 0 ? Math.round(sinkItem.cap * 100) : 0
                                            model: [
                                                { value: 0,  label: "No limit" },
                                                { value: 40, label: "40%" },
                                                { value: 60, label: "60%" },
                                                { value: 80, label: "80%" }
                                            ]
                                            onPicked: (v) => Audio.setCap(sinkItem.modelData, v / 100)
                                        }
                                    }

                                    // Only for an output that has a left/right pair.
                                    ColumnLayout {
                                        id: balBox
                                        Layout.fillWidth: true
                                        Layout.fillHeight: false
                                        visible: sinkItem.canBalance
                                        spacing: Tokens.spacingSm

                                        readonly property real balance: Audio.balanceOf(sinkItem.modelData)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            StyledText { Layout.fillWidth: true; text: "Balance"; variant: "caption"; font.weight: Font.DemiBold }
                                            StyledText {
                                                text: Math.abs(balBox.balance) < 0.01 ? "Centred"
                                                    : Math.round(Math.abs(balBox.balance) * 100) + "% " + (balBox.balance < 0 ? "left" : "right")
                                                variant: "caption"; emphasis: "dim"
                                            }
                                            PanelButton {
                                                visible: Math.abs(balBox.balance) >= 0.01
                                                variant: "ghost"
                                                label: Translation.tr("Centre")
                                                onActivated: Audio.centreBalance(sinkItem.modelData)
                                            }
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: false
                                            spacing: Tokens.spacingMd
                                            StyledText { text: "L"; variant: "caption"; emphasis: "dim" }
                                            ValueSlider {
                                                Layout.fillWidth: true
                                                // −1..+1 folded onto 0..1; the notch marks centre.
                                                value: (balBox.balance + 1) / 2
                                                maximum: 1.0
                                                notchAt: 0.5
                                                accent: root.accent
                                                onMoved: function (v) { Audio.setBalance(sinkItem.modelData, v * 2 - 1) }
                                                onScrolled: function (d) { Audio.setBalance(sinkItem.modelData, balBox.balance + d * 0.05) }
                                            }
                                            StyledText { text: "R"; variant: "caption"; emphasis: "dim" }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Heading { text: Translation.tr("Input") }
                    Repeater {
                        model: Audio.sources
                        DeviceCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            node: modelData
                            current: Audio.source
                            accent: root.info
                            onPicked: Audio.setDefaultSource(modelData)
                        }
                    }
                    StyledText {
                        visible: Audio.sources.length === 0
                        text: Translation.tr("No input devices.")
                        variant: "caption"; emphasis: "dim"
                    }

                    // ── Remembered apps ───────────────────────────────────────
                    Heading { text: root._pins.length > 0 ? "Remembered apps · " + root._pins.length : "Remembered apps" }
                    StyledText {
                        Layout.fillWidth: true
                        visible: root._pins.length === 0
                        text: Translation.tr("Pin an app on the Mixer page and it starts at the level and output you left it on.")
                        variant: "caption"; emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                    Repeater {
                        model: root._pins
                        delegate: Rectangle {
                            id: pinRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: pinLine.implicitHeight + Tokens.spacingMd * 2
                            radius: Tokens.radiusCard
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

                            RowLayout {
                                id: pinLine
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.spacingMd
                                spacing: Tokens.spacingMd

                                MaterialIcon { name: "push_pin"; fill: 1; font.pixelSize: Tokens.iconMd; color: root.info }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: pinRow.modelData.name !== "" ? pinRow.modelData.name : pinRow.modelData.key
                                        variant: "caption"
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: root._pinLine(pinRow.modelData)
                                        variant: "caption"; emphasis: "dim"
                                        elide: Text.ElideRight
                                    }
                                }
                                PanelButton {
                                    variant: "ghost"
                                    label: Translation.tr("Forget")
                                    onActivated: MixerMemory.forgetKey(pinRow.modelData.key)
                                }
                            }
                        }
                    }

                    // ── Behaviour ─────────────────────────────────────────────
                    Heading { text: Translation.tr("Behaviour") }
                    ShapeTile {
                        symbol: "volume_up"
                        shape: "burst"
                        accent: Colors.of(QsWindow.window).warning
                        label: Translation.tr("Boost past 100%")
                        subLabel: Config.mixerBoost ? "Faders go to " + Math.round(Audio.boostCeiling * 100) + "% — it can distort"
                                                    : "Faders stop at 100%"
                        active: Config.mixerBoost
                        available: Audio.ready
                        help: Translation.tr("Lets the output and each app go past 100%. A boosted level is kept across reloads while this is on.")
                        onToggled: Config.mixerBoost = !Config.mixerBoost
                    }
                    ShapeTile {
                        symbol: "speaker"
                        shape: "squircle"
                        label: Translation.tr("Remember each output's volume")
                        subLabel: Config.audioRememberLevels ? "Switching outputs puts each one back" : "The level carries over"
                        active: Config.audioRememberLevels
                        help: Translation.tr("Switching outputs puts each one back where you left it.")
                        onToggled: Config.audioRememberLevels = !Config.audioRememberLevels
                    }

                    // Two-step: restarting the stack drops audio for a second or two and apps holding a stream may
                    // not recover on their own, so a stray click costs a second one.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: restartRow.implicitHeight + root.cardPad * 2
                        radius: Tokens.radiusCard
                        color: restartLatch.armed ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.18)
                                                  : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        RowLayout {
                            id: restartRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.cardPad
                            spacing: Tokens.spacingMd
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText { text: "Restart audio"; variant: "body"; font.weight: Font.DemiBold }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: restartLatch.armed ? "Sound cuts out for a second or two"
                                                             : "A device missing, a stream stuck silent"
                                    variant: "caption"; emphasis: "dim"
                                    elide: Text.ElideRight
                                }
                            }
                            PanelButton {
                                variant: restartLatch.armed ? "primary" : "ghost"
                                accent: Colors.of(QsWindow.window).warning
                                symbol: "restart_alt"
                                symbolFill: restartLatch.armed ? 1 : 0
                                label: restartLatch.armed ? "Tap again" : "Restart"
                                enabled: Audio.ready && !Audio.restarting
                                onActivated: restartLatch.trigger()
                            }
                        }
                    }
                }

                // ══ INPUT ═════════════════════════════════════════════════════
                ColumnLayout {
                    id: inputPage
                    readonly property int idx: 2
                    width: pagesBox.width
                    x: (inputPage.idx - pg.value) * pagesBox.width
                    opacity: Math.max(0, 1 - Math.abs(inputPage.idx - pg.value) * 1.4)
                    visible: inputPage.opacity > 0.01
                    spacing: Tokens.spacingSm

                    ChannelCard {
                        node: Audio.source
                        metering: inputPage.visible && Audio.ready
                        symbol: Audio.micMuted ? "mic_off" : "mic"
                        label: Audio.shortLabelFor(Audio.source)
                        subLabel: "Microphone"
                        accent: root.info
                        shape: "cookie9"
                        level: Audio.micVolume * 100
                        muted: Audio.micMuted
                        onToggled: Audio.toggleMicMute()
                        onSetLevel: function (v) { Audio.setMicVolume(v / 100) }
                    }

                    // ── Hear yourself ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: testCol.implicitHeight + root.cardPad * 2
                        radius: Tokens.radiusCard
                        color: MicTest.running ? Colors.of(QsWindow.window).alpha(root.info, 0.14)
                                               : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                        Behavior on color { ColorAnimation { duration: Motion.standard } }

                        ColumnLayout {
                            id: testCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: root.cardPad
                            spacing: Tokens.spacingSm

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingMd

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: false
                                    spacing: 0
                                    StyledText { text: "Hear yourself"; variant: "body"; font.weight: Font.DemiBold }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: MicTest.running ? "Stops in " + MicTest.remaining + "s"
                                                              : "Play your microphone back through the output."
                                        variant: "caption"; emphasis: "dim"
                                        elide: Text.ElideRight
                                    }
                                }
                                PanelButton {
                                    variant: MicTest.running ? "primary" : "normal"
                                    accent: root.info
                                    symbol: MicTest.running ? "stop" : "headphones"
                                    label: MicTest.running ? "Stop" : "Listen"
                                    enabled: Audio.source !== null
                                    onActivated: MicTest.toggle()
                                }
                            }

                            // Its OWN cava, on the input device — the shared one analyses the output and would
                            // draw the music, not your voice. Runs only while the test does.
                            Spectrum {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Tokens.sideCardUnit
                                visible: MicTest.running
                                levels: micCava.bars
                                barCount: micCava.barCount
                                barGap: Tokens.spacingXs + 1
                                accent: root.info
                            }

                            // Only while it matters: a warning sitting there permanently is one you stop reading.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                visible: MicTest.running
                                spacing: Tokens.spacingSm
                                MaterialIcon { name: "warning"; variant: "caption"; color: Colors.of(QsWindow.window).warning }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("On speakers this will howl — headphones only.")
                                    color: Colors.of(QsWindow.window).warning
                                    variant: "caption"
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }

                    // ── Who's listening ───────────────────────────────────────
                    Heading { text: Audio.recordingApps.length > 0 ? "Recording · " + Audio.recordingApps.length : "Recording" }
                    StyledText {
                        visible: Audio.recordingApps.length === 0
                        text: Translation.tr("No app is using the microphone.")
                        variant: "caption"; emphasis: "dim"
                    }

                    // One row per APP, not per stream — see Audio.recordingApps.
                    Repeater {
                        model: Audio.recordingApps

                        Rectangle {
                            id: recRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: recLine.implicitHeight + Tokens.spacingMd * 2
                            radius: Tokens.radiusCard
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

                            // Watches every one of the app's streams, so the meter doesn't read flat when the live
                            // one is the second.
                            PeakGroup {
                                id: recPeaks
                                nodes: recRow.modelData.nodes
                                active: inputPage.visible && Audio.ready
                            }

                            RowLayout {
                                id: recLine
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: Tokens.spacingMd
                                spacing: Tokens.spacingMd

                                MaterialIcon { name: "mic"; fill: 1; font.pixelSize: Tokens.iconMd; color: root.info }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Audio.labelFor(recRow.modelData.node)
                                    variant: "caption"
                                    font.weight: Font.DemiBold
                                    elide: Text.ElideRight
                                }
                                // Only for an app holding more than one stream.
                                StyledText {
                                    visible: recRow.modelData.count > 1
                                    text: "×" + recRow.modelData.count
                                    variant: "caption"; emphasis: "dim"
                                }
                                // Fixed width: a meter that resized with the longest name would jitter as the list changes.
                                Meter {
                                    Layout.preferredWidth: Tokens.sideCardUnit * 2
                                    implicitHeight: Tokens.spacingXs * 2
                                    value: Audio.meterLevel(recPeaks.peak)
                                    accent: root.info
                                    fillDuration: Motion.track
                                }
                            }
                        }
                    }
                }
            }
            Scrollbar { flickable: pageFlick }
        }
    }

    CavaStream {
        id: micCava
        source: Audio.source ? Audio.source.name : ""
        running: MicTest.running
    }

    ContextMenu {
        id: routeMenu
        anchors.fill: parent
        // Measured on SoundPage: the longest real label ("HD-Audio Generic  ·  Digital Stereo (IEC958)   ✓")
        // needs ~400 or it elides.
        menuWidth: 400

        onTriggered: function (key) {
            const sink = Audio.sinks.filter(s => s.name === key)[0]
            if (sink && root._routeStream) {
                Audio.moveStream(root._routeStream, sink)
                MixerMemory.note(root._routeStream, { sink: sink.name })
            }
            root._routeStream = null
        }
    }

    // ── Heading ───────────────────────────────────────────────────────────────
    // A small section title — VoicePanel's, so the panels read alike.
    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        variant: "caption"
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
        emphasis: "muted"
    }
}
