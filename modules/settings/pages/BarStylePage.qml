pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import ".."
import "../../../services"

// ── BarStylePage — Bar › Style ────────────────────────────────────────────────
// The bar's own geometry and finish: how thick it is, how round, how solid, and
// whether its groups wear an inner chip. Split out of BarPage, which used to carry
// this behind its own segmented strip (see that file's header).
//
// ── No preview here either ─────────────────────────────────────────────────────
// A scaled screen used to sit at the top of this page too (`BarPreview`, off
// `Config.layout`) — the same picture BarPage carried, for the same reason: the
// real bar is a few pixels above this window at full brightness, already showing
// every one of these settings live. A second, smaller copy of it answered nothing
// the real one didn't. There is no Apply button because there is nothing to apply.
//
// ── Fits the window ───────────────────────────────────────────────────────────
// Size beside Look (two cards of three controls each, so the row is flush), the
// bar-wide switches as tiles, then presets as chips. The text and icon scales had no
// control at all after an earlier pass (barFontScale/barIconScale were only reachable
// through a size preset); they are back, in Look. "Grow on hover" moved to Desktop ›
// Style — it is the desktop widgets' (WidgetFrame), whatever its Config name says.
//
// ── What is NOT here any more ─────────────────────────────────────────────────
// "Animations" and "Speed" used to sit in this card. They are `Config.motionEnabled`
// and `Config.motionScale` — every surface in the shell reads them, not just the bar
// — so they live in Appearance › Type & shape, with the other shell-wide look
// settings. Setting the whole shell's motion from the Bar page was a category error
// that only looked harmless because nowhere else offered it.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰸌"
        title:     Translation.tr("Bar")
        titleTail: "style"
        accent:    Colors.of(QsWindow.window).primary
        // Parenthesised: `a ?? b + c` binds as `a ?? (b + c)`, which would drop the
        // rest of the line for every size that HAS a label — i.e. always.
        subtitle:  (Config.barSizeLabels[Config.barSizeName] ?? "Custom")
                   + "  ·  " + Config.barThicknessPref + " px"
                   + "  ·  " + Math.round(Config.barOpacity * 100) + "% opaque"

        // Loads the default preset, which throws away your layout as well as your
        // sizes — so it arms first. ArmLatch is the shell's click-twice control;
        // there is no undo for a discarded arrangement.
        actions: ChipTray {
            ChipButton {
                ArmLatch {
                    id: resetBar
                    onConfirmed: Config.resetBar()
                }
                label:  resetBar.armed ? "Discard layout?" : "Reset bar"
                symbol: resetBar.armed ? "warning" : "restart_alt"
                on:     resetBar.armed
                tint:   resetBar.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                onActivated: resetBar.trigger()
            }
        }

        // ══ Size ══════════════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󰩨"
            title:  Translation.tr("Size")
            accent: Colors.of(QsWindow.window).primary
            help:   Translation.tr("Small, Normal and Big move thickness, roundness, inset and the text and icon scales together. Any slider takes you off them, to Custom.")

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: Config.barSizeOrder.map(k => ({
                    value: k,
                    label: Config.barSizeLabels[k],
                    // Small → large, as three sizes of the same mark. Every name has
                    // an icons.js fallback.
                    icon: k === Config.barSizeOrder[0] ? "density_small"
                        : k === Config.barSizeOrder[Config.barSizeOrder.length - 1]
                          ? "density_large" : "density_medium"
                }))
                current: Config.barSizeName
                onPicked: function (v) { Config.applyBarSize(v) }
            }

            Fader {
                label: Translation.tr("Thickness")
                accent: Colors.of(QsWindow.window).primary
                from: Config.barThicknessMin
                to:   Config.barThicknessMax
                // The raw preference, not Config.barThickness — that's the
                // resolution-scaled value everything else reads, and this slider sets
                // the base the scaling multiplies, not the rendered pixel count.
                value: Config.barThicknessPref
                readout: Config.barThicknessPref + " px"
                onCommit: function (v) { Config.barThicknessPref = v }
            }
            Fader {
                label: Translation.tr("Roundness")
                accent: Colors.of(QsWindow.window).primary
                from: 0
                to:   Config.barRoundnessMax
                value: Config.barRoundness
                readout: Config.barShape ? "square" : Config.barRoundness + " px"
                enabled: !Config.barShape
                onCommit: function (v) { Config.barRoundness = v }
            }
        }

        // ══ Look ══════════════════════════════════════════════════════════════
        Section {
            span:   1
            glyph:  "󰸌"
            title:  Translation.tr("Look")
            accent: Colors.of(QsWindow.window).primary

            Fader {
                label: Translation.tr("Opacity")
                help:  Translation.tr("Translucency needs a compositor blur behind it — Hyprland's is in Desktop › Tuning.")
                accent: Colors.of(QsWindow.window).primary
                from: Config.barOpacityMin
                to:   1.0
                step: 0.01
                value: Config.barOpacity
                readout: Math.round(Config.barOpacity * 100) + "%"
                onCommit: function (v) { Config.barOpacity = v }
            }
            // Multipliers, not pixel sizes (see Config.barFontScalePref): the ratios
            // between Tokens' sizes are the design.
            Fader {
                label: Translation.tr("Text")
                help:  Translation.tr("How big the bar's text runs — the clock, the workspace numbers, labels.")
                accent: Colors.of(QsWindow.window).primary
                from: 0.8
                to:   1.6
                step: 0.02
                value: Config.barFontScalePref
                readout: Config.barFontScalePref.toFixed(2) + "×"
                onCommit: function (v) { Config.barFontScalePref = v }
            }
            Fader {
                label: Translation.tr("Icons")
                help:  Translation.tr("How big the bar's icons run. Separate from text: a glyph is an icon that happens to be a character.")
                accent: Colors.of(QsWindow.window).primary
                from: 0.8
                to:   1.6
                step: 0.02
                value: Config.barIconScalePref
                readout: Config.barIconScalePref.toFixed(2) + "×"
                onCommit: function (v) { Config.barIconScalePref = v }
            }
        }

        // ══ The switches ══════════════════════════════════════════════════════
        // Tiles, not rows: each one changes the bar's whole silhouette, and each is
        // visible on the real bar the moment you tap it.
        QuickToggleTile {
            roomy:  true
            symbol: "square"
            label:  Translation.tr("Square corners")
            accent: Colors.of(QsWindow.window).primary
            active: Config.barShape
            subLabel: Config.barShape
                ? "Every corner in the shell, and the bar edge to edge"
                : "Rounded, at the radius above"
            onToggled: Config.toggleShape()
        }

        QuickToggleTile {
            roomy:  true
            symbol: "layers"
            label:  Translation.tr("Inner pill")
            accent: Colors.of(QsWindow.window).primary
            active: Config.barInnerPill
            subLabel: Config.barInnerPill
                ? "A lighter chip behind each group"
                : "Groups sit straight on the bar"
            onToggled: Config.barInnerPill = !Config.barInnerPill
        }

        // Moved from Modules: it is about the whole bar's centring, not one module.
        QuickToggleTile {
            roomy:  true
            symbol: "center_focus_strong"
            label:  Translation.tr("Anchor on workspaces")
            accent: Colors.of(QsWindow.window).primary
            active: Config.barCentreAnchor
            available: Config.isPlaced("workspaces")
            subLabel: !Config.isPlaced("workspaces")
                ? "Needs the workspaces module on the bar"
                : Config.barCentreAnchor
                ? "The dots hold true screen centre"
                : "Centred on its own region instead"
            help: Translation.tr("Keeps the workspace dots at the exact centre of the screen, however wide the modules either side of them grow.")
            onToggled: Config.barCentreAnchor = !Config.barCentreAnchor
        }

        // ══ Presets ═══════════════════════════════════════════════════════════
        // A preset is the whole bar — the layout AND these sizes — so it sits with
        // them rather than on the Modules view.
        Section {
            span:   1
            glyph:  "󰸖"
            title:  Translation.tr("Presets")
            help:   Translation.tr("The whole bar, saved under a name: what is on it and every size on this page.")
            accent: Colors.of(QsWindow.window).primary

            PresetChips {
                accent:   Colors.of(QsWindow.window).primary
                presets:  Config.allPresets
                isActive: function (name) { return Config.presetActive(name) }
                savePlaceholder: "Name this bar"
                onLoad:   function (name) { Config.loadPreset(name) }
                onSave:   function (name) { Config.savePreset(name) }
                onRename: function (from, to) { Config.renamePreset(from, to) }
                onRemove: function (name) { Config.deletePreset(name) }
            }
        }
    }
}
