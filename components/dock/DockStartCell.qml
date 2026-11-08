pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../../config"
import "../../services"
import "../../state"
import "../../services/dock.js" as DockJs
import "../../services/workspaces.js" as Wsp
import ".."
import "."

// DockStartCell — DockIconStrip's inline `StartCell`, moved into its own file (2026-11-08).
// ── The buttons before the apps: the start button, and (ii) the keep button ──
// Both wash and answer the same way; they differ in what they show and do.
Item {
    id: leadCell
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip

    // The reserved key its hover label is filed under ("__launcher" / "__keep").
    property string hoverKey: ""
    property string symbol: ""
    property string glyph:  ""
    property bool   open:   false
    // The dock's main button (the sidebar's launcher, 2026-10-31): Material's FAB — the
    // glyph on a filled rounded square in the accent, the apps' themed plates being the
    // quieter tone beside it. Open, it rounds into a circle on the spatial spring.
    property bool   hero:   false
    // Where the keyboard is, while it's on this one.
    property bool   kbRing: false
    // Its slot along the strip.
    property real   at: 0
    signal clicked()

    width:  strip.button
    height: strip.button
    x: strip.vertical ? 0 : leadCell.at
    y: strip.vertical ? leadCell.at : 0

    DockWash { strip: leadCell.strip;
        id: leadWash
        hovered: leadMouse.containsMouse
    }

    DockFocusRing { strip: leadCell.strip; visible: leadCell.kbRing }

    Rectangle {
        anchors.fill: parent
        radius: strip.cellRadius
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
        opacity: leadCell.open && !leadCell.hero ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
    }

    SpringValue {
        id: heroRound
        spec: Motion.springSpatial
        epsilon: 0.002
        target: leadCell.open ? 1 : 0
    }
    Rectangle {
        id: heroPlate
        visible: leadCell.hero
        anchors.centerIn: parent
        width:  strip.iconPx
        height: strip.iconPx
        scale: strip.barFeedback ? leadWash.lift : 1
        // Material's large corner on a FAB is about 0.3 of its side; open, a circle.
        radius: Tokens.corner(Config.barShape, width * (0.3 + 0.2 * Math.max(0, Math.min(1, heroRound.value))))
        color: Colors.of(QsWindow.window).primary
    }

    MaterialIcon {
        anchors.centerIn: parent
        name:  leadCell.symbol
        glyph: leadCell.glyph
        fill:  leadCell.open ? 1 : 0
        // On the plate it is the plate's glyph: Android's 2/3, in the colour made for it.
        font.pixelSize: leadCell.hero ? Math.round(strip.iconPx * 0.64) : strip.iconPx
        color: leadCell.hero ? Colors.of(QsWindow.window).fgOnPrimary
             : leadCell.open ? Colors.of(QsWindow.window).primary : Colors.of(QsWindow.window).fg
        transformOrigin: strip.magnifying ? strip.magnifyOrigin : Item.Center
        scale: (strip.barFeedback ? leadWash.lift : 1)
             * (leadMouse.pressed ? strip.pressScale
                : strip.magnifying ? strip.magnifyAt(leadCell.at + strip.button / 2)
                : leadMouse.containsMouse ? strip.hoverScale : 1.0)
        // Not on the sidebar: the lift is a spring already, and easing it again would chase.
        Behavior on scale {
            enabled: !strip.magnifying && !strip.barFeedback
            NumberAnimation { duration: Motion.respond; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }
        Behavior on color { ColorAnimation { duration: Motion.respond } }
    }

    MouseArea {
        id: leadMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: m => leadWash.press(m.x, m.y)
        onReleased: leadWash.release()
        onCanceled: leadWash.release()
        onClicked: leadCell.clicked()
        onContainsMouseChanged: strip._hover(leadCell.hoverKey, leadMouse.containsMouse)
    }
}
