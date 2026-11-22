pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/procs.js" as Procs

// ── IslandTasks ───────────────────────────────────────────────────────────────
// The Performance page's second tab, laid out as Mission Center's Processes table: a search, a column header
// that sorts (click again for the other way), one line per task with its processes folded under it (the chevron
// opens them, each with its own numbers and its own End). The numbers sit on tinted cells, the heavier the
// nearer the busiest. Ending asks first (TaskLine's layer). The compositor and the shell are not offered.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)

    // The process list is read only while this tab is on screen (SysStats.acquireTop refcounts it).
    property bool active: false
    onActiveChanged: if (root.active) SysStats.acquireTop(); else SysStats.releaseTop()
    Component.onDestruction: if (root.active) SysStats.releaseTop()

    property string sortBy: "cpu"
    // The line whose confirm layer is up: a task's name, or "name#pid" for one of its processes.
    property string armed: ""
    // Which tasks are folded open, by name.
    property var openSet: ({})
    // The task the toolbar acts on (a press on its line selects it), and the sections folded shut.
    property string selected: ""
    property var folded: ({})

    // Is a task an app? It has a desktop entry. Looked up once per name; the cache empties when the installed apps change.
    property var _appCache: ({})
    function isApp(name) {
        const hit = root._appCache[name]
        if (hit !== undefined) return hit
        const yes = DesktopEntries.heuristicLookup(name) !== null
        root._appCache[name] = yes
        return yes
    }
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { root._appCache = ({}) }
    }
    function toggleSection(key) {
        const f = Object.assign({}, root.folded)
        f[key] = !f[key]
        root.folded = f
    }

    function toggleOpen(name) {
        const o = Object.assign({}, root.openSet)
        o[name] = !o[name]
        root.openSet = o
    }
    function sortTo(by) {
        root.sortBy = by
    }

    readonly property var everything: Procs.mergeRows(SysStats.topCpu, SysStats.topMem, SysInfo.cores.length)
    readonly property var shown: Procs.sortRows(Procs.filterRows(root.everything, search.text), root.sortBy)
    // The list as drawn: an Apps header and its tasks, a Processes header and its tasks.
    readonly property var listed: Procs.sections(root.shown, root.isApp, root.folded)
    readonly property var selectedRow: root.shown.find(r => r.name === root.selected) ?? null
    readonly property int appCount: root.shown.filter(r => !Procs.protectedRow(r) && root.isApp(r.name)).length
    readonly property real peakCpu:  Math.max(0.0001, ...root.everything.map(r => r.cpu))
    readonly property real peakMb:   Math.max(0.0001, ...root.everything.map(r => r.mb))
    readonly property real peakDisk: Math.max(0.0001, ...root.everything.map(r => r.disk))
    readonly property real peakGpu:  Math.max(0.0001, ...root.everything.map(r => r.gpu))
    readonly property real totalCpu:  root.everything.reduce((a, r) => a + r.cpu, 0)
    readonly property real totalMb:   root.everything.reduce((a, r) => a + r.mb, 0)
    readonly property real totalDisk: root.everything.reduce((a, r) => a + r.disk, 0)

    // ── Keys, while this tab is up and the search is not typing ────────────────
    readonly property bool keysOn: root.active && !search.editing
    // The tasks in the order drawn (no headers), for the arrows.
    readonly property var order: root.listed.filter(r => r.head !== true)
    function step(by) {
        if (root.order.length === 0) return
        const at = root.order.findIndex(r => r.name === root.selected)
        const next = at < 0 ? (by > 0 ? 0 : root.order.length - 1) : Math.max(0, Math.min(root.order.length - 1, at + by))
        root.selected = root.order[next].name
        root.armed = ""
        list.positionViewAtIndex(root.listed.findIndex(r => r.name === root.selected), ListView.Contain)
    }
    Shortcut { sequence: "/";            enabled: root.keysOn; onActivated: search.forceFocus() }
    Shortcut { sequence: "Down";         enabled: root.keysOn; onActivated: root.step(1) }
    Shortcut { sequence: "Up";           enabled: root.keysOn; onActivated: root.step(-1) }
    Shortcut { sequence: "Delete";       enabled: root.keysOn && root.selectedRow !== null && !Procs.protectedRow(root.selectedRow); onActivated: root.armed = root.selected }
    Shortcut { sequence: "Shift+Delete"; enabled: root.keysOn && root.selectedRow !== null && !Procs.protectedRow(root.selectedRow); onActivated: SysStats.endTask(root.selectedRow, true) }
    Shortcut { sequence: "Escape";       enabled: root.keysOn && (root.armed !== "" || root.selected !== ""); onActivated: { if (root.armed !== "") root.armed = ""; else root.selected = "" } }

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingSm

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            SearchPill {
                id: search
                Layout.fillWidth: true
                lead: Translation.tr("Search tasks")
                hints: [{ key: "/", text: Translation.tr("to jump here") }]
                found: search.text === "" ? -1 : root.shown.length
                total: root.everything.length
                onEdited: root.armed = ""
            }
            // Mission Center's buttons: they act on the selected line.
            ChipButton {
                symbol: "chevron_right"
                label: Translation.tr("Collapse all")
                tonal: true
                onActivated: { root.openSet = ({}) }
            }
            ChipButton {
                symbol: "stop"
                label: Translation.tr("End")
                tonal: true
                visible: root.selectedRow !== null
                enabled: root.selectedRow !== null && !Procs.protectedRow(root.selectedRow)
                opacity: enabled ? 1 : 0.45
                onActivated: root.armed = root.selected
            }
            ChipButton {
                symbol: "bolt"
                label: Translation.tr("Force end")
                tonal: true
                visible: root.selectedRow !== null
                enabled: root.selectedRow !== null && !Procs.protectedRow(root.selectedRow)
                opacity: enabled ? 1 : 0.45
                onActivated: SysStats.endTask(root.selectedRow, true)
            }
        }

        // The column header: the same widths as TaskLine's columns, each one a sort.
        RowLayout {
            id: header
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            readonly property real lead: Tokens.iconLg + (Tokens.iconXl + Tokens.spacingSm) + Tokens.spacingSm * 3

            Item { Layout.preferredWidth: header.lead - Tokens.spacingSm }
            HeadCell {
                Layout.preferredWidth: Tokens.spacingXxl * 2.5
                label: Translation.tr("Name")
                by: "name"
                current: root.sortBy
                onPicked: root.sortTo("name")
            }
            // What is running, in the gap between the name and the numbers.
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.everything.length > 0
                    ? Translation.tr("%1 apps · %2 tasks · %3 GB in use").arg(root.appCount).arg(root.everything.length)
                        .arg((root.totalMb / 1024).toFixed(1))
                    : Translation.tr("Reading tasks…")
                variant: "caption"
                emphasis: "dim"
                font.features: ({ tnum: 1 })
                elide: Text.ElideRight
            }
            HeadCell {
                Layout.preferredWidth: line.pidW
                label: Translation.tr("PID")
                by: "pid"
                current: root.sortBy
            }
            HeadCell {
                Layout.preferredWidth: line.cpuW
                label: Translation.tr("CPU")
                icon: "speed"
                note: Math.round(SysInfo.cpu * 100) + "%"
                by: "cpu"
                current: root.sortBy
                onPicked: root.sortTo("cpu")
            }
            HeadCell {
                Layout.preferredWidth: line.memW
                label: Translation.tr("Memory")
                icon: "memory_alt"
                note: Math.round(SysInfo.memFraction * 100) + "%"
                by: "mem"
                current: root.sortBy
                onPicked: root.sortTo("mem")
            }
            HeadCell {
                Layout.preferredWidth: line.diskW
                label: Translation.tr("Disk")
                icon: "hard_drive"
                note: root.totalDisk.toFixed(1) + " MB/s"
                by: "disk"
                current: root.sortBy
                onPicked: root.sortTo("disk")
            }
            HeadCell {
                Layout.preferredWidth: line.gpuW
                label: Translation.tr("GPU")
                icon: "monitor"
                note: SysInfo.hasGpu ? Math.round(SysInfo.gpu * 100) + "%" : ""
                by: "gpu"
                current: root.sortBy
                onPicked: root.sortTo("gpu")
            }
            Item { Layout.preferredWidth: line.toolsW }
        }

        StyledText {
            Layout.fillWidth: true
            visible: SysStats.endError !== ""
            text: SysStats.endError
            variant: "caption"
            color: root.palette.danger
            wrapMode: Text.WordWrap
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacingXs
            boundsBehavior: Flickable.StopAtBounds
            // A re-sort glides: rows slide to their new places, a leaving row fades.
            displaced: Transition { NumberAnimation { properties: "y"; duration: Motion.standard; easing.type: Motion.travel } }
            remove: Transition { NumberAnimation { property: "opacity"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve } }
            model: ScriptModel { values: root.listed; objectProp: "name" }

            // Nothing to list: a cookie that turns while the tasks load and rests when none matches.
            Column {
                anchors.centerIn: parent
                spacing: Tokens.spacingSm
                visible: root.shown.length === 0
                opacity: visible ? 1 : 0
                Item {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Tokens.iconXl * 2
                    height: Tokens.iconXl * 2
                    MorphShape {
                        anchors.fill: parent
                        shape: "cookie9"
                        turns: root.everything.length === 0
                        fillColor: root.palette.alpha(root.palette.primary, 0.16)
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: root.everything.length > 0 ? "search_off" : "hourglass_top"
                        font.pixelSize: Tokens.iconXl
                        color: root.palette.primary
                    }
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.everything.length > 0 ? Translation.tr("No task matches") : Translation.tr("Reading tasks…")
                    variant: "label"
                    emphasis: "dim"
                }
            }

            delegate: Column {
                id: group
                required property var modelData
                required property int index
                readonly property bool isHead: group.modelData.head === true
                readonly property bool open: root.openSet[group.modelData.name] === true
                width: list.width
                spacing: Tokens.spacingXs

                // A section header: Apps / Processes with its count; a press folds it.
                Loader {
                    active: group.isHead
                    width: group.width
                    height: item ? item.implicitHeight : 0
                    sourceComponent: Item {
                        id: head
                        HoverHandler { id: headHover }
                        readonly property bool shut: root.folded[group.modelData.key] === true
                        implicitHeight: Tokens.iconXl + Tokens.spacingSm
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Tokens.spacingSm
                            spacing: Tokens.spacingSm
                            SpringValue { id: fold; spec: Motion.springSpatialFast; target: head.shut ? 0 : 90 }
                            MaterialIcon {
                                name: "chevron_right"
                                rotation: fold.value
                                font.pixelSize: Tokens.iconLg
                                color: root.palette.primary
                            }
                            // A badge of its own shape per section, as the pages' headers have.
                            Item {
                                Layout.preferredWidth: Tokens.iconXl
                                Layout.preferredHeight: Tokens.iconXl
                                MorphShape {
                                    anchors.fill: parent
                                    shape: headHover.hovered ? "squircle" : (group.modelData.key === "apps" ? "cookie9" : "sunny")
                                    fillColor: root.palette.alpha(root.palette.primary, 0.22)
                                }
                                MaterialIcon {
                                    anchors.centerIn: parent
                                    name: group.modelData.key === "apps" ? "apps" : "memory"
                                    font.pixelSize: Tokens.iconMd
                                    color: root.palette.primary
                                }
                            }
                            StyledText {
                                text: group.modelData.key === "apps" ? Translation.tr("Apps") : Translation.tr("Processes")
                                variant: "label"
                                font.weight: Font.DemiBold
                                color: root.palette.primary
                            }
                            Rectangle {
                                implicitWidth: countText.implicitWidth + Tokens.spacingMd
                                implicitHeight: countText.implicitHeight + Tokens.spacingXs
                                radius: height / 2
                                color: root.palette.alpha(root.palette.primary, 0.16)
                                StyledText {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: String(group.modelData.count)
                                    variant: "caption"
                                    font.weight: Font.DemiBold
                                    font.features: ({ tnum: 1 })
                                    color: root.palette.primary
                                }
                            }
                            Item { Layout.fillWidth: true }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleSection(group.modelData.key)
                            Accessible.role: Accessible.Button
                            Accessible.name: Translation.tr("Fold this section")
                            Accessible.onPressAction: root.toggleSection(group.modelData.key)
                        }
                    }
                }

                // A task, then (opened) its processes, each with its own numbers and its own End.
                Loader {
                    active: !group.isHead
                    width: group.width
                    height: item ? item.implicitHeight : 0
                    sourceComponent: Column {
                        width: group.width
                        spacing: Tokens.spacingXs

                        TaskLine {
                            width: parent.width
                            task: group.modelData
                            title: Icons.nameForAppId(group.modelData.name)
                            subtitle: group.modelData.procs === 1 ? Translation.tr("1 process") : Translation.tr("%1 processes").arg(group.modelData.procs)
                            iconSource: root.isApp(group.modelData.name) ? Icons.pathForAppId(group.modelData.name) : ""
                            pid: group.modelData.procs === 1 && group.modelData.pids.length > 0 ? String(group.modelData.pids[0]) : ""
                            cpu: group.modelData.cpu
                            mb: group.modelData.mb
                            disk: group.modelData.disk
                            gpu: group.modelData.gpu
                            peakGpu: root.peakGpu
                            peakCpu: root.peakCpu
                            peakMb: root.peakMb
                            peakDisk: root.peakDisk
                            sortBy: root.sortBy
                            selected: root.selected === group.modelData.name
                            expandable: group.modelData.members.length > 1
                            expanded: group.open
                            armed: root.armed === group.modelData.name
                            entrance: group.index
                            onPicked: root.selected = root.selected === group.modelData.name ? "" : group.modelData.name
                            onToggled: root.toggleOpen(group.modelData.name)
                            onArm: { root.selected = group.modelData.name; root.armed = group.modelData.name }
                            onDisarm: root.armed = ""
                        }
                        Repeater {
                            model: group.open ? group.modelData.members : []
                            delegate: TaskLine {
                                id: mline
                                required property var modelData
                                required property int index
                                width: parent.width
                                member: true
                                indent: 1
                                entrance: mline.index
                                task: ({ name: group.modelData.name, pids: [mline.modelData.pid] })
                                title: Translation.tr("Process %1").arg(mline.modelData.pid)
                                pid: String(mline.modelData.pid)
                                cpu: mline.modelData.cpu
                                mb: mline.modelData.mb
                                disk: mline.modelData.disk
                                gpu: mline.modelData.gpu
                                peakGpu: root.peakGpu
                                peakCpu: root.peakCpu
                                peakMb: root.peakMb
                                peakDisk: root.peakDisk
                                sortBy: root.sortBy
                                armed: root.armed === group.modelData.name + "#" + mline.modelData.pid
                                onArm: root.armed = group.modelData.name + "#" + mline.modelData.pid
                                onDisarm: root.armed = ""
                            }
                        }
                    }
                }
            }
        }
    }

    // A column title: active, it takes the accent and an arrow; a press sorts by it.
    component HeadCell: Item {
        id: cell
        property string label: ""
        property string by: ""
        property string current: ""
        property string note: ""
        property string icon: ""
        signal picked()
        implicitHeight: Tokens.iconMd + Tokens.spacingXs * 2 + (cell.note !== "" ? Tokens.iconSm : 0)
        readonly property bool on: cell.current === cell.by
        ColumnLayout {
            anchors.fill: parent
            spacing: 0
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconMd + Tokens.spacingXs * 2
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    x: cell.by === "name" ? 0 : (parent.width - width) / 2
                    spacing: Tokens.spacingXs
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: cell.icon !== ""
                        name: cell.icon
                        fill: cell.on ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: cell.on ? root.palette.primary : root.palette.fgMuted
                        scale: 1 + bloom.value
                        SpringValue { id: bloom; spec: Motion.springSpatialFast; target: cell.on ? 0.25 : 0 }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cell.label
                        variant: "caption"
                        font.weight: cell.on ? Font.DemiBold : Font.Medium
                        color: cell.on ? root.palette.primary : root.palette.fgMuted
                    }
                }
                // The sort arrow sits at the cell's edge, so showing it moves nothing.
                MaterialIcon {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "arrow_downward"
                    font.pixelSize: Tokens.iconMd
                    color: root.palette.primary
                    opacity: cell.on ? 1 : 0
                    scale: cell.on ? 1 : 0.4
                    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: cell.note !== ""
                horizontalAlignment: Text.AlignHCenter
                text: cell.note
                variant: "caption"
                font.weight: Font.DemiBold
                font.features: ({ tnum: 1 })
                color: cell.on ? root.palette.primary : root.palette.fg
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: cell.picked()
            Accessible.role: Accessible.Button
            Accessible.name: Translation.tr("Sort by %1").arg(cell.label)
            Accessible.onPressAction: cell.picked()
        }
    }

    // Column widths live in TaskLine; the header reads them from a line that is never shown.
    TaskLine { id: line; visible: false; width: 0; height: 0 }
}
