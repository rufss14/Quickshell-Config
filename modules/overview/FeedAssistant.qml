import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── FeedAssistant ─────────────────────────────────────────────────────────────
// The left face's AI page (OverviewFeed): a chat with the provider the launcher's `?` uses (Ai — a
// model on this machine by default, Claude Pro, or an API key) that OPERATES the shell — colours,
// settings, wallpaper, sound, brightness, media, workspaces, apps, timers, the shell's own actions
// (services/Assistant + assistant.js, which decide what's allowed). Changes happen as the reply lands,
// each a card with Undo; the few that ask first wait on their card.
//
// The conversation (redesigned 2026-10-24, the user: "prettier, pleasant to use, good and smooth
// animations"): a ListView over a ListModel kept in step with Assistant.messages by APPENDING
// (`sync`), so a new turn is the only delegate built — it slides in (`add`), a reply types itself out
// and deals its cards (ChatMessage), and the list glides to the end (`glide`). The thread's head is
// the local AI's setup (LocalAiSetup) until it's ready, or the ideas when there's nothing yet; its foot
// is the reply on its way (dots that hop, or the words as they stream) and any error. The box is
// ChatComposer: the send button inside the pill.
//
// No key yet (a cloud provider): the page takes one in place (Ai.saveKey, stdin → 0600). The tune chip
// picks the provider, and for the local one its models (LocalModelList).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property bool current: false
    property color accent: Colors.of(QsWindow.window).primary
    readonly property Flickable flick: chat

    // The provider row, under the header.
    property bool picking: false

    readonly property string blocker: Ai.blocker()
    readonly property bool needsKey: Config.aiEnabled && Ai.needsKey && !Ai.ready
    readonly property bool localSetup: Config.aiEnabled && Ai.provider === "ollama" && !LocalAi.ready
    onCurrentChanged: if (root.current && Ai.provider === "ollama") LocalAi.refresh()

    function send(text) {
        const t = (text || "").trim()
        // "Hey Claude" TYPED is someone looking for the voice switch, not a request: show it.
        if (/^(hey|okay|ok)[ ,]+claude[!.? ]*$/i.test(t)) { root.picking = true; composer.clear(); return }
        if (t === "" || Assistant.busy || root.blocker !== "") return
        Assistant.ask(t)
        composer.clear()
    }

    // ── The thread, appended to ───────────────────────────────────────────────
    ListModel { id: thread }
    function sync(animate) {
        const ms = Assistant.messages
        if (ms.length < thread.count) thread.clear()
        for (let i = thread.count; i < ms.length; i++)
            thread.append({ m: i, role: ms[i].role, body: ms[i].text, acts: JSON.stringify(ms[i].actions ?? []), fresh: animate })
        root.scrollEnd()
    }
    Component.onCompleted: root.sync(false)
    Connections {
        target: Assistant
        function onMessagesChanged() { root.sync(true) }
        function onPendingChanged() { root.scrollEnd() }
        function onBusyChanged() { root.scrollEnd() }
    }

    // To the end, gliding — a beat later, once the new row has its height.
    function scrollEnd() { endSoon.restart() }
    Timer {
        id: endSoon
        interval: 30
        onTriggered: {
            const to = Math.max(chat.originY, chat.originY + chat.contentHeight - chat.height)
            glide.stop()
            if (!Config.motionEnabled) { chat.contentY = to; return }
            glide.from = chat.contentY
            glide.to = to
            glide.start()
        }
    }
    NumberAnimation { id: glide; target: chat; property: "contentY"; duration: Motion.spatial; easing.type: Motion.travel }

    // The answer as it streams, without the action blocks being typed out (they become cards).
    readonly property string pendingText: {
        const p = Assistant.pending
        const i = p.indexOf("```")
        return (i >= 0 ? p.slice(0, i) : p).trim()
    }
    readonly property bool pendingActs: Assistant.pending.indexOf("```") >= 0

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        FeedHeader {
            Layout.fillWidth: true
            Layout.fillHeight: false
            symbol: "auto_awesome"
            title: Translation.tr("Ask")
            tail: Ai.label
            accent: root.accent
            hot: Assistant.busy
            subtitle: root.blocker !== "" ? root.blocker
                    : Assistant.busy ? (Assistant.thinking ? Translation.tr("Thinking…") : Translation.tr("Answering…"))
                    : (Ai.provider === "ollama" ? LocalAi.model + "  ·  " + Translation.tr("on this computer")
                                                : Translation.tr("Runs your shell for you"))
                      + (Config.aiVoice && VoiceAssistant.state === "idle" ? "  ·  " + Translation.tr("say “hey claude”") : "")

            ChipTray {
                ChipButton {
                    visible: Assistant.hasThread
                    symbol: "add"
                    tint: root.accent
                    onActivated: Assistant.clear()
                }
                ChipButton {
                    symbol: "tune"
                    on: root.picking
                    tint: root.accent
                    onActivated: root.picking = !root.picking
                }
            }
        }

        // ── Who answers ─────────────────────────────────────────────────────────
        // Switching starts the new provider on its own default model (Config.aiModel "").
        Flow {
            id: providers
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.picking
            spacing: Tokens.spacingXs
            ViewEnter { target: providers; active: root.picking; rise: Tokens.spacingSm }
            Repeater {
                model: Ai.providers
                delegate: ChipButton {
                    required property var modelData
                    label: modelData.label
                    on: Ai.provider === modelData.id
                    tint: root.accent
                    onActivated: {
                        if (Ai.provider !== modelData.id) { Config.aiProvider = modelData.id; Config.aiModel = "" }
                        Ai.refreshKeys()
                        if (modelData.id === "ollama") LocalAi.refresh()
                        root.picking = modelData.id === "ollama" && LocalAi.running
                    }
                }
            }
        }
        // "Hey Claude": voice requests (services/VoiceAssistant).
        VoiceSetupRow {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.picking
            accent: root.accent
        }
        // The local AI's models, to switch or fetch another (once it's running).
        LocalModelList {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.picking && Ai.provider === "ollama" && LocalAi.running
            accent: root.accent
        }

        // ── A key, typed here ───────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.needsKey
            spacing: Tokens.spacingXs
            InputField {
                id: keyField
                Layout.fillWidth: true
                implicitHeight: Tokens.iconXl + Tokens.spacingMd
                cornerRadius: implicitHeight / 2
                icon: "key"
                secret: true
                placeholder: Translation.tr("Paste your %1 API key").arg(Ai.label)
                onAccepted: value => { Ai.saveKey(Ai.provider, value); keyField.clear() }
            }
            StyledText {
                Layout.fillWidth: true
                text: Ai.keyHelp
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.Wrap
            }
            ChipButton {
                visible: Ai.keyUrl !== ""
                symbol: "open_in_new"
                label: Translation.tr("Get a key")
                tint: root.accent
                onActivated: Qt.openUrlExternally(Ai.keyUrl)
            }
        }

        // ── The conversation ────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: chat
                anchors.fill: parent
                clip: true
                spacing: Tokens.spacingMd
                boundsBehavior: Flickable.StopAtBounds
                // Scrolled by the face's wheel and drag (OverviewFeed); a mouse drag here is the swipe.
                interactive: false
                model: thread

                delegate: ChatMessage {
                    accent: root.accent
                }

                // A new turn rises into place and settles from a touch smaller.
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.standard; easing.type: Motion.enter }
                        NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring }
                        NumberAnimation { property: "y"; from: ViewTransition.destination.y + Tokens.spacingXl; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                    }
                }
                displaced: Transition {
                    NumberAnimation { properties: "y"; duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
                }

                // ── The head: the local AI's setup, or the ideas ────────────────
                header: Column {
                    width: chat.width
                    spacing: Tokens.spacingMd
                    bottomPadding: (root.localSetup || thread.count === 0) && !Assistant.busy ? Tokens.spacingMd : 0
                    // The ideas sit in the middle of the room the face has, not in a clump under its header with a
                    // blank stretch above the composer (2026-11-03 review).
                    topPadding: ideas.visible ? Math.max(0, Math.round((chat.height - ideas.implicitHeight) / 2 - Tokens.spacingXl)) : 0

                    LocalAiSetup {
                        width: parent.width
                        visible: root.localSetup
                        accent: root.accent
                        onCloudAsked: root.picking = true
                    }
                    ChatIdeas {
                        id: ideas
                        width: parent.width
                        visible: thread.count === 0 && !Assistant.busy && !root.needsKey && !root.localSetup
                        accent: root.accent
                        enabled: root.blocker === ""
                        onPicked: text => root.send(text)
                    }
                }

                // ── The foot: the reply on its way, or what went wrong ──────────
                footer: Column {
                    width: chat.width
                    topPadding: Assistant.busy || errorLine.visible ? Tokens.spacingMd : 0
                    spacing: Tokens.spacingSm

                    Item {
                        id: coming
                        visible: Assistant.busy
                        width: parent.width
                        height: Math.max(26, comingBubble.height)
                        opacity: Assistant.busy ? 1 : 0
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        ScallopChip {
                            implicitWidth: 26
                            implicitHeight: 26
                            symbol: "auto_awesome"
                            tint: root.accent
                            hot: true
                        }
                        Rectangle {
                            id: comingBubble
                            readonly property int padH: Tokens.spacingMd
                            readonly property int padV: Tokens.spacingSm + 1
                            x: 26 + Tokens.spacingSm
                            width: (root.pendingText !== "" ? Math.min(live.implicitWidth, parent.width * 0.86 - x - padH * 2) : hop.width) + padH * 2
                            height: (root.pendingText !== "" ? live.height : hop.height) + (root.pendingActs ? prep.implicitHeight + Tokens.spacingXs : 0) + padV * 2
                            radius: Tokens.radiusPill
                            topLeftRadius: 5
                            color: Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceContainer, 0.94)
                            border.width: Tokens.borderWidth
                            border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)
                            Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

                            // Three dots that hop one after another.
                            Row {
                                id: hop
                                x: comingBubble.padH
                                y: comingBubble.padV
                                visible: root.pendingText === ""
                                spacing: Tokens.spacingXs + 1
                                height: 16
                                Repeater {
                                    model: 3
                                    delegate: Rectangle {
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 7
                                        height: 7
                                        radius: 3.5
                                        color: root.accent
                                        opacity: 0.45 + Math.max(0, -bounce.y) / 10
                                        transform: Translate { id: bounce; y: 0 }
                                        SequentialAnimation {
                                            running: Assistant.busy && Config.motionEnabled
                                            loops: Animation.Infinite
                                            PauseAnimation { duration: index * 140 }
                                            NumberAnimation { target: bounce; property: "y"; to: -5; duration: 260; easing.type: Motion.respondCurve }
                                            NumberAnimation { target: bounce; property: "y"; to: 0; duration: 320; easing.type: Easing.OutBounce }
                                            PauseAnimation { duration: (2 - index) * 140 + 260 }
                                        }
                                    }
                                }
                            }
                            StyledText {
                                id: live
                                x: comingBubble.padH
                                y: comingBubble.padV
                                visible: root.pendingText !== ""
                                width: Math.min(implicitWidth, coming.width * 0.86 - comingBubble.x - comingBubble.padH * 2)
                                text: root.pendingText
                                variant: "label"
                                wrapMode: Text.Wrap
                            }
                            StyledText {
                                id: prep
                                x: comingBubble.padH
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: comingBubble.padV
                                visible: root.pendingActs
                                text: Translation.tr("Getting it done…")
                                variant: "micro"
                                color: root.accent
                            }
                        }
                    }

                    StyledText {
                        id: errorLine
                        width: parent.width
                        visible: Assistant.error !== "" && !Assistant.busy
                        text: Assistant.error
                        variant: "caption"
                        color: Colors.of(QsWindow.window).danger
                        wrapMode: Text.Wrap
                    }
                }
            }
            Scrollbar { flickable: chat }
        }

        // ── The box ─────────────────────────────────────────────────────────────
        ChatComposer {
            id: composer
            Layout.fillWidth: true
            Layout.fillHeight: false
            accent: root.accent
            busy: Assistant.busy
            ready: root.blocker === ""
            placeholder: root.blocker !== "" ? root.blocker : Translation.tr("Ask %1 to change something…").arg(Ai.label)
            onSent: text => root.send(text)
            onStopped: Assistant.stop()
        }
    }
}
