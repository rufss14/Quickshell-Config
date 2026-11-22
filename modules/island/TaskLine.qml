pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/procs.js" as Procs

// ── TaskLine ──────────────────────────────────────────────────────────────────
// One line of the Tasks table: a task (its processes added up) or one of its processes. Columns: name, CPU,
// memory, disk. Each number sits on a cell tinted by how far it is toward the busiest row, so the eye finds the
// heavy ones without reading. Hover brings the end tools; ending asks first, on a layer over the line.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: line

    readonly property var palette: Colors.of(QsWindow.window)

    // The row's numbers, and the busiest value of each column (the cells' scale).
    property var  task: ({})          // { name, pids, … } as services/tasks.js reads it
    property string title: ""
    property string subtitle: ""
    // The app's own icon (a path from Icons.pathForAppId), or "" for a process: it gets a tile with its first letter.
    property string iconSource: ""
    property string pid: ""
    property bool selected: false
    property real cpu: 0
    property real mb: 0
    property real disk: 0
    property real gpu: 0
    property real peakCpu: 1
    property real peakMb: 1
    property real peakDisk: 1
    property real peakGpu: 1
    property string sortBy: "cpu"
    property int indent: 0
    property bool member: false
    property bool expandable: false
    property bool expanded: false
    // The confirm layer is up on this line; the parent owns which line that is.
    property bool armed: false
    // Its place in the set it arrives with (the cascade's beat); the parent sets it.
    property int entrance: 0
    signal toggled()
    signal picked()
    signal arm()
    signal disarm()

    // The pid the layer copies: a process's own, or a task's first one.
    readonly property string pidText: line.pid !== "" ? line.pid : (line.task.pids && line.task.pids.length > 0 ? String(line.task.pids[0]) : "")
    readonly property bool hot: !line.member && (line.cpu >= 50 || line.gpu >= 60)
    readonly property bool guarded: Procs.protectedRow(line.task)

    // Column widths, shared with the header in IslandTasks.
    readonly property real pidW:  Tokens.spacingXxl * 2.25
    readonly property real gpuW:  Tokens.spacingXxl * 3
    readonly property real cpuW:  Tokens.spacingXxl * 3
    readonly property real memW:  Tokens.spacingXxl * 3.6
    readonly property real diskW: Tokens.spacingXxl * 3.2
    readonly property real toolsW: Tokens.iconMd

    width: parent ? parent.width : 0
    height: Tokens.iconXl + Tokens.spacingLg
    radius: Tokens.radiusSm
    color: line.member ? "transparent" : line.palette.plate
    clip: true

    HoverHandler { id: hover }

    // 0 at rest, 1 with the options open. The number cells ride it out of the way and the strip rides it open.
    SpringValue { id: gone; spec: Motion.springSpatial; epsilon: 0.001; target: line.armed ? 1 : 0 }

    // ── Motion ────────────────────────────────────────────────────────────────
    // Quiet: it fades up with its neighbours (PopIn's opacity), and the pointer only washes it.
    PopIn { id: pop; active: line.visible; index: line.entrance }
    opacity: pop.opacity
    Behavior on border.width { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }

    // A soft wash under the pointer.
    Rectangle {
        anchors.fill: parent
        radius: line.radius
        color: line.palette.fg
        opacity: hover.hovered && !line.armed ? 0.05 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond; easing.type: Motion.travel } }
    }

    // The selected line wears the accent; a press on empty space selects it (the toolbar then acts on it).
    border.width: line.selected ? Tokens.borderWidth * 2 : 0
    border.color: line.palette.primary
    // Left selects. Right opens the options IN the line (no popup): the line becomes a row of buttons.
    MouseArea {
        id: press
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => { if (mouse.button === Qt.RightButton) line.arm(); else line.picked() }
    }

    function cellTint(v, peak) {
        const share = Math.min(1, v / Math.max(0.0001, peak))
        return line.palette.alpha(line.palette.primary, 0.05 + 0.32 * share)
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Tokens.spacingSm + line.indent * Tokens.spacingLg
        anchors.rightMargin: Tokens.spacingSm
        spacing: Tokens.spacingSm

        // The chevron opens a task's processes; a process has none.
        Item {
            // Always takes its place, so every icon lines up whether or not the task has processes to open.
            Layout.preferredWidth: Tokens.iconLg
            Layout.preferredHeight: Tokens.iconLg
            SpringValue { id: turn; spec: Motion.springSpatialFast; target: line.expanded ? 90 : 0 }
            MaterialIcon {
                anchors.centerIn: parent
                visible: line.expandable
                name: "chevron_right"
                rotation: turn.value
                font.pixelSize: Tokens.iconLg
                color: line.palette.fgMuted
            }
            MouseArea {
                anchors.fill: parent
                anchors.margins: -Tokens.spacingXs
                enabled: line.expandable
                cursorShape: Qt.PointingHandCursor
                onClicked: line.toggled()
                Accessible.role: Accessible.Button
                Accessible.name: line.expanded ? Translation.tr("Hide the processes") : Translation.tr("Show the processes")
                Accessible.onPressAction: line.toggled()
            }
        }
        // The task's face: the app's own icon on a soft tile, or the first letter of a process on the accent's.
        Rectangle {
            visible: !line.member
            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingSm
            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingSm
            radius: Tokens.radiusSm
            color: line.iconSource !== "" ? line.palette.alpha(line.palette.fg, 0.06) : line.palette.primaryContainer
            Image {
                anchors.centerIn: parent
                width: Tokens.iconXl
                height: Tokens.iconXl
                visible: line.iconSource !== ""
                source: line.iconSource
                sourceSize: Qt.size(width * 2, height * 2)
                asynchronous: true
                fillMode: Image.PreserveAspectFit
            }
            StyledText {
                anchors.centerIn: parent
                visible: line.iconSource === ""
                text: line.title.charAt(0).toUpperCase()
                variant: "title"
                font.weight: Font.Bold
                color: line.palette.fgOnPrimaryContainer
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                StyledText {
                    Layout.fillWidth: true
                    text: line.title
                    variant: line.member ? "caption" : "label"
                    font.weight: line.member ? Font.Normal : Font.DemiBold
                    font.features: ({ tnum: 1 })
                    elide: Text.ElideRight
                }
                // A task that is working hard wears a gauge that pulses.
                MaterialIcon {
                    id: hotIcon
                    visible: line.hot
                    name: "speed"
                    fill: 1
                    font.pixelSize: Tokens.iconMd
                    color: line.palette.primary
                    SequentialAnimation on scale {
                        running: line.hot && line.visible && Motion.ambientOn
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.3; duration: Motion.standard * 3; easing.type: Motion.travel }
                        NumberAnimation { to: 1.0; duration: Motion.standard * 3; easing.type: Motion.travel }
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: line.subtitle !== ""
                text: line.subtitle
                variant: "caption"
                emphasis: "dim"
                elide: Text.ElideRight
            }
        }

        StyledText {
            Layout.preferredWidth: line.pidW
            horizontalAlignment: Text.AlignHCenter
            text: line.pid
            variant: "caption"
            emphasis: "dim"
            font.features: ({ tnum: 1 })
        }
        Rectangle {
            Layout.preferredWidth: line.cpuW
            Layout.preferredHeight: parent.height - Tokens.spacingXs * 2
            radius: Tokens.radiusSm
            color: line.cellTint(line.cpu, line.peakCpu)
            opacity: 1 - Math.min(1, gone.value * 1.5)
            transform: Translate { x: -gone.value * Tokens.spacingLg * 1 }
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            StyledText {
                anchors.centerIn: parent
                text: line.cpu.toFixed(1) + "%"
                variant: "label"
                font.weight: line.sortBy === "cpu" ? Font.DemiBold : Font.Normal
                font.features: ({ tnum: 1 })
            }
        }
        Rectangle {
            Layout.preferredWidth: line.memW
            Layout.preferredHeight: parent.height - Tokens.spacingXs * 2
            radius: Tokens.radiusSm
            color: line.cellTint(line.mb, line.peakMb)
            opacity: 1 - Math.min(1, gone.value * 1.5)
            transform: Translate { x: -gone.value * Tokens.spacingLg * 2 }
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            StyledText {
                anchors.centerIn: parent
                text: line.mb >= 1024 ? (line.mb / 1024).toFixed(1) + " GB" : Math.round(line.mb) + " MB"
                variant: "label"
                font.weight: line.sortBy === "mem" ? Font.DemiBold : Font.Normal
                font.features: ({ tnum: 1 })
            }
        }
        Rectangle {
            Layout.preferredWidth: line.diskW
            Layout.preferredHeight: parent.height - Tokens.spacingXs * 2
            radius: Tokens.radiusSm
            color: line.cellTint(line.disk, line.peakDisk)
            opacity: 1 - Math.min(1, gone.value * 1.5)
            transform: Translate { x: -gone.value * Tokens.spacingLg * 3 }
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            StyledText {
                anchors.centerIn: parent
                text: line.disk >= 1 ? line.disk.toFixed(1) + " MB/s" : (line.disk * 1024).toFixed(0) + " KB/s"
                variant: "label"
                font.weight: line.sortBy === "disk" ? Font.DemiBold : Font.Normal
                font.features: ({ tnum: 1 })
            }
        }

        Rectangle {
            Layout.preferredWidth: line.gpuW
            Layout.preferredHeight: parent.height - Tokens.spacingXs * 2
            radius: Tokens.radiusSm
            color: line.cellTint(line.gpu, line.peakGpu)
            opacity: 1 - Math.min(1, gone.value * 1.5)
            transform: Translate { x: -gone.value * Tokens.spacingLg * 4 }
            Behavior on color { ColorAnimation { duration: Motion.standard } }
            StyledText {
                anchors.centerIn: parent
                text: Math.round(line.gpu) + "%"
                variant: "label"
                font.weight: line.sortBy === "gpu" ? Font.DemiBold : Font.Normal
                font.features: ({ tnum: 1 })
            }
        }

        // The last slot is always here (the header keeps the same one); a protected task shows its lock in it.
        Item {
            Layout.preferredWidth: line.toolsW
            Layout.preferredHeight: Tokens.iconMd
            MaterialIcon {
                anchors.centerIn: parent
                visible: line.guarded
                name: "lock"
                font.pixelSize: Tokens.iconMd
                color: line.palette.fgMuted
                Accessible.name: Translation.tr("Protected: the shell does not end this")
            }
        }
    }

    // The options layer, opened by a right click: the line itself turns into the buttons. End asks the task to
    // quit (SIGTERM), Force end kills it, Copy PID puts its process id on the clipboard, the cross closes it.
    // ── The options, opened by a right click ──────────────────────────────────
    // The name, the icon and the PID stay put. The number cells slide left and fade, each a little further than the
    // one before; a pill springs open from the right edge into the strip they leave, easing from a pill to a
    // rounded bar, and the buttons pop in one after another. End asks the task to quit (SIGTERM), Force end kills
    // it, Copy PID copies its process id.
    Item {
        id: options
        anchors.right: parent.right
        anchors.rightMargin: Tokens.spacingSm + line.toolsW + Tokens.spacingSm
        anchors.verticalCenter: parent.verticalCenter
        readonly property real full: line.cpuW + line.memW + line.diskW + line.gpuW + Tokens.spacingSm * 3
        width: options.full * Math.min(1, gone.value)
        height: parent.height - Tokens.spacingXs * 2
        clip: true
        visible: gone.value > 0.01

        Rectangle {
            anchors.right: parent.right
            width: options.full
            height: parent.height
            radius: Tokens.radiusSm + (height / 2 - Tokens.radiusSm) * (1 - Math.min(1, gone.value))
            color: line.palette.primaryContainer
        }
        // A press on the bare strip closes it (the buttons take theirs first).
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: line.disarm()
        }
        PopIn { id: popEnd;   active: line.armed; index: 0; cap: 4 }
        PopIn { id: popForce; active: line.armed; index: 1; cap: 4 }
        PopIn { id: popCopy;  active: line.armed; index: 2; cap: 4 }
        PopIn { id: popClose; active: line.armed; index: 3; cap: 4 }
        RowLayout {
            anchors.right: parent.right
            width: options.full
            height: parent.height
            anchors.rightMargin: 0
            spacing: Tokens.spacingXs
            Item { Layout.fillWidth: true }
            StyledText {
                visible: line.guarded
                text: Translation.tr("Protected")
                variant: "label"
                color: line.palette.fgOnPrimaryContainer
                opacity: popEnd.opacity
            }
            ChipButton {
                visible: !line.guarded
                symbol: "stop"
                label: Translation.tr("End")
                solid: true
                opacity: popEnd.opacity
                scale: popEnd.scale
                onActivated: { SysStats.endTask(line.task, false); line.disarm() }
            }
            ChipButton {
                visible: !line.guarded
                symbol: "bolt"
                label: Translation.tr("Force")
                tonal: true
                opacity: popForce.opacity
                scale: popForce.scale
                onActivated: { SysStats.endTask(line.task, true); line.disarm() }
            }
            ChipButton {
                visible: line.pidText !== ""
                symbol: "content_copy"
                tonal: true
                opacity: popCopy.opacity
                scale: popCopy.scale
                onActivated: { Quickshell.execDetached(["wl-copy", line.pidText]); line.disarm() }
                Accessible.name: Translation.tr("Copy PID")
            }
            ChipButton {
                symbol: "close"
                tonal: true
                opacity: popClose.opacity
                scale: popClose.scale
                onActivated: line.disarm()
                Accessible.name: Translation.tr("Close")
            }
            Item { Layout.preferredWidth: Tokens.spacingXs }
        }
    }
}
