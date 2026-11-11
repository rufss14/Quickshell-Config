import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

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
// Settings used to be a card of exactly known size — the pages carry comments
// asserting "the page is 1510 × 952" and pin columns against it. It is a resizable
// window now, so there is no such number: it can be 900px wide or fullscreen on an
// ultrawide. Filling that width edge-to-edge puts a toggle's label at the far left
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
    // It was one centred column capped at 760. That read well but was wrong for a
    // resizable window in the way that actually matters: on a 1900px screen it left
    // ~450px of nothing down each side and made every page tall enough to scroll.
    // Sound was six sections in a single file — a page that used to be three columns
    // and fitted.
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
    readonly property int _cols: root.bento
        ? Math.max(1, Math.min(3,
            Math.floor((root.width + root.gap) / (root.minTileWidth + root.gap))))
        : Math.max(1, Math.min(root.columns,
            Math.floor((root.width + root.gap) / (root.minColumnWidth + root.gap))))

    // A bento takes the whole width — its tiles are the grid, so there is nothing to
    // centre. A column page stays capped and centred.
    //
    // Either way it stays `Tokens.scrollRoom` clear of each edge: the Scrollbar sits at the
    // right one, and content under it was covered (2026-10-31).
    readonly property real _contentWidth: root.bento
        ? root.width - Tokens.scrollRoom * 2
        : Math.min(root.width - Tokens.scrollRoom * 2,
                   root._cols * root.columnWidth + (root._cols - 1) * root.gap)

    // Everything else is a Section in the scrolling column.
    default property alias content: body.data

    // Bring one item of the body to the top of the view — a composed page jumping to
    // the group a deep link named (UiState.settingsGroup). Eased, so the page reads as
    // moving to it rather than being somewhere else.
    function scrollToItem(item) {
        if (!item) return
        const y = item.mapToItem(body, 0, 0).y
        scrollAnim.to = Math.max(0, Math.min(y, flick.contentHeight - flick.height))
        scrollAnim.restart()
    }

    NumberAnimation {
        id: scrollAnim
        target: flick
        property: "contentY"
        duration: Motion.standard
        easing.type: Motion.travel
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
                contentHeight: body.implicitHeight - body.topTrim
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // A BentoGrid, not a bare GridLayout: in bento mode it fills every row
                // (a lone tile, a card that wouldn't squeeze in) instead of leaving the
                // empty space a grid leaves when it wraps. Otherwise it IS a bare grid.
                BentoGrid {
                    id: body
                    // Positioned, not margined: this one is not in a layout, so it
                    // sets its own geometry. y is the grid's own top gap (its anchor
                    // row — see BentoGrid.topTrim), negated so the content starts at 0.
                    y: -body.topTrim
                    x: root._gutter
                    width: root._contentWidth

                    pack: root.bento
                    bentoCols: root._cols
                    columnSpacing: root.gap
                    rowSpacing:    root.bodySpacing
                }
            }

            // ── There is more ─────────────────────────────────────────────────
            // A page that runs past the window used to just stop at its edge, a card cut in
            // half. The rim fades into the card's own colour while there is more to scroll
            // to in that direction (and not otherwise), so the edge reads as "continues".
            // The colour behind the page: the card's own fill, or the frame's while the card is
            // welded into it (Config.settingsPanel).
            readonly property color _ground: Config.settingsPanel ? Colors.of(QsWindow.window).frameFill
                                                                  : Colors.of(QsWindow.window).surface
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
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
            // the fixed step Scrollbar defaults to was "too little per notch" on the long
            // pages (the user, 2026-11-08) — a page five screens tall took dozens.
            Scrollbar {
                flickable: flick
                wheelStep: Math.max(Tokens.spacingXl * 4, Math.round(flick.height / 4))
            }
        }
    }
}
