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
    columnSpacing: Tokens.spacingXxl
    rowSpacing: Tokens.spacingMd
    Layout.fillWidth: true
    Layout.fillHeight: false

    // Why previews and menus can't melt out of the dock, or "".
    readonly property string weldBlocker:
          !Morph.available     ? "The Morph plugin isn't built (Setup has the build command)"
        : !Config.screenFrame  ? "There's no screen frame to melt out of"
        : !Config.barAnchored  ? "The bar isn't anchored to the frame"
        :                        ""

    // ── What it shows ─────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: Tokens.spacingSm

        SettingRow {
            label:  Translation.tr("Apps")
            detail: Config.dockScope === "all" ? "Every running app"
                  : Config.dockScope === "monitor" ? "Apps on this screen" : "Apps on this workspace"
            help:   Translation.tr("Click an app to open it or go to its next window; Shift-click for a new one; middle-click closes its newest window. Right-click for its jump list. Super+T puts the keyboard on the dock; Super+Alt+1–9 opens its nth app.")
            TabStrip {
                implicitWidth: 220
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "all",       label: "All",       icon: "apps" },
                    { value: "monitor",   label: "Screen",    icon: "monitor" },
                    { value: "workspace", label: "Workspace", icon: "workspaces" }
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
                hint:   Translation.tr("At the dock's end — click it for your newest files.")
                active: Config.dockShowDownloads
                onToggled: Config.dockShowDownloads = !Config.dockShowDownloads
            }
            ToggleChip {
                symbol: "delete"
                label:  Translation.tr("Trash")
                hint:   Translation.tr("At the dock's end — drop files on it; right-click it to empty.")
                active: Config.dockShowTrash
                onToggled: Config.dockShowTrash = !Config.dockShowTrash
            }
        }

        SettingRow {
            label:  Translation.tr("Style")
            detail: Config.dockStyle === "ii" ? Translation.tr("Flat buttons, a dot per window, a keep and an overview button")
                                              : Translation.tr("Bar-styled, with a swell and a travelling focus pill")
            help:   Translation.tr("ii is End-4's dock: flat rounded buttons, up to three dots under an app (one per window), hairlines between groups, a keep button before the apps (when the sidebar auto-hides — it holds the dock out) and an overview button after them. It has no magnification.")
            TabStrip {
                implicitWidth: 180
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
            label:  Translation.tr("Inner pill")
            detail: Config.dockInnerPill ? "Running apps share a pill" : "Icons straight on the dock"
            help:   Translation.tr("Running apps sit on a pill, neighbours sharing one — like the bar's workspaces.")
            Toggle { checked: Config.dockInnerPill; onToggled: Config.dockInnerPill = !Config.dockInnerPill }
        }

        // ── Pinned ────────────────────────────────────────────────────────────
        StyledText {
            Layout.topMargin: Tokens.spacingSm
            text: Taskbar.pinned.length === 0 ? Translation.tr("Nothing pinned — pin from an app's right-click menu")
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
                    label: Taskbar.nameFor(modelData) + (Taskbar.canPin(modelData) ? "" : "  (not installed)")
                    symbol: "close"
                    tint: Colors.of(QsWindow.window).danger
                    onActivated: Taskbar.unpin(modelData)
                }
            }
        }
    }

    // ── How it moves ──────────────────────────────────────────────────────────
    ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredWidth: 0
        Layout.alignment: Qt.AlignTop
        spacing: Tokens.spacingSm

        SettingRow {
            label:  Translation.tr("Previews")
            detail: Config.dockPreviews ? "Live thumbnails on hover" : "Just the app's name"
            help:   Translation.tr("Hover an app for a live thumbnail of each of its windows.")
            Toggle { checked: Config.dockPreviews; onToggled: Config.dockPreviews = !Config.dockPreviews }
        }
        SettingRow {
            label:  Translation.tr("Peek")
            detail: Config.dockPeek ? "Glance at a window's workspace" : "Off"
            help:   Translation.tr("Rest on a window in a preview to glance at its workspace, with that window lit.")
            Toggle { checked: Config.dockPeek; onToggled: Config.dockPeek = !Config.dockPeek }
        }
        SettingRow {
            label:  Translation.tr("Melting")
            enabled: root.weldBlocker === ""
            detail: root.weldBlocker !== "" ? root.weldBlocker
                  : Config.dockPreviewFuse  ? "Menus melt out of the dock"
                  :                           "Menus float as cards"
            help:   Translation.tr("Previews and the right-click menu melt out of the dock, inside its length, instead of floating above it.")
            Toggle {
                checked: Config.dockPreviewFuse && root.weldBlocker === ""
                onToggled: Config.dockPreviewFuse = !Config.dockPreviewFuse
            }
        }
        SettingRow {
            label:  Translation.tr("Magnify")
            enabled: Config.dockStyle !== "ii"
            detail: Config.dockStyle === "ii" ? Translation.tr("Not in the ii style — it is flat")
                  : Config.dockMagnify ? Translation.tr("Icons swell toward the pointer") : Translation.tr("Only the hovered icon lifts")
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
            detail: Config.dockOverflow === "grow" ? "The dock grows along the edge" : "It stops at a cap and scrolls"
            TabStrip {
                implicitWidth: 180
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "clip", label: "Cap",  icon: "crop" },
                    { value: "grow", label: "Grow", icon: "open_with" }
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
