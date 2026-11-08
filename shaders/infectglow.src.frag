#version 440
// ── infectglow ────────────────────────────────────────────────────────────────
// The FRONT of the wave on one shell window (components/Infection.qml), blended
// over whatever infect.frag left: the old look's anti-aliased edge, then a bright
// line right at the front and a burn trailing behind it — freshly taken shell glows
// in the NEW accent and cools into its new colour over ~0.1 of the screen height.
// It glows only where there is shell to glow on (the snapshot's alpha, plus a few
// pixels of halo so the burn still reads on a thin frame), so it creeps along the
// frame and up the bar like an infection.
//
// glow: the new accent (Colors.primary — already live underneath by now).
// lift: what the hottest line is mixed toward (Colors.fg) — the palette's own
//       light, never a hardcoded white.
// texel: one logical pixel of the snapshot, in uv, for the halo.
// burn:  how strongly freshly taken ground glows behind the line — 1 on the shell's
//        chrome (thin, so it creeps); lower over an app window (the WaveCurtain),
//        where the whole window is "ground" and a full burn would be a searchlight.
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
    vec4 rect;
    vec4 glow;
    vec4 lift;
    vec2 texel;
    float burn;
};
layout(binding = 1) uniform sampler2D src;
//@FRONT
void main() {
    if (cover < 0.5 || progress <= 0.0) discard;
    vec2 uv = qt_TexCoord0;
    vec2 su = rect.xy + uv * rect.zw;                 // this pixel, in whole-screen uv
    vec2 p = vec2((su.x - 0.5) * aspect, 1.0 - su.y);
    float inside = frontInside(p, progress, aspect, time);
    if (inside < -0.003) discard;                     // infect.frag drew it, exactly
    vec4 old = texture(src, uv);
    // The old look's own soft edge, blended here because infect.frag cannot blend.
    float keep = 1.0 - smoothstep(-0.003, 0.006, inside);
    // A few pixels of halo off the edge of the frame and bar, so the burn reads on
    // a thin frame (the snapshot's alpha, spread outward).
    vec2 px = texel * 5.0;
    float near = max(max(texture(src, uv + vec2(px.x, 0.0)).a, texture(src, uv - vec2(px.x, 0.0)).a),
                     max(texture(src, uv + vec2(0.0, px.y)).a, texture(src, uv - vec2(0.0, px.y)).a));
    near = max(near, max(max(texture(src, uv + 2.0 * vec2(px.x, 0.0)).a, texture(src, uv - 2.0 * vec2(px.x, 0.0)).a),
                         max(texture(src, uv + 2.0 * vec2(0.0, px.y)).a, texture(src, uv - 2.0 * vec2(0.0, px.y)).a)) * 0.5);
    float halo = max(old.a, near * 0.7);
    // The front: a bright line right at the edge…
    float rim = exp(-(inside - 0.004) * (inside - 0.004) / 0.00012);
    // …and a burn trailing behind it.
    float trail = inside > 0.0 ? exp(-inside / 0.10) : 0.0;
    float pulse = 0.8 + 0.2 * sin(time * 14.0 - inside * 90.0);
    float fade = 1.0 - smoothstep(0.75, 1.0, progress);        // the burn dies out as it lands
    vec3 hot = mix(glow.rgb, lift.rgb, 0.35);
    float g = (rim * 1.2 + trail * 0.8 * burn) * pulse * fade * halo;
    fragColor = (old * keep + vec4(hot, 1.0) * g) * qt_Opacity;
}
