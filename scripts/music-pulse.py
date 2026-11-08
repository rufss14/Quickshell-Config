#!/usr/bin/env python3
"""music-pulse.py — what the music is doing, fast enough to move with it.

The low-latency half of services/MusicPulse (2026-10-31). It reads a PipeWire node's audio
straight off `pw-record` — the playing app's own stream, so a Discord call or a notification
sound is not part of the music — and prints, about 94 times a second, one line of twenty
numbers the desktop moves to:

    level bass mid high kick beats flash bpm locked snare snares hat boom booms impact impacts
    loud sub heavy accents

level/bass/mid/high are 0..1 envelopes. `kick`, `snare`, `hat` and `boom` (a bass note: an
808, a bass guitar — not a kick) are 1 when that sound is HEARD and decay; `beats`,
`snares` and `booms` count kicks, snares and bass notes. `impact` is 1 on the hardest of
them — a kick or snare in the top `IMPACT_Q` of the last `IMPACT_WINDOW` hits' strength, at
most one a second (`IMPACT_GAP_S`), so it stays rare on any track — and `impacts` counts it. `flash` is 1 on the hardest
hits, at most three a second (the photosensitive-epilepsy guidance, WCAG 2.3.1: never more
than three flashes in any one second). `bpm` is the tempo the beat clock is locked to (0
while it isn't) and `locked` 1 while it is.

── How big this part of the song is (2026-10-31) ────────────────────────────────
The user: the effects were "too intense in calmer parts of the song and when the drop hits
it's quite underwhelming", and the rumble should come "when big bass kicks come". Every
envelope above is normalised to its band's own 4 s peak, so a quiet verse reads as loud as a
drop within seconds — measured on a cinematic track: the sub band (35–130 Hz) at 36–41 dB in
its big part and 16–20 dB in its calm one, the whole band 18–22 against 7–13 dB, all of it
erased by the normaliser. So three numbers that are NOT renormalised:
  `loud`   the whole band (35 Hz–9 kHz), smoothed over `SECTION_S`, in dB under the song's
           loudest so far: 1 at it, 0 at `LEVEL_RANGE_DB` below
  `sub`    the same for the sub band, over `SUB_RANGE_DB`
  `heavy`  how big the last kick's bass was: the sub band's peak in the `HEAVY_WINDOW_S` after
           it, on `sub`'s scale. The previous kick's value holds through that window and the
           new one replaces it at its end — resetting it to 0 at the kick made every punch
           start small and peak late (the user: "still feels out of sync")
"The loudest so far" falls `SONG_PEAK_FALL_DB_S` and never below a floor (`REF_LEVEL_DB`,
`REF_SUB_DB`, ~10 dB under that track's big part — one track measured), so a song that is calm
all the way through reads calm, and a quiet intro isn't taken for the drop.

── Accents (2026-10-31) ─────────────────────────────────────────────────────────
`accents` counts the snares worth a shockwave. The user: the ring "is constantly getting
spammed" — on a funk track every clap and tamborim is a snare (75 in 30 s, 230–370 ms apart).
So a snare is an accent when it is among the strongest of the last `ACCENT_WINDOW` (z against
their quantile 1 − `ACCENT_RATE` / the snare rate of the last `ACCENT_SPAN_S`: on a backbeat at
1 a second every snare passes, on a busy track the loudest ~1.2 a second) and at least
`ACCENT_GAP_S` after the last.

── One sound per effect (2026-10-31) ────────────────────────────────────────────
The user: "each effect should have a sound it should trigger after, not all at once, it
feels weird for the screen to be shaking and zooming without kicks". Two causes: every hit
effect followed the one `kick`, and while locked the clock FIRED beats on its predicted
grid, kick or no kick (a half-time bar, a fill, a skipped kick). So: nothing fires unless
it is heard, and the drum kit is split — kick, snare/clap and hi-hat each detected on its
own (see "The drums"), so services/wallfx.js can give each effect its own sound. Then the
user: zoom and shake "are the most intense so they should be Bass and Kicks" — so a bass
note that isn't a kick (`boom`) is a sound of its own too.

── Why not cava ─────────────────────────────────────────────────────────────────
The user, 2026-10-31: the effects "feel off or slow compared to the song". cava is built to
be LOOKED at: to resolve the bass it analyses a long window (tens of ms to ~100 ms, the
middle of which is what it reports), smooths on top, and `pw-record` itself buffers 100 ms
by default. Here: a 1024-sample window (21 ms) hopped every 256 samples (5.3 ms), asked of
PipeWire in 256-sample chunks (`--latency 256`), a beat called on the first hop it shows,
envelopes that fall in 110 ms instead of 240. `scripts/test-music-pulse.py` pins the latency
on a synthetic track: every kick found within one window of its start.

── The beat clock: a gate, not a trigger ────────────────────────────────────────
On bass-heavy music (an 808 that slides between notes) the kick band hears hits that aren't
kicks: measured on a 125 BPM phonk track the raw onsets fired 100 times in 20 s. So
`BeatTracker` finds the TEMPO (autocorrelation of a multi-band onset signal over the last
8 s, 70–180 BPM, a prior around 120) and the PHASE (the kick band's click-aware onsets
folded over that period across the last 6 s). While it is LOCKED, a kick onset counts only
within `KICK_GATE` of the grid — an 808 note on the off-beat doesn't — and nothing fires on
the grid without one. Unlocked (the fold doesn't stand out, or no kick for a few beats: a
breakdown) only a clear kick counts. `--offset-ms` holds every line back, for speakers
slower than the screen (Bluetooth); nothing can land earlier than it is heard.

── The drums ────────────────────────────────────────────────────────────────────
Measured on synthetic hits (band RMS per bin, the first 20 ms): a kick rises ~100 in the
kick band and only ~1.4 in the 1.5–6 kHz noise band (its beater click); a snare ~8 in the
noise band with ~6 above 7 kHz and a body at 150–400 Hz; a clap ~7 in the noise band and
almost nothing above; a hi-hat ~4.5 above 7 kHz and ~0.1 in the noise band; an 808 note
only the kick band. So a SNARE is a flux onset in the noise band whose rise is at least
`SNARE_OVER_HAT` of the hat band's (not a hat) and `SNARE_OVER_KICK` of the kick band's (not
a kick's click); a HAT a flux onset above 7 kHz rising `HAT_OVER_NOISE` times the noise
band's, and not a snare. A BOOM (a bass note) is a rise of the kick band's energy that isn't
a kick: waited on for `BOOM_HOLD_S` in case the kick is called a hop later, and not within
`BOOM_AFTER_KICK_S` of one.

── The onsets ───────────────────────────────────────────────────────────────────
Spectral flux in the kick band (35–130 Hz): how much the band's log-compressed magnitudes
ROSE since the last hop, against its own recent mean plus `FLUX_K` deviations (a ~1 s moving
average), over a floor, at most once per `REFRACTORY_S`. A rise, not a level — a bass that
sits loud doesn't fire, and a hi-hat isn't in the band. Magnitudes are normalised against a
slowly decaying peak per band (cava's autosens, our own), so loud and quiet tracks both
reach 1.

Exits with Quickshell (PR_SET_PDEATHSIG), and takes pw-record with it.
"""
import argparse
import ctypes
import math
import re
import shutil
import signal
import subprocess
import sys
import time
from collections import deque

import numpy as np

RATE = 48000
HOP = 256
WIN = 1024

KICK_BAND = (35.0, 130.0)
BASS_BAND = (35.0, 180.0)
MID_BAND = (180.0, 2000.0)
HIGH_BAND = (2000.0, 9000.0)
SNARE_BAND = (1500.0, 6000.0)   # the snare's wires, a clap
HAT_BAND = (7000.0, 16000.0)

ATTACK_S = 0.008
RELEASE_S = 0.110
PEAK_DECAY_S = 4.0        # the normaliser's memory
FLOOR = 0.5               # magnitudes below this are silence, not quiet music
KICK_NOISE = 2.0          # kick-band magnitude below this is leakage (a hi-hat's attack), not a kick
FLUX_S = 1.0
FLUX_K = 1.6
FLUX_FLOOR = 0.08
REFRACTORY_S = 0.140
FALLBACK_K = 2.6          # while the clock isn't locked, only a clear kick is a beat
FALLBACK_REFRACTORY_S = 0.250
KICK_DECAY_S = 0.170
FLASH_K = 2.8
FLASH_GAP_S = 0.340       # at most three flashes a second, and a margin
FLASH_DECAY_S = 0.070
KICK_GATE = 0.040         # while locked, a kick this close to the grid (s), or 12% of a beat
GATE_K = 0.8              # …and FLUX_K there is this
BAND_NOISE = 0.1          # the snare/hat bands' floor (their magnitudes run far below the kick's)
SNARE_K, SNARE_FLOOR, SNARE_REFRACTORY_S = 2.5, 0.05, 0.120
SNARE_OVER_HAT = 0.8
SNARE_OVER_KICK = 0.04
KICK_OVER_SNARE = 4.0     # a snare's body leaks into the kick band; a kick's own rise is ~70×
SNARE_DECAY_S = 0.150
HAT_K, HAT_FLOOR, HAT_REFRACTORY_S = 1.8, 0.05, 0.060
HAT_OVER_NOISE = 2.0
HAT_DECAY_S = 0.070
BOOM_K, BOOM_FLOOR, BOOM_REFRACTORY_S = 1.8, 0.05, 0.150
BOOM_HOLD_S = 0.011       # a bass rise waits this long: if a kick is called in it, it was the kick's
BOOM_AFTER_KICK_S = 0.080 # …and a kick's own rise goes on this long after it is called
BOOM_DECAY_S = 0.200
IMPACT_Q = 0.85
IMPACT_WINDOW = 48        # hits (kicks and snares), ~10–20 s of music
IMPACT_MIN_HITS = 8
IMPACT_GAP_S = 1.0
IMPACT_DECAY_S = 0.220
BOOM_LEVEL = 4.0          # kick-band RMS a bass note reaches at least (a clap's leak: ~1.3; an
                          # 808 at -20 dB: ~14)

