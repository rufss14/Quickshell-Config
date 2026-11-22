pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── DockOptions ───────────────────────────────────────────────────────────────
// The dock's own settings, in the module inspector when the dock is the module picked.
// They were Sidebar & dock › Dock, a tab of their own with an on/off switch in its
// heading; the user's call (2026-11-08): the dock is a module like the rest — placed on
// the Modules page, its settings where every module's are. Moved, not redesigned: the
// same controls and wording as that page. The preview strip didn't come along — the
// map above draws the real dock.
// ─────────────────────────────────────────────────────────────────────────────
GridLayout {
    id: root

    readonly property bool wide: root.width >= 640
    columns: root.wide ? 2 : 1
    columnSpacing: Tokens.spacingLg
    rowSpacing: Tokens.spacingLg
    Layout.fillWidth: true
    Layout.fillHeight: false

    // Why previews and menus can't melt out of the dock, or "".
    readonly property string weldBlocker:
          !Morph.available     ? Translation.tr("The Morph plugin isn't built (Setup has the build command)")
        : !Config.screenFrame  ? Translation.tr("There's no screen frame to melt out of")
        : !Config.barAnchored  ? Translation.tr("The bar isn't anchored to the frame")
        :                        ""

    // ── What it shows ─────────────────────────────────────────────────────────
    // Grouped Sections side by side, one segment per row; the chips and the pinned list are one segment each.
    Section {
        grouped: true
        Layout.preferredWidth: 0
        symbol:  "dock_to_bottom"
        title:   Translation.tr("Dock")
        subtitle: Config.dockScope === "all" ? Translation.tr("Every running app")
                : Config.dockScope === "monitor" ? Translation.tr("Apps on this screen") : Translation.tr("Apps on this workspace")

        SettingRow {
            label:  Translation.tr("Apps")
            help:   Translation.tr("Click an app to open it or go to its next window; Shift-click for a new one; middle-click closes its newest window. Right-click for its jump list. Super+T puts the keyboard on the dock; Super+Alt+1–9 opens its nth app.")
            TabStrip {
                connected: true
                implicitWidth: Tokens.fieldHeight * 10
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "all",       label: Translation.tr("All"),       icon: "apps" },
                    { value: "monitor",   label: Translation.tr("Screen"),    icon: "monitor" },
                    { value: "workspace", label: Translation.tr("Workspace"), icon: "workspaces" }
                ]
                current: Config.dockScope
                onPicked: function (v) { Config.dockScope = v }
            }
        }

        Flow {
            Layout.fillWidth: true
            spacing: Tokens.spacingSm
            ToggleChip {
                symbol: "apps"
                label:  Translation.tr("Start button")
                hint:   Translation.tr("The app launcher, at the start of the dock. Without it, the launcher keybind (Super+R by default) still opens it.")
                active: Config.dockShowLauncher
                onToggled: Config.dockShowLauncher = !Config.dockShowLauncher
            }
            ToggleChip {
                symbol: "download"
                label:  Translation.tr("Downloads")
                hint:   Translation.tr("At the dock's end. Click it for your newest files.")
                active: Config.dockShowDownloads
                onToggled: Config.dockShowDownloads = !Config.dockShowDownloads
            }
            ToggleChip {
                symbol: "delete"
                label:  Translation.tr("Trash")
                hint:   Translation.tr("At the dock's end. Drop files on it; right-click it to empty.")
                active: Config.dockShowTrash
                onToggled: Config.dockShowTrash = !Config.dockShowTrash
            }
        }

        SettingRow {
            label:  Translation.tr("Style")
            detail: Config.dockStyle === "ii" ? Translation.tr("Flat buttons, a dot per window, a keep and an overview button")
                                              : Translation.tr("Bar-styled, with a swell and a travelling focus pill")
            help:   Translation.tr("ii is End-4's dock: flat rounded buttons, up to three dots under an app (one per window), hairlines between groups, a keep button before the apps (when the sidebar auto-hides, it holds the dock out) and an overview button after them. It has no magnification.")
            TabStrip {
                connected: true
                implicitWidth: Tokens.fieldHeight * 7
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "frame", label: Translation.tr("Frame"), icon: "dock_to_bottom" },
                    { value: "ii",    label: "ii",    icon: "dashboard" }
                ]
                current: Config.dockStyle
                onPicked: function (v) { Config.dockStyle = v }
            }
        }
        SettingRow {
            rowTap: true
            // Not "Inner pill": the inspector above this block has a row of that name for the module's own chip.
            label:  Translation.tr("Dock inner pill")
            detail: Config.dockInnerPill ? Translation.tr("Running apps share a pill") : Translation.tr("Icons straight on the dock")
            help:   Translation.tr("Running apps sit on a pill, neighbours sharing one, like the bar's workspaces.")
            onTapped: Config.dockInnerPill = !Config.dockInnerPill
            Toggle { checked: Config.dockInnerPill; onToggled: Config.dockInnerPill = !Config.dockInnerPill }
        }
        SliderRow {
            label: Translation.tr("App slots")
            help: Translation.tr("The sidebar's and the bar's dock always show this many app slots, with a dot for each one that is empty, so the dock never changes length and the modules next to it stay put. More apps than that scroll: use the wheel over the dock (Ctrl and the wheel is an app's own volume or windows). Off lets the dock grow with its apps.")
            from: 0
            to:   Config.dockSlotsMax
            step: 1
            value: Config.dockSlotCount
            readout: Config.dockSlotCount === 0 ? Translation.tr("Off") : Config.dockSlotCount + ""
            numberWidth: 44
            onCommit: function (v) { Config.dockSlots = Math.round(v) }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Icon tiles")
            detail: Config.dockIconPlate ? Translation.tr("A quiet tile behind every icon") : Translation.tr("Icons straight on the dock")
            help:   Translation.tr("On the sidebar's dock, every app icon sits on a tile of the same shape, so a round logo and a square one look like a set. The icons keep their colours.")
            onTapped: Config.dockIconPlate = !Config.dockIconPlate
            Toggle { checked: Config.dockIconPlate; onToggled: Config.dockIconPlate = !Config.dockIconPlate }
        }

        // ── Pinned ────────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm
            StyledText {
                text: Taskbar.pinned.length === 0 ? Translation.tr("Nothing pinned. Pin from an app's right-click menu")
                    : Translation.tr("Pinned") + "  ·  " + Taskbar.pinned.length
                variant: "caption"
                emphasis: "dim"
            }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                visible: Taskbar.pinned.length > 0
                Repeater {
                    model: Taskbar.pinned
                    delegate: ChipButton {
                        required property string modelData
                        label: Taskbar.nameFor(modelData) + (Taskbar.canPin(modelData) ? "" : Translation.tr("  (not installed)"))
                        symbol: "close"
                        tint: Colors.of(QsWindow.window).danger
                        onActivated: Taskbar.unpin(modelData)
                    }
                }
            }
        }
    }

    // ── How it moves ──────────────────────────────────────────────────────────
    Section {
        grouped: true
        Layout.preferredWidth: 0
        symbol:  "tune"
        title:   Translation.tr("How it moves")

        SettingRow {
            rowTap: true
            label:  Translation.tr("Previews")
            detail: Config.dockPreviews ? Translation.tr("Live thumbnails on hover") : Translation.tr("Just the app's name")
            help:   Translation.tr("Hover an app for a live thumbnail of each of its windows.")
            onTapped: Config.dockPreviews = !Config.dockPreviews
            Toggle { checked: Config.dockPreviews; onToggled: Config.dockPreviews = !Config.dockPreviews }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Peek")
            detail: Config.dockPeek ? Translation.tr("Glance at a window's workspace") : Translation.tr("Previews only")
            help:   Translation.tr("Rest on a window in a preview to glance at its workspace, with that window lit.")
            onTapped: Config.dockPeek = !Config.dockPeek
            Toggle { checked: Config.dockPeek; onToggled: Config.dockPeek = !Config.dockPeek }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Melting")
            enabled: root.weldBlocker === ""
            detail: root.weldBlocker !== "" ? root.weldBlocker
                  : Config.dockPreviewFuse  ? Translation.tr("Menus melt out of the dock")
                  :                           Translation.tr("Menus float as cards")
            help:   Translation.tr("Previews and the right-click menu melt out of the dock, inside its length, instead of floating above it.")
            onTapped: Config.dockPreviewFuse = !Config.dockPreviewFuse
            Toggle {
                checked: Config.dockPreviewFuse && root.weldBlocker === ""
                onToggled: Config.dockPreviewFuse = !Config.dockPreviewFuse
            }
        }
        SettingRow {
            rowTap: true
            label:  Translation.tr("Magnify")
            enabled: Config.dockStyle !== "ii"
            detail: Config.dockStyle === "ii" ? Translation.tr("Not in the ii style, which is flat")
                  : Config.dockMagnify ? Translation.tr("Icons swell toward the pointer") : Translation.tr("Only the hovered icon lifts")
            onTapped: Config.dockMagnify = !Config.dockMagnify
            Toggle { checked: Config.dockMagnify; onToggled: Config.dockMagnify = !Config.dockMagnify }
        }
        SliderRow {
            enabled: Config.dockMagnify && Config.dockStyle !== "ii"
            label: Translation.tr("Zoom")
            from:  Math.round(Config.dockMagnifyScaleMin * 100)
            to:    Math.round(Config.dockMagnifyScaleMax * 100)
            step:  5
            value: Math.round(Config.dockMagnifyPeak * 100)
            readout: Math.round(Config.dockMagnifyPeak * 100) + "%"
            onCommit: function (v) { Config.dockMagnifyScale = Math.round(v) / 100 }
        }
        SettingRow {
            label:  Translation.tr("Too many apps")
            detail: Config.dockOverflow === "grow" ? Translation.tr("The dock grows along the edge") : Translation.tr("It stops at a cap and scrolls")
            TabStrip {
                connected: true
                implicitWidth: Tokens.fieldHeight * 7
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "clip", label: Translation.tr("Cap"),  icon: "crop" },
                    { value: "grow", label: Translation.tr("Grow"), icon: "open_with" }
                ]
                current: Config.dockOverflow
                onPicked: function (v) { Config.dockOverflow = v }
            }
        }
        SliderRow {
            visible: Config.dockOverflow !== "grow"
            label: Translation.tr("Cap")
            help:  Translation.tr("How much of the edge the dock may take before it scrolls.")
            stepper: false
            from:  Config.dockClipLengthMin
            to:    Config.dockClipLengthMax
            step:  5
            value: Config.dockClipPercent
            readout: Config.dockClipPercent + "%"
            onCommit: function (v) { Config.dockClipLength = Math.round(v) }
        }
    }
}
