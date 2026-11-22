pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import ".."
import "../../../services"

// ── BarStylePage — Bar & sidebar › Style ──────────────────────────────────────
// How both surfaces look: ONE set of knobs. Every shared knob is here once, and the Sidebar
// group says which of them the sidebar follows (a SideLink row each: "Same as the bar" until
// unlinked, and then the sidebar's own control opens under it; Config.sidebarStyle, surfaces.js).
//
//   shared, linkable   roundness, opacity, text, icons, inner pills, the music's glow
//   shell-wide         square corners (every corner in the shell, Tokens.corner)
//   one surface        the bar's thickness and size presets (the sidebar's size is the
//                      dock's icon size — Behaviour); the sidebar's group pills (the bar's
//                      groups are always islands); where the bar centres (workspaces)
//
// "Square corners" is Type, shape & motion's: it is the shell's one shape switch, said once there.
//
// Grouped rows (docs/settings-style.md 1.6): Size, Look, Sidebar, Pills, Workspaces, Presets, in that
// order so the two columns end at similar heights.
//
// The file keeps its name so every link to the bar's style still lands here.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property int unlinked: { void Config.sidebarStyle; return Object.keys(Config.sidebarStyle).length }

    SettingsPage {
        anchors.fill: parent

        grouped:   true
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
                label:  resetBar.armed ? Translation.tr("Discard layout?") : Translation.tr("Reset bar")
                symbol: resetBar.armed ? "warning" : "restart_alt"
                on:     resetBar.armed
                tint:   resetBar.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary
                onActivated: resetBar.trigger()
            }
        }

        // ══ Size ══════════════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "density_medium"
            title:    Translation.tr("Size")
            subtitle: Config.barSizeLabels[Config.barSizeName] ?? Translation.tr("Custom")
            help:     Translation.tr("Small, Normal and Big move the bar's thickness, roundness, inset and the text and icon scales together. Any slider takes you off them, to Custom. The sidebar's size is the dock's icon size, on the Sidebar page.")

            TabStrip {
                Layout.fillWidth: true
                connected: true
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
                readout: Config.barShape ? Translation.tr("square") : Config.barRoundness + " px"
                enabled: !Config.barShape
                onCommit: function (v) { Config.barRoundness = v }
            }
        }

        // ══ Look ══════════════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "palette"
            title:   Translation.tr("Look")

            Fader {
                label: Translation.tr("Opacity")
                help:  Translation.tr("Translucency needs a compositor blur behind it. Hyprland's is in Desktop › Tuning.")
                accent: Colors.of(QsWindow.window).primary
                from: Config.barOpacityMin
                to:   1.0
                step: 0.01
                value: Config.barOpacity
                readout: Math.round(Config.barOpacity * 100) + "%"
                onCommit: function (v) { Config.barOpacity = v }
            }
            Fader {
                label: Translation.tr("Text")
                help:  Translation.tr("How big the text runs: the clock, the workspace numbers, labels.")
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
                help:  Translation.tr("How big the icons run. Separate from text: a glyph is an icon that happens to be a character.")
                accent: Colors.of(QsWindow.window).primary
                from: 0.8
                to:   1.6
                step: 0.02
                value: Config.barIconScalePref
                readout: Config.barIconScalePref.toFixed(2) + "×"
                onCommit: function (v) { Config.barIconScalePref = v }
            }
        }

        // ══ Sidebar ═══════════════════════════════════════════════════════════
        // Which of the bar's knobs the sidebar follows. Off, the sidebar's own control opens under its row.
        Section {
            grouped:  true
            symbol:   "vertical_split"
            title:    Translation.tr("Sidebar")
            subtitle: root.unlinked === 0 ? Translation.tr("Matches the bar")
                    : Translation.tr("%1 of its own").arg(root.unlinked)
            help:     Translation.tr("Each switch is on while the sidebar follows the bar's value. Turn one off to give the sidebar its own, starting from the bar's.")

            SideLink {
                key: "roundness"
                label: Translation.tr("Roundness")
                barValue: Config.barRoundness
                Fader {
                    label: Translation.tr("Sidebar roundness")
                    accent: Colors.of(QsWindow.window).primary
                    from: 0
                    to:   Config.barRoundnessMax
                    value: Config.sideRoundness
                    readout: Config.barShape ? Translation.tr("square") : Config.sideRoundness + " px"
                    enabled: !Config.barShape
                    onCommit: function (v) { Config.setSideStyle("roundness", v) }
                }
            }
            SideLink {
                key: "opacity"
                label: Translation.tr("Opacity")
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
            SideLink {
                key: "fontScale"
                label: Translation.tr("Text")
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
            SideLink {
                key: "iconScale"
                label: Translation.tr("Icons")
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
            SideLink {
                key: "innerPill"
                label: Translation.tr("Inner pill")
                barValue: Config.barInnerPill
                SettingRow {
                    rowTap: true
                    label:  Translation.tr("Sidebar inner pill")
                    detail: Config.sideInnerPill ? Translation.tr("A lighter chip behind each group") : Translation.tr("Straight on the sidebar")
                    onTapped: Config.setSideStyle("innerPill", !Config.sideInnerPill)
                    Toggle {
                        accent: Colors.of(QsWindow.window).primary
                        checked: Config.sideInnerPill
                        onToggled: Config.setSideStyle("innerPill", !Config.sideInnerPill)
                    }
                }
            }
            SideLink {
                key: "musicReact"
                label: Translation.tr("With the music")
                barValue: Config.barMusicReact
                SettingRow {
                    rowTap: true
                    label:  Translation.tr("Sidebar with the music")
                    detail: Config.sideMusicReact ? Translation.tr("Its rims glow while music plays") : Translation.tr("Still")
                    onTapped: Config.setSideStyle("musicReact", !Config.sideMusicReact)
                    Toggle {
                        accent: Colors.of(QsWindow.window).primary
                        checked: Config.sideMusicReact
                        onToggled: Config.setSideStyle("musicReact", !Config.sideMusicReact)
                    }
                }
            }
        }

        // ══ Pills ═════════════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "layers"
            title:   Translation.tr("Pills")
            help:    Translation.tr("The chips the modules stand on. A module can opt out of its inner pill in its own settings, in Modules.")

            SettingRow {
                rowTap: true
                label:  Translation.tr("Inner pill")
                detail: Config.barInnerPill ? Translation.tr("A lighter chip behind each group") : Translation.tr("Groups sit straight on the bar")
                onTapped: Config.barInnerPill = !Config.barInnerPill
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.barInnerPill
                    onToggled: Config.barInnerPill = !Config.barInnerPill
                }
            }

            SettingRow {
                rowTap: true
                label:  Translation.tr("Tooltips")
                detail: Config.barTooltips ? Translation.tr("Rest on a pill to see what it is doing") : Translation.tr("Pills stay quiet")
                help:   Translation.tr("Resting the pointer on a bar module shows its name and what it is doing right now: the network you are on, the volume, how many updates are waiting.")
                onTapped: Config.barTooltips = !Config.barTooltips
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.barTooltips
                    onToggled: Config.barTooltips = !Config.barTooltips
                }
            }
            SettingRow {
                rowTap: true
                label:  Translation.tr("With the music")
                detail: Config.barMusicReact ? Translation.tr("The pills' rims glow while music plays") : Translation.tr("Still")
                onTapped: Config.barMusicReact = !Config.barMusicReact
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.barMusicReact
                    onToggled: Config.barMusicReact = !Config.barMusicReact
                }
            }

            // The detail says "Sidebar islands" so a search for the old name still lands here.
            SettingRow {
                rowTap: true
                label:  Translation.tr("Group pills")
                detail: Config.sidebarIslands ? Translation.tr("Sidebar islands: a pill per group, like the bar")
                                              : Translation.tr("Sidebar islands off: one pill per region, with dividers")
                help:   Translation.tr("The bar's groups are always islands. The sidebar can run one pill down each region instead, with a divider between groups.")
                onTapped: Config.sidebarIslands = !Config.sidebarIslands
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.sidebarIslands
                    onToggled: Config.sidebarIslands = !Config.sidebarIslands
                }
            }
        }

        // ══ Workspaces ════════════════════════════════════════════════════════
        // How the bar is laid out, not when it shows (that is Behaviour).
        Section {
            grouped: true
            symbol:  "center_focus_strong"
            title:   Translation.tr("Workspaces")

            SettingRow {
                rowTap: true
                enabled: Config.isPlaced("workspaces")
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Anchor on workspaces")
                detail: !Config.isPlaced("workspaces")
                    ? Translation.tr("Needs the workspaces module on the bar")
                    : Config.barCentreAnchor
                    ? Translation.tr("The dots hold true screen centre")
                    : Translation.tr("Centred on its own region instead")
                help:   Translation.tr("Keeps the workspace dots at the exact centre of the screen, however wide the modules either side of them grow.")
                onTapped: Config.barCentreAnchor = !Config.barCentreAnchor
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.barCentreAnchor
                    onToggled: Config.barCentreAnchor = !Config.barCentreAnchor
                }
            }
        }

        // ══ Presets ═══════════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "bookmark"
            title:   Translation.tr("Presets")
            help:    Translation.tr("Both surfaces, saved under a name: what is on them and every knob on this page. A preset saved before the sidebar was in presets leaves the sidebar alone.")

            PresetChips {
                accent:   Colors.of(QsWindow.window).primary
                presets:  Config.allPresets
                isActive: function (name) { return Config.presetActive(name) }
                savePlaceholder: Translation.tr("Name this setup")
                onLoad:   function (name) { Config.loadPreset(name) }
                onSave:   function (name) { Config.savePreset(name) }
                onRename: function (from, to) { Config.renamePreset(from, to) }
                onRemove: function (name) { Config.deletePreset(name) }
            }
        }
    }
}
