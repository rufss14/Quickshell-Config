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
// ── A mixing desk, and one channel's detail ───────────────────────────────────
// It was a hero of six bars plus six cards, each with the same slider and the same Play
// buttons: seven boxes saying one thing. Now it is ONE card that looks like what it is:
// a channel strip per group (and the master) — a tall fader you drag, scroll or tap,
// with its on/off above it and its name below. Tapping a name selects that channel, and
// the card under the desk shows ITS detail: what it plays, a button per sound, and (for
// typing) where it listens.
//
// A view: the sounds, the files and the player are services/Sfx. The Play buttons work
// with the master off (`Sfx.warm()` builds the files).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onCompleted: Sfx.warm()

    // The selected channel's id; its detail is the second card.
    property string sel: "panels"

    // The groups, in sfx.js's order. `on` / `level` name the Config properties, so the desk
    // and the detail read ONE table.
    readonly property var groups: [
        { id: "panels",   title: "Panels",        symbol: "view_quilt",    accent: Colors.of(QsWindow.window).primary,
          on: "sfxPanels",   level: "sfxPanelsVolume",
          detail: "A soft swoosh as a panel, the launcher or the overview opens and closes",
          cues: [{ id: "open", label: "Open" }, { id: "close", label: "Close" }] },
        { id: "typing",   title: "Typing",        symbol: "keyboard",      accent: Colors.of(QsWindow.window).primary,
          on: "sfxTyping",   level: "sfxTypingVolume",
          detail: "A key click in the shell's own text fields",
          cues: [{ id: "key", label: "Key" }, { id: "space", label: "Space" },
                 { id: "enter", label: "Enter" }] },
        { id: "switches", title: "Switches",      symbol: "tune",          accent: Colors.of(QsWindow.window).info,
          on: "sfxSwitches", level: "sfxSwitchesVolume",
          detail: "A blip when a switch flips on or off",
          cues: [{ id: "on", label: "On" }, { id: "off", label: "Off" }] },
        { id: "notify",   title: "Alerts",        symbol: "notifications", accent: Colors.of(QsWindow.window).warning,
          on: "sfxNotify",   level: "sfxNotifyVolume",
          detail: "A chime when a notification arrives",
          cues: [{ id: "notify", label: "Chime" }] },
        { id: "alerts",   title: "Timer",         symbol: "alarm",         accent: Colors.of(QsWindow.window).danger,
          on: "sfxAlerts",   level: "sfxAlertsVolume",
          detail: "A bell when a countdown finishes, soft beeps when an alarm goes off",
          cues: [{ id: "timer", label: "Timer" }, { id: "alarm", label: "Alarm" }] },
        { id: "capture",  title: "Capture",       symbol: "photo_camera",  accent: Colors.of(QsWindow.window).success,
          on: "sfxCapture",  level: "sfxCaptureVolume",
          detail: "A shutter for a screenshot, a chime when a clip is saved",
          cues: [{ id: "shutter", label: "Shutter" }, { id: "clipsaved", label: "Clip saved" }] }
    ]
    // The master is the first strip: same shape, its own Config names.
    readonly property var strips: [
        { id: "master", title: "Master", symbol: "volume_up", accent: Colors.of(QsWindow.window).primary,
          on: "sfxEnabled", level: "sfxVolume" }
    ].concat(root.groups)

    readonly property var current: root.groups.find(g => g.id === root.sel) ?? root.groups[0]
    readonly property bool currentLive: Config.sfxEnabled && Config[root.current.on]

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F057E}"
        title:     Translation.tr("Sound")
        titleTail: "effects"
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.sfxEnabled ? "Off — the shell stays quiet"
                 : "On, at " + Math.round(Config.sfxVolume * 100) + "%"

        // ══ The desk ══════════════════════════════════════════════════════════
        Section {
            span:     3
            symbol:   "equalizer"
            title:    Translation.tr("Mixer")
            subtitle: Sfx.blocker !== "" ? Sfx.blocker : "Drag, scroll or tap a fader"
            help:     Translation.tr("Off until you turn it on. Every sound is generated on this machine (scripts/gen-sfx.py) — nothing is downloaded.")
            accent:   Colors.of(QsWindow.window).primary

            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 252
                Layout.fillHeight: false
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
                        Layout.preferredWidth: strip.master ? 104 : 0
                        Layout.fillHeight: true
                        Layout.rightMargin: strip.master ? Tokens.spacingLg : 0

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

                        // The fader: a tall capsule, filled from the bottom. Dim while its
                        // group is off, since moving it then changes nothing you can hear.
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
                                color: strip.lit ? strip.modelData.accent
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

                        // On / off — a chip carrying the channel's own icon.
                        ChipButton {
                            id: power
                            anchors.bottom: name.top
                            anchors.bottomMargin: Tokens.spacingXs
                            anchors.horizontalCenter: parent.horizontalCenter
                            symbol: strip.master && !Config.sfxEnabled ? "volume_off" : strip.modelData.symbol
                            on:     strip.lit
                            tint:   strip.modelData.accent
                            enabled: strip.master || Config.sfxEnabled
                            onActivated: Config[strip.modelData.on] = !Config[strip.modelData.on]
                        }

                        // The name selects the channel, and carries the selection.
                        Rectangle {
                            id: name
                            anchors.bottom: parent.bottom
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: nameText.implicitWidth + Tokens.spacingLg * 2
                            height: Tokens.iconLg + Tokens.spacingXs
                            radius: height / 2
                            visible: !strip.master
                            color: strip.chosen ? Colors.of(QsWindow.window).alpha(strip.modelData.accent, 0.22)
                                 : nameHover.hovered ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                 : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            StyledText {
                                id: nameText
                                anchors.centerIn: parent
                                text: strip.modelData.title
                                variant: "caption"
                                font.weight: strip.chosen ? Font.DemiBold : Font.Normal
                                color: strip.chosen ? strip.modelData.accent : Colors.of(QsWindow.window).fgMuted
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
        }

        // ══ The chosen channel ════════════════════════════════════════════════
        Section {
            span:     3
            symbol:   root.current.symbol
            title:    root.current.title
            subtitle: root.current.detail
            accent:   root.current.accent

            actions: Toggle {
                checked: Config[root.current.on]
                accent:  root.current.accent
                enabled: Config.sfxEnabled
                opacity: enabled ? 1 : 0.5
                onToggled: Config[root.current.on] = !Config[root.current.on]
            }

            // Hear each sound in the group. They answer with the group off too, so you can
            // audition before you decide.
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.current.cues

                    ChipTray {
                        required property var modelData
                        ChipButton {
                            symbol: "play_arrow"
                            label:  parent.parent.modelData.label
                            tint:   root.current.accent
                            enabled: Sfx.ready
                            onActivated: Sfx.preview(parent.parent.modelData.id)
                        }
                    }
                }
            }

            // Where typing sounds: just the shell's own fields, or every key in every app
            // (a Hyprland hook, services/SfxKeys).
            TabStrip {
                Layout.fillWidth: true
                visible: root.current.id === "typing"
                accent: root.current.accent
                model: [{ value: "shell", label: "Shell only", icon: "keyboard" },
                        { value: "all",   label: "Everywhere", icon: "public" }]
                current: Config.sfxTypingScope
                onPicked: function (v) { Config.sfxTypingScope = v }
            }

            // What it is doing, in the service's own words, so the chip and the state cannot
            // disagree. Honest about the privacy cost of "Everywhere".
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.current.id === "typing" && Config.sfxTypingScope === "all"
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: SfxKeys.lastError !== "" ? "normal" : "dim"
                color: SfxKeys.lastError !== "" ? Colors.of(QsWindow.window).warning : Colors.of(QsWindow.window).fgMuted
                text: SfxKeys.lastError !== ""
                    ? "Hyprland refused the hook: " + SfxKeys.lastError
                    : SfxKeys.live
                    ? "Every app (" + SfxKeys.events + " keys heard) — only the kind of key, never which one."
                    : Gamemode.silencesKeys ? "Muted while Game Mode is on."
                    : Lock.locked ? "Paused while the screen is locked."
                    : "Waiting — turn the master switch and Typing on."
            }

            // Feel it: whatever you type here makes the typing sound, if it is on.
            InputField {
                cornerRadius: implicitHeight / 2
                Layout.fillWidth: true
                visible: root.current.id === "typing"
                placeholder: Translation.tr("Type here to hear it")
            }
        }
    }
}
