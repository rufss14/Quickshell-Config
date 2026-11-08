#version 440
// ── wallwave ──────────────────────────────────────────────────────────────────
// The new WALLPAPER spreading over the old from the bottom middle, like water
// (modules/desktop/WallpaperView.qml, one per WallWave channel). A wobbly rim with a
// foam line, the picture bending like a lens just under the rim, ripples trailing
// behind it. Outside the front: transparent, the old wallpaper shows.
//
// `src` is the new picture exactly as it will sit on screen (zoomed and panned by
// the parallax), so the water hands over to the settled wallpaper with no jump.
// `tint` is what the foam and ripples lift toward — the palette's foreground
// (Colors.fg), so even the water's light is the theme's, never a hardcoded white.
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
    vec4 tint;
};
layout(binding = 1) uniform sampler2D src;
//@FRONT
void main() {
    // Not started: nothing. (The rim's wobble alone would put a small blob at the
    // bottom middle while the change is still being prepared.)
    if (progress <= 0.0) { fragColor = vec4(0.0); return; }
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2((uv.x - 0.5) * aspect, 1.0 - uv.y);
    float d = length(p);
    float inside = frontInside(p, progress, aspect, time);
    float calm = 1.0 - 0.7 * progress;
    float a = smoothstep(-0.004, 0.010, inside);
    // The lens: just under the rim the picture is pushed outward, like looking
    // through the water's edge.
    float band = exp(-(inside * inside) / 0.0016);
    vec2 dir = p / max(d, 1e-4);
    vec2 off = dir * band * 0.020;
    vec4 c = texture(src, vec2(uv.x - off.x / aspect, uv.y + off.y));
    float foam = exp(-(inside - 0.006) * (inside - 0.006) / 0.00006) * 0.35;
    float rip = sin(inside * 80.0 - time * 10.0) * exp(-max(inside, 0.0) * 9.0) * 0.05 * calm;
    c.rgb = c.rgb + tint.rgb * (foam + rip) * c.a;
    fragColor = vec4(c.rgb * a, c.a * a) * qt_Opacity;
}
