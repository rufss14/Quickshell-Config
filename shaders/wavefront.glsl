// ── wavefront.glsl ────────────────────────────────────────────────────────────
// THE shape of a wallpaper/palette change (services/WallWave.qml): one front that
// spreads from the bottom middle of the screen like water. Every wave shader has
// this pasted in at `//@FRONT` by scripts/build-shaders.sh — the wallpaper's water
// (wallwave) and the shell's infection (infect, infectglow) — so the new picture and
// the new colours cannot move apart: same curve, same wobble, same clock.
//
// Returns how far inside the front a point is: > 0 already taken, < 0 not yet.
//   p         the point, origin at the screen's BOTTOM MIDDLE, y up, in screen
//             heights (x scaled by `aspect`)
//   progress  0 → 1, WallWave's channel (eased on Motion.travel)
//   aspect    screen width / height
//   time      WallWave.t, seconds — the rim's drift
//
// Ported unchanged from the shell this effect came from. services/contagion.js
// mirrors R below (progress × (maxR + 0.14), without the wobble) to know when the
// front reaches a window; change one and change the other.
float frontInside(vec2 p, float progress, float aspect, float time) {
    float d = length(p);
    float ang = atan(p.y, p.x);
    // The farthest point of the screen from the origin: a top corner.
    float maxR = length(vec2(0.5 * aspect, 1.0));
    float calm = 1.0 - 0.7 * progress;                 // the rim settles as it arrives
    // A liquid rim: three sine waves round the circumference, drifting.
    float wob = (sin(ang * 7.0 + time * 5.0) * 0.022
               + sin(ang * 13.0 - time * 7.0) * 0.011
               + sin(ang * 23.0 + time * 11.0) * 0.006) * calm;
    // Tendrils: thin fingers reaching ahead of the front, like something growing.
    float v1 = pow(max(0.0, sin(ang * 37.0 + time * 2.3)), 12.0);
    float v2 = pow(max(0.0, sin(ang * 61.0 - time * 3.1 + 1.7)), 16.0);
    float veins = (v1 * 0.055 + v2 * 0.04) * calm * smoothstep(0.0, 0.08, progress);
    float R = progress * (maxR + 0.14) + wob + veins;
    return R - d;
}
