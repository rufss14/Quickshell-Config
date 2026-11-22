pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H
import "../../services/inputkeys.js" as IK

// ── HudInputCard ──────────────────────────────────────────────────────────────
// The input overlay (keys and mouse drawn on screen), with what you actually change in it:
//   · the live widget on a canvas plate: HudInput with `listen: false` (its key hook is a Hyprland
//     Lua subscription, installed only while the widget is on screen), wearing its own size and
//     transparency, so a change is seen where it is made;
//   · On screen: the switch, and where it shows (over games, or always);
//   · the keyboard layout, one press each (WASD up to the full board; the layout is the thing that
//     differs by game: 4K is for osu!mania), with what it puts on the event socket said under it;
//   · size and transparency as sliders. The mouse, the rates and the fine settings are the island's
//     Keys page (the tune chip).
// ─────────────────────────────────────────────────────────────────────────────
HudCard {
    id: root
    wid: "input"

    readonly property var o: Hud.layout.widgets.input.opts
    readonly property var layoutNow: IK.layoutOf(root.o.layout)
    // Live: whether it's on screen, and when.
    status: !root.entry.pinned ? Translation.tr("Hidden")
        : root.entry.where === "always" ? Translation.tr("Showing on screen")
        : Translation.tr("Shows while you play")

    // ══ The live overlay, on a canvas plate (a picture of the thing: it keeps the hairline) ═══
    Rectangle {
        Layout.fillHeight: true
        implicitWidth: holder.implicitWidth + Tokens.spacingMd * 2
        radius: Tokens.radiusCard
        color: root.pal.section
        border.width: Tokens.borderWidth
        border.color: root.pal.outlineNested

        Item {
            id: holder
            anchors.centerIn: parent
            implicitWidth: Math.round(preview.implicitWidth * holder.fit)
            implicitHeight: Math.round(preview.implicitHeight * holder.fit)
            width: implicitWidth
            height: implicitHeight
            // Never so wide that the controls beside it are squeezed.
            readonly property real fit: Math.min(1, (root.bodyHeight - Tokens.spacingMd * 2) / Math.max(1, preview.implicitHeight),
                (root.width * 0.38 - Tokens.spacingMd * 2) / Math.max(1, preview.implicitWidth))

            HudInput {
                id: preview
                listen: false
                sizeScale: 1
                anchors.centerIn: parent
                scale: holder.fit
            }
        }
    }

    // ══ What you change ══════════════════════════════════════════════════════
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.radiusCard
        color: root.pal.section
        implicitWidth: controls.implicitWidth + Tokens.spacingMd * 2
        implicitHeight: controls.implicitHeight + Tokens.spacingMd * 2

        ColumnLayout {
            id: controls
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingSm

            // The one thing to do: show the keys and clicks you press, on screen.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Toggle {
                    checked: root.entry.pinned
                    accent: root.accent
                    onToggled: Hud.pin(root.wid, !root.entry.pinned)
                }
                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("On screen")
                    variant: "label"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    HoverTip {
                        text: Translation.tr("Draws the keys and clicks you press on your screen, live, for streams and tutorials.")
                    }
                }
                // While it is on: only over games, or always.
                ChipButton {
                    visible: root.entry.pinned
                    symbol: root.entry.where === "always" ? "monitor" : "sports_esports"
                    label: root.entry.where === "always" ? Translation.tr("Always") : Translation.tr("Games only")
                    tonal: true
                    tint: root.accent
                    onActivated: Hud.setWhere(root.wid, root.entry.where === "always" ? "games" : "always")
                    HoverTip { text: Translation.tr("Choose whether it shows all the time, or only while a game is running.") }
                }
                ChipButton {
                    symbol: "tune"
                    tonal: true
                    tint: root.accent
                    on: Hud.inspecting === root.wid
                    onActivated: Hud.inspect(Hud.inspecting === root.wid ? "" : root.wid)
                    HoverTip { text: Translation.tr("More: the mouse, the click and key rates, and where it sits on the screen.") }
                }
            }

            // The keyboard it draws.
            ChipTray {
                Layout.fillWidth: false
                border.width: 0
                color: root.pal.surfaceHigh
                Repeater {
                    model: IK.LAYOUT_IDS
                    delegate: ChipButton {
                        required property string modelData
                        label: IK.layoutOf(modelData).name
                        on: root.o.layout === modelData
                        tint: root.accent
                        onActivated: Hud.setOpt(root.wid, "layout", modelData)
                        HoverTip { text: IK.layoutOf(modelData).blurb }
                    }
                }
            }
            // What the layout puts on the event socket, which every program you run can read: a bigger
            // keyboard names more keys, said in the danger tone for the ones that cover everything you type.
            StyledText {
                Layout.fillWidth: true
                text: root.layoutNow.exposes === "all" ? Translation.tr("Names every key you type while it shows. No passwords.")
                    : root.layoutNow.exposes === "some" ? Translation.tr("Names the keys around WASD too.")
                    : Translation.tr("Names only the keys games use.")
                variant: "caption"
                color: root.layoutNow.exposes === "all" ? Verdict.fail : root.pal.fgDim
                elide: Text.ElideRight
            }

            // Size and see-through.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingLg
                Repeater {
                    model: [
                        { key: "scale",   symbol: "open_with", min: H.SCALE_MIN,   max: H.SCALE_MAX },
                        { key: "opacity", symbol: "opacity",   min: H.OPACITY_MIN, max: H.OPACITY_MAX }
                    ]
                    delegate: RowLayout {
                        id: knob
                        required property var modelData
                        readonly property real v: root.o[knob.modelData.key] ?? 1
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        MaterialIcon {
                            name: knob.modelData.symbol
                            color: root.pal.fgMuted
                            font.pixelSize: Tokens.iconSm
                        }
                        ValueSlider {
                            Layout.fillWidth: true
                            expressive: true
                            thickness: 6
                            accent: root.accent
                            value: (knob.v - knob.modelData.min) / (knob.modelData.max - knob.modelData.min)
                            onMoved: function (x) { Hud.setOpt(root.wid, knob.modelData.key, knob.modelData.min + x * (knob.modelData.max - knob.modelData.min)) }
                        }
                        StyledText {
                            Layout.preferredWidth: Tokens.sideCardUnit * 0.9
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(knob.v * 100) + "%"
                            variant: "label"
                            font.features: { "tnum": 1 }
                            font.weight: Font.DemiBold
                        }
                    }
                }
            }
        }
    }
}
