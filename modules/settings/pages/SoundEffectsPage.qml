pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── SoundEffectsPage — Appearance › Sound effects ─────────────────────────────
// The shell's own little sounds: a swoosh as a panel opens, a click per key typed in
// its fields, a blip for a switch, a bell for a timer. Output devices and levels are
// the Sound page; this is the shell making noise of its own, and whether it should.
//
// ── A mixing desk, and one channel's detail beside it ─────────────────────────
// The desk is the page's tool, so it keeps its own layout inside one full-row group: a channel
// strip per group (and the master), each a tall fader you drag, scroll or tap, with its on/off
// above it and its name below. That chip is the ONLY on/off for a channel: tapping a name
// selects the channel, and the lifted plate beside the desk shows ITS detail: what it plays, a
// button per sound, and (for typing) where it listens. Narrow, the plate drops under the desk.
//
// One colour rule for every fader: on is the accent, off is dim. A channel is not told apart
// by hue, the name under it does that.
//
// A view: the sounds, the files and the player are services/Sfx. The Play buttons work
// with the master off (`Sfx.warm()` builds the files).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted: Sfx.warm()

    // The selected channel's id; its detail is the plate beside the desk.
    property string sel: "panels"

    // One accent for the whole desk: a lit fader, a lit chip and the chosen name all wear it.
    readonly property color accent: Colors.of(QsWindow.window).primary

    // The groups, in sfx.js's order. `on` / `level` name the Config properties, so the desk
    // and the detail read ONE table.
    readonly property var groups: [
        { id: "panels",   title: Translation.tr("Panels"),   symbol: "view_quilt",
          on: "sfxPanels",   level: "sfxPanelsVolume",
          detail: Translation.tr("A soft swoosh as a panel, the launcher or the overview opens and closes"),
          cues: [{ id: "open", label: Translation.tr("Open") }, { id: "close", label: Translation.tr("Close") }] },
        { id: "typing",   title: Translation.tr("Typing"),   symbol: "keyboard",
          on: "sfxTyping",   level: "sfxTypingVolume",
          detail: Translation.tr("A key click in the shell's own text fields"),
          cues: [{ id: "key", label: Translation.tr("Key") }, { id: "space", label: Translation.tr("Space") },
                 { id: "enter", label: Translation.tr("Enter") }] },
        { id: "switches", title: Translation.tr("Switches"), symbol: "tune",
          on: "sfxSwitches", level: "sfxSwitchesVolume",
          detail: Translation.tr("A blip when a switch flips on or off"),
          cues: [{ id: "on", label: Translation.tr("On") }, { id: "off", label: Translation.tr("Off") }] },
        { id: "notify",   title: Translation.tr("Alerts"),   symbol: "notifications",
          on: "sfxNotify",   level: "sfxNotifyVolume",
          detail: Translation.tr("A chime when a notification arrives"),
          cues: [{ id: "notify", label: Translation.tr("Chime") }] },
        { id: "alerts",   title: Translation.tr("Timer"),    symbol: "alarm",
          on: "sfxAlerts",   level: "sfxAlertsVolume",
          detail: Translation.tr("A bell when a countdown finishes, soft beeps when an alarm goes off"),
          cues: [{ id: "timer", label: Translation.tr("Timer") }, { id: "alarm", label: Translation.tr("Alarm") }] },
        { id: "capture",  title: Translation.tr("Capture"),  symbol: "photo_camera",
          on: "sfxCapture",  level: "sfxCaptureVolume",
          detail: Translation.tr("A shutter for a screenshot, a chime when a clip is saved"),
          cues: [{ id: "shutter", label: Translation.tr("Shutter") }, { id: "clipsaved", label: Translation.tr("Clip saved") }] }
    ]
    // The master is the first strip: same shape, its own Config names.
    readonly property var strips: [
        { id: "master", title: Translation.tr("Master"), symbol: "volume_up",
          on: "sfxEnabled", level: "sfxVolume" }
    ].concat(root.groups)

    readonly property var current: root.groups.find(g => g.id === root.sel) ?? root.groups[0]
    readonly property bool currentLive: Config.sfxEnabled && Config[root.current.on]

    // Why the chosen channel makes no sound right now, or "".
    readonly property string silentWhy: !Config.sfxEnabled ? Translation.tr("Silent while the master is off")
                                      : !Config[root.current.on] ? Translation.tr("Silent while this group is off")
                                      : ""

    // The plate beside the desk: wide enough for "Shell only" and "Everywhere" with their icons.
    readonly property int plateWidth: Tokens.fieldHeight * 10
    // The desk needs room for seven strips and their names; under this it stacks above the plate.
    readonly property int deskMin: Tokens.fieldHeight * 14

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "\u{F057E}"
        title:     Translation.tr("Sound")
        titleTail: "effects"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.sfxEnabled ? Translation.tr("Off, the shell stays quiet")
                 : Translation.tr("On, at %1%").arg(Math.round(Config.sfxVolume * 100))

        // ══ The desk and the chosen channel ═══════════════════════════════════
        Section {
            grouped:  true
            fullRow:  true
            symbol:   "equalizer"
            title:    Translation.tr("Mixer")
            subtitle: Sfx.blocker !== "" ? Sfx.blocker : Translation.tr("Drag, scroll or tap a fader")
            help:     Translation.tr("Off until you turn it on. Every sound is generated on this machine (scripts/gen-sfx.py). Nothing is downloaded.")

            GridLayout {
                id: board
                Layout.fillWidth: true
                Layout.fillHeight: false
                readonly property bool side: width >= root.plateWidth + root.deskMin + columnSpacing
                columns: board.side ? 2 : 1
                columnSpacing: Tokens.spacingLg
                rowSpacing: Tokens.spacingLg

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: board.side
                    Layout.preferredHeight: 340
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: root.strips

                        Item {
                            id: strip
                            required property var modelData
                            required property int index
                            readonly property bool master: strip.modelData.id === "master"
                            readonly property bool lit: strip.master ? Config.sfxEnabled
                                                                     : Config.sfxEnabled && Config[strip.modelData.on]
                            readonly property bool chosen: strip.modelData.id === root.sel
                            readonly property real stored: Config[strip.modelData.level]
                            // While the fader is held it shows where the pointer is; the value is
                            // written on release, so a drag is one write and not forty.
                            property real held: -1
                            readonly property real value: strip.held >= 0 ? strip.held : strip.stored

                            // Equal cells for the six; the master is its own, a little apart.
                            Layout.fillWidth: !strip.master
                            Layout.preferredWidth: strip.master ? 72 : 0
                            Layout.fillHeight: true
                            Layout.rightMargin: strip.master ? Tokens.spacingMd : 0

                            function _set(v) { Config[strip.modelData.level] = Math.round(Math.max(0, Math.min(1, v)) * 20) / 20 }

                            // The percentage, above the fader it describes.
                            StyledText {
                                id: readout
                                anchors.top: parent.top
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Math.round(strip.value * 100) + "%"
                                variant: "caption"
                                font.weight: Font.DemiBold
                                emphasis: strip.lit ? "normal" : "dim"
                            }

                            // The fader: a tall capsule, filled from the bottom. Accent while its
                            // group is on, dim while it is off, since moving it then changes
                            // nothing you can hear.
                            Rectangle {
                                id: track
                                anchors.top: readout.bottom
                                anchors.topMargin: Tokens.spacingXs
                                anchors.bottom: power.top
                                anchors.bottomMargin: Tokens.spacingSm
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(parent.width - Tokens.spacingSm, 64)
                                radius: width / 2
                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                clip: true

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: Math.max(parent.width, parent.height * strip.value)
                                    radius: parent.radius
                                    color: strip.lit ? root.accent
                                                     : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.28)
                                    Behavior on height { enabled: strip.held < 0; NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                                    Behavior on color  { ColorAnimation { duration: Motion.standard } }
                                }

                                // Tick marks at the quarters, so a level reads without a number.
                                Repeater {
                                    model: 3
                                    Rectangle {
                                        required property int index
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width * 0.3
                                        height: 1
                                        y: parent.height * (index + 1) / 4
                                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                                    }
                                }

                                scale: drag.pressed ? 1.04 : 1.0
                                Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.overshoot } }

                                MouseArea {
                                    id: drag
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    function _at(y) { return 1 - Math.max(0, Math.min(1, y / height)) }
                                    onPressed:  function (m) { strip.held = _at(m.y) }
                                    onPositionChanged: function (m) { if (pressed) strip.held = _at(m.y) }
                                    onReleased: { strip._set(strip.held); strip.held = -1 }
                                    onCanceled: strip.held = -1
                                    onWheel: function (w) { strip._set(strip.stored + (w.angleDelta.y > 0 ? 0.05 : -0.05)) }
                                }
                            }

                            // On / off: a chip carrying the channel's own icon.
                            ChipButton {
                                id: power
                                anchors.bottom: name.top
                                anchors.bottomMargin: Tokens.spacingXs
                                anchors.horizontalCenter: parent.horizontalCenter
                                symbol: strip.master && !Config.sfxEnabled ? "volume_off" : strip.modelData.symbol
                                on:     strip.lit
                                tint:   root.accent
                                enabled: strip.master || Config.sfxEnabled
                                onActivated: Config[strip.modelData.on] = !Config[strip.modelData.on]
                            }

                            // The name selects the channel, and carries the selection.
                            Rectangle {
                                id: name
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: nameText.implicitWidth + Tokens.spacingMd
                                height: Tokens.iconLg + Tokens.spacingXs
                                radius: height / 2
                                visible: !strip.master
                                color: strip.chosen ? Colors.of(QsWindow.window).alpha(root.accent, 0.22)
                                     : nameHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                     : "transparent"
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                StyledText {
                                    id: nameText
                                    anchors.centerIn: parent
                                    text: strip.modelData.title
                                    variant: "caption"
                                    font.weight: strip.chosen ? Font.DemiBold : Font.Normal
                                    color: strip.chosen ? root.accent : Colors.of(QsWindow.window).fgMuted
                                }
                                HoverHandler { id: nameHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: root.sel = strip.modelData.id }
                            }
                            // The master has no detail to select; its name is a plain label.
                            StyledText {
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: Tokens.spacingXs
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: strip.master
                                text: Translation.tr("Master")
                                variant: "caption"
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                }

                // The chosen channel, lifted off the group's tone. Concentric with the group:
                // its corner is the group's less the gap.
                Rectangle {
                    id: plate
                    Layout.fillWidth: !board.side
                    Layout.preferredWidth: board.side ? root.plateWidth : -1
                    Layout.fillHeight: board.side
                    implicitHeight: plateCol.implicitHeight + Tokens.spacingLg * 2
                    radius: Tokens.radiusCard
                    color: Colors.of(QsWindow.window).surfaceHigh

                    ColumnLayout {
                        id: plateCol
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingMd

                        // Which channel this is: a disc while it is silent, a cookie once it plays.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingMd

                            Item {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth:  Tokens.iconXl + Tokens.spacingMd
                                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                                MorphShape {
                                    anchors.fill: parent
                                    shape: root.currentLive ? "cookie9" : "circle"
                                    fillColor: root.currentLive ? Colors.of(QsWindow.window).primaryContainer
                                                                : Colors.of(QsWindow.window).surfaceContainer
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: root.current.symbol
                                    fill: 1
                                    font.pixelSize: Tokens.iconLg
                                    color: root.currentLive ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                            : Colors.of(QsWindow.window).fgMuted
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText {
                                    text: root.current.title
                                    variant: "title"
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: root.silentWhy !== ""
                                    text: root.silentWhy
                                    variant: "caption"
                                    color: Colors.of(QsWindow.window).warning
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            text: root.current.detail
                            variant: "caption"
                            emphasis: "dim"
                            wrapMode: Text.WordWrap
                        }

                        // Hear each sound in the group. They answer with the group off too, so
                        // you can audition before you decide.
                        Flow {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm

                            Repeater {
                                model: root.current.cues

                                ChipTray {
                                    id: cue
                                    required property var modelData
                                    ChipButton {
                                        symbol: "play_arrow"
                                        label:  cue.modelData.label
                                        tint:   root.accent
                                        enabled: Sfx.ready
                                        onActivated: Sfx.preview(cue.modelData.id)
                                    }
                                }
                            }
                        }

                        // Where typing sounds: just the shell's own fields, or every key in every
                        // app (a Hyprland hook, services/SfxKeys).
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            visible: root.current.id === "typing"
                            spacing: Tokens.spacingSm

                            StyledText {
                                text: Translation.tr("Listens to")
                                variant: "body"
                                font.weight: Font.Medium
                            }
                            TabStrip {
                                Layout.fillWidth: true
                                connected: true
                                accent: root.accent
                                model: [{ value: "shell", label: Translation.tr("Shell only"), icon: "keyboard" },
                                        { value: "all",   label: Translation.tr("Everywhere"), icon: "public" }]
                                current: Config.sfxTypingScope
                                onPicked: function (v) { Config.sfxTypingScope = v }
                            }
                            // What it is doing, in the service's own words, so the chip and the
                            // state cannot disagree. Honest about the privacy cost of "Everywhere".
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                visible: Config.sfxTypingScope === "all"
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: SfxKeys.lastError !== "" ? "normal" : "dim"
                                color: SfxKeys.lastError !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                                text: SfxKeys.lastError !== ""
                                    ? Translation.tr("Hyprland refused the hook: %1").arg(SfxKeys.lastError)
                                    : SfxKeys.live
                                    ? Translation.tr("Every app (%1 keys heard). Only the kind of key, never which one.").arg(SfxKeys.events)
                                    : Gamemode.silencesKeys ? Translation.tr("Muted while Game Mode is on.")
                                    : Lock.locked ? Translation.tr("Paused while the screen is locked.")
                                    : Translation.tr("Waiting: turn the master switch and Typing on.")
                            }
                        }

                        // Feel it: whatever you type here makes the typing sound, if it is on.
                        InputField {
                            Layout.fillWidth: true
                            visible: root.current.id === "typing"
                            cornerRadius: implicitHeight / 2
                            placeholder: Translation.tr("Type here to hear it")
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }
        }
    }
}
