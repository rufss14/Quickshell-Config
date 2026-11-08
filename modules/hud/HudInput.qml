pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/inputkeys.js" as InputJs

// ── HudInput ──────────────────────────────────────────────────────────────────
// The input overlay: a block of keys (Tab Q W E R / Shift A S D F / Ctrl Space), a mouse
// (left, right, middle, the two side buttons), and clicks/keys per second under them — the
// thing you show over a game. Which keys and where they sit is ONE table,
// services/inputkeys.js KEYS; the hook and the rates are services/InputKeys, held while
// this exists — and this only exists while it's on screen (HudWidget's Loader).
//
// ── Look ──────────────────────────────────────────────────────────────────────
// A card in the shell's surface and outline, HudCap's flat keys on it, the accent when
// lit. How see-through it is is the widget's `opacity` option (hud.js), stepped by the
// edit chrome's −/+ buttons: it fades the card and the IDLE keys, never a lit key or the
// text. It draws its own card (so the card can fade), so HudLayer gives it `plain`.
//
// ── Size ──────────────────────────────────────────────────────────────────────
// Everything is in key units (`u`) times `sizeScale`, which HudWidget hands in from the
// saved `scale` option (its corner grip, in edit mode) — so the whole overlay grows as one
// rather than as a stretched picture. Radii, spacing and type are the Tokens scaled by it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property real sizeScale: 1

    // A preview (the overview's card and map) draws the keys idle and installs no hook:
    // the hook is a Hyprland Lua subscription, not something to add on every overview open.
    property bool listen: true
    property bool _acquired: false
    Component.onCompleted: if (root.listen) { InputKeys.acquire(); root._acquired = true }
    Component.onDestruction: if (root._acquired) InputKeys.release()

    readonly property var pal: Colors.of(QsWindow.window)
    readonly property var held: InputKeys.held
    readonly property real s: root.sizeScale
    readonly property real op: Hud.layout.widgets.input.opts.opacity
    // Which keyboard, and whether the mouse and the rates are drawn (the island's "Keys" page).
    readonly property var lay: InputJs.layoutOf(Hud.layout.widgets.input.opts.layout)
    readonly property bool showMouse: Hud.layout.widgets.input.opts.mouse !== false
    readonly property bool showStats: Hud.layout.widgets.input.opts.stats !== false
    // One letter key, in px.
    readonly property int u: Math.round(Tokens.sideCardUnit * 0.7 * root.s)
    readonly property int gap: Math.max(2, Math.round(Tokens.spacingXs * root.s))
    readonly property int pad: Math.round(Tokens.spacingLg * root.s)

    implicitWidth: content.implicitWidth + root.pad * 2
    implicitHeight: content.implicitHeight + root.pad * 2

    // ── The card ──────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Math.round(Tokens.radiusCard * root.s)
        antialiasing: true
        color: root.pal.fade(root.pal.surface, root.op)
        border.width: Tokens.borderWidth
        border.color: root.pal.fade(root.pal.outline, root.op)
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: Math.round(Tokens.spacingMd * root.s)

        Row {
            id: board
            spacing: Math.round(Tokens.spacingLg * root.s)

            // ── Keys ──────────────────────────────────────────────────────────
            Item {
                width:  Math.round(root.lay.cols * root.u) - root.gap
                height: Math.round(root.lay.rows * root.u) - root.gap

                Repeater {
                    model: root.lay.keys
                    HudCap {
                        required property var modelData
                        x: Math.round(modelData.x * root.u)
                        y: Math.round(modelData.y * root.u)
                        width: Math.round(modelData.w * root.u) - root.gap
                        height: Math.round(modelData.h * root.u) - root.gap
                        sizeScale: root.s
                        fillOpacity: root.op
                        raised: true
                        label: modelData.label
                        on: root.held[modelData.id] === true
                    }
                }
            }

            // ── Mouse ─────────────────────────────────────────────────────────
            // Tiled like the keys, never stacked: two buttons following a round nose,
            // the wheel in the slot between them, the palm under them with a rounded heel,
            // the side buttons in a strip of their own beside it — every piece separated
            // by the key gap. Stacked layers (a shell with buttons on it) looked fine
            // opaque and like a tangle of outlines once the overlay was see-through.
            Item {
                id: rodent
                visible: root.showMouse
                // Centred on the keys, whatever their height.
                y: Math.round((board.height - rodent.height) / 2)
                readonly property int sideW: Math.max(4, Math.round(root.u * 0.22))
                readonly property int bodyX: rodent.sideW + root.gap
                readonly property int mw: Math.round(root.u * 2)
                // Three rows tall at most: a tall keyboard does not make a tall mouse.
                readonly property int mh: Math.min(3, root.lay.rows) * root.u - root.gap
                readonly property int nose: Math.round(rodent.mw / 2)
                readonly property int heel: Math.round(rodent.mw * 0.42)
                readonly property int split: Math.round(rodent.mh * 0.46)
                readonly property int slotW: Math.round(rodent.mw * 0.22)
                readonly property int btnW: Math.round((rodent.mw - rodent.slotW) / 2)
                readonly property int small: Math.round(Tokens.radiusXs * root.s)
                width: rodent.bodyX + rodent.mw
                height: rodent.mh

                // Side buttons, on the thumb side, level with the palm: forward (M5)
                // above back (M4).
                Repeater {
                    model: ["m5", "m4"]
                    HudCap {
                        required property string modelData
                        required property int index
                        x: 0
                        y: rodent.split + root.gap * 3 + index * (height + root.gap)
                        width: rodent.sideW
                        height: Math.round(rodent.mh * 0.17)
                        sizeScale: root.s
                        fillOpacity: root.op
                        radius: width / 2
                        on: root.held[modelData] === true
                    }
                }

                Repeater {
                    model: ["lmb", "rmb"]
                    HudCap {
                        required property string modelData
                        required property int index
                        x: rodent.bodyX + (index === 0 ? 0 : rodent.mw - rodent.btnW)
                        width: rodent.btnW
                        height: rodent.split
                        sizeScale: root.s
                        fillOpacity: root.op
                        topLeftRadius:     index === 0 ? rodent.nose : rodent.small
                        topRightRadius:    index === 1 ? rodent.nose : rodent.small
                        bottomLeftRadius:  rodent.small
                        bottomRightRadius: rodent.small
                        on: root.held[modelData] === true
                    }
                }

                // The wheel, in the slot: lit while the middle button is held, ridged so it
                // reads as a wheel and not a pill.
                HudCap {
                    id: wheel
                    width: Math.max(4, rodent.slotW - root.gap * 2)
                    height: Math.round(rodent.split * 0.5)
                    x: rodent.bodyX + rodent.btnW + Math.round((rodent.slotW - width) / 2)
                    y: Math.round(rodent.split * 0.2)
                    sizeScale: root.s
                    fillOpacity: root.op
                    radius: width / 2
                    on: root.held.mmb === true

                    Column {
                        anchors.centerIn: parent
                        spacing: Math.max(2, Math.round(Tokens.spacingXs * root.s))
                        Repeater {
                            model: 3
                            Rectangle {
                                width: Math.max(2, Math.round(wheel.width * 0.5))
                                height: Tokens.borderWidth
                                color: wheel.lit ? root.pal.fgOnPrimary : root.pal.fgFaint
                            }
                        }
                    }
                }

                // The palm.
                HudCap {
                    x: rodent.bodyX
                    y: rodent.split + root.gap
                    width: rodent.mw
                    height: rodent.mh - rodent.split - root.gap
                    sizeScale: root.s
                    fillOpacity: root.op
                    topLeftRadius:     rodent.small
                    topRightRadius:    rodent.small
                    bottomLeftRadius:  rodent.heel
                    bottomRightRadius: rodent.heel
                }
            }
        }

        // ── Rates ─────────────────────────────────────────────────────────────
        // One slim cap each: the figure, what it counts, and this session's best.
        Row {
            id: rates
            visible: root.showStats
            spacing: root.gap
            // From the row above, not the Column: the Column's width is made of this row.
            readonly property int tileW: Math.round((board.width - rates.spacing * 2) / 3)

            Repeater {
                model: [
                    { label: "LMB CPS", now: InputKeys.cpsLeft,  best: InputKeys.bestLeft },
                    { label: "RMB CPS", now: InputKeys.cpsRight, best: InputKeys.bestRight },
                    { label: "KPS",     now: InputKeys.kps,      best: InputKeys.bestKeys }
                ]
                HudCap {
                    id: tile
                    required property var modelData
                    width: rates.tileW
                    height: root.u - root.gap
                    sizeScale: root.s
                    fillOpacity: root.op

                    Row {
                        anchors.centerIn: parent
                        spacing: Math.round(Tokens.spacingSm * root.s)
                        // A plain figure: a rate changes many times a second, and a rolling
                        // digit never finished one change before the next began.
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: String(tile.modelData.now)
                            variant: "title"
                            sizeScale: root.s
                            font.family: Tokens.fontMono
                            font.weight: Font.Bold
                            color: tile.modelData.now > 0 ? root.pal.primary : root.pal.fg
                            Behavior on color { ColorAnimation { duration: Motion.standard } }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText {
                                text: tile.modelData.label
                                variant: "micro"
                                sizeScale: root.s
                                font.weight: Font.DemiBold
                                emphasis: "muted"
                            }
                            StyledText {
                                text: Translation.tr("best %1").arg(tile.modelData.best)
                                variant: "micro"
                                sizeScale: root.s
                                emphasis: "dim"
                            }
                        }
                    }
                }
            }
        }
    }
}
