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

// DockTailButton — DockIconStrip's inline `TailButton`, moved into its own file (2026-11-08).
// ── The far end: pinned files and folders, the drop slot, Downloads, Trash ─
Item {
    id: tail
    // The DockIconStrip this belongs to (its state and its actions; was `root`).
    required property var strip
    required property string modelData
    readonly property string key: tail.modelData
    readonly property var  file:    strip.fileFor(tail.key)
    readonly property bool isTrash: tail.key === "__trash"
    readonly property bool isSlot:  tail.key === "__pin"
    readonly property bool armed:   tail.isTrash && strip.trashArmed
    readonly property bool dropHot: (tail.isTrash && strip.fileDropIndex === strip.trashSlot)
                                  || (tail.isSlot && strip.fileDropIndex === strip.pinSlotIndex)
    readonly property int  kbAt:    strip.kbTail.indexOf(tail.key)
    readonly property bool kbHere:  tail.kbAt >= 0 && strip.kbIndex === strip.count + tail.kbAt

    width:  strip.button
    height: strip.button
    readonly property real pos: Math.max(0, strip.tailPos(tail.key))
    x: strip.vertical ? 0 : tail.pos
    y: strip.vertical ? tail.pos : 0
    Behavior on x { NumberAnimation { duration: Motion.emphasized
                    easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
    Behavior on y { NumberAnimation { duration: Motion.emphasized
                    easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }

    DockWash { strip: tail.strip;
        id: tailWash
        hovered: tailMouse.containsMouse || tail.dropHot || tail.kbHere
    }
    DockFocusRing { strip: tail.strip;
        visible: tail.armed || tail.dropHot || tail.kbHere
        border.color: tail.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).focus
    }

    // The drop slot: an outlined space with a plus — "put it here".
    Rectangle {
        visible: tail.isSlot
        anchors.fill: parent
        anchors.margins: Tokens.spacingSm
        radius: strip.cellRadius
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.35)
    }

    Item {
        id: tailFace
        anchors.fill: parent
        // Swells with the others under magnification (see face in AppButton).
        readonly property real magnified: strip.magnifying ? strip.magnifyAt(tail.pos + strip.button / 2) : 1.0
        transformOrigin: strip.magnifying ? strip.magnifyOrigin : Item.Center
        scale: tailMouse.pressed ? strip.pressScale
             : strip.magnifying ? tailFace.magnified
             : tailMouse.containsMouse ? strip.hoverScale : 1.0
        Behavior on scale {
            enabled: !strip.magnifying
            NumberAnimation { duration: Motion.respond; easing.bezierCurve: Motion.spring
                              easing.type: Easing.BezierSpline }
        }

        // A pinned file's own themed icon, when gio named one the theme has.
        Image {
            id: fileIcon
            anchors.centerIn: parent
            readonly property string path: tail.file && tail.file.icon !== ""
                ? Quickshell.iconPath(tail.file.icon, true) : ""
            visible: fileIcon.path !== ""
            source: fileIcon.path
            width:  strip.iconPx
            height: strip.iconPx
            sourceSize: Qt.size(strip.iconRaster, strip.iconRaster)
            layer.enabled: strip.tinted
            layer.textureSize: Qt.size(strip.iconRaster, strip.iconRaster)
            layer.smooth: true
            layer.effect: MonoIconEffect {}
        }

        MaterialIcon {
            anchors.centerIn: parent
            visible: !fileIcon.visible
            // The ii overview button: every window and workspace. (`name` wins over
            // `glyph`; it is empty for every other tail button.)
            name: tail.key === "__overview" ? "grid_view" : ""
            fill: tail.key === "__overview" && UiState.overviewOpen ? 1 : 0
            // Folder / file; a folder with a download arrow; full / empty bin; +.
            glyph: tail.file          ? (tail.file.dir ? "\u{F024B}" : "\u{F0214}")
                : tail.isSlot        ? "\u{F0415}"
                : !tail.isTrash      ? "\u{F024D}"
                : Places.trashFull   ? "\u{F01B4}"
                :                      "\u{F06CC}"
            font.pixelSize: tail.isSlot ? strip.iconPx * 0.6 : strip.iconPx
            color: tail.armed ? Colors.of(QsWindow.window).danger
                 : tail.isSlot ? Colors.of(QsWindow.window).fgMuted
                 : tail.key === "__overview" && UiState.overviewOpen ? Colors.of(QsWindow.window).primary
                 : Colors.of(QsWindow.window).fg
            Behavior on color { ColorAnimation { duration: Motion.respond } }
        }
    }

    // Armed: say what the next click does, in the button's own place.
    Rectangle {
        visible: tail.armed
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Tokens.spacingXs
        width:  armText.implicitWidth + Tokens.spacingSm * 2
        height: armText.implicitHeight + Tokens.spacingXs
        radius: height / 2
        color: Colors.of(QsWindow.window).danger
        StyledText {
            id: armText
            anchors.centerIn: parent
            text: Translation.tr("Empty?")
            variant: "caption"
            color: Colors.of(QsWindow.window).fgOnPrimary
        }
    }

    MouseArea {
        id: tailMouse
        anchors.fill: parent
        enabled: !tail.isSlot
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onPressed: m => tailWash.press(m.x, m.y)
        onReleased: tailWash.release()
        onCanceled: tailWash.release()
        onContainsMouseChanged: strip._hover(tail.key, tailMouse.containsMouse)
        onClicked: function(m) {
            const s = tailMouse.mapToItem(null, m.x, m.y)
            if (m.button === Qt.RightButton) strip._openTail(tail.key, s.x, s.y)
            else                             strip._activateTail(tail.key, s.x, s.y)
        }
    }
}
