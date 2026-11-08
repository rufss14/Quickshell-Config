#!/usr/bin/env python3
"""
test-lens.py — tests for scripts/lens.py.

    python3 scripts/test-lens.py

Safe: a fixture TSV for the grouping, and a real tesseract read of an image this
test draws itself (Pillow + an installed font) in a temp dir. The read is skipped,
with a note, without tesseract or a font.
"""
import importlib.util
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("lens", os.path.join(HERE, "lens.py"))
lens = importlib.util.module_from_spec(spec)
spec.loader.exec_module(lens)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


H = "level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\tconf\ttext"
def row(level, b, p, l, w, x, y, ww, hh, conf, text):
    return "\t".join(map(str, (level, 1, b, p, l, w, x, y, ww, hh, conf, text)))

TSV = "\n".join([H,
    row(1, 0, 0, 0, 0, 0, 0, 400, 200, -1, ""),
    row(4, 1, 1, 1, 0, 10, 10, 200, 20, -1, ""),
    row(5, 1, 1, 1, 1, 10, 10, 60, 20, 95.5, "Hello"),
    row(5, 1, 1, 1, 2, 80, 12, 70, 18, 90, "world"),
    row(5, 1, 1, 2, 1, 10, 40, 50, 20, 88, "again"),
    row(5, 1, 1, 2, 2, 70, 40, 30, 20, -1, "  "),
    row(5, 2, 1, 1, 1, 10, 100, 40, 20, 70, "Next"),
    "garbage line",
])
lines = lens.parse_tsv(TSV)
check("lines", [l["text"] for l in lines], ["Hello world", "again", "Next"])
check("union box", (lines[0]["x"], lines[0]["y"], lines[0]["w"], lines[0]["h"]), (10, 10, 140, 20))
check("blocks", [l["block"] for l in lines], [1, 1, 2])
check("conf", lines[0]["conf"], 93)
check("scaled back", lens.parse_tsv(TSV, 2)[0]["w"], 70)
check("prose", lens.join_text(lines), "Hello world\nagain\n\nNext")
check("bad header", lens.parse_tsv("nope\n1\t2"), [])
check("langs subset", lens.pick_langs("eng+jpn", ["eng", "osd"]), "eng")
check("langs fallback", lens.pick_langs("klingon", ["deu", "eng", "osd"]), "eng")
check("langs no eng", lens.pick_langs("", ["deu", "osd"]), "deu")
check("langs order", lens.pick_langs("jpn,eng", ["eng", "jpn"]), "jpn+eng")

# ── auto: the script decides, English first ─────────────────────────────────
check("auto, one language", lens.pick_langs("auto", ["eng", "osd"]), "eng")
check("auto, two languages read together", lens.pick_langs("auto", ["jpn", "eng", "osd"]), "eng+jpn")
many = ["deu", "eng", "fra", "jpn", "kor", "rus", "osd"]
check("auto + Latin script", lens.pick_langs("auto", many, "Latin"), "eng+deu+fra".replace("eng+deu+fra", "eng+fra+deu"))
check("auto + Japanese text", lens.pick_langs("auto", many, "Japanese"), "eng+jpn")
check("auto + Han reads jpn and kor too", lens.pick_langs("auto", many, "Han"), "eng+jpn+kor")
check("auto + Cyrillic", lens.pick_langs("auto", many, "Cyrillic"), "eng+rus")
check("auto, script not installed: falls back to everything, capped", lens.pick_langs("auto", many, "Thai"), "eng+deu+fra+jpn")
check("auto, script unknown", lens.pick_langs("", many, ""), "eng+deu+fra+jpn")
check("explicit still means explicit", lens.pick_langs("deu", many, "Japanese"), "deu")
check("osd never reads", "osd" not in lens.pick_langs("auto", ["osd"]).split("+"), True)

osd = "Page number: 0\nOrientation in degrees: 0\nRotate: 0\nOrientation confidence: 12.34\nScript: Japanese\nScript confidence: 4.20\n"
check("osd script", lens.parse_osd(osd), "Japanese")
check("osd unsure", lens.parse_osd(osd.replace("4.20", "0.40")), "")
check("osd nothing", lens.parse_osd("Too few characters. Skipping this page"), "")
check("osd empty", lens.parse_osd(""), "")
check("missing image", lens.ocr("/nonexistent.png", "eng")["ok"], False)

font = ""
try:
    font = subprocess.run(["fc-match", "-f", "%{file}", "sans"], capture_output=True, text=True).stdout.strip()
except OSError:
    pass
if shutil.which("tesseract") and font and os.path.isfile(font):
    from PIL import Image, ImageDraw, ImageFont
    tmp = tempfile.mkdtemp(prefix="lens-test-")
    img = Image.new("RGB", (360, 70), (30, 30, 46))
    d = ImageDraw.Draw(img)
    d.text((10, 8), "Hello world from the lens", fill=(230, 230, 230), font=ImageFont.truetype(font, 13))
    d.text((10, 38), "Second line of text", fill=(230, 230, 230), font=ImageFont.truetype(font, 13))
    path = os.path.join(tmp, "shot.png")
    img.save(path)
    r = lens.ocr(path, "eng")
    check("real read ok", r.get("ok"), True)
    check("real read lines", [l["text"] for l in r.get("lines", [])], ["Hello world from the lens", "Second line of text"])
    check("real read size", (r.get("width"), r.get("height")), (360, 70))
    if r.get("lines"):
        check("box in image pixels", 0 <= r["lines"][0]["x"] < 40 and 0 <= r["lines"][0]["y"] < 20, True)
else:
    print("note: tesseract or a font missing — real read skipped")

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
