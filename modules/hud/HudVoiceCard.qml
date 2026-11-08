pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── HudVoiceCard ──────────────────────────────────────────────────────────────
// Your Discord call, over the workspaces:
//   · where you are — the server and the channel — with the line's quality (a dot + the
//     ping, Discord.quality) at the end; how long you've been in it is the status line;
//   · everyone in it across the card (HudFace — a ring that ripples out while they talk, a
//     badge when they can't be heard; a "+N" once they don't fit). CLICK someone and the
//     bottom row becomes THEIR volume for you (0–200 %, Discord's own per-user volume) and
//     a mute-for-me; click them again, the ✕, or yourself for your mic's volume again;
//   · mute, deafen and leave stacked at the end (leave asks twice: ArmLatch).
// Out of a call: three empty seats and what to do; with Discord not set up, it says what to
// do. Everything is services/Discord. Discord's RPC only says WHETHER someone is talking,
// not how loud, so the ripple is a steady beat while they do — not a level.
// ─────────────────────────────────────────────────────────────────────────────
HudCard {
    id: root
    wid: "voice"

    readonly property bool live: Discord.enabled && Discord.inCall

    // The call's length ticks in seconds only while there is a call to time.
    property bool _clockHeld: false
    function _syncClock() {
        if (root.live === root._clockHeld) return
        if (root.live) Clock.acquireSeconds(); else Clock.releaseSeconds()
        root._clockHeld = root.live
    }
    onLiveChanged: { root._syncClock(); if (!root.live) root.chosen = "" }
    Component.onCompleted: root._syncClock()
    Component.onDestruction: if (root._clockHeld) Clock.releaseSeconds()

    readonly property var talkers: Discord.users.filter(u => u.speaking).map(u => u.name ?? "")
    readonly property color line: Discord.quality === "good" ? root.accent
                                : Discord.quality === "bad" ? root.pal.danger : root.pal.fgMuted
    status: !Discord.enabled ? Translation.tr("Discord is off in Settings")
        : Discord.needsSetup ? Translation.tr("Needs Discord set up")
        : !Discord.inCall ? Translation.tr("Not in a call")
        : root.talkers.length === 1 ? Translation.tr("%1 is talking · %2").arg(root.talkers[0]).arg(Discord.durationText(Clock.now.getTime()))
        : root.talkers.length > 1 ? Translation.tr("%1 people talking · %2").arg(root.talkers.length).arg(Discord.durationText(Clock.now.getTime()))
        : Translation.tr("In the call · %1").arg(Discord.durationText(Clock.now.getTime()))

    // The person whose volume the bottom row sets ("" = your own mic). A copy is held for
    // the row's swap (SwapFade), so the old row fades out showing who it was.
    property string chosen: ""
    readonly property var chosenUser: root.chosen !== "" ? Discord.userById(root.chosen) : null
    readonly property string rowKey: root.chosenUser ? root.chosen : ""
    property string shownKey: ""
    property var shownUser: null

    // ── Out of a call: three empty seats ──────────────────────────────────────
    // Overlapped like an avatar stack, so each is OPAQUE (the card's own ground, tinted) with
    // the middle one in front — see-through, the overlaps doubled up and the rings crossed
    // inside each other, and the stack read as a smudge.
    Row {
        Layout.alignment: Qt.AlignVCenter
        visible: !root.live
        spacing: -Tokens.spacingMd
        Repeater {
            model: 3
            Rectangle {
                required property int index
                z: index === 1 ? 1 : 0
                width: Tokens.sideCardUnit * (index === 1 ? 1.2 : 1)
                height: width
                anchors.verticalCenter: parent.verticalCenter
                radius: width / 2
                color: Qt.tint(root.pal.surfaceHigh, root.pal.alpha(root.accent, index === 1 ? 0.16 : 0.07))
                border.width: Tokens.borderChrome
                border.color: root.pal.alpha(root.accent, index === 1 ? 0.5 : 0.22)
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: parent.index === 1
                    name: "headphones"
                    color: root.pal.alpha(root.accent, 0.7)
                    font.pixelSize: Tokens.iconMd
                }
            }
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: false
        visible: !root.live
        spacing: Tokens.spacingXs
        // The status line already says "Not in a call" / "Needs Discord set up": this says
        // only what to do about it (it used to repeat it in a title of its own as well).
        StyledText {
            Layout.fillWidth: true
            text: Discord.needsSetup ? Translation.tr("Add your Discord app's details in Settings › Discord, then join a call.")
                : Translation.tr("Join a voice channel and the people in it show up here — and on screen, if pinned.")
            variant: "label"
            emphasis: "muted"
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }
    }

    // ── In a call ─────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.live
        spacing: Tokens.spacingXs

        // Where: the server › the channel, and the line.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            MaterialIcon {
                visible: Discord.guildName !== ""
                name: "dns"
                color: root.pal.fgMuted
                font.pixelSize: Tokens.iconSm
            }
            StyledText {
                visible: Discord.guildName !== ""
                Layout.maximumWidth: Tokens.sideCardUnit * 3
                text: Discord.guildName
                variant: "caption"
                emphasis: "muted"
                elide: Text.ElideRight
            }
            MaterialIcon {
                name: Discord.guildName !== "" ? "chevron_right" : "volume_up"
                color: root.pal.fgFaint
                font.pixelSize: Tokens.iconSm
            }
            StyledText {
                Layout.fillWidth: true
                // A call with no channel name yet (Discord has not sent it) is still "a voice call", not a blank next to a ping.
                text: Discord.channelName !== "" ? Discord.channelName : Translation.tr("Voice call")
                variant: "caption"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Rectangle {
                implicitWidth: lineRow.implicitWidth + Tokens.spacingSm * 2
                implicitHeight: lineRow.implicitHeight + Tokens.spacingXs
                radius: height / 2
                color: root.pal.alpha(root.line, 0.14)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
                RowLayout {
                    id: lineRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingXs
                    Rectangle {
                        id: lineDot
                        width: Tokens.spacingSm + 2; height: width; radius: width / 2; color: root.line
                        // A slow beat while it's connecting, still once the line is up.
                        SequentialAnimation on opacity {
                            running: Discord.ping <= 0 && root.running && Config.motionEnabled
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) lineDot.opacity = 1
                            NumberAnimation { to: 0.3; duration: Motion.pulse }
                            NumberAnimation { to: 1; duration: Motion.pulse }
                        }
                    }
                    StyledText {
                        text: Discord.ping > 0 ? Discord.ping + " ms" : Translation.tr("connecting")
                        variant: "caption"
                        font.family: Tokens.fontMono
                        color: root.line
                    }
                }
            }
        }

        // Everyone in it: one row, as many as fit; the last slot becomes "+N" when they don't.
        // Click someone for their volume.
        Item {
            id: faces
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            readonly property int slot: Tokens.sideCardUnit
            readonly property int fit: Math.max(1, Math.floor((faces.width + Tokens.spacingSm) / (faces.slot + Tokens.spacingSm)))
            readonly property int extra: Discord.users.length > faces.fit ? Discord.users.length - faces.fit + 1 : 0

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Tokens.spacingSm

                Repeater {
                    model: ScriptModel {
                        values: faces.extra > 0 ? Discord.users.slice(0, faces.fit - 1) : Discord.users
                        objectProp: "id"
                    }
                    Item {
                        id: who
                        required property var modelData
                        required property int index
                        readonly property bool picked: root.chosen === who.modelData.id
                        width: faces.slot
                        height: faces.height

                        // Joins pop in, a beat apart.
                        PopIn { id: whoPop; active: root.running; index: who.index }
                        opacity: whoPop.opacity
                        scale: whoPop.scale * (whoTap.pressed ? 0.94 : 1)

                        Rectangle {
                            anchors.fill: parent
                            anchors.topMargin: Tokens.spacingXs
                            anchors.bottomMargin: Tokens.spacingXs
                            radius: Tokens.radiusCard
                            color: root.pal.alpha(root.accent, who.picked ? 0.16 : whoHover.hovered ? 0.08 : 0)
                            border.width: who.picked ? Tokens.borderChrome : 0
                            border.color: root.pal.alpha(root.accent, 0.6)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            HudFace {
                                anchors.horizontalCenter: parent.horizontalCenter
                                person: who.modelData
                                running: root.running
                            }
                            StyledText {
                                width: faces.slot - Tokens.spacingXs * 2
                                horizontalAlignment: Text.AlignHCenter
                                text: who.modelData.name ?? ""
                                variant: "caption"
                                emphasis: who.modelData.speaking || who.picked ? "normal" : "muted"
                                font.weight: who.modelData.speaking ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }
                        }
                        HoverHandler { id: whoHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            id: whoTap
                            onTapped: root.chosen = (who.picked || who.modelData.isSelf) ? "" : who.modelData.id
                        }
                    }
                }
                Rectangle {
                    visible: faces.extra > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.iconXl + Tokens.spacingMd
                    height: width
                    radius: width / 2
                    color: root.pal.alpha(root.pal.fg, 0.06)
                    StyledText {
                        anchors.centerIn: parent
                        text: "+" + faces.extra
                        variant: "label"
                        font.weight: Font.DemiBold
                    }
                }
            }
        }

        // Your mic, as loud as Discord sends it — or, with someone picked, how loud THEY are
        // for you. Sent once a drag settles (each send is a message to the RPC helper), shown
        // live meanwhile.
        RowLayout {
            id: levelRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            SwapFade {
                target: levelRow
                key: root.rowKey
                shownKey: root.shownKey
                travel: Tokens.spacingXs
                onSwapped: { root.shownKey = root.rowKey; root.shownUser = root.chosenUser; level.held = -1 }
            }
            readonly property bool them: root.shownKey !== "" && root.shownUser !== null
            // Theirs follows the live entry (it changes as Discord confirms); the held copy
            // only says WHO, for the fade out.
            readonly property var subject: levelRow.them ? (Discord.userById(root.shownKey) ?? root.shownUser) : null
            readonly property bool silenced: levelRow.them ? (levelRow.subject.mute ?? false) : Discord.mute

            Avatar {
                visible: levelRow.them
                Layout.preferredWidth: Tokens.iconMd + Tokens.spacingXs
                Layout.preferredHeight: Tokens.iconMd + Tokens.spacingXs
                source: levelRow.subject?.avatar ?? ""
                name: levelRow.subject?.name ?? ""
            }
            MaterialIcon {
                visible: !levelRow.them
                name: Discord.mute ? "mic_off" : "mic"
                color: root.pal.fgMuted
                font.pixelSize: Tokens.iconSm
                HoverTip { text: Translation.tr("How loud you are for everyone else. Click a person above to set how loud THEY are for you.") }
            }
            ValueSlider {
                id: level
                property real held: -1
                Layout.fillWidth: true
                maximum: levelRow.them ? 2 : 1
                notchAt: levelRow.them ? 1 : 0
                value: level.held >= 0 ? level.held
                     : levelRow.them ? (levelRow.subject.volume ?? 100) / 100 : Discord.inputVolume / 100
                accent: root.accent
                enabled: !levelRow.silenced
                onMoved: function (v) { level.held = v; levelSend.restart() }
                Timer {
                    id: levelSend
                    // A debounce, not motion: Motion's durations drop to 0 with animations off.
                    interval: 150
                    onTriggered: {
                        if (levelRow.them) Discord.setUserVolume(root.shownKey, Math.round(level.held * 100))
                        else Discord.setInputVolume(Math.round(level.held * 100))
                        levelHold.restart()
                    }
                }
                // Held a little past the send, until Discord's answer is back in `users`.
                Timer { id: levelHold; interval: 1200; onTriggered: level.held = -1 }
            }
            StyledText {
                Layout.preferredWidth: Tokens.sideCardUnit * 0.8
                horizontalAlignment: Text.AlignRight
                text: Math.round(level.held >= 0 ? level.held * 100
                                 : levelRow.them ? (levelRow.subject.volume ?? 100) : Discord.inputVolume) + "%"
                variant: "caption"
                emphasis: "muted"
                font.family: Tokens.fontMono
            }
            ChipButton {
                visible: levelRow.them
                symbol: levelRow.silenced ? "volume_off" : "volume_up"
                on: levelRow.silenced
                tint: root.pal.danger
                onActivated: Discord.setUserMute(root.shownKey, !levelRow.silenced)
            }
            ChipButton {
                visible: levelRow.them
                symbol: "close"
                onActivated: root.chosen = ""
            }
        }
    }

    // ── You ───────────────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: false
        visible: root.live
        spacing: Tokens.spacingXs

        ChipButton {
            Layout.fillWidth: true
            symbol: Discord.mute ? "mic_off" : "mic"
            label: Discord.mute ? Translation.tr("Mic off") : Translation.tr("Mic on")
            on: Discord.mute
            tint: root.pal.danger
            onActivated: Discord.toggleMute()
            HoverTip { text: Discord.mute ? Translation.tr("You are muted: nobody can hear you. Click to unmute.") : Translation.tr("Mute your microphone.") }
        }
        ChipButton {
            Layout.fillWidth: true
            symbol: Discord.deaf ? "headset_off" : "headphones"
            label: Discord.deaf ? Translation.tr("Speakers off") : Translation.tr("Speakers on")
            on: Discord.deaf
            tint: root.pal.danger
            onActivated: Discord.toggleDeaf()
            HoverTip { text: Discord.deaf ? Translation.tr("You cannot hear the call (and are muted). Click to hear it again.") : Translation.tr("Stop hearing the call. This also mutes you.") }
        }
        ArmLatch { id: leave; onConfirmed: Discord.disconnect() }
        ChipButton {
            Layout.fillWidth: true
            symbol: "logout"
            label: leave.armed ? Translation.tr("Leave?") : Translation.tr("Leave")
            on: leave.armed
            tint: root.pal.danger
            onActivated: leave.trigger()
            HoverTip { text: Translation.tr("Leave the call. Click twice to confirm.") }
        }
    }
}
