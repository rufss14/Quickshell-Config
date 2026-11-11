import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../state"

// ── PillTip ───────────────────────────────────────────────────────────────────
// Rest on a bar pill and its tooltip melts out of the bar's underside under it, as a lobe of
// the blob: the module's name and what it is doing, in the bar's own material. It is the
// pill-sized sibling of WorkspaceGlance's card and borrows its melt (a bud the pill's width
// pushes out and widens as it grows; closing, it is drawn back into the pill).
//
// What it speaks is the tip the pill already published through HelpTip (`pill: true`) — the
// words are ModuleGlance's, one wording for the sidebar chip and this. A tip that is not a
// pill's, or any tip while the bar isn't welded, is TipBubble's: it stands down for exactly
// those (`skipPills`), so one tip is on screen, never two.
//
// Read-only: no mask region, so the pointer passes through and a tip can't hold itself open.
// Fills Bar.qml's window like WorkspaceGlance; Bar.qml folds `blob*` into the blob's lobes.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // Bar.qml's `blobRing`: only a welded bar has a lobe to melt out of.
    property bool welded: false
    property matrix4x4 deformMatrix
    // The bar's underside, in this window's coordinates.
    property real dockInner: Config.belowBar
    // The docked settings card inside this window: its preview pills are TipBubble's, not the bar's.
    property Item except: null
    // How far in from the window's left / right edge a sidebar stands there (its face, in this
    // window's coordinates): the card keeps clear of it by a blob's reach, so the two don't weld.
    property real clearLeft: 0
    property real clearRight: 0

    readonly property QtObject source: UiState.tipSource
    readonly property int pad: Tokens.spacingMd
    readonly property int margin: Tokens.spacingMd
    readonly property int maxText: 300

    function _owns(item) {
        for (let it = item; it; it = it.parent) {
            if (root.except && it === root.except) return false
            if (it === root.parent) return true
        }
        return false
    }
    function _mine(src) {
        return root.welded && !!src && src.pill === true && !!src.parent && root._owns(src.parent)
    }

    // ── What it shows (its own copy: a fading card must not blank on the way out) ─
    property string title: ""
    property string value: ""
    property real   main: 0     // the pill's centre along the bar, in this item's coordinates
    property real   bud: 0      // the pill's width

    // "Name · what it is doing": the name never has a dot of its own, the rest may.
    function _read(src) {
        const t = UiState.tipText
        const i = t.indexOf(" · ")
        root.title = i < 0 ? t : t.slice(0, i)
        root.value = i < 0 ? "" : t.slice(i + 3)
        const p = src.parent.mapToItem(root, src.parent.width / 2, 0)
        root.main = p.x
        root.bud = src.parent.width
    }

    // ── When ─────────────────────────────────────────────────────────────────
    // A long rest before the first tip (it is a hint, not a response), so sweeping the pointer
    // along the bar doesn't flash one per pill; then pill to pill at once, bridged by a short grace so the card glides
    // across the gap instead of closing and reopening.
    property bool open: false
    readonly property int dwell: 900
    readonly property int grace: 150

    function _follow() {
        const src = root.source
        if (!root._mine(src)) {
            dwellTimer.stop()
            if (root.open) graceTimer.restart()
            return
        }
        graceTimer.stop()
        root._read(src)
        if (!root.open) dwellTimer.restart()
    }
    onSourceChanged: root._follow()
    onWeldedChanged: if (!root.welded) { dwellTimer.stop(); graceTimer.stop(); root.open = false }
    Connections {
        target: UiState
        function onTipTextChanged() { if (root._mine(UiState.tipSource)) root._read(UiState.tipSource) }
    }
    Timer {
        id: dwellTimer
        interval: root.dwell
        onTriggered: if (root._mine(root.source)) root.open = true
    }
    Timer {
        id: graceTimer
        interval: root.grace
        onTriggered: root.open = false
    }

    // ── The melt ─────────────────────────────────────────────────────────────
    property real grow: root.open ? 1 : 0
    Behavior on grow {
        NumberAnimation {
            duration: Motion.surfaceDuration(root.open)
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.open ? Easing.BezierSpline : Motion.exitCurve
        }
    }
    property real narrow: root.open ? 1 : 0
    Behavior on narrow {
        NumberAnimation {
            duration: root.open ? Motion.spatial : Motion.exit
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: root.open ? Easing.BezierSpline : Motion.travel
        }
    }
    // Both at rest: only then may the glide between pills take the box over.
    readonly property bool melted: root.grow >= 1 && root.narrow >= 1
    // Arriving, the card lands in place; only once it is showing does it glide to the next pill.
    property bool _glide: false
    onOpenChanged: {
        if (root.open) Qt.callLater(() => root._glide = root.open)
        else root._glide = false
    }

    readonly property bool shown: root.welded && root.grow > 0.01
    readonly property real blobX: root.shown ? card.x : 0
    readonly property real blobY: root.shown ? card.y : 0
    readonly property real blobW: root.shown ? card.width  : 0
    readonly property real blobH: root.shown ? card.height : 0

    readonly property real cardW: body.implicitWidth  + root.pad * 2
    readonly property real cardH: body.implicitHeight + root.pad * 2
    function _clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }

    Surface {
        id: card

        // The bar's material, drawn by the blob's own fill: no outline, no shadow of its own.
        color:        Colors.of(QsWindow.window).frameFill
        cornerRadius: Tokens.radiusCard
        focused:      false
        borderWidth:  0
        castsShadow:  false
        clip:         true
        visible:      root.shown

        readonly property real minX: Math.max(root.margin, root.clearLeft > 0 ? root.clearLeft + Morph.smoothing : 0)
        readonly property real maxX: Math.max(card.minX, root.width - root.cardW - Math.max(root.margin, root.clearRight > 0 ? root.clearRight + Morph.smoothing : 0))
        readonly property real restX: root._clamp(root.main - root.cardW / 2, card.minX, card.maxX)
        readonly property real along: Math.min(root.cardW, root.bud + (root.cardW - root.bud) * root.narrow)
        width:  card.along
        height: root.cardH * root.grow
        x: root._clamp(root.main - card.along / 2, card.restX, card.restX + root.cardW - card.along)
        y: root.dockInner

        transform: Matrix4x4 { matrix: root.deformMatrix }

        Behavior on x      { enabled: root._glide && root.melted; NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
        Behavior on width  { enabled: root._glide && root.melted; NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }
        Behavior on height { enabled: root._glide && root.melted; NumberAnimation { duration: Motion.standard
                             easing.bezierCurve: Motion.emphasizedDecel; easing.type: Easing.BezierSpline } }

        // Stays where the whole card would put it while the box narrows round it (the clip
        // trims it), so nothing slides sideways; arrives in the last half of the melt.
        Item {
            id: body
            x: root.pad + (root.melted ? 0 : card.restX - card.x)
            y: root.pad
            opacity: Math.max(0, Math.min(root.grow, root.narrow) * 2 - 1)
            implicitWidth:  Math.max(titleText.width, valueText.visible ? valueText.width : 0)
            implicitHeight: titleText.implicitHeight + (valueText.visible ? valueText.implicitHeight : 0)

            StyledText {
                id: titleText
                width: Math.min(implicitWidth, root.maxText)
                elide: Text.ElideRight
                font.bold: true
                text: root.title
            }
            StyledText {
                id: valueText
                y: titleText.implicitHeight
                width: Math.min(implicitWidth, root.maxText)
                visible: root.value !== ""
                elide: Text.ElideRight
                variant: "caption"
                emphasis: "dim"
                text: root.value
            }
        }
    }
}
