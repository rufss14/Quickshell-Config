pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperGalleryView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
ColumnLayout {
    id: galleryView
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    property alias pager: pager
    anchors.fill: parent
    spacing: Tokens.spacingLg

    opacity: page.view === "gallery" && !page.browsing && !page.choosing ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // ── Picking a scene for a screen (or a span group) ───────────
    // Entered from the Engine tab's Monitors section. A tile's click
    // routes to WallpaperEngine.assignMonitor()/spanMonitors() while
    // this is up — see WallTile.doApply().
    Rectangle {
        Layout.fillWidth: true
        visible: page.anyPicking
        implicitHeight: pickRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.35)

        RowLayout {
            id: pickRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            MaterialIcon { name: "equalizer"; color: Colors.of(QsWindow.window).primary; variant: "body" }
            StyledText {
                Layout.fillWidth: true
                text: page.pickingWs > 0
                    ? "Choose a wallpaper for workspace " + page.pickingWs
                    : page.pickingScreens.length > 0
                    ? "Choose a scene to span " + page.pickingScreens.join(" + ")
                    : "Choose a scene for " + page.pickingForScreen
                variant: "caption"
                color: Colors.of(QsWindow.window).primary
            }
            PanelButton {
                capsule: true
                variant: "ghost"
                label: Translation.tr("Cancel")
                onActivated: page.cancelPicking()
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: !page.anyPicking
        text: Translation.tr("Click applies a wallpaper everywhere · right-click it to choose its workspaces")
        variant: "caption"
        emphasis: "dim"
        wrapMode: Text.WordWrap
    }

    // Scenes that workspaces own, and the shared scene, play in windows the shell
    // captures (services/ScenePreload) — which is what lets the pointer move them.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        visible: !page.pickingActive && (Wallpaper.perWorkspace || WallpaperEngine.sharedIsScene)
        spacing: Tokens.spacingMd
        Toggle {
            accent: Colors.of(QsWindow.window).primary
            checked: Config.wpePreload
            onToggled: Config.wpePreload = !Config.wpePreload
        }
        StyledText {
            Layout.fillWidth: true
            text: Config.wpePreload
                ? "Play scenes through the shell — parallax follows the pointer anywhere, workspace switches are instant; each scene keeps using the GPU"
                : "Play scenes through the shell — off: the scene's own renderer plays them (its parallax works only over a bare desktop)"
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }

    // ── Hero — what's on screen, and what it did to the shell ────
    // The bar panel's hero: the current picture (dissolving into the next
    // when it changes), its name with its aspect and format, where the
    // shell's colours are coming from, and the palette that made — the
    // wallpaper→theme link, made visible. The gallery below CHANGES the
    // wallpaper; this SHOWS it. Hidden when nothing is set.
    Rectangle {
        id: hero
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: page.heroHeight
        visible: page.heroName !== ""
        radius: Tokens.radiusSm
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.22)
        gradient: Gradient {
            GradientStop { position: 0.0
                color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, Colors.of(QsWindow.window).primary, 0.11) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).surfaceContainer }
        }

        // The current wallpaper's aspect, from the loaded thumbnail (sourceSize
        // preserves the ratio even though it scales the pixels). More use than
        // an exact resolution here — it tells you whether it fits your screen.
        readonly property string aspect: {
            const w = heroImage.implicitWidth, h = heroImage.implicitHeight
            if (!(w > 1) || !(h > 1)) return ""
            const r = w / h
            const known = [[16, 9], [16, 10], [21, 9], [4, 3], [3, 2], [1, 1],
                           [9, 16], [9, 21], [3, 4], [2, 3]]
            for (let i = 0; i < known.length; i++)
                if (Math.abs(r - known[i][0] / known[i][1]) < 0.03)
                    return known[i][0] + ":" + known[i][1]
            return r.toFixed(2)
        }

        // The current picture again, blurred and dim, as the card's own
        // backdrop: depth and a hint of the wallpaper's colour for free.
        ClippingRectangle {
            anchors.fill: parent
            radius: hero.radius
            color: "transparent"
            Image {
                anchors.fill: parent
                source: heroImage.source
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 240
                opacity: status === Image.Ready ? 0.30 : 0
                Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
                layer.enabled: opacity > 0
                layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 48 }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin:   Tokens.spacingXs
            anchors.rightMargin:  Tokens.spacingLg
            anchors.topMargin:    Tokens.spacingXs
            anchors.bottomMargin: Tokens.spacingXs
            spacing: Tokens.spacingLg

            ClippingRectangle {
                id: heroThumb
                // 16:9, the shape of a wallpaper.
                Layout.preferredWidth: Math.round((page.heroHeight - Tokens.spacingXs * 2) * 16 / 9)
                Layout.fillHeight: true
                radius: Tokens.radiusXs
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0.5)

                // ── Crossfade on a wallpaper change ─────────────────────
                // `heroImage` shows the current picture; `heroPrev` holds the
                // one before it underneath until the new one has loaded, so a
                // switch dissolves instead of blinking through the empty plate.
                readonly property string src: page.bust(page.heroSource)
                onSrcChanged: {
                    heroPrev.source  = heroImage.source
                    heroPrev.opacity = 1
                    heroImage.source = heroThumb.src
                }
                Component.onCompleted: heroImage.source = heroThumb.src

                Image {
                    id: heroPrev
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    cache: true
                    sourceSize.width: 320
                    opacity: 0
                    Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
                }
                Image {
                    id: heroImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 320
                    opacity: (String(source) !== "" && status === Image.Ready) ? 1 : 0
                    Behavior on opacity {
                        NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel }
                    }
                    onStatusChanged: if (status === Image.Ready) heroPrev.opacity = 0
                }
                // The Material Wallpaper, as the desktop draws it, in place of a picture.
                Loader {
                    anchors.fill: parent
                    active: page.materialOnScreen
                    // The page stays loaded off stage (PageSlot), so only animate
                    // while its slot is showing.
                    sourceComponent: MaterialWallpaper { running: page.parent?.visible ?? true }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    visible: heroImage.opacity < 0.05 && heroPrev.opacity < 0.05 && !page.materialOnScreen
                    name: page.sceneOnScreen ? "movie" : "wallpaper"
                    variant: "title"
                    color: Colors.of(QsWindow.window).fgDim
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingXs

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: page.sceneOnScreen ? "smart_display" : "check_circle_outline"
                        fill: 1
                        color: Colors.of(QsWindow.window).primary
                        variant: "caption"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: page.heroName
                        variant: "body"
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        visible: text !== ""
                        text: {
                            const bits = []
                            if (page.sceneOnScreen) {
                                if (page.heroKind !== "") bits.push(page.heroKind)
                            } else if (page.materialOnScreen) {
                                bits.push("Live")
                            } else {
                                if (hero.aspect !== "") bits.push(hero.aspect)
                                const ext = page.heroName.indexOf(".") !== -1
                                    ? page.heroName.split(".").pop().toUpperCase() : ""
                                if (ext !== "") bits.push(ext)
                            }
                            return bits.join("  ·  ")
                        }
                        variant: "micro"
                        emphasis: "dim"
                    }
                }

                // Where the colours are from.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingSm

                    MaterialIcon {
                        name: !Config.wallTheming ? "format_paint"
                            : AlbumScheme.active   ? "music_note" : "palette"
                        fill: (Config.wallTheming && AlbumScheme.active) ? 1 : 0
                        color: Config.wallTheming ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fgDim
                        variant: "caption"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: page.heroThemeSource
                            + (Config.wallTheming
                               ? "  ·  " + (Config.themeMode === "light" ? "Light" : "Dark")
                               : "")
                        variant: "caption"
                        emphasis: "dim"
                        elide: Text.ElideRight
                    }
                }

                // ── The palette on screen ───────────────────────────────
                // ansi(1..6), the vivid half of the extracted set — the same
                // colours the whole shell is wearing right now, as one strip.
                // Hidden when theming is off: there is nothing to show.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 1
                    spacing: Tokens.spacingSm
                    visible: Config.wallTheming

                    Repeater {
                        model: [1, 2, 3, 4, 5, 6]
                        delegate: Rectangle {
                            required property int modelData
                            Layout.fillWidth: true
                            implicitHeight: Tokens.spacingMd
                            radius: Tokens.radiusXs
                            color: Colors.of(QsWindow.window).ansi(modelData)
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                    }
                }
            }

            PanelButton {
                capsule: true
                Layout.alignment: Qt.AlignVCenter
                visible: page.sceneOnScreen && WallpaperEngine.needsRefresh
                variant: "primary"
                accent:  Colors.of(QsWindow.window).primary
                symbol:  "refresh"
                label:   Translation.tr("Refresh")
                onActivated: WallpaperEngine.refresh()
            }
        }
    }

    // ── Source switch + search ──────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        // The same strip as the view switch above — the wash slides — and it
        // takes the row's room; the search keeps its own. Only scenes can be
        // assigned to a monitor, so Images is inert while one is being picked.
        TabStrip {
            Layout.fillWidth: true
            Layout.preferredHeight: Tokens.fieldHeight
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "images", label: "Images  " + Wallpaper.wallpapers.length, icon: "image" },
                { value: "engine", label: "Scenes  " + WallpaperEngine.items.length, icon: "movie" }
            ]
            current: page.source
            onPicked: function (v) {
                if (page.pickingActive && v === "images") return
                page.source = v
            }
        }

        // The settings app's own search box (InputField, as in the rail), not a
        // one-off. Escape clears it; the field is per keystroke, the list
        // filters as you type.
        Item {
            Layout.preferredWidth: 240
            Layout.preferredHeight: Tokens.fieldHeight

            Keys.onEscapePressed: function (e) {
                if (searchField.text !== "") {
                    searchField.clear()
                    page.query = ""
                    e.accepted = true
                } else {
                    e.accepted = false
                }
            }

            InputField {
                cornerRadius: implicitHeight / 2
                id: searchField
                anchors.left: parent.left
                anchors.right: parent.right
                placeholder: page.isImages ? "Search wallpapers" : "Search scenes"
                // Types a few names from the library after the words, like the
                // launcher's field does.
                hintLead: page.isImages ? "Search wallpapers" : "Search scenes"
                hints: page.isImages
                    ? Wallpaper.wallpapers.slice(0, 6).map(p => ({ key: p.split("/").pop().replace(/\.[^.]+$/, "") }))
                    : WallpaperEngine.items.slice(0, 6).map(i => ({ key: i.title }))
                onEdited: function (t) { page.query = t }
            }
        }
    }

    // ── The sliding gallery ─────────────────────────────────────
    Item {
        id: pagerHost
        Layout.fillWidth: true
        Layout.fillHeight: true

        // Cells fill both axes with constant gutters; the ratio drifts
        // a few percent from 16:9 and the crop absorbs it.
        readonly property int tileW:
            Math.floor((pagerHost.width - Tokens.spacingMd * 2) / 3)
        readonly property int tileH: Math.max(60,
            Math.floor((pagerHost.height - Tokens.spacingMd * 2) / 3))

        ListView {
            id: pager
            anchors.fill: parent
            orientation: ListView.Horizontal
            clip: true
            snapMode: ListView.SnapOneItem
            highlightRangeMode: ListView.StrictlyEnforceRange
            highlightMoveDuration: Motion.standard * 2
            highlightMoveVelocity: -1
            boundsBehavior: Flickable.StopAtBounds
            model: page.pageCount

            delegate: Item {
                id: pageCell
                required property int index
                width: pager.width
                height: pager.height

                Grid {
                    anchors.fill: parent
                    columns: 3
                    columnSpacing: Tokens.spacingMd
                    rowSpacing: Tokens.spacingMd

                    // The launcher's typing animation: a keystroke keeps the tiles that
                    // still match, they SLIDE to their new place (`move`), and the new
                    // ones fade in — short, because it runs on every letter. Nothing
                    // animates when a page first appears. (Keyed by `id` for scenes and
                    // the action card; a picture is its path.)
                    add: Transition {
                        NumberAnimation { property: "opacity"; from: 0; to: 1
                                          duration: Motion.fast; easing.type: Motion.enter }
                    }
                    move: Transition {
                        NumberAnimation { properties: "x,y"; duration: Motion.standard
                                          easing.type: Motion.travel }
                    }

                    Repeater {
                        model: ScriptModel {
                            values: page.entries.slice(
                                pageCell.index * page.pageSize,
                                (pageCell.index + 1) * page.pageSize)
                            objectProp: "id"
                        }
                        delegate: WallpaperPageTile {
                            page: galleryView.page
                            required property var modelData
                            entry: modelData
                            pageIndex: pageCell.index
                            width: pagerHost.tileW
                            height: pagerHost.tileH
                        }
                    }
                }
            }
        }

        // Empty state — says what to DO.
        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width * 0.6
            spacing: Tokens.spacingXs
            visible: page.entries.length === 0 && !page.scanning

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                glyph: page.query !== "" ? "󰍉" : "󰋩"
                variant: "title"
                emphasis: "dim"
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                variant: "body"
                emphasis: "dim"
                text: page.query !== ""
                    ? "Nothing matches “" + page.query + "”."
                    : page.isImages
                        ? "No images in " + Wallpaper.wallpaperDir + "."
                        : "No Wallpaper Engine scenes installed."
            }
            StyledText {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: "dim"
                visible: page.query === ""
                text: page.isImages
                    ? "Use “Add images”, or drop files there and rescan."
                    : "Subscribe in the Steam Workshop, then rescan."
            }
        }
    }

    // ── Page slider ─────────────────────────────────────────────
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd
        visible: page.pageCount > 1

        StyledText {
            text: (pager.currentIndex + 1) + " / " + page.pageCount
            variant: "caption"
            emphasis: "dim"
        }
        ValueSlider {
            Layout.fillWidth: true
            maximum: 1.0
            value: pager.width > 0 && page.pageCount > 1
                ? pager.contentX / (pager.width * (page.pageCount - 1))
                : 0
            onMoved: function(v) {
                pager.currentIndex = Math.round(v * (page.pageCount - 1))
            }
        }
        StyledText {
            text: page.shownCount + (page.isImages ? " images" : " scenes")
            variant: "caption"
            emphasis: "dim"
        }
    }

    // ── Failure strip ──────────────────────────────────────────
    // A FAILED apply always surfaces — hiding it removes the only
    // account of what went wrong. Compact here; the full step log
    // lives in the bar panel.
    Rectangle {
        Layout.fillWidth: true
        visible: page.isImages && !Wallpaper.applying
                 && (Wallpaper.lastFailed || Wallpaper.needsRestart)
        implicitHeight: failRow.implicitHeight + Tokens.spacingMd * 2
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.12)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.35)

        RowLayout {
            id: failRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            MaterialIcon { name: "warning"; color: Colors.of(QsWindow.window).warning; variant: "body" }
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                wrapMode: Text.WordWrap
                variant: "caption"
                color: Colors.of(QsWindow.window).warning
                text: Wallpaper.lastFailed
                    ? Wallpaper.failedCount + " step"
                      + (Wallpaper.failedCount !== 1 ? "s" : "")
                      + " failed — the picture is set, some apps kept "
                      + "their old colours."
                    : "Some apps only read the theme at startup and are "
                      + "still showing the old colours."
            }
            PanelButton {
                capsule: true
                visible: Wallpaper.needsRestart
                variant: "normal"
                symbol: "refresh"
                label: Translation.tr("Restart them")
                onActivated: Wallpaper.restartAll()
            }
            PanelButton {
                capsule: true
                variant: "ghost"
                label: Translation.tr("Dismiss")
                onActivated: {
                    if (Wallpaper.lastFailed) Wallpaper.clearResult()
                    if (Wallpaper.needsRestart) Wallpaper.dismissRestart()
                }
            }
        }
    }
}
