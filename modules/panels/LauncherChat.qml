import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── LauncherChat ──────────────────────────────────────────────────────────────
// The `?` conversation: the thread so far, newest at the bottom, and the turn in
// flight. Lifted out of the launcher panel whole — it only ever talked to the Ai
// service, and it was 280 lines of a 1,600-line file.
//
// A ListView rather than one text block, because a conversation is rows and rows are
// what get animated in one at a time. Once a thread is open the launcher IS a chat:
// the field is the chat input and a follow-up needs no prefix.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // What the thread needs to show itself in full — the panel sizes the card from it.
    readonly property real contentH: chatView.contentHeight

    // The provider mark beside each answer, and the size the thinking bubble is built
    // around — one number, so the placeholder and the real turn line up exactly and the
    // reply does not jump when it lands.
    readonly property int avatarSize: Tokens.iconLg + Tokens.spacingXs

    readonly property bool footerActive: Ai.busy || Ai.error !== ""
    // The cost line keeps the footer open after a turn finishes, so it has somewhere
    // to sit without becoming a message in the thread.
    readonly property bool showMeta: !Ai.busy && Ai.error === "" && Ai.lastMs > 0 && Ai.hasThread

    ListView {
        id: chatView
        anchors.fill: parent
        anchors.margins: Tokens.spacingMd
        clip: true
        spacing: Tokens.spacingSm
        model: Ai.messages

        // The card is still growing toward this content, so "the end" moves for a few
        // hundred ms after a turn lands. Re-pinned on both, or the newest bubble sits
        // just below the fold exactly when it matters.
        onCountChanged:         Qt.callLater(() => chatView.positionViewAtEnd())
        onContentHeightChanged: if (!chatView.moving) chatView.positionViewAtEnd()

        // Each turn slides up into place as it arrives. `add` fires per delegate, so a
        // reply animates independently of the question above it.
        add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1
                              duration: Motion.emphasized; easing.type: Motion.enter }
            NumberAnimation { property: "y"; from: Tokens.spacingXl; duration: Motion.emphasized
                              easing.type: Easing.BezierSpline
                              easing.bezierCurve: Motion.emphasizedDecel }
        }
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Motion.standard
                              easing.type: Motion.travel }
        }

        delegate: Item {
            id: turn
            required property var modelData
            readonly property bool mine: modelData.role === "user"

            width: chatView.width
            implicitHeight: Math.max(bubble.implicitHeight, turn.mine ? 0 : root.avatarSize)

            // Only the model gets a mark; your own messages don't need telling apart
            // from themselves. Aligned to the bubble's TOP so a long answer keeps its
            // mark beside the first line rather than floating mid-paragraph.
            AiMark {
                id: avatar
                visible: !turn.mine
                anchors.left: parent.left
                anchors.top:  parent.top
                size: root.avatarSize
            }

            Surface {
                id: bubble
                // Yours on the right, the model's on the left — the oldest convention
                // there is for "who said this", and it costs nothing.
                anchors.right: turn.mine ? parent.right : undefined
                anchors.left:  turn.mine ? undefined : avatar.right
                anchors.leftMargin: turn.mine ? 0 : Tokens.spacingSm

                readonly property int padX: Tokens.spacingLg
                readonly property int padY: Tokens.spacingMd

                // Never full width: a bubble that spans the card is just a paragraph,
                // and the alignment stops carrying any meaning.
                width: Math.min(msg.implicitWidth + padX * 2,
                                chatView.width * 0.86
                                  - (turn.mine ? 0 : root.avatarSize + Tokens.spacingSm))
                implicitHeight: msg.implicitHeight + bubble.padY * 2

                // A large radius with ONE squared corner on the speaker's side is what
                // makes a stack read as a conversation rather than a column of boxes.
                elevation: Tokens.elevationNested
                cornerRadius: Tokens.radiusCard
                bottomRightRadius: turn.mine ? Tokens.radiusXs : cornerRadius
                bottomLeftRadius:  turn.mine ? cornerRadius : Tokens.radiusXs

                // Your turns carry a faint accent wash so the two voices separate at a
                // glance. The model's stay plain — it does the talking, so it does not
                // also need colouring.
                tint:       turn.mine ? Colors.of(QsWindow.window).focus : "transparent"
                tintAmount: turn.mine ? 0.14 : 0

                StyledText {
                    id: msg
                    x: bubble.padX
                    y: bubble.padY
                    width: bubble.width - bubble.padX * 2
                    text: turn.modelData.text
                    variant: "body"
                    wrapMode: Text.WordWrap
                }

                // Tap to copy, with the bubble flashing so the copy is visible —
                // silently putting something on the clipboard looks identical to a tap
                // that did nothing.
                property bool flash: false
                Timer { id: flashOff; interval: Motion.slow; onTriggered: bubble.flash = false }
                TapHandler {
                    onTapped: {
                        Clipboard.copyText(turn.modelData.text)
                        bubble.flash = true
                        flashOff.restart()
                    }
                }
                focused: bubble.flash || bubbleHover.hovered
                HoverHandler { id: bubbleHover }

                StyledText {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.spacingXs
                    text: "copied"
                    variant: "micro"
                    color: Colors.of(QsWindow.window).focus
                    opacity: bubble.flash ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                }
            }
        }

        // ── The turn in flight ────────────────────────────────────────────────
        // A footer, so neither the placeholder nor an error can end up in the thread
        // that gets sent back. Shaped exactly like a finished assistant turn — same
        // mark, same bubble, same squared corner — so the reply grows INTO the shape
        // that was already there rather than replacing a differently-shaped spinner.
        footer: Item {
            width: chatView.width
            height: (root.footerActive || root.showMeta) ? foot.implicitHeight + Tokens.spacingMd : 0
            visible: height > 0
            Behavior on height {
                NumberAnimation { duration: Motion.standard
                                  easing.type: Easing.BezierSpline
                                  easing.bezierCurve: Motion.emphasizedDecel }
            }

            Item {
                id: foot
                width: parent.width
                implicitHeight: Math.max(liveBubble.visible ? liveBubble.implicitHeight : 0,
                                         errText.visible ? errText.implicitHeight : 0,
                                         root.avatarSize)

                AiMark {
                    id: waitMark
                    anchors.left: parent.left
                    anchors.top:  parent.top
                    size: root.avatarSize
                    visible: Ai.busy
                    dim: 1.0
                    // Breathing only while there is nothing to read. Once text is
                    // arriving the text itself is the sign of life, and a pulsing mark
                    // beside it is just movement competing with reading. Gated on
                    // motion: with it off every step is 0ms and the loop would spin.
                    SequentialAnimation on dim {
                        running: Ai.thinking && Motion.slow > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.40; duration: Motion.slow
                                          easing.type: Motion.ambient }
                        NumberAnimation { to: 1.00; duration: Motion.slow
                                          easing.type: Motion.ambient }
                    }
                    onVisibleChanged: if (!visible) dim = 1.0
                }

                Surface {
                    id: liveBubble
                    anchors.left: waitMark.right
                    anchors.leftMargin: Tokens.spacingSm
                    anchors.top: parent.top
                    visible: Ai.busy

                    // Narrow while thinking — just the dots — widening only once there
                    // is text to hold. A full-width placeholder that shrinks when the
                    // answer lands is the shape change this footer exists to avoid.
                    width: Ai.thinking
                        ? root.avatarSize * 2.6
                        : parent.width - waitMark.width - Tokens.spacingSm - chatView.width * 0.10
                    Behavior on width {
                        NumberAnimation { duration: Motion.standard
                                          easing.type: Easing.BezierSpline
                                          easing.bezierCurve: Motion.emphasizedDecel }
                    }

                    implicitHeight: Ai.thinking
                        ? root.avatarSize + Tokens.spacingSm
                        : liveText.implicitHeight + Tokens.spacingMd * 2
                    height: implicitHeight
                    Behavior on implicitHeight {
                        NumberAnimation { duration: Motion.standard
                                          easing.type: Easing.BezierSpline
                                          easing.bezierCurve: Motion.emphasizedDecel }
                    }

                    elevation: Tokens.elevationNested
                    cornerRadius: Tokens.radiusCard
                    bottomLeftRadius: Tokens.radiusXs

                    TypingDots {
                        anchors.left: parent.left
                        anchors.leftMargin: Tokens.spacingLg
                        anchors.verticalCenter: parent.verticalCenter
                        running: Ai.thinking
                        visible: Ai.thinking
                        tint: Colors.of(QsWindow.window).fgDim
                    }

                    // The answer arrives whole and fades in as one block — it used to
                    // type itself out, which at any speed fast enough not to be a wait
                    // read as jitter. The bubble is already growing to meet it on the
                    // same curve, so the two read as one movement.
                    StyledText {
                        id: liveText
                        x: Tokens.spacingLg
                        y: Tokens.spacingMd
                        width: parent.width - Tokens.spacingLg * 2
                        visible: !Ai.thinking
                        opacity: Ai.thinking ? 0 : 1
                        transform: Translate { y: liveText.opacity < 1 ? Tokens.spacingSm : 0
                            Behavior on y {
                                NumberAnimation { duration: Motion.emphasized
                                                  easing.type: Easing.BezierSpline
                                                  easing.bezierCurve: Motion.emphasizedDecel }
                            }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: Motion.emphasized; easing.type: Motion.enter }
                        }
                        text: Ai.pending
                        variant: "body"
                        wrapMode: Text.WordWrap
                    }
                }

                // What the last turn cost. Quiet, and only once it is over — a
                // subscription still has limits, and a launcher you can hold a
                // conversation in is exactly where that runs away from you unnoticed.
                StyledText {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    visible: root.showMeta
                    text: (Ai.lastMs >= 1000 ? (Ai.lastMs / 1000).toFixed(1) + "s"
                                             : Ai.lastMs + "ms")
                        + (Ai.lastCost > 0 ? "  ·  $" + Ai.lastCost.toFixed(4) : "")
                    variant: "micro"
                    emphasis: "dim"
                }

                // An error belongs HERE and not in an empty answer — "the model had
                // nothing to say" and "your key is wrong" look identical otherwise.
                StyledText {
                    id: errText
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    visible: Ai.error !== "" && !Ai.busy
                    text: Ai.error
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
