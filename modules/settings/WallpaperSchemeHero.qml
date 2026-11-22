pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"

// ── WallpaperSchemeHero ───────────────────────────────────────────────────────
// The wallpaper-generated colours, as the Wallpaper panel's hero shows what is on screen: the
// picture, its name, where the shell's colours are coming from, and the colours themselves as a stack
// of dots. The picture is what the colours are made FROM, which is the whole idea of this source.
//
// The dots are always what the shell wears right now. When a scheme is held, the pill says so
// ("Held by Nord", with a lock) and the dots are that scheme's, so the card never claims the
// wallpaper made colours it didn't; "Use wallpaper colours" is the way back (it lets go of every pin).
//
// A tile of a settings bento (`span`), like Section.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property int span: 3
    readonly property bool _packed: !!(root.parent && root.parent.pack === true)
    Layout.columnSpan: (root.parent && root.parent.spanFor) ? root.parent.spanFor(root) : Math.min(root.span, 1)
    Layout.fillWidth: true
    Layout.preferredWidth: root._packed ? 0 : -1
    Layout.fillHeight: false
    Layout.preferredHeight: 84

    // ── What is on screen ─────────────────────────────────────────────────────
    readonly property bool sceneOnScreen: WallpaperEngine.running
    readonly property bool materialOnScreen: Config.wallMaterial && !root.sceneOnScreen
    readonly property bool wearingWallpaper: ColorScheme.wearingWallpaper
    readonly property bool busy: ColorScheme.busy || Wallpaper.applying

    readonly property string name: root.sceneOnScreen ? WallpaperEngine.titleFor(WallpaperEngine.current)
        : root.materialOnScreen ? Translation.tr("Material Wallpaper")
        : Wallpaper.current
    readonly property string source: {
        if (root.sceneOnScreen) {
            const it = WallpaperEngine.itemFor(WallpaperEngine.current)
            return (it && it.preview !== "") ? "file://" + it.preview : ""
        }
        return (!root.materialOnScreen && Wallpaper.currentPath !== "") ? "file://" + Wallpaper.currentPath : ""
    }
    readonly property string kind: {
        if (root.sceneOnScreen) {
            const it = WallpaperEngine.itemFor(WallpaperEngine.current)
            return it ? it.type : "scene"
        }
        if (root.materialOnScreen) return Translation.tr("Live")
        const ext = root.name.indexOf(".") !== -1 ? root.name.split(".").pop().toUpperCase() : ""
        return ext
    }

    // Where the shell's colours are coming from right now, in words. A held scheme and the album cover both
    // beat the wallpaper (the album is an overlay on Colors, not a file write), so they are said first.
    readonly property bool held: ColorScheme.locked
    readonly property string from: {
        if (root.held)
            return ColorScheme.worn !== "" ? Translation.tr("Held by %1").arg(ColorScheme.worn)
                                           : Translation.tr("Held by a saved scheme")
        if (!Config.wallTheming) return Translation.tr("Theming off")
        if (AlbumScheme.active) return Translation.tr("Colours from the album cover")
        if (root.sceneOnScreen)
            return Config.wpeScenePalette ? Translation.tr("Colours from the scene") : Translation.tr("Colours unchanged")
        if (root.materialOnScreen) return Translation.tr("Colours from the last picture")
        return Translation.tr("Colours from this wallpaper")
    }
    readonly property string fromIcon: root.held ? "lock"
        : !Config.wallTheming ? "format_paint"
        : AlbumScheme.active ? "music_note" : "palette"

    visible: root.name !== ""
    radius: Tokens.radiusCard
    color: Colors.of(QsWindow.window).surfaceContainer

    // The picture again, blurred and dim, as the card's own backdrop: depth and a hint of the wallpaper's
    // colour without any extra room. A scrim from the left keeps the words readable over a bright one.
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        Image {
            anchors.fill: parent
            source: root.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 240
            opacity: status === Image.Ready ? 0.62 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
            layer.enabled: opacity > 0
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.7; blurMax: 40; saturation: 0.25 }
        }
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.color, 0.55) }
                GradientStop { position: 0.6; color: Colors.of(QsWindow.window).alpha(root.color, 0.30) }
                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.color, 0.10) }
            }
        }
    }

    RowLayout {
        anchors.fill: parent
        // One even inset all round, and the thumbnail's corner concentric with the card's.
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        ClippingRectangle {
            Layout.preferredWidth: Math.round((root.height - Tokens.spacingMd * 2) * 16 / 9)
            Layout.fillHeight: true
            radius: Math.max(Tokens.radiusSm, root.radius - Tokens.spacingMd)
            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

            Image {
                id: thumb
                anchors.fill: parent
                source: root.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 240
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
            }
            // The Material Wallpaper is drawn by the shell, with no picture to show.
            MaterialIcon {
                anchors.centerIn: parent
                visible: thumb.opacity < 0.05
                name: root.sceneOnScreen ? "movie" : "wallpaper"
                variant: "title"
                color: Colors.of(QsWindow.window).fgDim
            }
        }

        // A name with its kind on a pill, and under it where the colours are from and the mode.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacingSm

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                StyledText {
                    Layout.fillWidth: true
                    text: root.name
                    variant: "body"
                    font.weight: Font.DemiBold
                    elide: Text.ElideMiddle
                }
                Rectangle {
                    visible: root.kind !== ""
                    implicitWidth:  kindText.implicitWidth + Tokens.spacingMd * 2
                    implicitHeight: kindText.implicitHeight + Tokens.spacingXs * 2
                    radius: height / 2
                    color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10)
                    StyledText {
                        id: kindText
                        anchors.centerIn: parent
                        text: root.kind
                        variant: "micro"
                        font.weight: Font.DemiBold
                        color: Colors.of(QsWindow.window).fgMuted
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumWidth: fromRow.implicitWidth + Tokens.spacingMd * 2
                implicitHeight: fromRow.implicitHeight + Tokens.spacingXs * 2
                radius: height / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.07)

                RowLayout {
                    id: fromRow
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingXs

                    MaterialIcon {
                        name: root.fromIcon
                        fill: root.held || AlbumScheme.active ? 1 : 0
                        color: Config.wallTheming || root.held ? Colors.of(QsWindow.window).primary
                                                               : Colors.of(QsWindow.window).fgDim
                        font.pixelSize: Tokens.iconSm
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.from + "  ·  " + (Config.themeMode === "light" ? Translation.tr("Light") : Translation.tr("Dark"))
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // The colours the shell wears now, as overlapping discs: ansi(1..6), the vivid half of the set.
        Row {
            Layout.alignment: Qt.AlignVCenter
            spacing: -(Tokens.spacingSm + Tokens.spacingXs)

            Repeater {
                model: [1, 2, 3, 4, 5, 6]
                delegate: Rectangle {
                    required property int modelData
                    width:  Tokens.iconLg + Tokens.spacingSm
                    height: width
                    radius: width / 2
                    color: Colors.of(QsWindow.window).ansi(modelData)
                    border.width: 2
                    border.color: root.color
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                }
            }
        }

        ChipTray {
            Layout.alignment: Qt.AlignVCenter
            groupShown: !root.wearingWallpaper
            ChipButton {
                symbol:  "wallpaper"
                label:   Translation.tr("Use wallpaper colours")
                tint:    Colors.of(QsWindow.window).primary
                enabled: !root.busy
                onActivated: ColorScheme.useWallpaper()
            }
        }
    }
}
