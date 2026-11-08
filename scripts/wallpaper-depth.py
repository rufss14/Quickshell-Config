#!/usr/bin/env python3
"""Depth clock: cut the part of a wallpaper that should sit IN FRONT of the desktop clock.

    wallpaper-depth.py IMAGE --cache DIR --models DIR [--aspect 1.778] [--clock X,Y] [--force]
    wallpaper-depth.py --prepare --models DIR        fetch the two models, nothing else

Prints ONE json line, which services/WallpaperDepth reads:

    {"state": "ready", "cutout": "<png>", "x": 0.74, "y": 0.08, "overlap": 0.249, "luma": 0.83, "image": ..., "aspect": ...}
    {"state": "none",  "x": ..., "y": ..., "overlap": 0.0, ...}       nothing in front of the clock

`--clock X,Y` puts the clock there (centre x, top y, screen fractions) instead of choosing; the
mask is then measured against THAT spot. `state: "none"` still carries x/y/luma, so the shell can draw
the clock plainly on a picture with nothing in front of it.

`cutout` is a MASK, not a picture: a grey+alpha PNG, cut to the screen's shape (the part of the
wallpaper a screen of --aspect shows), whose alpha is opaque where something is nearer than the scene behind the clock (or is the main subject), clear
elsewhere. WallpaperView hides the clock wherever the mask is opaque. (It used to be the wallpaper's
own pixels, drawn over the clock. Qt scales and premultiplies an image with alpha, so those pixels
never matched the picture under them exactly: a thin outline along the whole subject, and blotches
in the soft zones. A mask duplicates no picture pixels, so there is nothing to mismatch.)
`x`/`y` are the clock's centre and top as fractions of the screen; `luma` is how light the
wallpaper is behind the clock, so the shell can pick text that reads.

── How the mask is made ─────────────────────────────────────────────────────
Two models, both run once per wallpaper and cached (the maps survive a change of screen shape):
  · Depth Anything V2 (small, Apache-2.0): relative depth, normalised 0 far .. 1 near. What is
    nearer than the plane under the clock (its median) by more than NEAR_FROM..NEAR_TO is in front.
  · BiRefNet via rembg: a crisp outline of the main subject, which a depth map blurs. On
    illustrations it is the one that matters; depth adds the foreground (butterflies, props).
The two are merged with max(); the clock position is whichever of CANDIDATES leaves a pleasing
share (TARGET_OVERLAP) of the clock covered without hiding the time (MAX_OVERLAP).

numpy / PIL / onnxruntime / rembg are imported inside the functions that need them, so the
scoring below can be tested with just numpy (scripts/test-wallpaper-depth.py).
"""

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

DEPTH_MODEL = "onnx-community/depth-anything-v2-small"
SUBJECT_MODEL = "birefnet-general"   # handles illustration far better than birefnet-portrait

