#!/usr/bin/env python3
"""fit-rhythm.py — fits the rhythm engine's kick and snare models (KICK_W/KICK_B, SNARE_W/SNARE_B
in music-pulse.py).

The snare model (same day, the funk track's ring spam): which snare-band hits are THE snare or
clap — trained against the true backbeats — from flux z, sustain, body, air and the snare/kick
rise ratio. Tamborims, cowbells and rimshots are its negatives.

    python3 scripts/fit-rhythm.py [kick] [snare]

Every kick CANDIDATE event (a peak of the kick band's attack or flux — RhythmModel._kick_peaks)
on synthetic songs with known kicks (scripts/synthkit.py: four genres, three levels, two seeds)
is labelled kick (within LABEL_S of a true one) or not (beyond FAR_S), and a logistic model is
fitted on its acoustics: the envelope's jump (dB), the flux z, the click (the 1.5–6 kHz flux z), and the log ratio
of the kick band's rise to the snare band's — each clipped (KICK_CLIP: an 808 from silence
jumps 30+ dB, a hip-hop kick 50, and a linear weight on raw dB can't serve both). Balanced per song and class. Reports leave-one-song-
out recall/precision (each genre scored by a model that never saw it), then the constants to paste.

Why a fitted model (2026-10-31): hand thresholds kept passing one genre and failing another — a
sidechained bass's swell looked like a kick to flux, an 808 note like one to the attack. The
weights are only as good as synthkit's sounds; scripts/bench-rhythm.py checks the result.
"""
import importlib.util
import math
import os
import sys

import numpy as np

here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, here)
import synthkit as sk  # noqa: E402

spec = importlib.util.spec_from_file_location("music_pulse", os.path.join(here, "music-pulse.py"))
mp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mp)

LABEL_S, FAR_S = 0.025, 0.050
HARD_W = 1.0     # tried 5 (2026-10-31): phonk precision up, EDM/hip-hop recall down to 69–75% — off
SONGS = ("edm128", "phonk130", "jcore174", "hiphop90")


def features(c):
    """The model's inputs — music-pulse.py's RhythmModel.kick_features, kept in step with it."""
    return mp.RhythmModel.kick_features(c)


def collect(kind="kick"):
    """(features, label, song) for every `kind` candidate on the synthetic songs. A kick is
    labelled against the true kicks; a snare against the true BACKBEAT (the snare or clap that
    should ring) — every other snare-band hit (tamborims, cowbells, claps doubled on kicks) is a 0."""
    rows = []
    seen = []
    orig = mp.RhythmModel._decide

    def spy(self, k, c, tracker):
        if k == kind:
            seen.append((c["t0"], features(c) if kind == "kick" else mp.RhythmModel.snare_features(c)))
        return orig(self, k, c, tracker)

    mp.RhythmModel._decide = spy
    try:
        for song in SONGS:
            for g in (1.0, 0.4, 0.12):
                for seed in (0, 1):
                    x, tr = sk.arrangement(song, g, seed=seed)
                    seen.clear()
                    an = mp.Analyzer()
                    for i in range(0, len(x), mp.HOP):
                        an.feed(x[i:i + mp.HOP])
                        an.take_events()
                    truth = np.array(tr["kick"] if kind == "kick" else tr["back"])
                    for t0, f in seen:
                        d = float(np.min(np.abs(truth - t0)))
                        if d <= LABEL_S or d >= FAR_S:
                            rows.append((f, 1 if d <= LABEL_S else 0, song))
    finally:
        mp.RhythmModel._decide = orig
    return rows


def fit(X, y, sw, l2=1e-3, it=4000, lr=0.2):
    Xb = np.c_[X, np.ones(len(X))]
    w = np.zeros(Xb.shape[1])
    for _ in range(it):
        p = 1 / (1 + np.exp(-np.clip(Xb @ w, -30, 30)))
        w -= lr * (Xb.T @ ((p - y) * sw) / sw.sum() + l2 * np.r_[w[:-1], 0])
    return w


def balance(y, songs, X=None, kind="kick"):
    """Per song and class, equal weight. Then the HARD negatives — for kicks, rises as strong as a
    kick's (flux z ≥ 4: an 808 note) — count HARD_W times: among thousands of easy bass swells they
    were too few to matter, and the model let 808s through at p ~0.95."""
    w = np.ones(len(y))
    if X is not None and kind == "kick":
        w[(y == 0) & (X[:, 1] >= 4.0)] *= HARD_W
    for s in set(songs):
        for c in (0, 1):
            m = (songs == s) & (y == c)
            w[m] = w[m] / max(1e-9, w[m].sum())
    return w


def model(kind, names):
    rows = collect(kind)
    X = np.array([r[0] for r in rows], float)
    y = np.array([r[1] for r in rows], float)
    songs = np.array([r[2] for r in rows])
    mu, sd = X.mean(0), X.std(0) + 1e-9
    Xs = (X - mu) / sd
    print("%s: %d candidates (%d positive)" % (kind, len(y), int(y.sum())))
    for s in SONGS:
        tr = songs != s
        if (y[~tr] == 1).sum() == 0:
            continue
        w = fit(Xs[tr], y[tr], balance(y[tr], songs[tr], X[tr], kind))
        p = 1 / (1 + np.exp(-(np.c_[Xs[~tr], np.ones((~tr).sum())] @ w)))
        pred, yy = p >= 0.5, y[~tr] == 1
        print("  held out %-9s recall %.2f precision %.2f" % (s, (pred & yy).sum() / max(1, yy.sum()),
                                                            (pred & yy).sum() / max(1, pred.sum())))
    w = fit(Xs, y, balance(y, songs, X, kind))
    wr, br = w[:-1] / sd, w[-1] - float(np.sum(w[:-1] * mu / sd))
    print("%s_W = (%s)" % (names, ", ".join("%.4f" % v for v in wr)))
    print("%s_B = %.4f" % (names, br))


def main():
    which = sys.argv[1:] or ["kick", "snare"]
    if "kick" in which:
        model("kick", "KICK")
    if "snare" in which:
        model("snare", "SNARE")


if __name__ == "__main__":
    main()
