#!/usr/bin/env python3
"""clips-lib.py — the clip library behind services/Clips.qml.

    scripts/clips-lib.py index  <dir> <cachedir> [limit]   # JSON list, newest first
    scripts/clips-lib.py strip  <file> <cachedir> <n>      # JSON list of frame paths
    scripts/clips-lib.py trim   <file> <start> <end>       # prints the new file's path
    scripts/clips-lib.py headtrim <file> <keep-seconds>    # cut the START off, in place; prints the path
    scripts/clips-lib.py size   <dir> <since-ms> [file]    # bytes of the recording in progress
    scripts/clips-lib.py rename <file> <new name>          # prints the new file's path
    scripts/clips-lib.py export <file> <start> <end> <json-options>
                                   # streams "progress <0..1>", ends "done <path>"
    scripts/clips-lib.py frame  <file> <seconds>           # prints the saved PNG's path

── What it does and doesn't do ──────────────────────────────────────────────────
The shell can't decode video (no QtMultimedia here, and a missing QML module would
take down every file that imports it). So everything that needs to LOOK INSIDE a
clip is ffprobe/ffmpeg, here: its duration and size, a thumbnail, a filmstrip for
the trimmer. Playback is the user's own player (`gio open`), deletion is `gio trash`
from QML — neither needs this.

── The cache ───────────────────────────────────────────────────────────────────
<cachedir>/meta.json maps a key — a hash of path, size and mtime — to what ffprobe
said, and <cachedir>/thumbs/<key>.jpg is its thumbnail. A clip that changes gets a
new key, so nothing is ever stale; keys no clip has any more are pruned on each
index. A file ffprobe can't read (a recording still being written: mp4 writes its
index last) is listed with `ok: false` and NOT cached, so the next index tries again.

── Head-trim is the one in-place edit ───────────────────────────────────────────
"Clip it + N more seconds" saves the next signal length up (the recorder can only cut a few) and
needs the file to be what was asked for: `headtrim` keeps the last <keep> seconds as a stream
copy and swaps it over the original (temp + rename). It is used ONLY on a file the shell asked the
recorder to write seconds ago and nobody has been shown; everything the user does to a clip
(trim, export, rename) still never overwrites. The cut starts on the keyframe at or before the
point, so the result is a touch long, never short. A file already that short is left alone.

── Trim and rename never overwrite ─────────────────────────────────────────────
A trim writes `<name>-trim.<ext>` beside the original (then -trim-2, -3…), the
annotator's `-edited` rule. The cut is a stream copy: instant and lossless, but it
starts on the keyframe at or before `start` (the recorder puts one every 2s by
default). A rename refuses a name that's taken, a path, or a dot-file.

── Export: the editor's one command ─────────────────────────────────────────────
`export_plan()` turns the editor's options into ONE ffmpeg argv, and is pure so
the test can pin it without running ffmpeg:
  precise   false = a stream copy (instant, lossless, keyframe-snapped start);
            true  = re-encoded, frame-exact. Any option below that changes the
            picture or the size forces a re-encode.
  sizeMB    0 = no target; else a bitrate that lands the file under it (Discord's
            10/25/50 MB) — total bits × 0.92 headroom over the span, less audio.
  height    0 = as recorded; else scaled down to it (never up).
  audio     "mix" (the default: every track mixed into ONE) | "all" (kept as
            separate tracks) | "first" (the desktop track — drops the mic when the
            recorder split them) | "none". Mix is the default because a player,
            a browser and Discord's embed play only the FIRST audio track: with the
            recorder's "Separate tracks" on, anything but a mix loses the voice.
  format    "mp4" | "gif" (15 fps, ≤480px wide, a generated palette; no audio).
Progress comes from ffmpeg's own `-progress pipe:1`, as a fraction of the span.

`python3 scripts/test-clips-lib.py` runs all of it against a generated clip.
"""

