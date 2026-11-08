pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../../state"

// ── WindowPeek ────────────────────────────────────────────────────────────────
// Windows' Aero Peek, from the dock: rest on a window in a dock preview and the
// screen shows that window's WORKSPACE — every window on it, live, where it sits —
// with the one you're pointing at lit and outlined and the rest faded back. A
// glance, not a switch: nothing is focused or moved, and it's gone the moment the
// pointer leaves the tile. DockPreview asks for it (UiState.dockPeek, after a
// dwell); the Bar on the window's own monitor draws it.
//
// ── Why it's in Bar's window, at the bottom ──────────────────────────────────
// Declared FIRST in Bar.qml, under everything else the window draws — the frame,
// the bar, the dock and the very preview you're hovering all stay on top of it,
// while it covers the ordinary windows underneath (the window is the whole screen
// whenever the dock is on, and the peek only comes from the dock). A layer surface
// of its own would map after the bar and cover the dock.
//
// It takes no input (it isn't in Bar's mask), and captures only while shown.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: peek

    // This Bar's monitor: the peek draws where the window is, not where the dock is.
    required property var monitor

    readonly property string address: UiState.dockPeek
    readonly property var target: {
        if (peek.address === "") return null
        const ws = Hypr.windows
        for (let i = 0; i < ws.length; i++) if (ws[i].address === peek.address) return ws[i]
        return null
    }
    readonly property bool here: peek.target !== null && peek.monitor !== null
                                 && (peek.target.monitor?.name ?? "") === (peek.monitor?.name ?? "")
    readonly property int workspace: peek.here ? peek.target.workspaceId : -1

    // ── How the windows are drawn ─────────────────────────────────────────────
    // Every window at its real place and size. The lit one only slightly
    // see-through — it's a glance, not the window (the user asked for "slightly":
    // 85% read as far too transparent); the rest faded back.
    readonly property real litOpacity: 0.97
    readonly property real dimOpacity: 0.3

    // The workspace's windows, tiled first then floating (how they stack), and the
    // peeked one last so its outline is never under a neighbour.
    readonly property var windows: {
        if (!peek.here) return []
        const on = Hypr.windows.filter(w => w.workspaceId === peek.workspace)
        const rank = w => w.address === peek.address ? 2 : w.floating ? 1 : 0
        return on.slice().sort((a, b) => rank(a) - rank(b))
    }

    // Geometry fresh while a peek is asked for: Hypr's event tier (refresh on
    // Hyprland's own events, debounced) — held only then.
    readonly property bool wanted: peek.address !== ""
    property bool _held: false
    onWantedChanged: {
        if (peek.wanted === peek._held) return
        if (peek.wanted) Hypr.acquireEvents(); else Hypr.releaseEvents()
        peek._held = peek.wanted
    }
    Component.onDestruction: if (peek._held) Hypr.releaseEvents()

    opacity: peek.here ? 1 : 0
    visible: peek.opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

    // Everything else, pushed back.
    Rectangle {
        anchors.fill: parent
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).shadow, 0.55)
    }

    Repeater {
        model: ScriptModel { values: peek.visible ? peek.windows : []; objectProp: "address" }

        delegate: Item {
            id: win
            required property var modelData
            readonly property bool lit: win.modelData.address === peek.address

            x: win.modelData.at[0] - (peek.monitor?.x ?? 0)
            y: win.modelData.at[1] - (peek.monitor?.y ?? 0)
            width:  win.modelData.size[0]
            height: win.modelData.size[1]
            opacity: win.lit ? peek.litOpacity : peek.dimOpacity
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

            // The window, live, rounded like the compositor rounds it.
            Item {
                id: shot
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: shotMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                ScreencopyView {
                    anchors.fill: parent
                    captureSource: peek.visible ? win.modelData.wayland : null
                    live: peek.visible
                }
            }
            Item {
                id: shotMask
                anchors.fill: shot
                visible: false
                layer.enabled: true
                Rectangle { anchors.fill: parent; radius: Tokens.radiusCard; color: "white" }
            }

            // The one you're pointing at.
            Rectangle {
                anchors.fill: parent
                anchors.margins: -Tokens.borderChrome
                radius: Tokens.radiusCard + Tokens.borderChrome
                color: "transparent"
                border.width: Tokens.borderChrome
                border.color: Colors.of(QsWindow.window).focus
                visible: win.lit
            }
        }
    }

    // Which workspace this is — the glance's one line of text.
    Surface {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Config.barExtent + Tokens.spacingXl
        elevation: Tokens.elevationPopup
        cornerRadius: Tokens.radiusPill
        width:  chip.implicitWidth + Tokens.spacingLg * 2
        height: chip.implicitHeight + Tokens.spacingSm * 2
        visible: peek.workspace > 0

        Row {
            id: chip
            anchors.centerIn: parent
            spacing: Tokens.spacingSm
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\u{F0570}"                                       // 󰕰 view-grid
                color: Colors.of(QsWindow.window).focus
                variant: "label"
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Workspace " + peek.workspace
                variant: "label"
                font.bold: true
            }
        }
    }
}
