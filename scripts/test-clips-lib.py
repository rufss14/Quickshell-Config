#!/usr/bin/env python3
"""test-clips-lib.py — scripts/clips-lib.py against clips it generates itself.

    python3 scripts/test-clips-lib.py

Safe to run: ffmpeg's own test pattern (lavfi `testsrc`) makes two tiny clips in a
temp dir; nothing outside it is read or written.
"""

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
LIB = HERE / "clips-lib.py"
import importlib.util
spec = importlib.util.spec_from_file_location("clips_lib", LIB)
cl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cl)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL  {name}\n          got  {got!r}\n          want {want!r}")


def run(*args):
    return subprocess.run([sys.executable, str(LIB), *args], capture_output=True, text=True, timeout=120)


def probe_dur(path):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                       capture_output=True, text=True, timeout=30)
    return float(r.stdout.strip() or 0)


def make_clip(path, secs):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", f"testsrc=size=320x180:rate=30:duration={secs}",
                    "-c:v", "libx264", "-g", "30", "-pix_fmt", "yuv420p", str(path)], check=True, timeout=60)


def main():
    tmp = Path(tempfile.mkdtemp(prefix="clips-lib-"))
    lib, cache = tmp / "Clips", tmp / "cache"
    (lib / "2026-09-26").mkdir(parents=True)
    old, new = lib / "Replay_old.mp4", lib / "2026-09-26" / "Replay_new.mp4"
    make_clip(old, 4)
    time.sleep(0.05)
    make_clip(new, 6)
    (lib / "notes.txt").write_text("not a clip")
    (lib / ".hidden.mp4").write_text("")
    (lib / "Broken.mp4").write_bytes(b"\0" * 64)     # a recording still being written
    # The recorder's disk buffer lives in the output folder; never a clip, even if a
    # segment someday carries a video extension.
    (lib / "gsr-replay-2026-09-26.gsr").mkdir()
    make_clip(lib / "gsr-replay-2026-09-26.gsr" / "Replay_0.mp4", 1)

    # ── pure pieces ──────────────────────────────────────────────────────────
    check("name: fine", cl.valid_name("Ace clutch"), True)
    check("name: a path", cl.valid_name("../x"), False)
    check("name: a dot-file", cl.valid_name(".x"), False)
    check("name: empty", cl.valid_name("   "), False)
    check("name: too long", cl.valid_name("a" * 200), False)

    # ── index ────────────────────────────────────────────────────────────────
    r = run("index", str(lib), str(cache))
    check("index runs", r.returncode, 0)
    items = json.loads(r.stdout)
    names = [i["name"] for i in items]
    check("videos only, one level down included, no dot-files",
          sorted(names), sorted(["Replay_old", "Replay_new", "Broken"]))
    by = {i["name"]: i for i in items}
    check("duration", round(by["Replay_new"]["duration"]), 6)
    check("size", [by["Replay_new"]["width"], by["Replay_new"]["height"]], [320, 180])
    check("thumbnail made", os.path.getsize(by["Replay_new"]["thumb"]) > 0, True)
    check("unreadable file listed but not ok", [by["Broken"]["ok"], by["Broken"]["thumb"]], [False, ""])
    meta = json.loads((cache / "meta.json").read_text())
    check("unreadable file isn't cached", by["Broken"]["key"] in meta, False)
    check("limit", len(json.loads(run("index", str(lib), str(cache), "1").stdout)), 1)
    check("missing folder is empty", json.loads(run("index", str(tmp / "nope"), str(cache)).stdout), [])

    # ── strip ────────────────────────────────────────────────────────────────
    r = run("strip", str(new), str(cache), "6")
    frames = json.loads(r.stdout)
    check("strip: six frames", len([f for f in frames if f and os.path.getsize(f) > 0]), 6)

    # ── trim ─────────────────────────────────────────────────────────────────
    r = run("trim", str(new), "1", "4")
    check("trim runs", r.returncode, 0)
    out = Path(r.stdout.strip())
    check("trim: beside the original, never over it", [out.name, new.exists()], ["Replay_new-trim.mp4", True])
    d = cl.probe(out)["duration"]
    check("trim: about the span (keyframe-snapped)", 2.5 <= d <= 4.2, True)
    check("trim: a second one gets -2", Path(run("trim", str(new), "0", "2").stdout.strip()).name,
          "Replay_new-trim-2.mp4")
    check("trim: too short", run("trim", str(new), "1", "1.2").returncode, 2)
    check("trim: not a number", run("trim", str(new), "a", "2").returncode, 2)
    check("trim: relative path", run("trim", "Replay_new.mp4", "0", "2").returncode, 2)

    # ── headtrim: the one in-place edit ──────────────────────────────────────
    ht = lib / "Elden-Ring_Replay_head.mp4"
    make_clip(ht, 8)
    before = ht.stat().st_size
    r = run("headtrim", str(ht), "3")
    check("headtrim runs, prints the same path", [r.returncode, r.stdout.strip()], [0, str(ht)])
    d = probe_dur(ht)
    check("headtrim: about the last 3s (keyframe-snapped, never short)", 2.9 <= d <= 5.2, True)
    check("headtrim: in place, nothing left beside it", sorted(x.name for x in lib.glob("*head*")), ["Elden-Ring_Replay_head.mp4"])
    check("headtrim: smaller than before", ht.stat().st_size < before, True)
    r = run("headtrim", str(ht), "30")
    check("headtrim: already short enough is left alone", [r.returncode, abs(probe_dur(ht) - d) < 0.01], [0, True])
    check("headtrim: relative path", run("headtrim", "x.mp4", "3").returncode, 2)
    check("headtrim: not a number", run("headtrim", str(ht), "x").returncode, 2)
    check("headtrim: under a second is refused", run("headtrim", str(ht), "0.5").returncode, 2)
    check("headtrim: not a video", run("headtrim", str(lib / "notes.txt"), "3").returncode, 1)

    # ── size: the recording in progress ──────────────────────────────────────
    live = lib / "Video_2026-10-18_21-00-00.mp4"
    live.write_bytes(b"x" * 1234)
    check("size: by path", run("size", str(lib), "0", str(live)).stdout.strip(), "1234")
    check("size: by newest Video_ since", run("size", str(lib), str(int((time.time() - 60) * 1000))).stdout.strip(), "1234")
    check("size: nothing since a later time", run("size", str(lib), str(int((time.time() + 600) * 1000))).stdout.strip(), "0")
    check("size: a missing path is 0", run("size", str(lib), "0", str(lib / "nope.mp4")).stdout.strip(), "0")
    check("size: not a time", run("size", str(lib), "x").returncode, 2)
    live.unlink()

    # ── rename ───────────────────────────────────────────────────────────────
    r = run("rename", str(old), "Ace clutch")
    check("rename", [r.returncode, Path(r.stdout.strip()).name, old.exists()], [0, "Ace clutch.mp4", False])
    renamed = lib / "Ace clutch.mp4"
    check("rename: taken", run("rename", str(new), "Replay_new-trim").returncode, 1)
    check("rename: the original survives a refusal", new.exists(), True)
    check("rename: a path refused", run("rename", str(renamed), "../escape").returncode, 2)
    check("rename: same name is fine", run("rename", str(renamed), "Ace clutch").returncode, 0)

    # ── pruning ──────────────────────────────────────────────────────────────
    stale = by["Replay_old"]["thumb"]
    run("index", str(lib), str(cache))
    check("a renamed clip's old thumbnail is pruned", os.path.exists(stale), False)

    # ── export: the plan (pure) ──────────────────────────────────────────────
    co = cl.clean_options
    check("options: garbage falls back", co({"sizeMB": "x", "height": 123, "audio": "loud", "format": "avi"}),
          {"precise": False, "sizeMB": 0, "height": 0, "audio": "mix", "format": "mp4"})
    check("options: a size past the cap", co({"sizeMB": 9999})["sizeMB"], 0)
    check("options: not a dict", co("rm -rf")["format"], "mp4")
    check("options: precise must be exactly true", co({"precise": "yes"})["precise"], False)
    info = {"duration": 10.0, "height": 1080, "audio": 2}
    plan = lambda o: cl.export_plan("/in.mp4", info, 1.0, 5.0, co(o), "/out.mp4")
    check("plan: plain is a stream copy", "copy" in plan({"audio": "all"}) and "libx264" not in plan({}), True)
    check("plan: mix is the default, one amix of both tracks",
          [x for x in plan({}) if "amix" in x], ["[0:a:0][0:a:1]amix=inputs=2:duration=longest:normalize=0[mix]"])
    check("plan: a mix maps the mixed stream only", "[mix]" in plan({}) and "0:a" not in plan({}), True)
    check("plan: fast mix still copies the video", plan({})[plan({}).index("-c:v") + 1], "copy")
    check("plan: precise mix", "amix" in " ".join(plan({"precise": True})) and "libx264" in plan({"precise": True}), True)
    one = cl.export_plan("/in.mp4", dict(info, audio=1), 1.0, 5.0, co({}), "/o.mp4")
    check("plan: one track needs no mix", ["amix" in " ".join(one), "0:a" in one], [False, True])
    check("plan: precise re-encodes", "libx264" in plan({"precise": True}), True)
    check("plan: a size target re-encodes at a bitrate", "-b:v" in plan({"sizeMB": 10}), True)
    vk = int(plan({"sizeMB": 10})[plan({"sizeMB": 10}).index("-b:v") + 1].rstrip("k"))
    check("plan: the bitrate lands under the size", (vk + 128 * 2) * 4 / 8 / 1024 <= 10, True)
    check("plan: downscale", plan({"height": 720})[plan({"height": 720}).index("-vf") + 1], "scale=-2:720")
    check("plan: never upscale (and no re-encode for it)", "libx264" in plan({"height": 1440}), False)
    check("plan: first audio track only", "0:a:0" in plan({"audio": "first"}), True)
    check("plan: no audio", ["0:a" in x for x in plan({"audio": "none", "precise": True})].count(True), 0)
    check("plan: no audio, no audio codec", "-c:a" in plan({"audio": "none", "precise": True}), False)
    check("plan: gif uses a palette", "palettegen" in " ".join(plan({"format": "gif"})), True)
    check("plan: output last", plan({"precise": True})[-1], "/out.mp4")

    # ── export: real runs ────────────────────────────────────────────────────
    two = lib / "Two tracks.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=1280x720:rate=30:duration=6",
                    "-f", "lavfi", "-i", "sine=frequency=440:duration=6", "-f", "lavfi", "-i", "sine=frequency=880:duration=6",
                    "-map", "0", "-map", "1", "-map", "2", "-c:v", "libx264", "-g", "30", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", str(two)], check=True, timeout=60)
    def export(o, a="1", b="4"):
        return run("export", str(two), a, b, json.dumps(o))
    def audio_tracks(f):
        return cl.media_info(f)["audio"]

    r = export({"audio": "all"})
    lines = r.stdout.strip().splitlines()
    out = Path(lines[-1].split(" ", 1)[1]) if lines and lines[-1].startswith("done ") else None
    check("export: fast copy runs", [r.returncode, out.name if out else None], [0, "Two tracks-trim.mp4"])
    check("export: keeps both tracks", audio_tracks(out), 2)

    # The default: both tracks mixed into one, so every player hears the mic.
    r = export({})
    out = Path(r.stdout.strip().splitlines()[-1].split(" ", 1)[1])
    check("export: mix → one track", [r.returncode, audio_tracks(out)], [0, 1])
    def level(f):
        o = subprocess.run(["ffmpeg", "-v", "info", "-i", str(f), "-map", "0:a:0", "-af", "volumedetect",
                            "-f", "null", "-"], capture_output=True, text=True).stderr
        return float(o.split("mean_volume:")[1].split("dB")[0])
    src_level = level(two)
    check("export: the mix isn't quieter than one track (normalize=0)", level(out) >= src_level - 0.5, True)

    r = export({"precise": True, "audio": "first"})
    out = Path(r.stdout.strip().splitlines()[-1].split(" ", 1)[1])
    check("export: precise → -edit", out.name, "Two tracks-edit.mp4")
    check("export: precise is frame-exact", abs(cl.media_info(out)["duration"] - 3.0) < 0.15, True)
    check("export: the desktop track only", audio_tracks(out), 1)
    check("export: progress was streamed", any(l.startswith("progress ") for l in r.stdout.splitlines()), True)

    r = export({"audio": "none", "height": 360, "sizeMB": 1})
    out = Path(r.stdout.strip().splitlines()[-1].split(" ", 1)[1])
    info2 = cl.media_info(out)
    check("export: muted, scaled, under the size", [info2["audio"], info2["height"], out.stat().st_size <= 1024 * 1024],
          [0, 360, True])

    r = export({"format": "gif"})
    out = Path(r.stdout.strip().splitlines()[-1].split(" ", 1)[1])
    check("export: a gif", [out.suffix, out.read_bytes()[:6]], [".gif", b"GIF89a"])

    check("export: span too short", export({}, "1", "1.2").returncode, 2)
    check("export: past the end is clamped", export({}, "5", "99").returncode, 0)
    check("export: bad json", run("export", str(two), "0", "2", "{nope").returncode, 2)

    # Cancel mid-export: the runner goes, ffmpeg with it, and no partial file stays.
    # Long enough (and slow enough to encode) that it can't finish first.
    long_ = lib / "Long.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=30:duration=40",
                    "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", str(long_)], check=True, timeout=120)
    slow = subprocess.Popen([sys.executable, str(LIB), "export", str(long_), "0", "40",
                             json.dumps({"precise": True})], stdout=subprocess.PIPE, text=True)
    first = slow.stdout.readline()          # the first progress line: ffmpeg is running
    slow.terminate()
    code = slow.wait(timeout=10)
    time.sleep(0.3)
    left = [f.name for f in lib.iterdir() if f.name.startswith("Long-edit")]
    check("export: cancelled mid-way", [first.startswith("progress"), code], [True, 130])
    check("export: cancelled leaves nothing", left, [])
    check("export: no ffmpeg left running",
          subprocess.run(["pgrep", "-f", f"{long_}"], capture_output=True).returncode, 1)

    r = run("frame", str(two), "2.5")
    check("frame: a png beside the clip", [r.returncode, Path(r.stdout.strip()).suffix,
                                           Path(r.stdout.strip()).read_bytes()[:4]], [0, ".png", b"\x89PNG"])
    check("frame: a negative time", run("frame", str(two), "-1").returncode, 2)

    print(f"\n{passed} passed, {failed} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
