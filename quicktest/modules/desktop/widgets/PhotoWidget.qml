pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
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
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.primary

    // `Wallpaper.wallpapers` is a list of PLAIN PATH STRINGS, not records — checked
    // against the service rather than assumed. The first cut read `.path` off each entry
    // and every source assignment was `undefined`, so the tile showed nothing and said
    // nothing about why.
    readonly property var shots: Wallpaper.wallpapers ?? []
    readonly property int everyMs: Math.max(10, root.opts.seconds ?? 30) * 1000

    property int index: 0
    property bool showA: true

    // Explicit `file://`, the same as the wallpaper gallery does. A bare absolute path
    // is a RELATIVE url that only happens to resolve correctly because the base is
    // itself a file: url — true here, and not something to depend on.
    function _urlAt(i) {
        const p = root.shots[i]
        return (p === undefined || p === "") ? "" : "file://" + p
    }

    function _advance() {
        if (root.shots.length < 2) return
        root.index = (root.index + 1) % root.shots.length
        // The hidden image takes the new picture, then the pair cross-fades.
        if (root.showA) imgB.source = root._urlAt(root.index)
        else            imgA.source = root._urlAt(root.index)
        root.showA = !root.showA
    }

    Timer {
        interval: root.everyMs
        repeat: true
        running: root.active && root.shots.length > 1
        onTriggered: root._advance()
    }

    Component.onCompleted: {
        if (root.shots.length > 0) imgA.source = root._urlAt(0)
    }
    // The library arrives from a `find`, so it is normally EMPTY at construction and
    // fills a moment later — which is why the first picture is seeded here as well as
    // above rather than only on completion.
    onShotsChanged: if (imgA.source === "" && root.shots.length > 0)
                        imgA.source = root._urlAt(0)

    ClippingRectangle {
        anchors.fill: parent
        radius: Tokens.radiusSm
        color: Colors.alpha(Colors.fg, 0.06)

        Image {
            id: imgA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(700, 700)
            asynchronous: true
            smooth: true
            opacity: root.showA ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
        }
        Image {
            id: imgB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            sourceSize: Qt.size(700, 700)
            asynchronous: true
            smooth: true
            opacity: root.showA ? 0 : 1
            Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
        }

        StyledText {
            anchors.centerIn: parent
            visible: root.shots.length === 0
            text: "No wallpapers found"
            variant: "caption"
            emphasis: "dim"
        }
    }

    // Tap to skip ahead — the one interaction a photo frame wants.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        enabled: root.shots.length > 1
        onClicked: root._advance()
    }
}
