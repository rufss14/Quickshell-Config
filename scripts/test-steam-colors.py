#!/usr/bin/env python3
# ── test-steam-colors.py ─────────────────────────────────────────────────────
# Tests for steam-colors.py. Fully local and SAFE TO RUN: every case writes into a
# throwaway temp dir, and the real ~/.config/millennium/config.json is never opened.
#
#   python3 scripts/test-steam-colors.py
# ─────────────────────────────────────────────────────────────────────────────
import json
import os
import sys
import tempfile
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
_STATE = tempfile.mkdtemp()      # the accent cache lives under XDG_STATE_HOME: never read the real one
os.environ["XDG_STATE_HOME"] = _STATE
sc = SourceFileLoader("steam_colors", os.path.join(HERE, "steam-colors.py")).load_module()

PASS = 0
FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("FAIL: %s %s" % (name, detail))


def wal(bg="#0c1a1b", fg="#c2c5c6", cursor="#c2c5c6"):
    colors = {"color%d" % i: "#%02x%02x%02x" % (i * 16, 255 - i * 16, 40 + i * 8) for i in range(16)}
    return {"special": {"background": bg, "foreground": fg, "cursor": cursor}, "colors": colors}


def rgb(h):
    return sc.parse_color(h)


with tempfile.TemporaryDirectory() as tmp:
    def put(name, text):
        p = os.path.join(tmp, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "w") as f:
            f.write(text if isinstance(text, str) else json.dumps(text))
        return p

    # ── colour parsing ───────────────────────────────────────────────────────
    check("hex6", rgb("#212121") == (33, 33, 33))
    check("hex3", rgb("#fa0") == (255, 170, 0))
    check("rgb()", rgb("rgb(48, 48, 48)") == (48, 48, 48))
    check("rgba()", rgb("rgba(1,2,3,0.5)") == (1, 2, 3))
    check("not a colour", rgb("blur(10px)") is None and rgb("4px") is None)

    # ── the ramp ─────────────────────────────────────────────────────────────
    bg, fg = rgb("#0c1a1b"), rgb("#c2c5c6")
    stock = dict(sc.STOCK)
    colors = [rgb("#%02x%02x%02x" % (i * 16, 255 - i * 16, 40 + i * 8)) for i in range(16)]
    out = sc.derive(bg, fg, colors, stock)
    check("white reaches the foreground", out["--white"] == "#c2c5c6", out["--white"])
    check("black is the background", out["--black"] == "#0c1a1b", out["--black"])
    check("the theme's MAIN background is exactly the palette background", out["--color-darker"] == "#0c1a1b", out["--color-darker"])
    check("…and what is darker than it is clamped there, never below",
          out["--color-darkest"] == "#0c1a1b" and out["--darkergrey"] == "#0c1a1b")
    check("…while lighter layers still step above it",
          out["--color-dark"] != "#0c1a1b" and sc.lightness(rgb(out["--color-dark"])) > sc.lightness(bg))
    # Monotone: a lighter stock grey never lands closer to the background than a darker one.
    order = sorted((n for n in stock if n not in sc.HUES and sc.parse_color(stock[n])),
                   key=lambda n: sc.lightness(rgb(stock[n])))
    dist = [sum(abs(a - b) for a, b in zip(rgb(out[n]), bg)) for n in order]
    check("ramp is monotone", all(a <= b for a, b in zip(dist, dist[1:])), str(dist))
    check("dark surfaces stay dark", sc.lightness(rgb(out["--color-dark"])) < 0.2)
    check("status hues come from the palette", out["--ingame"] == "#%02x%02x%02x" % tuple(colors[2])
          and out["--online"] == "#%02x%02x%02x" % tuple(colors[6]))
    check("pywal names are still written", out["--color3"] == "#%02x%02x%02x" % tuple(colors[3])
          and out["--background"] == "#0c1a1b" and out["--cursor"] == "#c2c5c6")
    check("every stock variable is covered", all(n in out for n in stock))

    # A light palette (bg lighter than fg) keeps the same orientation: darks near bg, whites at fg.
    lo = sc.derive(rgb("#f4f1ea"), rgb("#2a2b2c"), colors, stock)
    check("light palette white → fg", lo["--white"] == "#2a2b2c" and lo["--black"] == "#f4f1ea")
    check("light palette: main background is still the palette background", lo["--color-darker"] == "#f4f1ea", lo["--color-darker"])

    # ── stock values come from colors.css, not from the config ───────────────
    theme = os.path.join(tmp, "theme")
    put("theme/colors.css", ":root {\n /** @name x */\n --color-dark: #101010;\n --brand-new: #808080;\n"
                            " --radius: 4px;\n}\n")
    ts = sc.theme_stock(theme)
    check("colors.css overrides the shipped value", ts["--color-dark"] == "#101010")
    check("a variable the theme added is picked up", ts.get("--brand-new") == "#808080")
    check("a non-colour declaration is ignored", "--radius" not in ts)
    check("shipped table is the fallback", sc.theme_stock(os.path.join(tmp, "nope")) == sc.STOCK)

    # ── end to end ───────────────────────────────────────────────────────────
    wal_path = put("wal/colors.json", wal())
    base = {"general": {"accentColor": "X"}, "themes": {"activeTheme": "simply-dark",
            "themeColors": {"Material-Theme": {"--m": "#123456"}, "simply-dark": {"--grey": "#2e2e2f", "--keep": "1"}}}}
    cfg = put("cfg/config.json", base)
    check("exit 0", sc.main([cfg, wal_path, "--theme-dir", theme]) == 0)
    first = json.load(open(cfg))
    check("other themes untouched", first["themes"]["themeColors"]["Material-Theme"] == {"--m": "#123456"})
    check("unrelated config untouched", first["general"] == {"accentColor": "X"}
          and first["themes"]["activeTheme"] == "simply-dark")
    check("unknown key in our block kept", first["themes"]["themeColors"]["simply-dark"]["--keep"] == "1")
    check("variable written", first["themes"]["themeColors"]["simply-dark"]["--grey"] != "#2e2e2f")
    sc.main([cfg, wal_path, "--theme-dir", theme])
    check("idempotent (no drift on re-run)", json.load(open(cfg)) == first)
    check("no temp files left behind", [f for f in os.listdir(os.path.dirname(cfg)) if f.endswith(".tmp")] == [])

    # ── bad input never touches the config ───────────────────────────────────
    before = open(cfg).read()
    check("bad palette → nonzero", sc.main([cfg, put("wal/bad.json", {"special": {}}), "--theme-dir", theme]) == 2)
    check("garbage palette → nonzero", sc.main([cfg, put("wal/garbage.json", "{nope"), "--theme-dir", theme]) == 2)
    check("missing config → nonzero", sc.main([os.path.join(tmp, "absent.json"), wal_path, "--theme-dir", theme]) == 2)
    check("config left as it was", open(cfg).read() == before)
    check("preview writes nothing", sc.main([cfg, wal_path, "--theme-dir", theme, "--preview"]) == 0
          and open(cfg).read() == before)

print("%d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
