pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import ".."

// ── SidebarPage — Bar & sidebar › Sidebar ─────────────────────────────────────
// Where the surfaces sit and when they show: the sidebar's edge and size, how it hides,
// and where the bar centres. WHAT stands on them is Modules (one page of
// modules, one inspector, one library for both); how they LOOK is Style (one set of
// knobs, each "Same as the bar" in its Sidebar group until unlinked). The file keeps its name: every
// sidebar module's right-click still opens "SidebarPage.qml", and lands here.
//
// ── It wears the top bar's style ──────────────────────────────────────────────
// It's one bar, like the top bar, and on the frame or floating as the top bar is; its
// corners, fills, borders and inner pills are Style's (the bar's, unless unlinked there).
// Its SIZE is the dock's:
// everything on it stands in a cell the dock button's size (Config.sidebarCell), so
// the icon size here is the dock's, the same setting.
//
// ── It hides as one ───────────────────────────────────────────────────────────
// Auto-hide, dodging windows and reserving space are the whole sidebar's (SideBarHost
// runs one reveal for everything on the edge). Dodge, Empty workspaces and Edge reveal are
// modes OF auto-hide (SideBarHost reads each only together with Config.sidebarAutoHide), so
// their rows dim while it is off; Reserve space is the opposite (DockReserve stands down
// while auto-hide is on), so it dims while it is on.
//
// Where the bar centres (Anchor on workspaces) is Style's: it is the bar's layout, not an edge.
//
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property bool anyOn: Config.sidebarAnyPlaced
    readonly property bool welded: Morph.available && Config.screenFrame && Config.barAnchored

    readonly property string positionGlyph:
          Config.dockPosition === "left"  ? "\u{F10AA}"        // dock-left
        : Config.dockPosition === "right" ? "\u{F10AB}"        // dock-right
        :                                   "\u{F10A9}"        // dock-bottom

    SettingsPage {
        anchors.fill: parent

        grouped:   true
        glyph:     "\u{F06FD}"
        title:     Translation.tr("Sidebar")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !root.anyOn ? Translation.tr("Nothing on it yet")
                 : [Translation.tr("On the %1").arg(Translation.tr(Config.dockPosition)),
                    root.welded ? Translation.tr("welded into the frame") : Config.barAnchored ? Translation.tr("on the frame") : Translation.tr("floating"),
                    Config.sidebarDepth + "px"].join("  ·  ")

        // ══ How it shows ══════════════════════════════════════════════════════
        Section {
            grouped:  true
            symbol:   "visibility_off"
            title:    Translation.tr("Showing")

            SettingRow {
                rowTap: true
                enabled: root.anyOn
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Auto-hide")
                detail: Config.sidebarAutoHide ? Translation.tr("Sinks away until you rest on the edge")
                      :                          Translation.tr("Always on screen")
                help:   Translation.tr("Rest the pointer on the edge, or press Super+D (by default), to bring it back.")
                onTapped: Config.sidebarAutoHide = !Config.sidebarAutoHide
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.sidebarAutoHide
                    onToggled: Config.sidebarAutoHide = !Config.sidebarAutoHide
                }
            }

            SettingRow {
                rowTap: true
                enabled: root.anyOn && Config.sidebarAutoHide
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Dodge windows")
                detail: !Config.sidebarAutoHide ? Translation.tr("Needs auto-hide")
                      : Config.sidebarDodge    ? Translation.tr("Hides only when a window is in its way")
                      :                          Translation.tr("Hides whenever the pointer leaves")
                help:   Translation.tr("A kind of auto-hide: the sidebar stays out until a window would sit under it.")
                onTapped: Config.sidebarDodge = !Config.sidebarDodge
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.sidebarAutoHide && Config.sidebarDodge
                    onToggled: Config.sidebarDodge = !Config.sidebarDodge
                }
            }

            SettingRow {
                rowTap: true
                enabled: root.anyOn && Config.sidebarAutoHide
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Empty workspaces")
                detail: !Config.sidebarAutoHide ? Translation.tr("Needs auto-hide")
                      : Config.sidebarEmptyReveal ? Translation.tr("Stays out with no windows on the workspace")
                      :                             Translation.tr("No special case for an empty workspace")
                help:   Translation.tr("Nothing to cover and nothing else to look at, so the sidebar and its dock stay out until a window opens. (End-4's rule.)")
                onTapped: Config.sidebarEmptyReveal = !Config.sidebarEmptyReveal
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.sidebarAutoHide && Config.sidebarEmptyReveal
                    onToggled: Config.sidebarEmptyReveal = !Config.sidebarEmptyReveal
                }
            }

            SettingRow {
                rowTap: true
                enabled: root.anyOn && Config.sidebarAutoHide
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Edge reveal")
                detail: !Config.sidebarAutoHide ? Translation.tr("Needs auto-hide")
                      : Config.sidebarEdgeReveal ? Translation.tr("Resting on the edge brings it out")
                      :                            Translation.tr("Only an empty workspace, Super+D or the keep button")
                help:   Translation.tr("Turn this off to stop the sidebar popping out whenever the pointer brushes the edge. Combine it with Empty workspaces and the dock's keep button.")
                onTapped: Config.sidebarEdgeReveal = !Config.sidebarEdgeReveal
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.sidebarAutoHide && Config.sidebarEdgeReveal
                    onToggled: Config.sidebarEdgeReveal = !Config.sidebarEdgeReveal
                }
            }
        }

        // ══ Edge and size ═════════════════════════════════════════════════════
        // The dock's edge and the dock's icon size: one setting each, said once.
        Section {
            grouped:  true
            glyph:    root.positionGlyph
            title:    Translation.tr("Edge & size")
            subtitle: Config.sidebarDepth + "px deep"
            help:     Translation.tr("The bar owns the top edge; the sidebar takes one of the other three. Everything on it is sized around the dock's icons.")

            TabStrip {
                Layout.fillWidth: true
                connected: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "left",   label: Translation.tr("Left"),   icon: "chevron_left" },
                    { value: "bottom", label: Translation.tr("Bottom"), icon: "keyboard_arrow_down" },
                    { value: "right",  label: Translation.tr("Right"),  icon: "chevron_right" }
                ]
                current: Config.dockPosition
                onPicked: function (v) { Config.dockPosition = v }
            }

            SliderRow {
                label: Translation.tr("Icons")
                from:  Config.dockIconSizeMin
                to:    Config.dockIconSizeMax
                step:  2
                value: Config.dockIconPx
                readout: Config.dockIconPx + "px"
                onCommit: function (v) { Config.dockIconSize = Math.round(v) }
            }
        }

        // ══ Screen space ══════════════════════════════════════════════════════
        Section {
            grouped: true
            symbol:  "push_pin"
            title:   Translation.tr("Screen space")

            SettingRow {
                rowTap: true
                enabled: root.anyOn && !Config.sidebarAutoHide
                opacity: enabled ? 1 : 0.4
                label:  Translation.tr("Reserve space")
                // One reservation for the whole edge (DockReserve).
                detail: Config.sidebarAutoHide ? Translation.tr("Off while auto-hide is on")
                      : Config.dockTakesSpace  ? Translation.tr("Tiled windows make room for it")
                      :                          Translation.tr("Floats over windows")
                help:   Translation.tr("Tiled windows leave the sidebar's edge free. Off while auto-hide is on, since it would reserve an empty strip.")
                onTapped: Config.dockTakesSpace = !Config.dockTakesSpace
                Toggle {
                    accent: Colors.of(QsWindow.window).primary
                    checked: Config.dockTakesSpace && !Config.sidebarAutoHide
                    onToggled: Config.dockTakesSpace = !Config.dockTakesSpace
                }
            }
        }
    }
}
