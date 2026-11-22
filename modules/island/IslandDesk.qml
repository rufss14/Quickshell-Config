import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../panels"
import "../../services/timers.js" as TM

// ── IslandDesk ────────────────────────────────────────────────────────────────
// The bottom-left island's dashboard (2026-11-15): the sidebar's small panels mixed into one page instead of a
// page each (the user: "some panels are so small that it's worth mixing in a dashboard"). Their buttons land
// here (config/islands.js ALIAS: To-do, Clipboard, Idle).
//
//   left    the loud card: a timer at a glance (what is left, the one big button, the usual lengths) over the
//           idle rules (the switch, the first rules)
//   right   the to-do list (add, tick, remove, clear what is done) over everything copied, as cards you scroll
//           through, big enough to read (a picture shown whole, a text with its first lines and its age)
//
// The idle card grows into its editor (IslandIdle) until it fills the page, and shrinks back into the card;
// Escape closes it, or the clipboard's question, first (handleEscape). The full timer is the next
// page on this island's rail; the hero's corner tool goes there (UiState.islandGo).
//
// Everything real is the services' (Timers, Tasks, Clipboard, Inactivity); this shows them and calls them.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm
    // The two plates under the bento: tall enough for a copied picture to be seen, not just noticed.
    readonly property int lowH: Tokens.spacingXl * 8 + Tokens.spacingSm

    // Escape answers what is open on top of the bento, one layer at a time.
    function handleEscape() {
        if (root.confirmWipe) { root.confirmWipe = false; return true }
        if (root.idleOpen) { root.idleOpen = false; return true }
        return false
    }

    // ── The timer at a glance ─────────────────────────────────────────────────
    readonly property bool timerLive: Timers.timerRunning || Timers.timerPaused
    readonly property int remain: Timers.timerRemain
    readonly property string timeText: root.timerLive || Timers.timerDone ? Timers.clockString(root.remain)
                                                                          : Timers.clockString(Timers.timerTotal)
    readonly property string timeLine: Timers.timerPaused ? Translation.tr("Paused")
        : Timers.timerRunning ? (Timers.pomoOn ? Translation.tr("%1 · session %2 of %3").arg(Translation.tr(Timers.pomoLabel)).arg(Timers.pomoSession).arg(Timers.pomoEvery)
                                               : Translation.tr("Ends %1").arg(TM.endsAt(Date.now(), root.remain)))
        : Timers.timerDone ? Translation.tr("Time's up")
        : Translation.tr("Pick a length or start this one")
    function primary() {
        if (Timers.timerRunning)     Timers.pauseTimer()
        else if (Timers.timerPaused) Timers.resumeTimer()
        else                         Timers.startTimer()
    }

    // ── The idle rules ────────────────────────────────────────────────────────
    readonly property var liveRules: Inactivity.rules.filter(r => r.enabled)
    readonly property string idleLine: !Inactivity.ready ? ""
        : Inactivity.rules.length === 0 ? Translation.tr("No rules yet")
        : !Inactivity.enabled ? (Inactivity.rules.length === 1 ? Translation.tr("Off. 1 rule kept")
                                                               : Translation.tr("Off. %1 rules kept").arg(Inactivity.rules.length))
        : root.liveRules.length === 0 ? Translation.tr("On, but every rule is off")
        : root.liveRules.length === 1 ? Inactivity.describe(root.liveRules[0])
        : Translation.tr("%1, then %2 more").arg(Inactivity.describe(root.liveRules[0])).arg(root.liveRules.length - 1)

    // ── The to-do list ────────────────────────────────────────────────────────
    readonly property int total: Tasks.items.length
    readonly property bool allDone: root.total > 0 && Tasks.openCount === 0
    property bool confirmClear: false
    // Clearing the whole clipboard asks on a sheet that grows out of the button.
    property bool confirmWipe: false
    // 0..1 while the copied cards fly off before the history is wiped.
    property real wipeK: 0

    // ══ The bento ═════════════════════════════════════════════════════════════
    Loader {
        anchors.fill: parent
        sourceComponent: deskView
    }

    Component {
        id: deskView

        RowLayout {
            spacing: Tokens.spacingMd

            // ── Left: the timer (loud), the idle rules ─────────────────────────
            ColumnLayout {
                Layout.fillWidth: false
                Layout.preferredWidth: root.sideW
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                IslandPlate {
                    id: hero
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    hero: true
                    order: 0
                    radius: Tokens.radiusXl

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingMd
                            IslandBadge {
                                filled: true
                                symbol: Timers.timerDone ? "alarm" : Timers.pomoOn ? "timer" : "hourglass_bottom"
                                shape: Timers.timerDone ? "burst" : Timers.timerRunning ? "cookie9" : Timers.timerPaused ? "squircle" : "circle"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: Timers.pomoOn ? Translation.tr("Focus") : Translation.tr("Timer")
                                variant: "title"
                                font.weight: Font.DemiBold
                                color: hero.ink
                            }
                            ChipButton {
                                symbol: "chevron_right"
                                tint: hero.ink
                                Accessible.name: Translation.tr("The whole timer")
                                onActivated: UiState.islandGo("timer")
                                HoverTip { text: Translation.tr("Stopwatch, alarms and focus"); alignEnd: true }
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.fillWidth: true }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.timeText
                            font.pixelSize: Tokens.fontDisplay * 2
                            font.weight: Font.Bold
                            font.features: ({ tnum: 1 })
                            color: hero.ink
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.timeLine
                            variant: "caption"
                            color: hero.inkDim
                            elide: Text.ElideRight
                        }
                        Meter {
                            Layout.fillWidth: true
                            visible: root.timerLive
                            value: Timers.timerSpan > 0 ? Math.min(1, root.remain / Timers.timerSpan) : 0
                            accent: hero.ink
                        }

                        Item { Layout.fillHeight: true; Layout.fillWidth: true }

                        // Idle: the usual lengths start one. Running: a minute more, five more, stop.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm

                            ChipButton {
                                solid: true
                                symbol: Timers.timerRunning ? "pause" : "play_arrow"
                                label: Timers.timerRunning ? Translation.tr("Pause") : Timers.timerPaused ? Translation.tr("Resume") : Translation.tr("Start")
                                onActivated: root.primary()
                            }
                            Repeater {
                                model: root.timerLive ? [{ s: 60, t: "+1" }, { s: 300, t: "+5" }]
                                                      : [{ s: 300, t: "5" }, { s: 900, t: "15" }, { s: 1500, t: "25" }]
                                delegate: ChipButton {
                                    required property var modelData
                                    tonal: true
                                    tint: hero.ink
                                    label: root.timerLive ? Translation.tr("%1 min").arg(modelData.t) : modelData.t
                                    Accessible.name: root.timerLive ? Translation.tr("%1 minutes more").arg(modelData.t)
                                                                    : Translation.tr("Start %1 minutes").arg(modelData.t)
                                    onActivated: root.timerLive ? Timers.extendTimer(modelData.s) : Timers.startTimerFor(modelData.s)
                                }
                            }
                            Item { Layout.fillWidth: true }
                            ChipButton {
                                visible: root.timerLive || Timers.timerDone
                                symbol: "stop"
                                tint: hero.ink
                                Accessible.name: Translation.tr("Stop")
                                onActivated: Timers.stopTimer()
                            }
                        }
                    }
                }

                // ── Idle rules: the card the editor grows out of ───────────────
                IslandPlate {
                    id: idle
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: root.lowH
                    order: 2
                    clickable: true
                    onClicked: root.openIdle(idle)
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Idle rules")

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingMd

                            IslandBadge {
                                symbol: "bedtime"
                                shape: Inactivity.enabled && root.liveRules.length > 0 ? "cookie9" : "circle"
                                filled: Inactivity.enabled && root.liveRules.length > 0
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingXs
                                StyledText {
                                    text: Translation.tr("When I'm away")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.idleLine
                                    variant: "caption"
                                    emphasis: "muted"
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            Toggle {
                                checked: Inactivity.enabled
                                accessibleName: Translation.tr("Idle rules")
                                onToggled: Inactivity.setEnabled(!Inactivity.enabled)
                            }
                        }

                        Item { Layout.fillHeight: true; Layout.fillWidth: true }

                        // The first rules as small pills: what it does and after how long.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingXs

                            Repeater {
                                model: Inactivity.rules.slice(0, 2)
                                delegate: Rectangle {
                                    id: mini
                                    required property var modelData
                                    Layout.fillHeight: false
                                    implicitHeight: Tokens.iconLg + Tokens.spacingSm
                                    implicitWidth: miniRow.implicitWidth + Tokens.spacingMd * 2
                                    radius: height / 2
                                    color: root.palette.plate
                                    opacity: mini.modelData.enabled && Inactivity.enabled ? 1 : 0.55
                                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                                    Row {
                                        id: miniRow
                                        anchors.centerIn: parent
                                        spacing: Tokens.spacingXs
                                        MaterialIcon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: Inactivity.actionChips.find(c => c.value === mini.modelData.action)?.symbol ?? "bedtime"
                                            font.pixelSize: Tokens.iconMd
                                            color: root.palette.fgMuted
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: Inactivity.duration(mini.modelData.minutes)
                                            variant: "micro"
                                            font.features: ({ tnum: 1 })
                                        }
                                    }
                                }
                            }
                            StyledText {
                                visible: Inactivity.rules.length > 2
                                text: "+" + (Inactivity.rules.length - 2)
                                variant: "micro"
                                emphasis: "muted"
                            }
                            Item { Layout.fillWidth: true }
                            MaterialIcon {
                                name: "chevron_right"
                                font.pixelSize: Tokens.iconLg
                                color: root.palette.fgDim
                            }
                        }
                    }
                }
            }

            // ── Right: the to-do list, the clipboard ───────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                IslandPlate {
                    id: todo
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    order: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingMd
                            IslandBadge {
                                size: Tokens.iconXl
                                symbol: root.allDone ? "task_alt" : "checklist"
                                shape: root.allDone ? "sunny" : root.total > 0 ? "cookie7" : "circle"
                                filled: root.allDone
                            }
                            StyledText {
                                text: Translation.tr("To-do")
                                variant: "title"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.total === 0 ? "" : root.allDone ? Translation.tr("All done")
                                    : Translation.tr("%1 of %2 left").arg(Tasks.openCount).arg(root.total)
                                variant: "caption"
                                emphasis: "muted"
                                elide: Text.ElideRight
                            }
                            // Clearing what is done asks on the row, not by arming the button in place.
                            ChipButton {
                                visible: Tasks.doneCount > 0 && !root.confirmClear
                                symbol: "delete"
                                label: Translation.tr("Clear done")
                                tonal: true
                                onActivated: root.confirmClear = true
                            }
                            ChipButton {
                                visible: root.confirmClear
                                label: Translation.tr("Keep")
                                tonal: true
                                onActivated: root.confirmClear = false
                            }
                            ChipButton {
                                visible: root.confirmClear
                                symbol: "delete"
                                label: Tasks.doneCount === 1 ? Translation.tr("Clear 1") : Translation.tr("Clear %1").arg(Tasks.doneCount)
                                solid: true
                                tint: root.palette.danger
                                onActivated: { Tasks.clearDone(); root.confirmClear = false }
                            }
                        }

                        InputField {
                            id: field
                            Layout.fillWidth: true
                            icon: "add"
                            placeholder: Tasks.ready ? Translation.tr("Add a task and press Enter") : Translation.tr("Loading…")
                            enabled: Tasks.ready
                            onAccepted: function (v) {
                                Tasks.add(v)
                                field.clear()
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            StyledText {
                                anchors.centerIn: parent
                                visible: Tasks.ready && root.total === 0
                                text: Translation.tr("Nothing to do. Kept on this computer.")
                                variant: "caption"
                                emphasis: "muted"
                            }

                            ListView {
                                id: list
                                anchors.fill: parent
                                visible: root.total > 0
                                clip: true
                                interactive: list.contentHeight > list.height
                                boundsBehavior: Flickable.StopAtBounds
                                spacing: Tokens.spacingXs
                                model: Tasks.items

                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    width: ListView.view.width
                                    height: Math.max(tick.height, label.implicitHeight) + Tokens.spacingSm * 2

                                    HoverHandler { id: rowHover }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Tokens.radiusSm
                                        color: root.palette.plate
                                        opacity: row.modelData.done ? 0.55 : 1
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                    }
                                    StateLayer {
                                        anchors.fill: parent
                                        radius: Tokens.radiusSm
                                        hovered: rowHover.hovered
                                        layerColor: root.palette.fg
                                    }
                                    MaterialIcon {
                                        id: tick
                                        anchors.left: parent.left
                                        anchors.leftMargin: Tokens.spacingMd
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: row.modelData.done ? "check_circle" : "radio_button_unchecked"
                                        fill: row.modelData.done ? 1 : 0
                                        font.pixelSize: Tokens.iconLg
                                        color: row.modelData.done ? root.palette.primary : root.palette.fgMuted
                                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                                    }
                                    StyledText {
                                        id: label
                                        anchors.left: tick.right
                                        anchors.leftMargin: Tokens.spacingMd
                                        anchors.right: gone.left
                                        anchors.rightMargin: Tokens.spacingSm
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.modelData.text
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        font.strikeout: row.modelData.done
                                        emphasis: row.modelData.done ? "dim" : "normal"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Tasks.toggle(row.modelData.id)
                                        Accessible.role: Accessible.CheckBox
                                        Accessible.name: row.modelData.text
                                        Accessible.checked: row.modelData.done
                                        Accessible.onPressAction: Tasks.toggle(row.modelData.id)
                                    }
                                    // Over the row's own press: a MouseArea, so the press does not fall through to it.
                                    MaterialIcon {
                                        id: gone
                                        anchors.right: parent.right
                                        anchors.rightMargin: Tokens.spacingMd
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: "close"
                                        font.pixelSize: Tokens.iconMd
                                        color: goneArea.containsMouse ? root.palette.danger : root.palette.fgDim
                                        opacity: rowHover.hovered ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                        MouseArea {
                                            id: goneArea
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.spacingXs
                                            enabled: rowHover.hovered
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Tasks.remove(row.modelData.id)
                                            Accessible.role: Accessible.Button
                                            Accessible.name: Translation.tr("Remove %1").arg(row.modelData.text)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── What was copied, as cards you scroll through ───────────────
                IslandPlate {
                    id: clip
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: root.lowH
                    order: 3

                    // Nothing copied: the plate says so with a badge that settles in, so a wipe ends on a state
                    // and not on a blank.
                    SpringValue {
                        id: emptyK
                        target: Clipboard.count === 0 ? 1 : 0
                        spec: Motion.springSpatial
                        epsilon: 0.002
                    }
                    RowLayout {
                        anchors.centerIn: parent
                        visible: emptyK.value > 0.01
                        opacity: Math.min(1, emptyK.value)
                        scale: 0.9 + 0.1 * emptyK.value
                        spacing: Tokens.spacingMd
                        IslandBadge {
                            symbol: "content_paste"
                            shape: "cookie9"
                        }
                        StyledText {
                            text: Translation.tr("Copy something and it shows up here")
                            variant: "caption"
                            emphasis: "muted"
                        }
                    }

                    // Newest first. Drag, or the wheel, moves it sideways; a card half in view says there is more.
                    ListView {
                        id: strip
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.right: wipeBtn.left
                        anchors.margins: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingSm
                        orientation: ListView.Horizontal
                        spacing: Tokens.spacingSm
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickDeceleration: 2400
                        model: Clipboard.entries
                        readonly property int cardW: Tokens.spacingXl * 13

                        // A wheel notch glides to its place instead of jumping: each notch moves the destination,
                        // and the strip eases to it from wherever it is, so a fast spin runs on smoothly.
                        NumberAnimation {
                            id: glide
                            target: strip
                            property: "contentX"
                            duration: Motion.spatialSlow
                            easing.type: Motion.travel
                        }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: function (e) {
                                const d = e.angleDelta.x !== 0 ? e.angleDelta.x : e.angleDelta.y
                                const from = glide.running ? glide.to : strip.contentX
                                glide.stop()
                                glide.from = strip.contentX
                                glide.to = Math.max(0, Math.min(strip.contentWidth - strip.width, from - d))
                                glide.start()
                            }
                        }
                        // A drag takes over from a glide in flight.
                        onMovementStarted: glide.stop()

                        delegate: Item {
                            id: cell
                            required property var modelData
                            readonly property bool isImage: cell.modelData.kind === "image"
                            readonly property bool copied: Clipboard.justCopied === cell.modelData.hash
                            // How far this card is through flying off: the ones nearest the left edge go first.
                            readonly property real gone: Math.max(0, Math.min(1,
                                (root.wipeK * 1.6 - Math.max(0, (cell.x - strip.contentX) / strip.cardW) * 0.25) / 0.6))
                            width: strip.cardW
                            height: strip.height

                            // The card sits inside its cell by the lean's reach, so the strip's clip does not cut it.
                            Rectangle {
                                id: card
                                anchors.fill: parent
                                anchors.margins: Tokens.spacingXs
                                radius: Tokens.radiusCard
                                color: cell.copied ? root.palette.primaryContainer : root.palette.plate
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                // Leans in under the pointer, dips on a press.
                                SpringValue {
                                    id: lean
                                    target: cardArea.pressed ? 0.96 : cardArea.containsMouse ? 1.03 : 1
                                    spec: Motion.springSpatialFast
                                    epsilon: 0.002
                                }
                                scale: lean.value * (1 - 0.3 * cell.gone)
                                rotation: -8 * cell.gone
                                opacity: 1 - cell.gone
                                transform: Translate { y: cell.gone * Tokens.spacingXl }
                                clip: true

                                Image {
                                    id: shot
                                    anchors.fill: parent
                                    visible: cell.isImage && status === Image.Ready
                                    source: cell.isImage && !StreamMode.active ? "file://" + cell.modelData.file : ""
                                    sourceSize.width: 480
                                    fillMode: Image.PreserveAspectCrop
                                }
                                // A picture that is loading, or hidden while the screen is shared.
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    visible: cell.isImage && !shot.visible
                                    name: "image"
                                    font.pixelSize: Tokens.iconXl
                                    color: root.palette.fgMuted
                                }
                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingMd
                                    visible: !cell.isImage
                                    spacing: Tokens.spacingXs
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        text: Clipboard.label(cell.modelData)
                                        color: cell.copied ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 4
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: false
                                        text: Clipboard.detail(cell.modelData)
                                        variant: "micro"
                                        color: cell.copied ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72)
                                                           : root.palette.fgMuted
                                        elide: Text.ElideRight
                                    }
                                }
                                MaterialIcon {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.spacingXs
                                    visible: cell.copied
                                    name: "check"
                                    font.pixelSize: Tokens.iconMd
                                    color: root.palette.fgOnPrimaryContainer
                                }
                                MouseArea {
                                    id: cardArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Clipboard.copy(cell.modelData)
                                    Accessible.role: Accessible.Button
                                    Accessible.name: Translation.tr("Copy again: %1").arg(Clipboard.label(cell.modelData))
                                }
                            }
                        }
                    }

                    // Clear all: a tall capsule at the strip's end. Pressed, it does not ask in place: it grows
                    // leftward over the strip into the question (the sheet below), and shrinks back to itself.
                    Rectangle {
                        id: wipeBtn
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: Tokens.spacingMd
                        width: Tokens.iconXl * 2 + Tokens.spacingMd
                        radius: width / 2
                        visible: Clipboard.count > 0 || root.wipeK > 0
                        color: root.palette.plate

                        SpringValue {
                            id: wipeLean
                            target: wipeTap.pressed ? 0.94 : wipeHover.hovered ? 1.05 : 1
                            spec: Motion.springSpatialFast
                            epsilon: 0.001
                        }
                        scale: wipeLean.value

                        StateLayer {
                            anchors.fill: parent
                            radius: wipeBtn.radius
                            hovered: wipeHover.hovered
                            layerColor: root.palette.danger
                        }
                        Column {
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                name: "delete"
                                fill: wipeHover.hovered ? 1 : 0
                                font.pixelSize: Tokens.iconXl
                                color: wipeHover.hovered ? root.palette.danger : root.palette.fgMuted
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                Behavior on fill { NumberAnimation { duration: Motion.standard } }
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Translation.tr("Clear all")
                                variant: "micro"
                                emphasis: wipeHover.hovered ? "normal" : "muted"
                            }
                        }
                        HoverHandler { id: wipeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: wipeTap; onTapped: root.confirmWipe = true }
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Clear the clipboard history")
                        Accessible.onPressAction: root.confirmWipe = true
                    }

                    SpringValue {
                        id: sheetK
                        target: root.confirmWipe ? 1 : 0
                        spec: ({ stiffness: Motion.springSpatial.stiffness, damping: 1.0 })
                        epsilon: 0.002
                    }
                    // The question's words arrive after its box and are gone before it shrinks.
                    SpringValue {
                        id: sheetInk
                        target: root.confirmWipe && sheetK.value > 0.55 ? 1 : 0
                        spec: Motion.springEffects
                        epsilon: 0.01
                    }
                    Rectangle {
                        id: sheet
                        readonly property real k: Math.max(0, Math.min(1, sheetK.value))
                        readonly property real fullW: wipeBtn.parent.width - Tokens.spacingMd * 2
                        anchors.right: wipeBtn.right
                        anchors.top: wipeBtn.top
                        anchors.bottom: wipeBtn.bottom
                        width: wipeBtn.width + (sheet.fullW - wipeBtn.width) * sheet.k
                        radius: wipeBtn.radius + (Tokens.radiusCard - wipeBtn.radius) * sheet.k
                        visible: sheet.k > 0.001
                        clip: true
                        color: Qt.tint(root.palette.surfaceHigh, root.palette.alpha(root.palette.danger, 0.2 * sheet.k))
                        // Swallows presses, so nothing under the sheet copies by accident.
                        MouseArea { anchors.fill: parent; hoverEnabled: true }

                        // Laid out at its full size, so it does not reflow while the sheet grows.
                        RowLayout {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: sheet.fullW - Tokens.spacingLg * 2
                            anchors.topMargin: Tokens.spacingLg
                            anchors.bottomMargin: Tokens.spacingLg
                            anchors.rightMargin: Tokens.spacingLg
                            spacing: Tokens.spacingMd
                            opacity: sheetInk.value

                            Item {
                                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                                MorphShape {
                                    anchors.fill: parent
                                    shape: root.confirmWipe ? "cookie9" : "circle"
                                    spec: Motion.springSpatialFast
                                    fillColor: root.palette.danger
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: "delete"
                                    fill: 1
                                    font.pixelSize: Tokens.iconLg
                                    color: root.palette.fgOnPrimary
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: Tokens.spacingXs
                                StyledText {
                                    text: Translation.tr("Clear all %1?").arg(Clipboard.count)
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("Pictures too. This can't be undone.")
                                    variant: "caption"
                                    emphasis: "muted"
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                            }
                            ChipButton {
                                label: Translation.tr("Keep")
                                tonal: true
                                enabled: root.confirmWipe
                                onActivated: root.confirmWipe = false
                            }
                            ChipButton {
                                symbol: "delete"
                                label: Translation.tr("Clear all")
                                solid: true
                                tint: root.palette.danger
                                enabled: root.confirmWipe
                                onActivated: root.wipeAll()
                            }
                        }
                    }
                }
            }
        }
    }

    // The sheet is closed first, then the cards fly off, then the history is wiped: a wipe that is only
    // a vanishing is not seen to happen.
    function wipeAll() {
        root.confirmWipe = false
        wipeRun.restart()
    }
    SequentialAnimation {
        id: wipeRun
        PauseAnimation { duration: Motion.standard }
        NumberAnimation { target: root; property: "wipeK"; from: 0; to: 1; duration: Motion.spatialSlow; easing.type: Motion.travel }
        ScriptAction { script: { Clipboard.wipe(); root.wipeK = 0 } }
    }

    // ══ The idle rules, grown out of their card ═══════════════════════════════
    // The editor is the card itself getting bigger: the sheet starts on the card's rectangle and runs to the whole
    // page on two springs in a row (an S curve, the way an island opens), its corners rounding out as it goes.
    // The editor's contents are laid out at the page's size and fade in once the sheet is mostly open; closing, they
    // are gone at once and the empty sheet shrinks. It is unloaded when it is closed.
    property bool idleOpen: false
    property real fromX: 0
    property real fromY: 0
    property real fromW: 0
    property real fromH: 0
    function openIdle(card) {
        const at = card.mapToItem(root, 0, 0)
        root.fromX = at.x
        root.fromY = at.y
        root.fromW = card.width
        root.fromH = card.height
        root.idleOpen = true
    }
    SpringValue {
        id: idleReveal
        target: root.idleOpen ? 1 : 0
        spec: ({ stiffness: Motion.springSpatial.stiffness, damping: 1.0 })
        epsilon: 0.002
    }
    SpringValue {
        id: idleFollow
        target: Math.max(0, Math.min(1, idleReveal.value))
        spec: ({ stiffness: Motion.springSpatialFast.stiffness, damping: 1.0 })
        epsilon: 0.002
    }
    SpringValue {
        id: idleInk
        target: root.idleOpen && idleFollow.value > 0.6 ? 1 : 0
        spec: Motion.springEffects
        epsilon: 0.01
    }
    Rectangle {
        id: idleSheet
        readonly property real k: Math.max(0, Math.min(1, idleFollow.value))
        x: root.fromX * (1 - idleSheet.k)
        y: root.fromY * (1 - idleSheet.k)
        width: root.fromW + (root.width - root.fromW) * idleSheet.k
        height: root.fromH + (root.height - root.fromH) * idleSheet.k
        radius: Tokens.radiusCard + (Tokens.radiusXl - Tokens.radiusCard) * idleSheet.k
        color: root.palette.section
        visible: idleSheet.k > 0.001
        clip: true
        // Swallows presses over the bento underneath.
        MouseArea { anchors.fill: parent; hoverEnabled: true }

        Loader {
            x: -idleSheet.x
            y: -idleSheet.y
            width: root.width
            height: root.height
            active: idleSheet.visible
            opacity: idleInk.value
            sourceComponent: IslandIdle { onCloseRequested: root.idleOpen = false }
        }
    }
}