SECTION_S = 0.300            # how big the section is: power smoothed over this
LEVEL_RANGE_DB = 15.0
SUB_RANGE_DB = 24.0
SONG_PEAK_FALL_DB_S = 0.1    # the song's loudest so far falls 6 dB a minute…
REF_LEVEL_DB = 8.0           # …never below these (this file's FFT scale): ~10 dB under the big part
REF_SUB_DB = 24.0            # of the one track measured (17 / 34), so Spotify's own volume turned
                             # down still leaves dynamics — at 17/34 a quieter playback read calm
                             # throughout and never reached a drop
HEAVY_WINDOW_S = 0.035
ACCENT_RATE = 1.2            # accents a second aimed at, at most
ACCENT_SPAN_S = 8.0
ACCENT_WINDOW = 32
ACCENT_MIN_SNARES = 4
ACCENT_GAP_S = 0.35

TEMPO_WINDOW_S = 8.0
PHASE_WINDOW_S = 6.0
WARMUP_S = 6.0             # (was 4: too little history for the comb's two-bar term below 120 BPM)
REESTIMATE_S = 0.5
BPM_MIN, BPM_MAX = 70.0, 180.0
PRIOR_BPM, PRIOR_OCTAVES = 128.0, 1.0    # (was 120 / 0.9: half time won ties against the true beat)
TEMPO_SWITCH = 1.25       # a different tempo must score this much over ours… (1.1 let a real J-core
                          # track flip to 116 — its dotted ⅔ — for 4 s)
RIVAL_A = 0.2             # …smoothed this much per estimate (REESTIMATE_S apart: ~3 s to cross)
TEMPO_NEAR = 0.10         # closer than this, a better tempo pulls ours in gradually instead
LOCK_CONTRAST = 2.5       # the folded phase must stand this far over its mean
PHASE_LAG_S = 0.016       # a kick's rise peaks this long after it starts, inside the 21 ms
                          # window (measured on test-music-pulse.py's track): the grid is
                          # moved back by it, so the beat lands on the kick, not after it
LOST_BEATS = 2.5          # this many periods without a kick onset: unlock
ODF_BANDS = 8             # log-spaced 40 Hz–8 kHz, for the tempo
ODF_WEIGHTS = (2.0, 1.8, 1.4, 1.0, 0.8, 0.7, 0.6, 0.6)


# ── The rhythm engine (RhythmModel) ────────────────────────────────────────────
LOOKAHEAD_S = 0.025          # a hit is judged on this much of its attack (under the output latency)
ONSET_BIAS_S = 0.005         # a rise is seen this long after the hit starts (measured: 6–9 ms)
Z_OPEN = {"kick": 0.8, "snare": 1.2, "hat": 1.0}
Z_HI = {"kick": 2.6, "snare": 2.5, "hat": 1.8}     # where nothing is expected
Z_LO = {"kick": 0.8, "snare": 1.4, "hat": 1.0}     # where the pattern is sure
REFRACT = {"kick": 0.140, "snare": 0.120, "hat": 0.060}
JUMP_OPEN = 4.0              # a kick candidate: an attack peak of at least this many dB…
Z_PEAK = 2.5                 # …or a flux peak this clear
ENV_DELAY_S = (65 - 1) / 2 * 16 / 48000 + 0.5 * 256 / 48000   # the envelope filter's delay, + half a hop
FOLLOW_P = 0.97              # only a kick this sure moves the grid (= LEARN_P below)…
TRACK_P = 0.97               # …or phases the beat clock
SNARE_P = 0.5                # a hit the snare model rates this high is THE snare (can ring, phases)
# The snare model (scripts/fit-rhythm.py): weights for flux z, sustain, body, air, log rise ratio.
SNARE_CLIP = ((-1.0, 8.0), (0.0, 1.5), (0.0, 10.0), (0.0, 10.0), (-4.0, 4.0))
SNARE_W = (0.8795, 10.9945, -1.0630, 0.9026, 1.2538)
SNARE_B = -12.0234
SNARE_TRACK = 0.7            # a snare this near the recent strongest phases it too…
SNARE_PEAK_DECAY = 0.98      # (that peak, per snare)
SNARE_TRACK_W = 1.0          # …at a kick's weight: the backbeat is the strongest phase cue
KODF_W = 0.5                 # the beat clock's own low-rise signal, beside them
BEAT_PRIOR = 0.5             # locked, a beat is this likely to have a kick
PRIOR_GAIN = 7.0             # log-odds per unit of expectation…
PRIOR_MID = 0.55             # …around this: an off-beat slot the pattern never plays costs 3.85 (a
                             # kick there must sound p ≥ 0.98: 808 notes scored 0.7–0.97), a beat
                             # costs 0.35, a slot the pattern is sure of gains 3.15
UNLOCKED_COST = 1.4          # before the beat clock locks: p ≥ 0.8 (a click-less 808 scored 0.64)
LEARN_P = 0.97               # only a kick this sure teaches the pattern, phases or moves the grid
# The kick model (scripts/fit-rhythm.py): weights for jump dB, flux z, click z, log rise ratio,
# and flux z × click (0..1).
KICK_CLIP = ((0.0, 15.0), (-1.0, 8.0), (-1.0, 8.0), (-2.0, 4.0))
KICK_W = (-0.0333, 0.2783, 0.2975, 0.5869, 1.1625)
KICK_B = -3.6260
CLICK_MIN = 1.5              # an unexpected kick's broadband rise over its mean (an 808 note has none)
SYNC_EXPECT = 0.3            # an off-beat kick counts where the pattern has kicks this often…
Z_SYNC = 4.0                 # …or when it is this clear (a dense track found 85 off-beat "kicks" in 42 s)
SLOT_TOL_S = 0.030           # a hit this near a 16th is on it
BEAT_A = 0.15                # per beat
PATTERN_A = 0.2              # per bar
PATTERN_MIN_BARS = 2
DOWN_HYSTERESIS = 0.15
ANCHOR_BONUS = 0.3
BACK_MIN = 0.3               # a backbeat's snare presence at least
BACK_STANDOUT = 1.3          # …and this many times the other positions'
PHASE_A = 0.15               # how far each kick near a beat pulls our grid
FOLLOW_WIN = 0.15            # (only kicks within this share of a beat of one)
KICK_SELF = 0.35             # a kick rising this share of a typical kick's rise is one, clap or not
SECTION_RISE_S, SECTION_FALL_S, SECTION_SLOW_S = 0.15, 1.5, 6.0
SECTION_FAST_S = 0.050       # the drop's own test reads the part this fast
SOUND_LEVEL = 0.02           # the section starts counting at this
DROP_JUMP = 0.3              # a drop: the part this far over the quiet before it…
DROP_MIN = 0.15              # …at least this big (low: quiet playback has drops too; the dip test filters)…
DROP_QUIET_S = 2.0           # …after this long…
DROP_DIP = 0.05              # …their mean this far under the song's long average
DROP_GAP_S = 8.0
SECTION_SCALE_MIN = 0.15     # the drop test's thresholds scale with the song's section peak, down to this
SECTION_PEAK_FALL = 0.005    # (that peak falls this much a second)
BIG_LEVEL = 0.6              # a phrase is marked only in a part this big
PHRASE_BARS = 8
ENV_DECIM = 16               # the kick-band envelope runs at 3 kHz…
ENV_TAPS = 65                # …through 65 taps (21 ms; 11 ms delay)
ENV_FLOOR = 1e-4             # its silence (−80 dB)
DEFAULT_LATENCY_S = 0.030
BT_LATENCY_S = 0.150

def estimate_latency():
    """Seconds from the player's stream (what pw-record taps) to the speakers: one graph
    quantum, plus the default sink's ALSA headroom and period; Bluetooth adds its codec's
    buffering (`BT_LATENCY_S`, a typical figure — the Sync fader covers the rest). Measured
    2026-10-31 on a USB headset: quantum 1024, headroom 256, period 256 at 48 kHz → 32 ms.
    Falls back to `DEFAULT_LATENCY_S` when PipeWire won't say."""
    import json
    try:
        meta = subprocess.run(["pw-metadata", "-n", "settings"], capture_output=True, text=True, timeout=2).stdout
        q = re.search(r"clock\.quantum' value:'(\d+)'", meta)
        r = re.search(r"clock\.rate' value:'(\d+)'", meta)
        quantum, rate = (int(q.group(1)) if q else 1024), (int(r.group(1)) if r else RATE)
        dflt = subprocess.run(["pw-metadata", "-n", "default"], capture_output=True, text=True, timeout=2).stdout
        m = re.search(r"default\.audio\.sink' value:'\{\"name\":\"([^\"]+)\"", dflt)
        sink = m.group(1) if m else ""
        lat = quantum / rate
        nodes = json.loads(subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=3).stdout or "[]")
        for o in nodes:
            props = ((o.get("info") or {}).get("props") or {})
            if props.get("node.name") == sink:
                lat += (int(props.get("api.alsa.headroom", 0)) + int(props.get("api.alsa.period-size", 0))) / rate
                if sink.startswith("bluez"):
                    lat += BT_LATENCY_S
                break
        return lat
    except Exception:
        return DEFAULT_LATENCY_S


