pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import ".."

// ── SidebarPage — Bar & sidebar › Behaviour ───────────────────────────────────
// Where the surfaces sit and when they show: the sidebar's edge and size, how it hides,
// and where the bar centres. WHAT stands on them is Modules (2026-11-08: one page of
// modules, one inspector, one library for both); how they LOOK is Style (one set of
// knobs, each "Sidebar: same as bar" until unlinked). The file keeps its name: every
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
// runs one reveal for everything on the edge).
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

        bento:     true
        glyph:     "\u{F06FD}"
        title:     Translation.tr("Behaviour")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !root.anyOn ? "The sidebar has nothing on it yet"
                 : ["Sidebar on the " + Config.dockPosition,
                    root.welded ? "welded into the frame" : Config.barAnchored ? "on the frame" : "floating",
                    Config.sidebarDepth + "px"].join("  ·  ")

        // ══ Edge and size ═════════════════════════════════════════════════════
        // The dock's edge and the dock's icon size — one setting each, said once. The
        // Dock tab shows what they make.
        Section {
            span:    1
            glyph:   root.positionGlyph
            title:   Translation.tr("Edge & size")
            subtitle: Config.sidebarDepth + "px deep"
            help:    Translation.tr("The bar owns the top edge; the sidebar takes one of the other three. Everything on it is sized around the dock's icons.")
            accent:  Colors.of(QsWindow.window).primary

            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "left",   label: "Left",   icon: "chevron_left" },
                    { value: "bottom", label: "Bottom", icon: "keyboard_arrow_down" },
                    { value: "right",  label: "Right",  icon: "chevron_right" }
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

        // ══ How it shows ══════════════════════════════════════════════════════
        QuickToggleTile {
            roomy: true
            symbol: "visibility_off"
            label:  Translation.tr("Auto-hide")
            accent: Colors.of(QsWindow.window).primary
            active: Config.sidebarAutoHide
            available: root.anyOn
            subLabel: Config.sidebarAutoHide ? "Sinks away until you rest on the edge"
                    :                          "Always on screen"
            help: Translation.tr("Rest the pointer on the edge, or press Super+D (by default), to bring it back.")
            onToggled: Config.sidebarAutoHide = !Config.sidebarAutoHide
        }

        QuickToggleTile {
            roomy: true
            symbol: "arrow_downward"
            label:  Translation.tr("Dodge windows")
            accent: Colors.of(QsWindow.window).primary
            active: Config.sidebarAutoHide && Config.sidebarDodge
            available: root.anyOn && Config.sidebarAutoHide
            subLabel: !Config.sidebarAutoHide ? "Needs auto-hide"
                    : Config.sidebarDodge    ? "Hides only when a window is in its way"
                    :                          "Hides whenever the pointer leaves"
            help: Translation.tr("A kind of auto-hide: the sidebar stays out until a window would sit under it.")
            onToggled: Config.sidebarDodge = !Config.sidebarDodge
        }

        QuickToggleTile {
            roomy: true
            symbol: "crop_free"
            label:  Translation.tr("Empty workspaces")
            accent: Colors.of(QsWindow.window).primary
            active: Config.sidebarAutoHide && Config.sidebarEmptyReveal
            available: root.anyOn && Config.sidebarAutoHide
            subLabel: !Config.sidebarAutoHide ? Translation.tr("Needs auto-hide")
                    : Config.sidebarEmptyReveal ? Translation.tr("Stays out with no windows on the workspace")
                    :                             Translation.tr("No special case for an empty workspace")
            help: Translation.tr("Nothing to cover and nothing else to look at, so the sidebar and its dock stay out until a window opens. (End-4's rule.)")
            onToggled: Config.sidebarEmptyReveal = !Config.sidebarEmptyReveal
        }

        QuickToggleTile {
            roomy: true
            symbol: "mouse"
            label:  Translation.tr("Edge reveal")
            accent: Colors.of(QsWindow.window).primary
            active: Config.sidebarAutoHide && Config.sidebarEdgeReveal
            available: root.anyOn && Config.sidebarAutoHide
            subLabel: !Config.sidebarAutoHide ? Translation.tr("Needs auto-hide")
                    : Config.sidebarEdgeReveal ? Translation.tr("Resting on the edge brings it out")
                    :                            Translation.tr("Only an empty workspace, Super+D or the keep button")
            help: Translation.tr("Turn this off to stop the sidebar popping out whenever the pointer brushes the edge — combine it with Empty workspaces and the dock's keep button.")
            onToggled: Config.sidebarEdgeReveal = !Config.sidebarEdgeReveal
        }

        QuickToggleTile {
            roomy: true
            symbol: "push_pin"
            label:  Translation.tr("Reserve space")
            accent: Colors.of(QsWindow.window).primary
            // One reservation for the whole edge (DockReserve).
            active: Config.dockTakesSpace && !Config.sidebarAutoHide
            available: root.anyOn && !Config.sidebarAutoHide
            subLabel: Config.sidebarAutoHide ? "Off while auto-hide is on"
                    : Config.dockTakesSpace  ? "Tiled windows make room for it"
                    :                          "Floats over windows"
            help: Translation.tr("Tiled windows leave the sidebar's edge free. Off while auto-hide is on — it would reserve an empty strip.")
            onToggled: Config.dockTakesSpace = !Config.dockTakesSpace
        }

        // ══ The bar ═════════════════════════════════════════════════════════
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
    }
}
