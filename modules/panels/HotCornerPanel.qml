import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/deskmenu.js" as Menus
import "../desktop/widgets/toggles.js" as Toggles

// ── HotCornerPanel ────────────────────────────────────────────────────────────
// What the hot corner panel holds: the time, then the sections you picked, in the order you put them
// (`Config.hotCornerParts`: volume and brightness, switches, music, pinned apps, capture). Which
// switches the switches section carries is `Config.hotCornerToggles`.
// HotCorner puts this in its window and animates it; `reveal` (0..1) is that animation, and the
// parts ride it one after another so the panel arrives as a wave from its corner rather than a
// slab. Nothing here knows about the corner.
//
// Every control calls the service that owns the job (Audio, Brightness, ShellActions, MusicPulse's
// player, Taskbar, Snip, Clips): the panel shows things and asks.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    signal closeRequested()

    // 0 closed … 1 open, from the window.
    property real reveal: 1

    readonly property var palette: Colors.of(QsWindow.window)

    readonly property var order: Menus.known(Config.hotCornerParts, Menus.PARTS)
    readonly property var toggleIds: Menus.known(Config.hotCornerToggles, Toggles.TABLE).slice(0, 8)
    readonly property var apps: Taskbar.pinned.slice(0, 12)
    readonly property var player: MusicPulse.player

    // Does this section have anything to show right now? (A music row with no player is no row.)
    function wants(id) {
        switch (id) {
        case "toggles": return root.toggleIds.length > 0
        case "media":   return root.player !== null
        case "apps":    return root.apps.length > 0
        default:        return true
        }
    }

    // How far part `i` has come in: they start one after another, each over most of the animation.
    function lead(i) { return Math.max(0, Math.min(1, root.reveal * 1.6 - i * 0.14)) }

    // Cards sit one gutter inside the panel, so their corners follow the panel's (concentric).
    readonly property int gutter: Tokens.spacingLg
    readonly property int cardRadius: Math.max(Tokens.spacingMd, Tokens.radiusCard - root.gutter)

    implicitWidth: 360
    implicitHeight: col.implicitHeight + root.gutter * 2

    // A capture needs the panel gone first: it would be in the picture otherwise.
    property var _after: null
    Timer {
        id: afterClose
        interval: Motion.exit + Motion.respond
        onTriggered: if (root._after) { const f = root._after; root._after = null; f() }
    }
    function closeThen(fn) {
        root._after = fn
        root.closeRequested()
        afterClose.restart()
    }

    component Card: Rectangle {
        Layout.fillWidth: true
        radius: root.cardRadius
        color: root.palette.section
    }

    // ── The sections ──────────────────────────────────────────────────────────
    Component {
        id: cSliders
        Card {
            implicitHeight: levels.implicitHeight + root.gutter * 2

            ColumnLayout {
                id: levels
                anchors.fill: parent
                anchors.margins: root.gutter
                spacing: Tokens.spacingSm

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
            }
            Component.onCompleted: Brightness.ensureProbed()
        }
    }

    Component {
        id: cToggles
        GridLayout {
            columns: 2
            rowSpacing: Tokens.spacingSm
            columnSpacing: Tokens.spacingSm

            Repeater {
                model: root.toggleIds
                delegate: QuickToggleTile {
                    id: tile
                    required property string modelData
                    readonly property var meta: Toggles.TABLE[tile.modelData]
                    readonly property string why: ShellActions.blockerOf(tile.modelData)
                    // A momentary action (next wallpaper, lock) is never "on".
                    readonly property bool momentary: Toggles.ACTIONS.indexOf(tile.modelData) >= 0
                    cornerRadius: root.cardRadius
                    active: !tile.momentary && ShellActions.switchOn(tile.modelData)
                    available: tile.why === ""
                    symbol: tile.active ? tile.meta.on : tile.meta.off
                    label: Translation.tr(tile.meta.label)
                    subLabel: tile.why !== "" ? Translation.tr(tile.why)
                            : tile.momentary ? ""
                            : tile.active ? Translation.tr("On") : Translation.tr("Off")
                    onToggled: tile.momentary ? root.closeThen(() => ShellActions.switchFlip(tile.modelData))
                                              : ShellActions.switchFlip(tile.modelData)
                }
            }
        }
    }

    Component {
        id: cMedia
        Card {
            implicitHeight: music.implicitHeight + root.gutter * 2

            RowLayout {
                id: music
                anchors.fill: parent
                anchors.margins: root.gutter
                spacing: Tokens.spacingMd

                Rectangle {
                    Layout.preferredWidth: Tokens.iconXl * 2
                    Layout.preferredHeight: Tokens.iconXl * 2
                    radius: Math.max(Tokens.spacingSm, root.cardRadius - root.gutter)
                    color: root.palette.plate
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: AlbumArt.hiRes(root.player?.trackArtUrl ?? "")
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
                    symbol: "skip_previous"
                    Accessible.name: Translation.tr("Previous")
                    enabled: root.player?.canGoPrevious ?? false
                    onActivated: root.player?.previous()
                }
                ChipButton {
                    symbol: root.player?.isPlaying ? "pause" : "play_arrow"
                    Accessible.name: root.player?.isPlaying ? Translation.tr("Pause") : Translation.tr("Play")
                    solid: true
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
    }

    Component {
        id: cApps
        Card {
            implicitHeight: appGrid.implicitHeight + root.gutter * 2

            GridLayout {
                id: appGrid
                anchors.fill: parent
                anchors.margins: root.gutter
                columns: 6
                rowSpacing: Tokens.spacingSm
                columnSpacing: Tokens.spacingSm

                Repeater {
                    model: root.apps
                    delegate: Item {
                        id: app
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingLg

                        Accessible.role: Accessible.Button
                        Accessible.name: Taskbar.nameFor(app.modelData)
                        Accessible.onPressAction: appMouse.clicked(null)

                        HoverTip { text: Taskbar.nameFor(app.modelData) }
                        Rectangle {
                            anchors.fill: parent
                            radius: Math.max(Tokens.spacingSm, root.cardRadius - root.gutter)
                            color: root.palette.alpha(root.palette.fg, appMouse.pressed ? Tokens.statePress : appMouse.containsMouse ? Tokens.stateHover : 0)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                        Image {
                            anchors.centerIn: parent
                            width: Tokens.iconXl
                            height: width
                            sourceSize: Qt.size(width, height)
                            source: Taskbar.iconFor(app.modelData)
                            scale: appMouse.pressed ? 0.9 : appMouse.containsMouse ? 1.08 : 1
                            Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                            layer.enabled: Config.colorizeIcons
                            layer.effect: MonoIconEffect {}
                        }
                        MouseArea {
                            id: appMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { Taskbar.launch(app.modelData); root.closeRequested() }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: cCapture
        RowLayout {
            spacing: Tokens.spacingSm

            ChipButton {
                Layout.fillWidth: true
                symbol: "crop"
                label: Translation.tr("Region")
                enabled: Snip.blocker("save") === ""
                onActivated: root.closeThen(() => Snip.start("save"))
            }
            ChipButton {
                Layout.fillWidth: true
                symbol: "content_copy"
                label: Translation.tr("Copy")
                enabled: Snip.blocker("copy") === ""
                onActivated: root.closeThen(() => Snip.start("copy"))
            }
            ChipButton {
                Layout.fillWidth: true
                symbol: Clips.recording ? "stop" : "fiber_manual_record"
                label: Clips.recording ? Translation.tr("Stop") : Translation.tr("Record")
                on: Clips.recording
                enabled: Clips.blocker() === ""
                onActivated: Clips.toggleRecord()
            }
        }
    }

    function part(id) {
        switch (id) {
        case "sliders": return cSliders
        case "toggles": return cToggles
        case "media":   return cMedia
        case "apps":    return cApps
        default:        return cCapture
        }
    }

    // ── The panel ─────────────────────────────────────────────────────────────
    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: root.gutter
        spacing: Tokens.spacingMd

        // The time and the day, then pin / Settings / Power.
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin: Tokens.spacingSm
            spacing: Tokens.spacingSm
            opacity: root.lead(0)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    text: Qt.formatTime(Clock.now, Qt.locale().timeFormat(Locale.ShortFormat))
                    variant: "headline"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    text: Qt.formatDate(Clock.now, "dddd, d MMMM")
                    variant: "caption"
                    emphasis: "dim"
                }
            }
            ChipButton {
                symbol: "keep"
                on: UiState.hotCornerPinned
                Accessible.name: UiState.hotCornerPinned ? Translation.tr("Unpin") : Translation.tr("Keep open")
                onActivated: UiState.hotCornerPinned = !UiState.hotCornerPinned
                HoverTip { text: UiState.hotCornerPinned ? Translation.tr("Unpin") : Translation.tr("Keep open") }
            }
            ChipButton {
                symbol: "settings"
                Accessible.name: Translation.tr("Settings")
                onActivated: { root.closeRequested(); UiState.openSettingsTo("HotCornerPage.qml") }
                HoverTip { text: Translation.tr("Hot corner settings") }
            }
            ChipButton {
                symbol: "power_settings_new"
                Accessible.name: Translation.tr("Power")
                onActivated: root.closeThen(() => { UiState.powerMenuOpen = true })
                HoverTip { text: Translation.tr("Power") }
            }
            ChipButton {
                visible: UiState.hotCornerPinned
                symbol: "close"
                Accessible.name: Translation.tr("Close")
                onActivated: root.closeRequested()
            }
        }

        Repeater {
            model: root.order
            delegate: Loader {
                id: slot
                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: root.wants(slot.modelData)
                sourceComponent: root.part(slot.modelData)
                opacity: root.lead(slot.index + 1)
                // Each part settles down into place as it arrives (from above, so none leaves the card).
                transform: Translate { y: -(1 - slot.opacity) * Tokens.spacingMd }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: root.order.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Nothing to show — pick sections in Settings › Desktop › Hot corner")
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }
}
