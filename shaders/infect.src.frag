#version 440
// ── infect ────────────────────────────────────────────────────────────────────
// The OLD look of one shell window — a frozen snapshot — standing wherever the
// wave's front has not reached yet (components/Infection.qml). Where the front HAS
// reached, this draws nothing and the live window, already in its new colours,
// shows. infectglow.frag draws the front itself on top.
//
// ── Drawn with blending OFF, which is the point of splitting it out ───────────
// A snapshot laid OVER the live window leaks: the shell's surfaces are translucent
// (Config.barOpacity, widget glass), so wherever the old look was 90% opaque, 10% of
// the NEW colour underneath showed through before the front arrived. This pass
// instead REPLACES the pixel — old colour and old alpha, exactly — so a frozen
// surface is frozen, whatever its opacity. Pixels it discards are left to the live
// window (and to infectglow's anti-aliased edge).
//
// cover 0: the frame the snapshot is TAKEN in — draw nothing at all, or the capture
// would record this pass instead of the window.
//
// Edit this (or wavefront.glsl), then run scripts/build-shaders.sh.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;
    float aspect;
    float time;
    float cover;
    vec4 rect;        // where this window sits on its screen: screen uv = rect.xy + uv * rect.zw
};
layout(binding = 1) uniform sampler2D src;
//@FRONT
void main() {
    if (cover < 0.5) discard;
    vec2 uv = qt_TexCoord0;
    if (progress > 0.0) {
        vec2 su = rect.xy + uv * rect.zw;             // this pixel, in whole-screen uv
        vec2 p = vec2((su.x - 0.5) * aspect, 1.0 - su.y);
        // Taken, or inside the edge band infectglow blends: not this pass's pixel.
        if (frontInside(p, progress, aspect, time) > -0.003) discard;
    }
    fragColor = texture(src, uv) * qt_Opacity;
}