def die_with_parent():
    """Exit when Quickshell does (bt-helper.py's note): a reload must not orphan us."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


class BeatTracker:
    """Tempo and phase from onset signals; says whether a moment is on the grid (see the
    docstring)."""

    def __init__(self, hop_s):
        self.hop_s = hop_s
        n = int(TEMPO_WINDOW_S / hop_s)
        self.odf = deque(maxlen=n)
        self.kodf = deque(maxlen=n)
        self.kev = deque(maxlen=n)     # the rhythm engine's confident kicks, as impulses
        self.t = 0.0
        self.period = 0.0
        self.pending = 0.0        # the best rival tempo
        self.rival = 1.0          # its score over ours, smoothed
        self.next = None
        self.locked = False
        self.contrast = 0.0
        self.since_est = 0.0
        self.last_onset = -1e9

    def bpm(self):
        return 60.0 / self.period if self.locked and self.period > 0 else 0.0

    def onset(self, t):
        self.last_onset = t

    def kick_event(self, t0, w, alive=True):
        """A kick the rhythm engine is sure of (2026-10-31): it phases the grid and keeps the
        lock alive. `kodf` alone (low rise × broadband click) went flat on kicks whose click sits
        under the analysis's noise floor — synthetic phonk never locked."""
        k = len(self.kev) - 1 - int(round((self.t - t0) / self.hop_s))
        if 0 <= k < len(self.kev):
            self.kev[k] += w
        if alive:                      # (a snare phases the beat but doesn't keep the lock alive:
            self.last_onset = max(self.last_onset, t0)   # a breakdown with snares and no kicks unlocks)

    def near(self, t):
        """Locked, and `t` within KICK_GATE (or 12% of a beat) of a grid point."""
        if not self.locked or self.next is None or self.period <= 0:
            return False
        d = (t - self.next) % self.period
        return min(d, self.period - d) <= max(KICK_GATE, 0.12 * self.period)

    def push(self, t, odf, kodf):
        """One hop."""
        self.odf.append(odf)
        self.kodf.append(kodf)
        self.kev.append(0.0)
        self.t = t
        self.since_est += self.hop_s
        if self.since_est >= REESTIMATE_S and len(self.odf) * self.hop_s >= WARMUP_S:
            self.since_est = 0.0
            self._estimate()
        if self.locked and self.period > 0 and t - self.last_onset > LOST_BEATS * self.period:
            self.locked = False
            self.next = None
        if self.locked and self.next is not None and t >= self.next + self.period / 2:
            self.next += self.period

    def _scores(self):
        """(lags, score) over the tempo range, lags in hops at quarter-hop steps. A lag scores by
        its whole METRE, not its own autocorrelation alone (2026-10-31): the beat, two beats, the
        bar (four), and the half beat — on a J-core track (174 BPM, dotted kicks) the bare peak sat
        at 1.5 beats (116 BPM) and the tracker flipped between 174, 116 and 87 every few seconds;
        a dotted lag has no half-beat and no bar partner, the true beat has both. On boom-bap at
        90 the bar is what beats 120 (4/3), so it weighs as much as two beats.
        FRACTIONAL lags, read off the autocorrelation by interpolation: 174 BPM is 64.66 hops, and
        an integer lag's multiples (130, 260) missed the true peaks (129.3, 258.6) by more than
        the peaks are wide — the tracker settled on 165."""
        o = np.asarray(self.odf, dtype=np.float64)
        o = o - o.mean()
        n = len(o)
        spec = np.fft.rfft(o, 2 * n)
        ac = np.fft.irfft(spec * np.conj(spec))[:n]
        ac = np.maximum(ac, 0.0)
        # Onsets are a hop wide, so their autocorrelation peaks are too; smoothed over ±2 hops a
        # multiple lands on its peak's shoulder at worst.
        ac = np.convolve(ac, np.array([0.25, 0.5, 1.0, 0.5, 0.25]) / 2.5, mode="same")
        lo = max(2.0, 60.0 / BPM_MAX / self.hop_s)
        hi = min(n / 2.0 - 2, 60.0 / BPM_MIN / self.hop_s)
        if hi <= lo:
            return None, None
        lags = np.arange(lo, hi, 0.25)
        idx = np.arange(n, dtype=np.float64)
        # A multiple counts only where the history reaches it, and the comb is renormalised by
        # what counted: at warm-up (4 s) the two-bar term had capped the lags at ~93 hops, so 90 BPM
        # (125) couldn't be the first guess — boom-bap locked on 120 and stayed there.
        at = lambda m: np.where(m * lags < n - 1, np.interp(m * lags, idx, ac), 0.0)
        have = lambda m: (m * lags < n - 1).astype(np.float64)
        bpm = 60.0 / (lags * self.hop_s)
        prior = np.exp(-0.5 * (np.log2(bpm / PRIOR_BPM) / PRIOR_OCTAVES) ** 2)
        # …and two bars: a fluke (a clap's triple burst, a bass swell) can line up with one
        # multiple, not with four (a 169 bump had beaten a 174 J-core beat with three).
        terms = ((1.0, 1.0), (0.75, 2.0), (1.0, 4.0), (0.5, 8.0), (0.5, 0.5))   # the bar weighs as much as the beat
        comb = sum(w * at(m) for w, m in terms) / sum(w * have(m) for w, m in terms) * sum(w for w, _ in terms)
        self._comb = comb                 # unweighted, for refining the winner (see _tempo)
        return lags, comb * prior

    def _tempo(self):
        lags, score = self._scores()
        if lags is None:
            return 0.0, None, None
        i = int(np.argmax(score))
        # The prior picks the peak; the peak's own top is found without it — its slope dragged a
        # 174 BPM peak to 170.
        w = slice(max(0, i - 12), min(len(score), i + 13))      # ±3 hops
        comb = self._comb[w]
        k = int(np.argmax(comb))
        L = float(lags[w][k])
        if 0 < k < len(comb) - 1:       # between quarter-hop steps, from the peak's neighbours
            a, b, c = comb[k - 1], comb[k], comb[k + 1]
            den = a - 2 * b + c
            if den != 0:
                L += 0.25 * 0.5 * (a - c) / den
        return L * self.hop_s, lags, score

    def _score_at(self, period, lags, score):
        j = int(np.argmin(np.abs(lags * self.hop_s - period)))
        return float(score[max(0, j - 1):j + 2].max())

    def _estimate(self):
        period, lags, score = self._tempo()
        if period <= 0:
            return
        if self.period <= 0:
            self.period = period
        else:
            related = lambda p: min(abs(p / self.period - r) for r in (1.0, 2.0, 0.5)) < 0.04
            near = lambda p: abs(p / self.period - 1) < TEMPO_NEAR
            if related(period) and abs(period / self.period - 1) < 0.04:
                self.period = 0.7 * self.period + 0.3 * period
            elif near(period) and self._score_at(period, lags, score) > self._score_at(self.period, lags, score):
                # Close and better: a first guess a few % off (122 for 128), pulled in.
                self.period = 0.8 * self.period + 0.2 * period
            # A different tempo replaces ours when the best of them has out-scored it by
            # TEMPO_SWITCH, smoothed over estimates (`rival`). Counting wins in a row didn't work:
            # on boom-bap the argmax alternated 90/120 and every 120 reset the count.
            cur = self._score_at(self.period, lags, score)
            sec = lags * self.hop_s
            ok = np.array([not related(p) and not near(p) for p in sec])
            if ok.any() and cur > 0:
                j = int(np.argmax(np.where(ok, score, -1.0)))
                ratio = float(score[j]) / cur
                cand = float(sec[j])
                if self.pending > 0 and abs(cand / self.pending - 1) >= 0.04:
                    self.rival = 1.0                       # a different rival: start over
                self.pending = cand
                self.rival += (ratio - self.rival) * RIVAL_A
                if self.rival >= TEMPO_SWITCH:
                    self.period, self.pending, self.rival = cand, 0.0, 1.0
                    self.locked = False                    # a new grid, phased from scratch
                    self.next = None

        # The phase: the kick band's onsets folded over the period.
        m = -int(PHASE_WINDOW_S / self.hop_s)
        k = np.asarray(self.kodf, dtype=np.float64)[m:]
        # The old click-aware low rise at half weight beside the engine's sure kicks and snares:
        # it is largest for an 808 rising out of near-silence, and on phonk (kicks on 1, 3 and the
        # "and" of 3, 808s between) it locked the grid half a beat off from the first seconds.
        k = KODF_W * k / (k.max() + 1e-9) + np.asarray(self.kev, dtype=np.float64)[m:]
        nb = max(4, int(round(self.period / self.hop_s)))
        times = self.t - (len(k) - 1 - np.arange(len(k))) * self.hop_s
        bins = ((np.mod(times, self.period) / self.period) * nb).astype(int) % nb
        acc = np.bincount(bins, weights=k, minlength=nb)
        acc = 0.25 * np.roll(acc, 1) + 0.5 * acc + 0.25 * np.roll(acc, -1)
        mean = float(acc.mean())
        self.contrast = float(acc.max()) / mean if mean > 1e-9 else 0.0
        if self.contrast < LOCK_CONTRAST or self.t - self.last_onset > LOST_BEATS * self.period:
            self.locked = False
            self.next = None
            return
        phase = (int(np.argmax(acc)) + 0.5) / nb * self.period - PHASE_LAG_S
        grid = phase + math.ceil((self.t - phase) / self.period) * self.period
        if not self.locked or self.next is None:
            self.next = grid
        else:
            # Nudge, don't jump: the grid point nearest the one already scheduled.
            near = grid + round((self.next - grid) / self.period) * self.period
            self.next += 0.5 * (near - self.next)
        self.locked = True


