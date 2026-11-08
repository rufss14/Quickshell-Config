#version 440
// ── wallfx ────────────────────────────────────────────────────────────────────
// The wallpaper, moved by the music (modules/desktop/WallFx.qml, 2026-10-31): every effect in
// one pass, each an amount WallFx sets every frame from MusicPulse (services/wallfx.js: the
// sound, the song, the user's trim, the master intensity). 0 = untouched.
//
//   zoom     the picture punches in from the centre on the kick; `punch` splits the colours
//            outward as it hits (red in, blue out — the music-video look)
//   shake    the bass's rumble: the picture trembles by (shakeX, shakeY) in uv
//   shock    the snare's shockwave: one ring at radius `shockR` (screen heights) bends the
//            picture as it passes and catches a little light
//   shimmer  the hi-hats: the brightest parts twinkle, a new pattern per hat (`seedHat`)
//   glitch   slices of the picture slip sideways, the channels split (the hardest hits)
//   blur     softened toward a blurred copy (breakdowns)
//   glow     a soft copy in the palette's `tint`, laid over (screen)
//   bloom    the highlights bleed light
//   pulse    brightness pumps (the kick)
//   strobe   a white flash on strong hits (MusicPulse caps them at three a second)
//
// The edge is MIRRORED (`mirror`): a tremble, a slice or the shockwave reaching past it shows
// the picture folded back, a few pixels of it — so nothing has to zoom in to hide the edge.
//
// `src` is the wallpaper as the screen shows it, MIPMAPPED (ShaderEffectSource.mipmap):
// the soft copy for blur, glow and bloom is a few taps at a higher mip level, not a
// second render. Reached with a BIAS, not textureLod, and `texel` (1 / the texture's size)
// comes in as a uniform: qsb's Qt 6 targets include GLSL ES 100, which has neither
// textureLod nor textureSize. The screen samples it 1:1, so the bias is the level.
//
// Edit this, then run scripts/build-shaders.sh.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float aspect;
    float seed;
    float seedHat;
    float zoom;
    float punch;
    float shakeX;
    float shakeY;
    float shock;
    float shockR;
    float shimmer;
    float glitch;
    float blur;
    float glow;
    float bloom;
    float pulse;
    float strobe;
    float texelX;
    float texelY;
    vec4 tint;
};
layout(binding = 1) uniform sampler2D src;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Folds a coordinate past the edge back inside it.
vec2 mirror(vec2 uv) {
    return 1.0 - abs(1.0 - abs(uv));
}

// Five taps around mip level `lod`, a step of that level's texel apart: a soft copy.
vec4 soft(vec2 uv, float lod) {
    vec2 px = exp2(lod) * vec2(texelX, texelY);
    vec4 c = texture(src, uv, lod) * 0.4;
    c += texture(src, mirror(uv + vec2( px.x, 0.0)), lod) * 0.15;
    c += texture(src, mirror(uv + vec2(-px.x, 0.0)), lod) * 0.15;
    c += texture(src, mirror(uv + vec2(0.0,  px.y)), lod) * 0.15;
    c += texture(src, mirror(uv + vec2(0.0, -px.y)), lod) * 0.15;
    return c;
}

void main() {
    vec2 c = (qt_TexCoord0 - 0.5) / (1.0 + zoom);

    // The shockwave: a derivative-of-Gaussian band, so the picture is pushed out just ahead of
    // the ring and pulled in just behind it — a lens passing, not a wobble.
    float front = 0.0;
    if (shock > 0.0) {
        vec2 p = vec2(c.x * aspect, c.y);
        float d = length(p);
        float x = (d - shockR) / 0.06;
        float ring = exp(-x * x);
        c -= (p / max(d, 1e-4)) * x * ring * shock * 0.025 * vec2(1.0 / aspect, 1.0);
        front = ring * shock;
    }

    vec2 uv = mirror(c + 0.5 + vec2(shakeX, shakeY));

    float split = 0.0;
    if (glitch > 0.0) {
        float band = floor(uv.y * 28.0);
        float h = hash(vec2(band, seed));
        float on = step(1.0 - glitch * 0.5, h);
        uv.x += on * (hash(vec2(seed + 7.0, band)) - 0.5) * 0.1 * glitch;
        uv = mirror(uv);
        split = glitch * 0.008;
    }

    vec4 col = texture(src, uv);
    // The colours apart: sideways for a glitch, outward from the middle for a punch.
    float ca = punch * 0.014;
    if (split > 0.0 || ca > 0.0) {
        vec2 out_ = (uv - 0.5) * ca;
        col.r = texture(src, mirror(uv + vec2(split, 0.0) - out_)).r;
        col.b = texture(src, mirror(uv - vec2(split, 0.0) + out_)).b;
    }

    if (blur > 0.0)
        col = mix(col, soft(uv, 1.0 + blur * 4.0), min(1.0, blur * 3.0));

    if (glow > 0.0 || bloom > 0.0) {
        vec4 s = soft(uv, 4.5);
        float l = dot(s.rgb, vec3(0.299, 0.587, 0.114));
        col.rgb += s.rgb * smoothstep(0.42, 0.9, l) * bloom * 1.8;
        vec3 g = tint.rgb * (0.35 + l) * glow * 0.8;
        col.rgb = 1.0 - (1.0 - col.rgb) * (1.0 - g);
    }

    // The shimmer: 3 px cells, a few of them lit, only where the picture is already bright.
    if (shimmer > 0.0) {
        vec2 cell = floor(qt_TexCoord0 / (3.0 * vec2(texelX, texelY)));
        float n = hash(cell + vec2(seedHat * 17.0, seedHat * 3.0));
        float l = dot(col.rgb, vec3(0.299, 0.587, 0.114));
        float spark = smoothstep(0.92, 1.0, n) * smoothstep(0.45, 0.9, l);
        col.rgb += vec3(spark * shimmer * 1.2) * col.a;
    }

    col.rgb += vec3(front * 0.18) * col.a;
    col.rgb *= 1.0 + pulse * 0.4;
    col.rgb = mix(col.rgb, vec3(col.a), strobe * 0.85);

    fragColor = vec4(min(col.rgb, vec3(col.a)), col.a) * qt_Opacity;
}
