#!/usr/bin/env python3
"""Synthesise the shell's sound effects into a directory of 16-bit mono WAVs.

    python3 scripts/gen-sfx.py <out-dir>        # write (skips when nothing changed)
    python3 scripts/gen-sfx.py <out-dir> --force

Stdlib only. Nothing here is a recording: every sound is noise and sine maths, so the
repo ships no third-party audio and has no licence to carry. The output is
deterministic (a fixed seed per sound), which is what lets test-gen-sfx.py pin it.

── What each family is ───────────────────────────────────────────────────────
  key1..key4, keyspace, keyenter, keyback   a mechanical key: a bright actuation click,
                                            then the bottom-out clack over the case's low
                                            resonance (modal synthesis). Four variants so a
                                            run of letters doesn't machine-gun one sample.
  open, close                               a swoosh: noise through a band-pass that sweeps
                                            up (open) or down (close) — air going past.
  on, off                                   a rising / falling pair of sine blips.
  notify                                    two soft bell partials.
  tick                                      one tiny blip, for a stepped control.
  timer                                     a marimba roll (wooden mallet notes): a countdown ended.
  alarm                                     a radar/sonar ping, swelling, twice: an alarm.
  shutter                                   two clicks, a screenshot taken.
  clipsaved                                 two plucked-string notes (Karplus-Strong): a clip
                                            was saved. Deliberately NOT a bell — `notify` is
                                            one, and a saved clip chimed like a notification.

Levels are normalised per sound to a peak, and the shell's own volume (Sfx) scales
from there, so "typing quieter than a swoosh" is a property of this file, not of the
player.
"""
import hashlib
import math
import os
import random
import struct
import sys
import wave

RATE = 44100


def _env_sine(n):
    """0→1→0 over n samples, a raised sine: no click at either end."""
    return [math.sin(math.pi * i / max(1, n - 1)) ** 2 for i in range(n)]


def _norm(samples, peak):
    top = max((abs(s) for s in samples), default=0.0) or 1.0
    k = peak / top
    return [s * k for s in samples]


