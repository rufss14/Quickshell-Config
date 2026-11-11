import QtQuick
import "../../../config"
import "../../../components"

// ── DockPill ──────────────────────────────────────────────────────────────────
// The dock as a top-bar module (the user's pick, 2026-11-08: "full, bar-sized, no
// magnification"): the sidebar's DockIconStrip at the bar's pill height, with the bar's
// press feel (`barFeedback`), its corners, its scope (Config.dockScope), pinned and running
// apps, the focus mark and the running dots on the windows' side (`edge: "top"`). No
// magnification and no "ii" style — a bar module is a row of pills.
//
// What hangs off it — the window previews, the jump list, the keyboard (SUPER+T,
// SUPER+ALT+n) — is Bar.qml's BarDockPopups, which fills the window; this registers its
// strip there (`popups`). One dock exists at a time: it has one place (the one-place rule).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property var screen: null
    property var monitor: null
    property var popups: null
    property string moduleId: "dock"

    implicitWidth:  strip.implicitWidth + Tokens.spacingXs * 2
    implicitHeight: strip.implicitHeight

    // Right-click on the pill around the icons: the dock's own menu (Move to the sidebar,
    // its settings) — DockHost's cardMouse, on the bar. Under the strip, so a button's own
    // right-click (its jump list) wins.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.RightButton
        onClicked: function (m) {
            const s = mapToItem(null, m.x, m.y)
            strip.openDockMenu(s.x, s.y)
        }
    }

    DockIconStrip {
        id: strip
        anchors.centerIn: parent
        edge:           "top"
        buttonSize:     Config.barPillHeight
        iconPx:         Math.round(Tokens.iconMd * Config.barIconScale)
        barFeedback:    true
        magnifyAllowed: false
        iiAllowed:      false
        roundness:      Config.barRoundness
        screen:         root.screen
        monitor:        root.monitor
        scope:          Config.dockScope
        contextMenu:    root.popups ? root.popups.menu : null
        previewHovered: root.popups ? root.popups.previewHovered : false
    }

    Component.onCompleted:   if (root.popups) root.popups.strip = strip
    Component.onDestruction: if (root.popups && root.popups.strip === strip) root.popups.strip = null
}