class Onset:
    """Spectral flux over some bins (log magnitudes) against its own ~1 s mean plus `k`
    deviations, over a floor, at most once per `refractory` s. `z` is the last hop's flux in
    deviations over the mean."""

    def __init__(self, dt, k, floor, refractory):
        self.dt, self.k, self.floor, self.refractory = dt, k, floor, refractory
        self.prev = None
        self.mean = 0.0
        self.sq = 0.0
        self.since = 1e9
        self.z = 0.0

    def step(self, lmag):
        flux = 0.0 if self.prev is None else float(np.mean(np.maximum(0.0, lmag - self.prev)))
        self.prev = lmag
        sd = math.sqrt(max(0.0, self.sq - self.mean ** 2))
        self.z = (flux - self.mean) / sd if sd > 1e-9 else 0.0
        hit = flux > self.mean + self.k * sd and flux > self.floor and self.since >= self.refractory
        a = 1.0 - math.exp(-self.dt / FLUX_S)
        self.mean += (flux - self.mean) * a
        self.sq += (flux * flux - self.sq) * a
        self.since = 0.0 if hit else self.since + self.dt
        return hit


class RhythmModel:
    """The rhythm engine (2026-10-31): decides each hit WITH the beat and the bar, not alone.

    The user, after round upon round of threshold patches: the snare ring "still quite annoying",
    the big hits "quite off rhythm and sometimes still miss some notes … I want a complex and
    reliable system". Picked: this — no new dependency — with the ring on BACKBEAT snares only and
    the big hits on SONG STRUCTURE. Built against ground truth: scripts/bench-rhythm.py scores it
    on synthetic songs whose every hit is known (scripts/synthkit.py), and its two acoustic models
    are fitted there (scripts/fit-rhythm.py). On top of the Analyzer's detectors (it reads their
    features every hop; their own immediate calls stay for the tests and the cava-less fallback):

    - Kicks are EVENTS (`_kick_peaks`): peaks of the kick band's attack — its true amplitude
      envelope (Analyzer._low_env), not the FFT's, which a sustained bass makes swing ±6 dB a hop —
      or of its flux, timed at the peak. Each is scored by a fitted logistic model of how kick-like
      it sounds (`kick_prob`: attack dB, flux z, the beater's click, the kick/snare rise ratio, and
      rise × click — an 808 note has the rise without the click), then the bar has its say as
      log-odds: a beat is likely, a slot the learned pattern plays gains, an off-beat slot it never
      plays costs (`PRIOR_*`); unlocked, the acoustics must be surer (`UNLOCKED_COST`).
    - Snares: the snare band's flux opens a candidate, judged 25 ms later on its whole attack
      (`LOOKAHEAD_S`), and a second fitted model asks whether it is THE snare or clap (`snare_prob`:
      sustain — a snare's wires ring, a tamborim is gone in 15 ms — body, air, ratio). Only that
      kind, on a backbeat, is "back" (the ring); everything else is "ghost".
    - The grid: the tracker's beat (tempo by a metre comb, phase folded from the confident kicks
      and backbeat snares this engine feeds back — `BeatTracker.kick_event`), nudged toward
      confident kicks (`phase`, `_follow`); every hit placed on a 16th of a 4/4 bar. Beat 1 is the
      beat position whose kicks and snares look like a bar's start (`_score`), anchored by drops.
    - The pattern: per slot, how often each drum has been there over the last bars — learned only
      from SURE hits, so an 808 let in once can't teach the bar to expect it.
    - Structure: a DROP is judged on its own kick (`_drop_at`): the 2 s before it quieter than the
      song usually is, and the part right now (50 ms) leaping over that — exact to the kick on every
      synthetic song, none false. Every PHRASE_BARS bars since, in a big part, beat 1 is a "phrase".
    - Every event carries its own audio time `t0`; MusicPulse shows it when the speakers play it
      (`estimate_latency`, ~32 ms on a USB headset, longer than the ~21 ms the engine waits).

    Measured (bench-rhythm.py, 2026-10-31): kicks 92–100% found at 82–100% precision on EDM, J-core
    and boom-bap at three levels, 1–7 ms timing; the old detector 2–92%. Backbeat rings 62–96% with
    no ring on a ghost. Phonk is the weak case (61–69%): its synthetic 808s out-sound its kicks.
    On a real 174 BPM J-core recording the kicks sit closer to a steady grid than the old
    detector's (median 14.5 ms off it against 22.3). Cost: ~6.7% of one core (was 3.8%).
    """

    def __init__(self, hop_s):
        self.hop_s = hop_s
        self.t = 0.0
        self.open = {}               # kind -> candidate being watched
        self.last = {"kick": -1e9, "snare": -1e9, "hat": -1e9}
        self.phase = 0.0             # our correction to the tracker's grid, s (see `place`)
        self.kbuf = deque(maxlen=7)  # the last hops' kick features, for peak-picking
        self.kick_dk = 0.0           # a typical kick's rise in the kick band (EMA)
        self.snare_peak = 0.0        # the recent strongest snare (decays per snare)
        self.events = []             # decided, waiting to be printed: (t0, kind, strength, heavy, role)
        # The grid
        self.last_next = None
        self.idx_next = 0
        self.period = 0.0
        self.down = 0                # beat-index mod 4 that is beat 1
        self.anchor = None           # beat-index mod 4 a drop put beat 1 on
        self.k4 = [0.0] * 4          # on-beat presence per beat-index mod 4
        self.s4 = [0.0] * 4
        self.beat_hits = {}          # beat index -> {"kick": s, "snare": s}
        self.done_beat = None
        # The pattern, per slot of the bar (0..15, slot 0 = beat 1)
        self.pres = {k: [0.0] * 16 for k in ("kick", "snare", "hat")}
        self.str_ = {k: [0.0] * 16 for k in ("kick", "snare", "hat")}
        self.bar_hits = {}           # bar index -> {(kind, slot): strength}
        self.done_bar = None
        self.bars_learned = 0
        # Structure
        self.section = -1.0
        self.slow = -1.0
        self.since_drop = 1e9
        self.started = None          # when sound began (the long average starts then)
        self.sec_peak = 0.0          # the song's biggest section so far (falls slowly)
        self.recent = deque()        # (t, section) over the last DROP_QUIET_S
        self.fast = 0.0
        self.phrase_ref = None       # bar index the phrases count from
        self.last_struct = -1e9

    # ── The grid ──────────────────────────────────────────────────────────────
    def _grid(self, tracker):
        if not tracker.locked or tracker.next is None or tracker.period <= 0:
            self.last_next = None
            return
        self.period = tracker.period
        if self.last_next is not None:
            self.idx_next += int(round((tracker.next - self.last_next) / tracker.period))
        self.last_next = tracker.next
        # The beat before `next` has passed: learn from it once.
        passed = self.idx_next - 1
        if self.done_beat is None or passed > self.done_beat:
            if self.done_beat is not None:
                for b in range(self.done_beat + 1, passed + 1):
                    self._learn_beat(b)
            self.done_beat = passed

    def place(self, x):
        """(beat index, 16th within the beat, distance from that 16th in s) — or None unlocked.

        On OUR grid: the tracker's, moved by `phase`, which follows the kicks near each beat
        (`_follow`). Measured on a 174 BPM track: the tracker's grid sat 30–40 ms off the kicks,
        and with 86 ms 16ths that put every beat kick in "the 16th before the beat"."""
        if self.last_next is None or self.period <= 0:
            return None
        q = self.period / 4.0
        k = (x - self.last_next - self.phase) / q
        kr = int(round(k))
        return self.idx_next + kr // 4, kr % 4, abs(k - kr) * q

    def _follow(self, t0):
        """A kick within FOLLOW_WIN of a beat pulls our grid toward it (not a quarter: boom-bap's kick
        on the "a" of 2 sits exactly a quarter from beat 2, and dragged the grid)."""
        if self.last_next is None or self.period <= 0:
            return
        k = (t0 - self.last_next - self.phase) / self.period
        d = (k - round(k)) * self.period
        if abs(d) <= FOLLOW_WIN * self.period:
            self.phase += d * PHASE_A
            lim = 0.3 * self.period
            self.phase = max(-lim, min(lim, self.phase))

    def barpos(self, beat):
        return (beat - self.down) % 4

    def bar(self, beat):
        return (beat - self.down) // 4

    def _learn_beat(self, b):
        h = self.beat_hits.pop(b, {})
        m = b % 4
        self.k4[m] += ((1.0 if "kick" in h else 0.0) - self.k4[m]) * BEAT_A
        self.s4[m] += ((1.0 if "snare" in h else 0.0) - self.s4[m]) * BEAT_A
        old = self.down
        scores = [self._score(d) for d in range(4)]
        best = max(range(4), key=lambda d: scores[d])
        if best != self.down and scores[best] > scores[self.down] + DOWN_HYSTERESIS:
            self.down = best
        if self.down != old:
            # The bar turned: so does what the slots remember.
            shift = 4 * ((self.down - old) % 4)
            for k in self.pres:
                self.pres[k] = self.pres[k][shift:] + self.pres[k][:shift]
                self.str_[k] = self.str_[k][shift:] + self.str_[k][:shift]
            self.bar_hits.clear()
            self.done_bar = None
        # A bar has ended when the next beat is a beat 1.
        if self.barpos(b + 1) == 0:
            self._learn_bar(self.bar(b))

    def _score(self, d):
        k, s = self.k4, self.s4
        sc = k[d] + 0.5 * k[(d + 2) % 4] + s[(d + 1) % 4] + s[(d + 3) % 4] - s[d] - 0.5 * s[(d + 2) % 4]
        if self.anchor is not None and d == self.anchor:
            sc += ANCHOR_BONUS
        return sc

    def _learn_bar(self, bar):
        hits = self.bar_hits.pop(bar, {})
        for kind in self.pres:
            for sl in range(16):
                v = hits.get((kind, sl))
                self.pres[kind][sl] += ((1.0 if v is not None else 0.0) - self.pres[kind][sl]) * PATTERN_A
                if v is not None:
                    self.str_[kind][sl] += (v - self.str_[kind][sl]) * PATTERN_A * 2
        self.bars_learned += 1
        for old in [b for b in self.bar_hits if b < bar - 2]:
            del self.bar_hits[old]

    def expect(self, kind, slot):
        return self.pres[kind][slot] if self.bars_learned >= PATTERN_MIN_BARS else 0.0

    def backbeats(self):
        """The bar positions whose snare is THE snare: at most two, the busiest, when they stand
        out from the others (`BACK_STANDOUT`). A track with a clap on every beat (J-core) has no
        standouts: then beats 2 and 4, where a backbeat is. Never more than two a bar — the ring
        on every beat was the user's "annoying"."""
        s = [self.s4[(bp + self.down) % 4] for bp in range(4)]
        order = sorted(range(4), key=lambda bp: -s[bp])
        if s[order[0]] < BACK_MIN:
            return {1, 3}            # not learned yet: where a backbeat almost always is
        top2 = [bp for bp in order[:2] if s[bp] >= 0.5 * s[order[0]]]
        rest = [s[bp] for bp in range(4) if bp not in top2]
        if rest and min(s[bp] for bp in top2) < BACK_STANDOUT * (sum(rest) / len(rest)):
            return {1, 3}
        return set(top2)

    # ── One hop ───────────────────────────────────────────────────────────────
    def hop(self, t, f, tracker, loud, sub, fast=None):
        """`f`: this hop's features (see Analyzer._hop). Returns nothing; decided events pile
        up in `self.events`."""
        self.t = t
        self._grid(tracker)
        self._structure(loud, sub, raw_fast=fast)
        self._kick_peaks(t, f, tracker)
        for kind, z, ok in (("snare", f["sz"], True), ("hat", f["hz"], True)):
            c = self.open.get(kind)
            if c is None and ok and z >= Z_OPEN[kind] and t - self.last[kind] >= REFRACT[kind]:
                c = self.open[kind] = {"t0": t - ONSET_BIAS_S, "z": z, "dk": 0.0, "ds": 0.0, "dh": 0.0,
                                       "click": 0.0, "heavy": 0.0, "jump": 0.0, "smax": 0.0, "slast": 0.0,
                                       "body": 0.0}
            if c is not None:
                c["z"] = max(c["z"], z)
                c["dk"] += f["dk"]; c["ds"] += f["ds"]; c["dh"] += f["dh"]
                c["click"] = max(c["click"], f["click"])
                c["heavy"] = max(c["heavy"], f["heavy"])
                c["jump"] = max(c["jump"], f["jump"])
                c["smax"] = max(c["smax"], f["srms"])
                c["body"] += f["body"]
                c["slast"] = f["srms"]
                if t >= c["t0"] + LOOKAHEAD_S:
                    del self.open[kind]
                    self._decide(kind, c, tracker)

    def _kick_peaks(self, t, f, tracker):
        """Kick candidates are EVENTS: a peak of the kick band's attack (the envelope's dB jump,
        `jump`) or of its flux (`kz`), a local maximum over ±2 hops. Timed
        at the peak — the envelope's by its filter delay — so a pre-rise never becomes the kick
        (a candidate that opened on a threshold took the first rising hop, 30–70 ms early on a
        real track). Judged with its features over the hops around it; ~21 ms after the hit, under
        the speakers' latency."""
        self.kbuf.append((t, f))
        if len(self.kbuf) < 7:
            return
        b = list(self.kbuf)
        c_t, c = b[4]                                  # the hop judged: two hops of lookahead
        js = [x[1]["jump"] for x in b[2:]]
        zs = [x[1]["kz"] for x in b]
        jpeak = c["jump"] >= JUMP_OPEN and c["jump"] >= max(js)
        zpeak = b[2][1]["kz"] >= Z_PEAK and b[2][1]["kz"] >= max(zs)   # flux leads the envelope by ~2 hops
        if not (jpeak or zpeak):
            return
        t0 = (c_t - ENV_DELAY_S) if jpeak else (b[2][0] - ONSET_BIAS_S)
        # (No "one per 50 ms" for rejected candidates: a bass swell's little peak just before a
        # kick then suppressed the kick's own — 25 of 48 kicks on the synthetic EDM. Only an
        # accepted kick starts the refractory; the ±2-hop maximum keeps candidates apart.)
        if t0 - self.last["kick"] < REFRACT["kick"]:
            return
        w = [x[1] for x in b]                          # 7 hops around it
        cand = {"t0": t0, "z": max(zs), "jump": max(x["jump"] for x in w), "click": max(x["click"] for x in w),
                "sclick": max(x["sz"] for x in w),
                "dk": sum(x["dk"] for x in w), "ds": sum(x["ds"] for x in w), "dh": sum(x["dh"] for x in w),
                "heavy": max(x["heavy"] for x in w)}
        self._decide("kick", cand, tracker)

    @staticmethod
    def kick_features(c):
        """The kick model's inputs, each clipped to KICK_CLIP: attack jump (dB), flux z, the
        beater's click (the 1.5–6 kHz band's flux z — level-normalised: the broadband `click`
        subtracts an absolute floor a real but modest click never clears, and read 0 on most
        kicks; an 808 note has none, which is what tells it from a kick), log of the kick band's
        rise over the snare band's."""
        raw = (c["jump"], c["z"], c.get("sclick", 0.0), math.log((c["dk"] + 1.0) / (c["ds"] + 1.0)))
        f = [min(hi, max(lo, v)) for v, (lo, hi) in zip(raw, KICK_CLIP)]
        # A big rise WITH a beater: an 808 note has the rise and not the click (click z ~1 against
        # a kick's ~3), and a linear model over the two separately let 808s through at p 0.95.
        f.append(max(0.0, f[1]) * min(4.0, max(0.0, f[2])) / 4.0)
        return f

    @staticmethod
    def snare_features(c):
        """The snare model's inputs, clipped to SNARE_CLIP: snare-band flux z, sustain (the band
        25 ms in against its peak), body (the 150–550 Hz rise, summed over the window), air (the
        >7 kHz rise), log of the snare band's rise over the kick band's."""
        raw = (c["z"], c["slast"] / max(c["smax"], 1e-9), c.get("body", 0.0), c["dh"],
               math.log((c["ds"] + 0.1) / (c["dk"] + 0.1)))
        return [min(hi, max(lo, v)) for v, (lo, hi) in zip(raw, SNARE_CLIP)]

    def snare_prob(self, c):
        """How much this sounds like THE snare (or clap) of a groove, 0..1 — not a tamborim, a
        rimshot, a cowbell: a logistic model (SNARE_W, scripts/fit-rhythm.py). On funk the
        percussion is louder in the snare band than the snare, so the band's flux alone ranked
        them the wrong way round."""
        logit = SNARE_B + sum(w * v for w, v in zip(SNARE_W, self.snare_features(c)))
        return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, logit))))

    def kick_prob(self, c):
        """How kick-like this event sounds, 0..1, from its acoustics alone: a logistic model
        (KICK_W, fitted by scripts/fit-rhythm.py on synthetic songs with known kicks)."""
        logit = KICK_B + sum(w * v for w, v in zip(KICK_W, self.kick_features(c)))
        return 1.0 / (1.0 + math.exp(-max(-30.0, min(30.0, logit))))

    def _decide(self, kind, c, tracker):
        p_ac = self.kick_prob(c) if kind == "kick" else 0.0
        if kind == "kick" and p_ac >= FOLLOW_P:
            self._follow(c["t0"])          # before placing it: the grid follows confident kicks only
        at = self.place(c["t0"])
        slot, role_beat, beat = None, False, None
        if at is not None:
            beat, sub, dev = at
            if dev <= max(SLOT_TOL_S, 0.2 * self.period / 4):
                slot = self.barpos(beat) * 4 + sub
                role_beat = sub == 0
        e = self.expect(kind, slot) if slot is not None else 0.0
        if kind == "kick":
            # Acoustics and rhythm, as log-odds: how kick-like it sounds, plus what the bar says —
            # an expected slot (the learned pattern, or any beat while locked) lowers the bar, an
            # off-beat slot the pattern never plays raises it.
            logit = math.log(max(p_ac, 1e-6) / max(1 - p_ac, 1e-6))
            if at is not None:
                e = max(e, BEAT_PRIOR if role_beat else 0.0)
                logit += PRIOR_GAIN * (e - PRIOR_MID)
            else:
                logit -= UNLOCKED_COST          # no bar to lean on: the acoustics must be surer
            if logit < 0:
                return False
            role = "off" if not role_beat else ("down" if self.barpos(beat) == 0 else "beat")
        elif kind == "snare":
            # Two questions: is it a snare-ish hit at all (the band's flux, as before — ghosts
            # count, for the bar's rim), and is it THE snare (`snare_prob`: sustain, body, air…).
            p_sn = self.snare_prob(c)
            c["sustained"] = p_sn >= SNARE_P
            need = Z_HI["snare"] - (Z_HI["snare"] - Z_LO["snare"]) * e
            if not c["sustained"] and (c["ds"] < SNARE_OVER_HAT * c["dh"] or c["ds"] < SNARE_OVER_KICK * c["dk"]
                                       or c["z"] < need):
                return False
            strength = max(self._strength(c["z"]), p_sn if c["sustained"] else 0.0)
            back = c["sustained"] and role_beat and self.barpos(beat) in self.backbeats()
            role = "back" if back else "ghost"
        else:
            need = Z_HI["hat"] - (Z_HI["hat"] - Z_LO["hat"]) * e
            if c["dh"] < HAT_OVER_NOISE * c["ds"] or c["z"] < need or self.t - self.last["snare"] < 0.03:
                return False
            role = "hat"
        strength = self._strength(c["z"])
        self.last[kind] = c["t0"] + ONSET_BIAS_S
        # The pattern learns from sure hits only: an 808 let in at p 0.9 mustn't teach the bar that
        # kicks live on its 16th, and then be let in for being expected.
        if beat is not None and (kind != "kick" or p_ac >= LEARN_P) and (kind != "snare" or c["sustained"]):
            if slot is not None:
                self.bar_hits.setdefault(self.bar(beat), {})[(kind, slot)] = strength
            if role_beat and kind in ("kick", "snare"):
                self.beat_hits.setdefault(beat, {})[kind] = strength
        self.events.append((c["t0"], kind, strength, c["heavy"] if kind == "kick" else 0.0, role))
        if kind == "kick" and p_ac >= TRACK_P:
            tracker.kick_event(c["t0"] + PHASE_LAG_S, p_ac)   # (the fold expects a rise's peak, not its start)
        if kind == "snare" and c["sustained"]:
            self.snare_peak = max(strength, self.snare_peak * SNARE_PEAK_DECAY)
        if kind == "snare" and c["sustained"] and strength >= SNARE_TRACK * self.snare_peak:
            # The snares phase the beat too: a groove whose kicks are syncopated (phonk: 1, 3 and
            # the "and" of 3, 808s between) fits a half-beat-shifted grid as well as the true one
            # by its kicks alone; the backbeat snares settle it. Only the strong ones (near the
            # recent peak): six tamborim ghosts a bar outvoted two backbeat snares.
            tracker.kick_event(c["t0"] + PHASE_LAG_S, SNARE_TRACK_W * strength, alive=False)
        if kind == "kick":
            self._kick_struct(c["t0"], role, beat)
        return True

    @staticmethod
    def _strength(z):
        return min(1.0, max(0.05, (z - 0.5) / 4.0))

    # ── Structure ─────────────────────────────────────────────────────────────
    def _structure(self, loud, sub, raw_fast=None):
        d = self.hop_s
        raw = 0.5 * loud + 0.5 * sub
        self.fast = raw if raw_fast is None else raw_fast
        if self.started is None:
            if raw < SOUND_LEVEL:
                return                      # nothing playing yet: the long average starts with the sound
            self.started = self.t
            self.section = self.slow = raw
        tau = SECTION_RISE_S if raw > self.section else SECTION_FALL_S
        self.section += (raw - self.section) * (1 - math.exp(-d / tau))
        self.slow += (raw - self.slow) * (1 - math.exp(-d / SECTION_SLOW_S))
        self.since_drop += d
        self.sec_peak = max(self.section, self.sec_peak - SECTION_PEAK_FALL * d)
        self.recent.append((self.t, self.section))
        while self.recent and self.recent[0][0] < self.t - DROP_QUIET_S:
            self.recent.popleft()

    def _drop_at(self, t0):
        """Is THIS kick a drop? The DROP_QUIET_S before it QUIETER than the song usually is (their
        mean under the long average by DROP_DIP — a breakdown, a build; not a steady groove, not
        a bar's own 808 swelling: either of those called a drop every 8 s) and the part as it is
        right now (`fast`, 50 ms) leaping DROP_JUMP over that quiet, and at least DROP_GAP_S since
        the last. Judged on the kick itself, so the drop lands on its hit: waiting for the smoothed
        section, or for a beat 1, put it 0.2–2 s late."""
        if self.started is None or self.t - self.started < SECTION_SLOW_S or self.since_drop < DROP_GAP_S:
            return False
        before = [sv for tv, sv in self.recent if tv < t0 - 0.05]
        if not before:
            return False
        quiet = sum(before) / len(before)
        # In the song's own range: quiet playback compresses the whole section (0–0.35 at −18 dB),
        # and absolute thresholds never saw a drop there.
        scale = max(SECTION_SCALE_MIN, self.sec_peak)
        return (quiet <= self.slow - DROP_DIP * scale and self.fast - quiet >= DROP_JUMP * scale
                and self.fast >= DROP_MIN * scale)

    def _kick_struct(self, t0, role, beat):
        if self._drop_at(t0):
            self.since_drop = 0.0
            if beat is not None:
                # Drops land on beat 1: the bar is re-anchored here.
                self.anchor = beat % 4
                if self.down != self.anchor:
                    self.down = self.anchor
                    self.bar_hits.clear()
                    self.done_bar = None
                self.phrase_ref = self.bar(beat)
            self.last_struct = t0
            self.events.append((t0, "drop", 1.0, 0.0, "struct"))
            return
        if role == "down" and beat is not None:
            b = self.bar(beat)
            if self.phrase_ref is None:
                self.phrase_ref = b
            elif b != self.phrase_ref and (b - self.phrase_ref) % PHRASE_BARS == 0 and self.section >= BIG_LEVEL \
                    and t0 - self.last_struct >= 4 * 4 * self.period:
                self.last_struct = t0
                self.events.append((t0, "phrase", 1.0, 0.0, "struct"))


