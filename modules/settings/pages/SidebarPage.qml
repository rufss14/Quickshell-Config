pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import ".."

// ── SidebarPage — Sidebar & dock › Sidebar ────────────────────────────────────
// The edge the bar doesn't own, as a whole: which modules stand on it, which edge it
// is, how big, and when it hides. The dock, stats, screen time and clips each have a
// tab of their own beside this one. Only what is shared lives here.
//
// (For a while this was a GROUP stacked with the others on one composed scroll; the
// rest of Settings kept its tab strips, so this did too.)
//
// ── What changed from the page it was ─────────────────────────────────────────
// Thirteen full-size tiles, one per module, became one row of chips: a module is a
// member of a SET, and a card each said one word and one sentence thirteen times. Dock,
// Stats and Clips are not in the row — each has its own tab, with its switch in the
// heading, so there is one place to turn each one on. The drag-to-arrange catalogue
// (SideModuleTray) is the last card.
//
// ── It wears the top bar's style ──────────────────────────────────────────────
// It's one bar, like the top bar, and on the frame or floating as the top bar is; its
// corners, fills, borders and inner pills are Bar › Style's. Its SIZE is the dock's:
// everything on it stands in a cell the dock button's size (Config.sidebarCell), so
// the icon size here is the dock's, the same setting.
//
// ── It hides as one ───────────────────────────────────────────────────────────
// Auto-hide, dodging windows and reserving space are the whole sidebar's (SideBarHost
// runs one reveal for everything on the edge).
//
// ── Arranging is the button's ──────────────────────────────────────────────────
// It used to arm itself whenever this page opened. Now the heading's Arrange button is
// the only way in (UiState.sidebarArrange, SideArrange); leaving the page still
// disarms it, so it can't be left on.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    Component.onDestruction: UiState.sidebarArrange = false

    readonly property bool anyOn: Config.sidebarAnyPlaced
    readonly property bool welded: Morph.available && Config.screenFrame && Config.barAnchored

    // The modules that are a chip rather than a view of their own.
    readonly property var chipModules: Config.sidebarModuleList.filter(function (m) {
        return m.id !== "dock" && m.id !== "stats" && m.id !== "clips"
    })
    readonly property int chipsOn: root.chipModules.filter(function (m) { return Config.sidebarPlaced(m.id) }).length

    // A module whose tool is missing can't be placed — said once, under the row.
    function blocker(id) {
        return id === "colour" ? ColorPicker.blocker()
             : id === "lens"   ? Lens.blocker()
             :                   ""
    }
    readonly property string blockedNote: root.chipModules
        .filter(function (m) { return !Config.sidebarPlaced(m.id) && root.blocker(m.id) !== "" })
        .map(function (m) { return m.label + ": " + root.blocker(m.id) })
        .join("   ·   ")

    readonly property string positionGlyph:
          Config.dockPosition === "left"  ? "\u{F10AA}"        // dock-left
        : Config.dockPosition === "right" ? "\u{F10AB}"        // dock-right
        :                                   "\u{F10A9}"        // dock-bottom

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "\u{F06FD}"
        title:     Translation.tr("Sidebar")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !root.anyOn ? "Nothing on it yet"
                 : [Config.dockPosition,
                    root.welded ? "welded into the frame" : Config.barAnchored ? "on the frame" : "floating",
                    Config.sidebarDepth + "px"].join("  ·  ")

        actions: ChipTray {
            ChipButton {
                label:  UiState.sidebarArrange ? "Done" : "Arrange"
                symbol: UiState.sidebarArrange ? "check" : "drag_pan"
                on:     UiState.sidebarArrange
                tint:   Colors.of(QsWindow.window).primary
                onActivated: UiState.sidebarArrange = !UiState.sidebarArrange
            }
        }

        // ══ What stands on it ═════════════════════════════════════════════════
        Section {
            span:    3
            glyph:   "\u{F0B90}"                                   // view-grid-plus
            title:   Translation.tr("On the sidebar")
            subtitle: root.chipsOn + " of " + root.chipModules.length
            help:    Translation.tr("Tap one to put it on the sidebar or take it off. The dock, stats and clips have tabs of their own, with their switch in the heading.")
            accent:  Colors.of(QsWindow.window).primary

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm

                Repeater {
                    model: root.chipModules

                    delegate: ToggleChip {
                        required property var modelData
                        glyph:  modelData.glyph
                        label:  modelData.label
                        hint:   modelData.description
                        active: Config.sidebarPlaced(modelData.id)
                        available: Config.sidebarPlaced(modelData.id) || root.blocker(modelData.id) === ""
                        onToggled: Config.sidebarToggle(modelData.id)
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: root.blockedNote !== ""
                wrapMode: Text.WordWrap
                variant: "caption"
                emphasis: "dim"
                text: root.blockedNote
            }
        }

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

        // ══ Look ══════════════════════════════════════════════════════════════
        // The top bar's own devices, on the edge (2026-10-31): islands, a hero, the music.
        Section {
            span:    1
            symbol:  "auto_awesome"
            title:   Translation.tr("Look")
            subtitle: Config.sidebarIslands ? "Islands, like the top bar" : "One pill per region"
            help:    Translation.tr("Islands give each group its own pill. The hero sits on a tinted chip, as the top bar's clock does. The music makes the pills breathe and glow while something plays.")
            accent:  Colors.of(QsWindow.window).primary

            SettingRow {
                label:  Translation.tr("Islands")
                detail: Config.sidebarIslands ? "A pill per group" : "One pill per region, with dividers"
                Toggle { checked: Config.sidebarIslands; onToggled: Config.sidebarIslands = !Config.sidebarIslands }
            }
            SettingRow {
                label:  Translation.tr("With the music")
                detail: Config.barMusicReact ? "Both bars' pills glow while music plays" : "Still"
                Toggle { checked: Config.barMusicReact; onToggled: Config.barMusicReact = !Config.barMusicReact }
            }

            StyledText {
                text: Translation.tr("Hero")
                variant: "caption"
                emphasis: "dim"
            }
            // The modules that can wear the hero's chip, of those on the sidebar.
            ChipTray {
                id: heroTray
                // ChipTray lays its children in a row of its own: `parent` below would be that row.
                readonly property var heroable: ["claude", "nowplaying", "timer", "tasks", "clipboard",
                                                 "colour", "inactivity", "power", "voice"]
                ChipButton {
                    label: Translation.tr("None")
                    tint: Colors.of(QsWindow.window).primary
                    on: Config.sidebarHero === ""
                    onActivated: Config.sidebarHero = ""
                }
                Repeater {
                    model: heroTray.heroable.filter(id => Config.sidebarPlaced(id))
                    ChipButton {
                        required property string modelData
                        label: Config.sidebarModuleList.find(m => m.id === modelData)?.label ?? modelData
                        tint: Colors.of(QsWindow.window).primary
                        on: Config.sidebarHero === modelData
                        onActivated: Config.sidebarHero = modelData
                    }
                }
            }
        }

        // ══ Peeks ═════════════════════════════════════════════════════════════
        // A card beside a module for a moment when something happens to it (EventPeek).
        Section {
            span:    1
            symbol:  "notifications_active"
            title:   Translation.tr("Peeks")
            subtitle: [Config.peekTimer, Config.peekClaude, Config.peekColour, Config.peekClipboard]
                          .filter(b => b).length + " of 4 on"
            help:    Translation.tr("When something happens to a module, a card opens beside it for a moment — on the monitor you're on, and never over a panel you opened.")
            accent:  Colors.of(QsWindow.window).primary

            SettingRow {
                label:  Translation.tr("Timer")
                detail: Config.peekTimer ? "Finished or ringing, to dismiss or snooze" : "Off"
                Toggle { checked: Config.peekTimer; onToggled: Config.peekTimer = !Config.peekTimer }
            }
            SettingRow {
                label:  Translation.tr("Claude")
                detail: Config.peekClaude ? "Needs you, or finished a turn" : "Off"
                Toggle { checked: Config.peekClaude; onToggled: Config.peekClaude = !Config.peekClaude }
            }
            SettingRow {
                label:  Translation.tr("Colour picker")
                detail: Config.peekColour ? "The colour picked, and its hex" : "Off"
                Toggle { checked: Config.peekColour; onToggled: Config.peekColour = !Config.peekColour }
            }
            SettingRow {
                label:  Translation.tr("Clipboard")
                detail: Config.peekClipboard ? "Every copy's preview" : "Off"
                help:   Translation.tr("Copies a password manager marks as secret never reach the history, so they never peek.")
                Toggle { checked: Config.peekClipboard; onToggled: Config.peekClipboard = !Config.peekClipboard }
            }
        }

        // ══ Arranging ═════════════════════════════════════════════════════════
        Section {
            span:    3
            glyph:   "󰘇"
            title:   Translation.tr("Arrange")
            subtitle: UiState.sidebarArrange ? "Drag modules onto the sidebar" : "Press Arrange to drag"
            help:    Translation.tr("Drag one onto the sidebar, along it to move it, onto another to group them, or off it onto this card to take it off.")
            accent:  Colors.of(QsWindow.window).primary

            SideModuleTray {
                Layout.fillWidth: true
            }
        }
    }
}
