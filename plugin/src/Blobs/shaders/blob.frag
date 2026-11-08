#version 440
// Adapted verbatim from caelestia-dots/shell (plugin/src/Caelestia/Blobs/shaders/), GPLv3.
// See plugin/LICENSE and plugin/README.md.


layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float paddedX;
    float paddedY;
    float paddedW;
    float paddedH;
    float smoothFactor;
    int rectCount;
    int myIndex;
    vec4 color;
    int hasInverted;
    float invertedRadius;
    // Offsets 120/124 were std140 padding between `invertedRadius` and the vec4 at
    // 128 — borderWidth fits there without moving anything below it. borderColor is
    // appended AFTER rectData (offset 1440) for the same reason: every existing
    // offset in blobmaterial.cpp stays exactly where it was.
    float borderWidth;
    float _pad0;
    vec4 invertedOuter;
    vec4 invertedInner;
    vec4 rectData[80];
    vec4 borderColor;
    // ── The cookie field (Quicktest addition; BlobGroup::cookies) ──────────────
    // cookieParams: count, stroke width. cookieData: two vec4 per cookie —
    //   (cx, cy, radius, rotation) and (petals, petal depth, opacity, tone + 4 * outlined).
    vec4 cookieParams;
    vec4 tones[4];
    vec4 cookieData[48];
    // ── The rim sweep (Quicktest addition; BlobGroup::rimSweep / rimColor) ────────
    // rimSweep: centre x, centre y, radius, width. rimColor: rgb, strength (0 = off).
    vec4 rimSweep;
    vec4 rimColor;
};

float sdRoundedBox(vec2 p, vec2 center, vec2 halfSize, float radius) {
    vec2 d = abs(p - center) - halfSize + vec2(radius);
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0) - radius;
}

float sdRoundedBox4(vec2 p, vec2 center, vec2 halfSize, vec4 r) {
    // r = (topRight, bottomRight, bottomLeft, topLeft)
    p -= center;
    r.xy = (p.x > 0.0) ? r.xy : r.wz;
    r.x  = (p.y > 0.0) ? r.y : r.x;
    vec2 q = abs(p) - halfSize + r.x;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r.x;
}

