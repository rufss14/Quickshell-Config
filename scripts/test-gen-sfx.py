#!/usr/bin/env python3
"""Checks for scripts/gen-sfx.py. Writes only into a temp dir.

    python3 scripts/test-gen-sfx.py
"""
import importlib.util
import math
import os
import subprocess
import sys
import tempfile
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
GEN = os.path.join(HERE, "gen-sfx.py")

spec = importlib.util.spec_from_file_location("gen_sfx", GEN)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

fails = 0


def check(name, ok, detail=""):
    global fails
    print(("ok   " if ok else "FAIL ") + name + (("  " + detail) if detail and not ok else ""))
    if not ok:
        fails += 1


table = gen.sounds()

# Every name the player asks for must exist (services/sfx.js FILES).
for n in ["key1", "key2", "key3", "key4", "keyspace", "keyenter", "keyback",
          "open", "close", "on", "off", "notify", "tick",
          "timer", "alarm", "shutter", "clipsaved"]:
    check("has " + n, n in table)

for n, s in table.items():
    peak = max(abs(x) for x in s)
    ms = len(s) * 1000 / gen.RATE
    check(n + " peaks under full scale", 0.1 < peak <= 0.7, "peak %.2f" % peak)
    check(n + " is short", 20 <= ms <= 3000, "%.0f ms" % ms)
    # No click at either end: the first and last samples are faded to ~0.
    check(n + " starts and ends silent", abs(s[0]) < 0.02 and abs(s[-1]) < 0.02)

# ── Spectrum: a key is NOISE, a swoosh is LOW ────────────────────────────────
# Goertzel at log-spaced frequencies (stdlib; a full DFT of 4000 samples is slow in pure
# Python). The first keys rang a pitch and sounded like a bamboo stick; "no single
# frequency holds the energy" is what separates a knock from a note.
def spectrum(x, lo=80.0, hi=12000.0, bins=110):
    n = len(x)
    xs = [v * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1))) for i, v in enumerate(x)]
    freqs = [lo * (hi / lo) ** (k / (bins - 1)) for k in range(bins)]
    power = []
    for f in freqs:
        w = 2 * math.cos(2 * math.pi * f / gen.RATE)
        s1 = s2 = 0.0
        for v in xs:
            s1, s2 = v + w * s1 - s2, s1
        power.append(s1 * s1 + s2 * s2 - w * s1 * s2)
    return freqs, power


def centroid(x):
    f, p = spectrum(x)
    return sum(a * b for a, b in zip(f, p)) / sum(p)


def peak_share(x):
    f, p = spectrum(x)
    k = max(range(len(p)), key=p.__getitem__)
    near = sum(pp for ff, pp in zip(f, p) if f[k] * 0.9 <= ff <= f[k] * 1.1)
    return near / sum(p)


for n in ["key1", "key2", "key3", "key4", "keyspace", "keyenter", "keyback"]:
    check(n + " is noise-like, not a note", peak_share(table[n]) < 0.40, "%.2f" % peak_share(table[n]))
for b in gen.KEYBOARDS:
    check("keyboard " + b + " is noise-like", peak_share(gen.key(11, b)) < 0.40)
check("open is low, not shrill", centroid(table["open"]) < 1200, "%.0f Hz" % centroid(table["open"]))
check("close is lower than open", centroid(table["close"]) < centroid(table["open"]))
check("the swoosh is slow: over 400 ms", len(table["open"]) > 0.4 * gen.RATE)
check("…and subtle: quieter than a key", max(map(abs, table["open"])) < max(map(abs, table["key1"])))
# A saved clip chimed like a notification (both bells). The pluck is a different timbre AND
# a lower register; pin both so a later retune can't drift them back together.
check("a saved clip is lower than the notification chime", centroid(table["clipsaved"]) < 0.8 * centroid(table["notify"]),
      "%.0f vs %.0f Hz" % (centroid(table["clipsaved"]), centroid(table["notify"])))
check("the alarm is distinct from the timer", centroid(table["alarm"]) != centroid(table["timer"]))
check("the alarm pulses: several separate onsets", sum(
    1 for i in range(1, len(table["alarm"]) // 441)
    if max(abs(v) for v in table["alarm"][i * 441:(i + 1) * 441]) > 2.5 *
       max(abs(v) for v in table["alarm"][(i - 1) * 441:i * 441] or [1]) and
       max(abs(v) for v in table["alarm"][i * 441:(i + 1) * 441]) > 0.1) >= 6)
check("a spacebar is lower than a letter", centroid(table["keyspace"]) < centroid(table["key1"]))

# Deterministic: two builds are identical (the seeds are fixed).
check("deterministic", gen.sounds()["key1"] == table["key1"])

# Variants differ, or four keys would be one sample four times.
check("key variants differ", len({tuple(table[k][:200]) for k in ("key1", "key2", "key3", "key4")}) == 4)

# Open sweeps up, close sweeps down: compare the spectral tilt of each half by
# zero-crossing rate (a brighter noise crosses zero more often).
def zcr(x):
    return sum(1 for a, b in zip(x, x[1:]) if (a < 0) != (b < 0)) / max(1, len(x))

o, c = table["open"], table["close"]
check("open brightens", zcr(o[len(o) // 2:]) > zcr(o[:len(o) // 2]))
check("close darkens", zcr(c[len(c) // 2:]) < zcr(c[:len(c) // 2]))

# The CLI: writes, then is a no-op, then repairs a deleted file.
with tempfile.TemporaryDirectory() as d:
    out = os.path.join(d, "sfx")
    run = lambda *a: subprocess.run([sys.executable, GEN, out, *a], capture_output=True, text=True)
    r = run()
    check("first run writes", r.returncode == 0 and r.stdout.strip() == "wrote", r.stderr)
    r = run()
    check("second run is a no-op", r.stdout.strip() == "fresh")
    os.remove(os.path.join(out, "open.wav"))
    r = run()
    check("a missing file is regenerated", r.stdout.strip() == "wrote")
    with wave.open(os.path.join(out, "key1.wav")) as w:
        check("16-bit mono 44.1k", (w.getnchannels(), w.getsampwidth(), w.getframerate()) == (1, 2, 44100))
    check("no .part left behind", not [f for f in os.listdir(out) if f.endswith(".part")])
    check("usage error without a dir", subprocess.run([sys.executable, GEN], capture_output=True).returncode == 2)

sys.exit(1 if fails else 0)