import hashlib
import json
import os
import signal
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

EXTS = {".mp4", ".mkv", ".webm", ".mov", ".flv"}
THUMB_W = 480
STRIP_W = 160
NAME_MAX = 180


def key_of(path, st):
    return hashlib.sha1(f"{path}\0{st.st_size}\0{st.st_mtime_ns}".encode()).hexdigest()[:20]


# ── index ────────────────────────────────────────────────────────────────────
def scan(folder, limit):
    """Video files in `folder` and one level below (the recorder's -df puts clips
    in dated folders), newest first."""
    found = []
    root = Path(folder)
    if not root.is_dir():
        return found
    # Not the recorder's own disk buffer (`-replay-storage disk` keeps it in the
    # output folder as gsr-replay-<date>.gsr/): segments, not clips.
    subdirs = [d for d in sorted(root.iterdir())
               if d.is_dir() and not d.name.startswith(".") and not d.name.endswith(".gsr")]
    for base in [root] + subdirs:
        try:
            entries = list(base.iterdir())
        except OSError:
            continue
        for p in entries:
            if p.suffix.lower() not in EXTS or p.name.startswith("."):
                continue
            try:
                st = p.stat()
            except OSError:
                continue
            if p.is_file():
                found.append((p, st))
    found.sort(key=lambda x: x[1].st_mtime_ns, reverse=True)
    return found[:limit]


def probe(path):
    """{duration, width, height} or None when ffprobe can't read it (yet)."""
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0",
                            "-show_entries", "format=duration:stream=width,height",
                            "-of", "json", "--", str(path)],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
        dur = float(d.get("format", {}).get("duration", 0) or 0)
        s = (d.get("streams") or [{}])[0]
        if r.returncode != 0 or dur <= 0:
            return None
        return {"duration": round(dur, 2), "width": int(s.get("width", 0) or 0),
                "height": int(s.get("height", 0) or 0)}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def frame(path, at, out, width):
    """One frame at `at` seconds, scaled to `width`, as a jpg. -ss before -i is a
    keyframe seek: fast, and a thumbnail doesn't need to be exact."""
    tmp = out.with_suffix(".tmp.jpg")
    try:
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{max(0.0, at):.2f}", "-i", str(path),
                            "-frames:v", "1", "-vf", f"scale={width}:-2", "-q:v", "4", str(tmp)],
                           capture_output=True, timeout=20)
        if r.returncode == 0 and tmp.exists() and tmp.stat().st_size > 0:
            os.replace(tmp, out)
            return True
    except (OSError, subprocess.TimeoutExpired):
        pass
    try:
        tmp.unlink()
    except OSError:
        pass
    return False


def cmd_index(folder, cachedir, limit):
    cache = Path(cachedir)
    thumbs = cache / "thumbs"
    thumbs.mkdir(parents=True, exist_ok=True)
    try:
        meta = json.loads((cache / "meta.json").read_text())
        if not isinstance(meta, dict):
            meta = {}
    except (OSError, ValueError):
        meta = {}

    files = scan(folder, limit)

    def one(item):
        p, st = item
        k = key_of(p, st)
        m = meta.get(k) or probe(p)
        thumb = thumbs / f"{k}.jpg"
        if m and not thumb.exists():
            frame(p, min(1.0, m["duration"] * 0.25), thumb, THUMB_W)
        return k, p, st, m, thumb

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(one, files))

    out, keep = [], {}
    for k, p, st, m, thumb in results:
        if m:
            keep[k] = m
        out.append({
            "path": str(p), "name": p.stem, "ext": p.suffix.lstrip(".").lower(),
            "size": st.st_size, "mtime": st.st_mtime_ns // 1_000_000,
            "ok": m is not None,
            "duration": m["duration"] if m else 0,
            "width": m["width"] if m else 0, "height": m["height"] if m else 0,
            "thumb": str(thumb) if thumb.exists() else "",
            "key": k,
        })

    # Prune what no clip has any more: cache entries and their thumbnails and strips.
    tmp = cache / "meta.json.tmp"
    tmp.write_text(json.dumps(keep))
    os.replace(tmp, cache / "meta.json")
    for t in thumbs.glob("*.jpg"):
        if t.stem not in keep:
            try:
                t.unlink()
            except OSError:
                pass
    strips = cache / "strips"
    if strips.is_dir():
        for d in strips.iterdir():
            if d.name not in keep:
                for f in d.glob("*"):
                    f.unlink(missing_ok=True)
                try:
                    d.rmdir()
                except OSError:
                    pass

    print(json.dumps(out))
    return 0


