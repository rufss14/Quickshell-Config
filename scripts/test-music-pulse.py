#!/usr/bin/env python3
"""test-music-pulse.py — scripts/music-pulse.py's analysis, on synthetic tracks.

    python3 scripts/test-music-pulse.py

Pins what the user asked for (2026-10-31: effects that keep up with the song): every kick
found, and found FAST — within one analysis window (21 ms) of its start — while hi-hats and
a sustained bass don't fire, silence stays silent, and the flash never exceeds three a
second. Then (same day, "each effect should have a sound … not shaking and zooming without
kicks"): kick, snare/clap and hi-hat told apart, and no beat where no kick is heard.
"""
import importlib.util
import os
import sys

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("music_pulse", os.path.join(here, "music-pulse.py"))
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)

RATE = mp.RATE
failed = passed = 0


def check(name, ok, detail=""):
    global failed, passed
    if ok:
        passed += 1
    else:
        failed += 1
        print("FAIL", name, detail)


# The sounds live in synthkit.py (shared with bench-rhythm.py and fit-rhythm.py).
sys.path.insert(0, here)
from synthkit import kick, bandpass, hat, snare, clap, place, track, bass808, phonk  # noqa: E402

def run(x, chunk=mp.HOP, drums=None):
    an = mp.Analyzer()
    beats, flashes = [], []
    snares, hats, booms = [], [], []
    last_b, last_f, last_s, last_h, last_o = 0, 0.0, 0, 0.0, 0
    an.engine_kicks = []               # the rhythm engine's kicks (what the effects follow)
    for i in range(0, len(x), chunk):
        fed = an.feed(x[i:i + chunk])
        for e in an.take_events():
            f = e.split()
            if f[2] == "kick":
                an.engine_kicks.append(float(f[1]))
        for t, s in fed:
            if s[5] > last_b:
                beats.append(t)
                last_b = s[5]
            if s[6] == 1.0 and last_f < 1.0:
                flashes.append(t)
            last_f = s[6]
            if s[10] > last_s:
                snares.append(t)
                last_s = s[10]
            if s[11] == 1.0 and last_h < 1.0:
                hats.append(t)
            last_h = s[11]
            if s[13] > last_o:
                booms.append(t)
                last_o = s[13]
    if drums is not None:
        drums["snares"], drums["hats"], drums["booms"] = snares, hats, booms
    return beats, flashes, an


# Silence: nothing at all.
b, f, an = run(np.zeros(RATE * 3, dtype=np.float32))
check("silence: no beats", len(b) == 0, b)
check("silence: no level", an.state()[0] == 0.0, an.state())

# 120 BPM kicks under 8th-note hats for 10 s: every kick, no hat, and fast.
kicks = [0.5 + 0.5 * i for i in range(19)]
b, f, an = run(track(10.0, kicks, hats_every=0.25))
# (Once locked, the clock carries on past the clip's last kick: beats among the kicks are judged.)
inside = [x for x in b if x <= kicks[-1] + 0.1]
check("120 bpm: one beat per kick", len(inside) == len(kicks), "%d beats for %d kicks" % (len(inside), len(kicks)))
lags = []
for t in kicks:
    near = [x - t for x in b if -0.015 <= x - t <= 0.1]       # the clock may land a little early
    if near:
        lags.append(min(near, key=abs))
check("every kick found", len(lags) == len(kicks), "%d of %d" % (len(lags), len(kicks)))
if lags:
    worst = max(abs(x) for x in lags)
    check("found within one window (21 ms)", worst <= mp.WIN / RATE + 0.001, "worst %.1f ms" % (worst * 1000))
    print("  beat vs kick: mean %+.1f ms, worst %.1f ms" % (1000 * sum(lags) / len(lags), 1000 * worst))

# Hats alone: no beats (they aren't in the kick band).
b, f, an = run(track(5.0, [], hats_every=0.125))
check("hats alone: no beats", len(b) == 0, len(b))

