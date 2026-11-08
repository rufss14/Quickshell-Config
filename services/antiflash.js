.pragma library

// ── antiflash.js ──────────────────────────────────────────────────────────────
// The arithmetic behind services/AntiFlash: a brightness reading → the gain the
// screen should be at, the steps it eases through, and the shader that applies it.
// Pure, so `bun scripts/test-antiflash.js` pins it (and compiles the shader).
// ─────────────────────────────────────────────────────────────────────────────

// Above the threshold, aim the mean back down at it, no further than the floor;
// quantised to 0.05 so a page scrolling doesn't recompile a shader per sample.
function gainFor(mean, threshold, floor) {
    if (!(mean > threshold) || threshold <= 0) return 1
    const raw = Math.max(floor, Math.min(1, threshold / mean))
    return Math.round(raw * 20) / 20
}

// The next target from a reading. Dimming is immediate; brightening needs a margin —
// the same answer from a reading 8% brighter — so a reading on the edge of a step
// doesn't flicker between two. Returns the current target when nothing should change.
function decide(mean, target, threshold, floor) {
    let want = gainFor(mean, threshold, floor)
    if (want > target) want = Math.max(target, gainFor(mean * 1.08, threshold, floor))
    return Math.abs(want - target) < 0.049 ? target : want
}

// `steps` evenly spaced levels from `from` to `to`, ending exactly on `to`.
function ramp(from, to, steps) {
    const n = Math.max(1, Math.round(steps))
    const out = []
    for (let i = 1; i <= n; i++) out.push(Math.round((from + (to - from) * i / n) * 100) / 100)
    out[out.length - 1] = to
    return out
}

// The screen shader at a fixed gain (GLSL ES 3.0, Hyprland's screen-shader contract:
// `tex`, `v_texcoord`, `fragColor`). Brights take the full gain, darks a third of it,
// so a dark UI stays readable while a white page comes down.
function shader(gain) {
    const g = Math.max(0.05, Math.min(1, Number(gain) || 1)).toFixed(2)
    return "#version 300 es\n"
         + "// Written by services/AntiFlash.qml: anti-flashbang at a fixed gain.\n"
         + "precision mediump float;\n"
         + "in vec2 v_texcoord;\n"
         + "layout(location = 0) out vec4 fragColor;\n"
         + "uniform sampler2D tex;\n"
         + "const float GAIN = " + g + ";\n"
         + "void main() {\n"
         + "    vec4 c = texture(tex, v_texcoord);\n"
         + "    float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));\n"
         + "    float g = mix(1.0 - (1.0 - GAIN) / 3.0, GAIN, smoothstep(0.15, 0.75, l));\n"
         + "    fragColor = vec4(c.rgb * g, c.a);\n"
         + "}\n"
}

// Mean luminance (0..1) of RGBA bytes, Rec. 709 weights.
function meanLuma(data) {
    let s = 0, n = 0
    for (let i = 0; i + 3 < data.length; i += 4) {
        s += 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]
        n++
    }
    return n > 0 ? s / n / 255 : 0
}
