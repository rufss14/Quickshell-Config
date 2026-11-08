"""synthkit.py — synthetic drums and arrangements with KNOWN hit times, for testing
scripts/music-pulse.py (test-music-pulse.py pins behaviours; bench-rhythm.py scores the rhythm
engine on whole songs). Pure numpy; nothing here touches audio devices.

The single sounds are the ones test-music-pulse.py has always used (moved here unchanged), plus
what real tracks threw at the detector on 2026-10-31: a sidechained bass, a cowbell, a tamborim
(funk percussion that read as snares), claps on every beat (J-core), a pad, a crash.

`arrangement(name, gain)` returns (samples, truth): truth["kick"] / ["back"] (the backbeat
snares or claps — what should ring) / ["ghost"] (every other snare-ish hit) as onset times,
truth["drop"] (the drop's beat 1, or None), truth["bpm"], truth["bar1"] (a beat 1).
"""
import numpy as np

RATE = 48000


def kick(n, amp=0.8, seed=99):
    t = np.arange(n) / RATE
    # A kick: a falling 120→50 Hz sine with a fast decay — the low thump — and the beater's
    # click, a few ms of broadband noise on top, as a real kick has.
    f = 50 + 70 * np.exp(-t / 0.03)
    thump = amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.06)
    click = np.random.default_rng(seed).standard_normal(n) * 0.25 * amp * np.exp(-t / 0.004)
    return thump + click


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / RATE)
    X[(f < lo) | (f > hi)] = 0
    return np.fft.irfft(X, len(x))


def hat(n, amp=0.3, seed=0):
    # A closed hi-hat: a short hiss, all of it above 7 kHz.
    t = np.arange(n) / RATE
    return amp * bandpass(np.random.default_rng(seed).standard_normal(n), 7000, 18000) * np.exp(-t / 0.02)


def snare(n, amp=0.6, seed=0):
    # A body that drops from 240 to 180 Hz, and the wires: noise 1–12 kHz.
    t = np.arange(n) / RATE
    f = 180 + 60 * np.exp(-t / 0.01)
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.05)
    wires = bandpass(np.random.default_rng(seed + 7).standard_normal(n), 1000, 12000) * np.exp(-t / 0.10)
    return amp * (0.5 * body + 0.8 * wires)


def clap(n, amp=0.6, seed=0):
    # Three quick bursts and a tail, 0.9–5 kHz: no body, nothing high.
    t = np.arange(n) / RATE
    e = sum(np.where(t >= d, np.exp(-np.maximum(0.0, t - d) / 0.008), 0.0) for d in (0.0, 0.011, 0.022))
    e = e + np.where(t >= 0.03, np.exp(-np.maximum(0.0, t - 0.03) / 0.08), 0.0)
    return amp * bandpass(np.random.default_rng(seed + 13).standard_normal(n), 900, 5000) * e


def place(x, sound, times, length=0.25):
    for j, t in enumerate(times):
        i = int(t * RATE)
        if i >= len(x):
            break
        s = sound(min(int(length * RATE), len(x) - i), seed=j)
        x[i:i + len(s)] += s
    return x


def track(seconds, kicks_at, hats_every=None):
    x = np.zeros(int(seconds * RATE), dtype=np.float64)
    for t in kicks_at:
        i = int(t * RATE)
        k = kick(min(int(0.25 * RATE), len(x) - i))
        x[i:i + len(k)] += k
    if hats_every:
        t = 0.0
        j = 0
        while t < seconds:
            i = int(t * RATE)
            h = hat(min(int(0.05 * RATE), len(x) - i), seed=j)
            x[i:i + len(h)] += h
            t += hats_every
            j += 1
    return x.astype(np.float32)


def bass808(n, f0=55.0, amp=0.7, seed=0):
    t = np.arange(n) / RATE
    # A sustained 808 note that glides down a little: low, loud, no click — a 3 ms fade-in, as a
    # produced 808 has (2026-10-31: starting at full amplitude in one sample made a broadband
    # click no real 808 has, and the kick model rightly took it for a kick).
    f = f0 * (1 + 0.15 * np.exp(-t / 0.08))
    return amp * np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t / 0.35) * np.minimum(1.0, t / 0.003)


