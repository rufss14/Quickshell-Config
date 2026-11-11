import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../../services/wallfx.js" as FX

// ── WallFx ────────────────────────────────────────────────────────────────────
// The wallpaper moved by the music (2026-10-31, the user's ask: "make music feel more
// intense on the desktop … not only images but also Wallpaper Engine"). It takes the
// screen's whole drawn wallpaper — the picture, a captured scene window, the material
// wallpaper, the colour wave — as one texture and draws it again through
// shaders/wallfx.frag, every effect weighed by the song (MusicPulse.songView) and the user's
// intensity and per-sound trims (Config.wallFxIntensity / wallFxMix; services/wallfx.js says
// which sound moves which effect, and how the song shapes them).
//
// ── Nothing while it isn't moving ─────────────────────────────────────────────
// The view says whether it may (`allowed`: it draws this screen's wallpaper, no fullscreen
// window covers it, no Game Mode card). Only then does it ask MusicPulse to listen, and
// MusicPulse only listens while music plays. While nothing moves the source is drawn as it
// always was — no texture, no shader, no extra pass; `active` is the one switch, and it
// stays on while an effect winds down after the music stops.
//
// A scene the layer renderer draws is another program's surface and can't be reached: the
// shell has to be the one drawing it (a scene playing from its window — ScenePreload).
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The wallpaper as this screen draws it.
    property Item source: null
    property bool allowed: false

    // Reduced motion: the wallpaper no longer moves with the music. (`!reduced`, not `ambientOn`:
    // "animations off" never stopped this, and that stays as it was.)
    readonly property bool wanted: Config.wallFx && !Motion.reduced && root.allowed && FX.anyOn(Config.wallFxMix) && !PowerSaver.active

    property bool _held: false
    onWantedChanged: {
        if (root.wanted && !root._held) { MusicPulse.acquire(); root._held = true }
        else if (!root.wanted && root._held) { MusicPulse.release(); root._held = false }
    }
    Component.onCompleted: if (root.wanted) { MusicPulse.acquire(); root._held = true }
    Component.onDestruction: if (root._held) MusicPulse.release()

    readonly property real aspect: root.height > 0 ? root.width / root.height : 1
    // Sampled once per drawn frame, not bound: MusicPulse moves ~90 times a second, a field at
    // a time, and a binding would run amounts() for each field that changed.
    property var amt: FX.amounts({}, 0, null, null, null, 1)
    // This screen's motion between frames: the rumble's gate, the shockwave's age, the clock.
    property var _motion: FX.motionInitial()
    function _sample(dtMs) {
        // The music as it sounds on THIS frame: the rhythm engine's events are scheduled for when
        // the speakers play them (MusicPulse.pulseAt), so a kick lands on the frame it's heard.
        const p = MusicPulse.pulseAt(Date.now())
        root._motion = FX.step(root._motion, p, dtMs)
        // The target, then glided toward (wallfx.js `glide`: each effect its own rise and fall).
        root.amt = FX.glide(root.amt, FX.amounts(Config.wallFxMix, Config.wallFxIntensity, p,
                                                 MusicPulse.songView, root._motion, root.aspect), dtMs)
    }
    // (No re-sample on `active` changing: `active` reads `amt`, so that was a binding loop. The
    // FrameAnimation samples on its first frame, and an inactive layer draws nothing.)
    readonly property bool active: root.wanted && (MusicPulse.live || FX.any(root.amt))
    // Waking up starts the motion over: its counts are stale, and a bass note or snare heard
    // while asleep would otherwise fire on the first frame.
    onActiveChanged: if (root.active) root._motion = FX.motionInitial()

    FrameAnimation {
        running: root.active
        onTriggered: root._sample(frameTime * 1000)
    }

    ShaderEffectSource {
        id: tex
        sourceItem: root.active ? root.source : null
        hideSource: root.active
        live: true
        mipmap: true
        smooth: true
        visible: false
        width: root.width
        height: root.height
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.active
        fragmentShader: Qt.resolvedUrl("../../shaders/wallfx.frag.qsb")

        property var  src: tex
        property real aspect: root.aspect
        property real seed: MusicPulse.impacts    // the glitch's slices: new per hardest hit
        property real seedHat: (MusicPulse.songView.hats ?? 0) % 997   // the shimmer: new per hat
        property real zoom: root.amt.zoom
        property real punch: root.amt.punch
        property real shakeX: root.amt.shakeX
        property real shakeY: root.amt.shakeY
        property real shock: root.amt.shock
        property real shockR: root.amt.shockR
        property real shimmer: root.amt.shimmer
        property real glitch: root.amt.glitch
        property real blur: root.amt.blur
        property real glow: root.amt.glow
        property real bloom: root.amt.bloom
        property real pulse: root.amt.pulse
        property real strobe: root.amt.strobe
        property real texelX: 1 / Math.max(1, root.width)
        property real texelY: 1 / Math.max(1, root.height)
        // The glow's light: the palette's most colourful slot (its `vivid`).
        property color tint: Colors.of(QsWindow.window).vivid
    }
}
