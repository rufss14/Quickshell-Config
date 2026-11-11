pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/wallpaperentry.js" as WEntry
import "../wallpaper"
import "../../../services/wallpaperlib.js" as Lib

// ── WallpaperPanelBody ── part of WallpaperPanel.qml; `panel` is the WallpaperPanel it belongs to. ──
Item {
    id: body
    required property var panel
    property alias grid: grid
    property alias list: list
    property alias browseLoader: browseLoader
    Layout.fillWidth: true
    Layout.fillHeight: true
    visible: !panel.swapped

    // ── Source-switch and view transitions ────────────────────────────
    // A tab swap (Images / Scenes / Material) changes the whole model under the same views, and
    // a view change (gallery → browser / options / one scene's properties) swaps what the body
    // holds. Both are ONE move: the old content is gone in the same tick — so a GridView's
    // repopulate happens while nothing is visible — and the new page comes in from the side it
    // belongs to (a tab: right for Scenes, left for Images; a view: from the right going deeper,
    // from the left coming back). It slides home with a small overshoot, settling from a touch
    // smaller, while its tiles pop in one after another on their own springs
    // (WallpaperTile.arrive — the delegates are new, so every tile makes its entrance). No
    // per-tile transition: it would fire during this fade and fight it, which is what read as
    // "not smooth". The fade and the scale are two properties (`fadeK`, `enterK`) multiplied
    // into `opacity` / `scale`, never assigned to them, so the choosing fold's own opacity
    // binding survives (it was broken by the first tab switch).
    property real fadeK:  1
    property real enterK: 1
    property real chooseK: panel.choosing ? 0 : 1
    Behavior on chooseK { NumberAnimation { duration: Motion.fast } }
    opacity: body.chooseK * Math.max(0, Math.min(1, body.fadeK))
    scale: 0.97 + 0.03 * body.enterK
    transform: Translate { id: bodyShift }

    property string _lastView: "gallery"
    function _depth(v) { return v === "properties" ? 2 : (v === "browse" || v === "settings" || v === "effects") ? 1 : 0 }
    function _enter(dir) {
        if (!Config.motionEnabled) return
        body.fadeK = 0
        body.enterK = 0
        bodyShift.x = dir * 56
        sourceIn.restart()
    }

    Connections {
        target: panel
        // The tab, not the source: Material is a view, and a change of source from inside
        // it is one move, not two.
        function onTabChanged() { body._enter(panel.tab === "images" ? -1 : 1) }
        function onViewChanged() {
            const was = body._lastView
            body._lastView = panel.view
            // Material is a tab: its own change is the tab's move.
            if (was === "material" || panel.view === "material") return
            body._enter(body._depth(panel.view) >= body._depth(was) ? 1 : -1)
        }
    }
    ParallelAnimation {
        id: sourceIn
        NumberAnimation {
            target: body; property: "fadeK"
            from: 0; to: 1
            duration: Motion.spatial
            easing.type: Motion.travel
        }
        NumberAnimation {
            target: body; property: "enterK"
            to: 1
            duration: Motion.spatialSlow
            easing.type: Motion.travel
        }
        NumberAnimation {
            target: bodyShift; property: "x"
            to: 0
            duration: Motion.spatialSlow
            easing.type: Motion.overshoot
            easing.overshoot: 1.1
        }
    }

    // ── Grid ──────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        // Three columns across the whole width. The scrollbar is an overlay (4px, only while
        // scrolling), so it needs no gutter: the margins stay even on both sides.
        cellWidth:  Math.floor(grid.width / 3)
        cellHeight: Math.round(grid.cellWidth * 0.64)
        // A ScriptModel, so a change to the list (starring or removing one) is applied as
        // inserts, removes and moves to the delegates that are there — and the view keeps
        // its place. Handing the GridView a fresh array each time replaced the whole model,
        // which resets the scroll to the top.
        model: ScriptModel { values: panel.galleryModel }
        cacheBuffer: 500
        maximumFlickVelocity: 2500
        flickDeceleration: 1500

        opacity: panel.inGallery && !panel.listView && !panel.galleryEmpty ? 1.0 : 0.0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        // A little air under the last row, so a tile never ends on the panel's edge.
footer: Item { width: 1; height: Tokens.spacingLg }
delegate: WallpaperTile {
            panel:  body.panel
            width:  grid.cellWidth
            height: grid.cellHeight
        }
    }
    Scrollbar { flickable: grid }

    // ── List ──────────────────────────────────────────────────────────
    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: Tokens.spacingSm
        model: ScriptModel { values: panel.galleryModel }

        opacity: panel.inGallery && panel.listView && !panel.galleryEmpty ? 1.0 : 0.0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        footer: Item { width: 1; height: Tokens.spacingLg }
