#version 440

// ── liquidglass.frag ──────────────────────────────────────────────────────────
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
// `src` is the WALLPAPER, and the tile is told where it sits (`tileOrigin`) on a
// screen of `screenSize`, so it samples exactly the region of wallpaper it covers.
// That is truthful because these tiles live on the wlr-layershell BACKGROUND layer:
// the wallpaper genuinely is the only thing behind them. The bar and the frame sit
// above windows and cannot use this trick — they need the compositor's own blur.
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
    float specular;     // rim highlight, 0..1
    float tintAmount;   // 0..1
    float dim;          // darkens the body so content stays readable, 0..1
    vec4  tint;
} ubuf;

layout(binding = 1) uniform sampler2D src;

// Signed distance to a rounded rectangle: negative inside, zero on the contour.
// Everything else here is expressed against this one function, so the refraction, the
// specular and the silhouette cannot disagree with each other at the corners.
float sdRoundBox(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Screen UV for a point in tile space, so every sample goes through one place.
vec2 screenUV(vec2 tilePx) {
    return (ubuf.tileOrigin + tilePx) / ubuf.screenSize;
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
    vec2 bodyPx = (px - b) / (1.0 + ubuf.bulge) + b;
    vec2 lensPx = bodyPx + n * (ubuf.strength * t * t);

    // ── Body blur ─────────────────────────────────────────────────────────────
    // Eight taps on a rotated ring plus the centre. Not a gaussian and not trying to be:
    // at this radius the point is to take the edge off detail so the tile reads as
    // diffuse, and a ring is the cheapest thing that does not show a cross pattern.
    // Weighted so the centre still dominates, or a busy wallpaper turns to mush.
    vec3 col = texture(src, clamp(screenUV(lensPx), vec2(0.0), vec2(1.0))).rgb * 2.0;
    float wsum = 2.0;
    if (ubuf.blurRadius > 0.05) {
        for (int i = 0; i < 8; i++) {
            float a = (float(i) / 8.0) * 6.2831853 + 0.3927;
            // Two rings, so a single radius does not band on gradients.
            float r = ubuf.blurRadius * ((i % 2 == 0) ? 1.0 : 0.55);
            vec2 off = vec2(cos(a), sin(a)) * r;
            col  += texture(src, clamp(screenUV(lensPx + off), vec2(0.0), vec2(1.0))).rgb;
            wsum += 1.0;
        }
    }
    col /= wsum;

    // Glass lightens slightly and desaturates slightly; then the configured tint.
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(col, vec3(lum), 0.12);
    col = mix(col, ubuf.tint.rgb, ubuf.tintAmount);

    // Held back a little so widget text stays legible over a bright wallpaper. This is
    // the one non-physical term here and it earns its place: a perfectly clear pane over
    // a white photo is a tile you cannot read.
    col *= (1.0 - ubuf.dim);

    // ── Rim light ─────────────────────────────────────────────────────────────
    // Brightest where the surface turns fastest — the corners — and modulated by a fixed
    // light direction so the tile has a lit side rather than a uniform halo.
    vec2  lightDir = normalize(vec2(-0.4, -1.0));
    float facing   = clamp(dot(n, lightDir), 0.0, 1.0);
    col += vec3(ubuf.specular) * pow(t, 5.0) * (0.30 + 0.70 * facing);

    // A hairline of concentrated light on the contour itself. Narrow on purpose: wider
    // and it stops reading as an edge and becomes a border.
    float hair = smoothstep(0.82, 1.0, t) * smoothstep(1.0, 0.94, t);
    col += vec3(0.14 * ubuf.specular / max(ubuf.specular, 0.0001)) * hair * ubuf.specular;

    // Antialias the silhouette over one pixel.
    float cov = clamp(0.5 - d, 0.0, 1.0);
    fragColor = vec4(col, 1.0) * cov * ubuf.qt_Opacity;
}
