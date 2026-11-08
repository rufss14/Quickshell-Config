#!/usr/bin/env python3
# ── test-wallpaper-depth.py ───────────────────────────────────────────────────
# Tests for wallpaper-depth.py's scoring: where the clock goes and what is cut out. SAFE TO
# RUN: synthetic depth/subject maps with numpy only — no model, no network, no wallpaper.
#
#   python3 scripts/test-wallpaper-depth.py
#
# What is worth pinning is what WallpaperView relies on and would fail silently without:
#   · the clock's box maps to the SAME pixels the cutout is measured on (a screen-fraction box
#     through the cover-crop), or the clock sits where the mask was not measured;
#   · a wallpaper with nothing in front of the clock yields "none", not a blank cutout;
#   · the time is never mostly hidden (MAX_OVERLAP), and a subject alone is enough.
# ─────────────────────────────────────────────────────────────────────────────
import importlib.util
import pathlib
import sys

import numpy as np

spec = importlib.util.spec_from_file_location("wd", pathlib.Path(__file__).with_name("wallpaper-depth.py"))
wd = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wd)

failed = 0


def check(name, ok, detail=""):
    global failed
    print(("ok   " if ok else "FAIL ") + name + ("" if ok else "  " + detail))
    failed += not ok


# ── the box ──────────────────────────────────────────────────────────────────
b = wd.clock_box(0.5, 0.08)
check("centred box", abs(b[0] - 0.3) < 1e-9 and abs(b[2] - 0.4) < 1e-9, str(b))
check("box stays on screen at the right edge", wd.clock_box(0.99, 0.08)[0] + wd.BOX_W <= 1 + 1e-9)
check("box stays on screen at the bottom", wd.clock_box(0.5, 0.99)[1] + wd.BOX_H <= 1 + 1e-9)

# Same aspect: the box is unchanged. Wider image: only x is squeezed toward the centre.
check("same aspect is the identity", wd.box_in_image(b, 16 / 9, 16 / 9) == b)
x, y, w, h = wd.box_in_image((0.0, 0.1, 1.0, 0.2), 32 / 9, 16 / 9)
check("a 2x-wide image shows its middle half", abs(x - 0.25) < 1e-9 and abs(w - 0.5) < 1e-9 and y == 0.1, f"{x} {w}")
x, y, w, h = wd.box_in_image((0.1, 0.0, 0.2, 1.0), 16 / 18, 16 / 9)
check("a taller image shows its middle band", abs(y - 0.25) < 1e-9 and abs(h - 0.5) < 1e-9 and x == 0.1, f"{y} {h}")

# ── the screen's share of the picture ────────────────────────────────────────
check("a 16:9 picture on a 16:9 screen is whole", wd.cover_box((3840, 2160), 16 / 9) == (0, 0, 3840, 2160))
l, t, r, b = wd.cover_box((3840, 2160), 21 / 9)
check("an ultrawide screen shows a centred band", l == 0 and r == 3840 and t == (2160 - b + t) // 2 and abs((r - l) / (b - t) - 21 / 9) < 0.01,
      str((l, t, r, b)))
l, t, r, b = wd.cover_box((3840, 2160), 1.0)
check("a square screen shows a centred column", t == 0 and b == 2160 and abs((r - l) - 2160) <= 1 and l == (3840 - (r - l)) // 2,
      str((l, t, r, b)))

# ── the alpha ────────────────────────────────────────────────────────────────
H, W = 90, 160
flat = np.full((H, W), 0.3, np.float32)
none = np.zeros((H, W), np.float32)
region = wd.slices(wd.box_in_image(wd.clock_box(0.5, 0.08), W / H, W / H), flat.shape)

check("a flat scene has nothing in front", wd.foreground_alpha(flat, none, region).max() == 0)

