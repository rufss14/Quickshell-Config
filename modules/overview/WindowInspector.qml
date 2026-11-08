pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── WindowInspector ───────────────────────────────────────────────────────────
// The overview's bottom island, turned to ONE window: what it is and what you can do to it,
// without leaving the overview. Caelestia's window-info drawer (preview, details, a row of
// actions) is the reference for the shape; this shell's chips, cookies and services do the work.
//
//   ╭──────────╮  Title of the window, up to two lines          ╭ float pin full ╮   (x)
//   │ live     │  App · 3 · 1280x720 · 2 min                    ╰────────────────╯
//   ╰──────────╯
//   send ▸ 1 2 3 4 5 6 7 8 9 10     snap ▸ ▮▯ ▯▮ ▮ ◰ ◳ ◱ ◲  ⌖           12% CPU · 800 MB   ⋯
//
// Regrouped 2026-11-03 (the user: "improve layout, structure and features"): the state toggles (float, pin,
// fullscreen) are the one thing on the first row; PLACING it — a one-line map of the page's workspaces (what is
// on each, where it is) and the snap zones — is the second; everything rarer (its sound, a picture, record, the
// other screens, force quit, its workspace's page) is behind the ⋯ page, which replaces the row the way the
// workspace page does. It used to be two rows of everything, 830 px wide, squeezing the corner cards.
//
// It shows `win` — a Switcher record (Alt+Tab, the search, ←/→, or a right-click on a window
// in the grid) — and keeps its own copy (`held`) so the island can fade out showing the window
// it was showing, not a blank (CLAUDE.md: a surface that fades out keeps its own copy).
//
// Every action is ActiveWindow's (the service that already owns float/pin/fullscreen/centre/
// close/move for the bar's window panel); nothing here dispatches to Hyprland itself. The
// keyboard reaches the same functions (Overview.steer): Ctrl+F float, Ctrl+P pin,
// Ctrl+Enter fullscreen, Ctrl+W close (twice — the latch), Ctrl+1…0 move it there.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The Switcher record to show, or null.
    property var win: null
    // The grid's page, for the move-to chips: firstWorkspace … firstWorkspace + 9.
    property int firstWorkspace: 1
    property color accent: Colors.of(QsWindow.window).primary
    // The tools row shows its workspace's page instead (the ⋯ page's workspace chip), or the rarer tools (⋯).
    property bool spaceOpen: false
    property bool moreOpen: false

    property var held: null
    onWinChanged: if (root.win) { root.held = root.win; root.moreOpen = false; closeLatch.disarm(); killLatch.disarm(); allLatch.disarm() }
    Component.onCompleted: if (root.win) root.held = root.win

    readonly property var w: root.held
    readonly property var ipc: root.w?.toplevel?.lastIpcObject ?? ({})
    readonly property var geom: Hypr.geometryOf(root.w?.toplevel)
    readonly property bool floating: root.geom.floating
    readonly property bool fullscreen: root.geom.fullscreen
    readonly property bool pinned: root.ipc.pinned ?? false
    readonly property int workspaceId: root.w?.toplevel?.workspace?.id ?? root.w?.workspaceId ?? 0
    readonly property string address: root.w?.address ?? ""
    // The other screens, when there are any (Hypr.monitors); not the one this window is on.
    readonly property var otherScreens: {
        const here = Hypr.monitorForWorkspace(root.workspaceId)?.name ?? ""
        return Hypr.monitors.length > 1 ? Hypr.monitors.filter(m => m.name !== here) : []
    }

    // ── Actions — all ActiveWindow's ──────────────────────────────────────────
    function toggleFloat()      { if (root.address) ActiveWindow.toggleFloating(root.address) }
    function togglePin()        { if (root.address) ActiveWindow.togglePin(root.address) }
    function toggleFullscreen() { if (root.address) ActiveWindow.toggleFullscreen(root.address) }
    function centre()           { if (root.address) ActiveWindow.center(root.address) }
    function moveTo(ws) {
        if (!root.address || ws === root.workspaceId) return
        ActiveWindow.toWorkspace(root.address, ws)
        root.moved(ws)
    }
    // Twice: the first press arms (the button floods and asks), the second closes.
    function requestClose() { closeLatch.trigger() }

    // A window was sent to `ws` from here — the grid rings that cell (it lands there).
    signal moved(int ws)

    ArmLatch {
        id: closeLatch
        onConfirmed: if (root.address) ActiveWindow.close(root.address)
    }

    readonly property int previewH: 96
    implicitHeight: col.implicitHeight
    // One width for every page: the placing row is the widest, so the ⋯ page and the workspace page keep its width and
    // the corner cards beside the island (flankW follows it) do not move when a page is turned.
    implicitWidth: Math.max(col.implicitWidth, tools.implicitWidth)

    // ── The second row's services (2026-10-20, the user's picks) ──────────────
    // Its process tree's cost while this shows (ProcCost samples only while `pid` is set),
    // and the app's own playback streams (Audio — by app id, so it's the APP's sound: two
    // windows of one browser share it, and the row says so by being the app's).
    readonly property int pid: Number(root.ipc.pid ?? 0) || 0
    Binding { target: ProcCost; property: "pid"; value: root.pid; when: root.visible && root.pid > 0 }
    readonly property var streams: Audio.streamsFor(root.w?.appClass ?? "")
    readonly property var stream: root.streams.length > 0 ? root.streams[0] : null

    // Close every window of its workspace — twice (the third row).
    ArmLatch {
        id: allLatch
        onConfirmed: Hypr.closeAll(root.workspaceId)
    }
    ArmLatch {
        id: killLatch
        onConfirmed: if (root.address) ActiveWindow.kill(root.address)
    }

    // ── A picture of it ───────────────────────────────────────────────────────
    // Its own capture at its real size, rendered offscreen (a zero-size clipped holder keeps
    // it off the screen; grabToImage renders the item itself), saved where screenshots go and
    // handed to Screenshot — whose toast has the picture and its actions. "Copy" also puts
    // it on the clipboard. The overview over it doesn't matter: it's the window's own buffer.
    property string _grabFor: ""     // "" | "save" | "copy"
    function picture(copy) {
        if (!root.w || root._grabFor !== "") return
        const mode = copy === true ? "copy" : "save"
        Screenshot.ensureSaveDir(() => { root._grabFor = mode })
    }
    Item {
        width: 0
        height: 0
        clip: true
        ScreencopyView {
            id: grabber
            width: Math.max(1, root.geom.width)
            height: Math.max(1, root.geom.height)
            captureSource: root._grabFor !== "" ? (root.w?.wayland ?? null) : null
            live: root._grabFor !== ""
            onHasContentChanged: if (grabber.hasContent && root._grabFor !== "") root._grab()
        }
    }
    function _grab() {
        const copy = root._grabFor === "copy"
        const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19)
        const path = Screenshot.saveDir + "/window-" + stamp + ".png"
        grabber.grabToImage(function (r) {
            root._grabFor = ""
            if (!r.saveToFile(path)) return
            if (copy) Screenshot.copyToClipboard(path)
            Screenshot.present(path)
        })
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        spacing: Tokens.spacingMd

        RowLayout {
            id: row
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.previewH
            spacing: Tokens.spacingLg

            // ── The window, live ──────────────────────────────────────────────────
            // Its own capture, at its own aspect, in a rounded mask; the app's icon on a small
            // cookie in the corner, the way the grid's cards wear it.
            Item {
                id: preview
                readonly property real aspect: root.geom.height > 0 ? root.geom.width / root.geom.height : 16 / 9
                Layout.preferredHeight: root.previewH
                // The width follows the window's aspect on an M3E spring.
                SpringValue {
                    id: previewW
                    target: Math.round(Math.max(root.previewH * 0.75, Math.min(root.previewH * 2.2, root.previewH * preview.aspect)))
                    spec: Motion.springSpatial
                }
                Layout.preferredWidth: previewW.value
                Layout.alignment: Qt.AlignVCenter

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: previewMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                    Rectangle { anchors.fill: parent; color: Colors.of(QsWindow.window).surfaceContainer }
                    SharpCapture {
                        anchors.fill: parent
                        captureSource: UiState.overviewOpen ? (root.w?.wayland ?? null) : null
                        live: true
                    }
                }
                Item {
                    id: previewMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    Rectangle { anchors.fill: parent; radius: Tokens.radiusCard; color: "white" }
                }
                Rectangle {
                    anchors.fill: parent
                    radius: Tokens.radiusCard
                    color: "transparent"
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outlineNested
                }

                Item {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: -Tokens.spacingXs
                    width: 30
                    height: 30
                    readonly property string iconPath: Icons.pathForAppId(root.w?.appClass ?? "")
                    MorphShape {
                        anchors.fill: parent
                        shape: "cookie9"
                        fillColor: Colors.of(QsWindow.window).surfaceHigh
                        strokeColor: Colors.of(QsWindow.window).alpha(root.accent, 0.4)
                    }
                    Image {
                        anchors.centerIn: parent
                        visible: parent.iconPath !== ""
                        source: parent.iconPath
                        width: 18; height: 18
                        sourceSize: Qt.size(18, 18)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        visible: parent.iconPath === ""
                        name: "window"
                        color: root.accent
                        font.pixelSize: Tokens.iconSm
                    }
                }
            }

            // ── What it is ────────────────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                // Narrower than it was (300 / 360): the facts wrap, and every pixel here is taken off the corner
                // cards beside the island (flankW) while a window is picked.
                Layout.preferredWidth: 230
                Layout.maximumWidth: 300
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    text: root.w?.title || root.w?.appName || "Window"
                    variant: "title"
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                // Facts: a glyph and a word on a quiet pill each; `lit` for a state it is in.
                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: [
                            { symbol: "apps",       text: root.w?.appName || root.w?.appClass || "App" },
                            { symbol: "workspaces",
                              text: root.workspaceId > 0 ? String(root.workspaceId) : "special" },
                            { symbol: "crop_free",  text: Math.round(root.geom.width) + "×" + Math.round(root.geom.height) },
                            { symbol: "history",    text: Switcher.agoText(root.address) },
                            { symbol: "open_with",  text: root.floating ? "Floating" : "",     lit: true },
                            { symbol: "keep",       text: root.pinned ? "Pinned" : "",         lit: true },
                            { symbol: "fullscreen", text: root.fullscreen ? "Fullscreen" : "", lit: true }
                        ].filter(f => f.text !== "")
                        delegate: Rectangle {
                            id: fact
                            required property var modelData
                            readonly property bool lit: fact.modelData.lit === true
                            implicitHeight: 24
                            implicitWidth: factRow.implicitWidth + Tokens.spacingSm * 2
                            radius: height / 2
                            // A state it is in wears the tonal container (like every other lit chip); the rest are quiet.
                            color: fact.lit ? Colors.of(QsWindow.window).primaryContainer
                                            : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                            Row {
                                id: factRow
                                anchors.centerIn: parent
                                spacing: Tokens.spacingXs
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: fact.modelData.symbol
                                    fill: fact.lit ? 1 : 0
                                    color: fact.lit ? Colors.of(QsWindow.window).fgOnPrimaryContainer : Colors.of(QsWindow.window).fgMuted
                                    font.pixelSize: Tokens.iconSm - 2
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: fact.modelData.text
                                    variant: "caption"
                                    emphasis: fact.lit ? "normal" : "dim"
                                }
                            }
                        }
                    }
                }
            }

            // ── What you can do to it ─────────────────────────────────────────────
            ChipTray {
                Layout.alignment: Qt.AlignVCenter
                ChipButton {
                    symbol: "open_with"
                    on: root.floating
                    tint: root.accent
                    onActivated: root.toggleFloat()
                HoverTip { below: false; text: Translation.tr("Float: let it move and resize freely (Ctrl+F)") }
                }
                ChipButton {
                    symbol: "keep"
                    on: root.pinned
                    tint: root.accent
                    onActivated: root.togglePin()
                HoverTip { below: false; text: Translation.tr("Pin: keep it on screen on every workspace (Ctrl+P)") }
                }
                ChipButton {
                    symbol: "fullscreen"
                    on: root.fullscreen
                    tint: root.accent
                    onActivated: root.toggleFullscreen()
                HoverTip { below: false; text: Translation.tr("Fullscreen (Ctrl+Enter)") }
                }
            }

            // ── Close it — twice ──────────────────────────────────────────────────
            CookieButton {
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 44
                implicitHeight: 44
                name: closeLatch.armed ? "delete" : "close"
                tint: Colors.of(QsWindow.window).danger
                primary: closeLatch.armed
                points: 6
                onActivated: root.requestClose()
                HoverTip { below: false; text: Translation.tr("Close it: click twice to confirm (Ctrl+W)") }
            }
        }

        // ── Second row: PLACE it ──────────────────────────────────────────────
        // Where it goes (the page as a map: what is on each workspace, where this is), how it sits (the snap
        // zones — the rectangles a drag to the screen's edge gives, Snap.snapWindow, which floats it first — and
        // centre), what it costs, and the way to the rarer tools.
        RowLayout {
            id: tools
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: !root.spaceOpen && !root.moreOpen
            spacing: Tokens.spacingLg

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                MaterialIcon {
                    name: "drive_file_move"
                    color: Colors.of(QsWindow.window).fgMuted
                    font.pixelSize: Tokens.iconSm
                    HoverTip { text: Translation.tr("Send this window to a workspace. Brighter numbers have windows on them.") }
                }
                WorkspaceMap {
                    firstWorkspace: root.firstWorkspace
                    here: [root.workspaceId]
                    accent: root.accent
                    onPicked: ws => root.moveTo(ws)
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                MaterialIcon {
                    name: "vertical_split"
                    color: Colors.of(QsWindow.window).fgMuted
                    font.pixelSize: Tokens.iconSm
                    HoverTip { text: Translation.tr("Snap it to a part of the screen: a half, a corner, or all of it.") }
                }
                Row {
                    spacing: Tokens.spacingXs - 1
                    Repeater {
                        model: [
                            { zone: "left",  x: 0,   y: 0,   w: 0.5, h: 1 },
                            { zone: "right", x: 0.5, y: 0,   w: 0.5, h: 1 },
                            { zone: "max",   x: 0,   y: 0,   w: 1,   h: 1 },
                            { zone: "tl",    x: 0,   y: 0,   w: 0.5, h: 0.5 },
                            { zone: "tr",    x: 0.5, y: 0,   w: 0.5, h: 0.5 },
                            { zone: "bl",    x: 0,   y: 0.5, w: 0.5, h: 0.5 },
                            { zone: "br",    x: 0.5, y: 0.5, w: 0.5, h: 0.5 }
                        ]
                        delegate: Rectangle {
                            id: zc
                            required property var modelData
                            width: 28
                            height: 22
                            radius: Tokens.radiusXs + 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, zcHover.hovered ? 0.12 : 0.06)
                            border.width: Tokens.borderWidth
                            border.color: zcHover.hovered ? root.accent : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.18)
                            SpringValue {
                                id: zcLean
                                target: zcTap.pressed ? 0.9 : zcHover.hovered ? 1.06 : 1
                                spec: Motion.springSpatialFast
                                epsilon: 0.001
                            }
                            scale: zcLean.value
                            Rectangle {
                                x: 3 + (zc.width - 6) * zc.modelData.x
                                y: 3 + (zc.height - 6) * zc.modelData.y
                                width: (zc.width - 6) * zc.modelData.w - (zc.modelData.w < 1 ? 1 : 0)
                                height: (zc.height - 6) * zc.modelData.h - (zc.modelData.h < 1 ? 1 : 0)
                                radius: 2
                                color: zcHover.hovered ? root.accent : Colors.of(QsWindow.window).alpha(root.accent, 0.55)
                            }
                            HoverHandler { id: zcHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: zcTap; onTapped: if (root.address) Snap.snapWindow(root.address, zc.modelData.zone) }
                        }
                    }
                }
                ChipButton {
                    symbol: "center_focus_strong"
                    tint: root.accent
                    enabled: root.floating
                    onActivated: root.centre()
                HoverTip { below: false; text: Translation.tr("Centre it on the screen") }
                }
            }

            Item { Layout.fillWidth: true }

            // What it costs: CPU across its process tree, and memory.
            StyledText {
                Layout.alignment: Qt.AlignVCenter
                visible: root.pid > 0
                text: ProcCost.ok && ProcCost.pid === root.pid
                    ? Translation.tr("%1% CPU · %2").arg(Math.round(ProcCost.cpu)).arg(ProcCost.memText(ProcCost.rssMb))
                    : Translation.tr("measuring…")
                variant: "caption"
                emphasis: ProcCost.ok && ProcCost.cpu >= 80 ? "normal" : "muted"
                color: ProcCost.ok && ProcCost.cpu >= 80 ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                font.family: Tokens.fontMono
            }
            ChipButton {
                Layout.alignment: Qt.AlignVCenter
                symbol: "more_horiz"
                tint: root.accent
                onActivated: root.moreOpen = true
                HoverTip { below: false; text: Translation.tr("More: sound, screenshot, record, force quit") }
            }
        }

        // ── The ⋯ page: the rarer tools ───────────────────────────────────────
        // Its sound, a picture of it, record it, the other screens, its workspace's page, force quit. A page that
        // REPLACES the placing row (the island keeps its size), with the way back first.
        RowLayout {
            id: more
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.moreOpen && !root.spaceOpen
            spacing: Tokens.spacingLg

            ChipButton {
                Layout.alignment: Qt.AlignVCenter
                symbol: "arrow_back"
                on: true
                tint: root.accent
                onActivated: root.moreOpen = false
            }

            // Its sound: the app's first playback stream, and its mute.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                visible: root.stream !== null && root.stream.audio !== null
                spacing: Tokens.spacingXs
                ChipButton {
                    symbol: root.stream?.audio?.muted ? "volume_off" : "volume_up"
                    on: root.stream?.audio?.muted ?? false
                    tint: root.accent
                    onActivated: if (root.stream?.audio) root.stream.audio.muted = !root.stream.audio.muted
                }
                ValueSlider {
                    Layout.preferredWidth: 110
                    value: root.stream?.audio?.volume ?? 0
                    maximum: 1
                    accent: root.stream?.audio?.muted ? Colors.of(QsWindow.window).fgFaint : root.accent
                    onMoved: v => Audio.setNodeVolume(root.stream, v, false)
                }
                StyledText {
                    text: Math.round((root.stream?.audio?.volume ?? 0) * 100) + "%"
                    variant: "caption"
                    emphasis: "muted"
                    font.family: Tokens.fontMono
                }
            }

            // A picture of it, or onto the clipboard; record it (goes there first).
            ChipTray {
                Layout.alignment: Qt.AlignVCenter
                ChipButton {
                    symbol: "photo_camera"
                    tint: root.accent
                    on: root._grabFor === "save"
                    onActivated: root.picture(false)
                }
                ChipButton {
                    symbol: "content_copy"
                    tint: root.accent
                    on: root._grabFor === "copy"
                    onActivated: root.picture(true)
                }
                ChipButton {
                    symbol: "fiber_manual_record"
                    tint: Colors.of(QsWindow.window).danger
                    enabled: Clips.blocker() === "" && Clips.mode !== "record"
                    onActivated: {
                        const a = root.address
                        Hypr.focusWindow(a)
                        UiState.leaveOverview(root.workspaceId)
                        Clips.recordWindowSoon(a)
                    }
                }
            }

            // Send it to another screen: that screen's own workspace, the one showing there. Only
            // with more than one monitor; the screen it is on is not offered.
            RowLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                visible: root.otherScreens.length > 0
                spacing: Tokens.spacingXs
                Repeater {
                    model: root.otherScreens
                    delegate: ChipButton {
                        required property var modelData
                        symbol: "monitor"
                        label: modelData.name
                        tint: root.accent
                        enabled: (modelData.activeWorkspace?.id ?? 0) > 0
                        onActivated: root.moveTo(modelData.activeWorkspace.id)
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // Its workspace's page (name and icon the app, swap, bring here, close all).
            ChipButton {
                Layout.alignment: Qt.AlignVCenter
                visible: root.workspaceId > 0
                symbol: "workspaces"
                label: root.workspaceId > 0 ? String(root.workspaceId) : ""
                tint: root.accent
                onActivated: { root.moreOpen = false; root.spaceOpen = true }
            }
            // Force quit (twice).
            ChipButton {
                Layout.alignment: Qt.AlignVCenter
                visible: root.pid > 0
                symbol: "block"
                label: killLatch.armed ? Translation.tr("Force quit?") : ""
                on: killLatch.armed
                tint: Colors.of(QsWindow.window).danger
                onActivated: killLatch.trigger()
            }
        }

        // ── Its workspace — the tools row's other page ────────────────────────
        // What the cell's right-click menu used to hold (2026-10-24, the user's call: it lives
        // here now, and the cell has no menu): name and icon the APP (they follow it to any
        // workspace — WorkspaceLabels), swap the workspace with another of the page, bring all of
        // it to where you were, close all of it (twice). A page, not a third row: the island
        // keeps its width, and its height until you ask (the chip with the workspace's number,
        // which is also the way back).
        RowLayout {
            id: space
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.spaceOpen && root.workspaceId > 0
            spacing: Tokens.spacingLg

            readonly property string key: WorkspaceLabels.keyOf(root.w)
            readonly property var label: space.key !== "" ? WorkspaceLabels.appLabel(space.key) : null
            readonly property int count: Hypr.countByWorkspace[root.workspaceId] ?? 0

            ChipButton {
                Layout.alignment: Qt.AlignTop
                symbol: "workspaces"
                label: String(root.workspaceId)
                on: true
                tint: root.accent
                onActivated: root.spaceOpen = false
            }

            // The app's name and icon: a field, and under it the set, one of which (again to clear it).
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        name: space.label?.icon || "label"
                        fill: (space.label?.icon ?? "") !== "" ? 1 : 0
                        color: root.accent
                        font.pixelSize: Tokens.iconMd
                    }
                    InputField {
                        Layout.fillWidth: true
                        placeholder: Translation.tr("Name %1 — it follows it").arg(root.w?.appName || root.w?.appClass || "")
                        seed: space.label?.name ?? ""
                        onCommitted: value => { if (space.key !== "") WorkspaceLabels.setAppName(space.key, value) }
                    }
                }
                Row {
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: WorkspaceLabels.icons
                        ChipButton {
                            required property string modelData
                            symbol: modelData
                            on: (space.label?.icon ?? "") === modelData
                            tint: root.accent
                            onActivated: if (space.key !== "") WorkspaceLabels.setAppIcon(space.key, (space.label?.icon ?? "") === modelData ? "" : modelData)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingXs
                StyledText {
                    text: Translation.tr("Swap with")
                    variant: "caption"
                    emphasis: "muted"
                }
                WorkspaceChips {
                    firstWorkspace: root.firstWorkspace
                    here: [root.workspaceId]
                    accent: root.accent
                    onPicked: ws => { Hypr.swapWorkspaces(root.workspaceId, ws); root.moved(ws); root.moved(root.workspaceId) }
                }
            }

            Item { Layout.fillWidth: true }

            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                ChipButton {
                    symbol: "drive_file_move"
                    label: Translation.tr("Bring here")
                    tint: root.accent
                    enabled: space.count > 0 && root.workspaceId !== Hypr.focusedWorkspaceId
                    onActivated: { Hypr.moveAll(root.workspaceId, Hypr.focusedWorkspaceId); root.moved(Hypr.focusedWorkspaceId) }
                }
                ChipButton {
                    symbol: "close"
                    label: allLatch.armed ? Translation.tr("Close %1 — sure?").arg(space.count) : Translation.tr("Close all")
                    on: allLatch.armed
                    tint: Colors.of(QsWindow.window).danger
                    enabled: space.count > 0
                    onActivated: allLatch.trigger()
                }
            }
        }
    }
}
