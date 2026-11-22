import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/deskmenu.js" as Menus
import "widgets/toggles.js" as Toggles
import "../panels"

// ── DeskMenuBody ──────────────────────────────────────────────────────────────
// What the desktop menu holds, laid out the way a Windows desktop menu is: a row of icon buttons
// (the capture tools, Config.deskMenuTools), what is playing while something does, then a list that unfolds INLINE where a Windows menu
// would open a sub-menu:
//
//     View            widgets, status bar, sidebar, screen frame: a switch each, with what is true now
//     Personalize     your pictures, wallpapers, colours, light or dark
//     Quick settings  volume and brightness, then the round switches (Config.deskMenuSwitches)
//     New             a task, a timer
//     Display settings
//     Open in Terminal
//     More options    the places you picked (Config.deskMenuPlaces)
//
// One group is open at a time. DeskMenu puts this in its window and animates it; `reveal` (0..1) is
// how far its CONTENTS have come in, and the lines arrive one after another.
//
// A toggle (night light, a recording, the widgets) leaves the menu open so you can flip a few; a
// one-off (next wallpaper, lock, a capture) and every place closes it. Everything calls the service
// that owns the job.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal closeRequested()

    property real reveal: 1

    readonly property var palette: Colors.of(QsWindow.window)

    readonly property var pics: Menus.pictures(Wallpaper.wallpapers, Wallpaper.current, Wallpaper.mtimes, Config.deskMenuWallpapers)
    readonly property var switchIds: Menus.known(Config.deskMenuSwitches, Toggles.TABLE).slice(0, 6)
    readonly property var toolIds: Menus.known(Config.deskMenuTools, Menus.TOOLS).slice(0, 6)
    readonly property var player: MusicPulse.player
    readonly property var placeIds: Menus.known(Config.deskMenuPlaces, Menus.PLACES)

    Component.onCompleted: Brightness.ensureProbed()

    // Which group is unfolded ("" = none).
    property string openGroup: ""
    function toggleGroup(id) { root.openGroup = root.openGroup === id ? "" : id }

    // Line `i` comes in one beat after the one before.
    function lead(i) { return Math.max(0, Math.min(1, root.reveal * 1.6 - i * 0.07)) }

    readonly property int gutter: Tokens.spacingMd
    readonly property int cardRadius: Math.max(Tokens.spacingMd, Tokens.radiusCard - root.gutter)

    implicitWidth: 240
    implicitHeight: col.implicitHeight + root.gutter * 2

    // A one-off needs the menu gone first (a lock, a new picture's wave, a capture): it would be in the way.
    property var _after: null
    Timer {
        id: afterClose
        interval: Motion.exit
        onTriggered: if (root._after) { const f = root._after; root._after = null; f() }
    }
    function closeThen(fn) {
        root._after = fn
        root.closeRequested()
        afterClose.restart()
    }

    function go(id) {
        switch (id) {
        case "wallpaper": UiState.openPanel("wallpaper"); break
        case "colours":   UiState.openPanel("colorScheme"); break
        case "widgets":   UiState.startArranging(); break
        case "displays":  UiState.openSettingsTo("DisplaysPage.qml"); break
        case "bar":       UiState.openSettingsTo("BarPage.qml"); break
        case "overview":  UiState.overviewOpen = true; break
        case "clipboard": UiState.openPanel("clipboard"); break
        case "notifications": UiState.openPanel("notifications"); break
        case "tasks":     UiState.openPanel("tasks"); break
        case "timer":     UiState.openPanel("timer"); break
        case "keys":      UiState.toggleCheatsheet(); break
        case "monitor":   root.closeThen(() => SysStats.openMonitor()); return
        // These take the keyboard or the focus: the menu lets go of both first.
        case "terminal":  root.closeThen(() => Quickshell.execDetached([Terminal.resolved])); return
        case "launcher":  root.closeThen(() => { UiState.launcherOpen = true }); return
        case "power":     root.closeThen(() => { UiState.powerMenuOpen = true }); return
        default:          UiState.openSettingsWindow()
        }
        root.closeRequested()
    }

    // Why a tool can't run here, or "" (the blocker() contract: a missing tool dims it).
    function toolWhy(id) {
        switch (id) {
        case "region": return Snip.blocker("save")
        case "copy":   return Snip.blocker("copy")
        case "colour": return ShellActions.blockerOf("colour")
        case "text":   return ShellActions.blockerOf("lens")
        default:       return ShellActions.blockerOf(id)
        }
    }

    // A capture needs the menu out of the picture first; a recording is a switch and stays.
    function runTool(id) {
        switch (id) {
        case "region": root.closeThen(() => Snip.start("save")); break
        case "copy":   root.closeThen(() => Snip.start("copy")); break
        case "colour": root.closeThen(() => ShellActions.run("colour")); break
        case "text":   root.closeThen(() => ShellActions.run("lens")); break
        case "clip":   root.closeThen(() => ShellActions.run("clip")); break
        default:       ShellActions.run(id)
        }
    }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.gutter
        spacing: Tokens.spacingXs

        // ── Icon buttons ──────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.toolIds.length > 0
            spacing: Tokens.spacingXs
            opacity: root.lead(0)
            transform: Translate { y: -(1 - root.lead(0)) * Tokens.spacingMd }

            Repeater {
                model: root.toolIds
                delegate: DeskMenuTile {
                    id: tool
                    required property string modelData
                    readonly property var meta: Menus.TOOLS[tool.modelData]
                    readonly property bool recording: tool.modelData === "record" && Clips.recording
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    iconOnly: true
                    radius: root.cardRadius
                    symbol: tool.recording ? "stop" : tool.meta.symbol
                    label: tool.recording ? Translation.tr("Stop") : Translation.tr(tool.meta.label)
                    tip: tool.recording ? Translation.tr("Stop recording") : Translation.tr(tool.meta.detail)
                    why: root.toolWhy(tool.modelData)
                    on: tool.recording
                    onActivated: root.runTool(tool.modelData)
                }
            }
        }

        Divider {
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            Layout.leftMargin: Tokens.spacingSm
            Layout.rightMargin: Tokens.spacingSm
            opacity: root.lead(0)
        }

        // ── Now playing ───────────────────────────────────────────────────────
        // Only while something plays: the cover, the song, play and next.
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.player !== null
            implicitHeight: Tokens.iconXl + Tokens.spacingLg
            radius: root.cardRadius
            color: root.palette.section
            opacity: root.lead(1)

            RowLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingSm
                spacing: Tokens.spacingMd

                Rectangle {
                    Layout.preferredWidth: Tokens.iconXl
                    Layout.preferredHeight: Tokens.iconXl
                    radius: Tokens.radiusSm
                    color: root.palette.surfaceHigh
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")
                        sourceSize: Qt.size(Tokens.iconXl * 2, Tokens.iconXl * 2)
                        fillMode: Image.PreserveAspectCrop
                        visible: status === Image.Ready
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "music_note"
                        font.pixelSize: Tokens.iconMd
                        color: root.palette.fgDim
                        visible: (root.player?.trackArtUrl ?? "") === ""
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.player?.trackTitle || Translation.tr("Unknown")
                        variant: "label"
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.player?.trackArtist ?? ""
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
                ChipButton {
                    symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                    solid: true
                    Accessible.name: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                    onActivated: root.player?.togglePlaying()
                }
                ChipButton {
                    symbol: "skip_next"
                    Accessible.name: Translation.tr("Next")
                    enabled: root.player?.canGoNext ?? false
                    onActivated: root.player?.next()
                }
            }
        }

        // ── View ──────────────────────────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            symbol: "visibility"
            label: Translation.tr("View")
            group: true
            open: root.openGroup === "view"
            radius: root.cardRadius
            opacity: root.lead(1)
            onActivated: root.toggleGroup("view")

            // Each element: a switch, what is true now, and a second job on a round button.
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "widgets"
                label: Translation.tr("Widgets")
                subtitle: !Config.widgetsEnabled ? Translation.tr("Hidden")
                        : DesktopWidgets.widgets.length === 0 ? Translation.tr("None placed yet")
                        : Translation.tr("%1 on the desktop").arg(DesktopWidgets.widgets.length)
                tip: Translation.tr("Show or hide the tiles on the desktop")
                showSwitch: true
                checked: Config.widgetsEnabled
                actionSymbol: "edit"
                actionTip: Translation.tr("Move and resize them")
                onActivated: Config.widgetsEnabled = !Config.widgetsEnabled
                onActionActivated: root.go("widgets")
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "web"
                label: Translation.tr("Status bar")
                subtitle: Config.barHidden ? Translation.tr("Hidden until you bring it back")
                        : Translation.tr("Along the top edge")
                tip: Translation.tr("Show or hide the bar and its modules")
                showSwitch: true
                checked: !Config.barHidden
                onActivated: UiState.setBarHidden(!Config.barHidden)
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "view_quilt"
                label: Translation.tr("Sidebar")
                subtitle: UiState.sidebarHidden ? Translation.tr("Out of the way")
                        : Config.sidebarAutoHide ? Translation.tr("Slides out at the edge")
                        : Translation.tr("On the %1 edge").arg(Translation.tr(Config.dockPosition))
                tip: Translation.tr("Show or hide the dock and its modules")
                showSwitch: true
                checked: !UiState.sidebarHidden
                actionSymbol: "visibility_off"
                actionTip: Config.sidebarAutoHide ? Translation.tr("Always show it") : Translation.tr("Hide it until the pointer reaches the edge")
                actionLit: Config.sidebarAutoHide
                onActivated: UiState.sidebarHidden = !UiState.sidebarHidden
                onActionActivated: Config.sidebarAutoHide = !Config.sidebarAutoHide
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "crop_free"
                label: Translation.tr("Screen frame")
                subtitle: Config.screenFrame ? Translation.tr("The ring round the screen") : Translation.tr("Off")
                tip: Translation.tr("The border the bar and the sidebar grow out of")
                showSwitch: true
                checked: Config.screenFrame
                onActivated: Config.toggleFrame()
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "grid_view"
                label: Translation.tr("Overview")
                tip: Translation.tr("Every window at a glance")
                onActivated: root.go("overview")
            }
        }

        // ── Personalize ───────────────────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            symbol: "palette"
            label: Translation.tr("Personalize")
            group: true
            open: root.openGroup === "personalize"
            radius: root.cardRadius
            opacity: root.lead(2)
            onActivated: root.toggleGroup("personalize")

            // Your pictures: the one on the desktop first, ringed in the accent, then the newest.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.pics.length > 0
                spacing: Tokens.spacingXs

                Repeater {
                    model: root.pics
                    delegate: Item {
                        id: pic
                        required property string modelData
                        readonly property bool current: pic.modelData.split("/").pop() === Wallpaper.current
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Tokens.iconXl * 1.5

                        Accessible.role: Accessible.Button
                        Accessible.name: pic.modelData.split("/").pop()
                        Accessible.onPressAction: picMouse.clicked(null)

                        HoverTip { text: pic.modelData.split("/").pop() }

                        Rectangle {
                            id: frame
                            anchors.fill: parent
                            radius: Tokens.radiusSm
                            color: root.palette.surfaceHigh
                            clip: true
                            scale: picMouse.pressed ? 0.95 : picMouse.containsMouse ? 1.05 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }

                            Image {
                                anchors.fill: parent
                                source: "file://" + pic.modelData
                                sourceSize: Qt.size(width * 2, height * 2)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }
                        }
                        Rectangle {
                            anchors.fill: frame
                            scale: frame.scale
                            radius: frame.radius
                            color: "transparent"
                            border.width: pic.current ? Tokens.borderWidth + 1 : 0
                            border.color: root.palette.primary
                        }
                        MouseArea {
                            id: picMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !pic.current && !Wallpaper.applying
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeThen(() => Wallpaper.apply(pic.modelData))
                        }
                    }
                }
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "wallpaper"
                label: Translation.tr("Wallpapers")
                tip: Translation.tr("Browse and set a picture")
                onActivated: root.go("wallpaper")
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "shuffle"
                label: Translation.tr("Next wallpaper")
                tip: Translation.tr("Another picture from your library")
                why: ShellActions.blockerOf("shuffle")
                onActivated: root.closeThen(() => ShellActions.run("shuffle"))
            }
            DeskMenuRow {
                Layout.fillWidth: true
                visible: Wallpaper.canUndo
                symbol: "undo"
                label: Translation.tr("Back to the last one")
                tip: Wallpaper.previousName
                onActivated: root.closeThen(() => Wallpaper.undo())
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "palette"
                label: Translation.tr("Colours")
                tip: Translation.tr("The palette and its schemes")
                onActivated: root.go("colours")
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: Config.themeMode === "light" ? "light_mode" : "dark_mode"
                label: Config.themeMode === "light" ? Translation.tr("Light mode") : Translation.tr("Dark mode")
                tip: Translation.tr("Flip the palette's mode")
                why: ShellActions.blockerOf("theme")
                onActivated: ShellActions.run("theme")
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "tune"
                label: Translation.tr("Bar & sidebar")
                tip: Translation.tr("What is on them, and how")
                onActivated: root.go("bar")
            }
        }

        // ── Quick settings ────────────────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            visible: root.switchIds.length > 0
            symbol: "bolt"
            label: Translation.tr("Quick settings")
            group: true
            open: root.openGroup === "quick"
            radius: root.cardRadius
            opacity: root.lead(3)
            onActivated: root.toggleGroup("quick")

            HotCornerSlider {
                Layout.fillWidth: true
                symbol: Audio.muted ? "volume_off" : Audio.volume > 0.5 ? "volume_up" : Audio.volume > 0 ? "volume_down" : "volume_mute"
                title: Translation.tr("Volume")
                value: Audio.volume
                maximum: 1
                muted: Audio.muted
                iconActionable: Audio.ready
                onMoved: v => Audio.setVolume(v)
                onIconActivated: Audio.toggleMute()
            }
            Repeater {
                model: Brightness.monitors
                delegate: HotCornerSlider {
                    id: bright
                    required property var model
                    required property int index
                    Layout.fillWidth: true
                    visible: bright.model.controllable
                    symbol: "brightness_6"
                    title: Translation.tr("Brightness")
                    value: bright.model.brightness / 100
                    onMoved: v => Brightness.requestBrightness(bright.index, Brightness.clampFor(bright.model.type, v * 100))
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                Repeater {
                    model: root.switchIds
                    delegate: ToggleOrb {
                        id: orb
                        required property string modelData
                        readonly property var meta: Toggles.TABLE[orb.modelData]
                        readonly property bool momentary: Toggles.ACTIONS.indexOf(orb.modelData) >= 0
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg
                        maxSide: Tokens.iconXl + Tokens.spacingSm
                        named: false
                        label: Translation.tr(orb.meta.label)
                        symbolOn: orb.meta.on
                        symbolOff: orb.meta.off
                        lit: !orb.momentary && ShellActions.switchOn(orb.modelData)
                        why: ShellActions.blockerOf(orb.modelData)
                        HoverTip { text: orb.why !== "" ? Translation.tr(orb.why) : orb.label }
                        onActivated: orb.momentary ? root.closeThen(() => ShellActions.switchFlip(orb.modelData))
                                                   : ShellActions.switchFlip(orb.modelData)
                    }
                }
            }
        }

        // ── New ───────────────────────────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            symbol: "add_circle"
            label: Translation.tr("New")
            group: true
            open: root.openGroup === "new"
            radius: root.cardRadius
            opacity: root.lead(4)
            onActivated: root.toggleGroup("new")

            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "task_alt"
                label: Translation.tr("Task")
                tip: Translation.tr("Add to your to-do list")
                onActivated: root.go("tasks")
            }
            DeskMenuRow {
                Layout.fillWidth: true
                symbol: "timer"
                label: Translation.tr("Timer")
                tip: Translation.tr("Start a countdown")
                onActivated: root.go("timer")
            }
        }

        Divider {
            Layout.topMargin: Tokens.spacingXs
            Layout.bottomMargin: Tokens.spacingXs
            Layout.leftMargin: Tokens.spacingSm
            Layout.rightMargin: Tokens.spacingSm
            opacity: root.lead(4)
        }

        // ── Display settings, Terminal ────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            symbol: "monitor"
            label: Translation.tr("Display settings")
            tip: Translation.tr("Arrangement, scale, refresh")
            radius: root.cardRadius
            opacity: root.lead(5)
            onActivated: root.go("displays")
        }
        DeskMenuRow {
            Layout.fillWidth: true
            symbol: "terminal"
            label: Translation.tr("Open in Terminal")
            tip: Translation.tr("A new terminal")
            radius: root.cardRadius
            opacity: root.lead(6)
            onActivated: root.go("terminal")
        }

        // ── More options ──────────────────────────────────────────────────────
        DeskMenuRow {
            Layout.fillWidth: true
            visible: root.placeIds.length > 0
            symbol: "more_horiz"
            label: Translation.tr("Show more options")
            group: true
            open: root.openGroup === "more"
            radius: root.cardRadius
            opacity: root.lead(7)
            onActivated: root.toggleGroup("more")

            Repeater {
                model: root.placeIds
                delegate: DeskMenuRow {
                    id: place
                    required property string modelData
                    readonly property var meta: Menus.PLACES[place.modelData]
                    Layout.fillWidth: true
                    symbol: place.meta.symbol
                    label: Translation.tr(place.meta.label)
                    tip: Translation.tr(place.meta.detail)
                    onActivated: root.go(place.modelData)
                }
            }
        }
    }
}