float sdBox(vec2 p, vec2 center, vec2 halfSize) {
    vec2 d = abs(p - center) - halfSize;
    return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float smin(float a, float b, float k) {
    // Circular smooth min — the blend fillet is a true circular arc of radius k,
    // tangent to both surfaces (not a polynomial/squircle curve). Deviates from
    // min(a, b) only in the corner region where BOTH a < k and b < k (unlike the
    // cubic it replaced, which deviated over the whole band |a - b| < k). Always
    // <= min(a, b); max blend depth at a == b is (sqrt(2) - 1) * k. It is C1 but
    // not C2 at the support boundary, so a circular-arc fillet shows the usual
    // line-meets-arc curvature step — by design, that is the "circular" look.
    return max(k, min(a, b)) - length(max(vec2(k) - vec2(a, b), vec2(0.0)));
}

float smax(float a, float b, float k) {
    // Circular smooth max — dual of smin: -smin(-a, -b, k). Always >= max(a, b).
    return min(-k, max(a, b)) + length(max(vec2(a, b) + vec2(k), vec2(0.0)));
}

float smaxSharpA(float a, float b, float k) {
    // Circular smax variant that keeps a's boundary sharp (no inward rounding at
    // a = 0). Used for the frame outer edge so it always fills to the edges.
    float sm = min(-k, max(a, b)) + length(max(vec2(a, b) + vec2(k), vec2(0.0)));
    float blend = (sm - max(a, b)) * smoothstep(0.0, k * 0.5, -a);
    return max(a, b) + blend;
}

void main() {
    vec2 pixel = vec2(paddedX, paddedY) + qt_TexCoord0 * vec2(paddedW, paddedH);

    // Phase 1: compute per-rect SDF, track owner. We can't smin yet because excluded
    // pairs need to skip the smooth blend, which requires pairwise pass below.
    float dArr[16];
    int owner = -2;
    float minDist = 1e10;

    for (int i = 0; i < rectCount; i++) {
        vec4 rect = rectData[i * 5];         // cx, cy, hw, hh
        vec4 props = rectData[i * 5 + 1];    // excludeMask(int bits), offsetX, offsetY, minEig
        vec4 invDm = rectData[i * 5 + 2];    // inverse deform matrix
        vec4 sh = rectData[i * 5 + 3];       // screenHalfX, screenHalfY, 0, 0
        vec4 radii = rectData[i * 5 + 4];    // effective per-corner radii (tr, br, bl, tl)

        // Offset center for asymmetric deformation
        vec2 center = rect.xy + props.yz;

        // AABB early-out: skip rects far from this pixel
        vec2 extent = sh.xy + vec2(smoothFactor * 1.5);
        if (abs(pixel.x - center.x) > extent.x || abs(pixel.y - center.y) > extent.y) {
            dArr[i] = 1e10;
            continue;
        }

        // Apply pre-computed inverse deformation to the evaluation point
        mat2 invDeform = mat2(invDm.xy, invDm.zw);
        vec2 transformedPixel = center + invDeform * (pixel - center);

        // Use pre-computed effective per-corner radii
        float d = sdRoundedBox4(transformedPixel, center, rect.zw, radii);

        // Use pre-computed minimum eigenvalue for SDF correction
        d *= max(props.w, 0.01);

        // Scale SDF on the axis facing a nearby border to narrow the smin blend zone
        // in that direction only, without reducing k (which would cause sharp edges).
        if (hasInverted != 0) {
            vec2 screenHalf = sh.xy;

            float distY0 = (center.y + screenHalf.y) - (invertedInner.y - invertedInner.w);
            float distY1 = (invertedInner.y + invertedInner.w) - (center.y - screenHalf.y);
            float distX0 = (center.x + screenHalf.x) - (invertedInner.x - invertedInner.z);
            float distX1 = (invertedInner.x + invertedInner.z) - (center.x - screenHalf.x);

            // 0 = far from border, 1 = at border (max compression)
            float yProx = 1.0 - min(
                smoothstep(0.0, smoothFactor, distY0),
                smoothstep(0.0, smoothFactor, distY1)
            );
            float xProx = 1.0 - min(
                smoothstep(0.0, smoothFactor, distX0),
                smoothstep(0.0, smoothFactor, distX1)
            );

            // Smooth axis weights: gradient-based at corners, face-based inside.
            vec2 q = abs(pixel - center) - screenHalf;
            vec2 qp = max(q, vec2(0.0));
            float cornerLen = length(qp);

            // Gradient direction in corner region (smooth 90-degree rotation)
            float gradX = qp.x / max(cornerLen, 0.001);
            float gradY = qp.y / max(cornerLen, 0.001);

            // Smooth face weights for inside/edge (no hard branch)
            float faceY = smoothstep(-4.0, 4.0, q.y - q.x);
            float faceX = 1.0 - faceY;

            // Blend: gradient in corner region, face-based inside
            float t = smoothstep(0.0, 2.0, cornerLen);
            float xWeight = mix(faceX, gradX, t);
            float yWeight = mix(faceY, gradY, t);

            float boost = 3.0;
            float scale = 1.0 + (xProx * xWeight + yProx * yWeight) * boost;
            d *= scale;
        }

        dArr[i] = d;
        if (d < smoothFactor && d < minDist) {
            minDist = d;
            owner = i;
        }
    }

    // Phase 2: hard-min baseline over all rects.
    float mergedSdf = 1e10;
    for (int i = 0; i < rectCount; i++) {
        mergedSdf = min(mergedSdf, dArr[i]);
    }

    // Phase 3: pair-wise smin contributions, skipping excluded pairs. Pair smin <= min,
    // so taking the min over all non-excluded pair smins gives the smoothly-merged SDF.
    for (int i = 0; i < rectCount; i++) {
        if (dArr[i] >= 1e9)
            continue;
        int excludeMask = floatBitsToInt(rectData[i * 5 + 1].x);
        for (int j = i + 1; j < rectCount; j++) {
            if (dArr[j] >= 1e9)
                continue;
            if ((excludeMask & (1 << j)) != 0)
                continue;
            // Circular smin deviates from min only where BOTH dArr are < smoothFactor.
            if (max(dArr[i], dArr[j]) >= smoothFactor)
                continue;
            mergedSdf = min(mergedSdf, smin(dArr[i], dArr[j], smoothFactor));
        }
    }

    if (hasInverted != 0) {
        float dOuter = sdBox(pixel, invertedOuter.xy, invertedOuter.zw) - 1.0;
        float dInner = sdRoundedBox(pixel, invertedInner.xy, invertedInner.zw, invertedRadius);

        // Border sinks: track the opposite rect edge, clamped to border thickness
        float innerTop = invertedInner.y - invertedInner.w;
        float innerBot = invertedInner.y + invertedInner.w;
        float innerLeft = invertedInner.x - invertedInner.z;
        float innerRight = invertedInner.x + invertedInner.z;
        float outerTop = invertedOuter.y - invertedOuter.w;
        float outerBot = invertedOuter.y + invertedOuter.w;
        float outerLeft = invertedOuter.x - invertedOuter.z;
        float outerRight = invertedOuter.x + invertedOuter.z;

        float sinkValue = 0.0;
        for (int i = 0; i < rectCount; i++) {
            vec4 rect = rectData[i * 5];
            vec4 sinkProps = rectData[i * 5 + 1];
            vec2 sinkSh = rectData[i * 5 + 3].xy;

            // Screen-space center (with offset) and pre-computed AABB half-extents
            vec2 ctr = rect.xy + sinkProps.yz;

            // Sink onset / residual overlap: how far a rect must penetrate the border before
            // the inner wall recedes to form its pocket. Too low and the wall recedes faster
            // than the junction can stay convex, denting the inner edge inward near the rect's
            // (squared) corners; too high and the rect nestles too deep before the wall yields.
            // Tuned between the old cubic blend depth (k/6, too shallow) and the circular blend
            // depth ((sqrt2-1)k): half the circular smin gap-closing distance, (2-sqrt2)k/2.
            float preOff = smoothFactor * (2.0 - sqrt(2.0)) * 0.5;

            // Top border: track rect's BOTTOM edge, only within border thickness
            float topPen = clamp(innerTop - (ctr.y + sinkSh.y) - preOff, 0.0, innerTop - outerTop);

            // Bottom border: track rect's TOP edge
            float botPen = clamp((ctr.y - sinkSh.y) - innerBot - preOff, 0.0, outerBot - innerBot);

            // Left border: track rect's RIGHT edge
            float leftPen = clamp(innerLeft - (ctr.x + sinkSh.x) - preOff, 0.0, innerLeft - outerLeft);

            // Right border: track rect's LEFT edge
            float rightPen = clamp((ctr.x - sinkSh.x) - innerRight - preOff, 0.0, outerRight - innerRight);

            // Lateral distance from pixel to rect's extent along each edge
            float hLat = max(abs(pixel.x - ctr.x) - sinkSh.x, 0.0);
            float vLat = max(abs(pixel.y - ctr.y) - sinkSh.y, 0.0);

            // Perpendicular proximity: full strength in border, fade inside inner area
            float topZone = 1.0 - smoothstep(innerTop, innerTop + smoothFactor, pixel.y);
            float botZone = smoothstep(innerBot - smoothFactor, innerBot, pixel.y);
            float leftZone = 1.0 - smoothstep(innerLeft, innerLeft + smoothFactor, pixel.x);
            float rightZone = smoothstep(innerRight - smoothFactor, innerRight, pixel.x);

            float s = smoothFactor * 2.0;
            float sink = max(
                max(topPen * smoothstep(s, 0.0, hLat) * topZone,
                    botPen * smoothstep(s, 0.0, hLat) * botZone),
                max(leftPen * smoothstep(s, 0.0, vLat) * leftZone,
                    rightPen * smoothstep(s, 0.0, vLat) * rightZone)
            );
            sinkValue = max(sinkValue, sink);
        }

        dInner -= sinkValue;

        // The circular smax fillet has radius kFrame; when it exceeds the border thickness
        // it can't complete inside the border, so the sharp outer-box term bleeds onto the
        // inner edge and bulges the inner corners (worst when thickness < smoothFactor — the
        // default border is thinner than the blend radius). Clamp kFrame to the thinnest side
        // so the inner edge stays a clean constant-radius arc. Each inner corner is bounded by
        // its thinner adjacent side, so the global min is correct for every corner.
        float minThick = min(min(innerTop - outerTop, outerBot - innerBot),
                             min(innerLeft - outerLeft, outerRight - innerRight));
        float kFrame = clamp(min(smoothFactor, minThick - 1.0), 1.0, smoothFactor);
        float dFrame = smaxSharpA(dOuter, -dInner, kFrame);

        mergedSdf = smin(mergedSdf, dFrame, smoothFactor);
        if (dFrame < minDist) {
            owner = -1;
        }
    }

    // Each renderer only outputs pixels it owns, but allow rendering
    // blend zones to prevent gaps (mergedSdf < smoothFactor means in blend)
    // myIndex == -1: inverted rect renders border-owned pixels
    // myIndex >= 0: individual rect renders its owned pixels
    //
    // Quicktest: and only the OWNER draws the interior. Every quad near a join used to paint the
    // whole region it covers, which is harmless for an opaque fill drawn twice, but the cookies are
    // translucent — drawn by two quads they doubled, and a later quad's fill covered an earlier
    // owner's cookies outright. The owner's quad always covers what it owns (its own interior, or a
    // fillet within the blend reach of its edge), so only the anti-aliased rim is left shared.
    if (owner != myIndex && (mergedSdf > smoothFactor || mergedSdf < -1.5))
        discard;

    float fw = fwidth(mergedSdf);
    float alpha = 1.0 - smoothstep(-fw, fw, mergedSdf);

    // ── The outline ─────────────────────────────────────────────────────────
    // mergedSdf is the union of every shape in the group, so a band along it is
    // ONE continuous stroke around the whole merged silhouette — bar, frame,
    // fillet and panel — with no join anywhere to align. That is the entire point:
    // a Qt-drawn border is a closed rectangle and can never follow a metaball
    // surface, which is why the panel's own stroke had to go.
    //
    // Drawn in the INNERMOST borderWidth of the material (the band sits at
    // mergedSdf in [-borderWidth, 0]), matching how a Qt Rectangle insets its
    // border and how this shell's frame strokes sit in the innermost pixels of
    // their strips — so the blob's stroke lands where the old ones did.
    vec3 rgb = color.rgb;

    // ── The cookies ──────────────────────────────────────────────────────────
    // Scallops (the shell's components/Scallop: a circle whose radius breathes in and out N times
    // round the turn), each over the material in order, like the QML items they replace. Only on
    // the pixels this quad owns: the one place each pixel is drawn. The radial distance to the
    // outline stands in for the true distance — exact at the petal tips and troughs, a fraction
    // of a pixel off between, at these petal depths.
    int cookieCount = int(cookieParams.x + 0.5);
    if (cookieCount > 0 && owner == myIndex) {
        for (int i = 0; i < cookieCount; i++) {
            vec4 ca = cookieData[i * 2];
            vec4 cb = cookieData[i * 2 + 1];
            vec2 d = pixel - ca.xy;
            float R = ca.z;
            if (abs(d.x) > R + 2.0 || abs(d.y) > R + 2.0)
                continue;
            float amp = R * cb.y;
            float ang = atan(d.y, d.x) - ca.w;
            float edgeR = (R - amp) + amp * (0.5 + 0.5 * cos(cb.x * ang));
            float sd = length(d) - edgeR;
            float cov = 1.0 - smoothstep(-0.75, 0.75, sd);
            int code = int(cb.w + 0.5);
            if (code >= 4) {
                // the faint outline every third shape wears: a stroke on the edge at 0.55
                float stroke = cookieParams.y;
                cov = max(cov, 0.55 * (1.0 - smoothstep(stroke * 0.5 - 0.5, stroke * 0.5 + 0.5, abs(sd))));
            }
            float a = cov * cb.z;
            if (a <= 0.0)
                continue;
            rgb = mix(rgb, tones[code - (code >= 4 ? 4 : 0)].rgb, a);
        }
    }

    if (borderWidth > 0.0) {
        float edge = smoothstep(-borderWidth - fw, -borderWidth + fw, mergedSdf);
        rgb = mix(rgb, borderColor.rgb, edge * borderColor.a);

        // A band of light running along the outline: the pixels of the stroke (and a faint
        // inner glow beside it) whose distance from the sweep's centre is near its radius.
        // Gaussian across the band, so it has no hard edge to flicker as it travels.
        if (rimColor.a > 0.0) {
            float across = (length(pixel - rimSweep.xy) - rimSweep.z) / max(rimSweep.w, 1.0);
            float band = exp(-across * across);
            float glow = smoothstep(-borderWidth * 5.0, 0.0, mergedSdf);
            float lit = max(edge * borderColor.a, 0.35 * glow);
            rgb = mix(rgb, rimColor.rgb, clamp(band * rimColor.a * lit, 0.0, 1.0));
        }
    }

    fragColor = vec4(rgb * alpha, alpha) * qt_Opacity;
}
