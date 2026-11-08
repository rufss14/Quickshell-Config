#!/usr/bin/env python3
"""bench-rhythm.py — scores scripts/music-pulse.py's rhythm engine on synthetic songs whose
every hit is known (scripts/synthkit.py), against the older immediate detector.

    python3 scripts/bench-rhythm.py            (a table; exit 0)
    python3 scripts/bench-rhythm.py --check    (exit 1 if a floor in FLOORS isn't met)

Why (2026-10-31): the user asked for "a complex and reliable system" after the effects kept
missing kicks, ringing on every clap and landing off the beat. Tuning on real recordings had no
ground truth — on a dense J-core track neither detector's kicks sat within 23 ms of any grid.
Here every kick, backbeat snare and ghost hit has a known time, at four tempos and three levels.

Scores: kick recall / precision (an event within MATCH_S of a true onset), the mean timing error
of matched kicks, ring precision / recall (the engine's "back" snares against the true backbeat),
ghost rings (a ring on a hit that isn't the backbeat), and whether a drop event came within one
beat of the true drop.
"""
import importlib.util
import os
import sys

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import synthkit as sk  # noqa: E402

spec = importlib.util.spec_from_file_location("music_pulse", os.path.join(here, "music-pulse.py"))
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)

MATCH_S = 0.030
SONGS = ("edm128", "phonk130", "jcore174", "hiphop90")
GAINS = (1.0, 0.4, 0.12)
# The engine must meet these on every song and level (the --check gate), set 2026-10-31 a little
# under what it measured then, to catch regressions. PHONK is the known weak case and has its own:
# its synthetic 808 notes rise out of near-silence at full flux while overlapping 808 tails shrink
# the kicks' attack, so the 808s sound the bigger "kick" and phase the grid onto the off-beat.
FLOORS = {"kick_recall": 0.90, "kick_precision": 0.85, "ring_precision": 0.95, "ring_recall": 0.55,
          "timing_ms": 8.0}
SONG_FLOORS = {"phonk130": {"kick_recall": 0.55, "kick_precision": 0.45, "ring_precision": 0.0,
                            "ring_recall": 0.0, "timing_ms": 8.0}}


def matched(found, truth, tol=MATCH_S):
    """(true positives, mean |error| of them) — each truth matched once."""
    used, tp, err = set(), 0, []
    for f in found:
        best, bi = None, None
        for i, t in enumerate(truth):
            if i in used:
                continue
            d = abs(f - t)
            if d <= tol and (best is None or d < best):
                best, bi = d, i
        if bi is not None:
            used.add(bi)
            tp += 1
            err.append(best)
    return tp, (1000 * float(np.mean(err)) if err else 0.0)


def run(x):
    an = mp.Analyzer()
    legacy, last, ev = [], 0, []
    for i in range(0, len(x), mp.HOP):
        for t, st in an.feed(x[i:i + mp.HOP]):
            if st[5] > last:
                legacy.append(t)
                last = st[5]
        for e in an.take_events():
            f = e.split()
            ev.append((float(f[1]), f[2], float(f[3]), float(f[4]), f[5]))
    return legacy, ev


def score(song, gain):
    x, tr = sk.arrangement(song, gain)
    legacy, ev = run(x)
    warm = tr["bar1"] + 4 * 4 * 60.0 / tr["bpm"]          # judged after 4 bars: the engine is learning
    kt = [t for t in tr["kick"] if t >= warm]
    ek = [t for t, k, *_ in ev if k == "kick" and t >= warm - MATCH_S]
    lk = [t for t in legacy if t >= warm - MATCH_S]
    tp, terr = matched(ek, kt)
    ltp, lerr = matched(lk, kt)
    bt = [t for t in tr["back"] if t >= warm]
    rings = [t for t, k, s, h, r in ev if k == "snare" and r == "back" and t >= warm - MATCH_S]
    rtp, _ = matched(rings, bt)
    drops = [t for t, k, *_ in ev if k in ("drop", "return")]
    P = 60.0 / tr["bpm"]
    drop_ok = any(abs(t - tr["drop"]) <= P * 0.6 for t in drops)
    return {
        "kick_recall": tp / max(1, len(kt)), "kick_precision": tp / max(1, len(ek)), "timing_ms": terr,
        "legacy_recall": ltp / max(1, len(kt)), "legacy_precision": ltp / max(1, len(lk)), "legacy_ms": lerr,
        "ring_recall": rtp / max(1, len(bt)), "ring_precision": rtp / max(1, len(rings)),
        "rings": len(rings), "drop": drop_ok, "drops": len(drops),
    }


def main():
    check = "--check" in sys.argv
    bad = []
    print("%-9s %5s | %-21s | %-21s | %-17s | drop" % ("song", "gain", "engine kick R/P ms", "legacy kick R/P ms", "ring R/P (n)"))
    for song in SONGS:
        for g in GAINS:
            s = score(song, g)
            print("%-9s %5.2f | %4.0f%% %4.0f%% %5.1f ms | %4.0f%% %4.0f%% %5.1f ms | %4.0f%% %4.0f%% (%3d) | %s/%d" % (
                song, g, 100 * s["kick_recall"], 100 * s["kick_precision"], s["timing_ms"],
                100 * s["legacy_recall"], 100 * s["legacy_precision"], s["legacy_ms"],
                100 * s["ring_recall"], 100 * s["ring_precision"], s["rings"], "yes" if s["drop"] else "NO", s["drops"]))
            for k, floor in SONG_FLOORS.get(song, FLOORS).items():
                ok = s[k] <= floor if k == "timing_ms" else s[k] >= floor
                if not ok:
                    bad.append("%s@%.2f %s %.3f (floor %.3f)" % (song, g, k, s[k], floor))
            if not s["drop"]:
                bad.append("%s@%.2f no drop" % (song, g))
    if bad:
        print("\n".join(["", "below the floors:"] + bad))
    return 1 if (check and bad) else 0


if __name__ == "__main__":
    sys.exit(main())
