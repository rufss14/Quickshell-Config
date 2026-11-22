import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../services"
import "../state"
import "masonry.js" as Masonry

// ── SettingsPage ──────────────────────────────────────────────────────────────
// The whole shape of a settings page: header, rule, and a scrolling column of
// Sections capped to a readable width and centred in whatever room the window
// gives it.
//
// ── Why this is a component and not a documented skeleton ─────────────────────
// It WAS a documented skeleton — docs/settings-style.md §3, copy-pasted into each
// page. Copy-paste is how eighteen pages ended up with eighteen slightly different
// ideas of the same layout in the first place: some scrolled and some didn't, some
// had a Scrollbar, the body spacing varied, and the pages that pinned their own
// column widths did it to three different numbers. A component makes "every page
// is laid out the same" true by construction rather than by everyone remembering.
//
// ── Why the content is CAPPED and centred ─────────────────────────────────────
// Settings is a resizable window, so a page has no known size: it can be 900px wide or
// fullscreen on an ultrawide. Filling that width edge-to-edge puts a toggle's label at the far left
// and its switch three feet away at the far right.
//
// So the body has a maximum and sits in the middle, which is the one arrangement
// that is correct at every size — and is what the reference design does. Gutters
// are not wasted space; they are what stops a row from becoming a scan line.
//
// `maxContentWidth` is a property rather than a constant because a few pages hold
// something that genuinely wants more room — a wallpaper gallery, a chart — and
// widening one page deliberately is better than uncapping all of them by default.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Header, passed straight through to PanelHeader.
    property string glyph:     ""
    property string title:     ""
    property string titleTail: ""
    property string subtitle:  ""
    property color  accent:    Colors.of(QsWindow.window).primary
    // The header badge's Material 3 Expressive shape (components/shapes.js). Left empty, a page gets one of
    // these by its title, so each page wears a different one and the same page always the same.
    property string headerShape: ""
    readonly property var _shapes: ["cookie9", "sunny", "clover", "squircle", "hexagon", "pentagon", "burst", "cookie6"]
    readonly property string _headerShape: {
        if (root.headerShape !== "") return root.headerShape
        let h = 0
        for (let i = 0; i < root.title.length; i++) h = (h * 31 + root.title.charCodeAt(i)) % 997
        return root._shapes[h % root._shapes.length]
    }

    // Header-right controls (a Reset button, a master toggle). A RowLayout, so
    // several lay out properly instead of stacking.
    property alias actions: headerRow.actions

    // Fixed content between the rule and the scroll — an apply/undo banner, an error
    // strip. Deliberately OUTSIDE the Flickable: a banner saying "saved, reload to
    // apply" that scrolls off the top is a banner you will not see.
    property alias banner: bannerCol.data

    // ── The body is a RESPONSIVE GRID, not one column ─────────────────────────
    // Not one centred column capped at 760: that reads well but, on a 1900px screen,
    // leaves ~450px of nothing down each side and makes every page tall enough to scroll.
    // (Grouped pages are the exception, below: a grouped row is one line to read.)
    //
    // So the width buys COLUMNS rather than wider rows. A row stretched to 1900px puts
    // a label at one edge and its switch at the other, which is what the cap existed
    // to prevent; two 760px columns keep every row readable AND halve the height.
    //
    // Columns are derived from the space available, so the same page is one column at
    // the window's 900px minimum and three on an ultrawide, with nothing per-page to
    // maintain.
    property real columnWidth:    760   // the widest ONE column is allowed to get

    // How many SectionColumns the PAGE declares. Width can take this down — never up:
    // a page that groups its content into two columns gets two wide ones on a big
    // screen rather than two narrow ones and an empty third.
    //
    // ── This stays 1, and the reason is worth writing down ────────────────────
    // Defaulting it to 2 looks like the fix for a page leaving ~430px of empty gutter
    // down each side of a 1900px window. It is not, and it makes that page worse.
    //
    // `columns` does not FLOW sections into columns — the body is a GridLayout whose
    // cells are the page's `SectionColumn` children, so the number here only says how
    // many of those to place per row. Every page's `columns` already equals its
    // SectionColumn count exactly. Raise the default and a page with one
    // SectionColumn puts all its content in the left cell and leaves the right one
    // genuinely empty, which is the same complaint with an extra step.
    //
    // A page uses the width by declaring a second SectionColumn and dividing its
    // sections between them. That is a per-page edit because WHICH sections pair is a
    // judgement — related ones should not end up in different columns.
    property int columns: 1

    // ── 360, and why it was wrong at 520 ──────────────────────────────────────
    // 520 was measured against a ~1900px window. The settings window OPENS at 1200 wide,
    // which leaves this page ~920px after the rail, the margins and the close button —
    // and 2 × 520 + gap is 1064. So every two-column page silently rendered as ONE
    // column at the size it actually opens at, which is exactly "every page is too
    // long to scroll". 360 buys two columns from ~732px up, and a row of label +
    // detail + switch still reads comfortably at that width.
    property real minColumnWidth: 360

    // ── Bento ─────────────────────────────────────────────────────────────────
    // The other way to lay out a page: instead of hand-grouped columns of stacked
    // cards, a mosaic of TILES that each declare how many columns they take. A
    // boolean is a tile you tap, a picker is a tile, and the thing the page is about
    // gets a tile the full width of the grid.
    //
    // Why it is a mode rather than the only way: a page whose content is genuinely a
    // LIST (keybinds, locales, packages) wants a column that runs, not a mosaic. Both
    // shapes share this shell, the header, the banner and the scroll.
    property bool bento: false

    // ── Grouped: a page that fills its width ──────────────────────────────────
    // A page of grouped rows (Section { grouped: true }) uses the whole width, like the island
    // dashboard: a box filled with plates of different sizes, so a page fits without scrolling
    // wherever it can. Each page picks the arrangement that suits it (`groupLayout`):
    //
    //   · "columns" (the default): groups flow across the full width into columns balanced by height
    //     (components/masonry.js: in order, each into the shortest column). Groups are not stretched
    //     to a row's height the way bento does, which would draw empty segments under a short group.
    //     A group with `Section.fullRow` (and a hero) takes the whole row above, between or below them.
    //   · "split": the hero (`Section.hero`) and any `Section.side` group stand in a LEFT column, in
    //     source order, pinned: the live preview stays in view while the groups on the right scroll
    //     (taller than the view, it scrolls on its own). The rest flow on the right as above.
    //   · Too narrow for the left column and one right column: ONE column, the left children first.
    //
    // A row of label + switch still reads as one line because a column is never wider than a few
    // hundred pixels; a row too narrow for its control stacks it under the label (SettingRow.stack).
    //
    // The children are moved out of the default slot into the two areas once the page is built
    // (_adopt). Which area a child goes to is read then, so `groupLayout`, `hero` and `side` are set
    // in the page source, not toggled later (`fullRow` may change at any time).
    property bool grouped: false
    property string groupLayout: "columns"
    // Only caps the narrow fallback's one column (and a no-hero page down to one column): a split
    // page uses the full width.
    property real groupedWidth: 720
    // The left column: this share of the page, held between these. 300 keeps a hero's big number and
    // slider readable; past 440 the hero is a banner and takes width the groups could use. Plain
    // pixels, like the other column widths here: text does not shrink with the density scale.
    property real leftShare:    0.38
    property real leftMinWidth: 300
    property real leftMaxWidth: 440
    readonly property real leftColumnWidth: Math.round(Math.max(root.leftMinWidth,
        Math.min(root.leftMaxWidth, root._fullWidth * root.leftShare)))
    // A right column is never narrower than this: a group's title, a label and a switch, with room.
    property real groupColumnMin: 340
    // Beside a hero the groups take two columns at most (four visual columns would be strips);
    // without one, three.
    property int  maxGroupColumns: root._hasLeft ? 2 : 3
    // Between columns and between stacked groups.
    property real groupGap: Tokens.spacingLg

    // A tile narrower than this is not worth the chrome around it — below ~300px a
    // label plus a state word starts eliding, which is where a grid stops helping.
    property real minTileWidth: 300

    // The gap between sections and between columns. spacingLg rather than spacingXxl:
    // the cards carry their own padding and tonal fill, so a wide gutter between them
    // was spending height and width on nothing.
    readonly property int gap: Tokens.spacingLg
    property real bodySpacing: root.gap

    // Bento derives its column count from the width alone and caps at three: past
    // that the tiles get narrower than the text in them without the page gaining
    // anything. A column page is capped by what it DECLARED, because which cards sit
    // together is a judgement the page made.
    readonly property int _cols: root.grouped ? 1
        : root.bento
        ? Math.max(1, Math.min(3,
            Math.floor((root.width + root.gap) / (root.minTileWidth + root.gap))))
        : Math.max(1, Math.min(root.columns,
            Math.floor((root.width + root.gap) / (root.minColumnWidth + root.gap))))

    // A bento takes the whole width — its tiles are the grid, so there is nothing to
    // centre. A column page stays capped and centred.
    //
    // Either way it stays `Tokens.scrollRoom` clear of each edge: the Scrollbar sits at the
    // right one, and would cover content under it.
    readonly property real _contentWidth: root.grouped
        ? (root._groupCols === 1 && !root._split ? Math.min(root._fullWidth, root.groupedWidth) : root._fullWidth)
        : root.bento
        ? root.width - Tokens.scrollRoom * 2
        : Math.min(root.width - Tokens.scrollRoom * 2,
                   root._cols * root.columnWidth + (root._cols - 1) * root.gap)

    // Everything else is a Section in the scrolling column.
    default property alias content: body.data

    // ── Grouped geometry ──────────────────────────────────────────────────────
    // All of it is read off the page's width and the children's own heights. Positions never feed
    // back into a height: a child's width comes from the column count, which comes from the width
    // alone, and the packing only reads heights.
    readonly property real _fullWidth: Math.max(0, root.width - Tokens.scrollRoom * 2)
    property var _leftKids:  []
    property var _rightKids: []
    readonly property bool _hasLeft: {
        if (!root.grouped) return false
        for (const c of root._leftKids) if (c && c.visible) return true
        return false
    }
    readonly property bool _split: root._hasLeft
        && root._fullWidth - root.leftColumnWidth - root.groupGap >= root.groupColumnMin
    // The right area's left edge, from the content's left edge.
    readonly property real _rightX: root._split ? root.leftColumnWidth + root.groupGap : 0
    readonly property int _groupCols: !root.grouped ? 1
        : root._split ? Masonry.columnsFor(root._fullWidth - root._rightX, root.groupColumnMin, root.groupGap, root.maxGroupColumns)
        : root._hasLeft ? 1
        : Masonry.columnsFor(root._fullWidth, root.groupColumnMin, root.groupGap, root.maxGroupColumns)
    readonly property real _rightWidth: root._split ? root._fullWidth - root._rightX : root._contentWidth
    readonly property real _groupColW: Masonry.columnWidth(root._rightWidth, root._groupCols, root.groupGap)
    // A hidden child (or an empty one) is 0: no place, no gap. (A child torn down with the page
    // reads null for a moment.)
    readonly property var _rightHeights: root._rightKids.map(c => c && c.visible ? c.implicitHeight : 0)
    // Which of them take a whole row: a `fullRow` group, and a hero in the flow (the loud card over
    // the columns, as on a one-column page).
    readonly property var _rightFull: root._rightKids.map(c => !!c && (c.fullRow === true || c.hero === true))
    readonly property var _flow: Masonry.pack(root._rightHeights, root._groupCols, root.groupGap, root._rightFull)

    // Moves the default slot's children into the left column or the right area. Run once the page
    // is built, and again if a child arrives later. Parent first, then geometry, each a binding.
    function _adopt() {
        if (!root.grouped) return
        const left = root._leftKids.slice()
        const right = root._rightKids.slice()
        const kids = []
        for (let i = 0; i < body.children.length; i++) kids.push(body.children[i])
        let moved = false
        const split = root.groupLayout === "split"
        for (const c of kids) {
            // BentoGrid's own anchor row and its Repeater stay where they are (only a Repeater
            // has itemAdded).
            if (c.isAnchor === true || c.itemAdded !== undefined) continue
            if (split && (c.hero === true || c.side === true)) {
                c.parent = leftCol
                c.x = 0
                c.width = Qt.binding(() => leftCol.width)
                left.push(c)
            } else {
                const idx = right.length
                c.parent = rightArea
                // From the flag, never from the packing: the packing reads this child's height.
                c.width = Qt.binding(() => root._rightFull[idx] ? root._rightWidth : root._groupColW)
                c.x = Qt.binding(() => {
                    const p = root._flow.places[idx]
                    return p && p.col > 0 ? p.col * (root._groupColW + root.groupGap) : 0
                })
                c.y = Qt.binding(() => {
                    const p = root._flow.places[idx]
                    return p ? p.y : 0
                })
                right.push(c)
            }
            // The grid may already have sized it; from here its height is its own.
            c.height = Qt.binding(() => c.implicitHeight)
            moved = true
        }
        if (!moved) return
        root._leftKids = left
        root._rightKids = right
    }
    Connections {
        target: root.grouped ? body : null
        function onChildrenChanged() { Qt.callLater(root._adopt) }
    }

    // ── Landing on a row: reveal() ────────────────────────────────────────────
    // A search result (or a link to a file folded into this page) names a card or row
    // here: UiState.settingsTarget = { section, title, kind }. reveal() finds it, scrolls
    // it to just under the top, flashes it once, and clears the target (consumed).
    //
    // Asked from onCompleted (a page loaded for the link) and on settingsTargetNav (a
    // page already on show). Either way it WAITS for a rendered frame: a bento or grouped
    // page places its cards in the layout's polish, so positions read straight after a
    // load are all 0. A frame that comes and still has no card (one built a moment later)
    // gets one more try.
    //
    // A page that is leaving (its slot is disabled while it slides out) never answers,
    // so the target is left for the page arriving.
    property int _revealTries: 0
    function reveal() {
        if (!UiState.settingsTarget || !root.enabled) return
        root._revealTries = 2
        const w = root.Window.window
        if (w) w.update()
    }
    Component.onCompleted: {
        root._adopt()
        root.reveal()
    }
    Connections {
        target: UiState
        function onSettingsTargetNavChanged() { root.reveal() }
    }
    Connections {
        target: root._revealTries > 0 ? root.Window.window : null
        function onFrameSwapped() { root._revealNow() }
    }

    function _revealNow() {
        const t = UiState.settingsTarget
        if (!t || !root.enabled) { root._revealTries = 0; return }
        const card = root._findCard(t.kind === "section" ? t.title : t.section)
        const row = t.kind === "section" ? null : root._findLabelled(card ?? flick.contentItem, t.title)
        if (!card && !row && --root._revealTries > 0) {
            const w = root.Window.window
            if (w) w.update()
            return
        }
        root._revealTries = 0
        UiState.settingsTarget = null
        const item = row ?? card
        if (!item) return

        // The rect to flash, in its own item's coordinates: a row in a grouped card is its whole
        // segment (the full card width, padded the way Section draws it); a card is itself; any
        // other row gets a little room around it.
        const seg = row && card && card._grouped ? root._segOf(card, row) : null
        const src = seg || !row ? card : row
        const lr = seg ? Qt.rect(0, seg.mapToItem(card, 0, 0).y - card._segPadY, card.width, seg.height + card._segPadY * 2)
                 : !row ? Qt.rect(0, 0, card.width, card.height)
                 : Qt.rect(-Tokens.spacingXs, -Tokens.spacingXs, row.width + Tokens.spacingXs * 2, row.height + Tokens.spacingXs * 2)

        // Which Flickable holds it. The pinned left column scrolls on its own, and only while it is
        // taller than the view; in the narrow fallback it sits in the page's scroll like the rest.
        const inLeft = root._within(item, leftFlick.contentItem)
        const scroller = !inLeft || !root._split ? flick : leftFlick.interactive ? leftFlick : null
        if (scroller) {
            // Mapped into that Flickable's content (the body already sits at -topTrim, the grid's
            // empty anchor row), so this y IS a contentY. A little room above it, clamped to what
            // can scroll.
            const sr = root._mapRect(src, lr, scroller.contentItem)
            scrollAnim.stop()
            scrollAnim.target = scroller
            scrollAnim.to = Math.max(0, Math.min(sr.y - Tokens.spacingXl, scroller.contentHeight - scroller.height))
            scrollAnim.restart()
        }

        // Drawn in the content that scrolls with the item, so it stays on it.
        const host = inLeft ? leftFlick.contentItem : flick.contentItem
        const r = root._mapRect(src, lr, host)
        flash.parent = host
        flash.x = r.x
        flash.y = r.y
        flash.width = r.width
        flash.height = r.height
        flash.radius = seg ? Tokens.radiusXl : !row ? card.cornerRadius : Tokens.radiusSm
        flashAnim.restart()
    }

    function _mapRect(from, r, to) {
        const p = from.mapToItem(to, r.x, r.y)
        return Qt.rect(p.x, p.y, r.width, r.height)
    }
    function _within(it, ancestor) {
        for (let p = it; p; p = p.parent) if (p === ancestor) return true
        return false
    }

    // A Section is told apart by what only it declares (its segment padding and card
    // corner), not by type: components have no type test in JS.
    function _isCard(it) { return it._segPadY !== undefined && it.cornerRadius !== undefined && it.title !== undefined }
    // The index holds the English source text; on screen it may be translated.
    function _same(text, want) { return typeof text === "string" && text !== "" && (text === want || text === Translation.tr(want)) }
    // A control is found by the props the index reads its title from (build-settings-index.py).
    function _labelled(it, want) {
        return root._same(it.label, want) || root._same(it.title, want)
            || root._same(it.accessibleName, want) || root._same(it.placeholder, want)
    }

    // The first shown Section titled `title`, depth first through the page's content (the body,
    // or a grouped page's two areas).
    function _findCard(title) {
        if (!title) return null
        const walk = function (it) {
            for (let i = 0; i < it.children.length; i++) {
                const c = it.children[i]
                if (!c.visible) continue
                if (root._isCard(c) && root._same(c.title, title)) return c
                const f = walk(c)
                if (f) return f
            }
            return null
        }
        return walk(flick.contentItem)
    }
    // The first shown control under `from` whose label is `title` (not `from` itself).
    function _findLabelled(from, title) {
        const walk = function (it) {
            for (let i = 0; i < it.children.length; i++) {
                const c = it.children[i]
                if (!c.visible) continue
                if (root._labelled(c, title)) return c
                const f = walk(c)
                if (f) return f
            }
            return null
        }
        return walk(from)
    }
    // The body child of a grouped card that holds `row` (its segment), or null.
    function _segOf(card, row) {
        for (let it = row; it && it !== card; it = it.parent)
            if (card._segs.indexOf(it) >= 0) return it
        return null
    }

    NumberAnimation {
        id: scrollAnim
        target: flick
        property: "contentY"
        duration: Motion.standard
        easing.type: Motion.travel
    }

    // Up, a beat, and gone: one pass, nothing left running.
    SequentialAnimation {
        id: flashAnim
        NumberAnimation { target: flash; property: "opacity"; to: Tokens.stateFocus; duration: Motion.standard; easing.type: Motion.enter }
        PauseAnimation  { duration: Motion.emphasized }
        NumberAnimation { target: flash; property: "opacity"; to: 0; duration: Motion.slow; easing.type: Motion.exitCurve }
    }

    // ── ONE source of the gutter, read off the page's own width ───────────────
    // Every centred thing on the page measures from this. It depends only on the
    // page's width — which anchors give it, top-down — so nothing here can ask a
    // layout how wide it is in order to decide how wide it should be.
    //
    // The first version computed the banner's margin from that layout's OWN width,
    // which is a binding loop — same class of re-entrancy as CavaBG.suppressed, and
    // worth not having. It was NOT, however, what broke the layout: that was the
    // fillHeight default documented below. Recorded because the two look alike and
    // the loop was a confident wrong answer once already.
    readonly property real _gutter: Math.max(0, (root.width - root._contentWidth) / 2)

    ColumnLayout {
        anchors.fill: parent
        spacing: Tokens.spacingLg

        // Capped and centred to the SAME width as the body, by the same margins.
        // Left full width it starts at the far left while the sections start at the
        // gutter, and the page reads as two things that failed to line up.
        // ── `Layout.fillHeight: false` here is LOAD-BEARING ───────────────────
        // A Layout nested in another Layout defaults BOTH fill flags to true — the
        // same rule SoundPage's header records for fillWidth ("load-bearing, not
        // redundant… do not tidy these away"). PanelHeader is a RowLayout and the
        // banner is a ColumnLayout, so inside this ColumnLayout each of them silently
        // claimed vertical fill and split the page's surplus with the scroll area.
        //
        // That is what put ~450px of nothing between the rule and the first section:
        // ~920px of page, less the header, rule and spacing, halved between the empty
        // banner and the body. It is invisible in the source, produces no warning, and
        // survived one wrong diagnosis (a binding loop, which was also real but was not
        // this). Both flags stay explicit.
        PanelHeader {
            // `id` is load-bearing: `property alias actions` above points at it. It was
            // dropped along with a wrapper Item during a refactor, which made the alias
            // unresolvable — and an invalid alias is a HARD LOAD FAILURE of the whole
            // component, so every page using SettingsPage went "Type unavailable" at
            // once. Nothing static catches it; the parse check passes cleanly.
            id: headerRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin:  root._gutter
            Layout.rightMargin: root._gutter
            glyph:     root.glyph
            title:     root.title
            titleTail: root.titleTail
            subtitle:  root.subtitle
            accent:    root.accent
            morph:     root._headerShape
            chipSize:  Tokens.iconXl + Tokens.spacingLg
            titleVariant: "headline"
            subtitleVariant: "label"
        }

        // No rule under the header: the panels' headers have none, and the cards below
        // are the separation.

        ColumnLayout {
            id: bannerCol
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.leftMargin:  root._gutter
            Layout.rightMargin: root._gutter
            spacing: Tokens.spacingMd
            // Most pages never set `banner`; an empty layout should contribute nothing,
            // and taking it out of the layout entirely is the cheapest way to be sure.
            //
            // And a banner that is there but has nothing to say (an UndoBar between
            // undos is 0 tall) must not count either: an empty-but-visible slot still
            // pays the column's spacing, and those pages started 12px lower than the
            // rest. Read off the children's IMPLICIT height, which does not depend on
            // this layout being visible, so hiding it can't hide the reason to show it.
            visible: {
                for (let i = 0; i < bannerCol.children.length; i++)
                    if (bannerCol.children[i].implicitHeight > 0) return true
                return false
            }
        }

        // Plain Item around the Flickable: Scrollbar reparents itself to
        // flickable.parent and anchors across it, so that parent must not be a Layout.
        Item {
            id: scrollHost
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: flick
                anchors.fill: parent
                contentWidth:  width
                // A packed grid starts with an empty row of column anchors (BentoGrid);
                // the body is offset up by it, so the content is that much shorter.
                // Grouped: the right area's bottom (the pinned left column scrolls on its own).
                contentHeight: root.grouped ? rightArea.y + rightArea.height
                                            : body.implicitHeight - body.topTrim
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // A BentoGrid, not a bare GridLayout: in bento mode it fills every row
                // (a lone tile, a card that wouldn't squeeze in) instead of leaving the
                // empty space a grid leaves when it wraps. Otherwise it IS a bare grid.
                // The deep-link flash (reveal()): one rectangle over whatever was named, in the
                // content so it scrolls with it. Drawn above the cards, never in the way of a click.
                Rectangle {
                    id: flash
                    z: 1
                    opacity: 0
                    visible: opacity > 0
                    color: Colors.of(QsWindow.window).primary
                }

                BentoGrid {
                    id: body
                    // Positioned, not margined: this one is not in a layout, so it
                    // sets its own geometry. y is the grid's own top gap (its anchor
                    // row — see BentoGrid.topTrim), negated so the content starts at 0.
                    y: -body.topTrim
                    x: root._gutter
                    width: root._contentWidth

                    pack: root.bento && !root.grouped
                    bentoCols: root._cols
                    columnSpacing: root.gap
                    rowSpacing:    root.bodySpacing
                }

                // ── Grouped: the right area ───────────────────────────────────
                // Children placed by _adopt from the packing; nothing here lays them out.
                Item {
                    id: rightArea
                    visible: root.grouped
                    x: root._gutter + root._rightX
                    // Under the left column's children in the narrow fallback.
                    y: root._hasLeft && !root._split && leftCol.height > 0 ? leftCol.height + root.groupGap : 0
                    width: root._rightWidth
                    height: root.grouped ? root._flow.total : 0
                }

                // ── Grouped: the left column ──────────────────────────────────
                // Inside the page's content so a wheel over it scrolls the page while it fits, and held
                // at the top of the view (y follows contentY) so it does not move. A plain Item holds its
                // own Flickable and Scrollbar (the Scrollbar anchors to its Flickable's parent). Its
                // width runs into the gap, where that Scrollbar sits clear of the hero.
                Item {
                    id: leftHost
                    // Not gated on _hasLeft: that reads its children's `visible`, which a hidden
                    // host would turn false for good. Empty, it is 0 tall.
                    visible: root.grouped
                    x: root._gutter
                    y: root._split ? flick.contentY : 0
                    width: root._split ? root.leftColumnWidth + root.groupGap : root._contentWidth
                    height: root._split ? Math.min(leftCol.height, flick.height) : leftCol.height

                    Flickable {
                        id: leftFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: leftCol.height
                        clip: root._split
                        boundsBehavior: Flickable.StopAtBounds
                        interactive: root._split && leftCol.height > flick.height + 1
                        onInteractiveChanged: if (!interactive) contentY = 0

                        // A positioner, not a layout: it skips hidden children (no space, no gap) and
                        // leaves their Layout.* alone.
                        Column {
                            id: leftCol
                            width: root._split ? root.leftColumnWidth : root._contentWidth
                            spacing: root.groupGap
                        }
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        width: leftCol.width
                        height: Tokens.spacingXl + Tokens.spacingMd
                        opacity: leftFlick.interactive && leftFlick.contentY + leftFlick.height < leftFlick.contentHeight - 2 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(scrollHost._ground, 0) }
                            GradientStop { position: 1.0; color: scrollHost._ground }
                        }
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        width: leftCol.width
                        height: Tokens.spacingLg
                        opacity: leftFlick.interactive && leftFlick.contentY > 2 ? 1 : 0
                        visible: opacity > 0.01
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: scrollHost._ground }
                            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(scrollHost._ground, 0) }
                        }
                    }

                    Scrollbar {
                        flickable: leftFlick
                        wheelStep: Math.max(Tokens.spacingXl * 4, Math.round(leftFlick.height / 4))
                    }
                }
            }

            // ── There is more ─────────────────────────────────────────────────
            // Without it a page that runs past the window just stops at its edge, a card cut
            // in half. The rim fades into the card's own colour while there is more to scroll
            // to in that direction (and not otherwise), so the edge reads as "continues".
            // The colour behind the page: the card's own fill, or the frame's while the card is
            // welded into it (Config.settingsPanel).
            readonly property color _ground: Config.settingsPanel ? Colors.of(QsWindow.window).frameFill
                                                                  : Colors.of(QsWindow.window).surface
            // Split, they cover the right area only: the pinned left column does not scroll with it.
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: root._split ? root._gutter + root._rightX : 0
                height: Tokens.spacingXl + Tokens.spacingMd
                opacity: flick.contentHeight > flick.height + 2
                         && flick.contentY + flick.height < flick.contentHeight - 2 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(scrollHost._ground, 0) }
                    GradientStop { position: 1.0; color: scrollHost._ground }
                }
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: root._split ? root._gutter + root._rightX : 0
                height: Tokens.spacingLg
                opacity: flick.contentY > 2 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: scrollHost._ground }
                    GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(scrollHost._ground, 0) }
                }
            }

            // A notch moves a quarter of what you can see (never less than the default):
            // the fixed step Scrollbar defaults to is too little per notch on the long pages,
            // where a page five screens tall took dozens.
            Scrollbar {
                flickable: flick
                wheelStep: Math.max(Tokens.spacingXl * 4, Math.round(flick.height / 4))
            }
        }
    }
}