# ── strip: frames for the trimmer ─────────────────────────────────────────────
def cmd_strip(path, cachedir, n):
    p = Path(path)
    n = max(2, min(24, n))
    try:
        st = p.stat()
    except OSError:
        print("[]")
        return 1
    m = probe(p)
    if not m:
        print("[]")
        return 1
    d = Path(cachedir) / "strips" / key_of(p, st)
    d.mkdir(parents=True, exist_ok=True)
    dur = m["duration"]
    # Each frame at the middle of its slice, so the strip reads as the whole clip.
    jobs = [(p, dur * (i + 0.5) / n, d / f"{n}-{i:02d}.jpg", STRIP_W) for i in range(n)]

    def one(job):
        return str(job[2]) if job[2].exists() or frame(*job) else ""

    with ThreadPoolExecutor(max_workers=4) as pool:
        frames = list(pool.map(one, jobs))
    print(json.dumps(frames))
    return 0


# ── trim / rename ────────────────────────────────────────────────────────────
def free_name(folder, stem, ext):
    """`stem.ext`, or stem-2.ext, stem-3.ext… — the first that doesn't exist."""
    cand = folder / f"{stem}{ext}"
    i = 2
    while cand.exists():
        cand = folder / f"{stem}-{i}{ext}"
        i += 1
    return cand


def cmd_trim(path, start, end):
    p = Path(path)
    try:
        a, b = float(start), float(end)
    except ValueError:
        print("Not a time", file=sys.stderr)
        return 2
    if not p.is_file() or not p.is_absolute():
        print("No such clip", file=sys.stderr)
        return 2
    if not (a >= 0 and b - a >= 0.5):
        print("The span is too short", file=sys.stderr)
        return 2
    out = free_name(p.parent, f"{p.stem}-trim", p.suffix)
    r = subprocess.run(["ffmpeg", "-v", "error", "-n", "-ss", f"{a:.2f}", "-to", f"{b:.2f}",
                        "-i", str(p), "-map", "0", "-c", "copy", "-avoid_negative_ts", "make_zero",
                        str(out)], capture_output=True, text=True, timeout=300)
    if r.returncode != 0 or not out.exists():
        out.unlink(missing_ok=True)
        print((r.stderr or "ffmpeg failed").strip().splitlines()[-1], file=sys.stderr)
        return 1
    print(out)
    return 0


def cmd_headtrim(path, keep):
    p = Path(path)
    try:
        k = float(keep)
    except ValueError:
        print("Not a time", file=sys.stderr)
        return 2
    if not p.is_file() or not p.is_absolute() or not (k >= 1):
        print("No such clip", file=sys.stderr)
        return 2
    info = media_info(p)
    if not info:
        print("Can't read that clip", file=sys.stderr)
        return 1
    if info["duration"] <= k + 1.0:          # already that short (or a second over: not worth a re-mux)
        print(p)
        return 0
    tmp = p.with_name(f".{p.stem}.headtrim{p.suffix}")
    r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", f"{info['duration'] - k:.2f}",
                        "-i", str(p), "-map", "0", "-c", "copy", "-avoid_negative_ts", "make_zero",
                        str(tmp)], capture_output=True, text=True, timeout=300)
    if r.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        print((r.stderr or "ffmpeg failed").strip().splitlines()[-1] if (r.stderr or "").strip() else "ffmpeg failed",
              file=sys.stderr)
        return 1
    os.replace(tmp, p)
    print(p)
    return 0


