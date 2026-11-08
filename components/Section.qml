import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"
import "../state"

// ── Section ───────────────────────────────────────────────────────────────────
// A titled group inside a page: an icon chip and a heading, then the rows — all in one
// card.
//
// ── The panels' card (2026-10-26) ─────────────────────────────────────────────
// A flat `section` fill, no outline, no cast shadow, no hover lift: the same container the
// Colours, Clock and Media panels put behind a group of controls. It was an outlined,
// shadowed card that lifted 2px under the pointer, with a scalloped chip; that was the
// settings app's own dialect, and the app sat next to three panels in another one. The
// life moved to the controls, to the page arriving (below) and to a soft light that follows
// the pointer (PointerGlow). Dropping the shadow also drops ~130 SurfaceShadows from a
// page-switch.
//
// The icon chip is PanelHeader's (ShapeBox: a rounded square unless Config.iconShape picks
// one shape for every holder), so a card heading and a panel heading read as one thing.
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

    property int cornerRadius: Tokens.radiusCard

    property alias actions: actionRow.data
    default property alias content: bodyCol.data

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
        color: root.elevation >= Tokens.elevationPopup ? Colors.of(QsWindow.window).surfaceFor(root.elevation)
             : root.elevation <= Tokens.elevationCard  ? Colors.of(QsWindow.window).surface
             :                                           Colors.of(QsWindow.window).section
        border.width: (root.cardBorder.a > 0 || root.elevation >= Tokens.elevationPopup) ? Tokens.borderWidth : 0
        border.color: root.cardBorder.a > 0 ? root.cardBorder : Colors.of(QsWindow.window).outlineFor(root.elevation)

        implicitHeight: cardCol.implicitHeight + root.padding * 2

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
            enabled: root.enabled
        }

        ColumnLayout {
            id: cardCol

            anchors.left:   parent.left
            anchors.right:  parent.right
            anchors.top:    parent.top
            anchors.bottom: root.fillBody ? parent.bottom : undefined
            anchors.margins: root.padding

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
                visible: root.title !== "" || root.glyph !== "" || root.symbol !== ""
                spacing: Tokens.spacingMd

                // A FIXED box, so every heading starts at the same place and reads at the
                // same weight whichever glyph it carries. Fill and stroke are PanelHeader's.
                ShapeBox {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.glyph !== "" || root.symbol !== ""
                    implicitWidth:  Tokens.iconXl + Tokens.spacingSm
                    implicitHeight: Tokens.iconXl + Tokens.spacingSm
                    fallback:    "rounded"
                    fillColor:   Colors.of(QsWindow.window).alpha(root.accent, 0.20)
                    strokeColor: Colors.of(QsWindow.window).alpha(root.accent, 0.32)

                    MaterialIcon {
                        anchors.centerIn: parent
                        name:  root.symbol
                        glyph: root.glyph
                        color: root.accent
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
                            variant: "title"
                            font.weight: Font.DemiBold
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
                        visible:  root.subtitle !== ""
                        text:     root.subtitle
                        variant:  "caption"
                        emphasis: "dim"
                        wrapMode: Text.WordWrap
                    }
                }

                // A RowLayout, so `actions:` takes a JS array for more than one button
                // and they lay out properly rather than stacking at 0,0.
                RowLayout {
                    id: actionRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingXs
                }
            }

            ColumnLayout {
                id: bodyCol
                Layout.fillWidth: true
                Layout.fillHeight: root.fillBody
                spacing: root.bodySpacing
            }
        }
    }
}
