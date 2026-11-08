import "../../../services"
import "../../../state"
import QtQuick
import Quickshell
import QtQuick.Layouts
import Quickshell.Io
import "../../../config"
import "../../../components"
import "../../../services/updatefmt.js" as UF

// ── UpdateRunningView ── part of UpdatePanel.qml; `panel` is the UpdatePanel it belongs to. ──
ColumnLayout {
    id: runCol
    required property var panel
    Layout.fillWidth:  true
    Layout.fillHeight: false
    visible: panel.viewState.view === "running"
    opacity: visible ? 1 : 0
    spacing: Tokens.spacingMd
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // ── Where it is ───────────────────────────────────────────────
    Rectangle {
        id: progCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        implicitHeight: progCol.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        opacity: 0
        ViewEnter { target: progCard; active: panel.runningOn; delay: panel.lead; rise: Tokens.spacingMd }

        ColumnLayout {
            id: progCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            // The steps (pacman, then the AUR helper, then flatpak): one segment each, filled as
            // they are reached — and a guess at how long is left, once there is enough to guess from.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: panel.viewState.phaseCount > 1 || (UF.etaText(panel.viewState.elapsedSecs, panel.viewState.progress) !== "" && panel.isBusy)

                StyledText {
                    visible: panel.viewState.phaseCount > 1
                    text: "Step " + Math.max(1, panel.viewState.phaseIndex) + " of " + panel.viewState.phaseCount
                    variant: "caption"
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: panel.viewState.phaseCount > 1 ? panel.viewState.phaseCount : 0
                    delegate: Rectangle {
                        id: seg
                        required property int index
                        Layout.preferredWidth: Tokens.iconXl
                        Layout.preferredHeight: Tokens.spacingXs + 1
                        radius: height / 2
                        readonly property bool reached: seg.index < panel.viewState.phaseIndex
                        color: reached ? Colors.of(QsWindow.window).focus
                                       : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.12)
                        Behavior on color { ColorAnimation { duration: Motion.standard } }
                    }
                }
                Item { Layout.fillWidth: true }
                StyledText {
                    visible: panel.isBusy
                    text: UF.etaText(panel.viewState.elapsedSecs, panel.viewState.progress)
                    variant: "caption"
                    emphasis: "dim"
                }
            }

            // Progress + percent — the shell's shared Meter, same as the
            // settings page, with a travelling highlight overlaid for the hook
            // phase (100%, no signal, would otherwise read as hung).
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                Meter {
                    id: progBar
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    clip: true
                    value: Math.max(0, Math.min(1, panel.viewState.progress))
                    accent: panel.isError ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                    fillDuration: Motion.slow

                    Rectangle {
                        id: shimmer
                        visible: panel.viewState.inHooks && panel.isBusy
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        width: Tokens.spacingXxl * 2
                        radius: height / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 0.5; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimary, 0.5) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        NumberAnimation on x {
                            running: shimmer.visible
                            from: -shimmer.width; to: progBar.width
                            duration: 1100
                            loops: Animation.Infinite
                        }
                    }
                }

                RollText {
                    text: Math.round(Math.max(0, Math.min(1, panel.viewState.progress)) * 100) + "%"
                    family:    Tokens.fontMono
                    pixelSize: Tokens.fontLabel
                    weight:    Font.Bold
                    color: panel.isError ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
                }
            }

            // What's happening right now.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: panel.nowDoing() !== "" && !Updates.awaitingInput
                spacing: Tokens.spacingMd

                MaterialIcon { name: "download"; font.pixelSize: Tokens.iconMd; color: Colors.of(QsWindow.window).focus }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.nowDoing()
                    variant: "body"
                    font.family: Tokens.fontMono
                    elide: Text.ElideMiddle
                }
                Badge {
                    visible: panel.viewState.pkgCount > 0 && !panel.isVencord
                    label: panel.viewState.pkgsDone + " / " + panel.viewState.pkgCount
                    tint: Colors.of(QsWindow.window).focus
                    filled: true
                }
            }
        }
    }

    // ── Finished: the receipt ─────────────────────────────────────
    // A cookie with a tick (or an alert), what changed, and what to do next: reboot if the kernel
    // moved, copy the log if it went wrong, or just close.
    Rectangle {
        id: finCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: panel.isFinished
        implicitHeight: finRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        readonly property color tone: panel.isError ? Colors.of(QsWindow.window).danger
            : panel.trulyDone ? Colors.of(QsWindow.window).success : Colors.of(QsWindow.window).warning

        PopIn { id: finPop; active: finCard.visible }
        opacity: finPop.opacity
        scale:   finPop.scale

        RowLayout {
            id: finRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            Item {
                Layout.preferredWidth:  Tokens.iconXl * 2
                Layout.preferredHeight: Tokens.iconXl * 2
                Layout.alignment: Qt.AlignTop
                Scallop {
                    anchors.fill: parent
                    points: 8
                    petalDepth: 0.09
                    fillColor:   Colors.of(QsWindow.window).alpha(finCard.tone, 0.20)
                    strokeColor: Colors.of(QsWindow.window).alpha(finCard.tone, 0.35)
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: panel.isError ? "error" : panel.trulyDone ? "check" : "warning"
                    fill: 1
                    font.pixelSize: Tokens.iconLg
                    color: finCard.tone
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                StyledText {
                    Layout.fillWidth: true
                    text: panel.isError ? "That didn't finish"
                        : panel.trulyDone ? (panel.isVencord ? "Discord is patched" : "All up to date")
                        : "Finished, but some are still pending"
                    variant: "label"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: !panel.isVencord && !panel.isError
                    text: {
                        const s = [Updates.runUpgraded, Updates.runInstalled, Updates.runRemoved]
                        if (s[0] + s[1] + s[2] === 0) return "No packages changed."
                        const parts = []
                        if (s[0]) parts.push(s[0] + " upgraded")
                        if (s[1]) parts.push(s[1] + " new")
                        if (s[2]) parts.push(s[2] + " removed")
                        return parts.join("  ·  ") + (Updates.runSizeText ? "  ·  " + Updates.runSizeText : "")
                    }
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: panel.isError
                    text: Updates.runHint || "The log has the detail — copy it to share, or open Output above."
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }

                ChipTray {
                    Layout.alignment: Qt.AlignLeft
                    Layout.topMargin: Tokens.spacingXs
                    ChipButton {
                        visible: Updates.needsReboot && !panel.isError && !panel.isVencord
                        symbol:  "restart_alt"
                        label:   panel.rebootLatch.armed ? "Reboot now?" : "Reboot"
                        on:      panel.rebootLatch.armed
                        tint:    Colors.of(QsWindow.window).warning
                        onActivated: panel.rebootLatch.trigger()
                    }
                    ChipButton {
                        symbol: "content_copy"
                        label:  Translation.tr("Copy log")
                        tint:   Colors.of(QsWindow.window).info
                        onActivated: Clipboard.copyText(panel._logText())
                    }
                    ChipButton {
                        symbol: "close"
                        label:  Translation.tr("Close")
                        tint:   Colors.of(QsWindow.window).info
                        onActivated: panel._close()
                    }
                }
            }
        }
    }

    // ══ INTERACTIVE PROMPT ═════════════════════════════════════════
    // pacman/yay asked something — a conflict, a replacement, a provider
    // choice, a confirmation, or sudo re-prompting after a long build — and
    // the run is blocked on stdin until it's answered. This is the whole point
    // of the rewrite: the question is now VISIBLE and answerable, instead of
    // the run wedging silently. Cancel is always here, so a question the parser
    // didn't anticipate can never trap the panel.
    Rectangle {
        id: promptCard
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: Updates.awaitingInput
        implicitHeight: promptCol.implicitHeight + Tokens.spacingLg * 2
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section
        // The one card with an outline: it is asking for you.
        border.width: Tokens.borderWidth * 2
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.7)

        PopIn { id: promptPop; active: promptCard.visible }
        opacity: promptPop.opacity
        scale:   promptPop.scale

        ColumnLayout {
            id: promptCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.spacingLg
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                MaterialIcon { name: "help"; fill: 1; font.pixelSize: Tokens.iconMd; color: Colors.of(QsWindow.window).focus }
                StyledText {
                    text: Translation.tr("The update needs your input")
                    variant: "body"
                    font.weight: Font.DemiBold
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: Updates.promptText
                variant: "caption"
                color: Colors.of(QsWindow.window).fg
                font.family: Tokens.fontMono
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 4
                elide: Text.ElideRight
            }

            // Yes / No — the default answer is the filled one.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Updates.promptKind === "yesno"

                ChipTray {
                    ChipButton {
                        symbol: "check"
                        label:  Translation.tr("Yes")
                        on:     Updates.promptDefault === "y"
                        tint:   Colors.of(QsWindow.window).focus
                        onActivated: Updates.answerYes()
                    }
                    ChipButton {
                        symbol: "close"
                        label:  Translation.tr("No")
                        on:     Updates.promptDefault === "n"
                        tint:   Colors.of(QsWindow.window).focus
                        onActivated: Updates.answerNo()
                    }
                }
                Item { Layout.fillWidth: true }
                ChipTray {
                    ChipButton {
                        symbol: "stop"
                        label:  Translation.tr("Cancel")
                        tint:   Colors.of(QsWindow.window).danger
                        onActivated: Updates.cancelRun()
                    }
                }
            }

            // Provider number / password / anything else the process asks.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                visible: Updates.promptKind !== "yesno"
                onVisibleChanged: if (visible) answerField.forceFocus()

                InputField {
                    id: answerField
                    Layout.fillWidth: true
                    implicitHeight: panel._fieldH
                    cornerRadius: implicitHeight / 2
                    secret: Updates.promptKind === "password"
                    icon: Updates.promptKind === "password" ? "lock" : ""
                    placeholder: Updates.promptKind === "password" ? "Password"
                        : Updates.promptKind === "number"
                            ? ("A number" + (Updates.promptDefault !== ""
                                ? " (default " + Updates.promptDefault + ")" : ""))
                            : "Type your answer, then Send"
                    // Enter answers (`accepted`: Enter and only Enter); the field clears for the next question.
                    onAccepted: (value) => { Updates.answer(value); answerField.clear() }
                    onKeyPressed: (event) => { if (event.key === Qt.Key_Escape) { panel._escClose(); event.accepted = true } }
                }
                ChipTray {
                    ChipButton {
                        symbol: "arrow_upward"
                        label:  Translation.tr("Send")
                        on:     true
                        tint:   Colors.of(QsWindow.window).focus
                        onActivated: { Updates.answer(answerField.text); answerField.clear() }
                    }
                    ChipButton {
                        symbol: "stop"
                        tint:   Colors.of(QsWindow.window).danger
                        onActivated: Updates.cancelRun()
                    }
                }
            }
        }
    }

    // Expand / collapse the activity feed. The header's terminal chip does the same thing; this
    // keeps it discoverable without spending a full button's worth of height on it.
    ChipTray {
        Layout.alignment: Qt.AlignHCenter
        visible: !Updates.awaitingInput
        ChipButton {
            symbol: panel.expanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
            label:  panel.expanded ? "Hide activity" : "Show activity"
            tint:   Colors.of(QsWindow.window).info
            onActivated: panel.expanded = !panel.expanded
        }
    }

    // ══ ACTIVITY — only when expanded and not prompting ════════════
    Rectangle {
        id: activityCard
        Layout.fillWidth:  true
        Layout.fillHeight: false
        Layout.preferredHeight: 220
        visible: panel.expanded && !Updates.awaitingInput
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).section

        PopIn { id: actPop; active: activityCard.visible }
        opacity: actPop.opacity
        scale:   actPop.scale

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            // Output (the raw log) or Simple (a tick per package) — two views of the same run.
            SegmentSwitch {
                Layout.fillWidth: true
                Layout.fillHeight: false
                accent: Colors.of(QsWindow.window).info
                model: [
                    { value: true,  label: "Output", icon: "terminal"  },
                    { value: false, label: "Simple", icon: "checklist" }
                ]
                current: panel.showDetails
                onPicked: (v) => panel.showDetails = v
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── The friendly feed ──────────────────────────────
                ListView {
                    anchors.fill: parent
                    visible: !panel.showDetails
                    clip: true
                    model: panel.activityModel
                    spacing: Tokens.spacingXs

                    delegate: RowLayout {
                        required property var model
                        width: ListView.view.width
                        spacing: Tokens.spacingSm

                        MaterialIcon { name: "check_circle"; fill: 1; font.pixelSize: Tokens.iconSm; color: Colors.of(QsWindow.window).success }
                        StyledText {
                            Layout.fillWidth: true
                            text: model.name
                            variant: "caption"
                            emphasis: "muted"
                            font.family: Tokens.fontMono
                            elide: Text.ElideMiddle
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: panel.activityModel.count === 0
                        text: panel.isBusy ? "Getting started…" : "Nothing to report"
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                // ── Raw details ────────────────────────────────────
                // Bound straight to the runner's log — no local copy to keep in sync.
                ListView {
                    id: logView
                    anchors.fill: parent
                    visible: panel.showDetails
                    clip: true
                    model: Updates.runLog
                    spacing: 1

                    delegate: RowLayout {
                        required property var modelData
                        width: ListView.view.width
                        spacing: Tokens.spacingSm

                        Rectangle {
                            visible: modelData.error
                            Layout.preferredWidth: 2
                            Layout.preferredHeight: 9
                            radius: 1
                            color: Colors.of(QsWindow.window).danger
                            Layout.alignment: Qt.AlignVCenter
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: modelData.text
                            variant: "caption"
                            color: modelData.error ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                            font.family: Tokens.fontMono
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }
                    // Oldest at the top, newest at the bottom, parked on the
                    // newest — a terminal. This was `BottomToTop` paired with
                    // positionViewAtBeginning(), which rendered the log in reverse
                    // AND then parked it on the oldest line: with BottomToTop,
                    // index 0 sits at the bottom, so "the beginning" is the line
                    // furthest from what's happening now.
                    onCountChanged: Qt.callLater(() => logView.positionViewAtEnd())
                }
            }
        }
    }
}
