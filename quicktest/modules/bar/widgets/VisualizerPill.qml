import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── VisualizerPill ────────────────────────────────────────────────────────────
// Audio spectrum, with an inline media controller behind a right-click.
//
//   left-click   → toggle the desktop cava background
//   middle-click → toggle the floating now-playing card
//   right-click  → swap between the spectrum and the media controller
//
// Was AudioVisualizer: 526 lines that were really two widgets, and it started a
// `cava` process at 60fps with `running: true` and *never stopped it* — not when
// hidden, not when swapped out for the controller. The bar built both its
// layouts, so there were two of them, plus a third inside CavaBG. Three cava
// processes analyzing the same audio to draw the same spectrum.
//
// Now: one shared Cava service, refcounted, running only while something is
// actually drawing bars. The media controller moved to MediaController.qml.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── accent ────────────────────────────────────────────────────────────────
    // Settable per module (Settings → Bar → pick a module). Defaults to the role this
    // widget already used, so an untouched module is unchanged.
    property color accent: Colors.focus

    // ── showController: local by default, persisted on request ────────────────
    // Right-click toggles this. Transient unless the module is opted into
    // "remember" (Settings → Bar → this module), in which case Config holds it and
    // it survives a reload.
    //
    // `_persist` is read once at construction rather than bound, on purpose. If it
    // were a live binding, turning "remember" on in settings would yank the value
    // out from under a state you'd just set by hand — the setting is about what
    // happens NEXT, not a retroactive rewrite of what's on screen.
    property bool showController: Config.modulePersist("visualizer")
        ? Config.moduleRightState("visualizer")
        : false

    function _toggleShowcontroller() {
        const next = !root.showController
        if (Config.modulePersist("visualizer")) Config.setModuleRightState("visualizer", next)
        // Assigning here would destroy the declarative binding above for good, so an
        // opted-in module would stop tracking Config after its first right-click.
        // Re-establishing it keeps Config the source of truth.
        root.showController = Qt.binding(() => Config.modulePersist("visualizer")
            ? Config.moduleRightState("visualizer")
            : next)
    }

    // A small "this thing is open" light. Declared once rather than driven by a
    // Repeater over an array of Panels bindings — that array would rebuild on
    // every toggle, destroying and recreating the delegate, so the fade would
    // restart from zero each time instead of animating.
    component IndicatorDot: Rectangle {
        property bool lit: false

        z: 10
        width:  6
        height: 6
        radius: 3
        color:  root.accent

        opacity: lit ? 1.0 : 0.0
        scale:   lit ? 1.0 : 0.4
        visible: opacity > 0.005

        Behavior on opacity { NumberAnimation { duration: Motion.fast; easing.type: Motion.enter } }
        Behavior on scale   { NumberAnimation { duration: Motion.fast; easing.type: Easing.OutBack } }

        // Soft ring, so the dot reads as lit rather than merely present.
        Rectangle {
            anchors.centerIn: parent
            width:  parent.width + 4
            height: parent.height + 4
            radius: width / 2
            color: "transparent"
            border.color: root.accent
            border.width: 1
            opacity: 0.5
        }
    }

    readonly property int barCount: 16
    readonly property int barW:     3
    readonly property int barGap:   3
    readonly property int maxBarH:  Tokens.pillHeight - 6

    readonly property int vizWidth: barCount * (barW + barGap) - barGap + Tokens.pillPadding * 2

    implicitWidth:  pill.width
    implicitHeight: Tokens.pillHeight

    // ── Cava lifecycle ────────────────────────────────────────────────────────
    // The service runs iff someone holds a reference. We hold one only while the
    // spectrum is actually on screen — swapping to the media controller releases
    // it, so flipping to the controller genuinely stops the process rather than
    // just hiding its output.
    readonly property bool wantsSpectrum: root.visible && !root.showController
    property bool _held: false

    function _sync() {
        if (wantsSpectrum === _held) return
        if (wantsSpectrum) Cava.acquire()
        else               Cava.release()
        _held = wantsSpectrum
    }

    onWantsSpectrumChanged: _sync()
    Component.onCompleted:  _sync()
    // Without this, a destroyed pill (e.g. a monitor unplugged) leaks its
    // reference and pins cava on forever.
    Component.onDestruction: if (_held) Cava.release()

    // 16 bars from the service's 32, averaged rather than sampled — sampling
    // drops transients, which is the content a visualizer exists to show.
    readonly property var bars: Cava.resample(Cava.bars, root.barCount)

    IconButton {
        id: pill
        height: Tokens.pillHeight
        width:  root.showController ? controller.preferredWidth : root.vizWidth
        Behavior on width { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }

        squareMode: Config.barShape
        clip:       true

        // Middle-click used to toggle a floating now-playing card on the desktop. That
        // card is gone (the overview's media pair replaced it), so the binding went with
        // it rather than being left pointing at nothing.
        onClicked:      Config.cavaBg  = !Config.cavaBg
        onRightClicked: root._toggleShowcontroller()

        // ── Indicator dot ─────────────────────────────────────────────────────
        // The desktop cava background is on. "A thing is open" is `focus`, not `primary`.
        IndicatorDot {
            lit: Config.cavaBg
            anchors.top:        parent.top
            anchors.right:      parent.right
            anchors.margins:    Tokens.spacingSm
        }

        // ── Spectrum ──────────────────────────────────────────────────────────
        // Shared renderer (components/Spectrum.qml). Sized to `barCount * (barW +
        // barGap) - barGap`, which is exactly what Spectrum's derived bar width solves
        // back to `barW` — so these stay 3px bars without the component needing a
        // fixed-width mode.
        Spectrum {
            anchors.centerIn: parent
            width:  root.barCount * (root.barW + root.barGap) - root.barGap
            height: root.maxBarH

            levels:   root.bars
            barCount: root.barCount
            barGap:   root.barGap
            accent:   root.accent

            opacity: root.showController ? 0.0 : 1.0
            visible: opacity > 0.005
            Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.travel } }
        }

        // ── Media controller ──────────────────────────────────────────────────
        MediaController {
            id: controller
            anchors.fill: parent
            shown: root.showController
        }
    }
}
