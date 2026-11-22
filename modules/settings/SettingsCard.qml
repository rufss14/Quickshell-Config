pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── SettingsCard ──────────────────────────────────────────────────────────────
// The settings surface itself: rail on the left, one page at a time on the right.
// It is a plain card. Two hosts: SettingsWindow (an xdg-toplevel, the default) and
// SettingsPanelHost (docked into the frame inside Bar's window, Config.settingsPanel).
//
// A toplevel has no compositor-drawn close affordance here, so `closable` draws a
// cross in the card's top-right corner — that and Escape are the ways out.
//
// ── Sections and pages: an accordion, no tabs ─────────────────────────────────
// The rail lists the SECTIONS (SettingsIndex.navPages). The current one unfolds in
// place to list its pages, the rest stay folded, so every page is one visible row and
// nothing hides behind a tab strip. A page is one file in pages/, loaded on demand,
// plus an optional anchor. The state is a page KEY (`file` or `file#anchor`), never
// an index: the catalogue renumbers when hardware appears, so the section is derived.
//
// ── Search lives in the rail ──────────────────────────────────────────────────
// Not a landing page, which is reachable only by going back to it: the field is in
// the rail, on every page. Typing swaps the page area for
// SettingsSearchResults, and clearing it (Escape, or picking a result) puts the page
// back. The page's Loader stays alive underneath, so nothing it held is lost.
//
// ── A SLAB, not a floating rail ───────────────────────────────────────────────
// The rail is flush: full height, no outer margin, no gap to the page, square where
// the two meet and following the card's curve where it doesn't. An inset rail reads
// as two panels that happen to be adjacent; flush reads as one window with a
// navigation column. The seam stays legible without a divider because of the
// elevation ladder: the card sits at Card and the slab one step up at Nested.
//
// The SELECTED page is one `primaryContainer` pill that travels between the rows on
// springs, and its section's badge blooms into a shape of its own (the island rail's
// idiom, docs/island-style.md §3). What stops the pill reading as a button is SHAPE: a
// full-width row in the slab, where a control is a hug-width box inside a card.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    elevation: Tokens.elevationCard

    // ── Welded into the frame by the blob (SettingsPanelHost) ────────────────
    // The blob draws the fill and one continuous outline around card + strips, so
    // the card drops its own border and shadow and takes the frame's fill.
    property bool welded: false
    borderWidth: root.welded ? 0 : Tokens.borderWidth
    castsShadow: !root.welded
    color: root.welded
        ? Colors.of(QsWindow.window).frameFill
        : Colors.of(QsWindow.window).fade(Colors.of(QsWindow.window).surfaceFor(root.elevation), root.fillOpacity)

    // Fallbacks only — both hosts give the card a size.
    implicitWidth:  980
    implicitHeight: 640

    property bool closable: false
    signal closeRequested()

    readonly property var searchHints: [
        { key: "theme" }, { key: "wifi" }, { key: "dock" }, { key: "font" },
        { key: "clips" }, { key: "audio" }, { key: "cursor" }, { key: "lock" },
        { key: "update" }, { key: "bluetooth" }
    ]

    // The corner cluster: the pin star, and the close cross beside it when `closable`,
    // as one ChipTray — the panels' header-action tray. The page area keeps clear of it
    // (pageArea.sideRight). The star stays while searching (dimmed) so the room it
    // reserves, and with it the results' width, never changes.
    readonly property int chromeButton: Tokens.iconXl + Tokens.spacingXs
    readonly property int chromeW: root.chromeButton * (root.closable ? 2 : 1)
        + (root.closable ? Tokens.spacingXs : 0) + (Tokens.spacingXs + 1) * 2

    // ── The KEY is the state; the page record is derived ──────────────────────
    // A derived record, never an assigned index: a hardware handler assigning an
    // index before Config loaded once destroyed the restore binding, and a renumber (a
    // Bluetooth dongle appearing) re-resolves a key for free.
    //
    // Not in UiState: that holds session state and is deliberately not persisted,
    // and "the page I was last on" should survive a restart.
    property string currentKey: Config.settingsPage

    // Every available page, flat in rail order, and the rail's sections. Both live in
    // SettingsIndex because search needs them too, and search is not loaded by this card.
    readonly property var pages:    SettingsIndex.pages
    readonly property var navPages: SettingsIndex.navPages

    // The page on show. A remembered key that resolves to nothing (hardware went
    // away, a page that is gone with no alias) lands on the first page, the same
    // fallback the Loader uses.
    readonly property var currentEntry: SettingsIndex.entryFor(root.currentKey) ?? root.pages[0]
    readonly property var currentNav:
        SettingsIndex.navPageFor(root.currentEntry?.key ?? "") ?? root.navPages[0]

    onCurrentKeyChanged: {
        Config.settingsPage = root.currentKey
        root._rememberView()
    }
    function _rememberView() {
        const e = SettingsIndex.entryFor(root.currentKey)
        const nav = SettingsIndex.navPageFor(root.currentKey)
        if (e && nav) root._lastView[nav.label] = e.key
    }
    onCurrentEntryChanged: {
        root._syncAnchor()
        Qt.callLater(rail.ensureCurrent)
    }

    // A file holding several rail rows reads the anchor to show the right part.
    function _syncAnchor() { UiState.settingsAnchor = root.currentEntry?.anchor ?? "" }

    // Which page each section was last on, for this card's lifetime — returning to
    // Devices goes back to Bluetooth rather than resetting to Sound. A plain object
    // on purpose: nothing binds to it, it is only read on a section click.
    property var _lastView: ({})

    function showPage(nav) {
        root.clearSearch()
        // A move of the hand's own: nothing left over from a deep link to reveal.
        UiState.settingsTarget = null
        const last = root._lastView[nav.label]
        const stillThere = nav.views.some(function (v) { return v.key === last })
        root.currentKey = stillThere ? last : nav.views[0].key
    }

    function openPage(key) {
        root.clearSearch()
        root.goTo(key)
    }

    // ── Search ────────────────────────────────────────────────────────────────
    property string query: ""
    readonly property bool searching: root.query.trim() !== ""

    // Which result the arrows are on, or -1 for "none yet, Enter takes the best".
    // Reset on every keystroke: the ranking reorders as you type, so an index into
    // the old order points at something you never looked at.
    property int resultIndex: -1
    onQueryChanged: root.resultIndex = -1

    readonly property var pinnedViews: SettingsIndex.pinned

    // ── Keyboard movement ─────────────────────────────────────────────────────
    // Wrapping on purpose: the rail is a ring, and stopping dead at the ends costs a
    // keypress every time you overshoot.
    function stepResult(d) {
        const item = resultsLoader.item
        if (!item) return
        const n = item.results.length
        if (n === 0) return
        root.resultIndex = root.resultIndex < 0 ? (d > 0 ? 0 : n - 1)
                                                : (root.resultIndex + d + n) % n
    }

    // ↑↓: the previous or next page in rail order, across sections; the accordion
    // follows because the section is derived from the page.
    function stepPage(d) {
        const list = root.pages
        if (!list || list.length === 0) return
        const key = root.currentEntry ? root.currentEntry.key : ""
        const i = Math.max(0, list.findIndex(p => p.key === key))
        UiState.settingsTarget = null
        root.currentKey = list[(i + d + list.length) % list.length].key
    }

    // ←→: the previous or next section, on the page it was last left on.
    function stepSection(d) {
        const list = root.navPages
        if (!list || list.length === 0) return
        const label = root.currentNav ? root.currentNav.label : ""
        const i = Math.max(0, list.findIndex(p => p.label === label))
        root.showPage(list[(i + d + list.length) % list.length])
    }

    // True while the keyboard is inside the page area: a page's field or control owns
    // its keys there. A single-line TextInput does not consume Up/Down, so without this
    // typing in a page field and pressing ↓ switched pages.
    function _focusInPage() {
        for (let it = root.Window.activeFocusItem; it; it = it.parent)
            if (it === pageArea) return true
        return false
    }

    // ── The keyboard map ──────────────────────────────────────────────────────
    // Ctrl+F from anywhere, then ↑↓ through results, Enter to open one, Esc to clear.
    // Otherwise ↑↓ walk every page in rail order and ←→ walk the sections — so the
    // whole app is reachable without the pointer. Esc with nothing to clear is not
    // accepted here, so it reaches the host, which closes settings.
    //
    // These fire on the CARD, which is the focus root, so they also hear keys a
    // focused child did not consume. In the rail's search field ←→ move the cursor and
    // never get here; inside the page area the arrows are left to the page.
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_F && (e.modifiers & Qt.ControlModifier)) {
            if (Config.railCollapsed) Config.toggleRail()
            searchField.forceFocus()
            e.accepted = true
            return
        }

        if (root.searching) {
            if (e.key === Qt.Key_Down)      { root.stepResult(1);  e.accepted = true }
            else if (e.key === Qt.Key_Up)   { root.stepResult(-1); e.accepted = true }
            else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                if (resultsLoader.item) resultsLoader.item.pickFirst()
                e.accepted = true
            }
            // The field's own wrapper clears first when it has focus; this is for a
            // search left open with the focus elsewhere.
            else if (e.key === Qt.Key_Escape) { root.clearSearch(); e.accepted = true }
            return
        }

        const arrow = e.key === Qt.Key_Up || e.key === Qt.Key_Down
                   || e.key === Qt.Key_Left || e.key === Qt.Key_Right
        if (!arrow || root._focusInPage()) return

        if (e.key === Qt.Key_Down)       root.stepPage(1)
        else if (e.key === Qt.Key_Up)    root.stepPage(-1)
        else if (e.key === Qt.Key_Right) root.stepSection(1)
        else                             root.stepSection(-1)
        e.accepted = true
    }

    function clearSearch() {
        root.query = ""
        searchField.clear()
    }

    // The one way to land on a page from a key — a search result, a pin, a deep link.
    // A key resolves to its page (a bare file to that file's first page). `target`
    // ({ section, title, kind }) is a card or row on it to reveal; without one, a file
    // that was folded into another page as a card (SettingsIndex.aliasPlate) reveals
    // that card. The target is set BEFORE the page changes, so showView() can tell a deep
    // link (no cascade: the cards must already be where reveal() measures them) from an
    // ordinary move, and bumped after, so a page already on show hears it too.
    function goTo(key, target) {
        const e = SettingsIndex.entryFor(key)
        const plate = SettingsIndex.plateOf(key)
        UiState.settingsTarget = target ?? (plate !== "" ? { section: plate, title: plate, kind: "section" } : null)
        if (e) root.currentKey = e.key
        if (UiState.settingsTarget) UiState.settingsTargetNav++
    }

    // A search result: its page, revealing the row or card it named; a setting that
    // lives in a panel or an island opens there, and the search stays as it was so the
    // next result is one click away.
    function openResult(r) {
        if (!r) return
        if (r.kind === "elsewhere") { UiState.openElsewhere(r.open); return }
        root.clearSearch()
        root.goTo(r.key ?? r.file,
                  r.kind === "page" ? null : { section: r.section ?? "", title: r.title, kind: r.kind })
    }

    // ── Jumping straight to a page, from outside ──────────────────────────────
    // A hardware pill (Battery, Bluetooth), the disk widget, or
    // `qs ipc … call settings page <file>`. The request rides UiState rather than
    // Config: currentKey's binding to Config.settingsPage does not survive the
    // first rail click, so a Config write is not a reliable way in.
    //
    // Applied from BOTH ends. SettingsWindow gates this card behind a Loader, so
    // with the window closed there is no card to hear the signal — openSettingsTo()
    // bumps the counter before the card exists. Component.onCompleted catches that
    // case; the Connections catches a window already open.
    function _applyPageRequest() {
        const key = UiState.settingsPageRequest
        if (key === "") return

        // Guarded on the page EXISTING: "the adapter went away between the click
        // and this handler" is a real sequence, and an unguarded assign would
        // persist a key the rail has no row for as the remembered page.
        if (!SettingsIndex.entryFor(key)) {
            UiState.settingsPageRequest = ""
            return
        }

        root.openPage(key)
        // Consumed, and that is load-bearing: a fresh card cannot tell a new request
        // from a leftover one, so an uncleared request would pin every later open.
        UiState.settingsPageRequest = ""
    }

    Component.onCompleted: {
        // A target left from the last time the card was open (a page that had no row to
        // reveal) must not land on the page this one opens on.
        UiState.settingsTarget = null
        root._syncAnchor()
        // The page the card opens on counts as visited: leaving its section and coming back lands here.
        root._rememberView()
        root._applyPageRequest()
    }

    Connections {
        target: UiState
        function onSettingsPageNavChanged() { root._applyPageRequest() }
    }

    // ══ Layout ════════════════════════════════════════════════════════════════
    // Exactly two things, no outer margin, no spacing: the slab and the page.
    RowLayout {
        anchors.fill: parent
        // Inset by the card's own stroke so the slab sits INSIDE it; otherwise the
        // border draws across the slab's rounded corner as a double line.
        anchors.margins: root.border.width
        spacing: 0

        // ══ Sidebar ═══════════════════════════════════════════════════════════
        Rectangle {
            id: rail

            readonly property int fullWidth:      216
            readonly property int collapsedWidth: 76
            readonly property bool collapsed: Config.railCollapsed

            // ── The accordion's measures ──────────────────────────────────────
            // A section row holds a full badge with a little air; a page row is a step
            // shorter, so the section reads as the heading it is.
            readonly property int sectionH:  Tokens.iconXl + Tokens.spacingMd
            readonly property int pageH:     Tokens.iconXl + Tokens.spacingSm
            readonly property int gap:       Tokens.spacingXs
            readonly property int badgeSize: Tokens.iconXl
            // Where a page row's pill starts: inset, so the pages read as inside their
            // section; their labels line up with the section labels above.
            readonly property int pageInset: Tokens.spacingLg
            // A section opening is a box growing: critically damped, it must not wobble.
            readonly property var openSpec: ({ stiffness: Motion.springSpatial.stiffness, damping: 1.0 })

            onCollapsedChanged: Qt.callLater(rail.ensureCurrent)

            // ── The selection pill ────────────────────────────────────────────
            // ONE pill for the whole list, travelling to the page you pick instead of
            // each row lighting up on its own. Its two edges ride two springs, the
            // leading one on the faster spec, so it stretches toward the new row and
            // settles into it. The springs' targets are BOUND to the row's live
            // position (`liveY`), so while a section folds or unfolds under it the
            // pill follows the row frame by frame instead of aiming where it was.
            //
            // At rest the pill simply IS its row's geometry (`pillSpringing` false), so
            // the card opens with it in place and a late layout never leaves it behind.
            // Folded, the rail has no page rows, and the pill sits on the section.
            property Item pillRow: null
            property bool pillDown: true
            property bool pillSpringing: false

            function placePill(row) {
                if (!row || rail.pillRow === row) return
                if (rail.pillRow === null || !pageArea.settled) {
                    rail.pillRow = row
                    return
                }
                const top = navPill.y
                pillTop.jump(top)
                pillBottom.jump(top + navPill.height)
                rail.pillDown = row.liveY > top
                rail.pillSpringing = true
                rail.pillRow = row
            }
            function _pillRest() {
                if (!pillTop.moving && !pillBottom.moving) rail.pillSpringing = false
            }

            SpringValue {
                id: pillTop
                target: navPill.rowY
                spec: rail.pillDown ? Motion.springSpatial : Motion.springSpatialFast
                epsilon: 0.1
                onMovingChanged: rail._pillRest()
            }
            SpringValue {
                id: pillBottom
                target: navPill.rowY + navPill.rowH
                spec: rail.pillDown ? Motion.springSpatialFast : Motion.springSpatial
                epsilon: 0.1
                onMovingChanged: rail._pillRest()
            }

            // ── Keep the current row in view ──────────────────────────────────
            // Measured from where the rows WILL be once the accordion has settled (every
            // other section folded), not where they are mid-spring, so the scroll goes
            // straight to its end. The section's own row comes into view with the page
            // when both fit.
            function ensureCurrent() {
                const secs = root.navPages
                const nav = root.currentNav
                if (!secs || !nav) return
                const si = secs.findIndex(s => s.label === nav.label)
                if (si < 0) return
                const step = rail.sectionH + rail.gap
                const secTop = si * step
                let top = secTop
                let h = rail.sectionH
                let extra = 0
                if (!rail.collapsed) {
                    const n = nav.views.length
                    const key = root.currentEntry ? root.currentEntry.key : ""
                    const pi = Math.max(0, nav.views.findIndex(v => v.key === key))
                    extra = rail.gap + n * rail.pageH + (n - 1) * rail.gap
                    top = secTop + rail.sectionH + rail.gap + pi * (rail.pageH + rail.gap)
                    h = rail.pageH
                }
                const total = secs.length * step - rail.gap + extra
                const view = navFlick.height
                const from = (top + h - secTop <= view) ? secTop : top
                let y = navFlick.contentY
                if (from < y) y = from
                else if (top + h > y + view) y = top + h - view
                y = Math.max(0, Math.min(y, Math.max(0, total - view)))
                if (Math.abs(y - navFlick.contentY) < 0.5) return
                navScroll.to = y
                navScroll.restart()
            }

            NumberAnimation {
                id: navScroll
                target: navFlick
                property: "contentY"
                duration: Motion.standard
                easing.type: Motion.travel
            }

            property int railWidth: rail.collapsed ? rail.collapsedWidth : rail.fullWidth
            Behavior on railWidth {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }

            // Pinned, not merely preferred: a RowLayout honours a child's derived
            // minimum over its preference, so one long label would widen the rail
            // until the page had no room. Labels elide instead.
            Layout.preferredWidth: rail.railWidth
            Layout.minimumWidth:   rail.railWidth
            Layout.maximumWidth:   rail.railWidth
            Layout.fillHeight: true

            color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationNested)

            // Follows the card's resolved corners outside, square where it meets the
            // page. Per-corner radii rather than `clip: true`, which costs a pass.
            topLeftRadius:     Math.max(0, root.topLeftRadius    - root.border.width)
            bottomLeftRadius:  Math.max(0, root.bottomLeftRadius - root.border.width)
            topRightRadius:    0
            bottomRightRadius: 0

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingMd
                spacing: Tokens.spacingMd

                // ── Wordmark and the fold control ─────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: 40
                    spacing: Tokens.spacingSm

                    StyledText {
                        Layout.fillWidth: true
                        visible: !rail.collapsed
                        opacity: rail.collapsed ? 0 : 1
                        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        text: Translation.tr("Settings")
                        // The one display-weight word on this surface: the mono, bold.
                        font.family: Tokens.fontBlock
                        font.weight: Font.Bold
                        variant: "display"
                        elide: Text.ElideRight
                    }

                    RailButton {
                        // fillWidth WITH an alignment centres the button in the whole
                        // row when the wordmark beside it has gone.
                        Layout.fillWidth: rail.collapsed
                        Layout.alignment: Qt.AlignVCenter
                            | (rail.collapsed ? Qt.AlignHCenter : Qt.AlignRight)
                        // The arrow points where the rail is GOING.
                        glyph: rail.collapsed ? "󰵵" : "󰁭"
                        onTapped: Config.toggleRail()
                    }
                }

                // ── Search ────────────────────────────────────────────────────
                // A wrapper Item carries Escape, rather than attaching Keys to the
                // InputField itself: TextInput doesn't consume Escape, so it bubbles
                // here first. With a query, Escape clears it; without one it keeps
                // bubbling to the host, which closes settings.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: !rail.collapsed
                    implicitHeight: searchField.implicitHeight

                    Keys.onEscapePressed: function (e) {
                        if (root.query !== "") { root.clearSearch(); e.accepted = true }
                        else e.accepted = false
                    }

                    InputField {
                        id: searchField
                        anchors.left: parent.left
                        anchors.right: parent.right
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        placeholder: Translation.tr("Search settings")
                        // Types a few of the things it can find after the words, like the
                        // launcher's field does: short ones, the rail is narrow. Every
                        // one is a word the index answers.
                        hintLead: "Search settings"
                        hints: root.searchHints
                        // `edited`, not `committed`: results appear as you type. The
                        // search is a pure function over ~200 records.
                        onEdited: function (t) { root.query = t }
                        onAccepted: if (resultsLoader.item) resultsLoader.item.pickFirst()
                    }
                }

                // Collapsed: no room for a field, so a button that unfolds the rail
                // and puts the cursor in it.
                RailButton {
                    Layout.alignment: Qt.AlignHCenter
                    visible: rail.collapsed
                    glyph: "󰍉"
                    onTapped: {
                        Config.toggleRail()
                        searchField.forceFocus()
                    }
                }

                // ── Pinned ────────────────────────────────────────────────────
                // The two or three pages you actually use, above the sections. A
                // pin is a page KEY (see Config.settingsPinned), so it survives the rail
                // renumbering when a dongle appears, and a pin for a page that is
                // currently unavailable simply doesn't render.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    visible: root.pinnedViews.length > 0
                    spacing: Tokens.spacingXs

                    StyledText {
                        visible: !rail.collapsed
                        Layout.leftMargin: Tokens.spacingSm
                        text: Translation.tr("Pinned")
                        variant: "label"
                        emphasis: "muted"
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: root.pinnedViews

                        Rectangle {
                            id: pinRow
                            required property var modelData

                            readonly property bool isCurrent:
                                !root.searching
                                && root.currentEntry !== undefined
                                && SettingsIndex.entryFor(pinRow.modelData.key)?.key === root.currentEntry.key

                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            radius: height / 2
                            color: pinRow.isCurrent  ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.22)
                                 : pinHover.hovered  ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                                     : "transparent"
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin:  rail.collapsed ? 0 : Tokens.spacingMd
                                anchors.rightMargin: rail.collapsed ? 0 : Tokens.spacingMd
                                spacing: Tokens.spacingSm

                                MaterialIcon {
                                    Layout.fillWidth: rail.collapsed
                                    horizontalAlignment: Text.AlignHCenter
                                    glyph: pinRow.modelData.glyph
                                    color: pinRow.isCurrent ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fgDim
                                    variant: "body"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: !rail.collapsed
                                    text: pinRow.modelData.label
                                    variant: "caption"
                                    color: pinRow.isCurrent ? Colors.of(QsWindow.window).focus : Colors.of(QsWindow.window).fg
                                    font.weight: pinRow.isCurrent ? Font.DemiBold : Font.Normal
                                    elide: Text.ElideRight
                                }
                            }

                            HoverHandler { id: pinHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler   { onTapped: root.openPage(pinRow.modelData.key) }
                        }
                    }

                    Divider { visible: !rail.collapsed }
                }

                // ── Sections and their pages ──────────────────────────────────
                // Seven sections fit the window this opens at, but the list still
                // scrolls: the window is resizable down to 560px tall, and an open
                // section adds its pages. Plain Column/Item, not layouts: the rows'
                // heights come from springs, which a layout would fight.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: navFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth:  width
                        contentHeight: navCol.height
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        Item {
                            width: navFlick.width
                            height: navCol.height

                            // The pill itself (see rail.placePill), behind the rows.
                            Rectangle {
                                id: navPill
                                readonly property real rowY: rail.pillRow ? rail.pillRow.liveY : 0
                                readonly property real rowH: rail.pillRow ? rail.pillRow.height : 0

                                x: rail.collapsed ? 0 : rail.pageInset
                                Behavior on x { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
                                width: parent.width - navPill.x
                                y: rail.pillSpringing ? pillTop.value : navPill.rowY
                                height: rail.pillSpringing ? Math.max(0, pillBottom.value - pillTop.value) : navPill.rowH
                                radius: height / 2
                                color: Colors.of(QsWindow.window).primaryContainer
                                opacity: rail.pillRow && !root.searching ? 1 : 0
                                Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                            }

                            Column {
                                id: navCol
                                width: parent.width
                                spacing: rail.gap

                                Repeater {
                                    model: root.navPages

                                    delegate: Item {
                                        id: sectionItem
                                        required property var modelData

                                        // The section stays unfolded while search has the
                                        // page area; only the pill steps aside.
                                        readonly property bool isCurrentSection: root.currentNav !== undefined
                                            && root.currentNav.label === sectionItem.modelData.label
                                        readonly property bool open: sectionItem.isCurrentSection && !rail.collapsed

                                        width: navCol.width
                                        height: rail.sectionH + pagesBox.height

                                        SpringValue {
                                            id: openSpring
                                            target: sectionItem.open ? rail.gap + pageList.implicitHeight : 0
                                            spec: rail.openSpec
                                            epsilon: 0.1
                                        }

                                        // ── The section row ───────────────────────────
                                        Item {
                                            id: sectionRow
                                            readonly property real liveY: sectionItem.y
                                            readonly property bool holdsPill: sectionItem.isCurrentSection
                                                && rail.collapsed && !root.searching
                                            readonly property color ink: sectionRow.holdsPill
                                                ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                : Colors.of(QsWindow.window).fg

                                            width: parent.width
                                            height: rail.sectionH

                                            onHoldsPillChanged: if (sectionRow.holdsPill) rail.placePill(sectionRow)
                                            Component.onCompleted: if (sectionRow.holdsPill) rail.placePill(sectionRow)

                                            SpringValue {
                                                id: sectionLean
                                                target: sectionTap.pressed ? 0.96 : 1
                                                spec: Motion.springSpatialFast
                                                epsilon: 0.001
                                            }
                                            scale: sectionLean.value

                                            Accessible.role: Accessible.Button
                                            Accessible.name: sectionItem.modelData.label
                                            Accessible.onPressAction: root.showPage(sectionItem.modelData)

                                            StateLayer {
                                                anchors.fill: parent
                                                radius: height / 2
                                                hovered: sectionHover.hovered && !sectionRow.holdsPill
                                                layerColor: sectionRow.ink
                                            }

                                            // A disc while folded; the open section's badge
                                            // blooms into the section's own shape.
                                            Item {
                                                id: sectionBadge
                                                x: rail.collapsed ? (parent.width - width) / 2 : Tokens.spacingSm
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: rail.badgeSize
                                                height: width

                                                MorphShape {
                                                    anchors.fill: parent
                                                    shape: sectionItem.isCurrentSection ? (sectionItem.modelData.shape ?? "cookie9") : "circle"
                                                    spec: Motion.springSpatialFast
                                                    fillColor: sectionItem.isCurrentSection
                                                        ? Colors.of(QsWindow.window).primary
                                                        : Colors.of(QsWindow.window).surfaceHigh
                                                }
                                                MaterialIcon {
                                                    anchors.centerIn: parent
                                                    name:  sectionItem.modelData.icon ?? ""
                                                    glyph: sectionItem.modelData.glyph
                                                    fill:  sectionItem.isCurrentSection ? 1 : 0
                                                    font.pixelSize: Tokens.iconMd
                                                    color: sectionItem.isCurrentSection
                                                        ? Colors.of(QsWindow.window).fgOnPrimary
                                                        : Colors.of(QsWindow.window).fgMuted
                                                    Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                                                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                                                }
                                            }

                                            StyledText {
                                                anchors.left: sectionBadge.right
                                                anchors.leftMargin: Tokens.spacingMd
                                                anchors.right: parent.right
                                                anchors.rightMargin: Tokens.spacingMd
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: !rail.collapsed
                                                text: sectionItem.modelData.label
                                                variant: "body"
                                                font.weight: sectionItem.isCurrentSection ? Font.DemiBold : Font.Normal
                                                color: sectionRow.ink
                                                elide: Text.ElideRight
                                            }

                                            // Folded, a badge alone is a guess: its name comes
                                            // from the card's tip, which no list clips.
                                            HelpTip { text: rail.collapsed ? sectionItem.modelData.label : "" }
                                            HoverHandler { id: sectionHover; cursorShape: Qt.PointingHandCursor }
                                            TapHandler   { id: sectionTap; onTapped: root.showPage(sectionItem.modelData) }
                                        }

                                        // ── Its pages ─────────────────────────────────
                                        // The only clip in the list: the box the open
                                        // section's height spring runs on.
                                        Item {
                                            id: pagesBox
                                            y: rail.sectionH
                                            width: parent.width
                                            height: openSpring.value
                                            clip: true
                                            visible: pagesBox.height > 0.5

                                            Column {
                                                id: pageList
                                                y: rail.gap
                                                width: parent.width
                                                spacing: rail.gap

                                                Repeater {
                                                    model: sectionItem.modelData.views

                                                    delegate: Item {
                                                        id: pageRow
                                                        required property var modelData

                                                        // Nothing is current while search has the page
                                                        // area: the pill would point at a page that
                                                        // isn't on screen.
                                                        readonly property bool isCurrent: !root.searching
                                                            && root.currentEntry !== undefined
                                                            && root.currentEntry.key === pageRow.modelData.key
                                                        readonly property bool holdsPill: pageRow.isCurrent && !rail.collapsed
                                                        readonly property real liveY: sectionItem.y + pagesBox.y + pageList.y + pageRow.y
                                                        readonly property color ink: pageRow.isCurrent
                                                            ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                            : Colors.of(QsWindow.window).fg

                                                        width: pageList.width
                                                        height: rail.pageH

                                                        onHoldsPillChanged: if (pageRow.holdsPill) rail.placePill(pageRow)
                                                        Component.onCompleted: if (pageRow.holdsPill) rail.placePill(pageRow)

                                                        SpringValue {
                                                            id: pageLean
                                                            target: pageTap.pressed ? 0.96 : 1
                                                            spec: Motion.springSpatialFast
                                                            epsilon: 0.001
                                                        }
                                                        scale: pageLean.value

                                                        Accessible.role: Accessible.RadioButton
                                                        Accessible.name: pageRow.modelData.label
                                                        Accessible.checkable: true
                                                        Accessible.checked: pageRow.isCurrent
                                                        Accessible.onPressAction: root.openPage(pageRow.modelData.key)

                                                        StateLayer {
                                                            x: rail.pageInset
                                                            width: parent.width - rail.pageInset
                                                            height: parent.height
                                                            radius: height / 2
                                                            hovered: pageHover.hovered && !pageRow.isCurrent
                                                            layerColor: pageRow.ink
                                                        }

                                                        MaterialIcon {
                                                            id: pageIcon
                                                            x: rail.pageInset + Tokens.spacingMd
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            name:  pageRow.modelData.icon ?? ""
                                                            glyph: pageRow.modelData.glyph
                                                            fill:  pageRow.isCurrent ? 1 : 0
                                                            font.pixelSize: Tokens.iconMd
                                                            color: pageRow.isCurrent
                                                                ? Colors.of(QsWindow.window).fgOnPrimaryContainer
                                                                : Colors.of(QsWindow.window).fgMuted
                                                            Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                                                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                                                        }

                                                        StyledText {
                                                            anchors.left: pageIcon.right
                                                            anchors.leftMargin: Tokens.spacingSm
                                                            anchors.right: parent.right
                                                            anchors.rightMargin: Tokens.spacingMd
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: pageRow.modelData.label
                                                            variant: "label"
                                                            font.weight: pageRow.isCurrent ? Font.DemiBold : Font.Medium
                                                            color: pageRow.ink
                                                            elide: Text.ElideRight
                                                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                                                        }

                                                        HoverHandler { id: pageHover; cursorShape: Qt.PointingHandCursor }
                                                        TapHandler   { id: pageTap; onTapped: root.openPage(pageRow.modelData.key) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Scrollbar { flickable: navFlick }
                }

                // ── Watermark: the rail's foot, bottom left ───────────────────
                // Compact (the logo alone) when the rail is folded. Scaled down rather than
                // clipped if the words would be wider than the rail, which a bigger font
                // scale can cause. Always on — there is no switch for it.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: mark.height

                    Watermark {
                        id: mark
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        compact:   rail.collapsed
                        pixelSize: Tokens.fontCaption
                        iconSize:  Tokens.iconMd
                        pad:       Tokens.spacingMd
                        transformOrigin: Item.BottomLeft
                        scale: Math.min(1, parent.width / Math.max(1, mark.width))
                    }
                }
            }
        }

        // ══ Page ══════════════════════════════════════════════════════════════
        Item {
            id: pageArea
            Layout.fillWidth: true
            Layout.fillHeight: true

            // The right side clears the close cross when there is one, so a page's
            // own header actions never end up underneath it.
            // ── Capped and centred when the window is big ─────────────────────
            // At the window's opening size the page is ~885px and this is 0. Past
            // `maxPageWidth` the extra goes to equal gutters either side, for the search
            // results and every page alike — so pages that own their layout (Wallpaper,
            // Widgets, Keybinds, Updates, Storage) centre the same way.
            // Wide enough for a grouped page's hero column and two group columns
            // (SettingsPage): a page that fills its box is the point, and no row runs
            // long because the width goes to columns, not to longer rows. The cap only
            // stops an ultrawide from turning those columns into strips far apart.
            readonly property int maxPageWidth: 1760
            readonly property real extraGutter: Math.max(0,
                (pageArea.width - Tokens.spacingXl - (Tokens.spacingMd + root.chromeW + Tokens.spacingSm)
                 - pageArea.maxPageWidth) / 2)

            readonly property int sideLeft:  Tokens.spacingXl + pageArea.extraGutter
            // ── Clear of BOTH corner buttons ──────────────────────────────────
            // The pin star (and, in the window, the close cross beside it) sit in the
            // page's top-right corner. Allowing for the cross alone puts the star on
            // whatever a page keeps at its right edge: a header's action group, a
            // segmented control's last segment, a search field. So every page's right
            // edge stops short of the whole cluster (one `chromeW` wide, plus the edge
            // gap and a hair).
            readonly property int sideRight: Tokens.spacingMd + root.chromeW + Tokens.spacingSm + pageArea.extraGutter

            // ── Search results ────────────────────────────────────────────────
            // A Loader so an idle card builds no result list at all.
            Loader {
                id: resultsLoader
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   Tokens.spacingXl
                anchors.leftMargin:  pageArea.sideLeft
                anchors.rightMargin: pageArea.sideRight
                active: root.searching
                sourceComponent: SettingsSearchResults {
                    query: root.query
                    selectedIndex: root.resultIndex
                    onPicked: function (result) { root.openResult(result) }
                }
            }

            // ── The page ──────────────────────────────────────────────────────
            // Loaders, not a stack of always-built pages: BatteryPage polls UPower
            // and AboutPage shells out to specs.sh. Kept alive (just hidden) while
            // searching, so a half-edited page survives a search.
            //
            // TWO of them, taking turns, so a change of page is a move rather than a
            // cut: the page you are leaving slides out while the next slides in from
            // the side you are going to — from below for a page further down the rail,
            // from above for one higher up. The incoming page is fully built before
            // either moves (a local source loads synchronously), so nothing is ever seen
            // half-loaded, and it is opaque within the first third of the move. The first
            // page after the card opens appears at once: an entrance there reads as slow
            // loading.
            //
            // Keyed on the FILE: two pages that are anchors of one file share its load,
            // so moving between them keeps whatever the page holds (UiState.settingsAnchor
            // tells it which part to show).
            //
            // No bottom margin: the page's Flickable should run to the card's edge,
            // so scrolled content leaves at the boundary.
            readonly property string wantKey: root.currentEntry?.key ?? ""
            property string shownFile: ""
            property string shownKey: ""
            property int front: 0

            // False until the card has finished opening: a deep link applied in the
            // card's own onCompleted (UiState.settingsPageRequest) is still "the page
            // it opened on", and must not slide in from the remembered one.
            property bool settled: false

            onWantKeyChanged: pageArea.showView()
            Component.onCompleted: {
                pageArea.showView()
                Qt.callLater(function () { pageArea.settled = true })
            }

            function _flat(key) { return root.pages.findIndex(p => p.key === key) }

            function showView() {
                const key = root.currentEntry?.key ?? ""
                const file = root.currentEntry?.file ?? ""
                const prevKey = pageArea.shownKey
                pageArea.shownKey = key
                if (file === pageArea.shownFile) return
                const prev = pageArea.shownFile
                pageArea.shownFile = file

                const dy = prev !== "" && file !== ""
                    ? Math.sign(pageArea._flat(key) - pageArea._flat(prevKey)) : 0

                const incoming = pageArea.front === 0 ? slotB : slotA
                const outgoing = pageArea.front === 0 ? slotA : slotB
                pageArea.front = 1 - pageArea.front
                // The page loads inside enter() (a local source is synchronous), and every
                // Section/tile made meanwhile staggers in; the flag is down again by the time
                // enter() returns.
                const opening = prev === "" || !pageArea.settled
                // A deep link lands still: the cascade's rise would move every card while
                // SettingsPage.reveal() measures where to scroll.
                UiState.settingsCascade = !opening && !UiState.settingsTarget
                incoming.enter(file !== "" ? Qt.resolvedUrl("pages/" + file) : "", 0, dy, opening)
                UiState.settingsCascade = false
                outgoing.leave(0, dy)
            }

            // Placed here, not inside PageSlot: an inline component cannot see this
            // file's ids (ComponentBehavior: Bound), so its anchors come from outside.
            PageSlot {
                id: slotA
                hidden: root.searching
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   Tokens.spacingXl
                anchors.leftMargin:  pageArea.sideLeft
                anchors.rightMargin: pageArea.sideRight
            }
            PageSlot {
                id: slotB
                hidden: root.searching
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   Tokens.spacingXl
                anchors.leftMargin:  pageArea.sideLeft
                anchors.rightMargin: pageArea.sideRight
            }
        }
    }

    // ── PageSlot — one of the two loaders the view alternates between ─────────
    component PageSlot: Loader {
        id: slot

        // 0 = off stage, 1 = in place. Direction is the move's: +1 right/down.
        property real t: 0
        property real dx: 0
        property real dy: 0
        property bool leaving: false
        // Search has the page area; the slots stay loaded underneath.
        property bool hidden: false
        readonly property real travel: 16

        visible: !slot.hidden && slot.status === Loader.Ready && slot.t > 0
        enabled: !slot.leaving
        z: slot.leaving ? 0 : 1

        // Comes in from the side it is going to; leaves toward the side it came from.
        // The leaving page fades on t² so it is mostly gone before the two overlap.
        opacity: slot.leaving ? slot.t * slot.t : Math.min(1, slot.t * 1.6)
        transform: Translate {
            x: (1 - slot.t) * slot.dx * slot.travel * (slot.leaving ? -1 : 1)
            y: (1 - slot.t) * slot.dy * slot.travel * (slot.leaving ? -1 : 1)
        }

        function enter(url, dx, dy, instant) {
            leaveAnim.stop()
            slot.leaving = false
            slot.dx = dx
            slot.dy = dy
            slot.source = url
            if (instant || (dx === 0 && dy === 0)) {
                enterAnim.stop()
                slot.t = 1
                return
            }
            slot.t = 0
            enterAnim.restart()
        }
        function leave(dx, dy) {
            enterAnim.stop()
            slot.leaving = true
            slot.dx = dx
            slot.dy = dy
            if (slot.source == "") return
            leaveAnim.restart()
        }

        NumberAnimation {
            id: enterAnim
            target: slot; property: "t"; to: 1
            duration: Motion.emphasized
            easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
        }
        SequentialAnimation {
            id: leaveAnim
            NumberAnimation {
                target: slot; property: "t"; to: 0
                duration: Motion.exit
                easing.type: Motion.respondCurve
            }
            ScriptAction { script: slot.source = "" }
        }
    }

    // ── The help tip ──────────────────────────────────────────────────────────
    // A control's explanation (its `help`, via components/HelpTip) appears here when
    // the pointer rests on it — drawn by the card, above everything, because a tip
    // drawn inside the page is clipped by its scroll area. It waits a moment before
    // the first one (sweeping across a page must not flash a tip per card), then
    // follows from control to control at once, as tooltips do.
    //
    // The window and the docked panel are two cards reading one UiState, so the tip
    // only follows a control that is inside THIS card.
    TipBubble {
        host: root
        z: 60
    }

    // ── The way out, and the pin ─────────────────────────────────────────────
    // Top-right corner, in the page's top gutter (the page area keeps clear of the whole
    // tray, `chromeW`), level with the page's header. Card chrome rather than a per-page
    // control: every page can be pinned, and asking thirty pages to each draw the same
    // star is how they drift. The ChipTray is what every panel's header wears for its actions.
    ChipTray {
        id: chromeTray
        z: 20
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacingXl
        anchors.rightMargin: Tokens.spacingMd

        ChipButton {
            // Fill IS the state: a pinned page's star is solid.
            symbol: "star"
            on: root.currentEntry !== undefined
                && SettingsIndex.isPinned(root.currentEntry.key)
            tint: Colors.of(QsWindow.window).primary
            enabled: !root.searching && root.currentEntry !== undefined
            onActivated: if (root.currentEntry)
                SettingsIndex.togglePin(root.currentEntry.key)
        }
        ChipButton {
            visible: root.closable
            symbol: "close"
            tint: Colors.of(QsWindow.window).danger
            onActivated: root.closeRequested()
        }
    }

    // ── RailButton — the round glyph button used for fold, search and close ───
    component RailButton: Rectangle {
        id: rb
        property string glyph: ""
        property string symbol: ""       // a Material Symbols name, instead of a glyph
        property bool active: false      // "on" — filled icon, accent tint
        property bool danger: false
        signal tapped()

        implicitWidth:  34
        implicitHeight: 34
        radius: height / 2
        color: rbHover.hovered
             ? (rb.danger ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.20) : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.10))
             : "transparent"
        Behavior on color { ColorAnimation { duration: Motion.respond } }

        MaterialIcon {
            anchors.centerIn: parent
            visible: rb.symbol === ""
            glyph: rb.glyph
            color: rbHover.hovered ? (rb.danger ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fg) : Colors.of(QsWindow.window).fgMuted
            variant: "title"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: rb.symbol !== ""
            name: rb.symbol
            // Fill IS the state here: a pinned view's star is solid, an unpinned one
            // is an outline. One glyph, two states, no second icon to keep in step.
            fill: rb.active ? 1 : 0
            color: rb.active ? Colors.of(QsWindow.window).focus
                 : rbHover.hovered ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgMuted
            variant: "title"
            Behavior on color { ColorAnimation { duration: Motion.respond } }
            scale: rb.active ? 1.0 : 0.92
            Behavior on scale {
                NumberAnimation {
                    duration: Motion.standard
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.spring
                }
            }
        }

        HoverHandler { id: rbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { onTapped: rb.tapped() }
    }
}