# A sustained bass note after its start: at most the start counts.
t = np.arange(RATE * 4) / RATE
d = {}
b, f, an = run((0.6 * np.sin(2 * np.pi * 60 * t)).astype(np.float32), drums=d)
check("sustained bass: at most its start", len(b) <= 1, len(b))
check("sustained bass: one bass note at most", len(d["booms"]) + len(b) <= 1, (len(d["booms"]), len(b)))

# Fast hard kicks (8 a second): the flash keeps to three a second.
b, f, an = run(track(6.0, [0.2 + i / 8 for i in range(46)]))
worst = 0
for i, t in enumerate(f):
    worst = max(worst, sum(1 for u in f[i:] if u - t < 1.0))
check("flashes happen", len(f) > 5, len(f))
check("never more than 3 flashes a second", worst <= 3, worst)

# Quiet and loud versions of the same track find the same beats (the normaliser).
# (2026-10-31: judged on the rhythm engine's kicks — what the effects follow now — not the old
# immediate detector's, whose beat clock the engine now phases.)
_, _, qa = run(track(6.0, kicks[:11]) * 0.1)
_, _, la = run(track(6.0, kicks[:11]))
nq = sum(1 for k in kicks[:11] if any(-0.010 <= f - k <= 0.030 for f in qa.engine_kicks))
nl = sum(1 for k in kicks[:11] if any(-0.010 <= f - k <= 0.030 for f in la.engine_kicks))
check("volume doesn't change the kicks", nq >= 10 and nl >= 10, "%d / %d" % (nq, nl))

# ── The beat clock ──────────────────────────────────────────────────────────────
x, kicks = phonk(16.0)
an = mp.Analyzer()
beats, last = [], 0
locked_at = None
for i in range(0, len(x), mp.HOP):
    for t, st in an.feed(x[i:i + mp.HOP]):
        if st[5] > last:
            beats.append(t)
            last = st[5]
        if st[8] == 1 and locked_at is None:
            locked_at = t
# (< 7 s since 2026-10-31: the first tempo estimate waits WARMUP_S = 6 s, so the comb's bar
# terms reach slow tempos — at 4 s boom-bap at 90 couldn't be the first guess.)
check("locks", locked_at is not None and locked_at < 7.0, locked_at)
check("tempo ~120", abs(an.tracker.bpm() - 120.0) < 1.5, an.tracker.bpm())
# (A clock carries on past the clip's last kick; only beats among the kicks are judged.)
late = [b for b in beats if 7.0 < b <= kicks[-1] + 0.1]
off = [min(abs(b - k) for k in kicks) for b in late]
check("locked beats sit on the kicks (±15 ms)", off and max(off) <= 0.015, "worst %.1f ms" % (1000 * max(off or [0])))
check("no beat for the 808 notes", len(late) <= len([k for k in kicks if k > 7.0]) + 1,
      "%d beats for %d kicks" % (len(late), len([k for k in kicks if k > 7.0])))
if off:
    print("  locked beat vs kick: mean %.1f ms, worst %.1f ms" % (1000 * sum(off) / len(off), 1000 * max(off)))

# A breakdown — the kicks stop, the hats go on: it unlocks, and stops beating.
y = np.concatenate((x, track(6.0, [], hats_every=0.25)))
an = mp.Analyzer()
last, beats_after = 0, 0
for i in range(0, len(y), mp.HOP):
    for t, st in an.feed(y[i:i + mp.HOP]):
        if st[5] > last:
            last = st[5]
            if t > 16.0 + 2.0:
                beats_after += 1
check("unlocks in a breakdown", an.tracker.locked is False)
check("no beats in a breakdown", beats_after == 0, beats_after)

# ── The drums, told apart ───────────────────────────────────────────────────────
def matched(found, times, early=0.005, late=0.030):
    return sum(1 for t in times if any(-early <= f - t <= late for f in found))


