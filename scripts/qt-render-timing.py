#!/usr/bin/env python3
"""qt-render-timing.py — which WINDOW of the shell is rendering, how often, and how long each frame takes.

    scripts/qt-render-timing.py                 30 s after a 15 s settle, your live config
    scripts/qt-render-timing.py --measure 60 --set cavaBg=false
    scripts/qt-render-timing.py --env QSG_RENDERER_DEBUG=render

The top/htop view shows several `QSGRenderThread`s with no names. Qt can say what each one did:
QSG_RENDER_TIMING=1 logs, per window, every frame — the render thread's sync / render / swap times
and the GUI thread's polish / animations / blockedForSync. This runs a THROWAWAY shell with that
switched on (scripts/bench_lib.py: scratch state dir, copy of your config), reads only the slice of
log after the settle, and sums it up per window.

Reading the table:
  fps       frames the window rendered per second. A window that is on screen and "idle" should be ~0;
            one at the display's refresh rate is repainting every frame (the bar's full-screen layer
            surface, a live capture, an animation nobody stopped).
  render ms mean / p95 / max of the render thread's time per frame (sync+render+swap).
  gui ms    mean time per frame on the GUI thread for polish and for animations (the QML animation
            tick) — the part of a repaint that is QML work, not drawing.
  blocked   mean ms the GUI thread waited for the render thread to finish the previous frame.
Windows are listed by fps × render ms (the busiest first) and named by address: the bar's window is the
one with the largest area, i.e. the highest render ms at idle. `--env` passes any extra variable to the
throwaway (QSG_RENDERER_DEBUG, QSG_VISUALIZE draw over the desktop — look at your screen).
"""
import argparse
import collections
import json
import os
import re
import statistics
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_lib as B  # noqa: E402

RENDER = re.compile(r"\[window (0x[0-9a-f]+)\]\[render thread [^\]]*\] syncAndRender: frame rendered in (\d+) ?ms, sync=(\d+), render=(\d+), swap=(\d+)")
PREP = re.compile(r"\[window (0x[0-9a-f]+)\]\[gui thread\] Frame prepared, polish=(\d+) ?ms, lock=(\d+) ?ms, blockedForSync=(\d+) ?ms, animations=(\d+) ?ms")


def pct(vals, p):
    s = sorted(vals)
    return s[min(len(s) - 1, int(len(s) * p))] if s else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--warm", type=float, default=15)
    ap.add_argument("--measure", type=float, default=30)
    ap.add_argument("--set", action="append", default=[], metavar="KEY=JSON")
    ap.add_argument("--env", action="append", default=[], metavar="KEY=VALUE")
    ap.add_argument("--config", help="preferences to start from (default: your live config.json)")
    a = ap.parse_args()

    cfg = B.live_config(a.config)
    for item in a.set:
        k, _, v = item.partition("=")
        cfg[k] = json.loads(v)
    env = {"QSG_RENDER_TIMING": "1"}
    env.update(dict(e.split("=", 1) for e in a.env))

    state = tempfile.mkdtemp(prefix="qs-render-timing-")
    with B.Throwaway(state=state, env=env, config=cfg) as t:
        time.sleep(a.warm)
        start = os.path.getsize(t.log)
        time.sleep(a.measure)
        end = os.path.getsize(t.log)
        with open(t.log, errors="replace") as f:
            f.seek(start)
            text = B.ANSI.sub("", f.read(end - start))

    render = collections.defaultdict(list)       # window → [(total, sync, render, swap)]
    gui = collections.defaultdict(list)          # window → [(polish, blocked, animations)]
    for m in RENDER.finditer(text):
        render[m.group(1)].append(tuple(int(m.group(i)) for i in (2, 3, 4, 5)))
    for m in PREP.finditer(text):
        gui[m.group(1)].append((int(m.group(2)), int(m.group(4)), int(m.group(5))))
    if not render:
        sys.exit("qt-render-timing: no scene-graph timing lines in the log — Qt build without them, or the shell did not start (see %s)" % t.log)

    rows = []
    for w, fr in render.items():
        tot = [x[0] for x in fr]
        g = gui.get(w, [])
        rows.append((len(fr) / a.measure * statistics.mean(tot or [0]), w, len(fr) / a.measure, tot, fr, g))
    rows.sort(reverse=True)
    print(f"{'window':<16} {'fps':>6}  {'render ms mean / p95 / max':<28} {'sync':>5} {'draw':>5} {'swap':>5}  {'gui polish':>10} {'animations':>10} {'blocked':>8}")
    for _, w, fps, tot, fr, g in rows:
        mean = lambda i, rs: statistics.mean([r[i] for r in rs]) if rs else 0
        print(f"{w:<16} {fps:6.1f}  {statistics.mean(tot):6.2f} / {pct(tot, .95):4d} / {max(tot):4d}      "
              f"{mean(1, fr):5.2f} {mean(2, fr):5.2f} {mean(3, fr):5.2f}  {mean(0, g):10.2f} {mean(2, g):10.2f} {mean(1, g):8.2f}")
    print(f"\n{len(rows)} windows rendered in {a.measure:.0f} s (settled {a.warm:.0f} s first). Whole-ms resolution: a mean under 0.5 reads as 0.")


if __name__ == "__main__":
    main()