delegate: WallpaperRow {
            panel: body.panel
            width: list.width
        }
    }
    Scrollbar { flickable: list }

    // ── Select mode's bar ─────────────────────────────────────────────
    ChipTray {
        z: 5
        groupShown: panel.selecting && panel.inGallery
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingMd

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: Tokens.spacingSm
            text: panel.selected.length + " selected"
            variant: "label"
        }
        ChipButton {
            symbol: "select_all"
            label: panel.allSelected ? "None" : "All"
            on: panel.allSelected
            tint: panel.accent
            onActivated: panel.toggleSelectAll()
        }
        ChipButton {
            symbol: panel.isImages ? "delete" : "delete_forever"
            label: panel.bulkLatch.armed
                ? (panel.isImages ? "Trash " + panel.selected.length + "?"
                                 : "Delete + unsubscribe " + panel.selected.length + "?")
                : "Delete"
            on: panel.bulkLatch.armed
            tint: Colors.of(QsWindow.window).danger
            enabled: panel.selected.length > 0
            onActivated: panel.bulkLatch.trigger()
        }
        ChipButton {
            symbol: "close"
            onActivated: panel.endSelect()
        }
    }

    // Soft edges: tiles fade into the panel instead of being cut by the clip.
    // Only while there is more to scroll in that direction. spacingXxl, not Lg:
    // at 12px the fade was too short to read, and the last row looked sliced.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: Tokens.spacingXxl
        readonly property Flickable fl: panel.listView ? list : grid
        opacity: panel.inGallery && fl.contentY > 1 ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).surface }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0) }
        }
    }
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Tokens.spacingXxl
        readonly property Flickable fl: panel.listView ? list : grid
        opacity: panel.inGallery && fl.contentY + fl.height < fl.contentHeight - 1 ? 1 : 0
        visible: opacity > 0.005
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).surface, 0) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).surface }
        }
    }

    // ── Empty state ───────────────────────────────────────────────────
    // Replaces the gallery outright rather than floating over it: with an
    // empty library the grid still holds the action card, and a centred
    // "nothing here" landing on top of it read as a rendering fault.
    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Tokens.spacingXxl * 2
        spacing: Tokens.spacingSm
        visible: panel.inGallery && panel.galleryEmpty && !panel.scanning

        MaterialIcon {
            Layout.alignment: Qt.AlignHCenter
            name: panel.searchInput.text.length > 0 ? "search_off" : panel.isImages ? "image_not_supported" : "movie"
            variant: "headline"
            emphasis: "dim"
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: panel.searchInput.text.length > 0
                ? "No matches"
                : panel.isImages ? "No wallpapers found" : "No scenes installed"
            variant: "body"
            font.weight: Font.DemiBold
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: panel.searchInput.text.length > 0
                ? "Nothing here is called “" + panel.searchInput.text + "”."
                : panel.isImages
                    ? "Put images in " + Wallpaper.wallpaperDir + " and rescan."
                    : "Subscribe to wallpapers in the Steam Workshop, then rescan."
            variant: "caption"
            emphasis: "dim"
            wrapMode: Text.WordWrap
        }
        PanelButton {
            Layout.alignment: Qt.AlignHCenter
            visible: panel.searchInput.text.length === 0
            variant: "normal"
            glyph: panel.actionEntry.glyph
            label: panel.actionEntry.title
            onActivated: panel.runAction(panel.actionEntry.action)
        }
    }

    // ── The file browser ──────────────────────────────────────────────
    // Behind a Loader, and this one is not housekeeping: a GridView builds
    // delegates for its viewport whether or not it is visible, so an
    // always-mounted browser would decode a screenful of $HOME thumbnails
    // every time the wallpaper panel opened — for a view most openings never
    // use. The FolderListModel lives inside it for the same reason.
    Loader {
        id: browseLoader
        anchors.fill: parent
        anchors.rightMargin: Tokens.spacingMd
        active: panel.view === "browse" && !panel.showProgress
        sourceComponent: panel.browseComponent
    }

    // ── Renderer settings ─────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        anchors.rightMargin: Tokens.spacingMd
        active: panel.view === "settings"
        sourceComponent: panel.settingsComponent
    }

    // ── The music effects ─────────────────────────────────────────────
    Loader {
        anchors.fill: parent
        anchors.rightMargin: Tokens.spacingMd
        active: panel.view === "effects"
        sourceComponent: panel.effectsComponent
    }

    // ── The Material Wallpaper: its preview and its style ──────────────
    Loader {
        anchors.fill: parent
        anchors.rightMargin: Tokens.spacingMd
        active: panel.isMaterial
        sourceComponent: panel.materialComponent
    }

    // ── One scene's custom properties ──────────────────────────────────
    Loader {
        anchors.fill: parent
        anchors.rightMargin: Tokens.spacingMd
        active: panel.view === "properties"
        sourceComponent: panel.propertiesComponent
    }


    // ── Progress ──────────────────────────────────────────────────────
    Flickable {
        id: progressPane
        anchors.fill: parent
        contentHeight: progressCol.implicitHeight
        clip: true

        opacity: panel.showProgress ? 1.0 : 0.0
        visible: opacity > 0.005
        interactive: panel.showProgress
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        ColumnLayout {
            id: progressCol
            width: progressPane.width
            spacing: Tokens.spacingXs

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: Tokens.spacingSm
                spacing: Tokens.spacingMd

                BusyDot { running: panel.applyBusy; tint: panel.accent }
                StyledText {
                    Layout.fillWidth: true
                    text: panel.progressTitle
                    variant: "body"
                    font.weight: Font.DemiBold
                    color: panel.applyBusy ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).warning
                    elide: Text.ElideRight
                }
                // Details are OPT-IN. Fourteen step lines on every single wallpaper
                // change is noise you have to look past — you only care which step
                // it was when something went wrong. Auto-opened on failure, for
                // exactly that reason. Scenes have no steps to open.
                PanelButton {
                    visible: panel.isImages
                    variant: "ghost"
                    symbol: panel.showDetails ? "keyboard_arrow_up" : "keyboard_arrow_down"
                    label: Translation.tr("Details")
                    onActivated: panel.showDetails = !panel.showDetails
                }
                PanelButton {
                    visible: !panel.applyBusy
                    variant: "ghost"
                    label: Translation.tr("Dismiss")
                    onActivated: {
                        if (panel.isImages) Wallpaper.clearResult()
                        else               WallpaperEngine.clearError()
                    }
                }
            }

            // The renderer's dying words — the tail of its own log. There is no
            // step protocol to show instead, and a bare "it failed" would send
            // you to a log file this panel has already read.
            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: !panel.isImages && !WallpaperEngine.busy
                         && WallpaperEngine.lastError !== ""
                text: WallpaperEngine.lastError
                variant: "caption"
                color: Colors.of(QsWindow.window).danger
                wrapMode: Text.WrapAnywhere
            }

            Repeater {
                model: panel.isImages && panel.showDetails ? Wallpaper.steps : []
                delegate: RowLayout {
                    id: stepRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Tokens.spacingMd

                    // The icon carries the state as well as the colour: `danger`
                    // shares a hue with `primary` in this palette, so colour alone
                    // can't be what marks a failure.
                    MaterialIcon {
                        name: stepRow.modelData.status === "ok"   ? "check"
                            : stepRow.modelData.status === "fail" ? "close"
                            : stepRow.modelData.status === "skip" ? "sleep"
                            : "hourglass_empty"
                        color: stepRow.modelData.status === "ok"   ? Colors.of(QsWindow.window).success
                             : stepRow.modelData.status === "fail" ? Colors.of(QsWindow.window).danger
                             : Colors.of(QsWindow.window).fgDim
                        variant: "caption"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: stepRow.modelData.text
                        variant: "caption"
                        emphasis: stepRow.modelData.status === "skip" ? "dim" : "normal"
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    Scrollbar { flickable: progressPane }
}
