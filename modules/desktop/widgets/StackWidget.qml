pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/desktopwidgets.js" as Rules

// ── StackWidget ───────────────────────────────────────────────────────────────
// A smart stack (iOS/macOS): several widgets in one tile. Scroll over it to flip; with
// `opts.smart` (on by default) it brings forward what matters right now — a running timer,
// else the music card while something plays (Rules.stackSurface, tested) — and goes back
// to the card you were on when that ends. `opts.rotate` (seconds, 0 = off) turns it on its
// own while the pointer isn't on it.
//
// ── The cards are the real widgets ────────────────────────────────────────────
// Each card is the type's own QML file, loaded the way WidgetLayer loads a tile
// (setSource with the required properties), at the stack's size, with that type's
// default options. `widgetId: -1`, a preview's id: a card has no record, so it must
// never write to the store (the clock's tap, the timer's mode switch check for it).
// Typed widgets (notes, reminders, habits) can't be cards for the same reason, and only
// types that come in the stack's size are used. Only the card on screen is `active`, so
// the others hold no service — a stack of five costs one live widget.
//
// ── The flip ──────────────────────────────────────────────────────────────────
// One spring (`pos`, Motion.springSpatial) drives every card from its offset to the
// current one: the leaving card slides up, shrinks and fades as the next rises from below
// — Material 3 Expressive's carousel, in depth. `current` counts without wrapping, so a
// flip from the last card to the first is still one step forward. A card with nothing to
// show (`hidden`: the lyrics with no lyrics) is skipped.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary
    // Handed to cards that open a panel (WidgetLayer binds it when declared).
    property var screen: null

    function cardOk(t) {
        const m = DesktopWidgets.info(t)
        return !!m && t !== "stack" && m.editable !== true && (m.sizes ?? []).indexOf(root.size) >= 0
    }
    readonly property var cards: (root.opts.cards ?? []).filter(t => root.cardOk(t))
    readonly property int count: root.cards.length
    readonly property bool smart: root.opts.smart !== false
    readonly property int rotateMs: Math.max(0, root.opts.rotate ?? 0) * 1000

    // ── Where it is ───────────────────────────────────────────────────────────
    property int current: 0
    readonly property int cur: root.count > 0 ? ((root.current % root.count) + root.count) % root.count : 0
    SpringValue { id: pos; spec: Motion.springSpatial; epsilon: 0.001; target: root.current }

    // Which cards are hidden right now, by index (each card reports its own).
    property var _hidden: ({})
    function _setHidden(i, on) {
        if ((root._hidden[i] === true) === on) return
        const next = Object.assign({}, root._hidden)
        if (on) next[i] = true
        else delete next[i]
        root._hidden = next
    }
    readonly property bool curHidden: root._hidden[root.cur] === true
    onCurHiddenChanged: if (root.curHidden) root.go(1)

    // Moves `step` cards (±1), passing over hidden ones.
    function go(step) {
        if (root.count < 2) return
        for (let k = 1; k <= root.count; k++) {
            const i = (((root.cur + step * k) % root.count) + root.count) % root.count
            if (root._hidden[i] !== true) { root.current += step * k; return }
        }
    }
    // To card `i` by the shorter way round.
    function goTo(i) {
        if (root.count === 0) return
        let d = i - root.cur
        if (d > root.count / 2) d -= root.count
        if (d < -root.count / 2) d += root.count
        root.current += d
    }

    // ── Smart: what matters now ───────────────────────────────────────────────
    MediaPosition { id: media; active: root.active && root.smart }
    readonly property int surface: root.smart
        ? Rules.stackSurface(root.cards, { playing: media.playing, timer: Timers.timerRunning }) : -1
    property int _before: -1
    onSurfaceChanged: {
        if (root.surface >= 0) {
            if (root._before < 0) root._before = root.cur
            root.goTo(root.surface)
        } else if (root._before >= 0) {
            root.goTo(Math.min(root._before, root.count - 1))
            root._before = -1
        }
    }
    // Flipping by hand while something was brought forward hands control back to you.
    function _manual(step) {
        root._before = -1
        root.go(step)
    }

    Timer {
        interval: Math.max(1000, root.rotateMs)
        repeat: true
        running: root.active && root.rotateMs > 0 && root.count > 1 && !hover.hovered && root.surface < 0
        onTriggered: root.go(1)
    }

    // ── Input ─────────────────────────────────────────────────────────────────
    HoverHandler { id: hover }
    // One card per notch; a touchpad's many small deltas are summed to a notch first.
    WheelHandler {
        property real _acc: 0
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (e) {
            _acc += e.angleDelta.y
            if (Math.abs(_acc) >= 120) {
                root._manual(_acc > 0 ? -1 : 1)
                _acc = 0
            }
        }
    }
    // The tile's tap goes to the card on screen when it has one, else flips.
    function tileTap() {
        const l = cardRepeater.itemAt(root.cur)
        const it = l ? l.item : null
        if (it && typeof it.tileTap === "function") it.tileTap()
        else root._manual(1)
    }

    WidgetEmpty {
        visible: root.count === 0
        icon: "layers"
        text: Translation.tr("Pick cards in Settings → Widgets")
    }

    // ── The cards ─────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        clip: true

        Repeater {
            id: cardRepeater
            model: root.cards

            Loader {
                id: card
                required property string modelData
                required property int index

                // Offset from the card on screen, the short way round: -1 above, +1 below.
                readonly property real d: {
                    const n = Math.max(1, root.count)
                    let x = (card.index - pos.value) % n
                    if (x > n / 2) x -= n
                    if (x < -n / 2) x += n
                    return x
                }
                readonly property real far: Math.min(1, Math.abs(card.d))

                width: parent.width
                height: parent.height
                y: card.d * parent.height * 0.6
                scale: 1 - 0.12 * card.far
                opacity: 1 - card.far
                visible: card.far < 1
                z: -card.far
                asynchronous: true

                readonly property bool hiddenCard: card.item ? card.item.hidden === true : false
                onHiddenCardChanged: root._setHidden(card.index, card.hiddenCard)
                Component.onDestruction: root._setHidden(card.index, false)

                // setSource, for the required properties (WidgetLayer's reason).
                Component.onCompleted: {
                    const t = card.modelData
                    card.setSource(t.charAt(0).toUpperCase() + t.slice(1) + "Widget.qml", {
                        opts: DesktopWidgets.defaultOpts(t),
                        size: root.size,
                        widgetId: -1
                    })
                }
                onLoaded: {
                    card.item.active = Qt.binding(() => root.active && card.far < 1)
                    card.item.accent = Qt.binding(() => root.accent)
                    if (card.item.screen !== undefined)
                        card.item.screen = Qt.binding(() => root.screen)
                }
            }
        }
    }

    // ── Where you are in the stack ────────────────────────────────────────────
    // Pips down the right edge, the current one stretched; shown while the pointer is on
    // the tile or the stack is moving.
    Column {
        anchors.right: parent.right
        anchors.rightMargin: -Tokens.spacingMd
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacingXs
        visible: root.count > 1
        opacity: hover.hovered || pos.moving ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard } }

        Repeater {
            model: root.count
            Rectangle {
                id: pip
                required property int index
                readonly property bool here: pip.index === root.cur
                SpringValue {
                    id: pipH
                    spec: Motion.springSpatialFast
                    epsilon: 0.05
                    target: pip.here ? Tokens.spacingXl : Tokens.spacingSm
                }
                width: Tokens.spacingSm
                height: pipH.value
                radius: width / 2
                color: pip.here ? root.accent
                     : root._hidden[pip.index] === true ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.1)
                     : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.3)
            }
        }
    }
}
