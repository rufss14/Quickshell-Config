pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import ".."
import "../../../services"

// ── BarStylePage — Bar & sidebar › Style ──────────────────────────────────────
// How both surfaces look: ONE set of knobs (2026-11-08, the user's pick). The sidebar
// used to borrow the bar's corners, fill, inner pills and scales with no say of its own,
// and keep two switches (islands, the music) on a page of its own. Now every shared knob
// is here once, and under each a SideLink — "Sidebar: same as bar" until unlinked, and
// then the sidebar's own control appears (Config.sidebarStyle, surfaces.js).
//
//   shared, linkable   roundness, opacity, text, icons, inner pills, the music's glow
//   shell-wide         square corners (every corner in the shell, Tokens.corner)
//   one surface        the bar's thickness and size presets (the sidebar's size is the
//                      dock's icon size — Behaviour); the sidebar's islands (the bar's
//                      groups are always islands)
//
// The file keeps its name so every link to the bar's style still lands here.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property int unlinked: { void Config.sidebarStyle; return Object.keys(Config.sidebarStyle).length }

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰸌"
        title:     Translation.tr("Style")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  (Config.barSizeLabels[Config.barSizeName] ?? "Custom")
                   + "  ·  " + Config.barThicknessPref + " px"
                   + "  ·  " + (root.unlinked === 0 ? "sidebar matches the bar"
                                : root.unlinked + (root.unlinked === 1 ? " sidebar override" : " sidebar overrides"))

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
            help:   Translation.tr("Small, Normal and Big move the bar's thickness, roundness, inset and the text and icon scales together. Any slider takes you off them, to Custom. The sidebar's size is the dock's icon size, in Behaviour.")

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: Config.barSizeOrder.map(k => ({
                    value: k,
                    label: Config.barSizeLabels[k],
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
            SideLink {
                key: "roundness"
                barValue: Config.barRoundness
                Fader {
                    label: Translation.tr("Sidebar roundness")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0
                    to:   Config.barRoundnessMax
                    value: Config.sideRoundness
                    readout: Config.barShape ? "square" : Config.sideRoundness + " px"
                    enabled: !Config.barShape
                    onCommit: function (v) { Config.setSideStyle("roundness", v) }
                }
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
            SideLink {
                key: "opacity"
                barValue: Config.barOpacity
                Fader {
                    label: Translation.tr("Sidebar opacity")
                    accent: Colors.of(QsWindow.window).primary
                    from: Config.barOpacityMin
                    to:   1.0
                    step: 0.01
                    value: Config.sideOpacity
                    readout: Math.round(Config.sideOpacity * 100) + "%"
                    onCommit: function (v) { Config.setSideStyle("opacity", v) }
                }
            }
            Fader {
                label: Translation.tr("Text")
                help:  Translation.tr("How big the text runs — the clock, the workspace numbers, labels.")
                accent: Colors.of(QsWindow.window).primary
                from: 0.8
                to:   1.6
                step: 0.02
                value: Config.barFontScalePref
                readout: Config.barFontScalePref.toFixed(2) + "×"
                onCommit: function (v) { Config.barFontScalePref = v }
            }
            SideLink {
                key: "fontScale"
                barValue: Config.barFontScalePref
                Fader {
                    label: Translation.tr("Sidebar text")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0.8
                    to:   1.6
                    step: 0.02
                    value: Config.sideFontScalePref
                    readout: Config.sideFontScalePref.toFixed(2) + "×"
                    onCommit: function (v) { Config.setSideStyle("fontScale", v) }
                }
            }
            Fader {
                label: Translation.tr("Icons")
                help:  Translation.tr("How big the icons run. Separate from text: a glyph is an icon that happens to be a character.")
                accent: Colors.of(QsWindow.window).primary
                from: 0.8
                to:   1.6
                step: 0.02
                value: Config.barIconScalePref
                readout: Config.barIconScalePref.toFixed(2) + "×"
                onCommit: function (v) { Config.barIconScalePref = v }
            }
            SideLink {
                key: "iconScale"
                barValue: Config.barIconScalePref
                Fader {
                    label: Translation.tr("Sidebar icons")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0.8
                    to:   1.6
                    step: 0.02
                    value: Config.sideIconScalePref
                    readout: Config.sideIconScalePref.toFixed(2) + "×"
                    onCommit: function (v) { Config.setSideStyle("iconScale", v) }
                }
            }
        }

        // ══ Pills ═════════════════════════════════════════════════════════════
        Section {
            span:   1
            symbol: "layers"
            title:  Translation.tr("Pills")
            accent: Colors.of(QsWindow.window).primary
            help:   Translation.tr("The chips the modules stand on. A module can opt out of its inner pill in its own settings, in Modules.")

            SettingRow {
                label:  Translation.tr("Inner pill")
                detail: Config.barInnerPill ? "A lighter chip behind each group" : "Groups sit straight on the bar"
                Toggle { checked: Config.barInnerPill; onToggled: Config.barInnerPill = !Config.barInnerPill }
            }
            SideLink {
                key: "innerPill"
                barValue: Config.barInnerPill
                SettingRow {
                    label:  Translation.tr("Sidebar inner pill")
                    detail: Config.sideInnerPill ? "A lighter chip behind each group" : "Straight on the sidebar"
                    Toggle { checked: Config.sideInnerPill; onToggled: Config.setSideStyle("innerPill", !Config.sideInnerPill) }
                }
            }

            SettingRow {
                label:  Translation.tr("Tooltips")
                detail: Config.barTooltips ? Translation.tr("Rest on a pill to see what it is doing") : Translation.tr("Off")
                help:   Translation.tr("Resting the pointer on a bar module shows its name and what it is doing right now: the network you are on, the volume, how many updates are waiting.")
                Toggle { checked: Config.barTooltips; onToggled: Config.barTooltips = !Config.barTooltips }
            }
            SettingRow {
                label:  Translation.tr("With the music")
                detail: Config.barMusicReact ? "The pills' rims glow while music plays" : "Still"
                Toggle { checked: Config.barMusicReact; onToggled: Config.barMusicReact = !Config.barMusicReact }
            }
            SideLink {
                key: "musicReact"
                barValue: Config.barMusicReact
                SettingRow {
                    label:  Translation.tr("Sidebar with the music")
                    detail: Config.sideMusicReact ? "Its rims glow while music plays" : "Still"
                    Toggle { checked: Config.sideMusicReact; onToggled: Config.setSideStyle("musicReact", !Config.sideMusicReact) }
                }
            }

            SettingRow {
                label:  Translation.tr("Sidebar islands")
                detail: Config.sidebarIslands ? "A pill per group, like the bar" : "One pill per region, with dividers"
                help:   Translation.tr("The bar's groups are always islands. The sidebar can run one pill down each region instead, with a divider between groups.")
                Toggle { checked: Config.sidebarIslands; onToggled: Config.sidebarIslands = !Config.sidebarIslands }
            }
        }

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

        // ══ Presets ═══════════════════════════════════════════════════════════
        Section {
            span:   2
            glyph:  "󰸖"
            title:  Translation.tr("Presets")
            help:   Translation.tr("Both surfaces, saved under a name: what is on them and every knob on this page. A preset saved before the sidebar was in presets leaves the sidebar alone.")
            accent: Colors.of(QsWindow.window).primary

            PresetChips {
                accent:   Colors.of(QsWindow.window).primary
                presets:  Config.allPresets
                isActive: function (name) { return Config.presetActive(name) }
                savePlaceholder: "Name this setup"
                onLoad:   function (name) { Config.loadPreset(name) }
                onSave:   function (name) { Config.savePreset(name) }
                onRename: function (from, to) { Config.renamePreset(from, to) }
                onRemove: function (name) { Config.deletePreset(name) }
            }
        }
    }
}
