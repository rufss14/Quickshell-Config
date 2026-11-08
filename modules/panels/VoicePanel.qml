pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── VoicePanel ────────────────────────────────────────────────────────────────
// The Discord call, beside the sidebar's Voice module (SidePanelDock). Two faces on a
// TabStrip:
//
//   People      everyone in the call. A row opens (one at a time) on a click — or, when
//               the panel was opened on a person (a right-click on their face,
//               UiState.sidePanelArg), on them — with their controls FOR YOU: a mute
//               that keeps their level for when you unmute, their volume (0–200%, 100
//               marked, with quick presets) and their balance (left … right). Your own
//               row leads to the other tab.
//   Your audio  your mic (with a live level, the "am I coming through?" check) and
//               output, which devices, voice activity or push-to-talk, and Discord's
//               noise suppression / echo cancellation / automatic gain.
//
// Over the tabs, a strip says how the call is doing (connection, ping, how long) and
// holds open-Discord, screen share and camera. Those last two are KEYSTROKES, not RPC
// (Discord has no command for either — services/Discord's quarantine); the panel steps
// aside first so the keystroke lands in Discord, and hovering one that can't work says
// why in the strip.
//
// ── Motion ────────────────────────────────────────────────────────────────────
// People arrive and leave as the dock's icons do (in rising, out fading, the rest
// closing up); the list's first build is staggered. A row opens on the surface curve
// with its controls fading in behind; the tabs crossfade and slide toward the side you
// picked, and only a tab switch eases the panel's height (a row opening already moves
// it smoothly, and easing that too would chase — Motion's one rule).
//
// While a slider is dragged it shows what you're asking for, and for a moment after,
// until Discord's answer catches up (otherwise the handle snaps back to the old level
// for a beat).
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets
// (Avatar, ValueSlider, PanelButton, ArmLatch, TabStrip, Toggle, Meter). Everything
// real is services/Discord (scripts/discord-rpc.py); this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The room the slot has (SidePanelDock sets it); the bodies scroll past it.
    property real maxHeight: Infinity

    readonly property int pad: Tokens.spacingLg
    implicitWidth: Tokens.sideCardUnit * 7
    implicitHeight: Math.min(root.maxHeight, col.implicitHeight + root.pad * 2)

    readonly property real bodyRoom: Math.max(Tokens.sideCardUnit * 2, Math.min(Tokens.sideCardUnit * 10,
        root.maxHeight - root.pad * 2 - head.implicitHeight - strip.implicitHeight
        - tabs.implicitHeight - col.spacing * 3))

    // ── Which face ────────────────────────────────────────────────────────────
    property string tab: "people"
    readonly property int tabIndex: root.tab === "people" ? 0 : 1
    // Held for one surface beat after a switch: the only time the body's height eases.
    property bool switching: false
    Timer { id: switchBeat; interval: Math.max(1, Motion.emphasized); onTriggered: root.switching = false }
    function show(t) {
        if (t === root.tab) return
        root.switching = true
        switchBeat.restart()
        root.tab = t
    }

    // The open row's person ("" for none): who it was opened on, then your clicks.
    property string expanded: UiState.sidePanelArg
    Connections {
        target: UiState
        function onSidePanelArgChanged() {
            if (UiState.sidePanel === "voice" && UiState.sidePanelArg !== "") {
                root.expanded = UiState.sidePanelArg
                root.show("people")
            }
        }
    }

    // The call ended: nothing left to show.
    Connections {
        target: Discord
        function onInCallChanged() {
            if (!Discord.inCall && UiState.sidePanel === "voice") UiState.closeSidePanel()
        }
    }

    // The call's duration counts seconds, only while this is open.
    Component.onCompleted: Clock.acquireSeconds()
    Component.onDestruction: Clock.releaseSeconds()

    ArmLatch {
        id: leaveLatch
        onConfirmed: Discord.disconnect()
    }

    // ── The strip's hint ──────────────────────────────────────────────────────
    // Claimed on enter, released on exit — only by its owner, since leaving one button
    // and entering the next fire in that order (DiscordCallBar's rule).
    property string tip: ""
    function setTip(on, t) {
        if (on) root.tip = t
        else if (root.tip === t) root.tip = ""
    }

    // A keystroke into Discord: out of the way first, so it has the keyboard.
    function press(spec) {
        UiState.closeSidePanel()
        Discord.pressInDiscord(spec)
    }

    readonly property color qualityColor: Discord.quality === "good" ? Colors.of(QsWindow.window).success
                                        : Discord.quality === "bad"  ? Colors.of(QsWindow.window).danger
                                        : Discord.quality === "connecting" ? Colors.of(QsWindow.window).warning
                                        : Colors.of(QsWindow.window).fgMuted
    readonly property string qualityText: Discord.quality === "good" ? "Connected"
                                        : Discord.quality === "bad"  ? "Connection trouble"
                                        : Discord.quality === "connecting" ? "Connecting…"
                                        : "Not in a call"

    ColumnLayout {
        id: col
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: root.pad
        spacing: Tokens.spacingMd

        PanelHeader {
            id: head
            Layout.fillHeight: false
            glyph:     "\u{F02CB}"                                           // 󰋋 headphones
            title:     Translation.tr("Voice")
            titleTail: "call"
            accent:    Colors.of(QsWindow.window).primary
            subtitle: {
                if (Discord.lastError !== "") return Discord.lastError
                if (!Discord.inCall) return "Not in a call"
                return Discord.guildName !== "" ? Discord.callTitle + " · " + Discord.guildName
                                                : Discord.callTitle
            }

            ActionGroup {
                groupShown: Discord.inCall
                PanelButton {
                    variant: Discord.mute ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).danger
                    symbol:  Discord.mute ? "mic_off" : "mic"
                    onActivated: Discord.toggleMute()
                }
                PanelButton {
                    variant: Discord.deaf ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).danger
                    symbol:  "headphones"
                    onActivated: Discord.toggleDeaf()
                }
                PanelButton {
                    variant: leaveLatch.armed ? "primary" : "ghost"
                    accent:  Colors.of(QsWindow.window).danger
                    symbol:  "logout"
                    label:   leaveLatch.armed ? "Leave?" : ""
                    onActivated: leaveLatch.trigger()
                }
            }
        }

        // ── Not in a call ─────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingMd
            Layout.bottomMargin: Tokens.spacingMd
            visible: !Discord.inCall
            spacing: Tokens.spacingSm
            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                glyph: "\u{F07CE}"                                            // 󰟎 headphones-off
                font.pixelSize: Tokens.fontNumeralMd
                color: Colors.of(QsWindow.window).fgDim
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Discord.needsAttention ? "Discord needs setting up — Settings › Discord."
                    : !Discord.connected ? "Discord isn't running, or isn't connected yet."
                    : "Join a voice channel or a call and it shows up here."
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }
        }

        // ── How the call is doing ─────────────────────────────────────────────
        RowLayout {
            id: strip
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: Discord.inCall
            spacing: Tokens.spacingSm

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: stripRow.implicitHeight + Tokens.spacingSm * 2
                radius: Tokens.radiusSm
                color: Colors.of(QsWindow.window).alpha(root.tip !== "" ? Colors.of(QsWindow.window).warning : root.qualityColor, 0.10)
                Behavior on color { ColorAnimation { duration: Motion.standard } }

                RowLayout {
                    id: stripRow
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    // The connection's dot — breathing while it's still connecting
                    // (a looping animation, so gated on motion: off, it just sits).
                    Rectangle {
                        id: dot
                        implicitWidth: Tokens.spacingSm
                        implicitHeight: Tokens.spacingSm
                        radius: width / 2
                        color: root.qualityColor
                        visible: root.tip === ""
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                        SequentialAnimation on opacity {
                            running: Discord.quality === "connecting" && Motion.slow > 0
                            loops: Animation.Infinite
                            alwaysRunToEnd: true
                            NumberAnimation { to: 0.3; duration: Motion.slow; easing.type: Motion.ambient }
                            NumberAnimation { to: 1;   duration: Motion.slow; easing.type: Motion.ambient }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.tip !== "" ? root.tip
                            : root.qualityText + (Discord.ping > 0 ? "  ·  " + Discord.ping + " ms" : "")
                        variant: "caption"
                        color: root.tip !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                        elide: Text.ElideRight
                    }
                    RollText {
                        visible: root.tip === "" && text !== ""
                        text: Discord.durationText(Clock.now.getTime())
                        family: Tokens.fontMono
                        pixelSize: Tokens.fontCaption
                        color: Colors.of(QsWindow.window).fgMuted
                    }
                }
            }

            ActionGroup {
                Tipped {
                    onHoveredChanged: root.setTip(hovered, tipText)
                    tipText: Discord.windowAddress === "" ? "Discord isn't running" : "Open Discord"
                    PanelButton {
                        variant: "ghost"
                        symbol: "open_in_new"
                        enabled: Discord.windowAddress !== ""
                        onActivated: { UiState.closeSidePanel(); Discord.focusWindow() }
                    }
                }
                Tipped {
                    onHoveredChanged: root.setTip(hovered, tipText)
                    tipText: Discord.pressBlocker(Discord.screenShareKey) || "Share your screen (Discord's keybind)"
                    PanelButton {
                        variant: "ghost"
                        symbol: "monitor"
                        enabled: Discord.canPress(Discord.screenShareKey)
                        onActivated: root.press(Discord.screenShareKey)
                    }
                }
                Tipped {
                    onHoveredChanged: root.setTip(hovered, tipText)
                    tipText: Discord.pressBlocker(Discord.cameraKey) || "Camera on/off (Discord's keybind)"
                    PanelButton {
                        variant: "ghost"
                        symbol: "videocam"
                        enabled: Discord.canPress(Discord.cameraKey)
                        onActivated: root.press(Discord.cameraKey)
                    }
                }
            }
        }

        TabStrip {
            id: tabs
            Layout.fillWidth: true
            visible: Discord.inCall
            accent:  Colors.of(QsWindow.window).primary
            current: root.tab
            model: [
                { value: "people", label: "People · " + Discord.users.length, icon: "headphones" },
                { value: "audio",  label: "Your audio",                         icon: "equalizer" }
            ]
            onPicked: (value) => root.show(value)
        }

        // ── The two faces, crossfading ────────────────────────────────────────
        Item {
            id: body
            Layout.fillWidth: true
            visible: Discord.inCall
            readonly property real target: root.tab === "people" ? people.height : audio.height
            Layout.preferredHeight: body.target
            Behavior on Layout.preferredHeight {
                enabled: root.switching
                NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter }
            }
            clip: root.switching

            // ══ People ═══════════════════════════════════════════════════════
            ListView {
                id: people
                width: body.width
                height: Math.min(people.contentHeight, root.bodyRoom)
                clip: true
                interactive: people.contentHeight > people.height
                spacing: Tokens.spacingXs
                boundsBehavior: Flickable.StopAtBounds

                opacity: root.tab === "people" ? 1 : 0
                visible: people.opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.enter } }
                transform: Translate {
                    x: root.tab === "people" ? 0 : -Tokens.spacingXl
                    Behavior on x { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }
                }

                model: ScriptModel {
                    values: Discord.users
                    objectProp: "id"
                }

                // First build: in one after another. Joins rise in; leaves fade; the rest
                // close up behind.
                populate: Transition {
                    id: pop
                    SequentialAnimation {
                        PropertyAction { property: "opacity"; value: 0 }
                        PauseAnimation { duration: Math.min(pop.ViewTransition.index * Motion.stagger * 2, Motion.staggerCap) }
                        ParallelAnimation {
                            NumberAnimation { property: "opacity"; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                            NumberAnimation { property: "x"; from: Tokens.spacingLg; to: 0; duration: Motion.emphasized; easing.type: Motion.enter }
                        }
                    }
                }
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                        NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Motion.emphasized; easing.type: Motion.enter }
                    }
                }
                remove: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
                        NumberAnimation { property: "scale"; to: 0.92; duration: Motion.exit; easing.type: Motion.exitCurve }
                    }
                }
                displaced: Transition {
                    NumberAnimation { property: "y"; duration: Motion.standard; easing.type: Motion.travel }
                }

                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index

                    readonly property string uid: row.modelData.id ?? ""
                    readonly property bool self: row.modelData.isSelf ?? false
                    readonly property bool open: root.expanded === row.uid && !row.self
                    readonly property bool speaking: row.modelData.speaking ?? false
                    readonly property bool mutedForMe: row.modelData.mute ?? false
                    readonly property bool theirMute: (row.modelData.selfMute ?? false) || (row.modelData.serverMute ?? false)
                    readonly property bool theirDeaf: (row.modelData.selfDeaf ?? false) || (row.modelData.serverDeaf ?? false)
                    readonly property int  volume: row.modelData.volume ?? 100
                    readonly property real pan: row.modelData.pan ?? 0
                    readonly property real headH: Tokens.iconXl + Tokens.spacingSm * 2

                    // What's true of them, in words (the glyphs alone needed a legend).
                    readonly property string summary: {
                        const bits = []
                        if (row.self) bits.push("Your audio  ›")
                        else {
                            if (row.speaking) bits.push("Speaking")
                            if (row.modelData.serverMute ?? false) bits.push("Server muted")
                            else if (row.modelData.selfMute ?? false) bits.push("Muted")
                            if (row.theirDeaf) bits.push("Deafened")
                            if (row.mutedForMe) bits.push("Muted for you")
                            else if (row.volume !== 100) bits.push(row.volume + "%")
                            if (Math.abs(row.pan) > 0.01) bits.push(row.pan < 0 ? "left" : "right")
                            if (row.modelData.bot ?? false) bits.push("Bot")
                        }
                        return bits.join(" · ")
                    }

                    width: people.width
                    height: row.headH + (row.open ? controls.implicitHeight + Tokens.spacingSm : 0)
                    clip: true
                    Behavior on height {
                        NumberAnimation { duration: Motion.surfaceDuration(row.open); easing.type: Motion.surfaceEasing(row.open) }
                    }

                    // Opened on load: bring it into view (a long call scrolls).
                    Component.onCompleted: if (row.open) Qt.callLater(() => people.positionViewAtIndex(row.index, ListView.Contain))

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusSm
                        color: row.open ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                             : rowMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04) : "transparent"
                        border.width: row.open ? Tokens.borderWidth : 0
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.35)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }

                    // ── Who ───────────────────────────────────────────────────────
                    RowLayout {
                        id: who
                        x: Tokens.spacingSm
                        width: row.width - Tokens.spacingSm * 2
                        height: row.headH
                        spacing: Tokens.spacingMd

                        Item {
                            implicitWidth: Tokens.iconXl
                            implicitHeight: Tokens.iconXl
                            // Talking: a soft halo and a ring, and the face leans in.
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + Tokens.borderChrome * 6
                                height: width
                                radius: width / 2
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.22)
                                opacity: row.speaking ? 1 : 0
                                scale: row.speaking ? 1 : 0.8
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.enter } }
                            }
                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.width + Tokens.borderChrome * 2
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.width: Tokens.borderChrome
                                border.color: Colors.of(QsWindow.window).focus
                                opacity: row.speaking ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            }
                            Avatar {
                                anchors.fill: parent
                                source: row.modelData.avatar ?? ""
                                name: row.modelData.name ?? ""
                                opacity: row.mutedForMe || row.theirDeaf ? 0.45 : 1
                                scale: row.speaking ? 1.06 : 1
                                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                Behavior on scale { NumberAnimation { duration: Motion.fast; easing.type: Motion.respondCurve } }
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: (row.modelData.name ?? "") + (row.self ? "  (you)" : "")
                                elide: Text.ElideRight
                                font.bold: row.open || row.speaking
                                emphasis: row.mutedForMe ? "dim" : "normal"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: row.summary
                                variant: "caption"
                                color: row.speaking && !row.self ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgDim
                                elide: Text.ElideRight
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }
                        }

                        // What's true of them, as Discord's glyphs.
                        Row {
                            spacing: Tokens.spacingXs
                            Glyph { shown: row.theirMute;  glyph: "\u{F036D}"; tint: (row.modelData.serverMute ?? false) ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted }  // 󰍭
                            Glyph { shown: row.theirDeaf;  glyph: "\u{F07CE}"; tint: (row.modelData.serverDeaf ?? false) ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted }  // 󰟎
                            Glyph { shown: row.mutedForMe; glyph: "\u{F075F}"; tint: Colors.of(QsWindow.window).danger }                                                         // 󰝟
                        }

                        // Opens / leads to "Your audio".
                        MaterialIcon {
                            glyph: row.self ? "\u{F0142}" : "\u{F0140}"               // 󰅂 chevron-right / 󰅀 chevron-down
                            variant: "body"
                            color: rowMouse.containsMouse || row.open ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                            rotation: row.open ? 180 : 0
                            Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                    }

                    // The row's head (not the controls below it) opens and shuts it;
                    // yours leads to your audio.
                    MouseArea {
                        id: rowMouse
                        width: row.width
                        height: row.headH
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (row.self) root.show("audio")
                            else root.expanded = row.open ? "" : row.uid
                        }
                    }

                    // ── Their controls, for you ───────────────────────────────────
                    ColumnLayout {
                        id: controls
                        x: Tokens.spacingSm
                        y: row.headH
                        width: row.width - Tokens.spacingSm * 2
                        spacing: Tokens.spacingSm
                        visible: !row.self
                        // Behind the row's growth: the room opens, then what's in it.
                        opacity: row.open ? 1 : 0
                        Behavior on opacity {
                            SequentialAnimation {
                                PauseAnimation { duration: row.open ? Motion.fast : 0 }
                                NumberAnimation { duration: Motion.standard; easing.type: Motion.enter }
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            PanelButton {
                                variant: row.mutedForMe ? "primary" : "ghost"
                                accent:  Colors.of(QsWindow.window).danger
                                symbol:  row.mutedForMe ? "volume_mute" : "volume_up"
                                label:   row.mutedForMe ? "Muted" : "Mute"
                                onActivated: Discord.setUserMute(row.uid, !row.mutedForMe)
                            }
                            Level {
                                Layout.fillWidth: true
                                maximum: 200
                                notchAt: 100
                                current: row.volume
                                enabled: !row.mutedForMe
                                onChosen: function (v) { Discord.setUserVolume(row.uid, v) }
                            }
                        }

                        // The usual levels, one click each.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs
                            enabled: !row.mutedForMe
                            opacity: enabled ? 1 : 0.4
                            StyledText { text: "Volume"; variant: "caption"; emphasis: "muted"; Layout.preferredWidth: Tokens.sideCardUnit * 1.2 }
                            Repeater {
                                model: [25, 50, 100, 150, 200]
                                PanelButton {
                                    required property int modelData
                                    Layout.fillWidth: true
                                    variant: row.volume === modelData ? "primary" : "ghost"
                                    label: modelData + "%"
                                    onActivated: Discord.setUserVolume(row.uid, modelData)
                                }
                            }
                        }

                        // Where they sit, left … right.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            enabled: !row.mutedForMe
                            opacity: enabled ? 1 : 0.4
                            StyledText { text: "Balance"; variant: "caption"; emphasis: "muted"; Layout.preferredWidth: Tokens.sideCardUnit * 1.2 }
                            Level {
                                Layout.fillWidth: true
                                maximum: 200
                                notchAt: 100
                                step: 10
                                numberWidth: Tokens.sideCardUnit * 1.1
                                current: (row.pan + 1) * 100
                                format: v => Math.abs(v - 100) < 1 ? "centre"
                                           : Math.round(Math.abs(v - 100)) + "% " + (v < 100 ? "L" : "R")
                                onChosen: function (v) { Discord.setUserPan(row.uid, v / 100 - 1) }
                            }
                        }
                    }
                }
            }

            // ══ Your audio ═══════════════════════════════════════════════════
            Flickable {
                id: audio
                width: body.width
                height: Math.min(audioCol.implicitHeight, root.bodyRoom)
                contentHeight: audioCol.implicitHeight
                clip: true
                interactive: audioCol.implicitHeight > audio.height
                boundsBehavior: Flickable.StopAtBounds

                opacity: root.tab === "audio" ? 1 : 0
                visible: audio.opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.enter } }
                transform: Translate {
                    x: root.tab === "audio" ? 0 : Tokens.spacingXl
                    Behavior on x { NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter } }
                }

                // Your mic, as the system hears it — what Discord is sending, when it's
                // on the default device. Only while this face is up and you're not muted.
                PwNodePeakMonitor {
                    id: peak
                    node: Audio.source
                    enabled: audio.visible && Discord.inCall && !Discord.mute
                             && peak.node !== null && Audio.hasKnownChannels(peak.node)
                }

                ColumnLayout {
                    id: audioCol
                    width: audio.width
                    spacing: Tokens.spacingMd

                    // ── Input ────────────────────────────────────────────────────
                    Heading { text: "Input" }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            glyph: Discord.mute ? "\u{F036D}" : "\u{F036C}"         // 󰍭 / 󰍬
                            variant: "body"
                            color: Discord.mute ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                        }
                        Level {
                            Layout.fillWidth: true
                            maximum: 100
                            current: Discord.inputVolume
                            onChosen: function (v) { Discord.setInputVolume(v) }
                        }
                    }
                    Meter {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tokens.spacingXl
                        implicitHeight: Tokens.spacingXs
                        value: peak.enabled ? Audio.meterLevel(peak.peak) : 0
                        accent: Colors.of(QsWindow.window).success
                        fillDuration: Motion.track
                    }
                    DevicePicker {
                        Layout.fillWidth: true
                        glyph: "\u{F036C}"                                         // 󰍬
                        devices: Discord.inputDevices
                        current: Discord.inputDevice
                        onPicked: function (id) { Discord.setInputDevice(id) }
                    }
                    TabStrip {
                        Layout.fillWidth: true
                        accent: Colors.of(QsWindow.window).primary
                        current: Discord.inputMode
                        model: [
                            { value: "VOICE_ACTIVITY", label: "Voice activity", icon: "mic" },
                            { value: "PUSH_TO_TALK",   label: "Push to talk",   icon: "keyboard" }
                        ]
                        onPicked: (value) => Discord.setInputMode(value)
                    }

                    // ── Output ───────────────────────────────────────────────────
                    Heading { text: "Output" }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            glyph: Discord.deaf ? "\u{F07CE}" : "\u{F02CB}"         // 󰟎 / 󰋋
                            variant: "body"
                            color: Discord.deaf ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                        }
                        Level {
                            Layout.fillWidth: true
                            maximum: 200
                            notchAt: 100
                            current: Discord.outputVolume
                            onChosen: function (v) { Discord.setOutputVolume(v) }
                        }
                    }
                    DevicePicker {
                        Layout.fillWidth: true
                        glyph: "\u{F04C3}"                                         // 󰓃 speaker
                        devices: Discord.outputDevices
                        current: Discord.outputDevice
                        onPicked: function (id) { Discord.setOutputDevice(id) }
                    }

                    // ── Processing ───────────────────────────────────────────────
                    Heading { text: "Processing" }
                    Repeater {
                        model: [
                            { key: "noise", label: "Noise suppression",      hint: "Filters background noise" },
                            { key: "echo",  label: "Echo cancellation",      hint: "Stops your speakers coming back through the mic" },
                            { key: "agc",   label: "Automatic gain control", hint: "Evens out how loud you are" }
                        ]
                        RowLayout {
                            id: procRow
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText { Layout.fillWidth: true; text: procRow.modelData.label; variant: "label" }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: procRow.modelData.hint
                                    variant: "caption"
                                    emphasis: "dim"
                                    elide: Text.ElideRight
                                }
                            }
                            Toggle {
                                checked: Discord.processing[procRow.modelData.key] ?? false
                                onToggled: Discord.setProcessing(procRow.modelData.key, !checked)
                            }
                        }
                    }
                }
            }
        }
    }

    // ── Pieces ────────────────────────────────────────────────────────────────

    // A level, 0..maximum, with its reading beside it. While dragged (and briefly
    // after) it shows what you asked for, not the service's last word.
    component Level: RowLayout {
        id: level
        property real maximum: 100
        property real notchAt: 0
        property real current: 0
        property int  step: 5
        property real numberWidth: Tokens.sideCardUnit * 0.8
        property var  format: v => Math.round(v) + "%"
        signal chosen(real v)
        Layout.fillHeight: false

        property real _asked: 0
        readonly property bool _holding: slider.pressed || settle.running

        spacing: Tokens.spacingSm

        Timer { id: settle; interval: 800 }

        ValueSlider {
            id: slider
            Layout.fillWidth: true
            maximum: level.maximum
            notchAt: level.notchAt
            enabled: level.enabled
            value: level._holding ? level._asked : level.current
            onMoved: function (v) { level._asked = Math.round(v); level.chosen(level._asked) }
            onScrolled: function (d) {
                level._asked = Math.max(0, Math.min(level.maximum, Math.round((level._holding ? level._asked : level.current) + d * level.step)))
                settle.restart()
                level.chosen(level._asked)
            }
            onPressedChanged: if (!slider.pressed) settle.restart()
        }
        StyledText {
            Layout.preferredWidth: level.numberWidth
            horizontalAlignment: Text.AlignRight
            text: level.format(level._holding ? level._asked : level.current)
            variant: "caption"
            emphasis: "dim"
            font.family: Tokens.fontMono
        }
    }

    // A small section title.
    component Heading: StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacingXs
        variant: "caption"
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
        emphasis: "muted"
    }

    // A state glyph that pops in and out rather than appearing.
    component Glyph: MaterialIcon {
        property bool shown: false
        property color tint: Colors.of(QsWindow.window).fgMuted
        color: tint
        visible: scale > 0.01
        scale: shown ? 1 : 0
        Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
    }

    // A button with a hover tip for the strip — on a wrapper, because a disabled button
    // (the one that most needs explaining) gets no hover of its own. The user says
    // where the tip goes (an inline component can't see this file's ids).
    component Tipped: Item {
        id: tipped
        property string tipText: ""
        readonly property bool hovered: tipHover.hovered
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
        HoverHandler { id: tipHover }
    }

    // Which device: the current one, and the list Discord offers when it's opened.
    component DevicePicker: ColumnLayout {
        id: picker
        property var devices: []
        property string current: ""
        property string glyph: ""
        property bool open: false
        signal picked(string id)
        Layout.fillHeight: false

        readonly property string currentName: {
            const d = picker.devices.find(x => x.id === picker.current)
            return d ? d.name : picker.devices.length > 0 ? "Default" : "No devices listed"
        }
        spacing: Tokens.spacingXs

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: pickRow.implicitHeight + Tokens.spacingSm * 2
            radius: Tokens.radiusSm
            color: pickMouse.containsMouse || picker.open ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08) : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.04)
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            RowLayout {
                id: pickRow
                anchors.fill: parent
                anchors.leftMargin: Tokens.spacingMd
                anchors.rightMargin: Tokens.spacingMd
                spacing: Tokens.spacingSm
                MaterialIcon { variant: "body"; glyph: picker.glyph; color: Colors.of(QsWindow.window).fgMuted }
                StyledText {
                    Layout.fillWidth: true
                    text: picker.currentName
                    variant: "label"
                    elide: Text.ElideRight
                }
                MaterialIcon {
                    visible: picker.devices.length > 1
                    glyph: "\u{F0140}"                                            // 󰅀
                    variant: "body"
                    color: Colors.of(QsWindow.window).fgDim
                    rotation: picker.open ? 180 : 0
                    Behavior on rotation { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                }
            }
            MouseArea {
                id: pickMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: picker.devices.length > 1
                cursorShape: Qt.PointingHandCursor
                onClicked: picker.open = !picker.open
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: picker.open ? choices.implicitHeight : 0
            clip: true
            Behavior on Layout.preferredHeight {
                NumberAnimation { duration: Motion.surfaceDuration(picker.open); easing.type: Motion.surfaceEasing(picker.open) }
            }
            opacity: picker.open ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.standard } }

            Column {
                id: choices
                width: parent.width
                spacing: 1
                Repeater {
                    model: picker.devices
                    Rectangle {
                        id: choice
                        required property var modelData
                        readonly property bool on: choice.modelData.id === picker.current
                        width: choices.width
                        height: choiceText.implicitHeight + Tokens.spacingSm * 2
                        radius: Tokens.radiusSm
                        color: choiceMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06) : "transparent"
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                        StyledText {
                            id: choiceText
                            anchors.left: parent.left
                            anchors.right: tick.left
                            anchors.leftMargin: Tokens.spacingXl + Tokens.spacingMd
                            anchors.verticalCenter: parent.verticalCenter
                            text: choice.modelData.name
                            variant: "label"
                            color: choice.on ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
                            elide: Text.ElideRight
                        }
                        MaterialIcon {
                            id: tick
                            anchors.right: parent.right
                            anchors.rightMargin: Tokens.spacingMd
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: "\u{F012C}"                                    // 󰄬
                            variant: "body"
                            color: Colors.of(QsWindow.window).primary
                            opacity: choice.on ? 1 : 0
                        }
                        MouseArea {
                            id: choiceMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { picker.picked(choice.modelData.id); picker.open = false }
                        }
                    }
                }
            }
        }
    }
}