def cmd_size(folder, since_ms, path=""):
    """Bytes of the recording being written: `path` when the recorder was given one (a plain
    recording), else the newest `Video_*`/`*_Video_*` file in `folder` (one level down too) modified
    since `since_ms` — a regular recording started during the buffer, whose name the recorder
    picks. 0 when there is none yet."""
    try:
        since = float(since_ms) / 1000.0
    except ValueError:
        print("Not a time", file=sys.stderr)
        return 2
    best = None
    if path:
        q = Path(path)
        if q.is_absolute() and q.is_file():
            best = q.stat().st_size
    else:
        root = Path(folder)
        if root.is_dir():
            newest = 0.0
            for q in list(root.glob("*")) + list(root.glob("*/*")):
                if q.suffix.lower() not in EXTS or "Video_" not in q.name:
                    continue
                try:
                    st = q.stat()
                except OSError:
                    continue
                if st.st_mtime >= since - 2 and st.st_mtime >= newest:
                    newest, best = st.st_mtime, st.st_size
    print(best or 0)
    return 0


# ── export ───────────────────────────────────────────────────────────────────
SIZE_MAX_MB = 500
HEIGHTS = (0, 360, 480, 720, 1080, 1440)
AUDIO = ("mix", "all", "first", "none")
FORMATS = ("mp4", "gif")
AUDIO_KBPS = 128
GIF_FPS = 15
GIF_MAX_W = 480


def media_info(path):
    """{duration, height, audio (track count)} or None."""
    try:
        r = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                            "format=duration:stream=codec_type,height", "-of", "json", "--", str(path)],
                           capture_output=True, text=True, timeout=15)
        d = json.loads(r.stdout or "{}")
        streams = d.get("streams") or []
        dur = float(d.get("format", {}).get("duration", 0) or 0)
        heights = [int(x.get("height") or 0) for x in streams if x.get("codec_type") == "video"]
        if r.returncode != 0 or dur <= 0 or not heights:
            return None
        return {"duration": dur, "height": heights[0],
                "audio": sum(1 for x in streams if x.get("codec_type") == "audio")}
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return None


def clean_options(o):
    """The editor's options, each checked — they arrive as JSON on argv (the trust
    boundary). Unknown or out-of-range values fall back to the safe default."""
    o = o if isinstance(o, dict) else {}
    try:
        size = int(o.get("sizeMB", 0) or 0)
    except (TypeError, ValueError):
        size = 0
    try:
        height = int(o.get("height", 0) or 0)
    except (TypeError, ValueError):
        height = 0
    return {
        "precise": o.get("precise") is True,
        "sizeMB": size if 0 < size <= SIZE_MAX_MB else 0,
        "height": height if height in HEIGHTS else 0,
        "audio": o.get("audio") if o.get("audio") in AUDIO else "mix",
        "format": o.get("format") if o.get("format") in FORMATS else "mp4",
    }


