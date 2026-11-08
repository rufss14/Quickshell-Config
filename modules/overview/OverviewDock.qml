import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"

// ── OverviewDock ──────────────────────────────────────────────────────────────
// The dock along the bottom of the overview. Everything it does — the launcher
// button, pinned and running apps, the jump list, drag-to-reorder — is the shared
// DockIconStrip, over the Taskbar service; this file is only the overview's own
// island Surface around it.
//
// Its hover preview is NOT in here: it's a DockPreview beside this dock in
// Overview.qml, fed `strip.previewCenter` through `previewCenter` below. A card
// parented into a 72px-tall dock at the bottom of the screen couldn't be drawn
// anywhere it would fit.
// ─────────────────────────────────────────────────────────────────────────────
Surface {
    id: root

    // The shared ContextMenu instance, owned by Overview.qml and handed down.
    property var contextMenu: null

    // The Overview instance's own screen and monitor: where a launcher opened from
    // here appears, and where a focus lands (see Hypr.goToToplevel).
    property var screen:  null
    property var monitor: null

    // Bound by Overview.qml to its DockPreview's hover — see
    // DockIconStrip.previewHovered.
    property bool previewHovered: false

    readonly property alias strip: strip

    // The previewed button's centre, in THIS item's coordinates (-1 for none).
    readonly property real previewCenter:
        strip.previewCenter < 0 ? -1 : strip.x + strip.previewCenter

    elevation:    Tokens.elevationCard
    cornerRadius: Tokens.radiusXl      // the overview's shared island corner

    implicitWidth:  strip.implicitWidth  + Tokens.spacingLg * 2
    implicitHeight: strip.implicitHeight + Tokens.spacingLg * 2

    DockIconStrip {
        id: strip
        anchors.centerIn: parent
        edge:           "bottom"
        contextMenu:    root.contextMenu
        screen:         root.screen
        monitor:        root.monitor
        previewHovered: root.previewHovered
        onActivated:    UiState.overviewOpen = false
    }
}
