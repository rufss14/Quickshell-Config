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
// One HUD widget as a card in the overview's corners, round the workspaces: the shared
// cookie field drifting through it (DriftShapes — the same field as the grid's card, the
// island and the open dim, so a cookie crosses from one into the next), a header — the
// widget's cookie chip, its name, where it shows once pinned, a status line — and three
// chips: PIN (draw it on screen), MOVE (arrange it on the real screen, HudArrange) and TUNE
// (put it in the island, where HudInspector sets its options; outlined while it's there).
// The widget's own content goes in the default slot, laid out in a ROW.
//
// Wide and short, at ONE height for every card (`bodyHeight`): the strips' height is then a
// constant, so the grid's room never depends on how wide a card ended up — a card whose
// height followed its width (wrapping text, a wrapping Flow) would feed back into the
// grid's size, which sets the cards' widths.
//
// ── Motion ────────────────────────────────────────────────────────────────────
//   · It springs in with its neighbours (PopIn, `index`); the overview flies it in from its
//     own corner on top of that.
//   · Under the pointer it LEANS: a couple of degrees about its centre, the edge nearest the
//     pointer sinking (the desktop widgets' tilt, smaller — these are wide), with the
//     settings cards' PointerGlow lighting the fill and the edge nearest it. The cookies
//     inside stay put on the screen (DriftShapes maps through the card's real transform), so
//     the card reads as glass moving over the field.
//   · The status line swaps through a fade when it changes KIND ("Not in a call" → "General
//     · 0:12"), and simply ticks while only its figures change (`statusKind`).
//   · The pin / move / tune chips fade and slide in only while the pointer is on the card.
//   · The cookie chip swells when the widget is pinned, and the where-badge grows in beside
//     the name — the same gesture QuickToggleTile makes for "you just turned me on".
// (The turning corner flourish, HudArt, was removed 2026-10-20: cut by the chips, it read as a
// glitch in the corner — the user's call.)
// ─────────────────────────────────────────────────────────────────────────────
Surface {
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
    // 2.2 units (2.5 until 2026-10-20: the two strips took ~380 of 1080 px from the grid).
    readonly property int bodyHeight: Math.round(Tokens.sideCardUnit * 2.2)

    readonly property var meta: H.info(root.wid)
    readonly property var entry: Hud.layout.widgets[root.wid]
    readonly property bool inspected: Hud.inspecting === root.wid

    // What the status line says, and the copy it shows (see the header's Motion).
    readonly property string statusText: root.status !== "" ? root.status : Translation.tr(root.meta.blurb)
    property string shownStatus: ""
    Component.onCompleted: root.shownStatus = root.statusText
    function statusKind(t) { return t.replace(/[0-9]/g, "") }
    onStatusTextChanged: if (root.statusKind(root.statusText) === root.statusKind(root.shownStatus)) root.shownStatus = root.statusText

    elevation: Tokens.elevationCard
    cornerRadius: Tokens.radiusXl
    focused: root.inspected
    implicitHeight: col.implicitHeight + Tokens.spacingLg * 2

    PopIn { id: pop; active: root.running; index: root.index }
    // Surface's opacity IS itemOpacity; the entrance folds into it rather than replacing it.
    // The corner cards sit back from the workspaces card (the point of the screen): a touch more see-through
    // and a quieter edge, until one is being tuned (2026-11-03 review: nine cards of equal weight).
    itemOpacity: Tokens.surfaceOpacity * 0.86 * pop.opacity
    borderColor: root.inspected ? Colors.of(QsWindow.window).outlineFocus
                                : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
    scale: pop.scale

    // ── The lean ──────────────────────────────────────────────────────────────
    // `px`/`py`: the pointer's place on the card, -1..1 from its centre, 0 off it. They are
    // what animates (live-tracking timing while over it, a spring home on leaving), so the
    // two rotations can't disagree. Sign as WidgetFrame's: the edge nearer the pointer sinks.
    HoverHandler { id: cardHover }
    readonly property real tiltMax: Config.motionEnabled ? 2.2 : 0
    property real px: cardHover.hovered && root.width > 0
        ? Math.max(-1, Math.min(1, (cardHover.point.position.x / root.width - 0.5) * 2)) : 0
    property real py: cardHover.hovered && root.height > 0
        ? Math.max(-1, Math.min(1, (cardHover.point.position.y / root.height - 0.5) * 2)) : 0
    Behavior on px { NumberAnimation { duration: cardHover.hovered ? Motion.track : Motion.spatial; easing.type: cardHover.hovered ? Motion.trackCurve : Motion.overshoot } }
    Behavior on py { NumberAnimation { duration: cardHover.hovered ? Motion.track : Motion.spatial; easing.type: cardHover.hovered ? Motion.trackCurve : Motion.overshoot } }
    transform: [
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 1; y: 0; z: 0 }
            angle: -root.py * root.tiltMax
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            axis { x: 0; y: 1; z: 0 }
            angle: root.px * root.tiltMax
        }
    ]

    Item {
        anchors.fill: parent
        clip: true
        DriftShapes {
            anchors.fill: parent
            visible: root.running
            radius: root.radius
            fade: 0
            seam: false
            shift: UiState.overviewDrift
        }
    }
    PointerGlow {
        hover: cardHover
        color: root.accent
        radius: root.radius
    }

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

            ScallopChip {
                implicitWidth: 34
                implicitHeight: 34
                tint: root.accent
                hot: root.entry.pinned
                MaterialIcon {
                    anchors.centerIn: parent
                    name: root.meta.symbol
                    fill: root.entry.pinned ? 1 : 0
                    color: root.accent
                    font.pixelSize: Tokens.iconMd
                    Behavior on fill { NumberAnimation { duration: Motion.standard } }
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
                        color: root.pal.alpha(root.accent, 0.16)
                        Behavior on implicitWidth { NumberAnimation { duration: Motion.spatial; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.spring } }
                        Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                        RowLayout {
                            id: whereRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingXs
                            MaterialIcon {
                                name: root.entry.where === "always" ? "monitor" : "sports_esports"
                                fill: 1
                                color: root.accent
                                font.pixelSize: Tokens.iconSm
                            }
                            StyledText {
                                text: root.entry.where === "always" ? Translation.tr("Always") : Translation.tr("Over games")
                                variant: "caption"
                                color: root.accent
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
            // The chips show only under the pointer (or while the card is in the island):
            // twelve of them across the four corners were the loudest thing on the overview
            // (the user's pick, 2026-10-20). Faded, not hidden, so the header doesn't reflow
            // as they come; whether it's pinned is still said by the where-badge.
            ChipTray {
                id: tray
                readonly property bool shown: cardHover.hovered || root.inspected
                opacity: tray.shown ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: tray.shown ? Motion.standard : Motion.exit } }
                transform: Translate {
                    x: (1 - tray.opacity) * Tokens.spacingMd
                }
                ChipButton {
                    symbol: "keep"
                    on: root.entry.pinned
                    tint: root.accent
                    onActivated: Hud.pin(root.wid, !root.entry.pinned)
                }
                ChipButton {
                    symbol: "open_with"
                    tint: root.accent
                    onActivated: Hud.arrange(true, root.wid)
                }
                ChipButton {
                    symbol: "tune"
                    on: root.inspected
                    tint: root.accent
                    onActivated: Hud.inspect(root.wid)
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