def export_plan(src, info, a, b, opts, out):
    """The ffmpeg argv for one export (see the header). Pure."""
    span = b - a
    base = ["ffmpeg", "-v", "error", "-nostats", "-progress", "pipe:1", "-n"]
    if opts["format"] == "gif":
        w = GIF_MAX_W if not opts["height"] else -2
        h = -1 if not opts["height"] else min(opts["height"], info["height"])
        scale = f"scale={w}:{h}:flags=lanczos" if opts["height"] else f"scale='min({GIF_MAX_W},iw)':-1:flags=lanczos"
        vf = (f"fps={GIF_FPS},{scale},split[s0][s1];[s0]palettegen=stats_mode=diff[p];"
              f"[s1][p]paletteuse=dither=bayer:bayer_scale=5")
        return base + ["-ss", f"{a:.3f}", "-t", f"{span:.3f}", "-i", src,
                       "-filter_complex", vf, "-loop", "0", out]

    n = info["audio"]
    maps, mix = ["-map", "0:v:0"], []
    if opts["audio"] == "mix" and n > 1:
        # normalize=0: amix otherwise divides every input by the count, and the
        # voice comes out quieter than it was recorded.
        ins = "".join(f"[0:a:{i}]" for i in range(n))
        mix = ["-filter_complex", f"{ins}amix=inputs={n}:duration=longest:normalize=0[mix]"]
        maps += ["-map", "[mix]"]
    elif opts["audio"] in ("mix", "all") and n > 0:
        maps += ["-map", "0:a"]
    elif opts["audio"] == "first" and n > 0:
        maps += ["-map", "0:a:0"]
    tracks = 0 if opts["audio"] == "none" else 1 if opts["audio"] in ("first", "mix") else n
    tracks = min(tracks, n)
    mixing = mix != []

    reencode = opts["precise"] or opts["sizeMB"] > 0 or (0 < opts["height"] < info["height"])
    if not reencode:
        # A stream copy: -ss/-to as INPUT options, snapped to the keyframe before.
        # A mix can't be copied, so then only the audio is encoded.
        codecs = ["-c:v", "copy", "-c:a", "aac", "-b:a", f"{AUDIO_KBPS}k"] if mixing else ["-c", "copy"]
        return base + ["-ss", f"{a:.3f}", "-to", f"{b:.3f}", "-i", src] + mix + maps + \
               codecs + ["-avoid_negative_ts", "make_zero", out]

    v = ["-c:v", "libx264", "-preset", "veryfast", "-pix_fmt", "yuv420p"]
    if opts["sizeMB"] > 0:
        total_kbps = opts["sizeMB"] * 8192 * 0.92 / span
        vk = max(150, int(total_kbps - AUDIO_KBPS * tracks))
        v += ["-b:v", f"{vk}k", "-maxrate", f"{vk}k", "-bufsize", f"{vk * 2}k"]
    else:
        v += ["-crf", "20"]
    if 0 < opts["height"] < info["height"]:
        v += ["-vf", f"scale=-2:{opts['height']}"]
    aud = ["-c:a", "aac", "-b:a", f"{AUDIO_KBPS}k"] if tracks > 0 else []
    # Input seeking is frame-exact when the stream is decoded; -t, not -to, because
    # after an input -ss the output's clock starts at 0.
    return base + ["-ss", f"{a:.3f}", "-t", f"{span:.3f}", "-i", src] + mix + maps + v + aud + \
           ["-movflags", "+faststart", out]


def export_name(p, opts, reencoded):
    if opts["format"] == "gif":
        return free_name(p.parent, p.stem, ".gif")
    return free_name(p.parent, f"{p.stem}-{'edit' if reencoded else 'trim'}", p.suffix)


