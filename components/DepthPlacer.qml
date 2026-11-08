import QtQuick
import Quickshell
import "../config"
import "../services"

// ── DepthPlacer ───────────────────────────────────────────────────────────────
// A miniature of the desktop for ONE wallpaper — the picture, and the clock cut by the picture's mask
// (components/DepthMasked) — where the clock can be picked up and put somewhere else. Releasing it
// asks WallpaperDepth for the mask measured at the new spot (~1 s, the maps are cached).
//
// It shows what the desktop will: the same entry (WallpaperDepth.entryFor, so the same job), the same
// ink (WallpaperDepth.ink) and the same proportions as WallpaperView's clock.
//
// ── The drag ──────────────────────────────────────────────────────────────────
//   · It commits once, on release: a drag is not a stream of jobs.
//   · While it is held the clock runs behind the subject by the picture's CURRENT mask. That is
//     truthful — the subject really is in front — and it is the preview: the mask is only re-measured
//     for what is behind the clock (the depth plane), which hardly changes the silhouette.
//   · After the release the clock STAYS where it was dropped until the new answer arrives. (It used to
//     fall back to its old spot for the second the job took, then jump.)
//   · `preventStealing`: this sits in a page that scrolls, which would otherwise take the drag over the
//     moment it wandered vertically.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The wallpaper's path, and the shape of the screen it is framed for.
    property string path: ""
    property real   aspect: 16 / 9
    property color accent: Colors.of(QsWindow.window).primary

    implicitHeight: Math.round(width / Math.max(0.5, root.aspect))

    // Keep in sync with wallpaper-depth.py (BOX_W, BOX_H): where the clock's box still fits.
    readonly property real _minX: 0.2
    readonly property real _maxX: 0.8
    readonly property real _maxY: 0.66

    readonly property var entry: WallpaperDepth.entryFor(root.path, root.aspect)
    readonly property bool waiting: WallpaperDepth.waiting(root.path, root.aspect)

    // ── Where the clock is drawn ──────────────────────────────────────────────
    // Under the pointer while dragging; where it was dropped until the answer for that spot lands;
    // else where the answer says. `_last` bridges the gap before any answer.
    property bool dragging: false
    property bool dropped: false
    property real _dragX: 0.5
    property real _dragY: 0.08
    property real _lastX: 0.5
    property real _lastY: 0.08
    readonly property bool _held: root.dragging || root.dropped
    readonly property real cx: root._held ? root._dragX : (root.entry && root.entry.x !== undefined ? root.entry.x : root._lastX)
    readonly property real cy: root._held ? root._dragY : (root.entry && root.entry.y !== undefined ? root.entry.y : root._lastY)
    // A different picture is a different drop.
    onPathChanged: root.dropped = false

    // The mask in use: the answer's, and held while the next one is measured (an answer of "nothing in
    // front" clears it). One handler for everything an answer does.
    property string _mask: ""
    onEntryChanged: {
        if (!root.entry) return
        if (root.entry.x !== undefined) { root._lastX = root.entry.x; root._lastY = root.entry.y }
        root._mask = root.entry.state === "ready" ? "file://" + root.entry.cutout : ""
        // The first answer after a drop is for the dropped spot.
        if (root.dropped && !root.dragging) root.dropped = false
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Colors.of(QsWindow.window).surfaceHigh
        clip: true

        Image {
            anchors.fill: parent
            source: root.path !== "" ? "file://" + root.path : ""
            fillMode: Image.PreserveAspectCrop
            // A preview: decoded small.
            sourceSize: Qt.size(Math.round(root.width * 1.5), Math.round(root.height * 1.5))
            asynchronous: true
            smooth: true
        }

        DepthMasked {
            anchors.fill: parent
            mask: root._mask
            onFailed: WallpaperDepth.stale(root.path, root.aspect)
            maskSize: Qt.size(Math.round(root.width * 1.5), Math.round(root.height * 1.5))

            Column {
                id: face
                x: root.width * root.cx - width / 2
                y: root.height * root.cy
                spacing: root.height * 0.01
                opacity: root.waiting && !root.dragging ? 0.6 : 1
                Behavior on opacity { NumberAnimation { duration: Motion.standard } }

                readonly property color ink: WallpaperDepth.ink(Colors.of(QsWindow.window), root.entry?.luma ?? 0.5, 3.5)
                readonly property color inkSmall: WallpaperDepth.ink(Colors.of(QsWindow.window), root.entry?.luma ?? 0.5, 4.5)
                readonly property real unit: root.height * Config.wallDepthScale

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: {
                        const h = Config.wallDepthHour12 ? (Clock.hours % 12 || 12) : Clock.hours
                        return (h < 10 ? "0" : "") + h + ":" + (Clock.minutes < 10 ? "0" : "") + Clock.minutes
                    }
                    color: face.ink
                    font.family: Tokens.fontBlock
                    font.weight: Font.ExtraBold
                    font.pixelSize: face.unit * 0.23
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Config.wallDepthDate
                    text: Qt.formatDate(Clock.now, "dddd, d MMMM")
                    color: face.inkSmall
                    font.family: Tokens.fontFamily
                    font.weight: Font.Medium
                    font.pixelSize: face.unit * 0.04
                    font.letterSpacing: face.unit * 0.003
                }
            }
        }

        // The outline the pointer grabs.
        Rectangle {
            x: face.x - Tokens.spacingSm
            y: face.y - Tokens.spacingXs
            width: face.width + Tokens.spacingSm * 2
            height: face.height + Tokens.spacingXs * 2
            radius: Tokens.radiusSm
            color: "transparent"
            border.width: 1
            border.color: root.accent
            opacity: root.dragging ? 0.9 : (hover.hovered ? 0.5 : 0)
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }
        }
        StyledText {
            anchors { left: parent.left; bottom: parent.bottom; margins: Tokens.spacingSm }
            visible: root.waiting && !root.dragging
            text: Translation.tr("Analysing…")
            variant: "caption"
            color: Colors.of(QsWindow.window).fg
        }
    }

    HoverHandler { id: hover; cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor }

    // The offset from where the clock was grabbed, so it doesn't jump to the pointer.
    property real _grabX: 0
    property real _grabY: 0
    MouseArea {
        anchors.fill: parent
        preventStealing: true
        onPressed: function (m) {
            root._dragX = root.cx
            root._dragY = root.cy
            root._grabX = m.x / root.width  - root.cx
            root._grabY = m.y / root.height - root.cy
            root.dropped = false
            root.dragging = true
        }
        onPositionChanged: function (m) {
            if (!root.dragging) return
            root._dragX = Math.max(root._minX, Math.min(root._maxX, m.x / root.width  - root._grabX))
            root._dragY = Math.max(0,          Math.min(root._maxY, m.y / root.height - root._grabY))
        }
        onReleased: {
            if (!root.dragging) return
            root.dragging = false
            if (root.path === "") return
            root.dropped = true
            WallpaperDepth.place(root.path, root._dragX, root._dragY)
        }
        onCanceled: root.dragging = false
    }
}
