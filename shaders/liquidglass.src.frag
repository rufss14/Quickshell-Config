#version 440

// ── liquidglass.src.frag ──────────────────────────────────────────────────
// The desktop tiles' material. A rounded-rect lens over the wallpaper.
//
// ── Why a shader and not layered Rectangles ───────────────────────────────────
// The previous material was a graded fill, a rim and a sheen — three stacked
// Rectangles. That is frosted glass, and the thing it cannot do is the one thing
// that actually identifies Apple's material: REFRACTION. A thick pane does not
// merely tint what is behind it, it bends it, hardest right at the edge, so the
// backdrop appears compressed into the rim and the tile reads as having depth
// rather than as a translucent sticker. No arrangement of opaque layers gets there.
//
// ── What it samples, and why that is honest here ──────────────────────────────
// `src` is the WALLPAPER AS DRAWN on this screen (components/WallBackdrop: the parallax
// zoom and pan, the workspace's own picture, the crossfade), and the tile is told where
// it sits (`tileOrigin`) on a screen of `screenSize`, so it samples exactly the region of
// wallpaper it covers — including while that wallpaper moves under it.
// That is truthful because these tiles live on the wlr-layershell BACKGROUND layer:
// the wallpaper genuinely is the only thing behind them. The bar and the frame sit
// above windows and cannot use this trick — they need the compositor's own blur.
//
// ── It reads the background it is over ────────────────────────────────────────
// The body is dimmed in proportion to how bright the wallpaper is under each pixel (a
// clear pane over a white photo is unreadable; over a dark one the same dim is a hole) and
// pulled toward the tile's own tone where it is very dark. The border does the same: the
// light on its lit side gives way to shade as the backdrop gets brighter, because a white
// rim over white vanishes.
//
// ── The border is part of the glass ───────────────────────────────────────────
// The shell's stroke (`rimBase`, the colour WidgetFrame's border carries — so hover and
// drag still change it) is drawn here, over the refraction, with light on it: bright on
// the upper-left, a fainter kick on the far side, shade just inside the lower-right so the
// edge has thickness. Drawn in the shader rather than as a Rectangle border because only
// the shader knows the contour the refraction bends against and what is behind it.
//
// ── Self-contained by design ──────────────────────────────────────────────────
// The body blur is done here with a handful of taps rather than by a MultiEffect or
// a ShaderEffectSource feeding this. Two reasons. It keeps the whole material to ONE
// texture and zero render targets, so seventeen tiles do not mean seventeen offscreen
// buffers. And an invisible ShaderEffectSource yields a 0x0 texture, which makes a
// ShaderEffect draw nothing at all — measured, and a trap worth not building on.
//
// Regenerate the .qsb after editing:
//   qsb --glsl "100es,120,150" --hlsl 50 --msl 12 \
//       -o shaders/liquidglass.frag.qsb shaders/liquidglass.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4  qt_Matrix;
    float qt_Opacity;
    vec2  size;         // tile size, px
    vec2  tileOrigin;   // tile's top-left in screen px
    vec2  screenSize;   // px
    float radius;       // corner radius, px
    float thickness;    // width of the refracting edge band, px
    float strength;     // edge displacement, px
    float bulge;        // whole-body magnification, 0..1
    float blurRadius;   // body softening, px
    float dispersion;   // colour split at the rim, 0..1
    float tintAmount;   // 0..1
    float dim;          // darkens a bright body so content stays readable, 0..1
    float bodyAlpha;    // how much of the body shows over what is under the tile, 0..1
    float rimWidth;     // the stroke, px
    float rimStrength;  // how much light and shade the border carries, 0..1
    vec4  tint;
    vec4  rimBase;      // the stroke itself (straight alpha)
    vec4  rimLight;     // what the lit side of the border is made of
    vec4  rimShade;     // and the far side
} ubuf;

layout(binding = 1) uniform sampler2D src;

// Signed distance to a rounded rectangle: negative inside, zero on the contour.
// Everything else here is expressed against this one function, so the refraction, the
// border and the silhouette cannot disagree with each other at the corners.
float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Screen UV for a point in tile space, so every sample goes through one place.
vec2 screenUV(vec2 tilePx) {
    return (ubuf.tileOrigin + tilePx) / ubuf.screenSize;
}

vec3 backdrop(vec2 tilePx) {
    return texture(src, clamp(screenUV(tilePx), vec2(0.0), vec2(1.0))).rgb;
}

