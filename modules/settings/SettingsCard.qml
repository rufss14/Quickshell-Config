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
// ── Pages and views ───────────────────────────────────────────────────────────
// The rail lists the PAGES (SettingsIndex.navPages). A page with more than one
// VIEW gets a TabStrip above its content — Devices is Sound | Network | Bluetooth… —
// except a composed page (Sidebar & dock), which is one view of stacked groups.
// Each view is one file in pages/, loaded on demand. The state is a FILE, never a
// page index: file names are unique across the catalogue, so the page is derived.
//
// ── Search lives in the rail ──────────────────────────────────────────────────
// It used to be a landing page (HomePage), reachable only by going back to it. The
// field is in the rail now, on every page; typing swaps the page area for
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
// The SELECTED item is a solid accent fill (docs/settings-style.md §5). What stops it
// reading as a button is SHAPE: a full-width row in the slab, where a control is a
// hug-width box inside a card.
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

    // ── The FILE is the state; the index is derived ───────────────────────────
    // `current` was once the property, restored by a binding — and a hardware
    // handler ASSIGNING it before Config loaded destroyed that binding, so the page
    // was always remembered and never restored. Deriving the index means a renumber
    // (a Bluetooth dongle appearing) re-resolves for free and there is nothing to
    // assign, so nothing to break.
    //
    // Not in UiState: that holds session state and is deliberately not persisted,
    // and "the page I was last on" should survive a restart.
    property string currentFile: Config.settingsPage
    readonly property int current: root._indexOfPage(root.currentFile)

    onCurrentFileChanged: {
        Config.settingsPage = root.currentFile
        const nav = SettingsIndex.navPageFor(root.currentFile)
        if (nav) root._lastView[nav.label] = root.currentFile
    }

    // Every available view, flat, and the rail's pages. Both live in SettingsIndex
    // because search needs them too, and search is not loaded by this card.
    readonly property var pages:    SettingsIndex.pages
    readonly property var navPages: SettingsIndex.navPages

    // The page the current view belongs to. Resolved through `current`, not
    // `currentFile`, so a remembered file that no longer exists (hardware went away)
    // lands on the same fallback the Loader does.
    readonly property var currentNav:
        SettingsIndex.navPageFor(root.pages[root.current]?.file ?? "") ?? root.navPages[0]

    // Which view each page was last on, for this card's lifetime — returning to
    // Devices goes back to Bluetooth rather than resetting to Sound. A plain object
    // on purpose: nothing binds to it, it is only read on a rail click.
    property var _lastView: ({})

    function showPage(nav) {
        root.clearSearch()
        const last = root._lastView[nav.label]
        const stillThere = nav.views.some(function (v) { return v.file === last })
        root.currentFile = stillThere ? last : nav.views[0].file
    }

    function _indexOfPage(requested) {
        // `pages` may be undefined on the first pass; reading it still registers the
        // dependency, so the binding re-runs once the list exists.
        const list = root.pages
        if (!list) return 0
        // A remembered or requested file may be a MEMBER of a composed page (an old
        // "DockPage.qml" in config.json); the page that renders it is its host.
        const file = SettingsIndex.hostOf(requested)
        for (let i = 0; i < list.length; i++)
            if (list[i].file === file) return i
        return 0        // remembered view no longer exists (hardware went away)
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
    // Wrapping on purpose: a rail of eight is a ring, and stopping dead at the ends
    // costs a keypress every time you overshoot.
    function stepResult(d) {
        const item = resultsLoader.item
        if (!item) return
        const n = item.results.length
        if (n === 0) return
        root.resultIndex = root.resultIndex < 0 ? (d > 0 ? 0 : n - 1)
                                                : (root.resultIndex + d + n) % n
    }

    function stepPage(d) {
        const list = root.navPages
        if (!list || list.length === 0) return
        const label = root.currentNav ? root.currentNav.label : ""
        let i = 0
        for (let k = 0; k < list.length; k++) if (list[k].label === label) i = k
        root.showPage(list[(i + d + list.length) % list.length])
    }

    function stepView(d) {
        const views = root.currentNav ? root.currentNav.views : []
        if (!views || views.length < 2) return
        const file = root.pages[root.current] ? root.pages[root.current].file : ""
        let i = 0
        for (let k = 0; k < views.length; k++) if (views[k].file === file) i = k
        root.currentFile = views[(i + d + views.length) % views.length].file
    }

    // ── The keyboard map ──────────────────────────────────────────────────────
    // Ctrl+F from anywhere, then ↑↓ through results and Enter to open one. With the
    // field empty, ↑↓ walk the rail and ←→ walk the views of the page you are on —
    // so the whole app is reachable without the pointer.
    //
    // These fire on the CARD, which is the focus root. A single-line TextInput does
    // not consume Up/Down, so the arrows still reach here while you are typing; it
    // does consume ←→ (cursor movement), which is why view-stepping is only bound
    // for the not-searching case.
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
            return
        }

        if (e.key === Qt.Key_Down)       { root.stepPage(1);  e.accepted = true }
        else if (e.key === Qt.Key_Up)    { root.stepPage(-1); e.accepted = true }
        else if (e.key === Qt.Key_Right) { root.stepView(1);  e.accepted = true }
        else if (e.key === Qt.Key_Left)  { root.stepView(-1); e.accepted = true }
    }

    function clearSearch() {
        root.query = ""
        searchField.clear()
    }

    // The one way to land on a view from a name — a search result, a pin, a deep link.
    // A member of a composed page lands on its host and asks it to scroll to the group;
    // anything else is the view itself.
    function goTo(file) {
        const host = SettingsIndex.hostOf(file)
        // Only a member names a group; an alias (a file that is gone) just lands.
        const member = SettingsIndex.memberPages.some(function (m) { return m.file === file })
        UiState.settingsGroup = member ? file : ""
        root.currentFile = host
    }

    function openResult(file) {
        root.clearSearch()
        root.goTo(file)
    }

    // ── Jumping straight to a view, from outside ──────────────────────────────
    // A hardware pill (Battery, Bluetooth), the disk widget, or
    // `qs ipc … call settings page <file>`. The request rides UiState rather than
    // Config: currentFile's binding to Config.settingsPage does not survive the
    // first rail click, so a Config write is not a reliable way in.
    //
    // Applied from BOTH ends. SettingsWindow gates this card behind a Loader, so
    // with the window closed there is no card to hear the signal — openSettingsTo()
    // bumps the counter before the card exists. Component.onCompleted catches that
    // case; the Connections catches a window already open.
    function _applyPageRequest() {
        const file = UiState.settingsPageRequest
        if (file === "") return

        // Guarded on the view EXISTING: "the adapter went away between the click
        // and this handler" is a real sequence, and an unguarded assign would
        // persist a file the rail has no entry for as the remembered page.
        const host = SettingsIndex.hostOf(file)
        if (root._indexOfPage(host) === 0 && root.pages[0]?.file !== host) {
            UiState.settingsPageRequest = ""
            return
        }

        root.clearSearch()
        root.goTo(file)
        // Consumed, and that is load-bearing: a fresh card cannot tell a new request
        // from a leftover one, so an uncleared request would pin every later open.
        UiState.settingsPageRequest = ""
    }

    Component.onCompleted: root._applyPageRequest()

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

            property int railWidth: rail.collapsed ? rail.collapsedWidth : rail.fullWidth
            Behavior on railWidth {
                NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
            }

            // Pinned, not merely preferred: a RowLayout honours a child's derived
            // minimum over its preference, so one long label used to widen the rail
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
                // The two or three views you actually use, above the eight pages. A
                // pin is a FILE (see Config.settingsPinned), so it survives the rail
                // renumbering when a dongle appears, and a pin for a view that is
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
                                && root.pages[root.current]
                                && root.pages[root.current].file === SettingsIndex.hostOf(pinRow.modelData.file)

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
                            TapHandler   {
                                onTapped: {
                                    root.clearSearch()
                                    root.goTo(pinRow.modelData.file)
                                }
                            }
                        }
                    }

                    Divider { visible: !rail.collapsed }
                }

                // ── Nav list ──────────────────────────────────────────────────
                // Eight entries fit the window this opens at, but it still scrolls:
                // the window is resizable down to 560px tall.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Flickable {
                        id: navFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth:  width
                        contentHeight: navCol.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        // ── The selection pill ────────────────────────────────
                        // ONE pill for the whole list, gliding to the page you pick,
                        // instead of each row lighting up on its own — the same idea
                        // as the tab strip's wash, so the rail and the strip move
                        // alike. Its two ends travel separately: the end facing the
                        // way it is going leads and the other follows, so it
                        // stretches toward the new row and settles into it.
                        Rectangle {
                            id: navPill
                            property Item row: null
                            // Only meaningful while gliding; at rest the pill simply
                            // IS its row's geometry, so a row the layout places late
                            // (or resizes) never leaves it behind.
                            property real topY: 0
                            property real bottomY: 0
                            readonly property bool gliding: pillTop.running || pillBottom.running

                            x: 0
                            y: navPill.gliding ? navPill.topY : (navPill.row ? navPill.row.y : 0)
                            width: navFlick.width
                            height: navPill.gliding ? Math.max(0, navPill.bottomY - navPill.topY)
                                                    : (navPill.row ? navPill.row.height : 0)
                            radius: height / 2
                            color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus,
                                       navPill.row && navPill.row.hot ? 1.0 : 0.92)
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                            opacity: navPill.row && !root.searching ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                            function glideTo(row, instant) {
                                // Where it is drawn now, before `row` moves it.
                                const fromTop = navPill.y
                                const fromBottom = navPill.y + navPill.height
                                const wasPlaced = navPill.row !== null && navPill.height > 0
                                navPill.row = row
                                if (!row || instant || !wasPlaced) {
                                    pillTop.stop()
                                    pillBottom.stop()
                                    return
                                }
                                navPill.topY = fromTop
                                navPill.bottomY = fromBottom
                                const down = row.y > fromTop
                                pillTop.to    = row.y
                                pillBottom.to = row.y + row.height
                                pillTop.duration    = down ? Motion.emphasized : Motion.standard
                                pillBottom.duration = down ? Motion.standard : Motion.emphasized
                                pillTop.restart()
                                pillBottom.restart()
                            }

                            NumberAnimation {
                                id: pillTop
                                target: navPill; property: "topY"
                                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                            }
                            NumberAnimation {
                                id: pillBottom
                                target: navPill; property: "bottomY"
                                easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel
                            }
                        }

                        ColumnLayout {
                            id: navCol
                            width: navFlick.width
                            spacing: Tokens.spacingXs

                            Repeater {
                                model: root.navPages

                                Rectangle {
                                    id: navItem
                                    required property var modelData

                                    // Nothing is "current" while search has the page
                                    // area — the pill would point at a page that isn't
                                    // on screen.
                                    readonly property bool isCurrent: !root.searching
                                        && root.currentNav?.label === navItem.modelData.label
                                    readonly property bool hot: navHover.hovered

                                    // The pill (navPill, above) carries the selection;
                                    // a row only says where the pointer is.
                                    onIsCurrentChanged: if (navItem.isCurrent) navPill.glideTo(navItem, false)
                                    Component.onCompleted: if (navItem.isCurrent) navPill.glideTo(navItem, true)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 42
                                    // A capsule, like the page switch's indicator beside
                                    // it: the rail and the strip are one navigation.
                                    radius: height / 2

                                    color: !navItem.isCurrent && navHover.hovered
                                         ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
                                         : "transparent"
                                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin:  rail.collapsed ? 0 : Tokens.spacingLg
                                        anchors.rightMargin: rail.collapsed ? 0 : Tokens.spacingLg
                                        spacing: Tokens.spacingMd

                                        MaterialIcon {
                                            Layout.fillWidth: rail.collapsed
                                            horizontalAlignment: Text.AlignHCenter
                                            // The page's Material symbol, filled in while it is the
                                            // current one (the FILL axis, animated) — the same way a
                                            // chosen segment's icon fills in on the strip beside it.
                                            name:  navItem.modelData.icon ?? ""
                                            glyph: navItem.modelData.glyph
                                            fill:  navItem.isCurrent ? 1 : 0
                                            Behavior on fill { NumberAnimation { duration: Motion.standard } }
                                            // `focus` on `focus` is invisible; the
                                            // contrast colour is the only legible one.
                                            color: navItem.isCurrent ? Colors.of(QsWindow.window).fgOnPrimary
                                                 : navHover.hovered  ? Colors.of(QsWindow.window).fg
                                                                     : Colors.of(QsWindow.window).fgDim
                                            variant: "title"
                                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                                            // Leans toward the page it would open.
                                            transform: Translate {
                                                x: navHover.hovered && !navItem.isCurrent && !rail.collapsed ? 3 : 0
                                                Behavior on x {
                                                    NumberAnimation {
                                                        duration: Motion.standard
                                                        easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring
                                                    }
                                                }
                                            }
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            visible: !rail.collapsed
                                            opacity: rail.collapsed ? 0 : 1
                                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                                            text: navItem.modelData.label
                                            variant: "body"
                                            color: navItem.isCurrent ? Colors.of(QsWindow.window).fgOnPrimary : Colors.of(QsWindow.window).fg
                                            font.weight: navItem.isCurrent ? Font.DemiBold : Font.Normal
                                            elide: Text.ElideRight
                                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                                        }
                                    }

                                    // ── Tooltip ────────────────────────────────
                                    // The collapsed rail is glyphs alone, and a glyph
                                    // is a guess. z-lifted so the row doesn't clip it.
                                    Rectangle {
                                        visible: rail.collapsed && navHover.hovered
                                        x: parent.width + Tokens.spacingMd
                                        anchors.verticalCenter: parent.verticalCenter
                                        z: 50
                                        width:  tipText.implicitWidth + Tokens.spacingMd * 2
                                        height: tipText.implicitHeight + Tokens.spacingSm * 2
                                        radius: Tokens.radiusSm
                                        color:        Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup)
                                        border.width: Tokens.borderWidth
                                        border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationPopup)

                                        StyledText {
                                            id: tipText
                                            anchors.centerIn: parent
                                            text:    navItem.modelData.label
                                            variant: "caption"
                                        }
                                    }

                                    HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                                    TapHandler   { onTapped: root.showPage(navItem.modelData) }
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
            // At the window's opening size the page is ~885px and this is 0. Fullscreen
            // on a wide screen it would be ~1600px: a switch row's label at one end and
            // its switch at the other, a tab strip of four ~400px segments. Past
            // `maxPageWidth` the extra goes to equal gutters either side, for the strip,
            // the search results and every page alike — so pages that own their layout
            // (Wallpaper, Widgets, Keybinds, Updates, Storage) centre the same way.
            readonly property int maxPageWidth: 1280
            readonly property real extraGutter: Math.max(0,
                (pageArea.width - Tokens.spacingXl - (Tokens.spacingMd + root.chromeW + Tokens.spacingSm)
                 - pageArea.maxPageWidth) / 2)

            readonly property int sideLeft:  Tokens.spacingXl + pageArea.extraGutter
            // ── Clear of BOTH corner buttons ──────────────────────────────────
            // The pin star (and, in the window, the close cross beside it) sit in the
            // page's top-right corner. Only the cross used to be allowed for, and by
            // 30px of a 34px button — so the star, and the last pixels of the cross,
            // landed on whatever a page kept at its right edge: a header's action
            // group, a tab strip's last segment, a search field. Every page's right edge
            // now stops short of the whole cluster (it is one `chromeW` wide, plus the
            // edge gap and a hair).
            readonly property int sideRight: Tokens.spacingMd + root.chromeW + Tokens.spacingSm + pageArea.extraGutter

            // ── View switch ───────────────────────────────────────────────────
            // Only for a page with more than one view. Hidden during search.
            TabStrip {
                id: viewStrip
                visible: !root.searching && (root.currentNav?.views.length ?? 0) > 1
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   Tokens.spacingXl
                anchors.leftMargin:  pageArea.sideLeft
                anchors.rightMargin: pageArea.sideRight
                accent: Colors.of(QsWindow.window).primary
                model: (root.currentNav?.views ?? []).map(function (v) {
                    return { value: v.file, label: v.label, icon: v.icon ?? "" }
                })
                current: root.pages[root.current]?.file ?? ""
                onPicked: function (value) { root.currentFile = value }
            }

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
                    onPicked: function (file) { root.openResult(file) }
                }
            }

            // ── The view ──────────────────────────────────────────────────────
            // Loaders, not a stack of always-built pages: BatteryPage polls UPower
            // and AboutPage shells out to specs.sh. Kept alive (just hidden) while
            // searching, so a half-edited page survives a search.
            //
            // TWO of them, taking turns, so a change of page is a move rather than a
            // cut: the page you are leaving slides out while the next slides in from
            // the side you are going to — sideways between the views of one page
            // (the tab strip's direction), up or down between pages (the rail's).
            // The incoming page is fully built before either moves (a local source
            // loads synchronously), so nothing is ever seen half-loaded, and it is
            // opaque within the first third of the move. The first page after the
            // card opens appears at once: an entrance there reads as slow loading.
            //
            // No bottom margin: the page's Flickable should run to the card's edge,
            // so scrolled content leaves at the boundary.
            readonly property string wantFile: root.pages[root.current]?.file ?? ""
            property string shownFile: ""
            property int front: 0

            // False until the card has finished opening: a deep link applied in the
            // card's own onCompleted (UiState.settingsPageRequest) is still "the page
            // it opened on", and must not slide in from the remembered one.
            property bool settled: false

            onWantFileChanged: pageArea.showView()
            Component.onCompleted: {
                pageArea.showView()
                Qt.callLater(function () { pageArea.settled = true })
            }

            function _navIndex(file) {
                const nav = SettingsIndex.navPageFor(file)
                if (!nav) return -1
                for (let i = 0; i < root.navPages.length; i++)
                    if (root.navPages[i].label === nav.label) return i
                return -1
            }
            function _viewIndex(file) {
                const nav = SettingsIndex.navPageFor(file)
                if (!nav) return -1
                for (let i = 0; i < nav.views.length; i++)
                    if (nav.views[i].file === file) return i
                return -1
            }

            function showView() {
                const file = pageArea.wantFile
                if (file === pageArea.shownFile) return
                const prev = pageArea.shownFile
                pageArea.shownFile = file

                let dx = 0, dy = 0
                if (prev !== "" && file !== "") {
                    const pn = pageArea._navIndex(prev), nn = pageArea._navIndex(file)
                    if (pn === nn) dx = Math.sign(pageArea._viewIndex(file) - pageArea._viewIndex(prev))
                    else           dy = Math.sign(nn - pn)
                }

                const incoming = pageArea.front === 0 ? slotB : slotA
                const outgoing = pageArea.front === 0 ? slotA : slotB
                pageArea.front = 1 - pageArea.front
                // The page loads inside enter() (a local source is synchronous), and every
                // Section/tile made meanwhile staggers in; the flag is down again by the time
                // enter() returns.
                const opening = prev === "" || !pageArea.settled
                UiState.settingsCascade = !opening
                incoming.enter(file !== "" ? Qt.resolvedUrl("pages/" + file) : "", dx, dy, opening)
                UiState.settingsCascade = false
                outgoing.leave(dx, dy)
            }

            // Placed here, not inside PageSlot: an inline component cannot see this
            // file's ids (ComponentBehavior: Bound), so its anchors come from outside.
            PageSlot {
                id: slotA
                hidden: root.searching
                anchors.top: viewStrip.visible ? viewStrip.bottom : parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   viewStrip.visible ? Tokens.spacingLg : Tokens.spacingXl
                anchors.leftMargin:  pageArea.sideLeft
                anchors.rightMargin: pageArea.sideRight
            }
            PageSlot {
                id: slotB
                hidden: root.searching
                anchors.top: viewStrip.visible ? viewStrip.bottom : parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin:   viewStrip.visible ? Tokens.spacingLg : Tokens.spacingXl
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
    function _owns(item) {
        for (let it = item; it; it = it.parent)
            if (it === root) return true
        return false
    }

    Rectangle {
        id: tip
        z: 60

        readonly property QtObject source: UiState.tipSource
        property bool shown: false
        readonly property int maxWidth: 300

        function place() {
            const src = UiState.tipSource
            if (!src || !src.parent) return
            const p = src.parent.mapToItem(root, src.point.position.x, src.point.position.y)
            const gap = Tokens.spacingXl
            let x = p.x + Tokens.spacingSm
            let y = p.y + gap
            if (x + tip.width > root.width - Tokens.spacingMd) x = root.width - Tokens.spacingMd - tip.width
            if (y + tip.height > root.height - Tokens.spacingMd) y = p.y - Tokens.spacingSm - tip.height
            tip.x = Math.max(Tokens.spacingMd, x)
            tip.y = Math.max(Tokens.spacingMd, y)
        }

        onSourceChanged: {
            const src = tip.source
            if (!src || !src.parent || !root._owns(src.parent)) {
                tipDelay.stop()
                tip.shown = false
                return
            }
            if (tip.shown) tip.place()
            else tipDelay.restart()
        }

        Timer {
            id: tipDelay
            interval: 550
            onTriggered: {
                tip.place()
                tip.shown = true
            }
        }

        width:  Math.min(tipText.implicitWidth, tip.maxWidth) + Tokens.spacingMd * 2
        height: tipText.implicitHeight + Tokens.spacingSm * 2 + 2
        radius: Tokens.radiusSm
        color:        Colors.of(QsWindow.window).surfaceFor(Tokens.elevationPopup)
        border.width: Tokens.borderWidth
        border.color: Colors.of(QsWindow.window).outlineFor(Tokens.elevationPopup)

        visible: tip.opacity > 0.01
        opacity: tip.shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        // Rises the last few pixels into place, so it reads as arriving, not blinking.
        transform: Translate {
            y: tip.shown ? 0 : 4
            Behavior on y { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        }

        StyledText {
            id: tipText
            anchors.centerIn: parent
            width: Math.min(tipText.implicitWidth, tip.maxWidth)
            text: UiState.tipText
            variant: "caption"
            wrapMode: Text.WordWrap
        }
    }

    // ── The way out, and the pin ─────────────────────────────────────────────
    // Top-right corner, in the page's top gutter (the page area keeps clear of the whole
    // tray, `chromeW`), level with the view switch. Card chrome rather than a per-page
    // control: every view can be pinned, and asking twenty-two pages to each draw the same
    // star is how they drift. The ChipTray is what every panel's header wears for its actions.
    ChipTray {
        id: chromeTray
        z: 20
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Tokens.spacingXl
        anchors.rightMargin: Tokens.spacingMd

        ChipButton {
            // Fill IS the state: a pinned view's star is solid.
            symbol: "star"
            on: root.pages[root.current] !== undefined
                && Config.settingsPinnedHas(root.pages[root.current].file)
            tint: Colors.of(QsWindow.window).primary
            enabled: !root.searching && root.pages[root.current] !== undefined
            onActivated: if (root.pages[root.current])
                Config.toggleSettingsPin(root.pages[root.current].file)
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
