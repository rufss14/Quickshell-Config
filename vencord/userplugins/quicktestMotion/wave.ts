/*
 * quicktestMotion — the Spotify progress-bar wave, drawn the way components/WaveSlider.qml draws
 * it: a real anti-aliased curve on a canvas, not a raster SVG tile scrolled via CSS `mask-
 * position`. Four CSS-only rounds (2026-11-01, same day) each fixed a real, CDP-confirmed bug —
 * restart-on-remount, the unsupported `mask-position-x` longhand, a `:root`-wide style recalc
 * tanking the whole page's frame rate — and STILL didn't look right: the user's side-by-side
 * comparison against the shell's own WaveSlider called it "on 30 frames" and asked for what an
 * earlier Claude session had built, which "really looked like the one from quickshell, straight
 * out." A scrolled raster pattern is never going to read the same as a redrawn vector curve, no
 * matter how smoothly it scrolls — the CSS approach was the wrong tool for this, not just buggy.
 * This replaces it outright: same math as WaveSlider.qml (`_curve`'s quadratic-through-samples
 * construction, `frequency: 6`, `lineW: 4`, amplitude `lineW * 0.5`, phase `Date.now() / 400`,
 * capped to 30 redraws/sec — WaveSlider.qml's own cap, "a wave travelling ~8px/s needs no more"),
 * just targeting a 2D canvas context instead of an SVG `ShapePath`.
 *
 * Position/duration come straight from `SpotifyStore` (Vencord's own built-in spotifyControls
 * plugin, which owns `#vc-spotify-player`) — `position` is already wall-clock-interpolated by the
 * store itself (`mPosition + (Date.now() - _start)` while playing), so the fill fraction this
 * drives is as smooth as the wave's own phase, not tied to the DOM bar's own 1s-interval `width`
 * transition the way the CSS approach was.
 *
 * The canvas is a child of `.bar_ec237e`, `position: absolute; inset: 0; pointer-events: none` —
 * drawn OVER the real (now-invisible, see quicktest.theme.css) wave mask, under nothing, so native
 * seeking/dragging on the real slider underneath is untouched. Re-created if the bar element is
 * ever swapped out from under it (Vencord's unmemoized re-render, documented above) — checked once
 * per tick, cheap (one querySelector), nothing like the `:root` write that caused the real
 * perf bug three rounds ago.
 */
import { SpotifyStore } from "@plugins/spotifyControls/SpotifyStore";

const FREQUENCY = 6; // cycles across the full track width — WaveSlider.qml's own tuning
const LINE_W = 4;
const AMPLITUDE = LINE_W * 0.5; // WaveSlider.qml: _amp at full "alive"
const HANDLE_GAP = 7; // pulls the curve's end back from the playhead — WaveSlider.qml's own gap
const SAMPLE_STEP = 3; // px between samples — WaveSlider.qml's own
const STEP_MS = 1000 / 30; // WaveSlider.qml's own cap

let rafId: number | null = null;
let lastStep = 0;
let canvas: HTMLCanvasElement | null = null;
let currentBar: Element | null = null;

function ensureCanvas(bar: HTMLElement): HTMLCanvasElement {
    if (canvas && canvas.isConnected && currentBar === bar) return canvas;
    canvas?.remove();
    const c = document.createElement("canvas");
    c.style.position = "absolute";
    c.style.inset = "0";
    c.style.pointerEvents = "none";
    bar.style.position ||= "relative"; // Discord's own rule usually already sets this; belt and braces
    bar.appendChild(c);
    canvas = c;
    currentBar = bar;
    return c;
}

function draw(bar: HTMLElement, accent: string) {
    const c = ensureCanvas(bar);
    const rect = bar.getBoundingClientRect();
    const dpr = window.devicePixelRatio || 1;
    const cssW = Math.max(1, rect.width), cssH = Math.max(1, rect.height);
    if (c.width !== Math.round(cssW * dpr) || c.height !== Math.round(cssH * dpr)) {
        c.width = Math.round(cssW * dpr);
        c.height = Math.round(cssH * dpr);
        c.style.width = `${cssW}px`;
        c.style.height = `${cssH}px`;
    }
    const ctx = c.getContext("2d");
    if (!ctx) return;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, cssW, cssH);

    const track = SpotifyStore.track;
    const duration = track?.duration ?? 0;
    const fraction = duration > 0 ? Math.max(0, Math.min(1, SpotifyStore.position / duration)) : 0;
    const fillX = cssW * fraction;
    const drawEnd = Math.max(0, fillX - HANDLE_GAP);
    if (drawEnd <= 1) return;

    const centerY = cssH / 2;
    const k = FREQUENCY * 2 * Math.PI / cssW; // wavelength relative to the FULL track, not the filled portion
    const phase = Date.now() / 400.0; // WaveSlider.qml's own phase source — the wall clock, nothing to restart
    const y = (t: number) => centerY + AMPLITUDE * Math.sin(k * t + phase);

    const x0 = LINE_W / 2;
    ctx.beginPath();
    ctx.moveTo(x0, y(x0));
    let px = x0;
    for (let x = x0 + SAMPLE_STEP; x < drawEnd; x += SAMPLE_STEP) {
        const midX = (px + x) / 2;
        ctx.quadraticCurveTo(px, y(px), midX, (y(px) + y(x)) / 2);
        px = x;
    }
    ctx.quadraticCurveTo(px, y(px), drawEnd, y(drawEnd));
    ctx.lineWidth = LINE_W;
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    ctx.strokeStyle = accent;
    ctx.stroke();
}

function tick(t: number) {
    rafId = requestAnimationFrame(tick);
    if (t - lastStep < STEP_MS) return;
    lastStep = t;

    const bar = document.querySelector<HTMLElement>("#vc-spotify-player .slider_ec237e .bar_ec237e");
    if (!bar) return; // no Spotify panel mounted
    if (!SpotifyStore.isPlaying) { canvas?.remove(); canvas = null; currentBar = null; return; } // paused: nothing drawn, same as CSS's flat mask
    const accent = getComputedStyle(document.documentElement).getPropertyValue("--qs-focus").trim() || "#fff";
    draw(bar, accent);
}

/** Starts the wave canvas driver. Returns a cleanup function. */
export function watchWave(): () => void {
    lastStep = performance.now();
    rafId = requestAnimationFrame(tick);
    return () => {
        if (rafId !== null) { cancelAnimationFrame(rafId); rafId = null; }
        canvas?.remove();
        canvas = null;
        currentBar = null;
    };
}
