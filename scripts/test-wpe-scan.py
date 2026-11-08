#!/usr/bin/env python3
"""
test-wpe-scan.py — tests for scripts/wpe-scan.py.

    python3 scripts/test-wpe-scan.py

Safe: builds a fake workshop folder in a temp dir and runs the scanner over it.
"""
import importlib.util
import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "wpe-scan.py")
spec = importlib.util.spec_from_file_location("wpe_scan", SCRIPT)
scan = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scan)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n  got:  %r\n  want: %r" % (name, got, want))


def read_tex(path):
    """TextureParser.cpp's parse(), for the TEXB0003 / embedded-file case."""
    import struct
    b = open(path, "rb").read()
    o = 0
    def take(fmt):
        nonlocal o
        v = struct.unpack_from(fmt, b, o); o += struct.calcsize(fmt)
        return v if len(v) > 1 else v[0]
    def magic():
        nonlocal o
        m = b[o:o + 9]; o += 9
        return m
    r = {"magic": magic(), "sub": magic()}
    r["format"], r["flags"], r["tw"], r["th"], r["w"], r["h"], _ = take("<7I")
    r["container"] = magic()
    r["images"], r["fif"] = take("<II")
    r["mips"] = take("<I")
    r["mw"], r["mh"], r["compression"], r["uncompressed"], r["size"] = take("<IIIii")
    r["data"] = b[o:o + r["size"]]
    r["trailing"] = len(b) - o - r["size"]
    return r


