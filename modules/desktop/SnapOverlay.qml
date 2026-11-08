import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../config"
import "../../components"
import "../../services"
import "../../services/snap.js" as SnapJs

// ── SnapOverlay ───────────────────────────────────────────────────────────────
// Where a carried floating window will snap (services/Snap): the half, quarter or whole
// screen, as a frosted outline in the window's own corner, with its name in a pill.
//
// Mapped only while a floating window is carried (`Snap.active`), on every screen — the
// pointer may cross to another — and the outline shows on the one under it. Click-
// through (an empty input mask) and keyboard-less: the drag is Hyprland's. On the
// Overlay layer, so the outline is drawn OVER the window in your hand; the fill is light
// enough that the window reads through it.
//
// The outline glides from zone to zone and shrinks out where it was when the pointer
// leaves one (`Snap.rect` keeps its last value — the fade-keeps-its-copy rule).
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: root

    readonly property var monitor: Hypr.monitorFor(root.screen)
    readonly property bool here: Snap.active && Snap.zone !== "" && Snap.monitorName === (root.monitor?.name ?? "")

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-snap"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.exclusiveZone: -1
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    color: "transparent"
    mask: Region {}

    visible: Snap.active || zone.opacity > 0.01

    // The label held for the fade, like the rect.
    property string heldLabel: ""
    onHereChanged: if (root.here) root.heldLabel = SnapJs.label(Snap.zone)
    Connections {
        target: Snap
        function onZoneChanged() { if (root.here) root.heldLabel = SnapJs.label(Snap.zone) }
    }

    Rectangle {
        id: zone
        readonly property var r: Snap.rect ?? ({ x: 0, y: 0, w: 0, h: 0 })
        x: zone.r.x - (root.monitor?.x ?? 0)
        y: zone.r.y - (root.monitor?.y ?? 0)
        width: zone.r.w
        height: zone.r.h
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).focus, 0.12)
        border.width: Tokens.borderChrome + 1
        border.color: Colors.of(QsWindow.window).focus

        opacity: root.here ? 1 : 0
        scale: root.here ? 1 : 0.96
        Behavior on opacity { NumberAnimation { duration: root.here ? Motion.respond : Motion.exit } }
        Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        // Zone to zone is a glide; the first appearance isn't (it would fly in from 0,0).
        Behavior on x      { enabled: zone.opacity > 0.01; NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on y      { enabled: zone.opacity > 0.01; NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on width  { enabled: zone.opacity > 0.01; NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }
        Behavior on height { enabled: zone.opacity > 0.01; NumberAnimation { duration: Motion.standard; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel } }

        Surface {
            anchors.centerIn: parent
            elevation: Tokens.elevationCard
            cornerRadius: height / 2
            implicitWidth: pill.implicitWidth + Tokens.spacingXl * 2
            implicitHeight: pill.implicitHeight + Tokens.spacingMd * 2
            Row {
                id: pill
                anchors.centerIn: parent
                spacing: Tokens.spacingSm
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "dashboard"
                    color: Colors.of(QsWindow.window).focus
                    font.pixelSize: Tokens.iconSm
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.heldLabel
                    variant: "label"
                    font.weight: Font.DemiBold
                }
            }
        }
    }

    // The wave: a shell window that's up during a theme change takes it on the front.
    Infection {
        host: root.contentItem
        screen: root.screen
        hostVisible: root.visible
    }
}
