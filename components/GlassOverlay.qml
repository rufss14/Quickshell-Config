import QtQuick
import Quickshell
import "../config"

// ── GlassOverlay ──────────────────────────────────────────────────────────────
// The lit-glass treatment for a rounded surface: a graded body, a soft sheen across
// the top, and a rim following the whole contour. Drop it into anything with a
// rounded rectangle and it makes that thing read as a pane of glass.
//
// ── What this is NOT ──────────────────────────────────────────────────────────
// It does not refract. Refraction needs a TEXTURE of what is behind the surface, and
// only the desktop tiles have one — they sit on the layer-shell background, so the
// wallpaper is genuinely all that is behind them, and `shaders/liquidglass.frag`
// samples it. The bar and the screen frame sit above windows: what is behind them is
// whatever you happen to have open, which the shell cannot sample. For those, the
// compositor's own blur supplies the diffuse body and this supplies the light.
//
// So there are two tiers on purpose, and this is the lower one. It is also the
// fallback for tiles when no wallpaper texture exists (a settings preview has no
// position on any screen; a Wallpaper Engine video has no still frame at all).
//
// ── Why the corners are four properties ───────────────────────────────────────
// Bar pills square off individual corners when they fuse into the screen frame's
// band or run into its side strips. Glass drawn at a uniform radius over a pill with
// two square corners misses them by the radius, which shows up as a bright arc
// crossing the corner. Every layer here takes the same four radii as its host.
Item {
    id: root

    // The host's corner radii. Set `radius` for the simple case; override individual
    // corners to match a surface that squares some of them off.
    property real radius: 0
    property real topLeftRadius:     root.radius
    property real topRightRadius:    root.radius
    property real bottomLeftRadius:  root.radius
    property real bottomRightRadius: root.radius

    // How much light the material carries. One number so a caller can dial the whole
    // treatment up or down; the individual strengths are ratios of it, tuned together.
    // 1.0 is what the desktop tiles use.
    property real intensity: 1.0

    // The colour light is made of here. The palette's foreground, because that is the
    // shell's "light on this background" role — never a literal white, which is wrong
    // the moment the wallpaper turns the palette warm.
    property color lightColor: Colors.of(QsWindow.window).fg

    // 1 — the body. Brightest at the top where light lands, with a little gathering at
    // the foot the way it pools at the bottom of a thick pane. Without that second
    // term the surface just fades out and reads as a gradient rectangle rather than as
    // something with a far edge.
    Rectangle {
        anchors.fill: parent
        antialiasing: true
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        gradient: Gradient {
            // Every far stop is the light colour at ZERO ALPHA, never "transparent".
            // Qt interpolates gradient stops in straight RGBA, so fading to #00000000
            // drags the colour toward black on the way down and leaves a dirty band
            // across the middle. Holding the hue and moving only the alpha is the fix,
            // and it is invisible until you go looking for it.
            GradientStop { position: 0.0;  color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.24 * root.intensity) }
            GradientStop { position: 0.42; color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.0) }
            GradientStop { position: 0.88; color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.0) }
            GradientStop { position: 1.0;  color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.10 * root.intensity) }
        }
    }

    // 2 — the sheen.
    //
    // Full bleed to the sides, wearing the HOST'S OWN top corners. Both matter, and
    // both were arrived at by rendering it wrong first:
    //
    //   • Inset from the sides with a radius of its own, it has a silhouette, and at
    //     mid-fade that silhouette draws a visible curve straight across the surface.
    //   • Full bleed with SQUARE corners instead leaks a bright nub outside the host's
    //     radius. Invisible at a glance and unambiguous in the pixels: the corner
    //     measured 22 levels above the backdrop where a plain one measured 1.
    //
    // Matching the host's top corners makes its outline coincide everywhere except the
    // bottom, and the bottom fades to zero alpha, so it has no edge to see. No clipping
    // layer is needed — which is just as well, since `layer.enabled` does NOT clip to a
    // parent's radius (see SpectrumPicker).
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(4, parent.height * 0.34)
        antialiasing: true
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  0
        bottomRightRadius: 0
        gradient: Gradient {
            GradientStop { position: 0.0; color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.19 * root.intensity) }
            GradientStop { position: 1.0; color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.0) }
        }
    }

    // 3 — the rim, over the other two so the edge stays the crispest thing here. One
    // continuous ring at uniform brightness: a half-height ring was tried, to light the
    // top more than the bottom, and a half ring HAS A BOTTOM EDGE which lands as a line
    // straight across the middle. Real glass catches light all the way round anyway.
    Rectangle {
        anchors.fill: parent
        antialiasing: true
        topLeftRadius:     root.topLeftRadius
        topRightRadius:    root.topRightRadius
        bottomLeftRadius:  root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        color: "transparent"
        border.width: 1
        border.color: Colors.of(QsWindow.window).alpha(root.lightColor, 0.32 * root.intensity)
    }
}
