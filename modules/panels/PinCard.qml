import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Wayland
import "../../config"
import "../../components"
import "../../services"
import "../desktop/widgets"

// ── PinCard ───────────────────────────────────────────────────────────────────
// One pinned picture: the crop at the size it had on screen, in the shell's corner, on a thin
// outline. Drag anywhere to move it (kept on the screen); hover for copy and ✕; right-click
// closes, the wheel resizes it. It is on every workspace and can be dragged anywhere. It springs in from slightly small, so a pin arrives where you cut it from.
//
// ── Live ──────────────────────────────────────────────────────────────────────
// A live pin (`rec.live`) draws captures instead of a file, and always the workspace it was taken
// from, not the one you are on now:
//   · a window it was cut from: one toplevel capture, wherever that window is;
//   · a region: that WORKSPACE's wallpaper with its windows on it, each a toplevel capture at its place
//     in the region (floating ones over tiled), slid so the region's corner is the card's corner.
//     Toplevel captures work for a window on another workspace, and they never contain this card, so
//     it can sit on its own source. What is not a window (the bar, desktop widgets) is not in it.
//   · a region with no workspace known (`workspace` -1): the screen itself. That includes the card,
//     so on its own source it shows itself and never updates — Snip puts it BESIDE its source, and the
//     card says so when it is moved back on top (`overlapping`).
// A closed window leaves a blank card that says so rather than a frozen last frame.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: card

    required property string pinId
    // The layer's size, for keeping the card on screen.
    property size bounds: Qt.size(0, 0)

    readonly property var rec: SnipPins.get(card.pinId)

    x: card.rec ? card.rec.x : 0
    y: card.rec ? card.rec.y : 0
    width:  card.rec ? card.rec.w : 0
    height: card.rec ? card.rec.h : 0

    property real shown: 0
    Component.onCompleted: card.shown = 1
    SpringValue { id: pop; target: card.shown; spec: Motion.springSpatial; epsilon: 0.0005 }
    SpringValue { id: fade; target: card.shown; spec: Motion.springEffects; epsilon: 0.002 }
    scale: 0.92 + 0.08 * pop.value
    opacity: Math.min(1, fade.value)

    // HoverHandler, not the MouseArea's containsMouse: the chips sit above the MouseArea, and the
    // pointer on a chip must keep them (and the card) lit.
    readonly property bool live: card.rec ? card.rec.live === true : false
    readonly property var screenObj: Quickshell.screens.find(sc => sc.name === (card.rec ? card.rec.screen : "")) ?? null
    // A region pin on top of the very region it shows.
    readonly property bool overlapping: card.live && card.rec.window === null && card.rec.workspace <= 0 && card.rec.src !== undefined
        && card.rec.x < card.rec.src.x + card.rec.src.w && card.rec.src.x < card.rec.x + card.rec.w
        && card.rec.y < card.rec.src.y + card.rec.src.h && card.rec.src.y < card.rec.y + card.rec.h
    readonly property bool hot: hover.hovered
    HoverHandler { id: hover }

    ClippingRectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard)
        Image {
            anchors.fill: parent
            visible: !card.live
            source: card.rec && !card.live ? "file://" + card.rec.path : ""
            fillMode: Image.Stretch
            smooth: true
            // The file is gone the moment the pin closes; never read it again after.
            cache: false
        }
        Loader {
            id: liveView
            anchors.fill: parent
            active: card.live
            sourceComponent: !card.rec ? null : card.rec.window ? windowView
                           : card.rec.workspace > 0 ? workspaceView : regionView
        }
        // A window that has gone: say so, instead of a frozen last frame.
        StyledText {
            anchors.centerIn: parent
            visible: card.live && card.rec.window !== null && liveView.item && !liveView.item.hasContent
            text: Translation.tr("Window closed")
            variant: "label"
            emphasis: "dim"
        }
    }
    Component {
        id: windowView
        ScreencopyView {
            captureSource: card.rec ? card.rec.window : null
            live: true
            paintCursor: false
        }
    }
    // The windows of the pin's workspace, tiled below floating. Keyed on the address so a window that
    // moves keeps its capture (a rebuilt delegate would restart it).
    ScriptModel {
        id: wsWindows
        objectProp: "address"
        values: !card.live || !card.rec || card.rec.window || card.rec.workspace <= 0 ? []
            : Hypr.windows.filter(w => w.workspaceId === card.rec.workspace)
                          .sort((a, b) => Number(a.floating) - Number(b.floating))
    }
    Component {
        id: workspaceView
        Item {
            id: wv
            readonly property real k: card.rec ? card.width / card.rec.src.w : 1
            readonly property string pic: card.rec ? Wallpaper.pictureFor(card.rec.workspace) : ""
            Rectangle {
                anchors.fill: parent
                color: Colors.of(QsWindow.window).base
            }
            Image {
                visible: wv.pic !== ""
                source: wv.pic === "" ? "" : (wv.pic.charAt(0) === "/" ? "file://" + wv.pic : wv.pic)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                width:  card.screenObj ? card.screenObj.width  * wv.k : 0
                height: card.screenObj ? card.screenObj.height * wv.k : 0
                x: card.rec ? -card.rec.src.x * wv.k : 0
                y: card.rec ? -card.rec.src.y * wv.k : 0
            }
            Repeater {
                model: wsWindows
                ScreencopyView {
                    id: cap
                    required property var modelData
                    captureSource: cap.modelData.wayland
                    live: true
                    paintCursor: false
                    z: cap.modelData.floating ? 1 : 0
                    x: card.rec && card.screenObj ? (cap.modelData.at[0] - card.screenObj.x - card.rec.src.x) * wv.k : 0
                    y: card.rec && card.screenObj ? (cap.modelData.at[1] - card.screenObj.y - card.rec.src.y) * wv.k : 0
                    width:  cap.modelData.size[0] * wv.k
                    height: cap.modelData.size[1] * wv.k
                }
            }
        }
    }
    // The region: the whole output, drawn at the card's scale and slid so the region's corner is the
    // card's corner. The card clips it.
    Component {
        id: regionView
        Item {
            readonly property alias hasContent: shot.hasContent
            readonly property real k: card.rec ? card.width / card.rec.src.w : 1
            ScreencopyView {
                id: shot
                captureSource: card.screenObj
                live: true
                paintCursor: false
                width:  card.screenObj ? card.screenObj.width  * parent.k : 0
                height: card.screenObj ? card.screenObj.height * parent.k : 0
                x: card.rec ? -card.rec.src.x * parent.k : 0
                y: card.rec ? -card.rec.src.y * parent.k : 0
            }
        }
    }
    Rectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).primary, card.hot ? 0.9 : 0.45)
        Behavior on border.color { ColorAnimation { duration: Motion.respond } }
    }

    // ── Drag / close ──────────────────────────────────────────────────────────
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        property point grab: Qt.point(0, 0)
        onPressed: function (m) {
            if (m.button === Qt.RightButton) { SnipPins.close(card.pinId); return }
            // Held in the card's PARENT's space: the card moves under the pointer, so its own
            // coordinates would drift as it goes.
            const p = mouse.mapToItem(card.parent, m.x, m.y)
            mouse.grab = Qt.point(p.x - card.x, p.y - card.y)
        }
        onWheel: function (w) {
            if (card.rec) SnipPins.resize(card.pinId, w.angleDelta.y > 0 ? 1.08 : 1 / 1.08, card.bounds)
        }
        onPositionChanged: function (m) {
            if (!(m.buttons & Qt.LeftButton) || !card.rec) return
            const p = mouse.mapToItem(card.parent, m.x, m.y)
            const nx = Math.max(0, Math.min(card.bounds.width  - card.width,  p.x - mouse.grab.x))
            const ny = Math.max(0, Math.min(card.bounds.height - card.height, p.y - mouse.grab.y))
            SnipPins.move(card.pinId, nx, ny)
        }
    }

    // ── LIVE, and why a region pin might not be ──────────────────────────────
    Row {
        visible: card.live
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs
        Rectangle {
            implicitHeight: Tokens.iconLg
            implicitWidth: liveRow.implicitWidth + Tokens.spacingMd * 2
            radius: height / 2
            color: Colors.of(QsWindow.window).surfaceFor(Tokens.elevationCard)
            Row {
                id: liveRow
                anchors.centerIn: parent
                spacing: Tokens.spacingXs
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Tokens.spacingMd - Tokens.spacingXs; height: width; radius: width / 2
                    color: Colors.of(QsWindow.window).primary
                    SequentialAnimation on opacity {
                        running: card.live && Motion.ripple > 0
                        loops: Animation.Infinite
                        NumberAnimation { to: 0.35; duration: Motion.slow * 2; easing.type: Motion.travel }
                        NumberAnimation { to: 1;    duration: Motion.slow * 2; easing.type: Motion.travel }
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Translation.tr("Live")
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: Colors.of(QsWindow.window).fg
                }
            }
        }
        Rectangle {
            visible: card.overlapping
            implicitHeight: Tokens.iconLg
            implicitWidth: warnText.implicitWidth + Tokens.spacingMd * 2
            radius: height / 2
            color: Colors.of(QsWindow.window).danger
            StyledText {
                id: warnText
                anchors.centerIn: parent
                text: Translation.tr("On its own source: move me")
                variant: "caption"
                color: Colors.of(QsWindow.window).fgOnPrimary
            }
        }
    }

    // ── Chips, only while the pointer is on the card ──────────────────────────
    Row {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingXs
        opacity: card.hot ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        TileChip {
            id: copyChip
            visible: !card.live
            icon: "content_copy"
            awake: true
            onActivated: Clipboard.copyFile(card.rec ? card.rec.path : "", "image/png")
        }
        TileChip {
            id: closeChip
            icon: "close"
            awake: true
            onActivated: SnipPins.close(card.pinId)
        }
    }
}