void main() {
    vec2 px = qt_TexCoord0 * ubuf.size;
    vec2 b  = ubuf.size * 0.5;
    vec2 p  = px - b;

    float d = sdRoundBox(p, b, ubuf.radius);

    // Nothing outside the silhouette. The QML side is a plain Item with no rounding of
    // its own, so this is what gives the tile its shape.
    if (d > 0.5) { fragColor = vec4(0.0); return; }

    // Outward normal, from the SDF gradient. Sampled with an epsilon rather than taken
    // from dFdx/dFdy: the edge band is only a few pixels wide, and screen-space
    // derivatives are noisiest exactly there — which is where this has to be smooth.
    const float e = 1.0;
    vec2 n = vec2(
        sdRoundBox(p + vec2(e, 0.0), b, ubuf.radius) - sdRoundBox(p - vec2(e, 0.0), b, ubuf.radius),
        sdRoundBox(p + vec2(0.0, e), b, ubuf.radius) - sdRoundBox(p - vec2(0.0, e), b, ubuf.radius));
    n = length(n) > 0.0001 ? normalize(n) : vec2(0.0, -1.0);

    // 0 deep in the body, 1 at the rim.
    float t = clamp(1.0 + d / max(ubuf.thickness, 0.001), 0.0, 1.0);

    // ── The lens ──────────────────────────────────────────────────────────────
    // Two components, both needed. A gentle magnification across the whole body, so the
    // tile reads as a solid piece of glass rather than a flat window with a decorated
    // border; and a sharp displacement inside the edge band that drags the backdrop
    // outward into the rim, which is the "squeeze" that makes it look thick.
    vec2  bodyPx = (px - b) / (1.0 + ubuf.bulge) + b;
    float push   = ubuf.strength * t * t;
    vec2  lensPx = bodyPx + n * push;

    // ── Body blur ─────────────────────────────────────────────────────────────
    // Eight taps on a rotated ring plus the centre. Not a gaussian and not trying to be:
    // at this radius the point is to take the edge off detail so the tile reads as
    // diffuse, and a ring is the cheapest thing that does not show a cross pattern.
    // Weighted so the centre still dominates, or a busy wallpaper turns to mush.
    vec3 col = backdrop(lensPx) * 2.0;
    float wsum = 2.0;
    if (ubuf.blurRadius > 0.05) {
        for (int i = 0; i < 8; i++) {
            float a = (float(i) / 8.0) * 6.2831853 + 0.3927;
            // Two rings, so a single radius does not band on gradients.
            float r = ubuf.blurRadius * ((i % 2 == 0) ? 1.0 : 0.55);
            col  += backdrop(lensPx + vec2(cos(a), sin(a)) * r);
            wsum += 1.0;
        }
    }
    col /= wsum;

    // ── Dispersion ────────────────────────────────────────────────────────────
    // Glass bends red less than blue, so at the rim the channels land a little apart: a
    // faint warm/cool fringe where the backdrop is squeezed. Two extra taps, only worth
    // anything where the displacement is (t²), and only the channel each one owns.
    if (ubuf.dispersion > 0.001 && push > 0.5) {
        float k = t * t;
        float r = backdrop(bodyPx + n * push * (1.0 + ubuf.dispersion)).r;
        float bl = backdrop(bodyPx + n * push * (1.0 - ubuf.dispersion)).b;
        col.r = mix(col.r, r,  k * 0.7);
        col.b = mix(col.b, bl, k * 0.7);
    }

    // Glass desaturates slightly; then the configured tint.
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(col, vec3(lum), 0.12);
    col = mix(col, ubuf.tint.rgb, ubuf.tintAmount);

    // ── Reading the background ────────────────────────────────────────────────
    // `bright` is how light the wallpaper is right here. The dim is the one non-physical
    // term and it earns its place: a perfectly clear pane over a white photo is a tile you
    // cannot read. It scales with the backdrop, so a light patch is held back further than
    // a dark one, and where the backdrop is nearly black the body is drawn up toward the
    // tile's own tone instead, so the glass does not become a hole in the wallpaper.
    float bright = smoothstep(0.30, 0.85, lum);
    col *= 1.0 - ubuf.dim * mix(0.5, 1.7, bright);
    col = mix(col, ubuf.tint.rgb, 0.35 * (1.0 - smoothstep(0.02, 0.28, lum)));

    // ── The border ────────────────────────────────────────────────────────────
    // `ring` is the stroke: 1 inside `rimWidth` of the contour, a soft inner edge. The
    // outer edge is the silhouette's own antialiasing below.
    float w    = max(ubuf.rimWidth, 0.5);
    float ring = clamp(d + w + 0.5, 0.0, 1.0);

    // Which way this bit of edge faces the light. A fixed light, upper left, so the tile
    // has a lit side. `lit` is the lit side; `kick` a fainter one opposite, the light that
    // passed through the pane and came out the far edge.
    vec2  lightDir = normalize(vec2(-0.55, -0.85));
    float f    = dot(n, lightDir);
    float lit  = smoothstep(-0.25, 1.0, f);
    float kick = smoothstep(0.30, 1.0, -f) * 0.55;
    float glint = max(lit, kick);

    // The stroke itself, then light on it. A bright backdrop takes less highlight (white
    // on white is nothing) and more shade, which is what keeps the border readable on both.
    col = mix(col, ubuf.rimBase.rgb, ubuf.rimBase.a * ring);
    col = mix(col, ubuf.rimLight.rgb, ring * ubuf.rimStrength * glint * mix(1.0, 0.55, bright));

    // Just inside the stroke: a soft bloom on the lit side and shade on the far side. This
    // is the edge's thickness — what makes the border a rounded lip and not a drawn line.
    float inner = pow(t, 4.0) * (1.0 - ring);
    col = mix(col, ubuf.rimLight.rgb, inner * lit * 0.10 * ubuf.rimStrength * mix(1.0, 0.5, bright));
    col = mix(col, ubuf.rimShade.rgb, pow(t, 3.0) * (1.0 - lit) * 0.16 * ubuf.rimStrength * mix(0.6, 1.4, bright));

    // The body shows `bodyAlpha` of itself over what is under the tile; the stroke does not
    // fade with it (the border stays crisp at any opacity — Surface's own rule).
    float alpha = mix(ubuf.bodyAlpha, 1.0, ring);

    // Antialias the silhouette over one pixel.
    float cov = clamp(0.5 - d, 0.0, 1.0);
    fragColor = vec4(col * alpha, alpha) * cov * ubuf.qt_Opacity;
}
