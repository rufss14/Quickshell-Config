pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── VisualizerWidget ──────────────────────────────────────────────────────────
// The audio spectrum, on the desktop. Pure decoration, and one of the only widgets
// here whose whole point is motion.
//
// Cava is refcounted and shared: the bar's pill, the desktop background and the sound
// page all read the SAME analyser, so adding this tile does not start a second cava.
// It releases when the tile is hidden, so a covered desktop isn't analysing audio.
//
// ── Three looks, one analyser ─────────────────────────────────────────────────
// `opts.style` picks the renderer: classic bars, a smoothed waveform ribbon, or a
// segmented LED-style grid. All three read the same `Cava` singleton — no style
// starts its own process, and only the ACTIVE one is instantiated (a Loader, not
// three overlapping items), so switching styles costs nothing and an unpicked
// style costs nothing while idle.
Item {
    id: root
    required property var opts
    required property string size
    property int widgetId: -1
    property bool active: true
    property color accent: Colors.of(QsWindow.window).primary

    property bool _held: false
    function _sync() {
        if (root.active && !root._held)      { Cava.acquire(); root._held = true }
        else if (!root.active && root._held) { Cava.release(); root._held = false }
    }
    onActiveChanged: root._sync()
    Component.onCompleted:   root._sync()
    Component.onDestruction: if (root._held) Cava.release()

    // "cookie" (Material 3 Expressive, 2026-10-30): a tonal cookie that swells with the bass,
    // ringed by the spectrum — the default for the square small tile, where a row of bars
    // has the least room. The wide sizes keep bars unless a style was picked.
    readonly property string vizStyle: root.opts.style ?? (root.size === "small" ? "cookie" : "bars")

    // Mirrored/centered only shape the "bars" and "wave" styles — a dot grid
    // already reads as its own thing regardless.
    readonly property bool mirroredMode: root.opts.mirrored ?? true
    readonly property bool centeredMode: root.opts.centered === true

    // ── "bars" ────────────────────────────────────────────────────────────────
    // Mirrored by default — the spectrum reads as symmetrical about its centre, the
    // shape a visualiser is expected to have, and it fills a wide tile better than a
    // ramp that trails off to the right. Bars grow from the vertical middle out when
    // `centered` — the bar pill's Dynamic-Island shape — bottom-aligned otherwise,
    // the same as every other level readout in the shell.
    readonly property var barsLevels: root.mirroredMode ? Cava.mirrored(Cava.bars) : Cava.bars
    readonly property int  barsCount: root.size === "small" ? 16 : 32

    // ── "dots" ────────────────────────────────────────────────────────────────
    // Fewer, wider columns than the bar styles — an LED grid reads as blocky cells,
    // and 32 of them in a 168px tile would be thinner than the gaps between them.
    readonly property int dotCols: root.size === "small" ? 6 : (root.size === "large" ? 14 : 10)
    readonly property var dotsLevels: root.mirroredMode
        ? Cava.mirrored(Cava.resample(Cava.bars, Math.max(1, Math.floor(root.dotCols / 2))))
        : Cava.resample(Cava.bars, root.dotCols)

    Loader {
        anchors.fill: parent
        sourceComponent: root.vizStyle === "wave" ? waveComp
                        : root.vizStyle === "dots" ? dotsComp
                        : root.vizStyle === "cookie" ? cookieComp
                        : barsComp
    }

    Component {
        id: barsComp
        Spectrum {
            levels: root.barsLevels
            barCount: root.barsCount
            centered: root.centeredMode
            accent: root.accent
        }
    }
    Component {
        id: waveComp
        WaveformSpectrum {
            levels: root.barsLevels
            barCount: root.barsCount
            centered: root.centeredMode
            accent: root.accent
        }
    }
    // The cookie: each bar is a zero-size Item at the centre turned to its angle, the dash
    // laid along its +x axis from just outside the cookie (CookieCover's ring idiom), so a
    // bar's length is only its `width`. The cookie's swell rides the fast spatial spring.
    Component {
        id: cookieComp
        Item {
            id: ck
            readonly property int n: 28
            readonly property var lv: Cava.resample(Cava.bars, ck.n)
            readonly property real side: Math.min(width, height)
            readonly property real core: ck.side * 0.5
            readonly property real gap: Tokens.spacingSm
            readonly property real thick: Tokens.spacingXs * 2
            readonly property real reach: ck.side / 2 - ck.core / 2 - ck.gap - ck.thick
            readonly property real bass: ck.lv.length >= 3 ? (ck.lv[0] + ck.lv[1] + ck.lv[2]) / 3 : 0

            SpringValue {
                id: swell
                spec: Motion.springSpatialFast
                epsilon: 0.002
                target: Cava.hasData ? ck.bass : 0
            }
            MorphShape {
                anchors.centerIn: parent
                width: ck.core
                height: ck.core
                shape: Config.barShape ? "squircle" : "cookie9"
                fillColor: Colors.of(QsWindow.window).primaryContainer
                scale: 0.92 + 0.16 * swell.value
            }
            Repeater {
                model: ck.n
                Item {
                    id: ray
                    required property int index
                    x: ck.width / 2
                    y: ck.height / 2
                    rotation: ray.index / ck.n * 360 - 90
                    Rectangle {
                        x: ck.core / 2 + ck.gap
                        y: -height / 2
                        height: ck.thick
                        width: ck.thick + Math.max(0, ck.reach) * Math.max(0, Math.min(1, ck.lv[ray.index] ?? 0))
                        radius: height / 2
                        antialiasing: true
                        color: root.accent
                    }
                }
            }
        }
    }

    Component {
        id: dotsComp
        DotMatrixSpectrum {
            levels: root.dotsLevels
            barCount: root.dotCols
            accent: root.accent
        }
    }

    WidgetEmpty {
        visible: !Cava.hasData
        glyph: "󰄨"
        text: Translation.tr("Play something")
    }
}