hits = [0.5 + 0.5 * i for i in range(9)]
for name, sound in (("snare", snare), ("clap", clap)):
    d = {}
    b, _, _ = run(place(np.zeros(RATE * 5), sound, hits).astype(np.float32), drums=d)
    check(name + "s: each is a snare", matched(d["snares"], hits) == len(hits) and len(d["snares"]) == len(hits),
          "%d snares for %d" % (len(d["snares"]), len(hits)))
    check(name + "s: no kick", len(b) == 0, len(b))
    check(name + "s: no hat", len(d["hats"]) == 0, len(d["hats"]))
    check(name + "s: no bass note", len(d["booms"]) == 0, len(d["booms"]))

d = {}
b, _, _ = run(track(5.0, hits), drums=d)
check("kicks: no snare (the beater's click isn't one)", len(d["snares"]) == 0, len(d["snares"]))
check("kicks: no hat", len(d["hats"]) == 0, len(d["hats"]))
check("kicks: no bass note (a kick is a kick)", len(d["booms"]) == 0, len(d["booms"]))

eighths = [0.25 + 0.25 * i for i in range(18)]
d = {}
b, _, _ = run(place(np.zeros(RATE * 5), hat, eighths, 0.05).astype(np.float32), drums=d)
check("hats: each is a hat", matched(d["hats"], eighths) == len(eighths), "%d of %d" % (matched(d["hats"], eighths), len(eighths)))
check("hats: no snare", len(d["snares"]) == 0, len(d["snares"]))

# A whole kit for 16 s: kick on 1 and 3, snare on 2 and 4, eighth hats, 808s on the off-beats.
x, kicks = phonk(16.0)
period = 0.5
snare_at = [k + period for k in kicks[::2]][:-1]
kicks = kicks[::2]
x = np.zeros(int(16.0 * RATE))
x = place(x, lambda n, seed: kick(n, seed=99 + seed), kicks)
x = place(x, snare, snare_at)
x = place(x, hat, [0.5 + 0.25 * i for i in range(62)], 0.05)
for k in kicks:
    i = int((k + period / 2) * RATE)
    nb = bass808(min(int(0.4 * RATE), len(x) - i))
    x[i:i + len(nb)] += nb
d = {}
b, _, kit_an = run(x.astype(np.float32), drums=d)
ek = kit_an.engine_kicks
check("kit: every kick a kick", matched(ek, kicks, early=0.015) >= len(kicks) - 1, "%d of %d" % (matched(ek, kicks, early=0.015), len(kicks)))
# Once the clock has locked (4 s): before it, an 808 as loud as a kick is judged by its sound alone.
ek_locked = [t for t in ek if t > 4.0]
check("kit: once locked, no kick that isn't one (the off-beat 808s)",
      len(ek_locked) - matched(ek_locked, kicks, early=0.015) == 0,
      "%d kicks, %d true" % (len(ek_locked), matched(ek_locked, kicks, early=0.015)))
check("kit: every snare a snare", matched(d["snares"], snare_at) == len(snare_at), "%d of %d" % (matched(d["snares"], snare_at), len(snare_at)))
check("kit: no snare that isn't one", len(d["snares"]) <= len(snare_at) + 1, "%d for %d" % (len(d["snares"]), len(snare_at)))
# The 808s are bass notes (the user: shake on the bass) — once the clock knows the kicks.
notes = [k + period / 2 for k in kicks if k > 7.0]
late_booms = [t for t in d["booms"] if t > 7.0]
check("kit: every 808 a bass note", matched(late_booms, notes) >= len(notes) - 1, "%d of %d" % (matched(late_booms, notes), len(notes)))
check("kit: no bass note on a kick", not [t for t in d["booms"] if any(abs(t - k) < 0.04 for k in kicks)],
      [round(t, 3) for t in d["booms"] if any(abs(t - k) < 0.04 for k in kicks)])
print("  kit: %d beats / %d kicks, %d snares / %d, %d hats, %d bass notes" % (len(b), len(kicks), len(d["snares"]), len(snare_at), len(d["hats"]), len(d["booms"])))

