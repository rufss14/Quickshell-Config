#!/usr/bin/env python3
# ── test-cursor-theme.py ─────────────────────────────────────────────────────
# Tests for generate-cursor-theme. Fully local and SAFE TO RUN: every case writes
# into a throwaway temp dir via --out, and --apply is never passed, so the real
# ~/.local/share/icons and the live cursor are untouched.
#
#   python3 scripts/test-cursor-theme.py
#
# The XCursor container is hand-written, so the tests parse it back the way a
# client would: header, table of contents, chunk headers, then pixels.
# ─────────────────────────────────────────────────────────────────────────────
import os
import struct
import subprocess
import sys
import tempfile
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "generate-cursor-theme")
gen = SourceFileLoader("generate_cursor_theme", SCRIPT).load_module()

FILL, EDGE = "#c4a0ff", "#101015"
PASS = 0
FAIL = 0


def check(label, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
    else:
        FAIL += 1
        print("FAIL  %s  %s" % (label, detail))


def parse(path):
    """→ list of (nominal, w, h, xhot, yhot, delay, pixels) in TOC order."""
    data = open(path, "rb").read()
    magic, hsize, ver, n = struct.unpack_from("<4s3I", data, 0)
    assert magic == b"Xcur" and hsize == 16
    out = []
    for i in range(n):
        typ, sub, pos = struct.unpack_from("<3I", data, 16 + 12 * i)
        assert typ == 0xFFFD0002
        ch, ctyp, csub, cver, w, h, xh, yh, delay = struct.unpack_from("<9I", data, pos)
        assert ch == 36 and ctyp == typ and csub == sub
        out.append((sub, w, h, xh, yh, delay, data[pos + 36:pos + 36 + w * h * 4]))
    return out


def px(frame, x, y):
    """(r, g, b, a) of one premultiplied BGRA pixel."""
    _, w, _, _, _, _, buf = frame
    b, g, r, a = buf[(y * w + x) * 4:(y * w + x) * 4 + 4]
    return r, g, b, a


with tempfile.TemporaryDirectory() as tmp:
    out = os.path.join(tmp, "quicktest")
    r = subprocess.run([sys.executable, SCRIPT, "--fill", FILL, "--edge", EDGE, "--out", out],
                       capture_output=True, text=True)
    check("script exits 0", r.returncode == 0, r.stderr)

    theme = open(os.path.join(out, "index.theme")).read()
    check("inherits Adwaita", "Inherits=Adwaita" in theme)

    cur = os.path.join(out, "cursors")
    for name, aliases in gen.ALIASES.items():
        check("%s exists" % name, os.path.isfile(os.path.join(cur, name)))
        for a in aliases:
            link = os.path.join(cur, a)
            check("%s → %s" % (a, name), os.path.islink(link) and os.readlink(link) == name)

    # ── one theme, two names ────────────────────────────────────────────────
    tw = out + "-b"
    check("twin name is a symlink to the theme", os.path.islink(tw) and os.readlink(tw) == "quicktest",
          os.readlink(tw) if os.path.islink(tw) else "missing")
    check("twin resolves to the same files", os.path.isfile(os.path.join(tw, "cursors", "default"))
          and os.path.samefile(os.path.join(tw, "cursors", "pointer"), os.path.join(cur, "pointer")))

    # ── the arrow, read back ────────────────────────────────────────────────
    frames = parse(os.path.join(cur, "default"))
    check("default: one frame per size", [f[0] for f in frames] == list(gen.SIZES), [f[0] for f in frames])
    f24 = frames[0]
    check("default: 24px square", f24[1] == 24 and f24[2] == 24)
    check("default: hotspot inside image", 0 <= f24[3] < 24 and 0 <= f24[4] < 24)
    check("default: still, no delay", f24[5] == 0)
    fill = tuple(int(FILL[i:i + 2], 16) for i in (1, 3, 5))
    edge = tuple(int(EDGE[i:i + 2], 16) for i in (1, 3, 5))
    f96 = frames[-1]
    S = 96 / 32

    def at(fr, dx, dy):
        return px(fr, round(dx * S), round(dy * S))

    def near(p, col, tol=4):
        return p[3] >= 253 and all(abs(p[i] - col[i]) <= tol for i in range(3))

    # The arrow is SOLID. Design (8, 14) is well inside it, (0, 31) is empty corner.
    check("default: body is the fill colour", near(at(f96, 8, 14), fill), at(f96, 8, 14))
    check("default: no hole in the middle", at(f96, 8, 14)[3] == 255)
    check("default: corner is transparent", px(f24, 0, 23)[3] == 0)
    check("default: outline pixels are the edge colour",
          any(near(px(f96, x, y), edge) for y in range(96) for x in range(96)))

    # Hovering something clickable must not change the shape: every pointer name is the
    # one arrow, not a second drawing.
    for nm in ("pointer", "hand2", "pointing_hand"):
        check("%s is the default arrow" % nm,
              os.path.islink(os.path.join(cur, nm)) and os.readlink(os.path.join(cur, nm)) == "default")

    # ── premultiplied: no channel may exceed alpha ──────────────────────────
    bad = [(x, y) for y in range(24) for x in range(24) if max(px(f24, x, y)[:3]) > px(f24, x, y)[3]]
    check("default: pixels are premultiplied", not bad, bad[:3])

    # ── the spinner really animates ─────────────────────────────────────────
    wait = parse(os.path.join(cur, "wait"))
    check("wait: SPIN_FRAMES per size", len(wait) == gen.SPIN_FRAMES * len(gen.SIZES), len(wait))
    check("wait: frames carry a delay", all(f[5] == gen.SPIN_DELAY for f in wait))
    check("wait: frames differ", wait[0][6] != wait[1][6])

    # ── every shape stays inside its own canvas ─────────────────────────────
    for name in gen.ALIASES:
        for f in parse(os.path.join(cur, name)):
            if not (0 <= f[3] < f[1] and 0 <= f[4] < f[2]):
                check("%s hotspot in bounds @%d" % (name, f[0]), False, f[3:5])
                break
        else:
            check("%s hotspots in bounds" % name, True)

    # ── regenerating replaces, never duplicates ─────────────────────────────
    r = subprocess.run([sys.executable, SCRIPT, "--fill", "#00ff00", "--edge", EDGE, "--out", out],
                       capture_output=True, text=True)
    check("re-run exits 0 over existing links", r.returncode == 0, r.stderr)
    again = px(parse(os.path.join(cur, "default"))[0], round(8 * 24 / 32), round(14 * 24 / 32))
    check("re-run picks up the new colour", again[1] > 200 and again[0] < 20, again)
    check("no stray .tmp left", not [n for n in os.listdir(cur) if n.endswith(".tmp")])

    # ── the full set: nothing a compositor asks for may fall through to Adwaita ──
    names = [a for al in gen.ALIASES.values() for a in al]
    check("no alias appears twice", len(names) == len(set(names)))
    check("no alias shadows a drawn shape", not set(names) & set(gen.SHAPES))
    check("every drawn shape has an alias entry", set(gen.SHAPES) == set(gen.ALIASES))
    # The window-edge, move and misc names that used to come from Adwaita. Both spellings:
    # the CSS name a compositor asks for and the legacy X name a toolkit asks for.
    for want, target in (("nw-resize", "nwse-resize"), ("se-resize", "nwse-resize"),
                         ("top_left_corner", "nwse-resize"), ("ne-resize", "nesw-resize"),
                         ("bottom_left_corner", "nesw-resize"), ("e-resize", "ew-resize"),
                         ("col-resize", "ew-resize"), ("left_side", "ew-resize"),
                         ("n-resize", "ns-resize"), ("row-resize", "ns-resize"),
                         ("sb_v_double_arrow", "ns-resize"), ("move", "all-resize"),
                         ("fleur", "all-resize"), ("all-scroll", "all-resize"),
                         ("no-drop", "not-allowed"), ("question_arrow", "help"),
                         ("hand1", "grab"), ("cell", "crosshair"), ("vertical-text", "text"),
                         ("pointer", "default"), ("copy", "default")):
        link = os.path.join(cur, want)
        check("%s → %s" % (want, target),
              os.path.islink(link) and os.readlink(link) == target)

    # The new shapes are actually drawn where they should be (design units, 96px frame).
    green = (0, 255, 0)      # the earlier re-run check left the theme green
    def shape96(nm):
        return parse(os.path.join(cur, nm))[-1]
    ew, ns, mv = shape96("ew-resize"), shape96("ns-resize"), shape96("all-resize")
    check("ew-resize: arrowhead on the left", near(at(ew, 7, 16), green), at(ew, 7, 16))
    check("ew-resize: nothing above the shaft", at(ew, 16, 4)[3] == 0)
    check("ns-resize: arrowhead at the top", near(at(ns, 16, 7), green), at(ns, 16, 7))
    check("ns-resize: nothing beside the shaft", at(ns, 4, 16)[3] == 0)
    check("all-resize: both axes", near(at(mv, 7, 16), green) and near(at(mv, 16, 7), green))
    na = shape96("not-allowed")
    check("not-allowed: ring", near(at(na, 16, 7.4), green), at(na, 16, 7.4))
    check("not-allowed: open between ring and slash", at(na, 19.5, 12.5)[3] < 16, at(na, 19.5, 12.5))
    zi, zo = shape96("zoom-in"), shape96("zoom-out")
    check("zoom-in has the vertical bar", near(at(zi, 13.6, 11), green), at(zi, 13.6, 11))
    check("zoom-out doesn't", at(zo, 13.6, 10.3)[3] < 16, at(zo, 13.6, 10.3))

    # ── fast: the stamp skips the drawing when nothing changed ──────────────
    first = os.path.getmtime(os.path.join(cur, "default"))
    tup = lambda h: tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
    check("unchanged colours: nothing redrawn", gen.write_theme(out, tup("#00ff00"), tup(EDGE)) is False)
    check("unchanged colours: files untouched", os.path.getmtime(os.path.join(cur, "default")) == first)
    check("new colour: redrawn", gen.write_theme(out, tup("#ff00ff"), tup(EDGE)) is True)
    os.remove(os.path.join(cur, "text"))
    check("a missing cursor file: redrawn", gen.write_theme(out, tup("#ff00ff"), tup(EDGE)) is True
          and os.path.isfile(os.path.join(cur, "text")))
    os.remove(os.path.join(cur, "top_left_corner"))
    check("a missing alias: redrawn", gen.write_theme(out, tup("#ff00ff"), tup(EDGE)) is True
          and os.path.islink(os.path.join(cur, "top_left_corner")))

    # ── parallel output is byte-identical to serial ─────────────────────────
    a, b = os.path.join(tmp, "serial"), os.path.join(tmp, "pooled")
    gen.write_theme(a, tup(FILL), tup(EDGE), jobs=1)
    gen.write_theme(b, tup(FILL), tup(EDGE), jobs=4)
    same = all(open(os.path.join(a, "cursors", n), "rb").read() == open(os.path.join(b, "cursors", n), "rb").read()
               for n in gen.SHAPES)
    check("pooled render == serial render, byte for byte", same)

    # ── the preview sheet, and --preview-only writing no theme ─────────────
    from PIL import Image
    sheet = os.path.join(tmp, "sub", "sheet.png")
    only = os.path.join(tmp, "only")
    r = subprocess.run([sys.executable, SCRIPT, "--fill", FILL, "--edge", EDGE, "--preview", sheet,
                        "--preview-only", "--out", only], capture_output=True, text=True)
    check("preview-only exits 0", r.returncode == 0, r.stderr)
    im = Image.open(sheet)
    cols = (len(gen.ALIASES) + 1) // 2
    check("preview is an RGBA sheet, two rows of tiles",
          im.mode == "RGBA" and im.size == (cols * 80 + 16, 2 * 80 + 16), im.size)
    check("preview has drawn pixels", im.getchannel("A").getbbox() is not None)
    check("preview-only writes no theme", not os.path.exists(only))

    # ── --apply hands Hyprland the name it is told to, so the caller can alternate ──
    calls = []
    gen._hyprctl = lambda theme, size: calls.append((theme, size)) or 0
    for nm in ("quicktest", "quicktest-b"):
        gen.main(["--fill", FILL, "--edge", EDGE, "--out", os.path.join(tmp, "applied"), "--apply", "--name", nm])
    check("apply passes each name through", calls == [("quicktest", 24), ("quicktest-b", 24)], calls)
    check("apply defaults to the plain name",
          (gen.main(["--fill", FILL, "--edge", EDGE, "--out", os.path.join(tmp, "applied"), "--apply"]),
           calls[-1])[1] == ("quicktest", 24), calls[-1])
    import contextlib, io
    try:
        with contextlib.redirect_stderr(io.StringIO()):     # argparse prints its usage
            gen.main(["--fill", FILL, "--edge", EDGE, "--out", os.path.join(tmp, "x"), "--apply", "--name", "evil"])
        check("rejects an unknown theme name", False)
    except SystemExit as e:
        check("rejects an unknown theme name", e.code == 2, e.code)

    # ── a real directory at the twin's path is left alone ───────────────────
    real = os.path.join(tmp, "own")
    os.makedirs(real + "-b")
    open(os.path.join(real + "-b", "keep"), "w").write("mine")
    gen.write_theme(real, (1, 2, 3), (4, 5, 6))
    check("a real dir at the twin path survives", os.path.isfile(os.path.join(real + "-b", "keep")))

    # ── --revert never needs colours, and asks hyprctl for the default theme ──
    calls = []
    gen._hyprctl = lambda theme, size: calls.append((theme, size)) or 0
    check("revert exits 0", gen.main(["--revert", "--size", "32"]) == 0)
    check("revert asks for the default theme", calls == [("default", 32)], calls)

    # ── trust boundary: colours come from QML ───────────────────────────────
    for bad_col in ("red", "#fff", "#gggggg", "#c4a0ff; rm", "", "c4a0ff"):
        r = subprocess.run([sys.executable, SCRIPT, "--fill", bad_col, "--edge", EDGE,
                            "--out", os.path.join(tmp, "nope")], capture_output=True, text=True)
        check("rejects fill %r" % bad_col, r.returncode == 2 and not os.path.exists(os.path.join(tmp, "nope")),
              "rc=%d" % r.returncode)

print("%d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
