pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/clips.js" as ClipsJs

// ── ClipsGalleryPanel ─────────────────────────────────────────────────────────
// The clip library, and the player / editor it opens into. Two views:
//
//   library   every clip and recording in Clips.saveDir, by day — one toolbar (search, filter,
//             sort). A click PLAYS a clip; pointing at one shows its star / edit / copy on the
//             frame; the tick (or Ctrl / Shift) selects, and a bar rises from the foot with what
//             can be done to the selection (play and edit for one; star, copy, shrink, delete
//             for several) and a big Clear. Nothing reflows when a selection appears.
//   player /  ClipEditor: "Play" opens it view-only (the clip plays in THIS shell — never the
//   editor    system's video app); "Edit" flips it to the editor: cut it, export it.
//
// ── Restyled (2026-10-18) to the media / colours panels' look ─────────────────
// ChipTray headers and toolbars, a SegmentSwitch for the filter, flat `section` cards (no outline),
// tiles and cards arriving on a spring (PopIn), a CookieButton for play. The clear controls are
// big on purpose: a disc as tall as the search field clears it, and a selection shows a banner with a
// full-size "Clear selection" button.
//
// ── Added 2026-10-18 ──────────────────────────────────────────────────────────
//   · Today — the library opens on it when there is something from today, else on All;
//   · a game filter (clips are named after the window: clips.js gameOf), once there are two games;
//   · multi-select: Ctrl-click or the tick on a tile, Shift-click for a range, Ctrl+A for all — then a
//     bulk pane: star, copy as files, shrink to a Discord size (one after another), delete (asks);
//   · drag a clip OUT (the handle on its thumbnail) into a chat or a file manager, as a file;
//   · `Clips.editRequest`: the peek / panel's "edit" opens this on a clip, in the editor.
//
// The panel recipe: PanelHeader + ActionGroup, tokens throughout, shared widgets.
// Everything real is services/Clips; this shows it and calls it. Hosted by
// ClipsGallery (its own PanelWindow).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: panel

    signal closeRequested()
    function focusSearch() { if (panel.view === "library") search.forceFocus() }

    // ══ Which view ════════════════════════════════════════════════════════════
    property string view: "library"            // "library" | "editor" (which is also the player)
    // The entry being played or edited: a plain copy, set on the way in and never cleared by
    // a refresh (a rename changes the path; the index catches up a moment later).
    property var editing: null
    // Watching, not cutting: ClipEditor.viewOnly.
    property bool viewOnly: false
    function openEditor(entry) { panel._open(entry, false) }
    function openPlayer(entry) { panel._open(entry, true) }
    function _open(entry, watch) {
        if (!entry || !entry.ok) return
        panel.editing = entry
        panel.viewOnly = watch
        panel.selectedPath = entry.path
        panel.view = "editor"
        Qt.callLater(function () { if (editorLoader.item) editorLoader.item.forceActiveFocus() })
    }
    function closeEditor() {
        panel.view = "library"
        if (panel.editing) panel.selectedPath = panel.editing.path
        Qt.callLater(function () { search.forceFocus() })
    }

    // ══ The library ═══════════════════════════════════════════════════════════
    property string query: ""
    property string filter: "all"
    property string sort: "newest"
    property string game: ""
    // The library opens on Today when anything is from today — once, and never over a pick of yours.
    property bool _filterTouched: false
    property bool _filterDefaulted: false
    function _defaultFilter() {
        if (panel._filterTouched || panel._filterDefaulted || Clips.clips.length === 0) return
        panel._filterDefaulted = true
        const now = Date.now()
        panel.filter = Clips.clips.some(c => ClipsJs.isToday(c.mtime, now)) ? "today" : "all"
    }
    Component.onCompleted: { panel._defaultFilter(); panel._consumeRequests() }
    readonly property var games: ClipsJs.gamesOf(Clips.clips)
    readonly property var shown: ClipsJs.libraryView(Clips.clips, panel.query, panel.filter,
                                                     Clips.favourites, panel.sort, panel.game, Date.now())

    // ── What is selected ──────────────────────────────────────────────────────
    // A tick on a tile (or Ctrl-click; Shift-click for a range; Ctrl+A for all) selects it, and a bar
    // rises from the foot of the library with what can be done to the selection. A plain click PLAYS a
    // clip — until something is selected, when a click toggles instead, the way a photo library does.
    // `multi` is the selection, by path; `anchor` is where a Shift range starts. Nothing reflows when a
    // selection appears: the bar floats over the grid.
    property var multi: []
    property string anchor: ""
    readonly property bool hasSelection: panel.multi.length > 0
    readonly property bool bulk: panel.multi.length > 1
    readonly property var multiEntries: panel.multi.map(p => Clips.clips.find(c => c.path === p)).filter(c => !!c)
    function isSelected(path) { return panel.multi.indexOf(path) >= 0 }
    function toggleMulti(path) {
        const m = panel.multi.slice()
        const i = m.indexOf(path)
        if (i >= 0) m.splice(i, 1); else m.push(path)
        panel.multi = m
        panel.anchor = path
    }
    function rangeTo(path) {
        const list = panel.shown.map(c => c.path)
        const a = list.indexOf(panel.anchor), b = list.indexOf(path)
        if (a < 0 || b < 0) { panel.toggleMulti(path); return }
        panel.multi = list.slice(Math.min(a, b), Math.max(a, b) + 1)
    }
    function selectAll() { panel.multi = panel.shown.map(c => c.path) }
    function clearSelection() { panel.multi = []; panel.anchor = "" }
    // A drag carries the whole selection when the tile is part of one, else just itself.
    function dragPaths(path) { return panel.isSelected(path) ? panel.multi : [path] }
    readonly property real totalBytes: Clips.clips.reduce((n, c) => n + (c.size || 0), 0)

    // The library as days ("Today", "Yesterday", "Monday"…) when it is in day order (newest / oldest);
    // one unlabelled group when sorted by length or size (clips.js groupByDay).
    readonly property bool byDay: panel.sort === "newest" || panel.sort === "oldest"
    readonly property var groups: ClipsJs.groupByDay(panel.shown, Date.now(), panel.byDay)
    readonly property var sorts: [{ value: "newest", label: "Newest" }, { value: "oldest", label: "Oldest" },
                                  { value: "longest", label: "Longest" }, { value: "largest", label: "Largest" }]
    function nextSort() {
        const i = panel.sorts.findIndex(x => x.value === panel.sort)
        panel.sort = panel.sorts[(i + 1) % panel.sorts.length].value
    }

    // The file being edited, by path: when it is renamed the editor follows it to the new name (the
    // index catches up a moment after the rename).
    property string selectedPath: ""
    readonly property var resolved: Clips.clips.find(c => c.path === panel.selectedPath) ?? null
    onResolvedChanged: {
        if (!panel.resolved) return
        if (panel.view === "editor" && panel.editing && panel.editing.path !== panel.resolved.path
            && panel._renamedFrom === panel.editing.path)
            panel.editing = panel.resolved
    }

    // A rename lands on the file it made; so does an export (not a saved frame).
    // In the editor, only a rename moves the selection — an export leaves you on
    // the clip you're cutting, and says where the new one went.
    property string _renamedFrom: ""
    Connections {
        target: Clips
        function onActionResultChanged() {
            const r = Clips.actionResult
            if (!r.select) return
            if (panel.view === "editor" && r.text.startsWith("Renamed")) {
                panel._renamedFrom = panel.editing ? panel.editing.path : ""
                panel.selectedPath = r.path
            } else if (panel.view === "library") {
                // What you just made or renamed is selected, so it is easy to find in the grid.
                panel.multi = [r.path]
                panel.anchor = r.path
            }
        }
    }

    // "Play" / "Edit" from the peek, the panel or the launcher: open it here, as soon as the library
    // knows the file. The request is cleared once taken (or once it can't be).
    function _consumeRequests() {
        const play = Clips.playRequest, edit = Clips.editRequest
        const path = play !== "" ? play : edit
        if (path === "") return
        const e = Clips.clips.find(c => c.path === path)
        if (!e) return
        if (play !== "") Clips.playRequest = ""; else Clips.editRequest = ""
        if (play !== "") panel.openPlayer(e); else panel.openEditor(e)
    }
    Connections {
        target: Clips
        function onEditRequestChanged() { panel._consumeRequests() }
        function onPlayRequestChanged() { panel._consumeRequests() }
        function onClipsChanged() { panel._defaultFilter(); panel._consumeRequests() }
    }

    readonly property string homeDir: Quickshell.env("HOME") || ""
    function tilde(p) {
        return panel.homeDir !== "" && p.startsWith(panel.homeDir) ? "~" + p.slice(panel.homeDir.length) : p
    }

    // Escape lets go of a selection first, then closes. (The player takes Escape first, to come back here.)
    Keys.onEscapePressed: {
        if (panel.hasSelection && panel.view === "library") panel.clearSelection()
        else panel.closeRequested()
    }
    Keys.onPressed: function (e) {
        if (panel.view === "library" && (e.modifiers & Qt.ControlModifier) && e.key === Qt.Key_A) {
            panel.selectAll()
            e.accepted = true
        }
    }

    // Delete asks twice, and always to the trash. Letting go of the selection (or changing it) disarms it.
    ArmLatch {
        id: selLatch
        onConfirmed: { Clips.trashClips(panel.multi); panel.clearSelection() }
    }
    onMultiChanged: selLatch.disarm()

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingXl
        spacing: Tokens.spacingMd

        PanelHeader {
            Layout.fillHeight: false
            glyph:     panel.view === "editor" ? (panel.viewOnly ? "\u{F040A}" : "\u{F0190}") : "\u{F0567}"   // 󰐊 play / 󰆐 content-cut / 󰕧 video
            title:     Translation.tr("Clip")
            titleTail: panel.view === "editor" ? (panel.viewOnly ? "player" : "editor") : "library"
            accent:    Colors.of(QsWindow.window).primary
            subtitle:  panel.view === "editor" ? (panel.editing?.name ?? "")
                     : Clips.clips.length === 0 ? panel.tilde(Clips.saveDir)
                     : Clips.clips.length + (Clips.clips.length === 1 ? " clip" : " clips")
                       + "  ·  " + NetStats.bytes(panel.totalBytes) + "  ·  " + panel.tilde(Clips.saveDir)

            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: Clips.indexing || Clips.acting || Clips.exporting
            }

            // What the recorder is doing, one tap away: clipping on/off, record.
            ChipTray {
                ChipButton {
                    symbol: "replay"
                    label: Clips.clipping ? "Clipping" : "Clipping off"
                    on: Clips.clipping
                    tint: Colors.of(QsWindow.window).primary
                    enabled: Clips.blocker() === ""
                    onActivated: Clips.toggleClipping()
                }
                ChipButton {
                    symbol: Clips.recording ? "stop" : "fiber_manual_record"
                    label: Clips.recording ? "Stop" : "Record"
                    on: Clips.recording
                    tint: Colors.of(QsWindow.window).danger
                    enabled: Clips.blocker() === ""
                    onActivated: Clips.toggleRecord()
                }
            }
            ChipTray {
                ChipButton {
                    symbol: "folder_open"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: Clips.openFolder()
                }
                ChipButton {
                    symbol: "settings"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: { UiState.openSettingsTo("ClipsPage.qml"); panel.closeRequested() }
                }
                ChipButton {
                    symbol: "close"
                    tint: Colors.of(QsWindow.window).primary
                    onActivated: panel.closeRequested()
                }
            }
        }

        // ══ Library view ══════════════════════════════════════════════════════
        ColumnLayout {
            visible: panel.view === "library"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── One toolbar: search, filter, sort ─────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingMd

                InputField {
                    id: search
                    Layout.fillWidth: true
                    Layout.minimumWidth: Tokens.sideCardUnit * 3
                    icon: "search"
                    cornerRadius: implicitHeight / 2
                    placeholder: Translation.tr("Search clips")
                    onEdited: function (v) { panel.query = v }
                }
                // Clear: a disc as tall as the field — a target you do not have to aim at.
                Rectangle {
                    Layout.preferredWidth: opacity > 0.01 ? Tokens.fieldHeight : 0
                    Layout.preferredHeight: Tokens.fieldHeight
                    radius: width / 2
                    clip: true
                    opacity: panel.query !== "" ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                    color: clearSearchMouse.containsMouse ? Colors.of(QsWindow.window).primary
                                                          : Colors.of(QsWindow.window).surfaceContainer
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "close"
                        color: clearSearchMouse.containsMouse ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                    }
                    MouseArea {
                        id: clearSearchMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { search.clear(); panel.query = ""; search.forceFocus() }
                    }
                }
                // The filter: a segmented pill, as wide as it needs and no wider.
                SegmentSwitch {
                    Layout.preferredWidth: Tokens.sideCardUnit * 10
                    Layout.fillHeight: false
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "all", label: "All" },
                            { value: "today", label: "Today" },
                            { value: "favourites", label: "Starred" },
                            { value: "clip", label: "Clips" },
                            { value: "recording", label: "Recordings" },
                            { value: "edit", label: "Edits" }]
                    current: panel.filter
                    onPicked: function (v) { panel._filterTouched = true; panel.filter = v }
                }
                // The sort is one chip: it says how it is sorted, and a click goes to the next.
                ChipTray {
                    ChipButton {
                        symbol: "expand_more"
                        label: panel.sorts.find(x => x.value === panel.sort)?.label ?? "Newest"
                        tint: Colors.of(QsWindow.window).primary
                        onActivated: panel.nextSort()
                    }
                }
            }
            // The games in the library (a clip is named after the window it was cut in).
            ChipRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: panel.games.length >= 2
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "", label: "All games" }].concat(panel.games.slice(0, 7).map(g => ({ value: g.game, label: g.game + "  " + g.count })))
                current: panel.game
                onPicked: function (v) { panel.game = v }
            }
            // The last thing that went wrong, or the last thing done.
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                elide: Text.ElideRight
                variant: "caption"
                color: Clips.lastError !== "" || !Clips.actionResult.ok ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                text: Clips.blocker() !== "" ? Clips.blocker()
                    : Clips.lastError !== "" ? Clips.lastError
                    : Clips.actionResult.text
            }

            // ── The clips, by day ─────────────────────────────────────────────
            Item {
                id: libArea
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    spacing: Tokens.spacingLg
                    cacheBuffer: 600
                    boundsBehavior: Flickable.StopAtBounds
                    // Room for the selection bar, so it never covers the last row.
                    bottomMargin: panel.hasSelection ? selBar.height + Tokens.spacingXl : 0
                    Behavior on bottomMargin { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    rightMargin: Tokens.spacingLg

                    readonly property int gap: Tokens.spacingMd
                    readonly property real usable: list.width - list.rightMargin
                    readonly property int cols: Math.max(2, Math.floor((list.usable + list.gap) / (Tokens.sideCardUnit * 5.2 + list.gap)))
                    readonly property real tileW: Math.floor((list.usable - list.gap * (list.cols - 1)) / list.cols)

                    // Keyed by day: a refresh keeps each group's tiles and their images.
                    model: ScriptModel { values: panel.groups; objectProp: "key" }

                    delegate: Column {
                        id: group
                        required property var modelData
                        width: list.usable
                        spacing: Tokens.spacingSm

                        // The day, and how much of it there is.
                        RowLayout {
                            width: parent.width
                            visible: group.modelData.label !== ""
                            spacing: Tokens.spacingSm
                            StyledText {
                                text: group.modelData.label
                                variant: "title"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignBottom
                                text: group.modelData.clips.length + (group.modelData.clips.length === 1 ? " clip" : " clips")
                                variant: "caption"
                                emphasis: "dim"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Grid {
                            columns: list.cols
                            spacing: list.gap

                            Repeater {
                                model: group.modelData.clips

                                delegate: Item {
                                    id: tile
                                    required property var modelData
                                    required property int index
                                    readonly property var pretty: ClipsJs.prettyName(tile.modelData.name, tile.modelData.ext, tile.modelData.mtime)
                                    readonly property bool selected: panel.isSelected(tile.modelData.path)
                                    readonly property bool fav: Clips.favourites.indexOf(tile.modelData.path) >= 0
                                    // The pointer is on the tile or on anything riding it (a chip).
                                    readonly property bool hot: tileHover.hovered
                                    readonly property bool ready: tile.modelData.ok

                                    width: list.tileW
                                    height: thumb.height + info.height + Tokens.spacingSm

                                    // Arrives on a spring, a beat after the one before (the first screenful only).
                                    PopIn { id: pop; active: true; index: tile.index; cap: 8; step: Motion.stagger }
                                    opacity: pop.opacity
                                    scale:   pop.scale

                                    HoverHandler { id: tileHover }

                                    ClipThumb {
                                        id: thumb
                                        width: tile.width
                                        height: Math.round(width * 9 / 16)
                                        radius: Tokens.radiusCard
                                        entry: tile.modelData
                                        // Lifts toward the pointer. (On the frame, not the tile: the tile's own scale is the
                                        // entrance spring, and an eased value on top of one would chase it.)
                                        scale: tile.hot ? 1.02 : 1.0
                                        Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                                        // The chosen ones: a ring in the accent.
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: thumb.radius
                                            color: tile.selected ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.18) : "transparent"
                                            border.width: tile.selected ? Tokens.borderChrome + 1 : 0
                                            border.color: Colors.of(QsWindow.window).primary
                                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                                        }
                                        // A scrim for what rides the foot of the frame.
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            height: parent.height * 0.5
                                            opacity: tile.hot ? 1 : 0
                                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                            gradient: Gradient {
                                                GradientStop { position: 0.0; color: "transparent" }
                                                GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.7) }
                                            }
                                        }
                                        // A tag where a clip is not the original: Trimmed, Edited, GIF.
                                        Rectangle {
                                            visible: tile.pretty.tag !== "" && !tile.hot
                                            anchors.left: parent.left
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Tokens.spacingSm
                                            width: tagText.implicitWidth + Tokens.spacingMd
                                            height: tagText.implicitHeight + Tokens.spacingXs
                                            radius: height / 2
                                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.6)
                                            StyledText {
                                                id: tagText
                                                anchors.centerIn: parent
                                                text: tile.pretty.tag
                                                variant: "micro"
                                                color: Colors.of(QsWindow.window).fg
                                            }
                                        }
                                        // A star on one you kept (the hover chips take over when pointed at).
                                        MaterialIcon {
                                            visible: tile.fav && !tile.hot
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: Tokens.spacingSm
                                            name: "star"
                                            fill: 1
                                            color: Colors.of(QsWindow.window).primary
                                            variant: "label"
                                        }
                                        // Pointed at: a play disc — one click plays it, here in the shell.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: Tokens.iconXl * 2.2
                                            height: width
                                            radius: width / 2
                                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.92)
                                            opacity: tile.hot && tile.ready && !panel.hasSelection ? 1 : 0
                                            scale: opacity > 0.5 ? 1 : 0.8
                                            visible: opacity > 0.01
                                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                            Behavior on scale { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                                            MaterialIcon {
                                                anchors.centerIn: parent
                                                name: "play_arrow"
                                                fill: 1
                                                font.pixelSize: Tokens.iconXl
                                                color: Colors.of(QsWindow.window).fgOnPrimary
                                            }
                                        }
                                    }

                                    // Click: play it — or, with something selected (or Ctrl / Shift), choose it.
                                    MouseArea {
                                        anchors.fill: thumb
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: function (mouse) {
                                            if (mouse.modifiers & Qt.ShiftModifier && panel.hasSelection) panel.rangeTo(tile.modelData.path)
                                            else if ((mouse.modifiers & Qt.ControlModifier) || panel.hasSelection) panel.toggleMulti(tile.modelData.path)
                                            else if (tile.ready) panel.openPlayer(tile.modelData)
                                        }
                                    }

                                    // The tick: choose it without a modifier key. Always there once anything is chosen.
                                    Rectangle {
                                        x: Tokens.spacingSm
                                        y: Tokens.spacingSm
                                        width: Tokens.iconLg + Tokens.spacingXs
                                        height: width
                                        radius: width / 2
                                        opacity: tile.hot || tile.selected || panel.hasSelection ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                        color: tile.selected ? Colors.of(QsWindow.window).primary
                                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.55)
                                        border.width: Tokens.borderWidth * 2
                                        border.color: tile.selected ? Colors.of(QsWindow.window).primary
                                                                    : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.7)
                                        Behavior on color { ColorAnimation { duration: Motion.respond } }
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            name: "check"
                                            visible: tile.selected
                                            variant: "caption"
                                            color: Colors.of(QsWindow.window).fgOnPrimary
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -Tokens.spacingXs
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: panel.toggleMulti(tile.modelData.path)
                                        }
                                    }

                                    // What you most often do to one, on the frame while you are on it.
                                    ChipTray {
                                        x: Tokens.spacingSm
                                        y: thumb.height - height - Tokens.spacingSm
                                        opacity: tile.hot && !panel.hasSelection ? 1 : 0
                                        visible: opacity > 0.01
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                        ChipButton {
                                            symbol: "star"
                                            on: tile.fav
                                            tint: Colors.of(QsWindow.window).primary
                                            onActivated: Clips.toggleFavourite(tile.modelData.path)
                                        }
                                        ChipButton {
                                            symbol: "content_cut"
                                            tint: Colors.of(QsWindow.window).primary
                                            enabled: tile.ready
                                            onActivated: panel.openEditor(tile.modelData)
                                        }
                                        ChipButton {
                                            symbol: "content_copy"
                                            tint: Colors.of(QsWindow.window).primary
                                            onActivated: Clips.copyClip(tile.modelData.path)
                                        }
                                    }

                                    // The handle: drag a clip OUT — into a chat, a file manager, a browser upload — as a
                                    // file. Only from here, so a drag on a tile still scrolls the list. (Qt's own drag,
                                    // text/uri-list; whether another app takes it is up to that app.)
                                    Rectangle {
                                        id: handle
                                        x: thumb.width - width - Tokens.spacingSm
                                        y: Tokens.spacingSm
                                        width: Tokens.iconLg + Tokens.spacingXs
                                        height: width
                                        radius: width / 2
                                        visible: opacity > 0.01 && tile.ready
                                        opacity: tile.hot || dragOut.active ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.55)
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            name: "drag_indicator"
                                            variant: "caption"
                                            color: Colors.of(QsWindow.window).fg
                                        }
                                        HoverHandler { cursorShape: dragOut.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
                                        DragHandler { id: dragOut; target: null }
                                        Drag.active: dragOut.active
                                        Drag.dragType: Drag.Automatic
                                        Drag.supportedActions: Qt.CopyAction
                                        Drag.mimeData: ({ "text/uri-list": Clips.uriList(panel.dragPaths(tile.modelData.path)) })
                                        Drag.imageSource: tile.modelData.thumb ? "file://" + tile.modelData.thumb : ""
                                    }

                                    // What it is, in words: its title, and when it was and how big.
                                    Column {
                                        id: info
                                        anchors.top: thumb.bottom
                                        anchors.topMargin: Tokens.spacingSm
                                        width: tile.width
                                        spacing: 0
                                        StyledText {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            text: tile.pretty.title
                                            variant: "label"
                                            font.weight: Font.DemiBold
                                        }
                                        StyledText {
                                            width: parent.width
                                            elide: Text.ElideRight
                                            variant: "caption"
                                            emphasis: "dim"
                                            text: !tile.ready ? "Still being written…"
                                                : tile.pretty.time + "  ·  " + NetStats.bytes(tile.modelData.size)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Scrollbar { flickable: list }

                // ── Nothing (yet, or matching) ────────────────────────────────
                Column {
                    anchors.centerIn: parent
                    width: parent.width * 0.5
                    spacing: Tokens.spacingSm
                    visible: panel.shown.length === 0 && !Clips.indexing
                    MaterialIcon {
                        anchors.horizontalCenter: parent.horizontalCenter
                        name: panel.query !== "" ? "search" : "movie"
                        font.pixelSize: Tokens.fontNumeralMd
                        color: Colors.of(QsWindow.window).fgFaint
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        variant: "title"
                        text: panel.query !== "" ? "Nothing matches “" + panel.query + "”"
                            : panel.filter === "today" ? "Nothing from today yet"
                            : panel.filter === "favourites" ? "Nothing starred yet"
                            : panel.filter !== "all" || panel.game !== "" ? "Nothing here yet"
                            : "No clips yet"
                    }
                    StyledText {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        emphasis: "dim"
                        text: panel.query !== "" ? "Try fewer letters, or clear the search."
                            : panel.filter === "favourites" ? "Point at a clip and tap its star to keep it here."
                            : panel.filter === "all" && panel.game === ""
                              ? "Turn clipping on from the sidebar button or the header, then press Alt+F10 whenever "
                                + "something happens — it keeps the last " + ClipsJs.span(Clips.bufferSeconds) + "."
                            : "Switch the filter to All to see everything."
                    }
                    ChipTray {
                        anchors.horizontalCenter: parent.horizontalCenter
                        groupShown: panel.query !== "" || panel.filter !== "all" || panel.game !== ""
                        ChipButton {
                            symbol: "close"
                            label: Translation.tr("Clear filters")
                            on: true
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: { search.clear(); panel.query = ""; panel._filterTouched = true; panel.filter = "all"; panel.game = "" }
                        }
                    }
                }

                // ── The selection bar: floats over the foot of the grid ───────
                SurfaceShadow { surface: selBar; elevation: Tokens.elevationPopup }
                Rectangle {
                    id: selBar
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Rises from below the foot; `y`, not an anchor margin, because it is animated.
                    y: panel.hasSelection ? libArea.height - height - Tokens.spacingMd : libArea.height + Tokens.spacingXl
                    Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                    opacity: panel.hasSelection ? 1 : 0
                    visible: opacity > 0.01
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                    width: Math.min(libArea.width - Tokens.spacingXl, barRow.implicitWidth + Tokens.spacingLg * 2)
                    height: Tokens.iconXl * 2 + Tokens.spacingSm
                    radius: height / 2
                    color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup)
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).outline

                    // What is chosen, held while the bar slides away (it must not blank on the way out).
                    property int count: 0
                    property var one: null
                    Connections {
                        target: panel
                        function onMultiChanged() {
                            if (panel.multi.length === 0) return
                            selBar.count = panel.multi.length
                            selBar.one = panel.multi.length === 1 ? (Clips.clips.find(c => c.path === panel.multi[0]) ?? null) : null
                        }
                    }
                    readonly property bool allStarred: panel.multi.length > 0 && panel.multi.every(p => Clips.isFavourite(p))

                    RowLayout {
                        id: barRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingMd

                        MaterialIcon {
                            name: "check_circle"
                            fill: 1
                            color: Colors.of(QsWindow.window).primary
                        }
                        StyledText {
                            Layout.maximumWidth: Tokens.sideCardUnit * 4
                            elide: Text.ElideRight
                            variant: "label"
                            font.weight: Font.DemiBold
                            text: selBar.count > 1 ? selBar.count + " selected"
                                : selBar.one ? ClipsJs.prettyName(selBar.one.name, selBar.one.ext, selBar.one.mtime).title : "1 selected"
                        }

                        // One clip: watch it, cut it.
                        ChipTray {
                            groupShown: selBar.count === 1
                            ChipButton {
                                symbol: "play_arrow"
                                label: Translation.tr("Play")
                                on: true
                                tint: Colors.of(QsWindow.window).primary
                                enabled: selBar.one !== null && selBar.one.ok
                                onActivated: panel.openPlayer(selBar.one)
                            }
                            ChipButton {
                                symbol: "content_cut"
                                label: Translation.tr("Edit")
                                tint: Colors.of(QsWindow.window).primary
                                enabled: selBar.one !== null && selBar.one.ok
                                onActivated: panel.openEditor(selBar.one)
                            }
                        }
                        // The file's actions: for one or for all of them.
                        ChipTray {
                            ChipButton {
                                symbol: "star"
                                label: selBar.count > 1 ? (selBar.allStarred ? "Unstar" : "Star all") : ""
                                on: selBar.allStarred
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: Clips.setFavourites(panel.multi, !selBar.allStarred)
                            }
                            ChipButton {
                                symbol: "content_copy"
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: Clips.copyClips(panel.multi)
                            }
                            ChipButton {
                                visible: selBar.count === 1
                                symbol: "send"
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: Clips.sendToDiscord(panel.multi[0])
                            }
                            ChipButton {
                                visible: selBar.count === 1
                                symbol: "folder_open"
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: Clips.showInFolder(panel.multi[0])
                            }
                        }
                        // Several: shrunk one after another to a size a chat accepts.
                        ChipTray {
                            groupShown: selBar.count > 1
                            ChipButton {
                                symbol: "bolt"
                                label: Clips.exportBatch ? "Shrinking " + Math.min(Clips.exportDone + 1, Clips.exportTotal) + "/" + Clips.exportTotal : "Shrink to"
                                tint: Colors.of(QsWindow.window).primary
                                enabled: false
                            }
                            Repeater {
                                model: [10, 25, 50]
                                delegate: ChipButton {
                                    required property int modelData
                                    label: modelData + " MB"
                                    tint: Colors.of(QsWindow.window).primary
                                    enabled: !Clips.exporting && !Clips.exportBatch
                                    onActivated: Clips.exportMany(panel.multiEntries,
                                        { precise: true, sizeMB: modelData, audio: "mix", format: "mp4" })
                                }
                            }
                            ChipButton {
                                visible: Clips.exportBatch
                                symbol: "close"
                                tint: Colors.of(QsWindow.window).danger
                                onActivated: Clips.cancelExport()
                            }
                        }
                        // Two clicks, and to the trash either way.
                        ChipTray {
                            ChipButton {
                                symbol: "delete"
                                label: selLatch.armed ? "Delete " + (selBar.count > 1 ? selBar.count : "it") + "?" : ""
                                on: selLatch.armed
                                tint: Colors.of(QsWindow.window).danger
                                onActivated: selLatch.trigger()
                            }
                        }

                        // The way out: big, labelled, and the last thing in the bar.
                        Rectangle {
                            Layout.preferredWidth: clearRow.implicitWidth + Tokens.spacingXl * 2
                            Layout.preferredHeight: Tokens.iconXl * 2 - Tokens.spacingSm * 2
                            radius: height / 2
                            color: clearBarMouse.containsMouse ? Colors.of(QsWindow.window).primary
                                                               : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.85)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            scale: clearBarMouse.pressed ? 0.97 : 1.0
                            Behavior on scale { NumberAnimation { duration: Motion.respond; easing.type: Motion.respondCurve } }
                            Row {
                                id: clearRow
                                anchors.centerIn: parent
                                spacing: Tokens.spacingSm
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "close"
                                    color: Colors.of(QsWindow.window).fgOnPrimary
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Clear")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    color: Colors.of(QsWindow.window).fgOnPrimary
                                }
                            }
                            MouseArea {
                                id: clearBarMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.clearSelection()
                            }
                        }
                    }
                }
            }
        }

        // ══ Player / editor view ══════════════════════════════════════════════
        // Built only while open: a player, a filmstrip, decoders — none of it while
        // you're browsing.
        Loader {
            id: editorLoader
            visible: panel.view === "editor"
            active: panel.view === "editor" && panel.editing !== null
            Layout.fillWidth: true
            Layout.fillHeight: true
            focus: panel.view === "editor"
            sourceComponent: ClipEditor {
                entry: panel.editing
                viewOnly: panel.viewOnly
                onBack: panel.closeEditor()
                onEditRequested: panel.viewOnly = false
            }
        }
    }
}