# Where the clock may go: (centre x, top y) as screen fractions. The first wins a tie.
# A grid of two rows by three columns; the top row is preferred (ROW_COST per row down), and the
# first candidate wins an exact tie.
CANDIDATES = [(0.5, 0.08), (0.26, 0.08), (0.74, 0.08), (0.5, 0.32), (0.26, 0.32), (0.74, 0.32)]
ROW_COST = 0.06
TIE_BONUS = 0.05
# How much the legibility of the text counts in a spot's score. A spot where the picture behind the
# visible digits is calm and clearly light or dark beats one that is busy or mid-grey, at the same
# overlap: dark text on a mid-grey, busy ground is the one that cannot be read.
LEGIBLE_WEIGHT, TONE_WEIGHT = 0.25, 0.15
BUSY_STD = 0.15            # luma spread (0..1) at which a ground counts as fully busy
TONE_SPAN = 0.30           # how far from mid-grey (0.5) counts as fully clear
# The share of the clock's box the foreground should cover, and the most before the time is lost.
TARGET_OVERLAP, MAX_OVERLAP = 0.20, 0.45
# Less than this covered: no depth effect for this wallpaper.
MIN_OVERLAP = 0.01
# A subject mask covering less of the image than this means "no subject".
MIN_SUBJECT = 0.005
# How much nearer than the plane behind the clock something must be to hide it (0..1 depth),
# with a smoothstep between the two so the edge is soft.
NEAR_FROM, NEAR_TO = 0.06, 0.14
# Bumped when the files' meaning changes: a cached answer of another format is made again.
# 5 = the subject is the model's soft output, SMOOTHED then tightened by a curve (4 = tightened only,
# which still stepped; 3 = the screen-shaped mask but of the model's thresholded 0/1 output, a
# staircase; 2 = a grey+alpha mask of the whole picture, 1 = the picture's own pixels with alpha).
FORMAT = 5
# The model works on 1024 px, so its contour is stepped at that grid — about 3.75 px of a 4K wallpaper
# — and any steep curve over it shows the steps. Smoothing the soft map first (three box passes of this
# radius, ~σ 3.5 px: the grid step) turns the steps into a smooth contour, and then this curve tightens
# the edge to ~2–3 px, anti-aliased. Smooth then curve is curvature smoothing: edges stay where they
# were, corners round by about σ. (Measured on a foot's outline: roughness 0.24 → 0.17 against tighten
# alone. A guided filter against the picture was tried instead and haloed: the subject and its
# ground are both near-white.)
SUBJECT_LO, SUBJECT_HI = 0.35, 0.65
SMOOTH_RADIUS, SMOOTH_PASSES = 3, 3
# Placed masks kept per wallpaper and screen shape, newest first. The shell remembers an answer for
# as long as it runs, so a spot you came from must still have its file when you go back to it.
KEEP_PLACED = 8
# The clock's box, matching WallpaperView's DepthClock: 40% of the screen wide, 36% tall.
BOX_W, BOX_H = 0.40, 0.36


def clock_box(cx, cy):
    """The clock's box (x, y, w, h) in screen fractions, kept on screen."""
    x = min(max(cx - BOX_W / 2, 0.0), 1.0 - BOX_W)
    y = min(max(cy - 0.02, 0.0), 1.0 - BOX_H)
    return (x, y, BOX_W, BOX_H)


def box_in_image(box, img_aspect, screen_aspect):
    """Screen-fraction box → image-fraction box. The wallpaper is shown centred and cropped to
    cover (Image.PreserveAspectCrop), so the longer side loses its edges."""
    x, y, w, h = box
    if img_aspect > screen_aspect:                  # wider than the screen: sides cropped
        seen = screen_aspect / img_aspect
        return ((1 - seen) / 2 + x * seen, y, w * seen, h)
    seen = img_aspect / screen_aspect               # taller: top and bottom cropped
    return (x, (1 - seen) / 2 + y * seen, w, h * seen)


def slices(box, shape):
    h, w = shape[:2]
    x, y, bw, bh = box
    return (slice(int(y * h), max(int((y + bh) * h), int(y * h) + 1)),
            slice(int(x * w), max(int((x + bw) * w), int(x * w) + 1)))


def foreground_alpha(depth, subject, region):
    """Alpha (0..1) of what stands in front of the plane under `region`, plus the subject."""
    import numpy as np
    plane = float(np.median(depth[region]))
    t = np.clip((depth - plane - NEAR_FROM) / (NEAR_TO - NEAR_FROM), 0.0, 1.0)
    return np.maximum(t * t * (3 - 2 * t), tighten(subject))


def box_blur(x, r):
    """Mean over a (2r+1)² window, edges clamped, by cumulative sums: O(pixels) whatever r is."""
    import numpy as np
    k = 2 * r + 1
    p = np.pad(x.astype(np.float64), ((r + 1, r), (r + 1, r)), mode="edge")
    c = p.cumsum(0).cumsum(1)
    return ((c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]) / (k * k)).astype(np.float32)


def smooth(x, radius=SMOOTH_RADIUS, passes=SMOOTH_PASSES):
    """Three box passes ≈ a gaussian (σ ≈ 3.5 px at radius 3), with no dependency beyond numpy."""
    for _ in range(passes):
        x = box_blur(x, radius)
    return x