near = flat.copy()
near[:, : W // 2] = 0.9                       # the left half stands well forward
a = wd.foreground_alpha(near, none, region)
check("something nearer than the plane is cut out", a[:, : W // 4].min() == 1.0 and a[:, 3 * W // 4 :].max() == 0.0)

soft = flat.copy()
soft[:, :20] = 0.3 + (wd.NEAR_FROM + wd.NEAR_TO) / 2               # between the two thresholds, left of the box
check("the edge is soft", 0 < wd.foreground_alpha(soft, none, region)[0, 0] < 1)

subj = none.copy()
subj[:, :20] = 1.0
check("the subject mask is merged in", wd.foreground_alpha(flat, subj, region)[0, 0] == 1.0)

# ── choosing ─────────────────────────────────────────────────────────────────
cx, cy, alpha, overlap, _ = wd.choose(flat, none, W / H, W / H)
check("nothing in front -> overlap under the floor", overlap < wd.MIN_OVERLAP, str(overlap))

# A subject inside the right candidate's box only (x .54..94, the others end at .7): it should win.
subj = none.copy()
subj[: int(H * 0.35), int(W * 0.8) : int(W * 0.9)] = 1.0
cx, cy, alpha, overlap, _ = wd.choose(flat, subj, W / H, W / H)
check("it picks the box the foreground reaches", cx == 0.74, f"{cx} {overlap}")

# A subject covering everything: the time would be hidden, so no candidate is better than
# another by overlap alone — the penalty must make the score fall.
check("a covered clock scores worse than a partly covered one",
      wd.score(0.9, False) < wd.score(wd.TARGET_OVERLAP, False))
check("under the floor scores -1", wd.score(0.0, True) == -1.0)
check("the first candidate wins an exact tie", wd.score(0.2, True) > wd.score(0.2, False))

# ── placing it yourself ──────────────────────────────────────────────────────
check("a placed clock is kept as given", wd.parse_clock("0.5,0.1") == (0.5, 0.1))
x, y = wd.parse_clock("0.0,0.99")
check("a placed clock is kept on screen", abs(x - wd.BOX_W / 2) < 1e-9 and y <= 1 - wd.BOX_H + 0.02 + 1e-9, f"{x} {y}")
try:
    wd.parse_clock("left")
    check("junk is refused", False)
except ValueError:
    check("junk is refused", True)

# Measuring at a spot the foreground does NOT reach reads no overlap there, though another spot has it.
subj = none.copy()
subj[: int(H * 0.35), int(W * 0.8) : int(W * 0.9)] = 1.0
_, _, at_left = wd.measure(flat, subj, W / H, W / H, 0.26, 0.08)
_, _, at_right = wd.measure(flat, subj, W / H, W / H, 0.74, 0.08)
check("a placed clock is judged where it is", at_left == 0 and at_right > wd.MIN_OVERLAP, f"{at_left} {at_right}")

# ── the soft subject edge ────────────────────────────────────────────────────
ramp = np.linspace(0, 1, 101, dtype=np.float32)
t = wd.tighten(ramp)
check("tighten keeps the ends", t[0] == 0 and abs(t[-1] - 1) < 1e-6)
check("tighten is monotonic", bool((np.diff(t) >= -1e-7).all()))
check("tighten is narrower than the model's own edge", float((t > 0.05).sum() - (t > 0.95).sum()) < float((ramp > 0.05).sum() - (ramp > 0.95).sum()))
check("tighten never makes a hard step (a threshold is the stair)", float(np.diff(t).max()) < 0.12, f"{np.diff(t).max()}")
check("a soft subject stays soft in the alpha",
      0 < float(wd.foreground_alpha(flat, np.full((H, W), 0.5, np.float32), region)[0, 0]) < 1)

# ── smoothing the model's stepped contour ────────────────────────────────────
yy, xx = np.mgrid[0:200, 0:300]
# A slanted edge sampled on a 4 px grid, lightly interpolated: what the model's 1024 px output is
# once it is stretched to a 4K wallpaper.
grid = np.where(((xx // 4) * 0.9 + (yy // 4) * 2.1) > 60, 1.0, 0.0).astype(np.float32)
upscaled = wd.box_blur(grid, 1)


def wobble(a):
    """Mean sideways distance (px) of the 0.5 contour from the straight line through it."""
    xs = []
    for y in range(40, 160):
        r = a[y]
        i = int(np.argmax(r >= 0.5))
        if i > 0:
            xs.append(i - 1 + (0.5 - r[i - 1]) / (r[i] - r[i - 1] + 1e-9))
    xs = np.array(xs)
    fit = np.polyval(np.polyfit(np.arange(len(xs)), xs, 1), np.arange(len(xs)))
    return float(np.abs(xs - fit).mean())


w_tight, w_smooth = wobble(wd.tighten(upscaled)), wobble(wd.tighten(wd.smooth(upscaled)))
check("tightening alone leaves the stairs (the first attempt)", w_tight > 1.5, f"{w_tight:.2f}px")
check("smoothing first more than halves the wobble", w_smooth < 0.5 * w_tight, f"{w_smooth:.2f} vs {w_tight:.2f}px")
flat_in = np.full((40, 40), 0.7, np.float32)
check("smoothing leaves a flat field alone", float(np.abs(wd.smooth(flat_in) - 0.7).max()) < 1e-5)
half = np.zeros((60, 60), np.float32); half[:, 30:] = 1.0
sm = wd.smooth(half)
cross = int(np.argmax(sm[30] >= 0.5))
check("smoothing keeps a straight edge where it was", abs(cross - 30) <= 1, str(cross))
check("smoothing keeps the mean", abs(float(wd.smooth(half).mean()) - float(half.mean())) < 0.01)
check("smoothed then tightened stays within 0..1", 0.0 <= float(wd.tighten(sm).min()) and float(wd.tighten(sm).max()) <= 1.0)

# ── readable spots ───────────────────────────────────────────────────────────
check("calm and clearly light is the most legible", wd.legibility(0.9, 0.0) > wd.legibility(0.5, 0.0))
check("busy is less legible than calm", wd.legibility(0.9, 0.2) < wd.legibility(0.9, 0.01))
check("legibility stays inside its weights", 0 <= wd.legibility(0.5, 1.0) <= wd.LEGIBLE_WEIGHT + wd.TONE_WEIGHT)
check("a higher row costs", wd.score(0.2, False, row=1) < wd.score(0.2, False, row=0))
check("legibility lifts a score", wd.score(0.2, False, ground=0.3) > wd.score(0.2, False))

# Two spots with the SAME amount of foreground (a patch in the left box only, the same patch in the
# right box only): without the picture's brightness the earlier one (left) wins an exact tie; with it, the
# one whose ground is calm wins when the left one is busy.
twin = none.copy()
twin[: int(H * 0.30), int(W * 0.10) : int(W * 0.20)] = 1.0     # inside x .06..46 only
twin[: int(H * 0.30), int(W * 0.80) : int(W * 0.90)] = 1.0     # inside x .54..94 only
calm = np.full((H, W), 0.92, np.float32)
busy_left = calm.copy()
busy_left[:, : int(W * 0.5)] = np.random.default_rng(1).uniform(0.2, 0.9, (H, int(W * 0.5)))
cx_plain, *_ = wd.choose(flat, twin, W / H, W / H)
cx_busy, *_ = wd.choose(flat, twin, W / H, W / H, busy_left)
cx_calm, *_ = wd.choose(flat, twin, W / H, W / H, calm)
check("without luma an exact tie goes to the earlier spot", cx_plain == 0.26, str(cx_plain))
check("a busy left ground sends the clock to the calm right one", cx_busy == 0.74, str(cx_busy))
check("two calm grounds are still a tie", cx_calm == 0.26, str(cx_calm))

# ── the service and the script agree on the format ───────────────────────────
import re
svc = (pathlib.Path(__file__).resolve().parent.parent / "services" / "WallpaperDepth.qml").read_text()
m = re.search(r"formatWanted:\s*(\d+)", svc)
check("WallpaperDepth.formatWanted matches the script's FORMAT", bool(m) and int(m.group(1)) == wd.FORMAT,
      f"service {m.group(1) if m else None} vs script {wd.FORMAT}")

# ── keeping the masks you came from ──────────────────────────────────────────
import os, tempfile, time
with tempfile.TemporaryDirectory() as d:
    d = pathlib.Path(d)
    files = []
    for i in range(12):
        f = d / f"m{i}.png"
        f.write_bytes(b"x")
        os.utime(f, (time.time() + i, time.time() + i))     # m11 is the newest
        files.append(f)
    cur = d / "m_new.png"
    cur.write_bytes(b"x")
    gone = wd.prune(files, 8, cur)
    left = sorted(p.name for p in d.iterdir())
    check("prune keeps `keep` files including the current one", len(left) == 8 and "m_new.png" in left, str(left))
    check("prune drops the oldest first", {g.name for g in gone} == {"m0.png", "m1.png", "m2.png", "m3.png", "m4.png"},
          str(sorted(g.name for g in gone)))
    check("prune never deletes the current file", cur.exists())

# ── brightness behind the clock ──────────────────────────────────────────────
rgb = np.full((H, W, 3), 240, np.uint8)
check("light ground reads light", wd.luma_behind(rgb, none, region) > 0.9)
rgb[:] = 20
check("dark ground reads dark", wd.luma_behind(rgb, none, region) < 0.1)
rgb[:, :80] = 255                              # light left half is covered by the cutout, dark right is not
cover = none.copy()
cover[:, :80] = 1.0
check("the covered pixels are not counted", wd.luma_behind(rgb, cover, region) < 0.2)
check("a fully covered box falls back to all of it",
      0.0 <= wd.luma_behind(rgb, np.ones((H, W), np.float32), region) <= 1.0)

print("\n%s" % ("all passed" if not failed else f"{failed} FAILED"))
sys.exit(1 if failed else 0)
