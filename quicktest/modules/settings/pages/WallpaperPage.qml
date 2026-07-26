pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"

// ── WallpaperPage ─────────────────────────────────────────────────────────────
// Both wallpaper libraries: static images (the theming pipeline's home ground)
// and Steam Workshop scenes rendered by linux-wallpaperengine. Applying either
// can theme the shell — images through pywal, scenes through their preview —
// or neither, if "Theme from wallpaper" is off.
//
// ── A hero and a SLIDING gallery ──────────────────────────────────────────────
// Six tiles at a time, and the pages physically slide sideways — wheel, drag,
// or the slider underneath — rather than snapping between page numbers. Never
// the whole library at once (the user's standing rule for this page).
//
// ── Scene previews ANIMATE ────────────────────────────────────────────────────
// Workshop previews are mostly GIFs, and a moving wallpaper deserves a moving
// preview. Only the visible page plays (six decoders, bounded); parked pages
// freeze. Rounded corners come from ClippingRectangle — plain `clip` clips to
// the bounding BOX, which is why every previous version had secretly square
// image corners inside rounded cards.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // "images" | "engine"
    property string source: "images"
    property string query: ""

    readonly property bool isImages: root.source === "images"
    readonly property int sideWidth: 360

    // ── The in-page image browser ─────────────────────────────────────────────
    // "Add images" used to open zenity — a separate window. Now the gallery in the
    // middle collapses and a file browser takes its place, so picking pictures
    // never leaves the shell. `browseFolder` is where it's pointed; `picked` is the
    // set of file PATHS ticked for import, cleared whenever the browser closes.
    property bool browsing: false
    property url  browseFolder: "file://" + Quickshell.env("HOME")
    property var  picked: []

    function isPicked(p) { return root.picked.indexOf(p) !== -1 }
    function togglePick(p) {
        root.picked = root.isPicked(p)
            ? root.picked.filter(x => x !== p)
            : root.picked.concat([p])
    }

    onBrowsingChanged: if (!root.browsing) root.picked = []
    // Nine per page — three 16:9 rows fill the page's height exactly, where two
    // left a dead band across the bottom.
    readonly property int pageSize: 9

    readonly property string weLogo: Quickshell.env("HOME")
        + "/.local/share/Steam/appcache/librarycache/431960/logo.png"

    // ── What is ACTUALLY on screen ────────────────────────────────────────────
    // A running scene covers the static wallpaper completely, so while the
    // renderer is up the static image is not "current" anywhere on this page —
    // it's the underlay you'd get back.
    readonly property bool sceneOnScreen: WallpaperEngine.running

    readonly property string currentImagePath: {
        if (root.sceneOnScreen) return ""
        const hit = Wallpaper.wallpapers.find(
            p => p.split("/").pop() === Wallpaper.current)
        return hit ?? ""
    }

    readonly property string heroName: root.sceneOnScreen
        ? WallpaperEngine.titleFor(WallpaperEngine.current)
        : (Wallpaper.current !== "" ? Wallpaper.current : "")

    readonly property string heroSource: {
        if (root.sceneOnScreen) {
            const it = WallpaperEngine.itemFor(WallpaperEngine.current)
            return (it && it.preview !== "") ? "file://" + it.preview : ""
        }
        return root.currentImagePath !== "" ? "file://" + root.currentImagePath : ""
    }

    readonly property string heroKind: {
        if (!root.sceneOnScreen) return ""
        const it = WallpaperEngine.itemFor(WallpaperEngine.current)
        return it ? it.type : "scene"
    }

    readonly property bool applyBusy:
        root.isImages ? Wallpaper.applying : WallpaperEngine.busy

    // ── The filtered libraries ────────────────────────────────────────────────
    readonly property var images: {
        const q = root.query.trim().toLowerCase()
        const all = Wallpaper.wallpapers
        if (q === "") return all
        return all.filter(p => p.split("/").pop().toLowerCase().indexOf(q) !== -1)
    }

    readonly property var scenes: {
        const q = root.query.trim().toLowerCase()
        const all = WallpaperEngine.items
        if (q === "") return all
        return all.filter(i => i.title.toLowerCase().indexOf(q) !== -1
                            || i.type.indexOf(q) !== -1)
    }

    readonly property var filtered: root.isImages ? root.images : root.scenes
    readonly property int shownCount: root.filtered.length
    readonly property int pageCount: Math.max(1, Math.ceil(root.shownCount / root.pageSize))

    onQueryChanged: pager.currentIndex = 0
    // Leaving the images tab also closes the browser — it has no meaning on the
    // engine tab, and a hidden-but-open browser would strand the collapsed gallery.
    onSourceChanged: { pager.currentIndex = 0; root.browsing = false }

    // ── The renderer's running state is polled, so only poll while looking ────
    property bool _held: false
    function _sync() {
        if (root.visible === root._held) return
        if (root.visible) WallpaperEngine.acquire()
        else              WallpaperEngine.release()
        root._held = root.visible
    }
    onVisibleChanged: root._sync()
    Component.onCompleted: root._sync()
    Component.onDestruction: if (root._held) WallpaperEngine.release()

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        PanelHeader {
            glyph:     "󰸉"
            title:     "Wallpaper"
            titleTail: root.isImages ? "images" : "engine"
            subtitle:  root.isImages
                ? "Your picture library. What it does to the shell's colours is up to "
                  + "the Appearance card."
                : "Animated Steam Workshop scenes, rendered behind your windows."

            PanelButton {
                label: "Rescan"
                glyph: "󰑐"
                variant: "ghost"
                onActivated: {
                    if (root.isImages) Wallpaper.rescan()
                    else               WallpaperEngine.rescan()
                }
            }
        }

        Divider {}

        // ── Source switch + search ────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm

            PanelButton {
                label: "Images (" + Wallpaper.wallpapers.length + ")"
                glyph: "󰋩"
                variant: root.isImages ? "primary" : "ghost"
                onActivated: root.source = "images"
            }

            PanelButton {
                label: "Wallpaper Engine (" + WallpaperEngine.items.length + ")"
                glyph: "󰕧"
                variant: !root.isImages ? "primary" : "ghost"
                onActivated: root.source = "engine"
            }

            Item { Layout.fillWidth: true }

            StyledText {
                text: root.query !== ""
                    ? root.shownCount + " of "
                      + (root.isImages ? Wallpaper.wallpapers.length
                                       : WallpaperEngine.items.length)
                    : root.shownCount + (root.isImages ? " images" : " scenes")
                variant: "caption"
                emphasis: "dim"
            }

            // The search wears a pill, like every other control on the shell —
            // a bare input floating in the toolbar read as an unfinished label.
            Rectangle {
                Layout.leftMargin: Tokens.spacingMd
                Layout.preferredWidth: 220
                Layout.preferredHeight: Tokens.pillHeight + Tokens.spacingXs * 2
                radius: Tokens.radiusFull
                color: Colors.surfaceContainer
                border.width: Tokens.borderWidth
                border.color: search.activeFocus ? Colors.outlineFocus : Colors.outline

                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.rightMargin: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    StyledText { text: "󰍉"; variant: "body"; emphasis: "dim" }

                    TextInput {
                        id: search
                        Layout.fillWidth: true
                        color: Colors.fg
                        font.family: Tokens.fontFamily
                        font.pixelSize: Tokens.fontBody
                        selectByMouse: true
                        clip: true
                        onTextChanged: root.query = text

                        Keys.onEscapePressed: function(e) {
                            if (search.text !== "") { search.text = ""; e.accepted = true }
                            else { root.forceActiveFocus(); e.accepted = true }
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Search wallpapers"
                            variant: "body"
                            emphasis: "dim"
                            visible: search.text === ""
                        }
                    }

                    // One press to clear — reaching for Escape shouldn't be the
                    // only way out of a filter.
                    StyledText {
                        text: "󰅖"
                        variant: "caption"
                        emphasis: "dim"
                        visible: search.text !== ""

                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -Tokens.spacingXs
                            cursorShape: Qt.PointingHandCursor
                            onClicked: search.text = ""
                        }
                    }
                }
            }
        }

        // ── Body: hero + sliding gallery | system column ──────────────────────
        RowLayout {
            Layout.fillWidth:  true
            Layout.fillHeight: true
            spacing: Tokens.spacingLg

            ColumnLayout {
                Layout.fillWidth:  true
                Layout.fillHeight: true
                spacing: Tokens.spacingLg

                // ══ On screen now — the About-page fact idiom ═════════════════
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    implicitHeight: heroRow.implicitHeight + Tokens.spacingLg * 2

                    RowLayout {
                        id: heroRow
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingLg

                        ClippingRectangle {
                            id: heroClip
                            Layout.preferredWidth: 200
                            Layout.preferredHeight: 112
                            radius: Tokens.radiusSm
                            color: Colors.alpha(Colors.surface, 0.5)

                            // Referenced by id, never by `parent`: children of a
                            // ClippingRectangle are reparented to its internal
                            // content item, so `parent.gif` resolves against that
                            // and reads undefined.
                            readonly property bool gif:
                                root.heroSource.toLowerCase().endsWith(".gif")

                            Image {
                                id: heroShot
                                anchors.fill: parent
                                source: heroClip.gif ? "" : root.heroSource
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                smooth: true
                                // No sourceSize: implicit size is then the file's
                                // real pixel size, which the fact chip reads.
                                cache: false
                            }

                            // The live scene's preview, actually moving — the
                            // one place a single always-playing GIF is worth it.
                            AnimatedImage {
                                anchors.fill: parent
                                source: heroClip.gif ? root.heroSource : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                playing: heroClip.gif && root.visible
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: "󰸉"
                                variant: "title"
                                emphasis: "dim"
                                visible: root.heroSource === ""
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingXs

                            StyledText {
                                text: "On screen now"
                                variant: "label"
                                emphasis: "muted"
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: root.heroName !== "" ? root.heroName
                                                           : "Nothing applied yet"
                                variant: "title"
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            RowLayout {
                                spacing: Tokens.spacingMd

                                FactChip {
                                    glyph: root.sceneOnScreen ? "󰕧" : "󰍹"
                                    text: {
                                        if (root.sceneOnScreen)
                                            return root.heroKind + " · animated"
                                        if (heroShot.status === Image.Ready)
                                            return heroShot.implicitWidth + " × "
                                                 + heroShot.implicitHeight
                                        return root.heroName !== "" ? "static image" : "—"
                                    }
                                }

                                FactChip {
                                    glyph: "󰸌"
                                    text: !Config.wallTheming ? "colours frozen"
                                        : root.sceneOnScreen
                                            ? (Config.wpeScenePalette
                                                ? "palette from scene" : "palette held")
                                            : (Config.themeMode === "light"
                                                ? "light palette" : "dark palette")
                                    visible: root.heroName !== ""
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.maximumWidth: 420
                                spacing: Tokens.spacingXs
                                visible: root.heroName !== ""

                                Repeater {
                                    model: [Colors.primary, Colors.focus, Colors.info,
                                            Colors.success, Colors.warning, Colors.danger]
                                    delegate: Rectangle {
                                        required property color modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 12
                                        radius: Tokens.radiusSm / 2
                                        color: modelData
                                        border.width: Tokens.borderWidth
                                        border.color: Colors.outline
                                    }
                                }
                            }
                        }

                        StyledText {
                            Layout.preferredWidth: 190
                            Layout.alignment: Qt.AlignVCenter
                            wrapMode: Text.WordWrap
                            variant: "caption"
                            emphasis: "dim"
                            visible: root.sceneOnScreen && root.isImages
                            text: "A scene is covering the static wallpaper — "
                                + "applying an image stops the renderer."
                        }
                    }
                }

                // ══ The gallery: six at a time, sliding ═══════════════════════
                Item {
                    id: pagerHost
                    Layout.fillWidth: true
                    // Collapsed while the in-page browser is open, which is what
                    // frees the middle of the page for it. `visible: false` drops
                    // it from the layout entirely, so the browser gets the height.
                    visible: !(root.isImages && root.browsing)
                    // Takes ALL the remaining height — the empty band at the
                    // bottom of the page was this being two fixed rows with a
                    // spacer under them. Three rows now, sized to fit.
                    Layout.fillHeight: true

                    // Cells fill BOTH axes exactly, with constant gutters. The
                    // previous version held tiles at a strict 16:9 and pushed
                    // the spare width into the column gaps — which turned into
                    // wide dead bands between the columns the moment height was
                    // the binding constraint. The ratio now drifts a few percent
                    // from 16:9 (≈1.8:1 at this page size) and the crop absorbs
                    // it; nobody can see 2% of aspect, everybody can see a 60px
                    // gutter.
                    readonly property int tileW:
                        Math.floor((pagerHost.width - Tokens.spacingMd * 2) / 3)
                    readonly property int tileH: Math.max(60,
                        Math.floor((pagerHost.height - Tokens.spacingMd * 2) / 3))

                    ListView {
                        id: pager
                        anchors.fill: parent
                        orientation: ListView.Horizontal
                        clip: true
                        // Pages SLIDE: snap one page at a time, and programmatic
                        // moves (wheel, slider) animate through the same motion
                        // instead of teleporting.
                        snapMode: ListView.SnapOneItem
                        highlightRangeMode: ListView.StrictlyEnforceRange
                        highlightMoveDuration: Motion.standard * 2
                        highlightMoveVelocity: -1
                        boundsBehavior: Flickable.StopAtBounds

                        model: root.pageCount

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

                                Repeater {
                                    model: root.filtered.slice(
                                        pageCell.index * root.pageSize,
                                        (pageCell.index + 1) * root.pageSize)

                                    delegate: WallTile {
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

                    // Empty states say what to DO, not just that there is nothing.
                    // Inside the pager area, where the tiles would be.
                    ColumnLayout {
                        anchors.centerIn: parent
                        width: parent.width * 0.6
                        spacing: Tokens.spacingXs
                        visible: root.shownCount === 0

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.query !== "" ? "󰍉" : "󰋩"
                            variant: "title"
                            emphasis: "dim"
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            variant: "body"
                            emphasis: "dim"
                            text: root.query !== ""
                                ? "Nothing matches “" + root.query + "”."
                                : root.isImages
                                    ? "No images in " + Wallpaper.wallpaperDir + "."
                                    : "No Wallpaper Engine wallpapers installed."
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            variant: "body"
                            emphasis: "dim"
                            visible: root.query === ""
                            text: root.isImages
                                ? "Use “Add images”, or drop files there and Rescan."
                                : "Subscribe in the Steam Workshop, then press Rescan."
                        }
                    }
                }

                // ══ In-page file browser ═════════════════════════════════════
                // Takes the gallery's place (both are fillHeight, only one visible
                // at a time). Navigate folders, tick pictures, Add — no pop-up
                // window, which is the whole point of this over the old zenity call.
                ColumnLayout {
                    id: browser
                    Layout.fillWidth:  true
                    Layout.fillHeight: true
                    visible: root.isImages && root.browsing
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacingSm

                        PanelButton {
                            glyph: "󰁭"
                            variant: "ghost"
                            enabled: String(fsModel.parentFolder) !== ""
                                     && String(fsModel.parentFolder) !== String(root.browseFolder)
                            onActivated: root.browseFolder = fsModel.parentFolder
                        }
                        PanelButton {
                            glyph: "󰋜"
                            variant: "ghost"
                            onActivated: root.browseFolder = "file://" + Quickshell.env("HOME")
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: String(root.browseFolder)
                                .replace("file://", "")
                                .replace(Quickshell.env("HOME"), "~")
                            variant: "body"
                            emphasis: "dim"
                            elide: Text.ElideMiddle
                        }

                        StyledText {
                            visible: root.picked.length > 0
                            text: root.picked.length + " selected"
                            variant: "caption"
                            emphasis: "dim"
                        }
                        PanelButton {
                            label: "Add " + root.picked.length
                            glyph: "󰋺"
                            visible: root.picked.length > 0
                            enabled: !Wallpaper.importing
                            // Copies the ticked files in, then clears the selection
                            // but stays open — the gallery rescans underneath, and
                            // you may well want to grab more from the same folder.
                            onActivated: { Wallpaper.addPaths(root.picked); root.picked = [] }
                        }
                        PanelButton {
                            label: "Done"
                            variant: "ghost"
                            onActivated: root.browsing = false
                        }
                    }

                    Rectangle {
                        Layout.fillWidth:  true
                        Layout.fillHeight: true
                        radius: Tokens.radiusPill
                        color: Colors.surfaceContainer
                        border.width: Tokens.borderWidth
                        border.color: Colors.outline

                        FolderListModel {
                            id: fsModel
                            folder: root.browseFolder
                            showDirs: true
                            showDirsFirst: true
                            showFiles: true
                            showDotAndDotDot: false
                            showHidden: false
                            // So *.jpg matches .JPG too — filters are the only place
                            // this browser cares about case.
                            caseSensitive: false
                            nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.gif", "*.webp"]
                        }

                        GridView {
                            id: fileGrid
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingSm
                            clip: true
                            model: fsModel
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: fileGrid.cellHeight * 2

                            property int cols: Math.max(2, Math.floor(width / 170))
                            cellWidth:  Math.floor(width / fileGrid.cols)
                            cellHeight: 120

                            delegate: Item {
                                id: cell
                                required property int index
                                required property string fileName
                                required property string filePath
                                required property bool   fileIsDir

                                width:  fileGrid.cellWidth
                                height: fileGrid.cellHeight

                                readonly property bool picked:
                                    !cell.fileIsDir && root.isPicked(cell.filePath)

                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: Tokens.spacingXs
                                    radius: Tokens.radiusSm
                                    color: Colors.surface
                                    border.width: cell.picked ? 2
                                        : (cellHover.hovered ? 1 : Tokens.borderWidth)
                                    border.color: cell.picked ? Colors.primary
                                        : (cellHover.hovered ? Colors.outlineFocus : Colors.outline)

                                    Behavior on border.color {
                                        ColorAnimation { duration: Motion.respond }
                                    }

                                    ClippingRectangle {
                                        anchors.fill: parent
                                        anchors.margins: Tokens.borderWidth
                                        radius: Tokens.radiusSm - Tokens.borderWidth
                                        color: "transparent"

                                        // Folders: a big glyph, since there's no
                                        // thumbnail to show.
                                        StyledText {
                                            anchors.centerIn: parent
                                            anchors.verticalCenterOffset: -8
                                            text: "󰉋"
                                            variant: "title"
                                            color: Colors.focus
                                            visible: cell.fileIsDir
                                        }

                                        Image {
                                            anchors.fill: parent
                                            visible: !cell.fileIsDir
                                            source: cell.fileIsDir ? "" : ("file://" + cell.filePath)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            cache: false
                                            sourceSize.width: 240
                                            smooth: true
                                        }

                                        Rectangle {
                                            anchors.left:   parent.left
                                            anchors.right:  parent.right
                                            anchors.bottom: parent.bottom
                                            height: 22
                                            color: Colors.alpha(Colors.surface, 0.85)

                                            StyledText {
                                                anchors.fill: parent
                                                anchors.leftMargin:  Tokens.spacingSm
                                                anchors.rightMargin: Tokens.spacingSm
                                                verticalAlignment: Text.AlignVCenter
                                                text: cell.fileName
                                                variant: "caption"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            visible: cell.picked
                                            anchors.top:    parent.top
                                            anchors.right:  parent.right
                                            anchors.margins: Tokens.spacingXs
                                            width: 20
                                            height: 20
                                            radius: 10
                                            color: Colors.primary

                                            StyledText {
                                                anchors.centerIn: parent
                                                text: "󰄬"
                                                variant: "caption"
                                                color: Colors.fgOnPrimary
                                            }
                                        }
                                    }
                                }

                                HoverHandler { id: cellHover }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (cell.fileIsDir)
                                            root.browseFolder = "file://" + cell.filePath
                                        else
                                            root.togglePick(cell.filePath)
                                    }
                                }
                            }
                        }

                        StyledText {
                            anchors.centerIn: parent
                            visible: fsModel.status === FolderListModel.Ready
                                     && fsModel.count === 0
                            text: "No images or folders here."
                            variant: "body"
                            emphasis: "dim"
                        }
                    }
                }

                // ── The page slider ───────────────────────────────────────────
                // Bound to contentX rather than the page index, so it glides
                // with the slide instead of jumping when the animation lands.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd
                    visible: root.pageCount > 1 && !(root.isImages && root.browsing)

                    StyledText {
                        text: (pager.currentIndex + 1) + " / " + root.pageCount
                        variant: "caption"
                        emphasis: "dim"
                    }

                    ValueSlider {
                        Layout.fillWidth: true
                        maximum: 1.0
                        value: pager.width > 0 && root.pageCount > 1
                            ? pager.contentX / (pager.width * (root.pageCount - 1))
                            : 0
                        onMoved: function(v) {
                            pager.currentIndex = Math.round(v * (root.pageCount - 1))
                        }
                    }

                    StyledText {
                        text: root.shownCount + (root.isImages ? " images" : " scenes")
                        variant: "caption"
                        emphasis: "dim"
                    }
                }

                // ── The one big library action ────────────────────────────────
                // Takes the slack below the gallery: importing on the images tab,
                // the Steam Workshop on the engine tab — each tab's one way of
                // getting MORE wallpapers, as a target you can't miss.
                BigAction {
                    visible: root.isImages && !root.browsing
                    glyph: "󰋺"
                    title: "Add images"
                    caption: "Opens a browser right here — pick pictures from any "
                           + "folder and they're copied in. The originals stay put."
                    onActivated: root.browsing = true
                }

                BigAction {
                    visible: !root.isImages
                    glyph: "󰓓"
                    title: "Browse the Steam Workshop"
                    caption: "Subscribe to wallpapers there, then press Rescan — "
                           + "Steam downloads them into the library this page reads."
                    onActivated: WallpaperEngine.openWorkshopHub()
                }
            }

            // ══ System column — scrolls ═══════════════════════════════════════
            // The engine renderer alone carries a dozen options, so this column is
            // taller than the page. A ColumnLayout can't shrink below its content's
            // total height, so left unscrolled it forced the whole BODY past the
            // viewport and clipped both columns — the left's "Browse the Workshop"
            // action fell off the bottom. Inside a Flickable its minimum height is
            // nil, the body fits again, and the overflow scrolls here where it
            // belongs.
            Item {
                id: sysColHost
                Layout.preferredWidth: root.sideWidth
                Layout.fillWidth:  false
                Layout.fillHeight: true

                Flickable {
                    id: sysFlick
                    anchors.fill: parent
                    contentWidth: width
                    contentHeight: sysCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                ColumnLayout {
                    id: sysCol
                    width: sysFlick.width
                    spacing: Tokens.spacingLg

                // ── Engine: what this tab even is ─────────────────────────────
                // Leads the column on the engine tab: the logo (Steam's own
                // cached copy — nothing vendored), and the two facts that stop
                // the two likeliest confusions: which program renders, and why
                // it needs Wallpaper Engine owned on Steam.
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: !root.isImages
                    implicitHeight: weBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: weBox
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.top:    parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        Image {
                            Layout.preferredWidth: 168
                            Layout.preferredHeight: 50
                            source: "file://" + root.weLogo
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            sourceSize.width: 336
                            smooth: true
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            wrapMode: Text.WordWrap
                            variant: "body"
                            emphasis: "dim"
                            text: "Rendered by linux-wallpaperengine, an open-source "
                                + "engine for Wallpaper Engine's formats. It needs the "
                                + "real Wallpaper Engine installed from Steam — that's "
                                + "where the wallpapers, their assets and the Workshop "
                                + "subscriptions come from."
                        }

                        FactRow {
                            glyph: "󰓓"
                            text: "Get wallpapers by subscribing in the Steam Workshop, "
                                + "then press Rescan"
                        }
                        FactRow {
                            glyph: "󰎁"
                            text: "\"video\" types cost more GPU than \"scene\" types"
                        }
                    }
                }

                // ── Appearance: theming, mode and shuffle ─────────────────────
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    implicitHeight: appearBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: appearBox
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.top:    parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        CardHead { glyph: "󰸌"; title: "Appearance" }

                        OptionRow {
                            label: "Theme from wallpaper"
                            detail: "Off: wallpapers change the picture and nothing else — "
                                  + "the current colours stay exactly as they are."
                            checked: Config.wallTheming
                            onToggled: Config.wallTheming = !Config.wallTheming
                        }

                        // A held colour scheme wins over everything this card
                        // does — better said here than discovered by clicking
                        // Light and watching nothing change.
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            wrapMode: Text.WordWrap
                            variant: "caption"
                            color: Colors.warning
                            visible: Config.wallTheming && ColorScheme.overrideCount > 0
                            text: "A saved colour scheme is holding "
                                + ColorScheme.overrideCount + " colour"
                                + (ColorScheme.overrideCount !== 1 ? "s" : "")
                                + " — Light and Dark can't fully take effect until you "
                                + "release it in the colour panel."
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            opacity: Config.wallTheming ? 1.0 : 0.4

                            PanelButton {
                                Layout.fillWidth: true
                                label: "Light"
                                glyph: "󰖨"
                                variant: Config.themeMode === "light" ? "primary" : "ghost"
                                enabled: Config.wallTheming && !Wallpaper.applying
                                onActivated: {
                                    if (Config.themeMode === "light") return
                                    Config.themeMode = "light"
                                    Wallpaper.reapplyPalette()
                                }
                            }

                            PanelButton {
                                Layout.fillWidth: true
                                label: "Dark"
                                glyph: "󰖔"
                                variant: Config.themeMode === "dark" ? "primary" : "ghost"
                                enabled: Config.wallTheming && !Wallpaper.applying
                                onActivated: {
                                    if (Config.themeMode === "dark") return
                                    Config.themeMode = "dark"
                                    Wallpaper.reapplyPalette()
                                }
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            wrapMode: Text.WordWrap
                            variant: "caption"
                            emphasis: "dim"
                            text: Config.wallTheming
                                ? "Same wallpaper, opposite palette. Light mode caps how "
                                  + "pale the accents can get, so text stays readable."
                                : "Theming is off — use the colour panel to set a palette "
                                  + "by hand, or turn this back on to follow the wallpaper."
                        }

                        // Shuffle is an images-tab concept — the timer refuses to
                        // fire while a scene runs, so offering it on the engine
                        // tab would be a control that does nothing. Hiding it
                        // also keeps the engine column inside the page (it was
                        // 12px from overflow with these rows shown).
                        Divider { visible: root.isImages }

                        OptionRow {
                            visible: root.isImages
                            label: "Shuffle wallpapers"
                            detail: "A random image on a timer. Paused while a scene runs."
                            checked: Config.wallShuffle
                            onToggled: Config.wallShuffle = !Config.wallShuffle
                        }

                        SliderRow {
                            visible: root.isImages
                            label: "Every"
                            from:  Config.wallShuffleMinsMin
                            to:    Config.wallShuffleMinsMax
                            value: Config.wallShuffleMins
                            readout: Config.wallShuffleMins + " min"
                            enabled: Config.wallShuffle
                            onCommit: function(v) { Config.wallShuffleMins = v }
                        }

                        PanelButton {
                            visible: root.isImages
                            label: "Surprise me"
                            glyph: "󰒝"
                            variant: "ghost"
                            enabled: !Wallpaper.applying && Wallpaper.wallpapers.length > 1
                            onActivated: Wallpaper.shuffleNow(true)
                        }

                        // ── Which monitor images land on ──────────────────────
                        Divider { visible: root.isImages && Quickshell.screens.length > 1 }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            visible: root.isImages && Quickshell.screens.length > 1

                            StyledText { text: "Apply to"; variant: "body"; font.weight: Font.DemiBold }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                PanelButton {
                                    label: "All"
                                    variant: Config.wallTarget === "" ? "primary" : "ghost"
                                    onActivated: Config.wallTarget = ""
                                }

                                Repeater {
                                    model: Quickshell.screens
                                    delegate: PanelButton {
                                        required property var modelData
                                        label: modelData.name
                                        variant: Config.wallTarget === modelData.name
                                            ? "primary" : "ghost"
                                        onActivated: Config.wallTarget = modelData.name
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: "dim"
                                text: "Images only — scenes always cover every screen. "
                                    + "The shell's palette stays global either way, "
                                    + "following whichever wallpaper was applied last."
                            }
                        }
                    }
                }

                // ── Library facts (images tab) ────────────────────────────────
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: root.isImages
                    implicitHeight: libBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: libBox
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.top:    parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        CardHead { glyph: "󰉋"; title: "Library" }

                        FactRow {
                            glyph: "󰋩"
                            text: Wallpaper.wallpapers.length + " images in "
                                + Wallpaper.wallpaperDir.replace(
                                      Quickshell.env("HOME"), "~")
                        }
                        FactRow {
                            glyph: "󰋺"
                            text: "“Add images” copies files in — originals stay "
                                + "where they were"
                        }
                        FactRow {
                            glyph: "󰩺"
                            text: "The ✕ on a tile moves it to the trash, not oblivion"
                        }
                        FactRow {
                            glyph: "󰸌"
                            text: "Applying takes a few seconds when theming is on — "
                                + "it repaints GTK, the terminal and the browser too"
                        }
                    }
                }

                // ── Images: failures / stale apps ─────────────────────────────
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: root.isImages
                             && (Wallpaper.lastFailed || Wallpaper.needsRestart)
                             && !Wallpaper.applying
                    implicitHeight: warnBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: warnBox
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.top:    parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            wrapMode: Text.WordWrap
                            variant: "caption"
                            color: Wallpaper.lastFailed ? Colors.warning : Colors.fg
                            text: Wallpaper.lastFailed
                                ? Wallpaper.failedCount + " step"
                                  + (Wallpaper.failedCount !== 1 ? "s" : "")
                                  + " failed — the picture is set, but some apps kept "
                                  + "their old colours."
                                : "Some apps only read the theme when they start, and "
                                  + "are still showing the old colours."
                        }

                        RowLayout {
                            spacing: Tokens.spacingSm

                            PanelButton {
                                label: "Restart them"
                                glyph: "󰜉"
                                visible: Wallpaper.needsRestart
                                onActivated: Wallpaper.restartAll()
                            }
                            PanelButton {
                                label: "Dismiss"
                                variant: "ghost"
                                onActivated: {
                                    if (Wallpaper.lastFailed) Wallpaper.clearResult()
                                    if (Wallpaper.needsRestart) Wallpaper.dismissRestart()
                                }
                            }
                        }
                    }
                }

                // ── Engine: the renderer ──────────────────────────────────────
                Surface {
                    Layout.fillWidth: true
                    elevation: Tokens.elevationNested
                    visible: !root.isImages
                    implicitHeight: engBox.implicitHeight + Tokens.spacingLg * 2

                    ColumnLayout {
                        id: engBox
                        anchors.left:   parent.left
                        anchors.right:  parent.right
                        anchors.top:    parent.top
                        anchors.margins: Tokens.spacingLg
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            BusyDot {
                                running: WallpaperEngine.busy
                                tint: WallpaperEngine.running ? Colors.success : Colors.info
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                variant: "body"
                                text: WallpaperEngine.busy ? "Restarting…"
                                    : WallpaperEngine.needsRefresh ? "Renderer running · changes pending"
                                    : WallpaperEngine.running ? "Renderer running"
                                    : "Renderer stopped"
                            }

                            // Options no longer restart the scene on their own — a
                            // change is collected and applied here, so dragging a
                            // slider doesn't flicker the wallpaper on every tick.
                            PanelButton {
                                label: "Refresh"
                                variant: "primary"
                                visible: WallpaperEngine.needsRefresh
                                onActivated: WallpaperEngine.refresh()
                            }
                            PanelButton {
                                label: "Stop"
                                variant: "ghost"
                                visible: WallpaperEngine.running && !WallpaperEngine.busy
                                onActivated: WallpaperEngine.stop()
                            }
                            PanelButton {
                                label: "Start"
                                visible: !WallpaperEngine.running && !WallpaperEngine.busy
                                         && Config.wpeCurrent !== ""
                                onActivated: WallpaperEngine.apply(Config.wpeCurrent)
                            }
                        }

                        // The renderer's dying words — the tail of its own log.
                        StyledText {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            wrapMode: Text.WrapAnywhere
                            variant: "caption"
                            color: Colors.danger
                            visible: WallpaperEngine.lastError !== ""
                                     && !WallpaperEngine.busy
                            text: "Last start failed:\n" + WallpaperEngine.lastError
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            visible: WallpaperEngine.paletteApplying

                            BusyDot { running: true; tint: Colors.info }
                            StyledText {
                                text: "Recolouring the shell from the scene…"
                                variant: "caption"
                                emphasis: "dim"
                            }
                        }

                        Divider {}

                        OptionRow {
                            label: "Scene colours"
                            detail: "Recolour the shell from the scene's preview"
                            checked: Config.wpeScenePalette
                            onToggled: Config.wpeScenePalette = !Config.wpeScenePalette
                        }

                        // ── Which monitor the scene renders on ────────────────
                        Divider { visible: Quickshell.screens.length > 1 }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            visible: Quickshell.screens.length > 1

                            StyledText {
                                text: "Render on"
                                variant: "body"
                                font.weight: Font.DemiBold
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Tokens.spacingSm

                                PanelButton {
                                    label: "All"
                                    variant: Config.wpeTarget === "" ? "primary" : "ghost"
                                    onActivated: Config.wpeTarget = ""
                                }

                                Repeater {
                                    model: Quickshell.screens
                                    delegate: PanelButton {
                                        required property var modelData
                                        label: modelData.name
                                        variant: Config.wpeTarget === modelData.name
                                            ? "primary" : "ghost"
                                        onActivated: Config.wpeTarget = modelData.name
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: "dim"
                                text: "Pinning one monitor is also the cure for a "
                                    + "scene whose sound doubles across screens — one "
                                    + "screen, one soundtrack."
                            }
                        }

                        SliderRow {
                            label: "Frame rate"
                            from:  Config.wpeFpsMin
                            to:    Config.wpeFpsMax
                            value: Config.wpeFps
                            readout: Config.wpeFps + " fps"
                            onCommit: function(v) { Config.wpeFps = v }
                        }

                        OptionRow {
                            label: "V-Sync"
                            detail: "Syncs the wallpaper to your display to stop "
                                  + "tearing, through the graphics driver."
                            checked: Config.wpeVsync
                            onToggled: Config.wpeVsync = !Config.wpeVsync
                        }

                        SliderRow {
                            label: "Volume"
                            from:  0
                            to:    100
                            value: Config.wpeVolume
                            readout: Config.wpeVolume + "%"
                            enabled: !Config.wpeMute
                            onCommit: function(v) { Config.wpeVolume = v }
                        }

                        OptionRow {
                            label: "Mute"
                            checked: Config.wpeMute
                            onToggled: Config.wpeMute = !Config.wpeMute
                        }
                        OptionRow {
                            label: "Keep audio with other apps"
                            detail: "Off: the wallpaper silences itself whenever "
                                  + "another app plays any sound."
                            checked: Config.wpeKeepAudio
                            onToggled: Config.wpeKeepAudio = !Config.wpeKeepAudio
                        }
                        OptionRow {
                            label: "React to audio"
                            checked: Config.wpeAudioProcessing
                            onToggled: Config.wpeAudioProcessing = !Config.wpeAudioProcessing
                        }
                        OptionRow {
                            label: "Follow the mouse"
                            checked: Config.wpeMouse
                            onToggled: Config.wpeMouse = !Config.wpeMouse
                        }
                        OptionRow {
                            label: "Parallax"
                            checked: Config.wpeParallax
                            onToggled: Config.wpeParallax = !Config.wpeParallax
                        }
                        OptionRow {
                            label: "Pause when fullscreen"
                            checked: Config.wpePauseFullscreen
                            onToggled: Config.wpePauseFullscreen = !Config.wpePauseFullscreen
                        }
                        OptionRow {
                            label: "Start with the shell"
                            checked: Config.wpeAutoStart
                            onToggled: Config.wpeAutoStart = !Config.wpeAutoStart
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm

                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: "dim"
                                text: "Changes apply on their own while the wallpaper is "
                                    + "running — the screen blinks once as it relaunches."
                            }
                            PanelButton {
                                label: "Restart now"
                                glyph: "󰜉"
                                variant: "ghost"
                                visible: WallpaperEngine.running && !WallpaperEngine.busy
                                onActivated: WallpaperEngine.apply(WallpaperEngine.current)
                            }
                        }
                    }
                }

                }
                }

                Scrollbar { flickable: sysFlick }
            }
        }
    }

    // ── Wheel = turn the page, ANYWHERE on the page ───────────────────────────
    // Declared AFTER the content so it sits on top: below it, the gallery's own
    // Flickable consumed every wheel event first, which is why the previous
    // WheelHandler worked headless and did nothing live. `NoButton` keeps it
    // transparent to clicks and hover — wheel is the only thing it takes, from
    // the entire page, which is exactly the request. Deltas accumulate to a
    // notch (±120) so a high-resolution touchpad doesn't fly through the
    // library per swipe.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        // Off while the browser is open, or it would swallow the wheel meant for
        // the file grid and the grid could never scroll.
        enabled: !root.browsing

        property real acc: 0
        onWheel: function(ev) {
            // Over the system column? Decline the event so the column's own
            // Flickable scrolls it, rather than paging the gallery from the far
            // side of the page.
            if (ev.x >= sysColHost.mapToItem(root, 0, 0).x) {
                ev.accepted = false
                return
            }
            acc += ev.angleDelta.y
            if (acc <= -120) { pager.incrementCurrentIndex(); acc = 0 }
            else if (acc >= 120) { pager.decrementCurrentIndex(); acc = 0 }
            ev.accepted = true
        }
    }


    // ── WallTile ──────────────────────────────────────────────────────────────
    // One gallery tile: picture (animated for GIF previews, but only on the
    // visible page), name bar, current mark, hover Apply, and the ✕ delete.
    component WallTile: Item {
        id: tile

        property var entry
        property int pageIndex: 0

        // Branch on the ENTRY's shape, never on root.isImages: during a tab
        // switch the flag flips while the outgoing tiles still exist for a
        // frame, so a string entry got asked for `.id` — undefined, three
        // warnings per tile, nine tiles per switch. The entry itself can't be
        // out of sync with what it is.
        readonly property bool isScene:
            tile.entry !== undefined && typeof tile.entry === "object"
                && tile.entry !== null

        readonly property string key: !tile.isScene
            ? String(tile.entry ?? "")
            : (tile.entry.id ?? "")
        readonly property string name: !tile.isScene
            ? String(tile.entry ?? "").split("/").pop()
            : (tile.entry.title ?? "")
        readonly property string thumb: {
            if (!tile.isScene) {
                const p = String(tile.entry ?? "")
                return p !== "" ? "file://" + p : ""
            }
            const prev = tile.entry.preview ?? ""
            return prev !== "" ? "file://" + prev : ""
        }
        readonly property bool isGif: tile.thumb.toLowerCase().endsWith(".gif")
        // Animate ONLY while this tile's page is the one on screen: six playing
        // GIF decoders is the deliberate ceiling, and parked pages cost nothing.
        readonly property bool animate: pager.currentIndex === tile.pageIndex
        readonly property bool isCurrent: root.isImages
            ? (!root.sceneOnScreen && Wallpaper.current === tile.name)
            : (root.sceneOnScreen && WallpaperEngine.current === tile.key)
        readonly property bool busy: root.isImages
            ? (Wallpaper.applying && Wallpaper.applyingPath === tile.key)
            : (WallpaperEngine.busy && Config.wpeCurrent === tile.key)

        property bool armed: false
        Timer {
            id: disarm
            interval: 4000
            onTriggered: tile.armed = false
        }

        function doApply() {
            if (root.applyBusy || tile.isCurrent) return
            if (root.isImages) Wallpaper.apply(tile.key)
            else               WallpaperEngine.apply(tile.key)
        }

        function doDelete() {
            if (!tile.armed) {
                tile.armed = true
                disarm.restart()
                return
            }
            tile.armed = false
            if (root.isImages) {
                Wallpaper.remove(tile.key)
            } else {
                WallpaperEngine.openWorkshop(tile.key)
                WallpaperEngine.remove(tile.key)
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Tokens.radiusPill
            color: Colors.surfaceContainer
            border.width: tile.isCurrent ? 2 : (hover.hovered ? 1 : 0)
            border.color: tile.isCurrent ? Colors.info : Colors.outlineFocus

            Behavior on border.color { ColorAnimation { duration: Motion.respond } }

            // Everything visual lives INSIDE the clipper so the rounded corners
            // are real — `clip: true` clips to the bounding box and quietly left
            // square image corners inside every previous version's round cards.
            ClippingRectangle {
                anchors.fill: parent
                anchors.margins: Tokens.borderWidth
                radius: Tokens.radiusPill - Tokens.borderWidth
                color: "transparent"

                Image {
                    anchors.fill: parent
                    source: tile.isGif ? "" : tile.thumb
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 480
                    smooth: true
                }

                AnimatedImage {
                    anchors.fill: parent
                    source: tile.isGif ? tile.thumb : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    playing: tile.isGif && tile.animate
                    // A parked page shows its last frame rather than unloading —
                    // paging back doesn't re-decode from scratch.
                    paused: !tile.animate
                }

                StyledText {
                    anchors.centerIn: parent
                    text: "󰋩"
                    variant: "title"
                    emphasis: "dim"
                    visible: tile.thumb === ""
                }

                // Name bar inside the picture.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 26
                    color: Colors.alpha(Colors.surface, 0.85)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Tokens.spacingMd
                        anchors.rightMargin: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        StyledText {
                            text: "󰄬"
                            variant: "caption"
                            color: Colors.info
                            visible: tile.isCurrent
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: tile.name
                            variant: "caption"
                            elide: Text.ElideRight
                        }
                        StyledText {
                            text: !tile.isScene
                                ? String(tile.entry ?? "").split(".").pop().toLowerCase()
                                : (tile.entry.type ?? "")
                            variant: "caption"
                            emphasis: "dim"
                        }
                    }
                }

                // ── Hover: the one primary action ─────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    color: Colors.alpha(Colors.surface, 0.55)
                    opacity: hover.hovered || tile.armed ? 1.0 : 0.0
                    visible: opacity > 0.005

                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }

                    PanelButton {
                        anchors.centerIn: parent
                        label: tile.busy ? "Applying…"
                             : tile.isCurrent ? "Applied" : "Apply"
                        glyph: "󰄬"
                        variant: tile.isCurrent ? "ghost" : "primary"
                        enabled: !root.applyBusy && !tile.isCurrent
                        onActivated: tile.doApply()
                    }

                    StyledText {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 34
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - Tokens.spacingLg * 2
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        emphasis: "dim"
                        visible: tile.armed
                        text: root.isImages
                            ? "Press ✕ again to move it to the trash."
                            : "Press ✕ again to delete the files and open its Workshop "
                              + "page — unsubscribe there, or Steam downloads it again."
                    }
                }

                // ── Delete: the ✕, top-right ──────────────────────────────────
                Rectangle {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Tokens.spacingSm
                    width: 24
                    height: 24
                    radius: 12
                    color: tile.armed ? Colors.danger : Colors.alpha(Colors.surface, 0.85)
                    border.width: Tokens.borderWidth
                    border.color: tile.armed ? Colors.danger : Colors.outline
                    opacity: hover.hovered || tile.armed ? 1.0 : 0.0
                    visible: opacity > 0.005

                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    Behavior on color   { ColorAnimation  { duration: Motion.respond } }

                    StyledText {
                        anchors.centerIn: parent
                        text: "󰅖"
                        variant: "caption"
                        color: tile.armed ? Colors.fgOnPrimary : Colors.fg
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tile.doDelete()
                    }
                }

                BusyDot {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: Tokens.spacingSm
                    running: tile.busy
                    tint: Colors.info
                }
            }
        }

        HoverHandler {
            id: hover
            onHoveredChanged: if (!hovered) tile.armed = false
        }
    }

    // ── BigAction — a large click target: icon in the middle, words under it ──
    component BigAction: Rectangle {
        id: act

        property string glyph: ""
        property string title: ""
        property string caption: ""
        signal activated()

        Layout.fillWidth: true
        Layout.preferredHeight: 88
        radius: Tokens.radiusPill
        color: actHover.hovered && act.enabled
            ? Colors.alpha(Colors.primary, 0.10)
            : Colors.surfaceContainer
        border.width: Tokens.borderWidth
        border.color: actHover.hovered && act.enabled ? Colors.outlineFocus
                                                      : Colors.outline
        opacity: act.enabled ? 1.0 : 0.5

        Behavior on color        { ColorAnimation { duration: Motion.respond } }
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

        RowLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Tokens.spacingLg * 4, 560)
            spacing: Tokens.spacingLg

            StyledText {
                text: act.glyph
                variant: "title"
                color: Colors.focus
                font.pixelSize: 26
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacingXs / 2

                StyledText {
                    text: act.title
                    variant: "body"
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: act.caption
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
            }
        }

        HoverHandler { id: actHover }
        MouseArea {
            anchors.fill: parent
            cursorShape: act.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (act.enabled) act.activated()
        }
    }

    // ── FactRow / FactChip — the About page's icon-led rows, in miniature ─────
    // Children reference the component root by ID, never `parent`: during
    // construction `parent` is briefly null, and every binding through it fired
    // an "Unable to assign [undefined] to QString" warning per re-evaluation —
    // three lines of this page were most of the reload's log noise.
    component FactRow: RowLayout {
        id: factRow
        property string glyph: ""
        property string text: ""
        Layout.fillWidth: true
        spacing: Tokens.spacingSm

        StyledText { text: factRow.glyph; variant: "body"; color: Colors.focus }
        StyledText {
            Layout.fillWidth: true
            Layout.preferredWidth: 0
            text: factRow.text
            variant: "body"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
    }

    component FactChip: RowLayout {
        id: factChip
        property string glyph: ""
        property string text: ""
        spacing: Tokens.spacingXs

        StyledText { text: factChip.glyph; variant: "caption"; color: Colors.focus }
        StyledText { text: factChip.text; variant: "caption"; emphasis: "dim" }
    }

    // ── CardHead — a section header with an identity, like the Bar page's ─────
    component CardHead: RowLayout {
        id: cardHead
        property string glyph: ""
        property string title: ""
        Layout.fillWidth: true
        spacing: Tokens.spacingSm

        StyledText { text: cardHead.glyph; variant: "body"; color: Colors.focus }
        StyledText {
            Layout.fillWidth: true
            text: cardHead.title
            variant: "body"
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }

    // ── OptionRow ─────────────────────────────────────────────────────────────
    component OptionRow: RowLayout {
        id: opt
        property string label:  ""
        property string detail: ""
        property bool   checked: false
        signal toggled()

        Layout.fillWidth: true
        spacing: Tokens.spacingSm

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText { text: opt.label; variant: "body" }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                text: opt.detail
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
                visible: opt.detail !== ""
            }
        }

        Toggle {
            checked: opt.checked
            onToggled: opt.toggled()
        }
    }

    // ── SliderRow ─────────────────────────────────────────────────────────────
    // Maps a real range onto ValueSlider's normalised 0..1, same as the bar page's.
    // Still duplicated deliberately — lifting BarPage's local component into
    // components/ is its own change, not something to smuggle into this one.
    component SliderRow: RowLayout {
        id: sliderRow

        property string label: ""
        property real from:  0
        property real to:    100
        property real value: 0
        property real step:  1
        property string readout: String(sliderRow.value)

        signal commit(real v)

        function quantise(v) {
            return Math.round(Math.round(v / sliderRow.step) * sliderRow.step * 1e6) / 1e6
        }

        Layout.fillWidth: true
        spacing: Tokens.spacingSm
        opacity: sliderRow.enabled ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }

        StyledText {
            Layout.preferredWidth: 84
            text:    sliderRow.label
            variant: "body"
            elide:   Text.ElideRight
        }

        ValueSlider {
            Layout.fillWidth: true
            maximum: 1.0
            value: sliderRow.to > sliderRow.from
                ? (sliderRow.value - sliderRow.from) / (sliderRow.to - sliderRow.from)
                : 0
            onMoved: function(v) {
                sliderRow.commit(sliderRow.quantise(
                    sliderRow.from + v * (sliderRow.to - sliderRow.from)))
            }
        }

        StyledText {
            Layout.preferredWidth: 50
            text: sliderRow.readout
            variant: "caption"
            emphasis: "dim"
            horizontalAlignment: Text.AlignRight
        }
    }
}
