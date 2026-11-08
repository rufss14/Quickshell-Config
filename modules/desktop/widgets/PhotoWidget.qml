pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Widgets
import QtQuick.Effects
import Qt.labs.folderlistmodel
import "../../../config"
import "../../../components"
import "../../../services"

// ── PhotoWidget ───────────────────────────────────────────────────────────────
// A slow slideshow of your wallpaper library, which the Wallpaper service already
// indexes — so this needs no folder picker, no scan and no new file watching.
//
// Two Images cross-fading rather than one whose source changes: swapping a source makes
// the tile go blank while the next file decodes, and on a large photo that blink is
// very visible. Loading the incoming one underneath and fading it up hides the decode
// entirely.
//
// ── Its own picture (2026-10-30) ──────────────────────────────────────────────
// Each frame now says WHAT it shows (`opts.source`): "library" (the wallpapers, as
// before), "folder" (every picture in one folder, cycling — `opts.folder`), or "image"
// (one picture, still — `opts.image`). Paths are stored `~`-relative and expanded by
// DesktopWidgets.expandPath; see desktopwidgets.js for why. The frame may be placed many
// times (catalogue `multiple`), each with its own source.
//
// ── Material 3 Expressive ─────────────────────────────────────────────────────
// Bare by default — the picture is the tile — and `opts.shape` cuts it: "rect" (the
// tile's own rounded corners) or one of the M3E shapes (cookie, clover, sunny, burst,
// squircle, circle…), so a photo can float on the desktop as a cookie. A shape change
// morphs. The shape cut is CookieCover's mask (a hidden layered silhouette read by
// MultiEffect), the idiom the media panel already ships.
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    readonly property string sourceKind: root.opts.source ?? "library"
    readonly property string folderPath: DesktopWidgets.expandPath(root.opts.folder ?? "")
    readonly property string imagePath:  DesktopWidgets.expandPath(root.opts.image ?? "")
    readonly property string frameShape: root.opts.shape ?? "rect"
    readonly property bool   shaped: root.frameShape !== "rect"

    // ── The pictures ──────────────────────────────────────────────────────────
    // A folder is listed by FolderListModel (Qt's own watcher, as Places and the lock
    // page's picker use): a picture added to the folder joins the cycle with no rescan.
    FolderListModel {
        id: folderModel
        folder: root.sourceKind === "folder" && root.folderPath !== "" ? "file://" + root.folderPath : ""
        showDirs: false
        showHidden: false
        caseSensitive: false
        sortField: FolderListModel.Name
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp", "*.bmp", "*.gif"]
        onCountChanged: root._readFolder()
        onStatusChanged: root._readFolder()
    }
    property var _folderShots: []
    function _readFolder() {
        if (root.sourceKind !== "folder" || root.folderPath === "" || folderModel.status !== FolderListModel.Ready) {
            root._folderShots = []
            return
        }
        const out = []
        for (let i = 0; i < folderModel.count; i++) out.push(folderModel.get(i, "filePath"))
        root._folderShots = out
    }
    onSourceKindChanged: root._readFolder()

    // `Wallpaper.wallpapers` is a list of PLAIN PATH STRINGS, not records — checked
    // against the service rather than assumed. The first cut read `.path` off each entry
    // and every source assignment was `undefined`, so the tile showed nothing and said
    // nothing about why.
    readonly property var shots: root.sourceKind === "image"  ? (root.imagePath !== "" ? [root.imagePath] : [])
                               : root.sourceKind === "folder" ? root._folderShots
                               : (Wallpaper.wallpapers ?? [])
    readonly property int everyMs: Math.max(10, root.opts.seconds ?? 30) * 1000

    // A slow zoom on the shown picture between advances — the Ken Burns move. On
    // by default; a photo FRAME is expected to have a little life. Off is a still.
    readonly property bool pan:        root.opts.pan        !== false
    readonly property bool shuffle:    root.opts.shuffle    === true
    readonly property string bgMode:   root.opts.bgMode     ?? "solid"
    readonly property color bgColor:   root.opts.bgColor    ?? "transparent"
    readonly property real bgOpacity:  root.opts.bgOpacity  ?? 1.0
    readonly property bool shapeRot:   root.opts.shapeRot   === true
    readonly property string border:   root.opts.border     ?? "none"
    readonly property color borderCol: root.opts.borderCol  ?? Colors.of(QsWindow.window).primary
    readonly property real borderWidth: root.opts.borderW   ?? 0
    readonly property real brightness: root.opts.brightness ?? 1.0
    readonly property real saturation: root.opts.saturation ?? 1.0
    readonly property real imgBlur:    root.opts.imgBlur    ?? 0
    readonly property int fadeMs:      root.opts.fadeMs     ?? Math.round(Motion.spatial)
    readonly property real panStrength: root.opts.panStr    ?? 1.0
    readonly property color tintCol:   root.opts.tintCol    ?? "transparent"
    readonly property real tintOp:     root.opts.tintOp     ?? 0

    property int index: 0
    property bool showA: true
    property real shapeRotation: 0

    function _next() {
        if (root.shots.length < 2) return 0
        if (!root.shuffle) return (root.index + 1) % root.shots.length
        // Random, but never the one already showing.
        let n = root.index
        while (n === root.index) n = Math.floor(Math.random() * root.shots.length)
        return n
    }

    // Explicit `file://`, the same as the wallpaper gallery does. A bare absolute path
    // is a RELATIVE url that only happens to resolve correctly because the base is
    // itself a file: url — true here, and not something to depend on.
    function _urlAt(i) {
        const p = root.shots[i]
        return (p === undefined || p === "") ? "" : "file://" + p
    }

    function _advance() {
        if (root.shots.length < 2) return
        root.index = root._next()
        // The hidden image takes the new picture, then the pair cross-fades.
        if (root.showA) imgB.source = root._urlAt(root.index)
        else            imgA.source = root._urlAt(root.index)
        root.showA = !root.showA
    }

    // The list changed under the frame (a new source, a folder that filled in, the library
    // arriving from its `find`): start again from its first picture unless the one on
    // screen is still in it.
    function _reseed() {
        const shown = String(root.showA ? imgA.source : imgB.source).replace("file://", "")
        const at = root.shots.indexOf(shown)
        if (at >= 0) { root.index = at; return }
        root.index = 0
        root.showA = true
        imgA.source = root._urlAt(0)
        imgB.source = ""
    }
    onShotsChanged: root._reseed()
    Component.onCompleted: root._reseed()

    Timer {
        interval: root.everyMs
        repeat: true
        running: root.active && root.shots.length > 1
        onTriggered: root._advance()
    }

    // Shape rotation animation
    SequentialAnimation on shapeRotation {
        running: root.active && root.shapeRot && root.shots.length > 0
        loops: Animation.Infinite
        NumberAnimation { from: 0; to: 360; duration: 20000; easing.type: Easing.Linear }
    }

    // ── Nothing to show ───────────────────────────────────────────────────────
    // On its own ground: the tile is bare, so without this the words would sit straight
    // on the wallpaper.
    Item {
        anchors.fill: parent
        visible: root.shots.length === 0
        layer.enabled: root.bgMode !== "solid" && root.bgMode !== "transparent"
        // An object literal can't sit in a ternary (parse error); the blur is switched instead.
        layer.effect: MultiEffect {
            blurEnabled: root.bgMode === "glass"
            blur: 0.8
            blurMax: 12
        }

        Rectangle {
            anchors.fill: parent
            radius: root.opts.roundness ?? Config.widgetRoundness
            color: root.bgMode === "transparent" ? "transparent" : Colors.of(QsWindow.window).surfaceContainer
            opacity: root.bgOpacity
        }
        WidgetEmpty {
            icon: "photo"
            text: root.sourceKind === "image"  ? "Pick a picture in Settings → Widgets"
                : root.sourceKind === "folder" ? (root.folderPath === "" ? "Pick a folder in Settings → Widgets"
                                                                          : "No pictures in this folder")
                : "No wallpapers found"
        }
    }

    // ── The shape the picture is cut to ───────────────────────────────────────
    // The silhouette as a mask. A layer, hidden: it is only ever read by the effect.
    Item {
        id: silhouette
        anchors.fill: parent
        visible: false
        layer.enabled: root.shaped
        MorphShape {
            anchors.fill: parent
            anchors.centerIn: parent
            spec: Motion.springSpatialFast
            shape: root.shaped ? root.frameShape : "circle"
            fillColor: "white"
            rotation: root.shapeRot ? root.shapeRotation : 0
        }
    }

    Item {
        anchors.fill: parent
        visible: root.shots.length > 0
        layer.enabled: root.shaped || root.imgBlur > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: root.shaped
            maskSource: root.shaped ? silhouette : null
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
            brightness: root.brightness
            saturation: root.saturation
            blur: root.imgBlur
            blurMax: 24
        }

        // Background
        Rectangle {
            anchors.fill: parent
            radius: root.shaped ? 0 : (root.opts.roundness ?? Config.widgetRoundness)
            color: root.bgMode === "transparent" ? "transparent" : Colors.of(QsWindow.window).surfaceContainer
            opacity: root.bgOpacity
            layer.enabled: root.bgMode === "blur" || root.bgMode === "glass"
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.8; blurMax: 12 }
        }

        // Images with Ken Burns effect
        Item {
            anchors.fill: parent
            clip: !root.shaped

            property real kb: 1.0
            SequentialAnimation on kb {
                running: root.active && root.pan && root.shots.length > 0
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.0 + (0.08 * root.panStrength); duration: root.everyMs * 2; easing.type: Motion.ambient }
                NumberAnimation { from: 1.0 + (0.08 * root.panStrength); to: 1.0; duration: root.everyMs * 2; easing.type: Motion.ambient }
            }

            AnimatedImage {
                id: imgA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(700, 700)
                asynchronous: true
                smooth: true
                scale: parent.kb
                opacity: root.showA ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
            }
            AnimatedImage {
                id: imgB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                sourceSize: Qt.size(700, 700)
                asynchronous: true
                smooth: true
                scale: parent.kb
                opacity: root.showA ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: root.fadeMs } }
            }
        }

        // Tint overlay
        Rectangle {
            anchors.fill: parent
            visible: root.tintOp > 0
            color: root.tintCol
            opacity: root.tintOp
        }

        // Border frame
        Rectangle {
            anchors.fill: parent
            visible: root.border !== "none" && root.borderWidth > 0
            radius: root.shaped ? 0 : (root.opts.roundness ?? Config.widgetRoundness)
            color: "transparent"
            border.color: root.borderCol
            border.width: root.borderWidth
        }
    }

    // Tap to skip ahead — the one interaction a photo frame wants.
    function tileTap() { root._advance() }

    // ── Set as wallpaper ──────────────────────────────────────────────────────
    // For the wallpaper library only, on hover: the one other thing you'd want from a
    // photo of your own wallpapers. A picture from anywhere else isn't a library item.
    HoverHandler { id: setHover }
    TileChip {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Tokens.spacingMd
        visible: root.sourceKind === "library" && root.shots.length > 0 && setHover.hovered
        filled: true
        awake: true
        accent: root.accent
        box: Tokens.iconXl + Tokens.spacingXs
        icon: "wallpaper"
        onActivated: {
            const p = root.shots[root.index]
            if (p) Wallpaper.apply(p)
        }
    }
}
