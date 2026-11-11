import QtQuick
import Quickshell
import "../config"
import "../services"

// ── MusicRim ──────────────────────────────────────────────────────────────────
// A bar pill's rim lit by the music (2026-10-31): a thin line of the palette's `vivid`, as
// bright as the music is loud, on BOTH bars' islands — the top bar's chips (BarGroup) and the
// sidebar's pills (SideRegionPills). Config.barMusicReact turns it on.
//
// ── Clean, not busy ───────────────────────────────────────────────────────────
// The first version scaled each sidebar pill on the beat and laid a wash over it; the user
// found it "a bit messy and not really a clean look" — the pill jumped round content that
// stayed put — and it was the sidebar's alone. So: nothing changes size, there is no fill,
// and the brightness rides the effects spring (Motion.springEffectsSlow) toward the level with
// a little of the beat in it, so it swells and settles instead of flashing per kick.
//
// Holds MusicPulse only while on and on screen; MusicPulse itself listens only while music
// plays, and the rim draws nothing at rest.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // The pill's own corner radius, so the rim lies exactly on its edge.
    property real radius: 0
    // Whose switch: the top bar's by default; the sidebar passes Config.sideMusicReact
    // (its own once unlinked in Bar & sidebar › Style).
    property bool react: Config.barMusicReact

    readonly property bool _wanted: root.react && root.visible
    property bool _held: false
    on_WantedChanged: {
        if (root._wanted && !root._held) { MusicPulse.acquire(); root._held = true }
        else if (!root._wanted && root._held) { MusicPulse.release(); root._held = false }
    }
    Component.onCompleted: if (root._wanted) { MusicPulse.acquire(); root._held = true }
    Component.onDestruction: if (root._held) MusicPulse.release()

    SpringValue {
        id: glow
        spec: Motion.springEffectsSlow
        epsilon: 0.002
        target: root._held ? Math.min(1, 0.8 * MusicPulse.level + 0.25 * MusicPulse.kick) : 0
    }

    Rectangle {
        anchors.fill: parent
        visible: glow.value > 0.01
        radius: root.radius
        color: "transparent"
        border.width: Tokens.borderChrome
        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).vivid, 0.65 * glow.value)
    }
}
