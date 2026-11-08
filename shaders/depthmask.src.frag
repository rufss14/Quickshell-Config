#version 440
// ── depthmask ─────────────────────────────────────────────────────────────────
// The depth clock's occlusion (components/DepthMasked): the clock, hidden wherever the picture's
// mask says something stands in front of it.
//
//   out = clock × (1 − softened(mask.alpha))
//
// `src` is the clock, premultiplied, so scaling all four channels by (1 − cover) stays premultiplied
// and a soft edge in the mask is a soft edge on the clock. `mask` is the grey+alpha PNG scripts/
// wallpaper-depth.py writes, already cut to the screen's shape, so the same coordinates address both:
// no framing maths here.
//
// ── The softening ─────────────────────────────────────────────────────────────
// The mask is as sharp as the model could make it, which on a screen is a hard line that shows
// every pixel of its own edge. `soft` (in mask texels, which are screen pixels: the mask is decoded at
// the screen's size) blurs the cover with a 3×3 binomial kernel [1 2 1; 2 4 2; 1 2 1]/16 spaced `soft`
// texels apart — bilinear sampling fills in between, so a spacing of 1–2 reads as a smooth ~1–3 px edge.
// 0 is the mask as it is. A blur of the COVER (not of the clock) means only the occlusion edge moves.
//
// Why not MultiEffect's mask: its mask handling is thresholds and a spread with undocumented edge
// cases, and an exact product is easier to trust than to measure.
//
// Edit this, then rebuild it (scripts/build-shaders.sh, or just this one:
//   /usr/lib/qt6/bin/qsb --qt6 -o shaders/depthmask.frag.qsb shaders/depthmask.src.frag).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 texel;     // one mask texel, in texture coordinates
    float soft;     // the kernel's spacing, in texels; 0 = none
};
layout(binding = 1) uniform sampler2D src;
layout(binding = 2) uniform sampler2D mask;

float cover(vec2 uv) { return texture(mask, uv).a; }

void main() {
    vec2 uv = qt_TexCoord0;
    float c;
    if (soft <= 0.001) {
        c = cover(uv);
    } else {
        vec2 d = texel * soft;
        c  = cover(uv) * 4.0;
        c += (cover(uv + vec2(-d.x, 0.0)) + cover(uv + vec2(d.x, 0.0))
            + cover(uv + vec2(0.0, -d.y)) + cover(uv + vec2(0.0, d.y))) * 2.0;
        c += cover(uv + vec2(-d.x, -d.y)) + cover(uv + vec2(d.x, -d.y))
           + cover(uv + vec2(-d.x,  d.y)) + cover(uv + vec2(d.x,  d.y));
        c /= 16.0;
    }
    fragColor = texture(src, uv) * (1.0 - c) * qt_Opacity;
}
