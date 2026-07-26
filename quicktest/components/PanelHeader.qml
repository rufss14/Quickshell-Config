import QtQuick
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
    // most just take a Nerd Font glyph. Give it one; `icon` wins if both are set.
    property string glyph:    ""
    property url    icon:     ""

    property string title:    ""      // rendered in the normal foreground
    property string titleTail: ""     // rendered in `accent` — the panel's identity
    property string subtitle: ""

    // One accent per panel. Defaults to `focus`, the "this is what you're looking
    // at" role — a panel header is identity, not an action.
    property color accent: Colors.focus

    // Actions go on the right (rescan, close, mode toggles…).
    default property alias actions: actionRow.data

    Layout.fillWidth: true
    spacing: Tokens.spacingLg

    // ── Icon ──────────────────────────────────────────────────────────────────
    Rectangle {
        Layout.alignment: Qt.AlignVCenter
        width:  36
        height: 36
        radius: Tokens.radiusSm + 2

        color:        Colors.alpha(root.accent, 0.20)
        border.color: Colors.alpha(root.accent, 0.32)
        border.width: Tokens.borderWidth

        StyledText {
            visible: root.glyph !== "" && String(root.icon) === ""
            anchors.centerIn: parent
            text:    root.glyph
            color:   root.accent
            variant: "headline"
        }

        // Loader-gated: an Image with an empty source resolves to Quickshell's
        // qs-blackhole placeholder and warns, so a glyph-only header must not
        // construct one at all.
        Loader {
            active: String(root.icon) !== ""
            anchors.centerIn: parent

            sourceComponent: Image {
                source: root.icon
                sourceSize: Qt.size(18, 18)
                width:  18
                height: 18
                fillMode: Image.PreserveAspectFit
                smooth: true
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
                variant: "title"
                font.weight: Font.DemiBold
            }
            StyledText {
                visible: root.titleTail !== ""
                text:    root.titleTail
                variant: "title"
                font.weight: Font.DemiBold
                color:   root.accent
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible:  root.subtitle !== ""
            text:     root.subtitle
            variant:  "caption"
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
