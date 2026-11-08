pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/notifyview.js" as View

// ── NotificationStrip ─────────────────────────────────────────────────────────
// The history at a glance: a pill of one chip per app — its tone (the cookie's colour on its
// tiles) and its count — that is also the filter. Tap one to see only that app, tap it again
// (or "All") to see everything. In the pill ChipTray and SegmentSwitch use, so it reads as part
// of the same panel; it scrolls sideways (wheel or drag) when the apps don't fit, which on the
// overview's narrow card they won't.
//
// `apps` is [{ app, count }] from View.appCounts, newest app first. A muted app's chip is dimmed.
// It shows nothing for fewer than two apps: a filter between one thing and itself is noise.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property var    apps: []
    property string current: ""          // "" = All
    property color  accent: Colors.of(QsWindow.window).primary

    signal picked(string app)

    readonly property int pad: Tokens.spacingXs + 1
    readonly property int total: {
        let n = 0
        for (const a of root.apps) n += a.count
        return n
    }

    implicitHeight: Tokens.iconXl + Tokens.spacingMd
    visible: root.apps.length > 1
    radius: height / 2
    color: Colors.of(QsWindow.window).surfaceContainer
    border.width: Tokens.borderWidth
    border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)

    function _tone(app) {
        const p = Colors.of(QsWindow.window)
        return [p.primary, p.focus, p.info][View.toneIndex(app, 3)]
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: root.pad
        anchors.rightMargin: root.pad
        clip: true
        contentWidth: row.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds

        // A wheel turns it sideways; the strip is one line tall and has no vertical to give.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - d))
            }
        }

        Row {
            id: row
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacingXs

            // Never filled: "everything" is the resting state, and a lit disc on it was the loudest
            // thing in the card. The picked app's chip is the filled one; this one is the way back.
            ChipButton {
                label: root.current === "" ? "All  " + root.total : "All"
                symbol: root.current === "" ? "" : "close"
                tint:  root.accent
                opacity: root.current === "" ? 0.85 : 1
                onActivated: root.picked("")
            }
            Repeater {
                model: root.apps

                ChipButton {
                    required property var modelData
                    label:   modelData.app + "  " + modelData.count
                    dot:     root._tone(modelData.app)
                    on:      root.current === modelData.app
                    tint:    root._tone(modelData.app)
                    opacity: Notifications.isMuted(modelData.app) ? 0.6 : 1
                    onActivated: root.picked(root.current === modelData.app ? "" : modelData.app)
                }
            }
        }
    }

    // ── Edge fades ────────────────────────────────────────────────────────────
    // A chip cut off at the pill's edge read as a bug; a fade says "more this way". They go to the
    // pill's own colour, so they only show where there IS more to scroll to.
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.borderWidth
        width: Tokens.spacingXl * 2
        radius: height / 2
        opacity: flick.contentX > 1 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: root.color }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.color, 0) }
        }
    }
    Rectangle {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.borderWidth
        width: Tokens.spacingXl * 2
        radius: height / 2
        opacity: flick.contentWidth - flick.contentX - flick.width > 1 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.color, 0) }
            GradientStop { position: 1.0; color: root.color }
        }
    }
}
