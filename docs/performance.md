# Performance tools

How to find out what the shell costs and whether a change helped. Written 2026-11-02 after a pass in
which a gdb sampler said the wave visualiser was ~70% of the main thread and a config A/B said ~4 points:
**measure with the tool that counts, not the one that points.**

Everything here runs a THROWAWAY shell (`scripts/bench_lib.py`): its own `XDG_STATE_HOME` holding a copy of
your live `config.json`, so preferences, scores and history it writes never reach the real state. It still
shares the session — its windows appear over the desktop and it runs its own helpers while it lives — so
run these with the desktop otherwise idle. Never aimed at the live shell, which is never killed.

| Question | Tool |
|---|---|
| Did my change make it cheaper? | `scripts/bench-ab.py` |
| What does the running shell cost right now? | `scripts/shell-cost.py`, or `qs ipc call framewatch cost` |
| Which window is rendering, how often, how long per frame? | `scripts/qt-render-timing.py` |
| Where in C++ (GC, scene graph, QML engine) is the time? | `scripts/perf-record.sh` (needs `perf`) |
| Which QML expression is running? | `sudo bash scripts/profile-qml.sh` (gdb; biased, see below) |
| What can wake the shell every frame, and what stops it? | `scripts/check-qml-hotpaths.py` |
| Late frames, and what was happening | `qs ipc call framewatch start` (existing) |

## bench-ab.py

```
scripts/bench-ab.py base nowave,cavaBg=false                # a preference
scripts/bench-ab.py --rounds 7 new old,ref=HEAD~1            # committed code at a ref vs this working tree
scripts/bench-ab.py --set wallFx=false --warm 25 --measure 45 a b,wpeFps=30
```

Variants alternate in a rotated order each round; the table is the median and min–max per variant. **The
spread between rounds of one variant is the size of difference you cannot trust** — 5+ rounds before
believing anything under ~3 points. The audio state is read at both ends of a round and a changed round is
dropped; the tool plays nothing, so put the same thing on (or off) before you start. `ref=` runs the
committed code (git archive), not uncommitted edits: commit or `tree=` a copy to compare work in progress.
`gpu` is the SHELL's own gfx-engine time from `/proc/PID/fdinfo` (amdgpu, intel); `card%` is the whole card.

## qt-render-timing.py

Runs the throwaway with `QSG_RENDER_TIMING=1` and sums the slice of log after the settle, per window:
fps, render-thread ms (sync / draw / swap) and GUI-thread polish / animations / blockedForSync. Reading it:
**`swap` is mostly waiting for the compositor/vsync, not work** — a window at 34 fps with 9 ms of swap and
0.9 ms of draw is cheap. The busiest windows by fps × render ms are listed first. `--env QSG_VISUALIZE=changes`
(or `overdraw`, `batches`) draws over the desktop: look at your screen.

First reading (2026-11-02, music off, wpeFps 60): 5 windows; the two busiest rendered ~34 fps at ~10 ms
(nearly all swap), the rest 7–12 fps.

## perf-record.sh

`perf record -g` of a throwaway started as perf's own child (no root, no ptrace_scope). The kernel samples,
nothing stops the shell. Names Qt/QML C++ functions (QV4::, QQuick…, GC) but not QML lines. **Written
without `perf` installed — untested**; `sudo pacman -S perf` first. Say if it needs fixing.

## shell-cost.py / `framewatch cost`

`gui` is the main thread (every binding, handler and animation tick), `render` the QSGRenderThreads
summed, `other` the rest, `helpers` the shell's child processes (cava, music-pulse.py, wl-paste…),
`gpu` its own GPU time. The wallpaper renderer is detached, so it is not in `helpers`: `top` it yourself.

## check-qml-hotpaths.py

Lists every FrameAnimation, repeating Timer ≤ 33 ms, `onFrameSwapped` and `Animation.Infinite` with the
`running:` that stops it; UNGATED = no gate, or `true`. `check-all.sh` fails on any UNGATED one. A spring
started and stopped by hand counts as gated, and so does `running: true` with a non-literal `paused:`
(`CookieCover`'s turn, paused so it resumes where it stopped).

## What the first pass found (2026-11-02, music playing, 1080p@165)

Config A/B, GUI-thread points: wave visualiser ≈ 4, `wallFx` ≈ 4, cookies ≈ 3.5, `wpePreload` ≈ 0; the
floor with all of those off was ≈ 18% GUI + 20% render, **unattributed** (the bar's full-screen layer
surface is the suspect — an old note, not confirmed; `qt-render-timing.py` is how to confirm it). Helpers
outside the shell: `music-pulse.py` ≈ 11% of a core, three cava ≈ 2–4% each. GC ≈ 7% of main-thread
samples with `QV4_GC_TIMELIMIT=0`. Cold start: Configuration Loaded at 3.2 s, no startup burst.

## Why gdb sampling misleads (scripts/profile-qml.sh)

It stops the thread at a moment it chooses, so time spent in code that runs inside a long synchronous
handler (a `bars` assignment fanning out to bindings) is credited to that handler, and the first ~20 samples
fail until the engine pointer is found. Good for "which expression", wrong for "how much". Use it to NAME a
suspect, then settle the size with bench-ab.py. Rootless form: `QSP_RUN=1 gdb -batch -x scripts/profile-qml.py
--args quickshell -p REPO` with a scratch `XDG_STATE_HOME` (the script kills its own throwaway).
