import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── HeroCard ──────────────────────────────────────────────────────────────────
// The big visual at the top of a settings page: a preview on a recessed stage,
// with its title and controls reading as attached to it.
//
// ── Why this is not just a Section with a preview inside it ───────────────────
// It was, on every page that had a preview at all, and that is the problem. A
// Section's rhythm is heading-then-rows: the heading announces a group and the rows
// under it are peers. Put a preview in that shape and it becomes one setting among
// eight — the same card, the same corner, the same tone as "Roundness" sitting below
// it — when it is actually the SUBJECT of the page and every row is a control on it.
//
// So the arrangement inverts. Three differences, each doing a job:
//
//   1. The picture is on a RECESSED stage — a darker inner surface, cut into the
//      card rather than sitting on it. That is what makes a preview read as a window
//      into something else rather than as an image pasted onto a panel. It also gives
//      the preview a defined edge: a preview that draws a whole scene needs a frame
//      around it, or the picture bleeds into the card behind it.
//
//   2. The heading sits BELOW the stage, not above it. A title above a picture is a
//      caption you read before you have looked, which is backwards — the picture is
//      the fastest thing on the page to understand. Reading order here is: see it,
//      then find out what it is called, then reach for the controls.
//
//   3. `footer` is a control strip INSIDE the card, under the heading. That is what
//      "the controls read as attached to the preview" means concretely — the two or
//      three switches that change what you are looking at live in the same object,
//      instead of being the first rows of a separate card further down the page.
//      Everything else still belongs in ordinary Sections.
//
// ── It spans the page ─────────────────────────────────────────────────────────
// A hero in one column of a two-column grid is a hero at half size. Pages put this
// in its own full-width SectionColumn with `Layout.columnSpan` set — see BarPage.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    property string glyph:    ""
    property string title:    ""
    property string subtitle: ""

    // `focus` — identity, not an invitation to act. Same choice Section and
    // PanelHeader make, for the same reason.
    property color accent: Colors.of(QsWindow.window).primary

    // The card floats above the page rather than being nested in it. This is the
    // one surface on a settings page that is allowed to cast: it is the page's
    // subject, and elevation is how a surface says so.
    property int elevation: Tokens.elevationCard

    property int padding: Tokens.spacingXl

    // ── The stage ─────────────────────────────────────────────────────────────
    // Left at 0 the stage is as tall as whatever is in it, which is what a preview
    // that derives its own height from its width (a scene at a fixed aspect ratio)
    // wants. Set it for content that has no opinion — a swatch, a gauge.
    property real stageHeight: 0

    // How much air between the stage's edge and the thing on it. Generous by
    // default: the inset is what makes it read as a stage rather than as a border.
    property real stageInset: Tokens.spacingLg

    // Some previews ARE their own frame — a wallpaper thumbnail, a screenshot — and
    // a recessed plate behind them is then a second rectangle around the first one.
    property bool stageVisible: true

    // ── Heading above the content instead of below it ─────────────────────────
    // The default puts it below, and the reasoning for that holds for a PICTURE: a
    // title above an image is a caption you read before you have looked, and the
    // image is the fastest thing on the page to understand.
    //
    // It stops holding the moment the stage is not a picture. The bar page's hero
    // carries a tray of module tiles — a set of controls, not an illustration — and
    // a heading under a grid of buttons reads as belonging to whatever comes NEXT,
    // not to the grid it is describing. Controls want to be introduced; pictures
    // want to be recognised and then named.
    property bool headingFirst: false

    property alias actions: actionRow.data
    property alias footer:  footerCol.data

    // Everything declared plainly in the body goes onto the stage. Content wants
    // `Layout.fillWidth: true` and an implicitHeight of its own.
    default property alias content: stageCol.data

    Layout.fillWidth: true
    Layout.alignment: Qt.AlignTop
    spacing: 0

    Surface {
        Layout.fillWidth: true

        elevation:    root.elevation
        cornerRadius: Tokens.radiusXl
        // The same tonal wash Section carries, at the same strength, so the hero and
        // the sections under it read as one family rather than as two designs.
        color: Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceFor(root.elevation), root.accent, 0.07)

        implicitHeight: cardCol.implicitHeight + root.padding * 2

        // ── A GridLayout of one column, not a ColumnLayout ────────────────────
        // Solely so `headingFirst` can reorder. A ColumnLayout lays its children out
        // in DECLARATION order and offers nothing to change that — there is no
        // `Layout.row` for it — so the only ways to flip two children are to declare
        // both twice and hide one pair, or to swap the layout type. A one-column
        // GridLayout honours explicit `Layout.row`, which makes the order data.
        GridLayout {
            id: cardCol

            anchors.left:  parent.left
            anchors.right: parent.right
            anchors.top:   parent.top
            anchors.margins: root.padding

            columns: 1
            rowSpacing:    Tokens.spacingLg
            columnSpacing: 0

            // ── The recessed stage ────────────────────────────────────────────
            // `elevationBar` is the DARKEST fill in the ladder (`Colors.surface`),
            // which is what makes this read as cut into the card above it. The
            // ladder is "distance from the user", so reaching down it is how a
            // surface goes backwards — there is no separate "inset" tone to invent.
            //
            // `castsShadow: false` for the same reason `elevationNested` casts
            // nothing: this is flush with the material it is cut into, and a shadow
            // under it would say it is floating in front of the card it is inside.
            Surface {
                Layout.fillWidth: true
                Layout.column: 0
                Layout.row: root.headingFirst ? 1 : 0
                Layout.preferredHeight: root.stageHeight > 0
                    ? root.stageHeight
                    : stageCol.implicitHeight + root.stageInset * 2

                visible:      root.stageVisible || stageCol.children.length > 0
                elevation:    Tokens.elevationBar
                cornerRadius: Tokens.radiusCard
                castsShadow:  false
                // Invisible plate, visible content: `opacity` would fade the preview
                // with it, so the plate stands down by dropping its own fill and
                // border rather than by hiding, and the content keeps its geometry.
                color:        root.stageVisible ? Colors.of(QsWindow.window).surfaceFor(Tokens.elevationBar)
                                                : "transparent"
                borderWidth:  root.stageVisible ? Tokens.borderWidth : 0

                ColumnLayout {
                    id: stageCol
                    anchors.left:   parent.left
                    anchors.right:  parent.right
                    anchors.top:    parent.top
                    anchors.bottom: root.stageHeight > 0 ? parent.bottom : undefined
                    anchors.margins: root.stageInset
                    spacing: Tokens.spacingMd
                }
            }

            // ── Heading, under the picture ────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.column: 0
                Layout.row: root.headingFirst ? 0 : 1
                visible: root.title !== "" || root.glyph !== ""
                spacing: Tokens.spacingLg

                // The same icon chip Section uses, one size up. Deliberately not
                // factored into a shared component: two call sites that differ in a
                // constant is not yet an abstraction, and Section's chip is sized
                // against a `headline` title where this one is sized against
                // `display` — extracting it would immediately need the size back as
                // a parameter.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth:  44
                    Layout.preferredHeight: 44
                    visible: root.glyph !== ""
                    radius: Tokens.radiusCard
                    color:  Colors.of(QsWindow.window).alpha(root.accent, 0.16)

                    MaterialIcon {
                        anchors.centerIn: parent
                        glyph:    root.glyph
                        color:   root.accent
                        variant: "headline"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text:    root.title
                        variant: "display"
                        font.weight: Font.DemiBold
                        elide:   Text.ElideRight
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

                RowLayout {
                    id: actionRow
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Tokens.spacingSm
                }
            }

            // ── The attached control strip ────────────────────────────────────
            // Nothing at all when a page does not use it — an empty layout still
            // takes its parent's spacing, which would leave a gap under the heading
            // that looks like a rendering fault rather than like an empty slot.
            ColumnLayout {
                id: footerCol
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.column: 0
                Layout.row: 2
                visible: footerCol.children.length > 0
                spacing: Tokens.spacingSm
            }
        }
    }
}
