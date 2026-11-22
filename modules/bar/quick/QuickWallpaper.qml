import QtQuick
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "quickpicks.js" as Picks

// ── QuickWallpaper ────────────────────────────────────────────────────────────
// The wallpaper pill's quick card (PillTip hosts it): what is on screen as a picture, and three more from
// the library to try (random, `quickpicks.js`; the dice re-roll them, and opening the card rolls anew).
// A press applies like the gallery's left click does (`Wallpaper.pick`), so the per-workspace and Gamemode
// rules are the service's, not repeated here. Shuffle in the hero applies one at random now; Undo, Auto
// (timed shuffle) and the gallery sit under the pictures.
//
// A scene or the Material wallpaper on screen has no picture to show: the canvas wears a shape and its
// name instead. The service's blocker (pywal missing) disables the pictures.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property int count: 3
    readonly property int gap: Tokens.spacingSm
    readonly property int inner: root.cardWidth - root.inset * 2
    readonly property int thumbW: Math.floor((root.inner - root.gap * (root.count - 1)) / root.count)
    readonly property int thumbH: Math.round(root.thumbW * 0.66)
    // Opening the card rolls once; the dice change it.
    property int seed: Math.floor(Math.random() * 1000000)
    readonly property var chosen: Picks.sample(Wallpaper.wallpapers, Wallpaper.current, root.count, root.seed)
    readonly property string blocked: Wallpaper.pywalBlocker()
    readonly property bool plain: WallpaperEngine.running || Config.wallMaterial || Wallpaper.currentPath === ""
    readonly property color accent: root.palette.primary

    symbol: "wallpaper"
    shape: "cookie9"
    title: Translation.tr("Wallpaper")
    value: Config.wallMaterial ? Translation.tr("Material")
         : WallpaperEngine.running ? Translation.tr("Animated scene")
         : Wallpaper.current

    trailing: ChipButton {
        symbol: "shuffle"
        tint: root.palette.primary
        solid: true
        enabled: root.blocked === "" && !Wallpaper.applying && Wallpaper.wallpapers.length > 1
        onActivated: Wallpaper.shuffleNow(true)
    }

    // What is on screen: the picture on a lifted canvas, or a shape and its name.
    ClippingRectangle {
        width: parent.width
        height: Math.round(width * 0.42)
        radius: Tokens.radiusSm
        color: root.palette.surfaceHigh
        border.width: Tokens.borderWidth
        border.color: root.palette.outline

        Image {
            anchors.fill: parent
            visible: !root.plain
            source: root.plain ? "" : "file://" + Wallpaper.currentPath
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: root.inner * 2
            sourceSize.height: root.inner
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        }
        MorphShape {
            visible: root.plain
            anchors.centerIn: parent
            width: Tokens.iconXl * 1.6
            height: width
            shape: "cookie9"
            fillColor: root.palette.section
        }
    }

    Row {
        width: parent.width
        StyledText {
            width: parent.width - dice.width
            anchors.verticalCenter: parent.verticalCenter
            visible: root.chosen.length > 0
            variant: "caption"
            emphasis: "dim"
            text: Translation.tr("Try one")
        }
        ChipButton {
            id: dice
            visible: root.chosen.length > 0
            symbol: "casino"
            tint: root.accent
            onActivated: root.seed = Math.floor(Math.random() * 1000000)
        }
    }

    Row {
        spacing: root.gap
        visible: root.chosen.length > 0

        Repeater {
            model: root.chosen

            ClippingRectangle {
                id: tile
                required property string modelData
                required property int index
                readonly property string name: tile.modelData.split("/").pop()
                readonly property bool current: !WallpaperEngine.running && !Config.wallMaterial && Wallpaper.current === tile.name
                readonly property bool usable: root.blocked === "" && !Wallpaper.applying

                width: root.thumbW
                height: root.thumbH
                // Rounder under the pointer, as the gallery's cards go.
                radius: Tokens.radiusSm + (Tokens.radiusCard - Tokens.radiusSm) * lean.value
                scale: (1 + 0.04 * lean.value) * pop.scale
                opacity: (tile.usable || tile.current ? 1 : 0.4) * pop.opacity
                color: root.palette.surfaceHigh

                PopIn { id: pop; active: true; index: tile.index + 2 }
                SpringValue { id: lean; target: tapArea.pressed ? -0.5 : hoverArea.hovered && tile.usable ? 1 : 0; spec: Motion.springSpatialFast }

                Image {
                    anchors.fill: parent
                    source: "file://" + tile.modelData
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: root.thumbW * 2
                    sourceSize.height: root.thumbH * 2
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
                }

                // The one on screen: a tick in a shape of its own, not a caption.
                Item {
                    visible: tile.current
                    anchors { right: parent.right; bottom: parent.bottom; margins: Tokens.spacingXs }
                    width: Tokens.iconMd + Tokens.spacingSm
                    height: width
                    MorphShape { anchors.fill: parent; shape: "cookie9"; fillColor: root.accent }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "check"
                        fill: 1
                        color: root.palette.fgOnPrimary
                        font.pixelSize: parent.width - Tokens.spacingSm
                    }
                }

                StateLayer { anchors.fill: parent; radius: tile.radius; hovered: hoverArea.hovered && tile.usable }

                HoverHandler { id: hoverArea; cursorShape: tile.usable ? Qt.PointingHandCursor : Qt.ArrowCursor }
                MouseArea {
                    id: tapArea
                    anchors.fill: parent
                    enabled: tile.usable
                    onClicked: Wallpaper.pick(tile.modelData)
                }

                Accessible.role: Accessible.Button
                Accessible.name: tile.name
                Accessible.onPressAction: if (tile.usable) Wallpaper.pick(tile.modelData)
            }
        }
    }

    StyledText {
        visible: root.chosen.length === 0
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: Translation.tr("No other wallpapers yet. Add some in the gallery.")
    }

    StyledText {
        visible: root.blocked !== ""
        width: parent.width
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
        text: root.blocked
    }

    Row {
        spacing: Tokens.spacingSm
        ChipButton {
            symbol: "undo"
            label: Translation.tr("Undo")
            tint: root.accent
            visible: Wallpaper.canUndo
            enabled: !Wallpaper.applying
            onActivated: Wallpaper.undo()
        }
        ChipButton {
            symbol: "timer"
            label: Translation.tr("Auto")
            tint: root.accent
            on: Config.wallShuffle
            onActivated: Config.wallShuffle = !Config.wallShuffle
        }
        ChipButton {
            symbol: "wallpaper"
            label: Translation.tr("Gallery")
            tint: root.accent
            onActivated: root.openPanel("wallpaper")
        }
    }
}
