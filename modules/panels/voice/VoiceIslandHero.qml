pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"

// ── VoiceIslandHero ── part of VoicePanel.qml (island form); `panel` is the VoicePanel. ────────────────────────
// The voice page's loud card on an island, upright in the left column over the source rail (the wallpaper and
// colour pages' recipe):
//
//   top     where you are (the call, the server), and how it is doing: a dot, the words, the ping
//   middle  how long, as a big number, and who is in it as a row of faces (a ring while someone speaks)
//   foot    your own controls as lit tools: mic, headphones, screen share, camera, open Discord; Leave asks on a
//           layer (Keep / Leave), never by arming in place
//   off     not in a call: why (not running, needs setting up, or nobody to talk to) over the board beside it
//
// Screen share and camera are Discord's own keybinds (services/Discord's quarantine): a tool that cannot work says
// why in its tip and is dimmed. Everything real is services/Discord; this shows it and calls it.
// ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: hero
    required property var panel

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: hero.palette.fgOnPrimaryContainer
    readonly property color inkDim: hero.palette.alpha(hero.palette.fgOnPrimaryContainer, 0.72)
    property bool confirmLeave: false

    radius: Tokens.radiusXl
    color: hero.palette.primaryContainer
    PopIn { id: pop; active: true; index: 0 }
    opacity: pop.opacity
    scale: pop.scale

    // ── In a call ─────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm
        visible: Discord.inCall

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd
            VoiceBadge {
                symbol: "headphones"
                shape: Discord.quality === "good" ? "cookie9" : Discord.quality === "connecting" ? "squircle" : "circle"
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: Discord.callTitle
                    variant: "label"
                    font.weight: Font.DemiBold
                    color: hero.ink
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Discord.guildName !== "" ? Discord.guildName : Translation.tr("Call")
                    variant: "caption"
                    color: hero.inkDim
                    elide: Text.ElideRight
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            Rectangle {
                implicitWidth: Tokens.spacingSm
                implicitHeight: Tokens.spacingSm
                radius: width / 2
                color: hero.panel.qualityColor
            }
            StyledText {
                Layout.fillWidth: true
                text: hero.panel.tip !== "" ? hero.panel.tip
                    : Translation.tr(hero.panel.qualityText) + (Discord.ping > 0 ? " · " + Discord.ping + " ms" : "")
                variant: "caption"
                color: hero.inkDim
                elide: Text.ElideRight
            }
        }

        Item { Layout.fillHeight: true; Layout.fillWidth: true }

        StyledText {
            Layout.fillWidth: true
            text: Discord.durationText(Clock.now.getTime()) || "0:00"
            font.pixelSize: Tokens.fontDisplay * 2
            font.weight: Font.Bold
            font.features: ({ tnum: 1 })
            color: hero.ink
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Tokens.fontDisplay
        }
        // Who is in it: a face each, ringed while they speak; past six, a count.
        Row {
            Layout.fillHeight: false
            spacing: -Tokens.spacingSm
            Repeater {
                model: Discord.users.slice(0, 6)
                delegate: Item {
                    id: face
                    required property var modelData
                    width: Tokens.iconXl + Tokens.spacingXs * 2
                    height: width
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: (face.modelData.speaking ?? false) ? hero.palette.primary : hero.palette.primaryContainer
                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                    }
                    Avatar {
                        anchors.centerIn: parent
                        source: face.modelData.avatar ?? ""
                        name: face.modelData.name ?? ""
                    }
                }
            }
            StyledText {
                visible: Discord.users.length > 6
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: Tokens.spacingMd
                text: "+" + (Discord.users.length - 6)
                variant: "label"
                color: hero.ink
            }
        }

        Item { Layout.fillHeight: true; Layout.fillWidth: true }

        // Your own controls, or the leave layer in their place.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            visible: !hero.confirmLeave

            LitTool {
                symbol: Discord.mute ? "mic_off" : "mic"
                lit: Discord.mute
                ink: hero.ink
                tip: Discord.mute ? Translation.tr("Unmute") : Translation.tr("Mute")
                onActivated: Discord.toggleMute()
            }
            LitTool {
                symbol: "headphones"
                lit: Discord.deaf
                ink: hero.ink
                tip: Discord.deaf ? Translation.tr("Undeafen") : Translation.tr("Deafen")
                onActivated: Discord.toggleDeaf()
            }
            LitTool {
                symbol: "monitor"
                ink: hero.ink
                opacity: Discord.canPress(Discord.screenShareKey) ? 1 : 0.4
                tip: Discord.pressBlocker(Discord.screenShareKey) || Translation.tr("Share your screen")
                onActivated: if (Discord.canPress(Discord.screenShareKey)) hero.panel.press(Discord.screenShareKey)
            }
            LitTool {
                symbol: "videocam"
                ink: hero.ink
                opacity: Discord.canPress(Discord.cameraKey) ? 1 : 0.4
                tip: Discord.pressBlocker(Discord.cameraKey) || Translation.tr("Camera on or off")
                onActivated: if (Discord.canPress(Discord.cameraKey)) hero.panel.press(Discord.cameraKey)
            }
            LitTool {
                symbol: "open_in_new"
                ink: hero.ink
                opacity: Discord.windowAddress !== "" ? 1 : 0.4
                tip: Discord.windowAddress === "" ? Translation.tr("Discord isn't running") : Translation.tr("Open Discord")
                onActivated: if (Discord.windowAddress !== "") { hero.panel.stepAside(); Discord.focusWindow() }
            }
            Item { Layout.fillWidth: true }
            ChipButton {
                symbol: "logout"
                tint: hero.palette.danger
                Accessible.name: Translation.tr("Leave the call")
                onActivated: hero.confirmLeave = true
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            visible: hero.confirmLeave
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Leave the call?")
                variant: "label"
                font.weight: Font.DemiBold
                color: hero.ink
            }
            ChipButton {
                label: Translation.tr("Keep")
                tonal: true
                tint: hero.ink
                onActivated: hero.confirmLeave = false
            }
            ChipButton {
                symbol: "logout"
                label: Translation.tr("Leave")
                solid: true
                tint: hero.palette.danger
                onActivated: { hero.confirmLeave = false; Discord.disconnect() }
            }
        }
    }

    // ── Not in a call ─────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingSm
        visible: !Discord.inCall

        VoiceBadge {
            symbol: "headphones"
            shape: "circle"
            size: Tokens.iconXl * 2
        }
        Item { Layout.fillHeight: true }
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Not in a call")
            variant: "title"
            font.weight: Font.DemiBold
            color: hero.ink
        }
        StyledText {
            Layout.fillWidth: true
            text: Discord.needsAttention ? Translation.tr("Discord needs setting up in Settings › Discord.")
                : !Discord.connected ? Translation.tr("Discord isn't running, or isn't connected yet.")
                : Translation.tr("Join a voice channel or a call and it shows up here. Your board is beside this.")
            variant: "caption"
            color: hero.inkDim
            wrapMode: Text.Wrap
        }
        ChipButton {
            visible: Discord.windowAddress !== ""
            symbol: "open_in_new"
            label: Translation.tr("Open Discord")
            solid: true
            onActivated: { hero.panel.stepAside(); Discord.focusWindow() }
        }
    }
}