class Analyzer:
    """The analysis, pure: feed() samples (float32 mono, -1..1), get a state per hop."""

    def __init__(self, rate=RATE, hop=HOP, win=WIN):
        self.np = np
        self.rate, self.hop, self.win = rate, hop, win
        self.dt = hop / rate
        self.window = np.hanning(win).astype(np.float32)
        self.buf = np.zeros(win, dtype=np.float32)
        self.pending = np.zeros(0, dtype=np.float32)
        f = np.fft.rfftfreq(win, 1.0 / rate)
        band = lambda lo, hi: (f >= lo) & (f <= hi)
        self.kick_mask = band(*KICK_BAND)
        edges = np.geomspace(40.0, 8000.0, ODF_BANDS + 1)
        self.odf_masks = []
        for i in range(ODF_BANDS):
            m = band(edges[i], edges[i + 1] - 1e-6)
            if not m.any():                                    # a band narrower than one bin
                m = np.abs(f - edges[i]) == np.min(np.abs(f - edges[i]))
            self.odf_masks.append(m)
        self.odf_w = np.asarray(ODF_WEIGHTS)
        self.odf_prev = None
        self.low_prev = 0.0
        self.broad_mean = 0.0
        self.since_fallback = 1e9
        self.tracker = BeatTracker(hop / rate)
        self.rhythm = RhythmModel(hop / rate)
        self.snare_mask = band(*SNARE_BAND)
        self.hat_mask = band(*HAT_BAND)
        self.snare_on = Onset(self.dt, SNARE_K, SNARE_FLOOR, SNARE_REFRACTORY_S)
        self.hat_on = Onset(self.dt, HAT_K, HAT_FLOOR, HAT_REFRACTORY_S)
        self.band_peak = {"snare": FLOOR, "hat": FLOOR}
        self.rms_hist = deque(maxlen=3)   # (kick, snare, hat) band RMS, the last three hops
        self.low_db = deque(maxlen=3)     # the kick band's envelope in dB, the last three hops
        # The quadrature pair for that envelope: 35–150 Hz at RATE / ENV_DECIM, ENV_TAPS long.
        fs = rate / ENV_DECIM
        n = np.arange(ENV_TAPS) - (ENV_TAPS - 1) / 2
        h = (2 * 150.0 / fs) * np.sinc(2 * 150.0 / fs * n) - (2 * 35.0 / fs) * np.sinc(2 * 35.0 / fs * n)
        h *= np.hanning(ENV_TAPS)
        h /= np.max(np.abs(np.fft.rfft(h, 4096)))
        H = np.fft.fft(h, 4096)
        hq = np.real(np.fft.ifft(H * (-1j * np.sign(np.fft.fftfreq(4096)))))
        self.env_h = h
        self.env_hq = np.concatenate([hq[-(ENV_TAPS // 2):], hq[:ENV_TAPS - ENV_TAPS // 2]])
        self.env_buf = np.zeros(ENV_TAPS - 1)
        self.snare = 0.0
        self.snares = 0
        self.hat = 0.0
        self.boom_on = Onset(self.dt, BOOM_K, BOOM_FLOOR, BOOM_REFRACTORY_S)
        self.boom_at = None       # a bass rise waiting out BOOM_HOLD_S
        self.since_kick = 1e9
        self.boom = 0.0
        self.booms = 0
        self.hit_z = deque(maxlen=IMPACT_WINDOW)
        self.since_impact = 1e9
        self.impact = 0.0
        self.impacts = 0
        self.masks = {"bass": band(*BASS_BAND), "mid": band(*MID_BAND), "high": band(*HIGH_BAND),
                      "level": band(BASS_BAND[0], HIGH_BAND[1])}
        # Every band is a contiguous run of bins, so its RMS comes off one cumulative sum
        # of the power spectrum per hop (_hop's `cs`) instead of a numpy mean per band —
        # about 19 tiny reductions a hop, which were most of the helper's CPU (measured:
        # 0.31 ms/hop, numpy call overhead, not maths). (lo, hi) bin ranges, hi exclusive.
        def rng(m):
            idx = np.flatnonzero(m)
            if idx.size == 0:
                return (0, 0)
            assert idx[-1] - idx[0] + 1 == idx.size, "a band mask is not contiguous"
            return (int(idx[0]), int(idx[-1]) + 1)
        self.mask_rng = {k: rng(m) for k, m in self.masks.items()}
        self.kick_rng = rng(self.kick_mask)
        self.band_rng = {"snare": rng(self.snare_mask), "hat": rng(self.hat_mask)}
        self.odf_lo = np.array([rng(m)[0] for m in self.odf_masks])
        self.odf_hi = np.array([rng(m)[1] for m in self.odf_masks])
        self.cs = None
        self.peak = {k: FLOOR for k in self.masks}
        self.env = {k: 0.0 for k in self.masks}
        self.prev = None
        self.flux_mean = 0.0
        self.flux_sq = 0.0
        self.since = 1e9
        self.since_flash = 1e9
        self.kick = 0.0
        self.flash = 0.0
        self.beats = 0
        self.t = 0.0              # seconds of audio analysed
        self.raw = {k: 0.0 for k in self.masks}
        self.loud_pow = 0.0
        self.sub_pow = 0.0
        self.loud_fpow = 0.0
        self.sub_fpow = 0.0
        self.fast = 0.0
        self.loud_peak = REF_LEVEL_DB
        self.sub_peak = REF_SUB_DB
        self.loud = 0.0
        self.sub = 0.0
        self.heavy = 0.0
        self.heavy_new = 0.0
        self.heavy_until = -1.0
        self.snare_times = deque()
        self.snare_zs = deque(maxlen=ACCENT_WINDOW)
        self.accents = 0
        self.since_accent = 1e9

    def _a(self, tau):
        return 1.0 - math.exp(-self.dt / tau)

    def _hop(self, chunk):
        np = self.np
        self.buf = np.concatenate((self.buf[len(chunk):], chunk))
        self.t += self.dt
        spec = np.abs(np.fft.rfft(self.buf * self.window))
        cs = np.concatenate(([0.0], np.cumsum(spec.astype(np.float64) ** 2)))
        self.cs = cs

        for k, m in self.masks.items():
            e = self._rms(self.mask_rng[k])
            self.raw[k] = e
            self.peak[k] = max(e, self.peak[k] * math.exp(-self.dt / PEAK_DECAY_S), FLOOR)
            x = 0.0 if e < FLOOR else min(1.0, e / self.peak[k])
            tau = ATTACK_S if x > self.env[k] else RELEASE_S
            self.env[k] += (x - self.env[k]) * self._a(tau)

        self.since += self.dt
        self.since_flash += self.dt
        self.kick *= math.exp(-self.dt / KICK_DECAY_S)
        self.flash *= math.exp(-self.dt / FLASH_DECAY_S)
        self.snare *= math.exp(-self.dt / SNARE_DECAY_S)
        self.hat *= math.exp(-self.dt / HAT_DECAY_S)
        self.boom *= math.exp(-self.dt / BOOM_DECAY_S)
        self.impact *= math.exp(-self.dt / IMPACT_DECAY_S)
        self.since_impact += self.dt
        self.since_kick += self.dt

        # Flux over the kick band, log-compressed against the bass's own peak, above a noise
        # floor: a hi-hat's sharp attack leaks a little into every bin, and with no bass
        # playing the normaliser would magnify that leak into a "beat". A real kick there is
        # tens to hundreds; the leak is under one.
        k = np.maximum(0.0, spec[self.kick_mask] - KICK_NOISE)
        lk = np.log1p(10.0 * k / max(self.peak["bass"], KICK_NOISE))
        flux = 0.0 if self.prev is None else float(np.sum(np.maximum(0.0, lk - self.prev)))
        self.prev = lk
        sd = math.sqrt(max(0.0, self.flux_sq - self.flux_mean ** 2))
        # Where the locked clock expects a kick, a smaller rise is one: an 808 still ringing
        # from the off-beat hides most of the next kick's (measured: found up to 28 ms late).
        k_sd = GATE_K if self.tracker.near(self.t) else FLUX_K
        kz = (flux - self.flux_mean) / sd if sd > 1e-9 else 0.0     # for the rhythm engine
        onset = flux > self.flux_mean + k_sd * sd and flux > FLUX_FLOOR and self.since >= REFRACTORY_S
        strong = onset and flux > self.flux_mean + FLASH_K * sd
        a = self._a(FLUX_S)
        self.flux_mean += (flux - self.flux_mean) * a
        self.flux_sq += (flux * flux - self.flux_sq) * a

        # The tempo's onset signal: weighted flux over log-spaced bands, all of the spectrum.
        e = np.sqrt((cs[self.odf_hi] - cs[self.odf_lo]) / (self.odf_hi - self.odf_lo))
        le = np.log1p(10.0 * np.maximum(0.0, e - KICK_NOISE) / max(self.peak["level"], KICK_NOISE))
        rises = np.zeros(ODF_BANDS) if self.odf_prev is None else np.maximum(0.0, le - self.odf_prev)
        self.odf_prev = le
        odf = float(np.sum(self.odf_w * rises))

        # The PHASE's signal: a kick, not just a low note. A kick's beater clicks across the
        # whole spectrum as its thump starts; an 808 note is low only (and glides between
        # bins, so it's measured on the band's ENERGY, which a glide doesn't raise), a hi-hat
        # high only. So the low band's energy rise counts in proportion to the broadband rise
        # beside it (bands 4–6, ~570 Hz–4 kHz, against their own recent mean — not the top
        # band: a hi-hat reaches into it, and off-beat hats over off-beat 808s locked the
        # grid onto the 808s).
        low_e = float(cs[self.kick_rng[1]] - cs[self.kick_rng[0]])
        low_l = math.log1p(10.0 * max(0.0, math.sqrt(low_e) - KICK_NOISE) / max(self.peak["bass"], KICK_NOISE))
        low_rise = max(0.0, low_l - self.low_prev)
        self.low_prev = low_l
        broad = float(np.sum(rises[4:7]))
        self.broad_mean += (broad - self.broad_mean) * self._a(FLUX_S)
        kodf = low_rise * min(3.0, broad / max(self.broad_mean, 1e-3))

        # Each band's rise over the last two hops says which drum a flux onset was (see "The
        # drums"): a kick's is the kick band's, many times the snare band's.
        rms = (math.sqrt(low_e / max(1, int(self.kick_mask.sum()))),
               self._band_rms(spec, self.snare_mask, "snare"), self._band_rms(spec, self.hat_mask, "hat"))
        self.rms_hist.append(rms)
        d_kick, d_snare, d_hat = (max(0.0, rms[i] - self.rms_hist[0][i]) for i in range(3))
        onset = onset and d_kick >= KICK_OVER_SNARE * d_snare
        # Only a kick that is CALLED starts the refractory (2026-10-31, `self.since` in `kicked`
        # below). It used to start on any flux onset, before the test above and before the
        # gate: on funk, a clap landing with the kick rises a hop early and fails the test, or
        # (unlocked) the first rising hop is an onset but not a clear one — and the kick's own
        # peak a hop or two later fell in the refractory. Measured on a 128 BPM funk track: 15
        # of ~64 kicks lost in 30 s, strong ones (z 5–6.6), on the grid. EXCEPT while unlocked:
        # there the gate can't tell an 808 from a kick, and an 808's slow rise is an onset a hop
        # or two before it is a clear one — the old refractory is what kept those out (the
        # synthetic kit's off-beat 808s came back as beats without it). The price: a few kicks
        # in the seconds before the clock locks.
        if onset:
            self.tracker.onset(self.t)
            if not self.tracker.locked:
                self.since = 0.0

        # A kick, heard: on the grid while locked, else a clear one only. Never the grid alone.
        self.tracker.push(self.t, odf, kodf)
        clear = onset and flux > self.flux_mean + FALLBACK_K * sd and self.since_fallback >= FALLBACK_REFRACTORY_S
        self.since_fallback += self.dt
        if clear:
            self.since_fallback = 0.0
        kicked = (self.tracker.locked and onset and self.tracker.near(self.t)) or (not self.tracker.locked and clear)
        if kicked:
            self.since = 0.0
            self.kick = 1.0
            self.beats += 1
            self.since_kick = 0.0
            self.boom_at = None
        else:
            strong = False

        # How big this part is (see the header): not renormalised, against the song's loudest.
        a = self._a(SECTION_S)
        self.loud_pow += (self.raw["level"] ** 2 - self.loud_pow) * a
        self.sub_pow += (rms[0] ** 2 - self.sub_pow) * a
        af = self._a(SECTION_FAST_S)
        self.loud_fpow += (self.raw["level"] ** 2 - self.loud_fpow) * af
        self.sub_fpow += (rms[0] ** 2 - self.sub_fpow) * af
        ldb = 10.0 * math.log10(max(self.loud_pow, 1e-12))
        sdb = 10.0 * math.log10(max(self.sub_pow, 1e-12))
        fall = SONG_PEAK_FALL_DB_S * self.dt
        self.loud_peak = max(ldb, REF_LEVEL_DB, self.loud_peak - fall)
        self.sub_peak = max(sdb, REF_SUB_DB, self.sub_peak - fall)
        self.loud = min(1.0, max(0.0, 1.0 + (ldb - self.loud_peak) / LEVEL_RANGE_DB))
        self.sub = min(1.0, max(0.0, 1.0 + (sdb - self.sub_peak) / SUB_RANGE_DB))
        lf = 10.0 * math.log10(max(self.loud_fpow, 1e-12))
        sf = 10.0 * math.log10(max(self.sub_fpow, 1e-12))
        self.fast = 0.5 * min(1.0, max(0.0, 1.0 + (lf - self.loud_peak) / LEVEL_RANGE_DB)) \
            + 0.5 * min(1.0, max(0.0, 1.0 + (sf - self.sub_peak) / SUB_RANGE_DB))
        if kicked:
            self.heavy_new = 0.0
            self.heavy_until = self.t + HEAVY_WINDOW_S
        inst = 20.0 * math.log10(max(rms[0], 1e-6))
        inst_rel = min(1.0, max(0.0, 1.0 + (inst - self.sub_peak) / SUB_RANGE_DB))
        # The kick band's ATTACK: its amplitude envelope's dB rise over two hops (~11 ms). A kick
        # jumps; a sidechained bass swelling back, or an 808 sliding in, climbs a little per hop.
        # Not from the FFT above: a 40–60 Hz bass in a 21 ms window has its two frequency lobes
        # overlapping, so its measured energy swings ±6 dB hop to hop with its phase (seen on a
        # real track: 38/19/37 dB on alternate hops) — every bass note looked like a run of
        # kicks. `_low_env` is the band's true envelope (decimated, band-pass + its Hilbert pair).
        self.low_db.append(self._low_env(chunk))
        jump = self.low_db[-1] - self.low_db[0] if len(self.low_db) == 3 else 0.0
        if self.heavy_until >= 0:
            self.heavy_new = max(self.heavy_new, inst_rel)
            if self.t >= self.heavy_until:
                self.heavy = self.heavy_new
                self.heavy_until = -1.0

        # A bass note: the kick band's ENERGY rising (an 808 gliding between bins doesn't raise
        # it, where per-bin flux fired on every glide), not a snare's body leaking down, and
        # not a kick — not one called in the next BOOM_HOLD_S, nor the tail of one just called.
        if self.boom_on.step(np.array([low_l])) and not kicked and d_kick >= KICK_OVER_SNARE * d_snare \
                and rms[0] >= BOOM_LEVEL and self.since_kick >= BOOM_AFTER_KICK_S and self.boom_at is None:
            self.boom_at = self.t
        if self.boom_at is not None and self.t - self.boom_at >= BOOM_HOLD_S - 1e-9:
            self.boom_at = None
            self.boom = 1.0
            self.booms += 1

        # The snare and the hat.
        s_hit = self.snare_on.step(self._band_log(spec, self.snare_mask, "snare"))
        h_hit = self.hat_on.step(self._band_log(spec, self.hat_mask, "hat"))
        snare = s_hit and d_snare >= SNARE_OVER_HAT * d_hat and d_snare >= SNARE_OVER_KICK * d_kick
        self.since_accent += self.dt
        if snare:
            self.snare = 1.0
            self.snares += 1
            strong = strong or self.snare_on.z >= FLASH_K
            # An accent (see the header): among the strongest, for how busy the snares are.
            self.snare_times.append(self.t)
            while self.snare_times and self.snare_times[0] < self.t - ACCENT_SPAN_S:
                self.snare_times.popleft()
            rate = len(self.snare_times) / max(1.0, min(ACCENT_SPAN_S, self.t))
            q = 1.0 - ACCENT_RATE / max(rate, 1e-9)
            z = self.snare_on.z
            strongest = len(self.snare_zs) < ACCENT_MIN_SNARES or q <= 0.0 \
                or z >= float(np.quantile(self.snare_zs, q))
            if strongest and self.since_accent >= ACCENT_GAP_S:
                self.accents += 1
                self.since_accent = 0.0
            self.snare_zs.append(z)
        if h_hit and not snare and d_hat >= HAT_OVER_NOISE * d_snare:
            self.hat = 1.0

        if strong and self.since_flash >= FLASH_GAP_S:
            self.flash = 1.0
            self.since_flash = 0.0

        # The rhythm engine: the same features, judged with the bar (RhythmModel).
        self.rhythm.hop(self.t, {"kz": kz, "kflux": flux, "sz": self.snare_on.z, "hz": self.hat_on.z,
                                 "dk": d_kick, "ds": d_snare, "dh": d_hat,
                                 "click": broad / max(self.broad_mean, 1e-3), "heavy": inst_rel, "jump": jump,
                                 "srms": rms[1], "body": float(rises[3] + rises[4])},
                        self.tracker, self.loud, self.sub, self.fast)

        # The hardest hit: how hard against the hits before it, not a fixed bar, so it is rare
        # on a quiet track and a loud one alike.
        if kicked or snare:
            z = max((flux - self.flux_mean) / sd if kicked and sd > 1e-9 else 0.0,
                    self.snare_on.z if snare else 0.0)
            if len(self.hit_z) >= IMPACT_MIN_HITS and self.since_impact >= IMPACT_GAP_S \
                    and z >= float(np.quantile(self.hit_z, IMPACT_Q)):
                self.impact = 1.0
                self.impacts += 1
                self.since_impact = 0.0
            self.hit_z.append(z)

    def _low_env(self, chunk):
        """The kick band's amplitude envelope over this hop, in dB (floored at its noise). Delayed
        by the filter's half length (ENV_TAPS / 2 at RATE / ENV_DECIM: ~11 ms) — inside the rhythm
        engine's lookahead, which is where it is read."""
        d = chunk[: len(chunk) // ENV_DECIM * ENV_DECIM].reshape(-1, ENV_DECIM).mean(axis=1)
        seg = self.np.concatenate((self.env_buf, d))
        self.env_buf = seg[-(ENV_TAPS - 1):]
        i = self.np.convolve(seg, self.env_h, mode="valid")
        q = self.np.convolve(seg, self.env_hq, mode="valid")
        amp = float(self.np.mean(self.np.sqrt(i * i + q * q)))
        return 20.0 * math.log10(max(amp, ENV_FLOOR))

    def _rms(self, r):
        lo, hi = r
        return math.sqrt(max(0.0, self.cs[hi] - self.cs[lo]) / (hi - lo)) if hi > lo else 0.0

    def _band_rms(self, spec, mask, key):
        e = self._rms(self.band_rng[key])
        self.band_peak[key] = max(e, self.band_peak[key] * math.exp(-self.dt / PEAK_DECAY_S), BAND_NOISE)
        return e

    def _band_log(self, spec, mask, key):
        return np.log1p(10.0 * np.maximum(0.0, spec[mask] - BAND_NOISE) / self.band_peak[key])

    def state(self):
        e = self.env
        return (e["level"], e["bass"], e["mid"], e["high"], self.kick, self.beats, self.flash,
                self.tracker.bpm(), 1 if self.tracker.locked else 0, self.snare, self.snares, self.hat,
                self.boom, self.booms, self.impact, self.impacts, self.loud, self.sub, self.heavy,
                self.accents)

    def line(self):
        """The state line the shell reads (2026-10-31, the rhythm engine): `s`, the audio time,
        then level bass mid high loud sub section bpm locked barpos (the position in the bar,
        0..4, at that time; -1 unlocked)."""
        r = self.rhythm
        at = r.place(self.t)
        bp = -1.0
        if at is not None and r.period > 0:
            beat, sub, _ = at
            k = (self.t - r.last_next - r.phase) / r.period
            bp = (r.barpos(r.idx_next) + k) % 4.0
        e = self.env
        return "s %.4f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.1f %d %.3f" % (
            self.t, e["level"], e["bass"], e["mid"], e["high"], self.loud, self.sub,
            max(0.0, r.section), self.tracker.bpm(), 1 if self.tracker.locked else 0, bp)

    def take_events(self):
        """Decided events since the last call, as lines: `e`, the hit's audio time, kind
        (kick snare hat drop return phrase), strength, heavy, role."""
        out = ["e %.4f %s %.3f %.3f %s" % ev for ev in self.rhythm.events]
        self.rhythm.events = []
        return out

    def feed(self, samples):
        """Analyse what arrived; returns [(t, state), …], one per completed hop."""
        np = self.np
        self.pending = np.concatenate((self.pending, samples))
        out = []
        while len(self.pending) >= self.hop:
            chunk, self.pending = self.pending[:self.hop], self.pending[self.hop:]
            self._hop(chunk)
            out.append((self.t, self.state()))
        return out


def fmt(s):
    return "%.3f %.3f %.3f %.3f %.3f %d %.3f %.1f %d %.3f %d %.3f %.3f %d %.3f %d %.3f %.3f %.3f %d" % s


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--target", default="", help="PipeWire node to listen to (default: the default output)")
    ap.add_argument("--offset-ms", type=int, default=0,
                    help="hold every line back this long, for speakers slower than the screen")
    ap.add_argument("--every", type=int, default=2, help="print one line per this many hops")
    a = ap.parse_args(argv)

    exe = shutil.which("pw-record")
    if not exe:
        print("error pw-record is not installed (it ships with pipewire)", flush=True)
        return 2

    die_with_parent()
    cmd = [exe, "--raw", "--rate", str(RATE), "--channels", "1", "--format", "f32", "--latency", str(HOP)]
    if a.target:
        cmd += ["--target", a.target]
    cmd.append("-")
    try:
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                preexec_fn=die_with_parent)
    except OSError as e:
        print("error could not start pw-record: " + str(e), flush=True)
        return 2

    def stop(*_):
        proc.terminate()
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    an = Analyzer()
    held = deque()
    delay = max(0, a.offset_ms) / 1000.0
    n = 0
    rest = b""
    # How long after we hear it the speakers play it: the shell shows each event then.
    print("latency %d" % round(1000 * estimate_latency()), flush=True)
    try:
        while True:
            data = proc.stdout.read1(HOP * 4) if hasattr(proc.stdout, "read1") else proc.stdout.read(HOP * 4)
            if not data:
                break
            # A read can end mid-sample; the tail waits for the next one, or every later
            # float would be read out of step.
            data = rest + data
            usable = len(data) - len(data) % 4
            rest = data[usable:]
            now = time.monotonic()
            for _ in an.feed(np.frombuffer(data[:usable], dtype=np.float32)):
                n += 1
                if n % max(1, a.every) == 0:
                    held.append((now + delay, an.line()))
                for ev in an.take_events():
                    held.append((now + delay, ev))
            while held and held[0][0] <= time.monotonic():
                sys.stdout.write(held.popleft()[1] + "\n")
            sys.stdout.flush()
    except BrokenPipeError:
        pass
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
    return 0


if __name__ == "__main__":
    sys.exit(main())
