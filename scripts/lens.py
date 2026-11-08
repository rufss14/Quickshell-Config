#!/usr/bin/env python3
"""
lens.py — read the text in a screenshot, with where each line is.

    lens.py ocr <image.png> [--lang eng+jpn]    → one JSON object on stdout
    lens.py langs                               → {"ok":true,"langs":[…]}

services/Lens.qml runs this on the region you dragged out (slurp → grim), then draws
each line's box over the frozen picture (modules/panels/LensOverlay) — to copy, or to
translate in place (scripts/lyrics-translate.py, its local-first backends).

out  {"ok":true,"width":W,"height":H,"lang":"eng","text":"…",
      "lines":[{"text":"…","x":…,"y":…,"w":…,"h":…,"block":n,"conf":0-100}]}
     coordinates in the IMAGE's pixels (the shell scales them to the region)
out  {"ok":false,"error":"…","install":"tesseract tesseract-data-eng"}

Always exits 0: a failure is something the overlay says, never a traceback.

── Why scale up first ──────────────────────────────────────────────────────────
Tesseract is tuned for ~300 dpi scans; UI text at 1× is ~10px tall and comes back as
noise. A capture whose text is likely small (an image under 1000px tall) is enlarged
2× (Pillow, LANCZOS) before OCR and the boxes divided back. Measured on a generated
"Hello world" at 13px: unscaled misread it, scaled read it exactly.

── Languages ───────────────────────────────────────────────────────────────────
Whatever tesseract has data for (`tesseract --list-langs`; Arch: tesseract-data-<code>).
A requested language that isn't installed is dropped, never passed through — the
`--lang` value comes from a hand-editable config, and tesseract would fail the whole
read on one unknown code.

`--lang auto` (the default) reads whatever is installed, but not all at once: with more than
two languages installed, tesseract's own orientation-and-script detection (`--psm 0 -l osd`)
says which SCRIPT the picture is in and only the installed languages for that script are
used, English first. Reading Japanese with `eng+deu+fra+jpn+kor+…` is slow and drags
accuracy down; reading it with `eng+jpn` is neither. A script it can't tell (too little
text) falls back to every installed language, capped.

Reading text in a language with no data installed returns noise or nothing, which is why
the shell tells you (Settings › Setup) which `tesseract-data-<code>` packages are missing.

    python3 scripts/test-lens.py   — a fixture TSV, and a real read of a generated image
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

SCALE_BELOW = 1000      # image height under which text is enlarged before OCR
SCALE = 2
MIN_CONF = 0            # tesseract's -1 = "not a word"; anything 0+ is kept
TIMEOUT = 30


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def installed_langs():
    try:
        r = subprocess.run(["tesseract", "--list-langs"], capture_output=True, text=True, timeout=10)
    except (OSError, subprocess.TimeoutExpired):
        return None
    # First line is "List of available languages in …:"; the rest are codes.
    return [l.strip() for l in (r.stdout or "").splitlines()[1:] if re.fullmatch(r"[A-Za-z_]+", l.strip())]


# Which script tesseract's OSD names → the languages that read it. Han is shared by Chinese,
# Japanese and Korean, so all three are candidates there.
SCRIPT_LANGS = {
    "Latin": ["eng", "fra", "deu", "spa", "ita", "por", "nld", "pol", "tur", "ind", "swe", "dan",
              "nor", "fin", "ces", "slk", "hun", "ron", "cat", "vie", "hrv", "slv", "lav", "lit", "est"],
    "Cyrillic": ["rus", "ukr", "bul", "srp", "bel", "mkd"],
    "Han": ["chi_sim", "chi_tra", "jpn", "kor"],
    "Japanese": ["jpn", "jpn_vert"],
    "Hangul": ["kor", "kor_vert"],
    "Arabic": ["ara", "fas", "urd"],
    "Devanagari": ["hin", "mar", "nep", "san"],
    "Greek": ["ell"],
    "Hebrew": ["heb"],
    "Thai": ["tha"],
    "Bengali": ["ben"], "Tamil": ["tam"], "Telugu": ["tel"], "Georgian": ["kat"], "Armenian": ["hye"],
}
AUTO_CAP = 4            # most languages read at once when the script isn't known


def parse_osd(text):
    """The script from `tesseract --psm 0` output ("Script: Latin"), "" when it isn't sure.
    OSD prints a confidence; below 1.0 it is guessing."""
    script = conf = None
    for line in (text or "").splitlines():
        m = re.match(r"\s*Script:\s*(\S+)", line)
        if m:
            script = m.group(1)
        m = re.match(r"\s*Script confidence:\s*([0-9.]+)", line)
        if m:
            conf = float(m.group(1))
    if script and (conf is None or conf >= 1.0):
        return script
    return ""


def auto_langs(script, available):
    """The installed languages worth reading `script` with (English first), or — script unknown —
    everything installed up to AUTO_CAP."""
    have = [l for l in (available or []) if l != "osd"]
    pool = SCRIPT_LANGS.get(script, [])
    chosen = [l for l in pool if l in have]
    if chosen and "eng" in have and "eng" not in chosen:
        chosen.insert(0, "eng")
    if not chosen:
        chosen = ([l for l in have if l == "eng"] + [l for l in have if l != "eng"])[:AUTO_CAP]
    return chosen


def pick_langs(requested, available, script=None):
    """'eng+jpn' → the installed subset, in order ('osd' is never a reading language).
    "auto" (or nothing): everything installed when that is two or fewer, otherwise what reads
    `script` (see auto_langs). Falls back to eng, then to whatever is installed first."""
    have = [l for l in (available or []) if l != "osd"]
    req = (requested or "").strip()
    if req in ("", "auto"):
        if len(have) <= 2:
            chosen = ([l for l in have if l == "eng"] + [l for l in have if l != "eng"])
        else:
            chosen = auto_langs(script or "", have)
        return "+".join(chosen)
    want = [l for l in re.split(r"[+,\s]+", req) if l]
    chosen = [l for l in want if l in have]
    if not chosen:
        chosen = ["eng"] if "eng" in have else have[:1]
    return "+".join(chosen)


def detect_script(src):
    """Ask tesseract's OSD which script the picture is in; "" if it can't tell."""
    try:
        r = subprocess.run(["tesseract", src, "stdout", "--psm", "0", "-l", "osd"],
                           capture_output=True, text=True, timeout=TIMEOUT)
    except (OSError, subprocess.TimeoutExpired):
        return ""
    return parse_osd((r.stdout or "") + "\n" + (r.stderr or ""))


def parse_tsv(tsv, scale=1):
    """tesseract's TSV → lines with boxes. Words (level 5) are grouped by
    (block, paragraph, line); a line's box is the union of its words'."""
    lines = {}
    order = []
    rows = tsv.splitlines()
    if not rows:
        return []
    head = rows[0].split("\t")
    idx = {k: i for i, k in enumerate(head)}
    need = ("level", "block_num", "par_num", "line_num", "left", "top", "width", "height", "conf", "text")
    if any(k not in idx for k in need):
        return []
    for row in rows[1:]:
        f = row.split("\t")
        if len(f) < len(head):
            continue
        try:
            if int(f[idx["level"]]) != 5:
                continue
            conf = float(f[idx["conf"]])
            text = f[idx["text"]].strip()
            if conf < MIN_CONF or not text:
                continue
            key = (int(f[idx["block_num"]]), int(f[idx["par_num"]]), int(f[idx["line_num"]]))
            x, y = int(f[idx["left"]]), int(f[idx["top"]])
            w, h = int(f[idx["width"]]), int(f[idx["height"]])
        except ValueError:
            continue
        if key not in lines:
            lines[key] = {"words": [], "x0": x, "y0": y, "x1": x + w, "y1": y + h, "confs": []}
            order.append(key)
        ln = lines[key]
        ln["words"].append(text)
        ln["confs"].append(conf)
        ln["x0"], ln["y0"] = min(ln["x0"], x), min(ln["y0"], y)
        ln["x1"], ln["y1"] = max(ln["x1"], x + w), max(ln["y1"], y + h)
    result = []
    for key in order:
        ln = lines[key]
        result.append({
            "text": " ".join(ln["words"]),
            "x": round(ln["x0"] / scale), "y": round(ln["y0"] / scale),
            "w": round((ln["x1"] - ln["x0"]) / scale), "h": round((ln["y1"] - ln["y0"]) / scale),
            "block": key[0],
            "conf": round(sum(ln["confs"]) / len(ln["confs"])),
        })
    return result


def join_text(lines):
    """The lines as prose: a line break within a block, a blank line between blocks."""
    parts, last = [], None
    for ln in lines:
        if last is not None:
            parts.append("\n\n" if ln["block"] != last else "\n")
        parts.append(ln["text"])
        last = ln["block"]
    return "".join(parts)


def ocr(path, lang_req):
    if shutil.which("tesseract") is None:
        return {"ok": False, "error": "tesseract isn't installed", "install": "tesseract tesseract-data-eng"}
    if not (isinstance(path, str) and path.startswith("/") and os.path.isfile(path)):
        return {"ok": False, "error": "no such image"}
    langs = installed_langs()
    if not langs or langs == ["osd"]:
        return {"ok": False, "error": "tesseract has no language data", "install": "tesseract-data-eng"}

    try:
        from PIL import Image
        img = Image.open(path)
        width, height = img.size
    except Exception as e:
        return {"ok": False, "error": "can't open the capture (%s)" % e.__class__.__name__}

    scale, src, tmp = 1, path, None
    if height < SCALE_BELOW:
        scale = SCALE
        fd, tmp = tempfile.mkstemp(suffix=".png", prefix="lens-")
        os.close(fd)
        img.convert("RGB").resize((width * SCALE, height * SCALE), Image.LANCZOS).save(tmp)
        src = tmp
    # More than two languages installed and no explicit choice: find the script first.
    have = [l for l in langs if l != "osd"]
    auto = (lang_req or "").strip() in ("", "auto")
    script = detect_script(src) if (auto and len(have) > 2 and "osd" in langs) else ""
    lang = pick_langs(lang_req, langs, script)
    try:
        r = subprocess.run(["tesseract", src, "stdout", "-l", lang, "--psm", "3", "tsv"],
                           capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "tesseract took too long"}
    except OSError as e:
        return {"ok": False, "error": str(e)}
    finally:
        if tmp:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    if r.returncode != 0:
        return {"ok": False, "error": (r.stderr or "tesseract failed").strip().splitlines()[-1][:200]}
    lines = parse_tsv(r.stdout, scale)
    return {"ok": True, "width": width, "height": height, "lang": lang, "script": script,
            "text": join_text(lines), "lines": lines}


def main(argv):
    if argv[:1] == ["langs"]:
        langs = installed_langs()
        out({"ok": langs is not None, "langs": [l for l in (langs or []) if l != "osd"]})
        return 0
    if len(argv) >= 2 and argv[0] == "ocr":
        lang = ""
        if "--lang" in argv:
            i = argv.index("--lang")
            lang = argv[i + 1] if i + 1 < len(argv) else ""
        out(ocr(argv[1], lang))
        return 0
    out({"ok": False, "error": "usage: lens.py ocr <image> [--lang eng] | langs"})
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