def phonk(seconds, bpm=120.0, start=0.5):
    period = 60.0 / bpm
    kicks = [start + i * period for i in range(int((seconds - start) / period))]
    x = track(seconds, kicks, hats_every=period / 2).astype(np.float64)
    # 808 notes on the off-beats — what fooled the onset detector into a hit per note.
    for k in kicks:
        i = int((k + period / 2) * RATE)
        if i >= len(x):
            break
        b = bass808(min(int(0.4 * RATE), len(x) - i), f0=50 + 15 * ((i // 997) % 3))
        x[i:i + len(b)] += b
    return x.astype(np.float32), kicks


# ── More of what real tracks do (2026-10-31) ──────────────────────────────────

def kick_produced(n, amp=0.8, seed=99):
    """A produced kick, as a mixed track has it: the same thump and click, louder click, plus a
    knock — a short 150–300 Hz body. The plain `kick` (the tests' since day one) has a click a
    quarter of the thump's level and no knock."""
    t = np.arange(n) / RATE
    k = kick(n, amp, seed)
    click = np.random.default_rng(seed + 3).standard_normal(n) * 0.35 * amp * np.exp(-t / 0.003)
    knock = 0.35 * amp * np.sin(2 * np.pi * (180 + 120 * np.exp(-t / 0.01)) * t) * np.exp(-t / 0.025)
    return k + bandpass(click, 1000, 12000) + knock


def cowbell(n, amp=0.25, seed=0):
    # Two inharmonic square-ish tones (540/800 Hz), 100 ms: a funk cowbell.
    t = np.arange(n) / RATE
    tone = np.sign(np.sin(2 * np.pi * 540 * t)) + 0.8 * np.sign(np.sin(2 * np.pi * 800 * t))
    return amp * 0.5 * bandpass(tone, 300, 6000) * np.exp(-t / 0.1)


def tamborim(n, amp=0.3, seed=0):
    # A short bright slap, 2–7 kHz, 15 ms: the funk percussion that read as snares.
    t = np.arange(n) / RATE
    return amp * bandpass(np.random.default_rng(seed + 31).standard_normal(n), 2000, 7000) * np.exp(-t / 0.015)


def crash(n, amp=0.3, seed=0):
    t = np.arange(n) / RATE
    return amp * bandpass(np.random.default_rng(seed + 57).standard_normal(n), 3000, 16000) * np.exp(-t / 0.9)


def sidechain_bass(seconds, f0, kicks, amp=0.2, duck=0.85, release=0.12, start=0.0, end=None):
    """A sustained low saw (4 harmonics) that ducks under every kick and swells back — EDM and
    J-core's constant bass, whose wobble the kick band hears between the kicks."""
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    saw = sum(np.sin(2 * np.pi * f0 * h * t) / h for h in range(1, 5))
    g = np.ones(n)
    for k in kicks:
        i = int(k * RATE)
        if 0 <= i < n:
            m = min(n, i + int(0.6 * RATE))
            g[i:m] = np.minimum(g[i:m], 1 - duck * np.exp(-(t[i:m] - k) / release))
    on = (t >= start) & (t < (end if end is not None else seconds))
    return amp * saw * g * on


def pad(seconds, start, end, amp=0.12):
    n = int(seconds * RATE)
    t = np.arange(n) / RATE
    on = ((t >= start) & (t < end)).astype(float)
    return amp * on * sum(np.sin(2 * np.pi * f * t) for f in (220.0, 277.2, 329.6)) / 3


def arrangement(name, gain=1.0, seed=0):
    """A whole song shape with known hits. 4/4. Sections: groove (8 bars), breakdown (4 bars,
    no drums, a pad), DROP (8 bars, everything, a crash on its beat 1)."""
    rng = np.random.default_rng(seed)
    bpm = {"edm128": 128.0, "phonk130": 130.0, "jcore174": 174.0, "hiphop90": 90.0}[name]
    P = 60.0 / bpm
    bar1 = 0.5
    groove, brk, drop_bars = 8, 4, 8
    total_bars = groove + brk + drop_bars
    seconds = bar1 + total_bars * 4 * P + 1.0
    n = int(seconds * RATE)
    x = np.zeros(n)
    truth = {"kick": [], "back": [], "ghost": [], "drop": None, "bpm": bpm, "bar1": bar1}
    drop_at = bar1 + (groove + brk) * 4 * P
    truth["drop"] = drop_at

    def add(sound, t, length=0.25, amp=None, **kw):
        i = int(t * RATE)
        if i >= n:
            return
        s = sound(min(int(length * RATE), n - i), seed=int(rng.integers(1 << 30)), **kw)
        x[i:i + len(s)] += s if amp is None else s * amp

    def drums_bar(b0):
        """One bar of drums starting at b0, by genre. Returns nothing; appends truth."""
        beats = [b0 + k * P for k in range(4)]
        s16 = [b0 + k * P / 4 for k in range(16)]
        if name == "edm128":
            for t in beats:
                add(kick_produced, t); truth["kick"].append(t)
            for t in (beats[1], beats[3]):
                add(clap, t); truth["back"].append(t)
            for k, t in enumerate(s16):
                add(hat, t, 0.05, amp=0.6 if k % 2 else 1.0)
        elif name == "phonk130":
            for t in (beats[0], beats[2], b0 + 2.5 * P):      # 1, 3 and the "and" of 3
                add(kick_produced, t); truth["kick"].append(t)
            for t in (beats[1], beats[3]):
                add(snare, t); truth["back"].append(t)
            for k in (2, 6, 7, 10, 14):                         # a cowbell line
                add(cowbell, s16[k], 0.15)
            for k in (3, 5, 9, 11, 13, 15):                     # tamborim 16ths: ghosts
                add(tamborim, s16[k], 0.05); truth["ghost"].append(s16[k])
            for t in (b0 + 0.5 * P, b0 + 1.5 * P + P / 4):     # 808s between the kicks
                add(bass808, t, 0.4)
            for t in s16[::2]:
                add(hat, t, 0.05, amp=0.5)
        elif name == "jcore174":
            for t in beats:
                add(kick_produced, t); truth["kick"].append(t)
                add(clap, t, amp=0.7)                            # a clap on every beat, on the kick
            for t in (beats[1], beats[3]):
                add(snare, t); truth["back"].append(t)
            for t in s16[::2]:
                add(hat, t, 0.05, amp=0.7)
        elif name == "hiphop90":
            for t in (beats[0], b0 + 1.75 * P, beats[2] + P / 2):   # boom-bap
                add(kick_produced, t); truth["kick"].append(t)
            for t in (beats[1], beats[3]):
                add(snare, t); truth["back"].append(t)
            for k in range(8):                                      # swung 8ths
                add(hat, b0 + k * P / 2 + (P * 0.08 if k % 2 else 0), 0.05, amp=0.6)
            add(bass808, beats[0], 0.6)

    for b in range(total_bars):
        b0 = bar1 + b * 4 * P
        if groove <= b < groove + brk:
            continue                                            # the breakdown: no drums
        drums_bar(b0)
    if name in ("edm128", "jcore174"):
        kicks_on = [t for t in truth["kick"]]
        # The bass sits ~8 dB under the kick in the sub band, as a mix has it.
        x += sidechain_bass(seconds, 49.0 if name == "edm128" else 55.0, kicks_on, amp=0.15,
                            end=bar1 + groove * 4 * P)
        x += sidechain_bass(seconds, 49.0 if name == "edm128" else 55.0, kicks_on, amp=0.2, start=drop_at)
    x += pad(seconds, bar1 + groove * 4 * P, drop_at + 2 * P)
    add(crash, drop_at, 1.5)
    # The groove plays quieter than the drop: that is what a drop is.
    t = np.arange(n) / RATE
    x *= np.where(t < drop_at, 0.55, 1.0)
    x += rng.standard_normal(n) * 1e-4                           # a noise floor
    x = x / max(1e-9, np.max(np.abs(x))) * 0.9 * gain
    for k in truth:
        if isinstance(truth[k], list):
            truth[k].sort()
    return x.astype(np.float32), truth
