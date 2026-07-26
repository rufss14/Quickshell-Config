import QtQuick
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── TimerCard ─────────────────────────────────────────────────────────────────
// Bottom-right of the overview. Three faces in one card:
//
//   Timer      — counts DOWN from a set duration, and notifies when it lands.
//   Stopwatch  — counts UP from zero, with laps.
//   Alarm      — fires a notification at a time of day.
//
// ── A VIEW, not the owner ─────────────────────────────────────────────────────
// All the state, the tick, the notifications and the persistence live in the `Timers`
// singleton — because this card is built PER MONITOR and only exists while the overview
// is around. A running timer, a stopwatch, and armed alarms have to survive the overview
// closing, a shell reload, and a reboot, and must fire (and write) exactly once no matter
// how many screens show this card. So the card only renders `Timers.*` and calls its
// functions; it holds nothing of its own except the alarm being dialled in.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard

    implicitWidth: 300

    // ── A deliberately STABLE height ──────────────────────────────────────────
    // Floored at the tallest state any face can reach, so switching faces does not
    // resize the card. This is not cosmetic: the overlay derives the workspace grid's
    // free band — and therefore the grid's SCALE — from the height of the bottom-row
    // cards. If this card grew when you tapped a face, the whole grid would rescale.
    implicitHeight: Math.max(280, content.implicitHeight + Tokens.spacingXl * 2)
    Behavior on implicitHeight { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // The alarm being dialled in — the one piece of state that's genuinely the card's,
    // since it's an input, not something to persist or fire.
    property int newH: 7
    property int newM: 0
    function bumpNew(isHour, delta) {
        if (isHour) root.newH = (root.newH + delta + 24) % 24
        else        root.newM = (root.newM + delta + 60) % 60
    }

    // ══════════════════════════════════════════════════════════════════════════
    ColumnLayout {
        id: content

        anchors.left:    parent.left
        anchors.right:   parent.right
        anchors.top:     parent.top
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingLg

        // ── Face switch ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            Repeater {
                model: [
                    { key: "timer",     label: "Timer",     glyph: "󰔛" },  // 󰔛 timer-outline
                    { key: "stopwatch", label: "Stopwatch", glyph: "󱎫" },  // 󱎫 timer-sand
                    { key: "alarm",     label: "Alarm",     glyph: "󰀠" }   // 󰀠 alarm
                ]

                PanelButton {
                    required property var modelData

                    Layout.fillWidth: true
                    variant: Timers.mode === modelData.key ? "primary" : "normal"
                    accent:  Colors.focus
                    glyph:   modelData.glyph
                    // Three faces make the labels tight; the glyph carries it and the
                    // label shows on the active one, which is the one you're reading.
                    label:   Timers.mode === modelData.key ? modelData.label : ""
                    onActivated: Timers.mode = modelData.key
                }
            }
        }

        Divider {}

        // ══ TIMER ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: Timers.mode === "timer"
            spacing: Tokens.spacingLg

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: (Timers.timerRunning || Timers.timerDone || Timers.timerRemain > 0)
                    ? Timers.clockString(Timers.timerRemain)
                    : Timers.clockString(Timers.timerTotal)
                font.family: Tokens.fontMono
                font.pixelSize: 38
                font.bold: true
                color: Timers.timerDone    ? Colors.danger
                     : Timers.timerRunning ? Colors.focus
                     : Colors.fg

                // Finished BREATHES rather than flashing — the shell's ambient "needs you".
                SequentialAnimation on opacity {
                    running: Timers.timerDone
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.35; duration: Motion.slow; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.00; duration: Motion.slow; easing.type: Easing.InOutSine }
                }
            }

            // Duration setter — hidden while running.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                visible: !Timers.timerRunning
                spacing: Tokens.spacingMd

                Repeater {
                    model: [ { unit: 0, suffix: "h" }, { unit: 1, suffix: "m" }, { unit: 2, suffix: "s" } ]

                    RowLayout {
                        required property var modelData
                        spacing: Tokens.spacingXs

                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: "󰍴"
                            onActivated: Timers.bumpSet(modelData.unit, -1)
                        }
                        StyledText {
                            text: Timers.pad(Timers.readSet(modelData.unit)) + modelData.suffix
                            font.family: Tokens.fontMono
                            variant: "label"
                            font.bold: true
                            emphasis: Timers.readSet(modelData.unit) > 0 ? "normal" : "dim"
                        }
                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: "󰐕"
                            onActivated: Timers.bumpSet(modelData.unit, 1)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                PanelButton {
                    Layout.fillWidth: true
                    visible: !Timers.timerRunning
                    enabled: Timers.timerTotal > 0
                    variant: "primary"
                    accent:  Colors.focus
                    glyph:   "󰐊"
                    label:   Timers.timerDone ? "Restart" : "Start"
                    onActivated: Timers.startTimer()
                }
                PanelButton {
                    Layout.fillWidth: true
                    visible: Timers.timerRunning || Timers.timerDone
                    variant: "normal"
                    glyph:   "󰓛"
                    label:   "Stop"
                    onActivated: Timers.stopTimer()
                }
            }
        }

        // ══ STOPWATCH ═════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: Timers.mode === "stopwatch"
            spacing: Tokens.spacingLg

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Timers.lapString(Timers.swElapsed)
                font.family: Tokens.fontMono
                font.pixelSize: 34
                font.bold: true
                color: Timers.swRunning ? Colors.focus : Colors.fg
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                PanelButton {
                    Layout.fillWidth: true
                    variant: Timers.swRunning ? "normal" : "primary"
                    accent:  Colors.focus
                    glyph:   Timers.swRunning ? "󰏤" : "󰐊"
                    label:   Timers.swRunning ? "Pause"
                           : Timers.swElapsed > 0 ? "Resume" : "Start"
                    onActivated: Timers.swRunning ? Timers.pauseStopwatch()
                                                  : Timers.startStopwatch()
                }
                PanelButton {
                    Layout.fillWidth: true
                    visible: Timers.swRunning
                    variant: "normal"
                    glyph:   "󰑐"
                    label:   "Lap"
                    onActivated: Timers.lap()
                }
                PanelButton {
                    Layout.fillWidth: true
                    visible: !Timers.swRunning && Timers.swElapsed > 0
                    variant: "normal"
                    glyph:   "󰜉"
                    label:   "Reset"
                    onActivated: Timers.resetStopwatch()
                }
            }

            // Laps, newest first, capped at four — a corner of an overlay, not a race.
            ColumnLayout {
                Layout.fillWidth: true
                visible: Timers.laps.length > 0
                spacing: Tokens.spacingXs

                Divider {}

                Repeater {
                    model: Timers.laps.slice(0, 4)

                    RowLayout {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true

                        StyledText {
                            text: "Lap " + (Timers.laps.length - index)
                            variant: "caption"
                            emphasis: "dim"
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: Timers.lapString(modelData)
                            font.family: Tokens.fontMono
                            variant: "caption"
                            emphasis: "muted"
                        }
                    }
                }
            }
        }

        // ══ ALARM ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            visible: Timers.mode === "alarm"
            spacing: Tokens.spacingLg

            // The alarm being dialled.
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: Timers.pad(root.newH) + ":" + Timers.pad(root.newM)
                font.family: Tokens.fontMono
                font.pixelSize: 38
                font.bold: true
                color: Colors.fg
            }

            // HH : MM setter.
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacingLg

                Repeater {
                    model: [ { hour: true, suffix: "h" }, { hour: false, suffix: "m" } ]

                    RowLayout {
                        required property var modelData
                        spacing: Tokens.spacingXs

                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: "󰍴"
                            onActivated: root.bumpNew(modelData.hour, -1)
                        }
                        StyledText {
                            text: Timers.pad(modelData.hour ? root.newH : root.newM) + modelData.suffix
                            font.family: Tokens.fontMono
                            variant: "label"
                            font.bold: true
                        }
                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: "󰐕"
                            onActivated: root.bumpNew(modelData.hour, 1)
                        }
                    }
                }
            }

            PanelButton {
                Layout.fillWidth: true
                variant: "primary"
                accent:  Colors.focus
                glyph:   "󰀤"                              // 󰀤 alarm-plus
                label:   "Add alarm"
                onActivated: Timers.addAlarm(root.newH, root.newM)
            }

            // The armed alarms. Fixed to a few rows so the card's height stays stable;
            // any beyond still fire — they're the service's, not the card's — they just
            // roll up into a "+N more".
            ColumnLayout {
                Layout.fillWidth: true
                visible: Timers.alarms.length > 0
                spacing: Tokens.spacingXs

                Divider {}

                Repeater {
                    model: Timers.alarms.slice(0, 3)

                    RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        StyledText {
                            text: Timers.pad(modelData.h) + ":" + Timers.pad(modelData.m)
                            font.family: Tokens.fontMono
                            variant: "label"
                            font.bold: true
                            color: modelData.enabled ? Colors.fg : Colors.fgDim
                        }

                        Item { Layout.fillWidth: true }

                        // Arm / disarm — one-shot, so a fired alarm lands here disarmed to
                        // re-arm with a tap.
                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: modelData.enabled ? "󰀠" : "󰀣"   // alarm / alarm-off
                            glyphTint: modelData.enabled ? Colors.focus : Colors.fgDim
                            onActivated: Timers.toggleAlarm(modelData.id)
                        }
                        PanelButton {
                            variant: "ghost"; implicitWidth: 22; implicitHeight: 22
                            glyph: "󰅖"
                            onActivated: Timers.removeAlarm(modelData.id)
                        }
                    }
                }

                StyledText {
                    visible: Timers.alarms.length > 3
                    text: "+" + (Timers.alarms.length - 3) + " more"
                    variant: "caption"
                    emphasis: "dim"
                }
            }
        }
    }
}