def tighten(x):
    """A smoothstep over SUBJECT_LO..SUBJECT_HI: the soft model output, with an edge about as wide as
    anti-aliasing. Soft in, soft out: there is no point at which a pixel is cut to 0 or 1."""
    import numpy as np
    t = np.clip((x - SUBJECT_LO) / (SUBJECT_HI - SUBJECT_LO), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def legibility(mean, std):
    """0..1 for how readable text over a ground of this mean and spread of luma will be: calm
    (low std) and clearly light or dark (far from 0.5) is 1."""
    calm = 1.0 - min(1.0, std / BUSY_STD)
    clear = min(1.0, abs(mean - 0.5) / TONE_SPAN)
    return LEGIBLE_WEIGHT * calm + TONE_WEIGHT * clear


def score(overlap, is_first, row=0, ground=0.0):
    """How good a spot is: near the target overlap, never hiding the time, readable, and high up."""
    if overlap < MIN_OVERLAP:
        return -1.0
    return (1 - abs(overlap - TARGET_OVERLAP) - 3 * max(0.0, overlap - MAX_OVERLAP)
            + ground - ROW_COST * row + (TIE_BONUS if is_first else 0.0))


def measure(depth, subject, img_aspect, screen_aspect, cx, cy):
    """Clock at (cx, cy): its box in the image, the alpha measured against that spot, how much
    of the box the foreground covers."""
    region = slices(box_in_image(clock_box(cx, cy), img_aspect, screen_aspect), depth.shape)
    alpha = foreground_alpha(depth, subject, region)
    return region, alpha, float(alpha[region].mean())


def choose(depth, subject, img_aspect, screen_aspect, luma=None):
    """The best candidate: (centre x, top y, alpha, overlap, region). With `luma` (the picture's
    own brightness, same shape as the maps) a spot is also judged on how readable text would be
    on the part of it that stays visible."""
    best = None
    rows = sorted({cy for _, cy in CANDIDATES})
    for i, (cx, cy) in enumerate(CANDIDATES):
        region, alpha, overlap = measure(depth, subject, img_aspect, screen_aspect, cx, cy)
        ground = 0.0
        if luma is not None and overlap >= MIN_OVERLAP:
            mean, std = luma_stats(luma, alpha, region)
            ground = legibility(mean, std)
        s = score(overlap, i == 0, rows.index(cy), ground)
        if best is None or s > best[0]:
            best = (s, cx, cy, alpha, overlap, region)
    return best[1:]


def cover_box(size, aspect):
    """(left, top, right, bottom) of the part of an image of `size` that a screen of `aspect`
    shows when it covers it centred — the same crop Image.PreserveAspectCrop makes."""
    w, h = size
    if w / h > aspect:                       # wider than the screen: the sides go
        cw = round(h * aspect)
        left = (w - cw) // 2
        return (left, 0, left + cw, h)
    ch = round(w / aspect)                   # taller: the top and bottom go
    top = (h - ch) // 2
    return (0, top, w, top + ch)


def prune(files, keep, current):
    """Delete all but the `keep` newest of `files` (paths), never `current`. Returns what it deleted."""
    others = sorted((f for f in files if f != current), key=lambda f: f.stat().st_mtime, reverse=True)
    gone = others[max(keep - 1, 0):]
    for f in gone:
        f.unlink(missing_ok=True)
    return gone


def parse_clock(text):
    """'X,Y' → (x, y) kept where the whole box stays on screen. ValueError when it isn't two numbers."""
    x, y = (float(v) for v in text.split(","))
    return (min(max(x, BOX_W / 2), 1 - BOX_W / 2), min(max(y, 0.0), 1 - BOX_H + 0.02))


# ── models ───────────────────────────────────────────────────────────────────

def _providers():
    import onnxruntime as ort
    have = ort.get_available_providers()
    return [p for p in ("CUDAExecutionProvider", "CPUExecutionProvider") if p in have]


def run_depth(image):
    """Relative depth at the image's size, 0 far .. 1 near."""
    import numpy as np
    import onnxruntime as ort
    from huggingface_hub import hf_hub_download
    from PIL import Image

    session = ort.InferenceSession(hf_hub_download(DEPTH_MODEL, "onnx/model.onnx"), providers=_providers())
    # Long side ~1022 px, both sides a multiple of the model's 14 px patch.
    k = 1022 / max(image.size)
    size = (round(image.width * k / 14) * 14, round(image.height * k / 14) * 14)
    x = np.asarray(image.resize(size, Image.BICUBIC), dtype=np.float32) / 255
    x = ((x - [0.485, 0.456, 0.406]) / [0.229, 0.224, 0.225]).transpose(2, 0, 1)[None].astype(np.float32)
    d = session.run(None, {session.get_inputs()[0].name: x})[0][0]
    lo, hi = np.percentile(d, [2, 98])
    d = np.clip((d - lo) / (hi - lo + 1e-6), 0, 1).astype(np.float32)
    return np.asarray(Image.fromarray(d, mode="F").resize(image.size, Image.BICUBIC))


def run_subject(image):
    """The main subject's SOFT, SMOOTHED mask, 0..1 (all zeros when there isn't one). Not rembg's
    post_process_mask: that thresholds to 0/1 at the model's own 1024 px, which stretched to a 4K
    wallpaper is a staircase along every edge (measured: the old map held exactly two values)."""
    import numpy as np
    from rembg import new_session, remove

    try:
        session = new_session(SUBJECT_MODEL, providers=_providers())
        mask = remove(image, session=session, only_mask=True, post_process_mask=False)
    except Exception:   # e.g. out of VRAM: BiRefNet is big. The CPU always works.
        session = new_session(SUBJECT_MODEL, providers=["CPUExecutionProvider"])
        mask = remove(image, session=session, only_mask=True, post_process_mask=False)
    m = np.asarray(mask, dtype=np.float32) / 255
    return smooth(m) if m.mean() >= MIN_SUBJECT else np.zeros_like(m)


def cached_map(path, compute, image):
    """A 0..1 map kept as a 16-bit PNG, computed on a miss."""
    import numpy as np
    from PIL import Image
    if path.exists():
        return np.asarray(Image.open(path), dtype=np.float32) / 65535
    m = compute(image)
    Image.fromarray((m * 65535).astype(np.uint16)).save(path)
    return m


def luma_image(rgb):
    """Rec. 709 weights on the stored values, 0..1, one number per pixel — plenty to choose
    between dark text and light text."""
    import numpy as np
    px = rgb.astype(np.float32) / 255
    return px[..., 0] * 0.2126 + px[..., 1] * 0.7152 + px[..., 2] * 0.0722


def luma_stats(luma, alpha, region):
    """(mean, spread) of the picture's brightness where the clock's text will show: the pixels in
    its box that the foreground does NOT cover."""
    import numpy as np
    free = alpha[region] < 0.5
    if free.mean() < 0.02:
        free = np.ones_like(free)
    y = luma[region][free]
    return float(y.mean()), float(y.std())


def luma_behind(rgb, alpha, region):
    """How light the wallpaper is behind the clock's visible text (see luma_stats)."""
    return luma_stats(luma_image(rgb), alpha, region)[0]


# ── main ─────────────────────────────────────────────────────────────────────

def emit(args, result):
    """The one json line. It names the question it answers (the image exactly as given, the
    aspect and the clock as asked for), so the shell can match an answer to its job whatever order its pipes close in."""
    print(json.dumps({**result, "image": str(args.image), "aspect": round(args.aspect, 3),
                      "clock": args.clock or ""}))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("image", nargs="?", type=Path)
    ap.add_argument("--cache", type=Path, help="where results live")
    ap.add_argument("--models", type=Path, required=True, help="where the models live")
    ap.add_argument("--aspect", type=float, default=16 / 9, help="the screen's width/height")
    ap.add_argument("--clock", help="put the clock at 'X,Y' (centre x, top y, screen fractions)")
    ap.add_argument("--force", action="store_true", help="ignore what is cached")
    ap.add_argument("--prepare", action="store_true", help="only fetch the models")
    args = ap.parse_args()

    # Models stay under --models, never in the home directory's dotfiles.
    os.environ.setdefault("HF_HOME", str(args.models / "hf"))
    os.environ.setdefault("U2NET_HOME", str(args.models / "u2net"))

    if args.prepare:
        from huggingface_hub import hf_hub_download
        from rembg.sessions import sessions
        hf_hub_download(DEPTH_MODEL, "onnx/model.onnx")
        sessions[SUBJECT_MODEL].download_models()
        print("models ready")
        return
    if args.image is None or args.cache is None:
        ap.error("IMAGE and --cache are required (unless --prepare)")

    wall = args.image.expanduser().resolve()
    if not wall.is_file():
        sys.exit(f"not a file: {wall}")
    args.cache.mkdir(parents=True, exist_ok=True)

    try:
        manual = parse_clock(args.clock) if args.clock else None
    except ValueError:
        sys.exit(f"--clock wants 'X,Y', got {args.clock!r}")

    key = hashlib.sha1(str(wall).encode()).hexdigest()[:20]
    base = args.cache / key
    stamp = f"{wall.stat().st_mtime_ns}"
    # A placed clock has its own slot, replaced on each move: a drag shouldn't leave a 10 MB
    # cutout behind for every spot it passed over.
    name = f"{key}-{args.aspect:.3f}" + ("-placed" if manual else "")
    done = args.cache / f"{name}.json"
    # The subject map is `.subject3.png`: `.subject.png` held the model's thresholded output and
    # `.subject2.png` its soft output unsmoothed (see run_subject), and a map of one kind must never be
    # read as another. The depth map is unchanged.
    maps = (base.with_suffix(".depth.png"), base.with_suffix(".subject3.png"))
    for old in (".subject.png", ".subject2.png"):
        base.with_suffix(old).unlink(missing_ok=True)
    stampfile = base.with_suffix(".stamp")

    # A wallpaper edited in place (same path, new pixels) must not keep its old cutout.
    if stampfile.exists() and stampfile.read_text() != stamp:
        args.force = True
    if args.force:
        for stale in (*maps, *args.cache.glob(f"{key}-*")):
            stale.unlink(missing_ok=True)
    if done.exists():
        cached = json.loads(done.read_text())
        # An answer is only good if it is of this format, is for the spot asked, and its file is still there.
        usable = (cached.get("fmt") == FORMAT
                  and (manual is None or cached.get("placed") == list(manual))
                  and (cached.get("state") != "ready" or Path(cached.get("cutout", "")).is_file()))
        if usable:
            emit(args, cached)
            return

    import numpy as np
    from PIL import Image

    image = Image.open(wall).convert("RGB")
    depth = cached_map(maps[0], run_depth, image)
    subject = cached_map(maps[1], run_subject, image)
    stampfile.write_text(stamp)

    img_aspect = image.width / image.height
    luma = luma_image(np.asarray(image))
    if manual:
        cx, cy = manual
        region, alpha, overlap = measure(depth, subject, img_aspect, args.aspect, cx, cy)
    else:
        cx, cy, alpha, overlap, region = choose(depth, subject, img_aspect, args.aspect, luma)
    mean, spread = luma_stats(luma, alpha, region)
    result = {"fmt": FORMAT, "x": cx, "y": cy, "overlap": round(overlap, 4),
              "luma": round(mean, 3), "spread": round(spread, 3)}
    if manual:
        result["placed"] = list(manual)
    if overlap < MIN_OVERLAP:
        result["state"] = "none"
    else:
        # Cut to what the screen shows, so the shell maps it onto the screen with no framing maths.
        shows = cover_box(image.size, args.aspect)
        cover = Image.fromarray((alpha * 255).astype(np.uint8)).crop(shows)
        cut = Image.merge("LA", (Image.new("L", cover.size, 255), cover))
        # A placed mask is named for its spot: the shell caches decoded images by path, and a
        # new picture under an old name would keep showing the old one. The last few are kept, not
        # just the newest (see KEEP_PLACED).
        # The format is in the name too, so a mask of an older format is never mistaken for this one
        # (the shell caches decoded images by path), and the old file can simply be deleted.
        out = args.cache / (f"{name}-f{FORMAT}-{cx:.3f}x{cy:.3f}.png" if manual else f"{name}-f{FORMAT}.png")
        if not manual:
            (args.cache / f"{name}.png").unlink(missing_ok=True)      # the format-1/2 file
        if manual:
            prune([f for f in args.cache.glob(f"{name}-*.png") if not f.name.endswith(".tmp.png")], KEEP_PLACED, out)
        tmp = out.with_suffix(".tmp.png")
        cut.save(tmp, compress_level=3)
        tmp.replace(out)          # never show a half-written mask
        result.update(state="ready", cutout=str(out))
    done.write_text(json.dumps(result))
    emit(args, result)


if __name__ == "__main__":
    main()