def _fade(samples, ms=2.0):
    """A hard edge on any sound is a click of its own."""
    n = min(len(samples) // 2, int(RATE * ms / 1000))
    for i in range(n):
        g = i / n
        samples[i] *= g
        samples[-1 - i] *= g
    return samples


class Svf:
    """A state-variable band-pass whose centre can move every sample (TPT form, stable
    under modulation — a biquad's coefficients jumping per sample is not)."""

    def __init__(self):
        self.ic1 = self.ic2 = 0.0

    def bp(self, x, fc, q):
        g = math.tan(math.pi * min(fc, RATE * 0.45) / RATE)
        k = 1.0 / q
        a1 = 1.0 / (1.0 + g * (g + k))
        a2 = g * a1
        a3 = g * a2
        v3 = x - self.ic2
        v1 = self.ic1 * a1 + v3 * a2
        v2 = self.ic2 + self.ic1 * a2 + v3 * a3
        self.ic1 = 2 * v1 - self.ic1
        self.ic2 = 2 * v2 - self.ic2
        return v1 * k           # peak gain ~1 at the centre whatever q is


def _add(out, layer, start_ms):
    s0 = int(RATE * start_ms / 1000)
    for i, v in enumerate(layer):
        if s0 + i < len(out):
            out[s0 + i] += v


def _ring(freq, tau_ms, amp, ms):
    """A damped sine: one resonant mode of a struck object."""
    n = int(RATE * ms / 1000)
    return [amp * math.sin(2 * math.pi * freq * i / RATE) * math.exp(-i / RATE / (tau_ms / 1000))
            for i in range(n)]


def _hit(rng, fc, q, tau_ms, amp, ms):
    """A burst of band-passed noise with an exponential tail: the broadband part of an
    impact. Filtered, because raw white noise is a hiss, not a knock."""
    n = int(RATE * ms / 1000)
    f = Svf()
    return [amp * f.bp(rng.uniform(-1, 1), fc, q) * math.exp(-i / RATE / (tau_ms / 1000))
            for i in range(n)]


# A mechanical key is two events, not one: the switch ACTUATES (a bright tick) and a few
# ms later the keycap BOTTOMS OUT (a broadband clack over a low thud from the case).
#
# It is NOISE, not tone. The first version rang damped sines at 640/1180 Hz and a 230 Hz
# "case" mode, and it sounded like a bamboo stick being struck: a pitch that rings for
# tens of ms is what wood and metal bars do, and a keyboard does not. Measured, that
# version had a spectral flatness of 0.0001 (1 = noise, 0 = one sine) and 90% of its
# energy at one frequency. So every layer below is band-passed NOISE with a low Q (wide,
# unpitched) and a short tail; the only tonal part is a faint, fast-dying ring that gives
# the thud a body rather than a note. test-gen-sfx.py pins "no single dominant pitch".
KEYBOARDS = {
    #          tick Hz  tick amt  bottom delay ms  clack Hz  thud Hz  thud ms  thud amt  ring amt
    "tactile": dict(tick=3400, tick_amt=0.60, delay=5.0, clack=1900, thud=260, thud_ms=16, thud_amt=0.65, ring=0.06),
}


def key(seed, board="tactile", scale=1.0, peak=0.5, weight=1.0):
    """`scale` stretches every frequency (a bigger key sounds lower); `weight` is the
    thud's level (a spacebar is mostly thud)."""
    rng = random.Random(seed)
    b = KEYBOARDS[board]
    j = lambda: 1.0 + rng.uniform(-0.08, 0.08)
    ms = 90
    out = [0.0] * int(RATE * ms / 1000)
    # 1. the actuation tick: a few hundred microseconds of bright, wide noise
    _add(out, _hit(rng, b["tick"] * j() * scale, 0.9, 0.6, b["tick_amt"], 10), 0)
    # 2. the bottom-out `delay` ms later: a wide clack, and under it the thud
    d = b["delay"] * j()
    _add(out, _hit(rng, b["clack"] * j() * scale, 0.7, 4.0, 1.0, 40), d)
    _add(out, _hit(rng, b["thud"] * j() * scale, 0.8, b["thud_ms"] / 2.5, b["thud_amt"] * weight, 60), d)
    #    just enough ring that the thud has a body, and gone in a few ms
    _add(out, _ring(b["thud"] * 0.9 * j() * scale, b["thud_ms"] / 3, b["ring"] * weight, 40), d)
    return _fade(_norm(out, peak), 0.5)


def swoosh(seed, ms, f0, f1, q, peak, attack=0.3, air=0.0, soften=0.0, onset=2, fade_ms=4.0):
    """Noise through a band-pass that SWEEPS from f0 to f1 — a moving band reads as air
    going past, where a swept low-pass reads as something dragged along a floor. The
    envelope is asymmetric (`attack` is where it peaks, as a fraction) and the sweep
    eases out, so it arrives fast and trails off. `air` mixes a little unswept
    high-passed noise for the breath on top. `soften` is a low-pass cutoff in Hz applied
    after the sweep (two poles): it takes the grain off, which is what makes a swoosh
    read as soft rather than as noise. 0 = off. `onset` is the power of the rise (2 =
    a raised sine; higher starts later and softer) and `fade_ms` the edge fade — a
    swoosh that STARTS abruptly is the sharpest thing about it."""
    rng = random.Random(seed)
    n = int(RATE * ms / 1000)
    f = Svf()
    hp = 0.0
    out = []
    k = 1.0 - math.exp(-2 * math.pi * soften / RATE) if soften > 0 else 1.0
    l1 = l2 = 0.0
    for i in range(n):
        t = i / max(1, n - 1)
        ease = 1.0 - (1.0 - t) ** 2.2           # fast at first, settling
        fc = f0 * (f1 / f0) ** ease              # a log sweep: equal steps per octave
        if t < attack:
            env = math.sin(0.5 * math.pi * t / attack) ** onset
        else:
            env = math.cos(0.5 * math.pi * (t - attack) / (1 - attack)) ** 2
        x = rng.uniform(-1, 1)
        hp += 0.12 * (x - hp)
        body = f.bp(x, fc, q)
        y = (body + air * (x - hp)) * env
        l1 += k * (y - l1)
        l2 += k * (l1 - l2)
        out.append(l2)
    return _fade(_norm(out, peak), fade_ms)


def blip(freqs, ms, peak, decay=18.0):
    """Sine partials with an exponential tail; `freqs` is [(hz, start_ms), ...]."""
    total = int(RATE * (ms + max(s for _, s in freqs)) / 1000)
    out = [0.0] * total
    for hz, start_ms in freqs:
        s0 = int(RATE * start_ms / 1000)
        for i in range(total - s0):
            t = i / RATE
            out[s0 + i] += math.sin(2 * math.pi * hz * t) * math.exp(-t * decay)
    return _fade(_norm(out, peak), 3.0)


def sweep_blip(f0, f1, ms, peak):
    n = int(RATE * ms / 1000)
    env = _env_sine(n)
    out, phase = [], 0.0
    for i in range(n):
        hz = f0 + (f1 - f0) * (i / max(1, n - 1))
        phase += 2 * math.pi * hz / RATE
        out.append(math.sin(phase) * env[i])
    return _fade(_norm(out, peak))


def bell(notes, ms, peak, tau_ms=170.0):
    """A soft struck-bell chord/arpeggio: each note is its fundamental plus a quiet octave
    and a quieter fifth-above-that, ringing down together. `notes` = [(hz, start_ms)].
    The partials are what make it a bell and not a beep."""
    out = [0.0] * int(RATE * ms / 1000)
    for hz, start in notes:
        _add(out, _ring(hz, tau_ms, 1.0, ms), start)
        _add(out, _ring(hz * 2.0, tau_ms * 0.55, 0.30, ms), start)
        _add(out, _ring(hz * 3.0, tau_ms * 0.30, 0.10, ms), start)
    return _fade(_norm(out, peak), 3.0)


def marimba(notes, ms, peak, tau_ms=140.0):
    """Wooden mallet notes: a bar's fundamental, its strong overtone at ~4x that dies in a
    few ms (the "tok" of the strike), and a tiny mallet tick. `notes` = [(hz, start_ms)].
    A bar is NOT a bell — no shimmer, a short woody body — which is what keeps this apart
    from `notify`."""
    rng = random.Random(51)
    out = [0.0] * int(RATE * ms / 1000)
    for hz, start in notes:
        _add(out, _ring(hz, tau_ms, 1.0, ms), start)
        _add(out, _ring(hz * 4.0, 22.0, 0.40, 120), start)
        _add(out, _hit(rng, 2600, 1.0, 1.2, 0.18, 12), start)
    return _fade(_norm(out, peak), 3.0)


def radar(ms, peak, pulse_ms=150, pulses=6, rounds=2, round_gap_ms=380, f0=1250.0):
    """A sonar ping, repeated: each pulse is a bright sine that glides down a little as it
    decays, with a quick FM edge on the strike so it reads as electronic rather than as a
    bell. Pulses swell across a round (the radar sweeping closer), then a gap, then again."""
    out = [0.0] * int(RATE * ms / 1000)
    t0 = 0.0
    for r in range(rounds):
        for p in range(pulses):
            amp = 0.55 + 0.45 * p / max(1, pulses - 1)
            n = int(RATE * 0.22)
            phase = 0.0
            s0 = int(RATE * (t0 + p * pulse_ms / 1000.0))
            for i in range(n):
                t = i / RATE
                hz = f0 * (1.0 + 0.12 * math.exp(-t / 0.03))
                phase += 2 * math.pi * hz / RATE
                fm = 0.9 * math.exp(-t / 0.012) * math.sin(2.0 * phase)
                v = math.sin(phase + fm) * math.exp(-t / 0.055) * amp
                if s0 + i < len(out):
                    out[s0 + i] += v
        t0 += pulses * pulse_ms / 1000.0 + round_gap_ms / 1000.0
    return _fade(_norm(out, peak), 3.0)


def pluck(hz, ms, peak, damp=0.995, seed=61):
    """Karplus-Strong: noise circulating in a delay line the length of one period, each
    pass averaged — a plucked string. Different TIMBRE from every bell here, which is the
    point of using it for a saved clip."""
    rng = random.Random(seed)
    n = max(2, int(RATE / hz))
    line = [rng.uniform(-1, 1) for _ in range(n)]
    out = []
    for i in range(int(RATE * ms / 1000)):
        j = i % n
        nxt = line[(j + 1) % n]
        line[j] = damp * 0.5 * (line[j] + nxt)
        out.append(line[j])
    return _fade(_norm(out, peak), 2.0)


def sequence(parts, ms, peak):
    """Lay finished sounds on one timeline; `parts` = [(samples, start_ms)]."""
    out = [0.0] * int(RATE * ms / 1000)
    for samples, start in parts:
        _add(out, samples, start)
    return _fade(_norm(out, peak), 3.0)


def shutter(seed, peak):
    """Two clicks, a mirror and a curtain: a bright tick with a thunk under it, then a
    softer, lower one ~40 ms later."""
    rng = random.Random(seed)
    out = [0.0] * int(RATE * 0.11)
    _add(out, _hit(rng, 3500, 1.2, 1.5, 1.0, 14), 0)
    _add(out, _hit(rng, 900, 0.8, 6.0, 0.8, 35), 2)
    _add(out, _hit(rng, 2600, 1.0, 2.0, 0.7, 14), 40)
    _add(out, _hit(rng, 600, 0.8, 5.0, 0.6, 35), 42)
    return _fade(_norm(out, peak), 0.5)


def sounds():
    return {
        "key1":     key(11),
        "key2":     key(12),
        "key3":     key(13),
        "key4":     key(14),
        "keyspace": key(21, scale=0.62, weight=1.6, peak=0.55),
        "keyenter": key(22, scale=0.75, weight=1.3, peak=0.55),
        "keyback":  key(23, scale=1.15, weight=0.7, peak=0.45),
        "open":     swoosh(31, 600, 120, 320, 0.6, 0.20, attack=0.65, soften=450, onset=4, fade_ms=40),
        "close":    swoosh(32, 540, 300, 110, 0.6, 0.17, attack=0.5, soften=420, onset=4, fade_ms=40),
        "on":       sweep_blip(520, 780, 110, 0.45),
        "off":      sweep_blip(700, 470, 110, 0.40),
        "notify":   blip([(880, 0), (1320, 70)], 380, 0.50, decay=9.0),
        "tick":     blip([(1500, 0)], 40, 0.30, decay=60.0),
        "timer":    marimba([(659, 0), (784, 105), (988, 210), (1319, 315),
                             (988, 520), (1319, 625), (988, 730), (1319, 835)], 1500, 0.42),
        "alarm":    radar(2400, 0.40),
        "shutter":  shutter(41, 0.45),
        "clipsaved": sequence([(pluck(523, 260, 1.0), 0), (pluck(784, 320, 1.0, seed=62), 110)], 450, 0.40),
    }


def write_wav(path, samples):
    tmp = path + ".part"
    with wave.open(tmp, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))
    os.replace(tmp, path)       # a half-written file is never visible under its name


def script_hash():
    with open(os.path.abspath(__file__), "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()[:16]


def main(argv):
    if len(argv) < 2:
        print("usage: gen-sfx.py <out-dir> [--force]", file=sys.stderr)
        return 2
    out = argv[1]
    os.makedirs(out, exist_ok=True)
    stamp = os.path.join(out, ".stamp")
    want = script_hash()
    try:
        have = open(stamp).read().strip()
    except OSError:
        have = ""
    table = sounds()
    complete = all(os.path.exists(os.path.join(out, n + ".wav")) for n in table)
    if have == want and complete and "--force" not in argv:
        print("fresh")
        return 0
    for name, samples in table.items():
        write_wav(os.path.join(out, name + ".wav"), samples)
    with open(stamp, "w") as f:
        f.write(want)
    print("wrote")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
