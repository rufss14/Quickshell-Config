pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../../services/hud.js" as H

// ── HudCard ───────────────────────────────────────────────────────────────────
// One HUD widget as a card in the overview's HUD row: a flat ground (GroundCard: no outline, no
// shadow, no field), a header — the widget's own shape badge, its name, where it shows once
// pinned, a status line — and a tools capsule that opens under the pointer: PIN (draw it on
// screen), MOVE (arrange it on the real screen, HudArrange) and TUNE (put it in the island,
// where HudInspector sets its options; lit while it's there). The widget's own content goes in
// the default slot, laid out in a ROW, on plates of its own.
//
// Wide and short, at ONE height for every card (`bodyHeight`): the row's height is then a
// constant, so the grid's room never depends on how wide a card ended up — a card whose
// height followed its width (wrapping text, a wrapping Flow) would feed back into the
// grid's size, which sets the cards' widths.
//
// ── Motion ────────────────────────────────────────────────────────────────────
//   · It springs in with its neighbours (PopIn, `index`).
//   · The badge is a plain disc until the widget is pinned, then blooms into the widget's own
//     shape on a spring, and the where-badge grows in beside the name.
//   · The status line swaps through a fade when it changes KIND ("Not in a call" → "General
//     · 0:12"), and simply ticks while only its figures change (`statusKind`).
//   · The tools capsule fades and slides in only while the pointer is on the card.
// ─────────────────────────────────────────────────────────────────────────────
GroundCard {
    id: root

    required property string wid
    property int index: 0
    property bool running: false
    // The header's second line — the widget's live state ("Recording · 0:42").
    property string status: ""
    // 0 as ever; 1 / 2 colour the status line (a verdict that is worth a look / needs acting on: Performance).
    property int statusLevel: 0
    property color accent: Colors.of(QsWindow.window).primary
    readonly property var pal: Colors.of(QsWindow.window)
    default property alias content: body.data
    readonly property int bodyHeight: Math.round(Tokens.sideCardUnit * 2.8)

    readonly property var meta: H.info(root.wid)
    readonly property var entry: Hud.layout.widgets[root.wid]
    readonly property bool inspected: Hud.inspecting === root.wid
    // Each widget blooms into a shape of its own (island-style: give each sibling a different one).
    readonly property string badgeShape: ({ clips: "cookie9", voice: "clover", stats: "sunny", input: "squircle" })[root.wid] ?? "cookie9"

    // What the status line says, and the copy it shows (see the header's Motion).
    readonly property string statusText: root.status !== "" ? root.status : Translation.tr(root.meta.blurb)
    property string shownStatus: ""
    Component.onCompleted: root.shownStatus = root.statusText
    function statusKind(t) { return t.replace(/[0-9]/g, "") }
    onStatusTextChanged: if (root.statusKind(root.statusText) === root.statusKind(root.shownStatus)) root.shownStatus = root.statusText

    // A card being tuned is one tone up.
    tone: root.inspected ? root.pal.surfaceHigh : root.pal.surfaceFor(Tokens.elevationCard)
    implicitHeight: col.implicitHeight + Tokens.spacingLg * 2

    PopIn { id: pop; active: root.running; index: root.index }
    opacity: pop.opacity
    scale: pop.scale

    HoverHandler { id: cardHover }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingMd

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            // Off, a disc; pinned, it blooms into the widget's own shape.
            Item {
                implicitWidth: Tokens.iconXl + Tokens.spacingMd
                implicitHeight: implicitWidth
                MorphShape {
                    anchors.fill: parent
                    shape: root.entry.pinned ? root.badgeShape : "circle"
                    spec: Motion.springSpatialFast
                    fillColor: root.entry.pinned ? root.pal.primaryContainer : root.pal.surfaceHigh
                    Behavior on fillColor { ColorAnimation { duration: Motion.respond } }
                }
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.meta.symbol
                    fill: root.entry.pinned ? 1 : 0
                    color: root.entry.pinned ? root.pal.fgOnPrimaryContainer : root.pal.fgMuted
                    font.pixelSize: Tokens.iconMd
                    Behavior on fill { NumberAnimation { duration: Motion.standard } }
                    Behavior on color { ColorAnimation { duration: Motion.respond } }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText {
                        text: Translation.tr(root.meta.label)
                        variant: "title"
                        font.weight: Font.DemiBold
                    }
                    // Where it shows, once it does: grows in beside the name on a spring.
                    Rectangle {
                        implicitWidth: root.entry.pinned ? whereRow.implicitWidth + Tokens.spacingSm * 2 : 0
                        implicitHeight: whereRow.implicitHeight + Tokens.spacingXs
                        visible: implicitWidth > 0.5
                        opacity: root.entry.pinned ? 1 : 0
                        clip: true
                        radius: height / 2
                        color: root.pal.surfaceHigh
                        Behavior on implicitWidth { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        RowLayout {
                            id: whereRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                name: root.entry.where === "always" ? "monitor" : "sports_esports"
                                fill: 1
                                color: root.pal.fgMuted
                                font.pixelSize: Tokens.iconSm
                            }
                            StyledText {
                                text: root.entry.where === "always" ? Translation.tr("Always") : Translation.tr("Over games")
                                variant: "caption"
                                color: root.pal.fgMuted
                                font.weight: Font.DemiBold
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
                // The held copy SwapFade swaps at its midpoint; a tick within the same kind
                // (only digits differ) updates it straight away.
                StyledText {
                    id: statusLine
                    Layout.fillWidth: true
                    text: root.shownStatus
                    variant: "label"
                    // Mixed toward the foreground: the palette's warning / the fail red alone are dim on this dark ground.
                    color: root.statusLevel >= 2 ? root.pal.mix(root.pal.fg, Verdict.fail, 0.55)
                         : root.statusLevel === 1 ? root.pal.mix(root.pal.fg, root.pal.warning, 0.5) : root.pal.fgDim
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    elide: Text.ElideRight
                    SwapFade {
                        target: statusLine
                        key: root.statusKind(root.statusText)
                        shownKey: root.statusKind(root.shownStatus)
                        travel: Tokens.spacingXs
                        onSwapped: root.shownStatus = root.statusText
                    }
                }
            }
            // The tools show only under the pointer (or while the card is in the island): twelve
            // of them across the four cards were the loudest thing on the overview. Faded, not
            // hidden, so the header doesn't reflow as they come; whether it's pinned is still said
            // by the badge and the where-badge.
            Rectangle {
                id: tray
                readonly property bool shown: cardHover.hovered || root.inspected
                implicitWidth: tools.implicitWidth + Tokens.spacingXs * 2
                implicitHeight: tools.implicitHeight + Tokens.spacingXs * 2
                radius: height / 2
                color: root.pal.surfaceHigh
                opacity: tray.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: tray.shown ? Motion.standard : Motion.exit } }
                transform: Translate { x: (1 - tray.opacity) * Tokens.spacingMd }
                Row {
                    id: tools
                    anchors.centerIn: parent
                    CardTool {
                        symbol: "keep"
                        filled: root.entry.pinned
                        tint: root.entry.pinned ? root.accent : root.pal.fgMuted
                        hoverTint: root.accent
                        name: Translation.tr("Pin")
                        onActivated: { Hud.pin(root.wid, !root.entry.pinned); bump() }
                    }
                    CardTool {
                        symbol: "open_with"
                        tint: root.pal.fgMuted
                        hoverTint: root.accent
                        name: Translation.tr("Move")
                        onActivated: Hud.arrange(true, root.wid)
                    }
                    CardTool {
                        symbol: "tune"
                        filled: root.inspected
                        tint: root.inspected ? root.accent : root.pal.fgMuted
                        hoverTint: root.accent
                        name: Translation.tr("Tune")
                        onActivated: Hud.inspect(root.wid)
                    }
                }
            }
        }

        RowLayout {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: root.bodyHeight
            spacing: Tokens.spacingLg
        }
    }
}
