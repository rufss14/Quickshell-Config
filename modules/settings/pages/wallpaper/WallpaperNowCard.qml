pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"

// ── WallpaperNowCard — the live hero of Placement & motion and Scenes ─────────
// The loud card of the two settings views that have no picture of their own: what is on the
// desktop right now, large enough to judge the options below it by. Placement shows the
// wallpaper the shell is drawing (a picture, the Material wallpaper, or a scene's still while
// one covers it) with its name and where the colours come from; Scenes (`renderer: true`)
// shows the scene the renderer plays, or last played, and carries its Start / Stop / Refresh,
// which are the page's only ones. The state itself ("Renderer stopped") is the page header's.
// `page` is WallpaperPage.qml's root.
Section {
    id: card
    hero: true

    required property var page
    // Scenes' card: the renderer's scene and its controls, not the shell's wallpaper.
    property bool renderer: false

    // Running, the scene on screen; stopped, the one that will start again.
    readonly property var sceneItem: WallpaperEngine.itemFor(
        WallpaperEngine.running ? WallpaperEngine.current : Config.wpeCurrent)

    readonly property string src: card.renderer
        ? ((card.sceneItem && card.sceneItem.preview !== "") ? "file://" + card.sceneItem.preview : "")
        : card.page.heroSource
    readonly property string name: card.renderer
        ? (card.sceneItem ? card.sceneItem.title : Translation.tr("No scene yet"))
        : (card.page.heroTitle !== "" ? card.page.heroTitle : Translation.tr("No wallpaper yet"))
    readonly property string note: {
        if (!card.renderer) return Translation.tr(card.page.heroThemeSource)
        if (!card.sceneItem) return Translation.tr("Pick one in the gallery")
        const kind = card.sceneItem.type ? card.sceneItem.type.charAt(0).toUpperCase() + card.sceneItem.type.slice(1) : ""
        const state = WallpaperEngine.running ? Translation.tr("Playing now") : Translation.tr("Not playing")
        return kind !== "" ? kind + " · " + state : state
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingLg

        // 16:9, the shape of a wallpaper; concentric with the card.
        ClippingRectangle {
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredWidth: 224
            Layout.preferredHeight: 126
            radius: Math.max(Tokens.radiusXs, Tokens.radiusXl - card.padding)
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

            Image {
                anchors.fill: parent
                source: card.page.bust(card.src)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 320
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            }
            // The Material wallpaper, as the desktop draws it, in place of a picture.
            Loader {
                anchors.fill: parent
                active: !card.renderer && card.page.materialOnScreen
                // The page stays loaded off stage: only animate while it is showing.
                sourceComponent: MaterialWallpaper { running: card.visible }
            }
            MaterialIcon {
                anchors.centerIn: parent
                visible: card.src === "" && !(!card.renderer && card.page.materialOnScreen)
                name: card.renderer ? "movie" : "wallpaper"
                variant: "title"
                color: card.inkDim
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingXs

            StyledText {
                Layout.fillWidth: true
                text: card.name
                variant: "title"
                font.weight: Font.DemiBold
                color: card.ink
                elide: Text.ElideMiddle
            }
            StyledText {
                Layout.fillWidth: true
                text: card.note
                variant: "caption"
                color: card.inkDim
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: card.renderer && WallpaperEngine.needsRefresh && !WallpaperEngine.busy
                text: Translation.tr("Changes apply on Refresh")
                variant: "caption"
                color: card.inkDim
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: card.renderer && WallpaperEngine.lastError !== "" && !WallpaperEngine.busy
                text: WallpaperEngine.lastError
                variant: "caption"
                color: Colors.of(QsWindow.window).danger
                wrapMode: Text.WrapAnywhere
            }

            // The actions that act on what the picture is showing.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.topMargin: Tokens.spacingMd
                spacing: Tokens.spacingSm

                BusyDot {
                    running: card.renderer && WallpaperEngine.busy
                    tint: card.ink
                }
                PanelButton {
                    capsule: true
                    visible: !card.renderer && !card.page.sceneOnScreen && Wallpaper.wallpapers.length > 1
                    symbol: "shuffle"
                    label: Translation.tr("Shuffle now")
                    enabled: !Wallpaper.applying
                    onActivated: Wallpaper.shuffleNow(true)
                }
                PanelButton {
                    capsule: true
                    visible: card.renderer && WallpaperEngine.needsRefresh
                    symbol: "refresh"
                    label: Translation.tr("Refresh")
                    enabled: !WallpaperEngine.busy
                    onActivated: WallpaperEngine.refresh()
                }
                PanelButton {
                    capsule: true
                    visible: card.renderer && WallpaperEngine.running && !WallpaperEngine.busy
                    symbol: "stop"
                    label: Translation.tr("Stop")
                    onActivated: WallpaperEngine.stop()
                }
                PanelButton {
                    capsule: true
                    visible: card.renderer && !WallpaperEngine.running && !WallpaperEngine.busy
                             && Config.wpeCurrent !== ""
                    symbol: "play_arrow"
                    label: Translation.tr("Start")
                    enabled: card.page.blocked === ""
                    onActivated: WallpaperEngine.apply(Config.wpeCurrent)
                }
                PanelButton {
                    capsule: true
                    symbol: "image"
                    label: Translation.tr("Open gallery")
                    onActivated: {
                        if (card.renderer) card.page.source = "engine"
                        card.page.openKey("WallpaperPage.qml")
                    }
                }
            }
        }
    }
}