# The hardest hits (Glitch's): rare — at most one a second — and they do come.
impacts, last = [], 0
an = mp.Analyzer()
for i in range(0, len(x), mp.HOP):
    for t, st in an.feed(x[i:i + mp.HOP].astype(np.float32)):
        if st[15] > last:
            impacts.append(t)
            last = st[15]
check("hardest hits happen", len(impacts) >= 3, len(impacts))
check("hardest hits at most one a second", all(b - a >= 0.99 for a, b in zip(impacts, impacts[1:])), impacts)

# The user's complaint: once locked, a kick that isn't played isn't a beat.
x, kicks = phonk(16.0)
skipped = [k for j, k in enumerate(kicks) if j % 4 == 3 and k > 7.0]
y = np.zeros(len(x))
y = place(y, lambda n, seed: kick(n, seed=99 + seed), [k for k in kicks if k not in skipped])
y = place(y, hat, [0.5 + 0.25 * i for i in range(62)], 0.05)
b, _, an = run(y.astype(np.float32))
ghost = [k for k in skipped if any(abs(t - k) < 0.06 for t in b)]
check("no beat where no kick is played", not ghost, "beats at %s" % ghost)
check("…while the clock stays locked", an.tracker.locked)

# How big the part is (2026-10-31): the same groove 20 dB down reads small on loud/sub, and its
# kicks light.
x, kicks = phonk(16.0)
y = x.copy()
y[len(y) // 2:] *= 0.1
an = mp.Analyzer()
rows = []
for i in range(0, len(y), mp.HOP):
    rows += an.feed(y[i:i + mp.HOP].astype(np.float32))
def part(a, b):
    return [st for t, st in rows if a <= t < b]
big, calm = part(5.0, 7.5), part(12.0, 15.5)
avg = lambda r, i: sum(st[i] for st in r) / max(1, len(r))
check("section: the quiet half is quieter", avg(calm, 16) < avg(big, 16) - 0.4, (avg(big, 16), avg(calm, 16)))
check("section: and lighter in the sub", avg(calm, 17) < avg(big, 17) - 0.4, (avg(big, 17), avg(calm, 17)))
check("section: heavy kicks where it's loud", max(st[18] for st in big) > 0.8, max(st[18] for st in big))
check("section: light kicks where it's quiet", max(st[18] for st in calm) < 0.5, max(st[18] for st in calm))

# Accents (2026-10-31, the ring "constantly getting spammed"): a backbeat's snares all count;
# busy snares only the strongest, about ACCENT_RATE a second.
def accents_of(x):
    an, last, out = mp.Analyzer(), 0, []
    for i in range(0, len(x), mp.HOP):
        for t, st in an.feed(x[i:i + mp.HOP].astype(np.float32)):
            if st[19] > last:
                out.append(t)
                last = st[19]
    return out, an.snares
backbeat = [1.0 + i for i in range(12)]
acc, n = accents_of(place(np.zeros(RATE * 14), snare, backbeat))
check("accents: a backbeat's every snare", len(acc) >= len(backbeat) - 1, "%d of %d (%d snares)" % (len(acc), len(backbeat), n))
busy = [1.0 + 0.25 * i for i in range(48)]
amp = [1.0 if i % 4 == 2 else 0.35 for i in range(48)]
y = np.zeros(RATE * 14)
for t, g in zip(busy, amp):
    i = int(t * RATE)
    s_ = snare(int(0.2 * RATE), seed=int(t * 100)) * g
    y[i:i + len(s_)] += s_
acc, n = accents_of(y)
check("accents: busy snares thinned", n > 30 and len(acc) <= 0.45 * n, "%d accents of %d snares" % (len(acc), n))
check("accents: at most ~3 a second", all(b - a >= mp.ACCENT_GAP_S - 1e-6 for a, b in zip(acc, acc[1:])))

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
