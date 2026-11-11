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
// ── The look: the media / colours panels' ─────────────────────────────────────
// ChipTray headers and toolbars, a SegmentSwitch for the filter, flat `section` cards (no outline),
// tiles and cards arriving on a spring (PopIn), a CookieButton for play. The clear controls are
// big on purpose: a disc as tall as the search field clears it, and a selection shows a banner with a
// full-size "Clear selection" button.
//
// ── What else it does ─────────────────────────────────────────────────────────
//   · Today — the library opens on it when there is something from today, else on All;
//   · a game filter (clips are named after the window: clips.js gameOf), once there are two games;
//   · multi-select: Ctrl-click or the tick on a tile, Shift-click for a range, Ctrl+A for all — then a
//     bulk pane: star, copy as files, shrink to a Discord size (one after another), delete (asks);
//   · drag a clip OUT (the handle on its thumbnail) into a chat or a file manager, as a file;
//   · `Clips.editRequest`: the peek / panel's "edit" opens this on a clip, in the editor;
//   · search also matches the song and the people a clip was stamped with (Clips.contexts) and your tags;
//   · narrow by "With music" / "In a call" (the stamp) and by one of your tags (`Clips.tags`, put on a
//     selection from the bar: a field to add, a chip to take one off);
//   · rest on a clip and the pointer's x scrubs through it (the editor's cached filmstrip);
//   · a heading per day says how many clips, how many bytes and how much footage it holds, and a chip in
//     the header appears when the limits in Settings › Clips name something to trash.
//
// ── What it keeps cheap ───────────────────────────────────────────────────────
// The list is a virtualised ListView of HEADINGS and ROWS (clips.js layoutRows), not a Grid per day, so a
// day with a hundred clips builds a screenful. What rides a frame on hover (tick, chips, drag handle, play
// disc, scrub) lives behind a Loader that is active only while the pointer is on the tile, something is
// selected, or just after it leaves — a tile at rest is a picture and a caption.
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
    // Narrowing by what a clip carries: "" | "music" | "call" (its stamp), and one of your tags.
    property string stamp: ""
    property string tag: ""
    // The library opens on Today when anything is from today — once, and never over a pick of yours.
    property bool _filterTouched: false
    property bool _filterDefaulted: false
    function _defaultFilter() {
        if (panel._filterTouched || panel._filterDefaulted || Clips.clips.length === 0) return
        panel._filterDefaulted = true
        const now = Date.now()
        panel.filter = Clips.clips.some(c => ClipsJs.isToday(c.mtime, now)) ? "today" : "all"
    }
    Component.onCompleted: { panel._defaultFilter(); panel._consumeRequests(); Clips.refreshHealth() }
    readonly property var games: ClipsJs.gamesOf(Clips.clips)
    readonly property var shown: ClipsJs.libraryView(Clips.clips, panel.query, panel.filter,
                                                     Clips.favourites, panel.sort, panel.game, Date.now(), Clips.contexts,
                                                     { stamp: panel.stamp, tag: panel.tag, tags: Clips.tags })
    // What there is to narrow by: stamped clips, and the tags in use (most used first).
    readonly property bool anyMusic: Object.keys(Clips.contexts).some(k => Clips.contexts[k].title)
    readonly property bool anyCall: Object.keys(Clips.contexts).some(k => (Clips.contexts[k].with ?? []).length > 0)
    readonly property var tagList: ClipsJs.tagCounts(Clips.tags, null).slice(0, 8)
    readonly property bool narrowed: panel.query !== "" || panel.filter !== "all" || panel.game !== "" || panel.stamp !== "" || panel.tag !== ""
    function clearFilters() {
        search.clear(); panel.query = ""; panel._filterTouched = true
        panel.filter = "all"; panel.game = ""; panel.stamp = ""; panel.tag = ""
    }

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
    // The same, cut into headings and rows so the list builds only the rows on screen.
    readonly property var rows: ClipsJs.layoutRows(panel.groups, list.cols)
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
    onMultiChanged: { selLatch.disarm(); panel.tagOpen = false }
    ArmLatch {
        id: pruneLatch
        onConfirmed: Clips.prune()
    }
    // The tag field in the selection bar.
    property bool tagOpen: false

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
                       + "  ·  " + NetStats.bytes(panel.totalBytes)
                       + (Clips.health.diskFreeMiB > 0 ? " (" + ClipsJs.bytesText(Clips.health.diskFreeMiB * 1048576) + " free)" : "")
                       + "  ·  " + panel.tilde(Clips.saveDir)

            BusyDot {
                Layout.alignment: Qt.AlignVCenter
                running: Clips.indexing || Clips.acting || Clips.exporting
            }

            // The limits in Settings › Clips name something to trash: two taps, to the trash.
            ChipTray {
                groupShown: panel.view === "library" && Clips.prunePreview.count > 0
                ChipButton {
                    symbol: "cleaning_services"
                    label: pruneLatch.armed ? Translation.tr("Trash") + " " + Clips.prunePreview.count + "?"
                                            : Translation.tr("Free") + " " + ClipsJs.bytesText(Clips.prunePreview.bytes)
                    on: pruneLatch.armed
                    tint: Colors.of(QsWindow.window).warning
                    onActivated: pruneLatch.trigger()
                }
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
            // Narrow it: the games (a clip is named after the window it was cut in), the clips that know what
            // was playing or who was there, and your tags. One row each, only when there is something to pick.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: panel.games.length >= 2 || panel.anyMusic || panel.anyCall
                spacing: Tokens.spacingMd
                ChipRow {
                    Layout.fillWidth: true
                    visible: panel.games.length >= 2
                    accent: Colors.of(QsWindow.window).primary
                    model: [{ value: "", label: "All games" }].concat(panel.games.slice(0, 7).map(g => ({ value: g.game, label: g.game + "  " + g.count })))
                    current: panel.game
                    onPicked: function (v) { panel.game = v }
                }
                Item { Layout.fillWidth: true; visible: panel.games.length < 2 }
                ChipTray {
                    groupShown: panel.anyMusic || panel.anyCall
                    ChipButton {
                        visible: panel.anyMusic
                        symbol: "music_note"
                        label: Translation.tr("With music")
                        on: panel.stamp === "music"
                        tint: Colors.of(QsWindow.window).primary
                        onActivated: panel.stamp = panel.stamp === "music" ? "" : "music"
                    }
                    ChipButton {
                        visible: panel.anyCall
                        symbol: "group"
                        label: Translation.tr("In a call")
                        on: panel.stamp === "call"
                        tint: Colors.of(QsWindow.window).primary
                        onActivated: panel.stamp = panel.stamp === "call" ? "" : "call"
                    }
                }
            }
            ChipRow {
                Layout.fillWidth: true
                Layout.fillHeight: false
                visible: panel.tagList.length > 0
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "", label: "All tags" }].concat(panel.tagList.map(t => ({ value: t.tag, label: "#" + t.tag + "  " + t.count })))
                current: panel.tag
                onPicked: function (v) { panel.tag = v }
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
                    spacing: Tokens.spacingMd
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

                    // Headings and rows (clips.js layoutRows), keyed: only the rows near the screen exist, and a
                    // refresh keeps the rows (and their pictures) it can.
                    model: ScriptModel { values: panel.rows; objectProp: "key" }

                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        readonly property bool isHead: rowItem.modelData.kind === "head"
                        width: list.usable
                        height: rowItem.isHead ? headRow.implicitHeight + Tokens.spacingMd : tilesRow.implicitHeight

                        // The day, and how much of it there is.
                        RowLayout {
                            id: headRow
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            visible: rowItem.isHead
                            spacing: Tokens.spacingSm
                            StyledText {
                                text: rowItem.modelData.label ?? ""
                                variant: "title"
                                font.weight: Font.DemiBold
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignBottom
                                text: rowItem.isHead ? ClipsJs.groupLine(rowItem.modelData.count, rowItem.modelData.bytes, rowItem.modelData.secs) : ""
                                variant: "caption"
                                emphasis: "dim"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        Row {
                            id: tilesRow
                            visible: !rowItem.isHead
                            spacing: list.gap

                            Repeater {
                                model: rowItem.isHead ? [] : rowItem.modelData.clips

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
                                    readonly property string context: ClipsJs.contextLine(Clips.contextOf(tile.modelData.path))
                                    readonly property var labels: Clips.tagsOf(tile.modelData.path)

                                    // What rides the frame (the tick, the chips, the handle, the scrub) is built only
                                    // while the pointer is on the tile, or something is selected, and for a beat after
                                    // it leaves so it can fade: a library of a hundred clips would otherwise carry
                                    // hundreds of buttons, each with its own springs and handlers, doing nothing.
                                    property bool _warm: false
                                    readonly property bool chrome: tile.hot || tile.selected || panel.hasSelection || tile._warm
                                    onHotChanged: { if (tile.hot) { tile._warm = true; cool.stop() } else cool.restart() }
                                    Timer { id: cool; interval: Motion.standard + Motion.respond; onTriggered: tile._warm = false }

                                    width: list.tileW
                                    height: thumb.height + info.height + Tokens.spacingSm

                                    // Arrives on a spring, a beat after the one before it in its row.
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
                                            visible: tile.selected
                                            anchors.fill: parent
                                            radius: thumb.radius
                                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.18)
                                            border.width: Tokens.borderChrome + 1
                                            border.color: Colors.of(QsWindow.window).primary
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

                                    // The pointer's tile: scrub, scrim, play disc, tick, chips, handle.
                                    Loader {
                                        anchors.fill: thumb
                                        active: tile.chrome
                                        sourceComponent: Item {
                                            id: chrome
                                            // Scrubbing: rest on a clip a moment and the pointer's x walks through it, a frame
                                            // from the filmstrip (the editor's, cached on disk — one ffmpeg run the first time).
                                            readonly property int frameCount: 10
                                            readonly property var frames: Clips.strip.path === tile.modelData.path ? Clips.strip.frames : []
                                            property bool dwelled: false
                                            readonly property bool scrubbing: chrome.dwelled && tile.hot && tile.ready && !panel.hasSelection
                                                                              && chrome.frames.length > 0
                                            readonly property int frameAt: Math.max(0, Math.min(chrome.frameCount - 1,
                                                Math.floor(scrubHover.point.position.x / Math.max(1, chrome.width) * chrome.frameCount)))
                                            HoverHandler { id: scrubHover }
                                            Timer {
                                                interval: 450
                                                running: tile.hot && tile.ready && !panel.hasSelection && !chrome.dwelled
                                                onTriggered: { chrome.dwelled = true; Clips.loadStrip(tile.modelData.path, chrome.frameCount) }
                                            }
                                            Connections {
                                                target: tile
                                                function onHotChanged() { if (!tile.hot) chrome.dwelled = false }
                                            }

                                            Image {
                                                anchors.fill: parent
                                                visible: chrome.scrubbing && (chrome.frames[chrome.frameAt] ?? "") !== ""
                                                source: chrome.scrubbing && (chrome.frames[chrome.frameAt] ?? "") !== "" ? "file://" + chrome.frames[chrome.frameAt] : ""
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: true
                                                asynchronous: true
                                            }
                                            // Where in the clip the pointer is.
                                            Rectangle {
                                                visible: chrome.scrubbing
                                                anchors.left: parent.left
                                                anchors.bottom: parent.bottom
                                                height: Tokens.spacingXs
                                                width: parent.width * (chrome.frameAt + 0.5) / chrome.frameCount
                                                color: Colors.of(QsWindow.window).primary
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
                                            // Pointed at: a play disc — one click plays it, here in the shell.
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: Tokens.iconXl * 2.2
                                                height: width
                                                radius: width / 2
                                                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, 0.92)
                                                opacity: tile.hot && tile.ready && !panel.hasSelection && !chrome.scrubbing ? 1 : 0
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

                                            // The tick: choose it without a modifier key. Always there once anything is chosen.
                                            Rectangle {
                                                x: Tokens.spacingSm
                                                y: Tokens.spacingSm
                                                width: Tokens.iconLg + Tokens.spacingXs
                                                height: width
                                                radius: width / 2
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
                                                y: chrome.height - height - Tokens.spacingSm
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
                                                x: chrome.width - width - Tokens.spacingSm
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
                                        }
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
                                        // The song that was playing and who was in the call, when stamped.
                                        StyledText {
                                            width: parent.width
                                            visible: tile.context !== ""
                                            elide: Text.ElideRight
                                            variant: "micro"
                                            emphasis: "dim"
                                            text: tile.context
                                        }
                                        // Your tags.
                                        StyledText {
                                            width: parent.width
                                            visible: tile.labels.length > 0
                                            elide: Text.ElideRight
                                            variant: "micro"
                                            color: Colors.of(QsWindow.window).primary
                                            text: tile.labels.map(t => "#" + t).join("  ")
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
                            : panel.narrowed ? "Nothing here yet"
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
                        groupShown: panel.narrowed
                        ChipButton {
                            symbol: "close"
                            label: Translation.tr("Clear filters")
                            on: true
                            tint: Colors.of(QsWindow.window).primary
                            onActivated: panel.clearFilters()
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
                        // Tags: the ones these carry (a tap takes it off all of them), and a field to put one on all.
                        ChipTray {
                            groupShown: !panel.tagOpen
                            Repeater {
                                model: panel.hasSelection ? ClipsJs.tagCounts(Clips.tags, panel.multi).slice(0, 2) : []
                                delegate: ChipButton {
                                    required property var modelData
                                    symbol: "close"
                                    label: "#" + modelData.tag
                                    on: modelData.count === selBar.count
                                    tint: Colors.of(QsWindow.window).primary
                                    onActivated: Clips.removeTag(panel.multi, modelData.tag)
                                }
                            }
                            ChipButton {
                                symbol: "sell"
                                tint: Colors.of(QsWindow.window).primary
                                onActivated: panel.tagOpen = true
                            }
                        }
                        InputField {
                            id: tagInput
                            visible: panel.tagOpen
                            Layout.preferredWidth: Tokens.sideCardUnit * 3
                            icon: "sell"
                            cornerRadius: implicitHeight / 2
                            placeholder: Translation.tr("Add a tag")
                            onVisibleChanged: if (tagInput.visible) tagInput.forceFocus()
                            onCommitted: function (v) {
                                if (v.trim() !== "") Clips.addTag(panel.multi, v)
                                tagInput.clear()
                                panel.tagOpen = false
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
