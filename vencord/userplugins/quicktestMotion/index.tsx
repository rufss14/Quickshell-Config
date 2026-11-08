/*
 * quicktestMotion — the Spotify progress-bar wave (wave.ts), driven the way WaveSlider.qml drives
 * it (wall-clock phase, not a CSS keyframe loop — see wave.ts's header). quicktest.theme.css does
 * everything else in pure CSS; this is the one piece that needs script.
 *
 * The sidebar/composer/guild-rail hover-track plate that used to live here (hoverTrack.ts,
 * style.css) was removed 2026-11-01 — user's call, didn't like the look. Each icon's own CSS
 * hover (quicktest.theme.css) was never wired to hand off to it, so removing it changed nothing
 * else.
 *
 * Deliberately NOT a webpack/React patch — no `patches` here, same reasoning quicktest.theme.css
 * follows for its own selectors (ARIA / a distinctively-named class over a hashed one): a patch
 * breaks HARD on a webpack module id shift, where a missing DOM node just means the wave doesn't
 * attach until it reappears.
 *
 * Requires quicktest.theme.css (or a theme defining the same --qs-* custom properties) to be the
 * active theme — without it `--qs-wave-x` is written but nothing reads it.
 */
import definePlugin from "@utils/types";

import { watchWave } from "./wave";

let stopWave: (() => void) | null = null;

export default definePlugin({
    name: "QuicktestMotion",
    description: "Drives the Quicktest theme's Spotify progress-bar wave off the wall clock instead of a CSS keyframe loop, so it doesn't restart every time Vencord's Spotify plugin re-renders the bar.",
    authors: [{ name: "rufss14", id: 0n }],
    tags: ["Motion", "Customisation"],
    required: false,
    enabledByDefault: false,

    start() {
        stopWave = watchWave();
    },

    stop() {
        stopWave?.();
        stopWave = null;
    },
});
