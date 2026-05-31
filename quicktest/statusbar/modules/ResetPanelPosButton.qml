import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "../../theming" as T

// ── ResetPanelPosButton ───────────────────────────────────────────────────────
// Resets all draggable popup panel windows back to their default position
// (flush below the bar, left-aligned with the bar margin) and fires a
// desktop notification confirming the action.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape: false

    // References to every draggable popup window — set by StatusBarRoot
    property var wallpaperPopup:  null
    property var brightnessPopup: null
    property var clockPopup:      null
    property var wifiPopup:       null

    // The default offset every panel starts at
    property int defaultX: 0   // set by StatusBarRoot to root.splitMargin + 8
    property int defaultY: 0   // set by StatusBarRoot to T.Theme.barHeight + 2

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  innerRow.implicitWidth + 16
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius { NumberAnimation { duration: T.Theme.animSlow; easing.type: Easing.OutCubic } }
    Behavior on color  { ColorAnimation  { duration: T.Theme.animFast } }

    // Hover overlay
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: ma.containsMouse ? T.Theme.hoverFull : "transparent"
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    // Flash overlay — briefly pulses accent on click
    Rectangle {
        id: flashOverlay
        anchors.fill: parent
        radius: parent.radius
        color: T.Theme.pw(T.Theme.pal?.colors?.color4, 0.35)
        opacity: 0
        SequentialAnimation {
            id: flashAnim
            running: false
            NumberAnimation { target: flashOverlay; property: "opacity"; to: 1.0; duration: 80;  easing.type: Easing.OutQuad }
            NumberAnimation { target: flashOverlay; property: "opacity"; to: 0.0; duration: 320; easing.type: Easing.InQuad }
        }
    }

    // Notification process
    Process {
        id: notifyProc
        running: false
        command: [
            "notify-send",
            "--app-name=Shell",
            "--urgency=low",
            "--icon=preferences-desktop",
            "Panel positions reset",
            "All panels have been moved back to their default position."
        ]
    }

    function resetAll() {
        if (wallpaperPopup)  { wallpaperPopup.dragOffsetX  = root.defaultX; wallpaperPopup.dragOffsetY  = root.defaultY }
        if (brightnessPopup) { brightnessPopup.dragOffsetX = root.defaultX; brightnessPopup.dragOffsetY = root.defaultY }
        if (clockPopup)      { clockPopup.dragOffsetX      = root.defaultX; clockPopup.dragOffsetY      = root.defaultY }
        if (wifiPopup)       { wifiPopup.dragOffsetX       = root.defaultX; wifiPopup.dragOffsetY       = root.defaultY }
        flashAnim.restart()
        notifyProc.running = false
        notifyProc.running = true
    }

    RowLayout {
        id: innerRow
        anchors.centerIn: parent
        spacing: 6

        Image {
            source: "../../theming/icons/resetpos.svg"
            width: 14; height: 14
            fillMode: Image.PreserveAspectFit
        }

        Text {
            text: "Reset"
            color: T.Theme.fg
            font {
                pixelSize: 11
                weight: Font.Medium
                family: T.Theme.fontFamily
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.resetAll()
    }
}
