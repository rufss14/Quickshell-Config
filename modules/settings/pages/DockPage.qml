pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── DockPage — Sidebar & dock › Dock ───────────────────────────────────────────
// The persistent app dock's settings. The dock itself (modules/bar/DockHost, over the
// shared DockIconStrip and the Taskbar service) owns every behaviour; this sets what it
// shows and how. Where it sits and how big its icons are is the Sidebar view's (one
// edge, one icon size for the whole sidebar), and this page shows the result.
//
// ── Pins ──────────────────────────────────────────────────────────────────────
// Pins are managed on the dock itself (right-click, drag); the list here is for the one
// case the dock can't show, a pin whose app was uninstalled, and for unpinning in one
// place. (A second, edit-mode strip used to sit beside it for reordering; the dock's own
// drag does that.)
//
// ── The weld is stated only when it is missing ────────────────────────────────
// Melting out of the frame needs three things at once: the Morph plugin built, the
// screen frame on, and the bar anchored (the blob only owns the ring then). Any one
// missing and the dock quietly falls back to an ordinary card, which reads as the
// feature not working. So when it ISN'T welded a card says which of the three is
// missing, with the fix one click away; when it is, the heading says "welded" and
// nothing else is spent on it.
//
// ── A tab again, and one screen ───────────────────────────────────────────────
// It was a GROUP of the composed Sidebar & dock scroll; Settings keeps tab strips, so
// it is its own view once more. Laid out to fit: the real strip at the top with what
// it shows (scope) in its heading and what stands on it (start button, downloads,
// trash) as chips right under it — the chips change the picture they sit under. Then
// behaviour beside zoom & length, then the pins. The gesture list that was a card of
// its own is the strip's tip.
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root

    // What stands between the dock and the weld, most fundamental first: without the
    // plugin nothing can melt; without a frame there's nothing to melt into; with the
    // bar floating the blob doesn't own the ring. "" = welded.
    readonly property string weldBlocker:
          !Morph.available     ? "plugin"
        : !Config.screenFrame  ? "frame"
        : !Config.barAnchored  ? "anchor"
        :                        ""

    SettingsPage {
        anchors.fill: parent

        bento:     true
        glyph:     "󰀻"
        title:     Translation.tr("Dock")
        accent:    Colors.of(QsWindow.window).primary
        subtitle:  !Config.dockEnabled ? "Off"
                 : [Config.dockPosition,
                    Config.sidebarAutoHide ? "auto-hides with the sidebar" : "always shown",
                    root.weldBlocker === "" ? "welded into the frame" : "floating"].join("  ·  ")

        actions: Toggle {
            accent:  Colors.of(QsWindow.window).primary
            checked: Config.dockEnabled
            onToggled: Config.sidebarToggle("dock")
        }

        // ══ The weld, when it is missing ══════════════════════════════════════
        // State what is missing, not what is fine: welded is a word in the header.
        Section {
            span:    3
            visible: root.weldBlocker !== ""
            enabled: Config.dockEnabled
            opacity: Config.dockEnabled ? 1 : 0.5
            glyph:   "\u{F0343}"                                  // magnet
            title:   Translation.tr("Floating, not welded")
            accent:  Colors.of(QsWindow.window).warning
            subtitle: root.weldBlocker === "plugin" ? "The Morph plugin isn't built"
                    : root.weldBlocker === "frame"  ? "There's no screen frame to melt out of"
                    :                                 "The bar isn't anchored to the frame"
            help: root.weldBlocker === "plugin"
                ? "Without the plugin the dock sits flush against the frame instead of melting out of it. Setup's Morph plugin row has the build command."
                : root.weldBlocker === "frame"
                ? "The screen frame is a thin ring of the bar's material around the screen; the bar and panels weld into it too."
                : "The frame only welds while the bar is anchored to it. Anchoring keeps the bar's shape."

            actions: PanelButton {
                capsule: true
                variant: "primary"
                accent:  Colors.of(QsWindow.window).primary
                label: root.weldBlocker === "plugin" ? "Open Setup"
                     : root.weldBlocker === "frame"  ? "Turn on the frame"
                     :                                 "Anchor the bar"
                onActivated: {
                    if (root.weldBlocker === "plugin")
                        UiState.openSettingsTo("SetupPage.qml")
                    else if (root.weldBlocker === "frame")
                        Config.screenFrame = true
                    else
                        Config.barLayout = "unifiedAnchored"
                }
            }
        }

        // ══ Your dock ═════════════════════════════════════════════════════════
        // The real strip over the real apps, in the frame's material — a picture of
        // the dock, not a second one: `enabled: false` makes it inert, so nothing
        // launches from the settings page.
        Section {
            span:    3
            enabled: Config.dockEnabled
            opacity: Config.dockEnabled ? 1 : 0.5
            glyph:   "\u{F0A68}"                                  // resize
            title:   Translation.tr("Your dock")
            accent:  Colors.of(QsWindow.window).primary
            help:    Translation.tr("Click an app to open it or go to its next window; Shift-click for a new one; middle-click closes its newest window. ")
                   + "Right-click for its jump list. Scroll over it for its volume, or its windows. "
                   + "Drag pins to reorder, or off the dock to unpin. Drop a file on an app to open it there. "
                   + "Super+T puts the keyboard on the dock; Super+Alt+1–9 opens its nth app."

            // What it lists: in the heading, beside the picture it changes.
            actions: TabStrip {
                implicitWidth: 300
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "all",       label: "All apps",   icon: "apps" },
                    { value: "monitor",   label: "Screen",     icon: "monitor" },
                    { value: "workspace", label: "Workspace",  icon: "workspaces" }
                ]
                current: Config.dockScope
                onPicked: function (v) { Config.dockScope = v }
            }

            PreviewStage {
                Layout.fillWidth: true
                Layout.preferredHeight: Config.dockThickness + Tokens.spacingLg * 2
                checkered: false
                clip: true

                Rectangle {
                    anchors.centerIn: parent
                    width:  Math.min(parent.width - Tokens.spacingLg * 2, previewStrip.implicitWidth + Tokens.spacingSm * 2)
                    height: Config.dockThickness
                    radius: Tokens.radiusCard
                    color:  Colors.of(QsWindow.window).frameFill
                    border.width: Tokens.borderWidth
                    border.color: Colors.of(QsWindow.window).frameLine

                    DockIconStrip {
                        id: previewStrip
                        anchors.centerIn: parent
                        enabled: false
                        edge: "bottom"
                        maxLength: parent.parent.width - Tokens.spacingLg * 2 - Tokens.spacingSm * 2
                    }
                }
            }

            // What stands on it besides your apps: a set, so chips, and they change
            // the strip right above them.
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
        }

        // ══ How it behaves ════════════════════════════════════════════════════
        // Switch rows rather than tiles: four booleans of one kind in one card is
        // the dense case docs/settings-style.md §6 allows, and four tiles would be a
        // screen of their own.
        Section {
            span:    1
            enabled: Config.dockEnabled
            opacity: Config.dockEnabled ? 1 : 0.5
            glyph:   "󰒓"
            title:   Translation.tr("Behaviour")
            accent:  Colors.of(QsWindow.window).primary

            // The buttons' look: the picture above changes with it.
            SettingRow {
                label:  Translation.tr("Style")
                detail: Config.dockStyle === "ii" ? Translation.tr("Flat buttons, a dot per window, a keep and an overview button")
                                                  : Translation.tr("Bar-styled, with a swell and a travelling focus pill")
                help:   "ii is End-4's dock: flat rounded buttons, up to three dots under an app (one per window), hairlines between groups, a keep button before the apps (when the sidebar auto-hides — it holds the dock out) and an overview button after them. It has no magnification."
                TabStrip {
                    implicitWidth: 200
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
                label:  Translation.tr("Previews")
                detail: Config.dockPreviews ? "Live thumbnails on hover" : "Just the app's name"
                help:   Translation.tr("Hover an app for a live thumbnail of each of its windows.")
                Toggle {
                    checked: Config.dockPreviews
                    onToggled: Config.dockPreviews = !Config.dockPreviews
                }
            }
            SettingRow {
                label:  Translation.tr("Peek")
                detail: Config.dockPeek ? "Glance at a window's workspace" : "Off"
                help:   Translation.tr("Rest on a window in a preview to glance at its workspace, with that window lit.")
                Toggle {
                    checked: Config.dockPeek
                    onToggled: Config.dockPeek = !Config.dockPeek
                }
            }
            // Only a welded dock has a lobe to melt out of — said, not hidden.
            SettingRow {
                label:  Translation.tr("Melting")
                enabled: root.weldBlocker === ""
                detail: root.weldBlocker !== "" ? "Needs the dock welded"
                      : Config.dockPreviewFuse  ? "Menus melt out of the dock"
                      :                           "Menus float as cards"
                help:   Translation.tr("Previews and the right-click menu melt out of the dock, inside its length, instead of floating above it.")
                Toggle {
                    checked: Config.dockPreviewFuse && root.weldBlocker === ""
                    onToggled: Config.dockPreviewFuse = !Config.dockPreviewFuse
                }
            }
            SettingRow {
                label:  Translation.tr("Inner pill")
                detail: Config.dockInnerPill ? "Running apps share a pill" : "Icons straight on the dock"
                help:   Translation.tr("Running apps sit on a pill, neighbours sharing one — like the bar's workspaces.")
                Toggle {
                    checked: Config.dockInnerPill
                    onToggled: Config.dockInnerPill = !Config.dockInnerPill
                }
            }
        }

        // ══ Zoom and length ═══════════════════════════════════════════════════
        Section {
            span:    1
            enabled: Config.dockEnabled
            opacity: Config.dockEnabled ? 1 : 0.5
            glyph:   "󰤼"
            title:   Translation.tr("Zoom & length")
            accent:  Colors.of(QsWindow.window).primary

            SettingRow {
                label:  Translation.tr("Magnify")
                enabled: Config.dockStyle !== "ii"
                detail: Config.dockStyle === "ii" ? Translation.tr("Not in the ii style — it is flat")
                      : Config.dockMagnify ? Translation.tr("Icons swell toward the pointer") : Translation.tr("Only the hovered icon lifts")
                Toggle {
                    checked: Config.dockMagnify
                    onToggled: Config.dockMagnify = !Config.dockMagnify
                }
            }
            // How big the icon under the pointer grows, while magnification is on.
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

            // Too many apps for the edge: stop at a cap and scroll, or keep growing.
            TabStrip {
                Layout.fillWidth: true
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "clip", label: "Stop at a cap", icon: "crop" },
                    { value: "grow", label: "Grow",          icon: "open_with" }
                ]
                current: Config.dockOverflow
                onPicked: function (v) { Config.dockOverflow = v }
            }
            // Clip's cap, as a share of the room the dock has along its edge.
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

        // ══ Pinned ════════════════════════════════════════════════════════════
        // The one place to see every pin at once — including a pin whose app has
        // since been uninstalled, which the dock can only show faded.
        Section {
            span:     3
            glyph:    "󰐃"
            title:    Translation.tr("Pinned")
            accent:   Colors.of(QsWindow.window).primary
            subtitle: Taskbar.pinned.length === 0 ? "Nothing pinned"
                    : Taskbar.pinned.length + (Taskbar.pinned.length === 1 ? " app" : " apps")
            help:     Translation.tr("Pin from an app's right-click menu in the dock. Reorder by dragging on the dock itself. Shared with the launcher.")

            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                visible: Taskbar.pinned.length > 0

                Repeater {
                    model: Taskbar.pinned

                    delegate: Rectangle {
                        id: chip
                        required property string modelData

                        readonly property bool launchable: Taskbar.canPin(chip.modelData)
                        readonly property string iconPath: Taskbar.iconFor(chip.modelData)

                        width:  chipRow.implicitWidth + Tokens.spacingMd * 2
                        height: Tokens.fieldHeight
                        radius: Tokens.radiusPill
                        color:  "transparent"
                        border.width: Tokens.borderWidth
                        border.color: unpinMouse.containsMouse ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.6)
                                                               : Colors.of(QsWindow.window).outlineFor(Tokens.elevationNested)
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        Row {
                            id: chipRow
                            anchors.centerIn: parent
                            spacing: Tokens.spacingSm

                            Image {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: chip.iconPath !== ""
                                source:  chip.iconPath
                                width:  Tokens.iconMd
                                height: Tokens.iconMd
                                sourceSize: Qt.size(Tokens.iconMd, Tokens.iconMd)
                                opacity: chip.launchable ? 1 : 0.4
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Taskbar.nameFor(chip.modelData)
                                    + (chip.launchable ? "" : "  (not installed)")
                                variant: "label"
                                emphasis: chip.launchable ? "normal" : "dim"
                            }
                            MaterialIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: "close"
                                font.pixelSize: Tokens.iconSm
                                color: unpinMouse.containsMouse ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                MouseArea {
                                    id: unpinMouse
                                    anchors.fill: parent
                                    anchors.margins: -Tokens.spacingXs
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Taskbar.unpin(chip.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
