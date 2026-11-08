import QtQuick
import Quickshell
import QtQuick.Layouts
import "../config"

// ── PanelHeader ───────────────────────────────────────────────────────────────
// The top of every panel: an icon, a two-word title whose second word carries the
// panel's accent, a subtitle, and an optional row of actions on the right.
//
// Every panel used to hand-roll this — same shape, seven different executions.
// They disagreed on the icon square's size and radius, on whether the title was
// 15px DemiBold or something else, on subtitle opacity (0.40 / 0.45 / 0.50), and
// four of them wrapped the icon in a two-stop gradient with a different pair of
// stops each time.
//
// ── Why flat, not gradient ────────────────────────────────────────────────────
// The gradients were tuned against a vivid palette. This shell's colours come
// from the wallpaper, and on a desaturated palette (yours is: primary #6f7a84,
// focus #afa59c) a two-stop gradient between two near-grey accents doesn't read
// as depth — it reads as mud. A flat tint at a known alpha stays legible on any
// palette the wallpaper throws at it, which is the whole point of sourcing colour
// from the wallpaper in the first place.
// ─────────────────────────────────────────────────────────────────────────────
RowLayout {
    id: root

    // A glyph OR an svg asset — some panels have a real icon (wallpaper, palette),
    // most just take a Nerd Font glyph. Give it one; `icon` wins if both are set —
    // unless the icon fails to load, in which case the glyph comes back. That
    // fallback is not decoration: the wallpaper panel's engine icon is Wallpaper
    // Engine's logo out of Steam's own cache, which simply isn't there on a machine
    // that doesn't own it, and an empty chip would read as a broken panel.
    property string glyph:    ""
    // A Material Symbols name ("snooze"); wins over `glyph`, which stays for every panel
    // that still passes a codepoint (the same additive pair as PanelButton).
    property string symbol:   ""
    property url    icon:     ""
    // A live item for the chip instead of the glyph/icon (the Claude panel's playing
    // burst). null = the glyph or icon, as ever.
    property Component mark: null

    property size iconSize: Qt.size(18, 18)

    // The header's scale. A panel's own size by default; the overview, a whole screen, asks for
    // a bigger chip and type (its title is the hero between four cards, not a panel's).
    property int    chipSize:        36
    property string titleVariant:    "title"
    property string subtitleVariant: "caption"

    // An M3E shape name (shapes.js: "cookie9", "sunny"…): the chip becomes a MorphShape on primaryContainer
    // that morphs when this changes, instead of the tinted rounded square. "" = the old chip, so the ~70
    // panels that don't ask look as they did.
    property string morph: ""

    // ── Taking a REGION of the icon file ──────────────────────────────────────
    // Wallpaper Engine's logo.png is 640x192: the mark on the left, a wordmark
    // filling the rest. Only the mark belongs in a 36px chip, so the wallpaper
    // panel hands over the mark's rectangle instead of a second, cropped copy of
    // someone else's trademark checked into this repo.
    //
    // MEASURED, not assumed: `sourceSize` is applied to the whole file BEFORE the
    // clip, so setting both scaled 640x192 down to 18x18 and then cut a 177px
    // rectangle out of that — which renders as a two-pixel sliver. With a clip in
    // play the clip IS the size, hence the reset below.
    property rect iconClip: Qt.rect(0, 0, 0, 0)
    readonly property bool _clipped: root.iconClip.width > 0 && root.iconClip.height > 0

    property string title:    ""      // rendered in the normal foreground
    property string titleTail: ""     // rendered in `accent` — the panel's identity
    property string subtitle: ""

    // One accent per panel. Defaults to `focus`, the "this is what you're looking
    // at" role — a panel header is identity, not an action.
    property color accent: Colors.of(QsWindow.window).primary

    // Actions go on the right (rescan, close, mode toggles…).
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: Tokens.spacingLg

    // ── Icon ──────────────────────────────────────────────────────────────────
    ShapeBox {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth:  root.chipSize
        implicitHeight: root.chipSize
        // A rounded square, as it always was, unless Config.iconShape picks one shape for
        // every holder (ShapeBox).
        fallback:    "rounded"
        fillColor:   root.morph !== "" ? "transparent" : Colors.of(QsWindow.window).alpha(root.accent, 0.20)
        strokeColor: root.morph !== "" ? "transparent" : Colors.of(QsWindow.window).alpha(root.accent, 0.32)

        MorphShape {
            anchors.fill: parent
            visible: root.morph !== ""
            shape: root.morph !== "" ? root.morph : "circle"
            fillColor: Colors.of(QsWindow.window).primaryContainer
        }

        MaterialIcon {
            visible: root.mark === null && (root.glyph !== "" || root.symbol !== "")
                     && (String(root.icon) === "" || iconLoader.failed)
            anchors.centerIn: parent
            name:     root.symbol
            glyph:    root.glyph
            color:   root.morph !== "" ? Colors.of(QsWindow.window).fgOnPrimaryContainer : root.accent
            variant: "headline"
        }

        // Loader-gated: an Image with an empty source resolves to Quickshell's
        // qs-blackhole placeholder and warns, so a glyph-only header must not
        // construct one at all.
        Loader {
            anchors.centerIn: parent
            active: root.mark !== null
            sourceComponent: root.mark
        }

        Loader {
            id: iconLoader
            active: root.mark === null && String(root.icon) !== ""
            anchors.centerIn: parent

            readonly property bool failed:
                (iconLoader.item?.status ?? Image.Null) === Image.Error

            sourceComponent: Image {
                source: root.icon
                sourceClipRect: root.iconClip
                sourceSize: root._clipped ? Qt.size(0, 0) : root.iconSize
                width:  root.iconSize.width
                height: root.iconSize.height
                fillMode: Image.PreserveAspectFit
                smooth: true
                // Hidden rather than left as a broken box: the glyph above takes
                // over, and two things occupying the chip at once would overlap.
                visible: status !== Image.Error
            }
        }
    }

    // ── Title + subtitle ──────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: 1

        RowLayout {
            spacing: Tokens.spacingSm + 2

            StyledText {
                text:    root.title
                variant: root.titleVariant
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: root.titleTail !== ""
                text:    root.titleTail
                variant: root.titleVariant
                font.weight: Font.DemiBold
                color:   root.accent
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible:  root.subtitle !== ""
            text:     root.subtitle
            variant:  root.subtitleVariant
            emphasis: "dim"
            elide:    Text.ElideRight
        }
    }

    // ── Actions ───────────────────────────────────────────────────────────────
    RowLayout {
        id: actionRow
        Layout.alignment: Qt.AlignVCenter
        spacing: Tokens.spacingMd
    }
}