def cmd_export(path, start, end, opts_json):
    p = Path(path)
    try:
        a, b = float(start), float(end)
        opts = clean_options(json.loads(opts_json))
    except ValueError:
        print("Bad arguments", file=sys.stderr)
        return 2
    if not p.is_file() or not p.is_absolute():
        print("No such clip", file=sys.stderr)
        return 2
    info = media_info(p)
    if not info:
        print("Can't read that clip", file=sys.stderr)
        return 2
    b = min(b, info["duration"])
    if not (a >= 0 and b - a >= 0.5):
        print("The span is too short", file=sys.stderr)
        return 2
    plan = export_plan(str(p), info, a, b, opts, "")
    reencoded = "libx264" in plan
    out = export_name(p, opts, reencoded)
    plan[-1] = str(out)

    proc = subprocess.Popen(plan, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    # Cancelled (the shell kills this runner): take ffmpeg down too, and leave no
    # half-written file behind to be mistaken for an export.
    def cancel(_sig, _frm):
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        out.unlink(missing_ok=True)
        sys.exit(130)
    signal.signal(signal.SIGTERM, cancel)
    signal.signal(signal.SIGINT, cancel)

    span_us = (b - a) * 1e6
    last = -1.0
    for line in proc.stdout:
        k, _, v = line.strip().partition("=")
        if k == "out_time_us" and v.isdigit():
            f = min(1.0, int(v) / span_us)
            if f - last >= 0.01:
                print(f"progress {f:.3f}", flush=True)
                last = f
    err = proc.stderr.read()
    code = proc.wait()
    if code != 0 or not out.exists() or out.stat().st_size == 0:
        out.unlink(missing_ok=True)
        print((err or "ffmpeg failed").strip().splitlines()[-1] if err.strip() else "ffmpeg failed",
              file=sys.stderr)
        return 1
    print(f"done {out}", flush=True)
    return 0


def cmd_frame(path, at):
    """One frame as a PNG beside the clip: `<name>-frame-<m>m<s>s.png`."""
    p = Path(path)
    try:
        t = float(at)
    except ValueError:
        print("Not a time", file=sys.stderr)
        return 2
    if not p.is_file() or not p.is_absolute() or t < 0:
        print("No such clip", file=sys.stderr)
        return 2
    m, sec = divmod(t, 60)
    out = free_name(p.parent, f"{p.stem}-frame-{int(m)}m{sec:04.1f}s", ".png")
    r = subprocess.run(["ffmpeg", "-v", "error", "-n", "-ss", f"{t:.3f}", "-i", str(p),
                        "-frames:v", "1", str(out)], capture_output=True, text=True, timeout=60)
    if r.returncode != 0 or not out.exists():
        out.unlink(missing_ok=True)
        print("Couldn't read a frame there", file=sys.stderr)
        return 1
    print(out)
    return 0


def valid_name(name):
    n = name.strip()
    return (0 < len(n) <= NAME_MAX and "/" not in n and "\0" not in n
            and not n.startswith(".") and n not in (".", ".."))


def cmd_rename(path, name):
    p = Path(path)
    if not p.is_file() or not p.is_absolute():
        print("No such clip", file=sys.stderr)
        return 2
    if not valid_name(name):
        print("Not a usable name", file=sys.stderr)
        return 2
    new = p.with_name(name.strip() + p.suffix)
    if new == p:
        print(p)
        return 0
    if new.exists():
        print("That name is taken", file=sys.stderr)
        return 1
    # link + unlink rather than rename: rename() replaces a file that appeared in
    # between the check and here; link() refuses to.
    try:
        os.link(p, new)
    except FileExistsError:
        print("That name is taken", file=sys.stderr)
        return 1
    except OSError:
        os.rename(p, new)       # a filesystem without hard links
        print(new)
        return 0
    os.unlink(p)
    print(new)
    return 0


def main(argv):
    try:
        cmd = argv[1]
        if cmd == "index":
            return cmd_index(argv[2], argv[3], int(argv[4]) if len(argv) > 4 else 300)
        if cmd == "strip":
            return cmd_strip(argv[2], argv[3], int(argv[4]))
        if cmd == "trim":
            return cmd_trim(argv[2], argv[3], argv[4])
        if cmd == "headtrim":
            return cmd_headtrim(argv[2], argv[3])
        if cmd == "size":
            return cmd_size(argv[2], argv[3], argv[4] if len(argv) > 4 else "")
        if cmd == "rename":
            return cmd_rename(argv[2], argv[3])
        if cmd == "export":
            return cmd_export(argv[2], argv[3], argv[4], argv[5])
        if cmd == "frame":
            return cmd_frame(argv[2], argv[3])
    except (IndexError, ValueError):
        pass
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
