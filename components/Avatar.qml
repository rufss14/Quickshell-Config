import QtQuick
import Quickshell
import QtQuick.Effects
import "../config"

// ── Avatar ────────────────────────────────────────────────────────────────────
// A person's picture in a circle, with their initial while it loads (or if it never
// does). Masked, not clipped: `clip` is rectangular. The sidebar's voice faces and
// the voice panel's rows draw it; size it with width/height (square).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    property url    source: ""
    property string name: ""

    implicitWidth:  Tokens.iconXl
    implicitHeight: Tokens.iconXl

    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Image {
            id: picture
            anchors.fill: parent
            source: root.source
            sourceSize: Qt.size(root.width * 2, root.height * 2)
            fillMode: Image.PreserveAspectCrop
            smooth: true
            mipmap: true
            visible: picture.status === Image.Ready
        }
    }
    Item {
        id: mask
        width:  root.width
        height: root.height
        visible: false
        layer.enabled: true
        // A stencil: only its alpha counts, so any opaque colour will do.
        Rectangle { anchors.fill: parent; radius: width / 2; color: Colors.of(QsWindow.window).fg }
    }
    // The initial while the picture loads, or if it never does. No disc behind it:
    // initial discs on the edge read as "weird" (the user, 2026-10-02).
    StyledText {
        anchors.centerIn: parent
        visible: picture.status !== Image.Ready
        text: (root.name || "?").charAt(0).toUpperCase()
        font.pixelSize: Math.round(root.height * 0.55)
        font.bold: true
        color: Colors.of(QsWindow.window).fgDim
    }
}
