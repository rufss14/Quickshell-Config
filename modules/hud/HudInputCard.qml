pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/hud.js" as H

// ── HudInputCard ──────────────────────────────────────────────────────────────
// The input overlay, under the workspaces right of the island: the real widget drawn idle
// (HudInput with `listen: false` — its key hook is a Hyprland Lua subscription, installed
// only while the widget is actually on screen), shrunk to the card's height and wearing its
// own transparency, with what it is for and its two knobs — size and opacity, stepped
// right here (the island's sliders are the fine version).
// ─────────────────────────────────────────────────────────────────────────────
HudCard {
    id: root
    wid: "input"

    readonly property var o: Hud.layout.widgets.input.opts
    // Live: whether it's on screen, and when (the description below says what it is).
    status: !root.entry.pinned ? Translation.tr("Hidden")
        : root.entry.where === "always" ? Translation.tr("Showing on screen")
        : Translation.tr("Shows while you play")

    Item {
        id: holder
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: false
        implicitWidth: Math.round(preview.implicitWidth * holder.fit)
        implicitHeight: Math.round(preview.implicitHeight * holder.fit)
        readonly property real fit: Math.min(1, root.bodyHeight / Math.max(1, preview.implicitHeight))

        HudInput {
            id: preview
            listen: false
            sizeScale: 1
            anchors.centerIn: parent
            scale: holder.fit
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        Layout.fillHeight: false
        spacing: Tokens.spacingXs

        // The one thing to do, as a switch with its name (it was "pin it to show it", behind a chip that only
        // appears on hover): show the keys and clicks you press, on screen.
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
                    text: Translation.tr("Draws the keys and clicks you press on your screen, live — for streams and tutorials.")
                }
            }
            ChipButton {
                symbol: "tune"
                tint: root.accent
                on: Hud.inspecting === root.wid
                onActivated: Hud.inspect(Hud.inspecting === root.wid ? "" : root.wid)
                HoverTip { text: Translation.tr("Customise: the keyboard layout (WASD up to a full keyboard), the mouse, size and see-through.") }
            }
            // While it is on: only over games, or always.
            ChipButton {
                visible: root.entry.pinned
                symbol: root.entry.where === "always" ? "monitor" : "sports_esports"
                label: root.entry.where === "always" ? Translation.tr("Always") : Translation.tr("Games only")
                tint: root.accent
                onActivated: Hud.setWhere(root.wid, root.entry.where === "always" ? "games" : "always")
                HoverTip { text: Translation.tr("Choose whether it shows all the time, or only while a game is running.") }
            }
        }

        // ── The two knobs, stepped ────────────────────────────────────────────
        Repeater {
            model: [
                { key: "scale",   symbol: "open_with", label: Translation.tr("Size"),    step: 0.1 },
                { key: "opacity", symbol: "opacity",   label: Translation.tr("Opacity"), step: 0.1 }
            ]
            RowLayout {
                id: knob
                required property var modelData
                readonly property real v: root.o[knob.modelData.key] ?? 1
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingXs

                MaterialIcon {
                    name: knob.modelData.symbol
                    color: root.pal.fgMuted
                    font.pixelSize: Tokens.iconSm
                }
                StyledText {
                    Layout.fillWidth: true
                    text: knob.modelData.label
                    variant: "caption"
                    emphasis: "muted"
                }
                ChipButton {
                    symbol: "remove"
                    enabled: knob.v > (knob.modelData.key === "scale" ? H.SCALE_MIN : H.OPACITY_MIN) + 1e-6
                    onActivated: Hud.setOpt("input", knob.modelData.key, knob.v - knob.modelData.step)
                }
                StyledText {
                    Layout.preferredWidth: Tokens.sideCardUnit
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(knob.v * 100) + "%"
                    variant: "label"
                    font.family: Tokens.fontMono
                    font.weight: Font.DemiBold
                }
                ChipButton {
                    symbol: "add"
                    enabled: knob.v < (knob.modelData.key === "scale" ? H.SCALE_MAX : H.OPACITY_MAX) - 1e-6
                    onActivated: Hud.setOpt("input", knob.modelData.key, knob.v + knob.modelData.step)
                }
            }
        }
    }
}
