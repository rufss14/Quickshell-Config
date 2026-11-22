import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../state"

// ── Section ───────────────────────────────────────────────────────────────────
// A titled group inside a page: an icon chip and a heading, then the rows — all in one
// card.
//
// ── The panels' card ──────────────────────────────────────────────────────────
// A flat `section` fill, no outline, no cast shadow, no hover lift: the same container the
// Colours, Clock and Media panels put behind a group of controls. Not an outlined, shadowed
// card that lifts under the pointer with a scalloped chip: that is a dialect of its own, and
// the settings app sits next to panels that speak this one. The life is in the controls, in
// the page arriving (below) and in a soft light that follows the pointer (PointerGlow). No
// shadow also means no ~130 SurfaceShadows on a page switch.
//
// The icon chip is PanelHeader's (ShapeBox: a rounded square unless Config.iconShape picks
// one shape for every holder), so a card heading and a panel heading read as one thing. It is
// TONAL (M3E): the accent's container with the on-container glyph, no outline.
//
// ── The heading sits INSIDE the card ──────────────────────────────────────────
// The title and the rows it introduces are one object that scrolls, elides and is bounded
// together. The heading outranks a row by WEIGHT (title, DemiBold) rather than by position.
//
// ── Arriving ──────────────────────────────────────────────────────────────────
// When the card was created by a view change (UiState.settingsCascade), it rises and fades
// in a few frames after the card before it — capped at six, so a page of twenty is not a
// queue. The page a window OPENS on appears at once. `ViewEnter` makes motion-off an
// instant swap.
//
// `padding` and `bodySpacing` are the card's internals, exposed because a section whose
// whole body is one preview canvas wants tighter padding than one holding eight rows.
//
// ── Grouped rows (opt-in, `grouped: true`) ────────────────────────────────────
// Material 3 Expressive's grouped list. No card behind the section: the title row stands on the
// ground (a small MorphShape badge, the title, the subtitle as a state note at the right, then
// `actions`), and every VISIBLE child of the body sits on a tonal segment of its own, a hairline
// apart, the group's outer corners large and the inner ones small. A child that offers `segPressed`
// (SettingRow with `rowTap`) rounds its segment's inner corners and dips it while pressed; one that
// offers `segHovered` / `segFocused` gets the wash and the focus ring in the segment's shape.
// Segments follow the children's own y and height, so a child that hides or grows moves them.
//
// ── The loud card (opt-in, `hero: true`) ──────────────────────────────────────
// The one primaryContainer card of a page. Children draw in `ink` / `inkDim` themselves. On a
// "split" grouped page it stands in the pinned left column (`side` puts a group under it); on a
// "columns" one it takes the row above the columns.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string glyph:    ""
    // A Material Symbols name; wins over `glyph`.
    property string symbol:   ""
    property string title:    ""
    property string subtitle: ""
    // The sentence that explains the card, shown in a tip when the pointer rests on
    // its heading (HelpTip). The subtitle is for a short STATE, not this.
    property string help:     ""

    property color accent: Colors.of(QsWindow.window).primary

    // Nested (the default) is the panels' section fill. Card is a well INSIDE another card
    // (a preview's ground); popup is the one that needs an outline to hold against a card.
    property int  elevation:   Tokens.elevationNested
    property int  padding:     Tokens.spacingLg
    property real bodySpacing: Tokens.spacingMd
    property bool fillBody: false
    // A warning card (blocker, lock-out risk) wears its own outline.
    property color cardBorder: "transparent"

    // Large corners, the Material 3 Expressive card. (A well inside a card, or a warning card, sets its own.)
    property int cornerRadius: Tokens.radiusXl
    // The accent is the palette's own primary, so the heading chip can wear its container role.
    readonly property bool tonalAccent: Qt.colorEqual(root.accent, Colors.of(QsWindow.window).primary)

    property alias actions: actionRow.data
    default property alias content: bodyCol.data

    property bool grouped: false
    property bool hero: false
    // On a grouped page laid out as "split" (SettingsPage.groupLayout), this group stands in the
    // pinned left column under the hero instead of flowing with the others on the right: for a
    // small group that belongs with the live preview (its master options), so both stay in view.
    property bool side: false
    // On a grouped page, this group takes the whole row above, between or below the balanced
    // columns: for a wide card (a picker, a list) that a column would squeeze. A hero in the flow
    // does this anyway.
    property bool fullRow: false
    // The grouped title badge's shape (components/shapes.js). Left empty, chosen by the title, so
    // sibling groups wear different ones and the same group always the same.
    property string shape: ""
    readonly property var _shapes: ["cookie9", "sunny", "clover", "squircle", "hexagon", "pentagon", "cookie6", "cookie4"]
    readonly property string _shape: {
        if (root.shape !== "") return root.shape
        let h = 0
        for (let i = 0; i < root.title.length; i++) h = (h * 31 + root.title.charCodeAt(i)) % 997
        return root._shapes[h % root._shapes.length]
    }
    // What a hero's children draw in.
    readonly property color ink:    Colors.of(QsWindow.window).fgOnPrimaryContainer
    readonly property color inkDim: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fgOnPrimaryContainer, 0.72)

    readonly property bool _grouped: root.grouped && !root.hero
    readonly property int  _pad: root._grouped ? 0 : root.padding
    // How far a segment runs past its child: room for the row to breathe.
    readonly property int  _segPadX: Tokens.spacingLg
    readonly property int  _segPadY: Tokens.spacingMd

    // The body's visible children, in order: one segment each. Read off `visible` (and a zero
    // height, which a Repeater or an empty slot has), so a child that hides takes its segment along.
    readonly property var _segs: {
        if (!root._grouped) return []
        const out = []
        const kids = bodyCol.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (c.visible && (c.implicitHeight > 0 || c.height > 0)) out.push(c)
        }
        return out
    }
    // A child that can answer for its whole segment learns how far the segment runs past it.
    function _adopt() {
        for (const c of root._segs) {
            if (c.segInsetX !== undefined && c.segInsetX !== root._segPadX)
                c.segInsetX = Qt.binding(() => root._segPadX)
            if (c.segInsetY !== undefined && c.segInsetY !== root._segPadY)
                c.segInsetY = Qt.binding(() => root._segPadY)
        }
    }
    on_SegsChanged: root._adopt()

    // How many columns of a bento grid this card takes (SettingsPage.bento). One
    // outside a bento page, where the grid's cells are whole columns already.
    property int span: 1

    // In a BentoGrid the grid fills its rows (it widens this card until the row is
    // flush) and the card stretches to the row's height, so a short card beside a tall
    // one has the same edges instead of floating at the top with a hole under it. Any
    // other parent keeps the old behaviour.
    readonly property bool _packed: !!(root.parent && root.parent.pack === true)
    Layout.columnSpan: (root.parent && root.parent.spanFor)
        ? root.parent.spanFor(root)
        : Math.min(root.span, (root.parent && root.parent.columns) ? root.parent.columns : 1)

    Layout.fillWidth: true
    // Packed items split a row by their span alone, not by how wide their text is.
    Layout.preferredWidth: root._packed ? 0 : -1
    Layout.fillHeight: root.fillBody || root._packed
    Layout.alignment: (root.fillBody || root._packed) ? 0 : Qt.AlignTop

    // The root is still a ColumnLayout holding exactly one card, rather than simply
    // BEING the card: sixteen pages set `Layout.*` on a Section and a handful nest one
    // inside another layout.
    spacing: 0

    // ── Arriving ──────────────────────────────────────────────────────────────
    // This card's place among its siblings, for the stagger. Counted once, when it is
    // made: anything before it that is shown and is not a grid anchor.
    function _place() {
        const p = root.parent
        if (!p) return 0
        let n = 0
        for (let i = 0; i < p.children.length; i++) {
            const c = p.children[i]
            if (c === root) break
            if (c.visible && c.isAnchor !== true && c.implicitHeight > 0) n++
        }
        return n
    }
    property bool _arrive: false
    Component.onCompleted: {
        root._adopt()
        if (!UiState.settingsCascade) return
        card.opacity = 0
        enter.delay = Math.min(root._place(), 5) * Motion.stagger * 2
        Qt.callLater(function () { root._arrive = true })
    }
    ViewEnter { id: enter; target: card; active: root._arrive; rise: Tokens.spacingMd }

    Rectangle {
        id: card
        Layout.fillWidth: true
        Layout.fillHeight: root.fillBody || root._packed

        radius: root.cornerRadius
        color: root.hero                                ? Colors.of(QsWindow.window).primaryContainer
             : root._grouped                            ? "transparent"
             : root.elevation >= Tokens.elevationPopup ? Colors.of(QsWindow.window).surfaceFor(root.elevation)
             : root.elevation <= Tokens.elevationCard  ? Colors.of(QsWindow.window).surface
             :                                           Colors.of(QsWindow.window).section
        border.width: (root.cardBorder.a > 0 || root.elevation >= Tokens.elevationPopup) ? Tokens.borderWidth : 0
        border.color: root.cardBorder.a > 0 ? root.cardBorder : Colors.of(QsWindow.window).outlineFor(root.elevation)

        implicitHeight: cardCol.implicitHeight + root._pad * 2

        // ── The one thing that answers the pointer ────────────────────────────
        // No lift, no outline — but a soft light follows the pointer across the card and
        // catches the edge nearest it, so a page of flat cards still feels alive under the
        // hand. Reads this HoverHandler instead of adding its own; draws nothing at rest.
        HoverHandler { id: cardHover; enabled: root.enabled }
        PointerGlow {
            hover:  cardHover
            color:  root.accent
            radius: card.radius
            fillStrength: 0.05
            edgeStrength: 0.38
            // A grouped section has no card for the light to cross.
            enabled: root.enabled && !root._grouped
            visible: !root._grouped
        }

        // ── The segments (grouped) ────────────────────────────────────────────
        // Under the content, one per visible body child. The model is a COUNT and each segment
        // reads its child by index, so a child growing or moving re-binds geometry without
        // rebuilding segments (a new array as the model would rebuild them all).
        Repeater {
            model: root._segs.length
            delegate: Rectangle {
                id: seg
                required property int index
                readonly property var kid: root._segs[seg.index] ?? null
                readonly property bool firstSeg: seg.index === 0
                readonly property bool lastSeg:  seg.index === root._segs.length - 1
                readonly property bool segDown:  !!seg.kid && seg.kid.segPressed === true
                readonly property bool segOver:  !!seg.kid && seg.kid.segHovered === true
                readonly property bool segFocus: !!seg.kid && seg.kid.segFocused === true

                // Pressed, the inner corners round up toward the outer ones and the segment dips.
                SpringValue { id: roundK; target: seg.segDown ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }
                SpringValue { id: dip; target: seg.segDown ? 0.98 : 1; spec: Motion.springSpatialFast; epsilon: 0.0005 }
                readonly property real innerR: Math.max(0, Math.min(seg.height / 2,
                    Tokens.radiusXs + roundK.value * (Tokens.radiusXl - Tokens.radiusXs)))
                readonly property real topR:    seg.firstSeg ? Tokens.radiusXl : seg.innerR
                readonly property real bottomR: seg.lastSeg  ? Tokens.radiusXl : seg.innerR

                x: 0
                width: card.width
                y: seg.kid ? cardCol.y + bodyCol.y + seg.kid.y - root._segPadY : 0
                height: seg.kid ? seg.kid.height + root._segPadY * 2 : 0
                scale: dip.value

                color: Colors.of(QsWindow.window).section
                topLeftRadius:     seg.topR
                topRightRadius:    seg.topR
                bottomLeftRadius:  seg.bottomR
                bottomRightRadius: seg.bottomR

                StateLayer {
                    anchors.fill: parent
                    hovered: seg.segOver
                    topLeftRadius:     seg.topR
                    topRightRadius:    seg.topR
                    bottomLeftRadius:  seg.bottomR
                    bottomRightRadius: seg.bottomR
                }
                // Keyboard focus on the child's row: a ring in the segment's own shape.
                Rectangle {
                    anchors.fill: parent
                    visible: seg.segFocus
                    color: "transparent"
                    border.width: Tokens.borderWidth * 2
                    border.color: Colors.of(QsWindow.window).outlineFocus
                    topLeftRadius:     seg.topR
                    topRightRadius:    seg.topR
                    bottomLeftRadius:  seg.bottomR
                    bottomRightRadius: seg.bottomR
                }
            }
        }

        ColumnLayout {
            id: cardCol

            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.bottom: root.fillBody ? parent.bottom : undefined
            anchors.margins: root._pad

            // Deliberately NOT `bodySpacing`: the gap between a heading and the rows
            // it introduces is structural, and a section that tightens its row spacing
            // for density should not also pull its title down onto the first row.
            spacing: Tokens.spacingMd

            // ── Heading ───────────────────────────────────────────────────────
            // Hides itself when `title` and every icon are empty — blockers and error
            // cards, where an "Error" heading would only restate the icon.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                // Grouped, the title row lines up with the rows' text inside their segments.
                Layout.leftMargin:  root._grouped ? root._segPadX : 0
                Layout.rightMargin: root._grouped ? root._segPadX : 0
                visible: root.title !== "" || root.glyph !== "" || root.symbol !== ""
                spacing: root._grouped ? Tokens.spacingSm : Tokens.spacingMd

                // Grouped: a small shape badge on the ground (WallpaperMaterialPlate's title row).
                Item {
                    visible: root._grouped && (root.glyph !== "" || root.symbol !== "")
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth:  Tokens.iconXl - Tokens.spacingSm
                    Layout.preferredHeight: Tokens.iconXl - Tokens.spacingSm
                    MorphShape {
                        anchors.fill: parent
                        shape: root._shape
                        fillColor: root.tonalAccent ? Colors.of(QsWindow.window).primaryContainer
                                                    : Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.26)
                    }
                    MaterialIcon {
                        anchors.centerIn: parent
                        name:  root.symbol
                        glyph: root.glyph
                        fill: 1
                        font.pixelSize: Tokens.iconSm
                        color: root.tonalAccent ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.accent
                    }
                }

                // A FIXED box, so every heading starts at the same place and reads at the
                // same weight whichever glyph it carries. Fill and stroke are PanelHeader's.
                ShapeBox {
                    Layout.alignment: Qt.AlignVCenter
                    visible: !root._grouped && (root.glyph !== "" || root.symbol !== "")
                    implicitWidth:  Tokens.iconXl + Tokens.spacingSm
                    implicitHeight: Tokens.iconXl + Tokens.spacingSm
                    fallback:    "rounded"
                    // Tonal (Material 3 Expressive): the accent's container, not a wash and an outline. For the
                    // default accent that IS the palette's primaryContainer; a warning card mixes its own the same way.
                    fillColor:   root.tonalAccent ? Colors.of(QsWindow.window).primaryContainer
                                                  : Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, root.accent, 0.26)

                    MaterialIcon {
                        anchors.centerIn: parent
                        name:  root.symbol
                        glyph: root.glyph
                        color: root.tonalAccent ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.accent
                        variant: "title"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    HelpTip { id: headTip; text: root.help }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        StyledText {
                            Layout.fillWidth: true
                            Layout.maximumWidth: Math.ceil(implicitWidth)
                            text:    root.title
                            variant: root._grouped ? "label" : "title"
                            font.weight: Font.DemiBold
                            color:   root.hero ? root.ink : Colors.of(QsWindow.window).fg
                            elide:   Text.ElideRight
                        }
                        // There is more to read: shown only while the pointer rests
                        // on a heading that has `help`.
                        MaterialIcon {
                            visible: root.help !== ""
                            name: "info"
                            color: Colors.of(QsWindow.window).fgDim
                            font.pixelSize: Tokens.iconSm
                            opacity: headTip.active ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
                        }
                        Item { Layout.fillWidth: true }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible:  !root._grouped && root.subtitle !== ""
                        text:     root.subtitle
                        variant:  "caption"
                        color:    root.hero ? root.inkDim : Colors.of(QsWindow.window).fgDim
                        wrapMode: Text.WordWrap
                    }
                }

                // Grouped: the subtitle is a short state note at the right of the title.
                StyledText {
                    visible:  root._grouped && root.subtitle !== ""
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: Math.ceil(implicitWidth)
                    text:     root.subtitle
                    variant:  "caption"
                    emphasis: "dim"
                    elide:    Text.ElideRight
                }

                // A RowLayout, so `actions:` takes a JS array for more than one button
                // and they lay out properly rather than stacking at 0,0.
                RowLayout {
                    id: actionRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingXs
                }
            }

            // Grouped, the body is inset by the segments' padding, and its spacing is that padding
            // twice plus the hairline gap between two segments.
            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                Layout.fillHeight: root.fillBody
                Layout.leftMargin:   root._grouped ? root._segPadX : 0
                Layout.rightMargin:  root._grouped ? root._segPadX : 0
                Layout.topMargin:    root._grouped ? root._segPadY : 0
                Layout.bottomMargin: root._grouped ? root._segPadY : 0
                spacing: root._grouped ? Tokens.spacingXs + root._segPadY * 2 : root.bodySpacing
            }
        }
    }
}
