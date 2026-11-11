pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── VoiceOrb ──────────────────────────────────────────────────────────────────
// "Hey Claude" on screen (services/VoiceAssistant): a card at the bottom centre, on the screen you're on,
// for as long as a request is going.
//
//   listening  the cookie breathes with your voice (the mic level) and turns slowly; your words appear
//              as they're heard, big
//   thinking   the cookie turns faster; your words stay
//   answer     the reply, and under it what it did — a chip per action, its state live (done, waiting
//              for your OK, couldn't); it goes after a few seconds, or longer when something waits
//
// The card grows to the reply and back on a spring. A tap opens the overview's Ask page, where the same
// conversation (and any card waiting for an OK) is. No light effects — the movement is the shape's.
//
// Never takes the keyboard, and only the card takes the pointer (the OSD's rules, modules/osd/OsdColumn). It keeps
// its own copy of what it shows (`held…`), so the fade out isn't an empty card.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: win

    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.namespace:     "quickshell-voice"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1

    readonly property bool owns: screenOwner.owns
    ScreenOwner {
        id: screenOwner
        screen: win.screen
        open: VoiceAssistant.active
    }
    readonly property bool shown: VoiceAssistant.active && win.owns
    readonly property color accent: Colors.of(QsWindow.window).primary

    // ── What it shows, held for the fade out ──────────────────────────────────
    property string heldState: "listening"
    property string heldHeard: ""
    property string heldReply: ""
    property var heldActions: []
    Connections {
        target: VoiceAssistant
        function onStateChanged() { if (VoiceAssistant.active) win.heldState = VoiceAssistant.state }
        function onHeardChanged() { if (VoiceAssistant.active) win.heldHeard = VoiceAssistant.heard }
        function onReplyChanged() { if (VoiceAssistant.active) win.heldReply = VoiceAssistant.reply }
        function onActionsChanged() { if (VoiceAssistant.active) win.heldActions = VoiceAssistant.actions }
    }

    readonly property int room: Tokens.shadowRoom(Tokens.elevationPopup)
    readonly property int maxW: 560
    // The words' widest: the card less the cookie and its padding.
    readonly property int textW: win.maxW - 52 - Tokens.spacingLg * 3
    anchors.bottom: true
    margins.bottom: Tokens.spacingXl * 3 - win.room
    implicitWidth: win.maxW + win.room * 2
    implicitHeight: 220 + win.room * 2
    color: "transparent"
    visible: win.shown || card.opacity > 0.005
    mask: Region { item: card }

    // The level, smoothed so the cookie breathes rather than jitters.
    property real breath: 0
    Behavior on breath { NumberAnimation { duration: 140; easing.type: Motion.respondCurve } }
    Binding { target: win; property: "breath"; value: win.heldState === "listening" ? VoiceAssistant.level : 0 }

    Surface {
        id: card
        readonly property int pad: Tokens.spacingLg
        readonly property bool answering: win.heldState === "answer"
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: win.room
        width: Math.min(win.maxW, Math.max(320, body.implicitWidth + orb.width + card.pad * 2 + Tokens.spacingLg))
        height: Math.max(orb.height, body.implicitHeight) + card.pad * 2
        Behavior on width { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        Behavior on height { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
        elevation: Tokens.elevationPopup
        cornerRadius: Math.min(Tokens.radiusCard * 2, height / 2)

        opacity: win.shown ? 1 : 0
        scale: win.shown ? 1 : 0.9
        transformOrigin: Item.Bottom
        transform: Translate {
            y: win.shown ? 0 : Tokens.spacingXl
            Behavior on y { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        }
        Behavior on opacity { NumberAnimation { duration: win.shown ? Motion.standard : Motion.exit } }
        Behavior on scale { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

        // ── The cookie ────────────────────────────────────────────────────────
        Item {
            id: orb
            x: card.pad
            anchors.verticalCenter: parent.verticalCenter
            width: 52
            height: 52
            ShapeBox {
                anchors.fill: parent
                fallback: "cookie"
                fillColor: Colors.of(QsWindow.window).alpha(win.accent, 0.2 + win.breath * 0.25)
                strokeColor: Colors.of(QsWindow.window).alpha(win.accent, 0.75)
                strokeWidth: 2
                scale: 1 + win.breath * 0.3
                RotationAnimator on rotation {
                    from: 0; to: 360
                    duration: win.heldState === "thinking" ? 1600 : 9000
                    loops: Animation.Infinite
                    // The 9 s idle turn is decoration; "thinking" is a busy indicator and keeps going.
                    running: win.shown && Config.motionEnabled && (Motion.ambientOn || win.heldState === "thinking")
                }
            }
            MaterialIcon {
                anchors.centerIn: parent
                name: win.heldState === "listening" ? "mic" : "auto_awesome"
                fill: 1
                color: win.accent
                font.pixelSize: Tokens.iconMd
            }
        }

        // ── The words ─────────────────────────────────────────────────────────
        Column {
            id: body
            anchors.left: orb.right
            anchors.leftMargin: Tokens.spacingLg
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, win.textW)
            spacing: Tokens.spacingXs

            StyledText {
                text: win.heldState === "listening" ? Translation.tr("Listening…")
                    : win.heldState === "thinking" ? Translation.tr("Thinking…")
                    : Ai.label
                variant: "micro"
                font.weight: Font.DemiBold
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
                color: win.accent
            }
            // What you said — the main line until the reply comes.
            StyledText {
                width: Math.min(implicitWidth, win.textW)
                visible: !card.answering || win.heldReply === ""
                text: win.heldHeard !== "" ? win.heldHeard : Translation.tr("Say what you'd like")
                variant: "title"
                font.weight: Font.DemiBold
                opacity: win.heldHeard !== "" ? 1 : 0.5
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            // …then, smaller above the reply.
            StyledText {
                width: Math.min(implicitWidth, win.textW)
                visible: card.answering && win.heldReply !== "" && win.heldHeard !== ""
                text: "“" + win.heldHeard + "”"
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
            StyledText {
                width: Math.min(implicitWidth, win.textW)
                visible: card.answering && win.heldReply !== ""
                text: win.heldReply
                variant: "body"
                font.weight: Font.Medium
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }
            // What it did.
            Flow {
                width: win.textW
                visible: card.answering && win.heldActions.length > 0
                spacing: Tokens.spacingXs
                Repeater {
                    model: win.heldActions
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        readonly property var act: Assistant.messages[chip.modelData.m]?.actions?.[chip.modelData.a] ?? null
                        readonly property string st: chip.act && chip.act.do === "invalid" ? "invalid"
                                                   : (Assistant.stateOf(chip.modelData.m, chip.modelData.a)?.state ?? "")
                        readonly property bool bad: chip.st === "invalid" || chip.st === "failed"
                        width: chipRow.implicitWidth + Tokens.spacingMd * 2
                        height: chipRow.implicitHeight + Tokens.spacingXs * 2
                        radius: height / 2
                        color: chip.bad ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.16)
                                        : Colors.of(QsWindow.window).alpha(win.accent, chip.st === "ask" ? 0.28 : 0.16)
                        opacity: 0
                        Component.onCompleted: chipIn.start()
                        NumberAnimation { id: chipIn; target: chip; property: "opacity"; to: 1; duration: Motion.standard }
                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: chip.bad ? "error" : chip.st === "ask" ? "help" : chip.st === "working" ? "auto_awesome" : "check"
                                fill: 1
                                color: chip.bad ? Colors.of(QsWindow.window).danger : win.accent
                                font.pixelSize: Tokens.iconSm - 2
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (chip.act ? (chip.act.label || chip.act.reason || "") : "")
                                    + (chip.st === "ask" ? "  ·  " + Translation.tr("tap to confirm") : "")
                                variant: "caption"
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }
        }

        HoverHandler { cursorShape: Qt.PointingHandCursor }
        TapHandler {
            // The conversation (and any OK it waits for) is on the overview's Ask page.
            onTapped: {
                Config.overviewFeedPage = 1
                UiState.overviewOpen = true
                VoiceAssistant.cancel()
            }
        }
    }
}