def put(root, wid, project, files=()):
    d = os.path.join(root, wid)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "project.json"), "w") as f:
        f.write(project if isinstance(project, str) else json.dumps(project))
    for name in files:
        p = os.path.join(d, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        open(p, "wb").write(b"x")
    return d


BASE_PROPS = {
    "on":     {"type": "bool", "value": True},
    "amount": {"type": "slider", "value": 1},
    "tint":   {"type": "color", "value": "1 1 1"},
    "mode":   {"type": "combo", "value": "a", "options": []},
    "label":  {"type": "textinput", "value": ""},
    "pic":    {"type": "scenetexture", "value": ""},
    "header": {"type": "text", "value": "<h4>"},
}

with tempfile.TemporaryDirectory() as W:
    put(W, "100", {"title": "Base", "type": "Scene", "file": "scene.json", "preview": "p.jpg",
                   "general": {"properties": BASE_PROPS}}, ["p.jpg", "scene.pkg"])
    put(W, "101", {"title": "Plain video", "type": "video", "file": "v.mp4"})
    put(W, "200", {
        "title": "My preset", "dependency": "100", "preview": "preview.jpg",
        "preset": {
            "on": False, "amount": 50, "tint": "0.2 0 1", "mode": "b", "label": "home",
            "pic": "files/a b.jpg",
            "header": False,            # a `text` label: never a value
            "alignmentx": 50,           # Wallpaper Engine's own, not the scene's
            "wec_hue": 50,
            "nothere": None,
        }}, ["preview.jpg", "files/a b.jpg"])
    # A path that climbs out of the preset's folder, and one that isn't there.
    put(W, "201", {"title": "Escape", "dependency": "100", "preset": {"pic": "../100/p.jpg"}})
    put(W, "202", {"title": "Missing pic", "dependency": "100", "preset": {"pic": "files/nope.jpg"}})
    # Base not installed, no preset blob, not a dict, garbage JSON.
    put(W, "300", {"title": "Orphan", "dependency": "999", "preset": {"on": True}})
    put(W, "301", {"title": "No blob", "dependency": "100"})
    put(W, "302", {"title": "Bad blob", "dependency": "100", "preset": [1, 2]})
    put(W, "303", {"title": "Dep is traversal", "dependency": "../100", "preset": {}})
    put(W, "304", "{not json")
    os.makedirs(os.path.join(W, "305"))          # a folder with no project.json at all

    # Real pictures for the preset's three scenetexture values.
    from PIL import Image
    pics = os.path.join(W, "200", "files")
    Image.new("RGB", (40, 30), (200, 10, 10)).save(os.path.join(pics, "a b.jpg"), "JPEG")
    Image.new("RGBA", (16, 16), (0, 255, 0, 128)).save(os.path.join(pics, "c.png"), "PNG")
    Image.new("RGB", (8, 4), (0, 0, 255)).save(os.path.join(pics, "d.bmp"), "BMP")

    TEX = os.path.join(W, "_tex")
    rows, skipped = scan.scan(W, TEX)
    by = {r[1]: r for r in rows}

    check("items", sorted(by), ["100", "101", "200", "201", "202"])
    check("skipped counts every non-wallpaper but the empty folder", skipped, 5)

    check("plain: no base, no props, no textures", (by["100"][4], by["100"][5], by["100"][6]), ("", {}, ""))
    check("plain: type lowercased", (by["100"][2], by["101"][2]), ("scene", "video"))

    t, d, typ, prev, base, props, texdir = by["200"]
    check("preset: base", base, "100")
    check("preset: type comes from the base", typ, "scene")
    check("preset: preview is its own", prev, os.path.join(W, "200", "preview.jpg"))
    check("preset: wire values, schema keys only, pictures not among them", props, {
        "on": "0", "amount": "50.0", "tint": "#3300ff", "mode": "b", "label": "home",
    })
    check("preset: escaping path dropped", (by["201"][5], by["201"][6]), ({}, ""))
    check("preset: missing file dropped", (by["202"][5], by["202"][6]), ({}, ""))

    # The pictures: materials/<property key>.tex under <texroot>/<id>.
    check("textures: dir", texdir, os.path.join(TEX, "200"))
    check("textures: only the scenetexture keys written",
          sorted(os.listdir(os.path.join(texdir, "materials"))), ["pic.tex"])
    # The folder is a project the renderer can mount. project.json must be a REAL
    # file (its directory adapter refuses a path that canonicalises outside the
    # folder); only the .pkg is a link.
    pj = os.path.join(texdir, "project.json")
    check("overlay: project.json is a real copy",
          (os.path.isfile(pj), os.path.islink(pj),
           open(pj, "rb").read() == open(os.path.join(W, "100", "project.json"), "rb").read()),
          (True, False, True))
    check("overlay: scene.pkg links to the base's",
          os.path.realpath(os.path.join(texdir, "scene.pkg")), os.path.realpath(os.path.join(W, "100", "scene.pkg")))
    check("overlay: nothing generated leaks into the base",
          sorted(os.listdir(os.path.join(W, "100"))), ["p.jpg", "project.json", "scene.pkg"])
    scan.scan(W, TEX)   # a second scan over an existing folder changes nothing
    check("overlay: rescan idempotent", sorted(os.listdir(os.path.join(texdir, "materials"))), ["pic.tex"])

    # A base that isn't packed (loose files) can't be played from such a folder: the
    # preset keeps its base and values, and simply has no pictures.
    put(W, "102", {"title": "Loose", "type": "scene", "file": "scene.json",
                   "general": {"properties": BASE_PROPS}}, ["scene.json"])
    put(W, "220", {"title": "On loose", "dependency": "102", "preview": "p.jpg",
                   "preset": {"on": False, "pic": "files/c.png"}}, ["files/c.png"])
    Image.new("RGB", (4, 4), (1, 2, 3)).save(os.path.join(W, "220", "files", "c.png"), "PNG")
    r220 = {r[1]: r for r in scan.scan(W, TEX)[0]}["220"]
    check("loose base: values kept, no texdir", (r220[4], r220[5], r220[6]), ("102", {"on": "0"}, ""))
    jt = read_tex(os.path.join(texdir, "materials", "pic.tex"))
    check("tex: magics", (jt["magic"], jt["sub"], jt["container"]),
          (b"TEXV0005\0", b"TEXI0001\0", b"TEXB0003\0"))
    check("tex: size and one image/mipmap", (jt["w"], jt["h"], jt["mw"], jt["mh"], jt["images"], jt["mips"]),
          (40, 30, 40, 30, 1, 1))
    check("tex: JPEG embedded verbatim", (jt["fif"], jt["compression"], jt["trailing"],
          jt["data"] == open(os.path.join(W, "200", "files", "a b.jpg"), "rb").read()), (2, 0, 0, True))
    check("tex: sizes agree", jt["uncompressed"], jt["size"])

    # PNG verbatim, BMP re-encoded to PNG (stb handles both; FreeImage id 13).
    pre = {"title": "Pics", "dependency": "100", "preview": "p.jpg",
           "preset": {"pic": "files/c.png"}}
    put(W, "210", pre, ["files/c.png"])
    Image.new("RGBA", (16, 16), (0, 255, 0, 128)).save(os.path.join(W, "210", "files", "c.png"), "PNG")
    put(W, "211", dict(pre, preset={"pic": "files/d.bmp"}), ["files/d.bmp"])
    Image.new("RGB", (8, 4), (0, 0, 255)).save(os.path.join(W, "211", "files", "d.bmp"), "BMP")
    scan.scan(W, TEX)
    pt = read_tex(os.path.join(TEX, "210", "materials", "pic.tex"))
    bt = read_tex(os.path.join(TEX, "211", "materials", "pic.tex"))
    check("tex: PNG verbatim", (pt["fif"], pt["w"], pt["h"]), (13, 16, 16))
    check("tex: BMP becomes PNG at its own size", (bt["fif"], bt["w"], bt["h"], bt["data"][:4]),
          (13, 8, 4, b"\x89PNG"))
    # And decodes back to the same pixels.
    import io
    check("tex: decodes", Image.open(io.BytesIO(bt["data"])).convert("RGB").getpixel((0, 0)), (0, 0, 255))

    # No texture root (or an unreadable picture) -> no textures, nothing else changes.
    rows2, _ = scan.scan(W)
    check("no texroot: no texdir", {r[1]: r[6] for r in rows2}["200"], "")
    open(os.path.join(W, "200", "files", "a b.jpg"), "wb").write(b"not an image")
    rows3, _ = scan.scan(W, os.path.join(W, "_tex2"))
    check("bad picture: no texdir", {r[1]: r[6] for r in rows3}["200"], "")

    # The CLI: tab-separated, title last, props one JSON field with no raw tab.
    out = subprocess.run([sys.executable, SCRIPT, W, os.path.join(W, "_tex3")],
                         capture_output=True, text=True, check=True).stdout.splitlines()
    check("cli: header", out[0].startswith("SKIPPED\t"), True)
    line = next(l for l in out if l.startswith("ITEM\t200\t"))
    parts = line.split("\t")
    check("cli: eight fields", len(parts), 8)
    check("cli: props round-trip", json.loads(parts[5]), props)
    check("cli: title last", parts[7], "My preset")

    # A tab in a title can't shift the fields.
    put(W, "400", {"title": "a\tb", "type": "scene", "file": "s.json"})
    out = subprocess.run([sys.executable, SCRIPT, W], capture_output=True, text=True, check=True).stdout.splitlines()
    check("cli: tab in title", next(l for l in out if "\t400\t" in l).split("\t")[7], "a b")

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
