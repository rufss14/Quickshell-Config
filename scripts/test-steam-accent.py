#!/usr/bin/env python3
# ── test-steam-accent.py ─────────────────────────────────────────────────────
# Tests for steam-accent.py: which of Steam's colours are touched and what they become, the
# stylesheet it renders, and the Quick CSS block. Fully local and SAFE TO RUN: temp files only.
#
#   python3 scripts/test-steam-accent.py
# ─────────────────────────────────────────────────────────────────────────────
import os
import sys
import tempfile
from importlib.machinery import SourceFileLoader

HERE = os.path.dirname(os.path.abspath(__file__))
sa = SourceFileLoader("steam_accent", os.path.join(HERE, "steam-accent.py")).load_module()
sc = sa._steam_colors()

PASS = FAIL = 0


def check(name, cond, detail=""):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print("FAIL: %s %s" % (name, detail))


rgb = sc.parse_color
BG, FG, ACCENT = rgb("#0e0000"), rgb("#c3c8cc"), rgb("#ff0000")
BASE = sc.ramp(sc.lightness(rgb("#191919")))

# ── hsl round trip ───────────────────────────────────────────────────────────
for c in ("#1a9fff", "#5c7e10", "#22242a", "#c6d4df", "#ff0000", "#808080"):
    check("hsl round trip " + c, sa.hsl_to_rgb(*sa.rgb_to_hsl(*rgb(c))) == rgb(c), c)

# ── which colours are Steam's ────────────────────────────────────────────────
fam = lambda h: sa.family(*rgb(h))
check("Steam's bright blues are accents", all(fam(c) == "accent" for c in ("#1a9fff", "#26b7ff", "#4cb4ff", "#20aaeb", "#7cc4ff")))
check("Steam's green is an accent", fam("#5c7e10") == "accent")
check("navy surfaces are neutrals", all(fam(c) == "neutral" for c in ("#22242a", "#1b2838", "#171d25", "#2c374a")))
check("slate text is a neutral", all(fam(c) == "neutral" for c in ("#c6d4df", "#8f98a0")))
check("greys are left alone", fam("#808080") is None and fam("#1e1e1f") is None)
check("near-greys with a 3+ level tint are Steam's (the Library Filter's #212124 and #dfe3e6)",
      fam("#212124") == "neutral" and fam("#dfe3e6") == "neutral" and fam("#e0e0e3") == "neutral")
check("a 2-level tint is a grey", fam("#212123") is None and fam("#dfe0e1") is None)
check("warm colours are left alone", all(fam(c) is None for c in ("#ff0000", "#ff6600", "#ffcc6a", "#d2e885" if False else "#ff00ff")))

# ── what they become ─────────────────────────────────────────────────────────
re_ = lambda h: sa.recolor(rgb(h), sa.rgb_to_hsl(*ACCENT), BG, FG, BASE, sc)
r1 = re_("#1a9fff")
h, s, l = sa.rgb_to_hsl(*r1)
check("a blue becomes the accent's hue", abs(h - 0) < 1 or abs(h - 360) < 1, (r1, h))
check("…keeping its lightness", abs(l - sa.rgb_to_hsl(*rgb("#1a9fff"))[2]) < 0.02, (l,))
check("a lighter blue stays lighter than a darker one", sa.rgb_to_hsl(*re_("#7cc4ff"))[2] > sa.rgb_to_hsl(*re_("#1a9fff"))[2])
check("a navy panel lands on the palette's bg layers (at, or just above, bg)",
      sum(re_("#22242a")) >= sum(BG) and sa.rgb_to_hsl(*re_("#22242a"))[2] < 0.1, re_("#22242a"))
check("Steam's main navy (#171d25, a touch above the stock main bg) lands within a few levels of bg",
      all(0 <= a - b <= 6 for a, b in zip(re_("#171d25"), BG)), re_("#171d25"))
check("…and a navy at exactly the stock main bg's lightness lands exactly on it",
      sa.family(19, 24, 32) == "neutral" and re_("#131820") == BG, re_("#131820"))
check("slate text lands near the foreground, not mid-grey", sc.lightness(re_("#c6d4df")) > 0.5, re_("#c6d4df"))
check("a muted accent gives muted results", sa.rgb_to_hsl(*sa.recolor(rgb("#1a9fff"), sa.rgb_to_hsl(*rgb("#6f7a84")), BG, FG, BASE, sc))[1] < 0.2)

# ── the static stylesheet and the variables it reads ─────────────────────────
rules = [
    {"w": [], "s": ".tab._1", "p": "border-bottom-color", "v": "\x010\x01", "c": [[26, 159, 255, 1, "#1a9fff"]]},
    {"w": ["@media (min-width: 600px)"], "s": ".btn:hover", "p": "background-image",
     "v": "linear-gradient(\x010\x01, #ff0000 40%, \x011\x01)", "c": [[26, 159, 255, 1, "#1a9fff"], [34, 36, 42, 0.6, "rgba(34, 36, 42, .6)"]]},
    {"w": [], "s": ".grey", "p": "color", "v": "\x010\x01", "c": [[128, 128, 128, 1, "#808080"]]},      # nothing of Steam's
    {"w": [], "s": ".tab._1", "p": "border-bottom-color", "v": "\x010\x01", "c": [[26, 159, 255, 1, "#1a9fff"]]},   # a duplicate
    {"w": [], "s": ".other", "p": "border-bottom-color", "v": "\x010\x01", "c": [[26, 159, 255, 1, "#1a9fff"]]},   # same block, other selector
    {"w": [], "s": ".frac", "p": "color", "v": "\x010\x01", "c": [[26.4, 159.2, 255, 1, "rgb(26.4 159.2 255)"]]},   # fractional channels
]
css = sa.rules_css(rules)
v1 = sa.variables(rules, BG, FG, ACCENT, BASE)
check("declarations read variables, never the literal", "var(--qs-1a9fffff)" in css and "#1a9fff" not in css.lower(), css)
check("every !important", css.count("!important") >= 3 and "!important}" in css)
check("a wrapper is kept around its rule", "@media (min-width: 600px){" in css and css.index("@media") < css.index(".btn:hover"), css)
check("the other gradient stops survive", "#ff0000 40%" in css)
check("a declaration with nothing of Steam's is dropped", ".grey" not in css)
check("a duplicate is emitted once", css.count(".tab._1") == 1)
check("selectors with an identical block are grouped", ".tab._1,.other{" in css or ".other,.tab._1{" in css, css)
check("fractional channels don't break the name", "var(--qs-1a9fffff)" in css and sa.var_name([26.4, 159.2, 255, 1]) == "--qs-1a9fffff")
check("alpha is part of the variable's identity", "--qs-22242a99" in css, css)
check("rendering is deterministic", sa.rules_css(rules) == css)
check("no rules → a header only", sa.rules_css([]).count("\n") == 1)

import re as _re
used = set(_re.findall(r"var\((--qs-[0-9a-f]{8})\)", css))
check("every variable the stylesheet reads has a value", used and used <= set(v1), (used, set(v1)))
check("a blue's variable holds the accent hue", sa.rgb_to_hsl(*sc.parse_color(v1["--qs-1a9fffff"]))[1] > 0.5
      and (sa.rgb_to_hsl(*sc.parse_color(v1["--qs-1a9fffff"]))[0] < 1 or sa.rgb_to_hsl(*sc.parse_color(v1["--qs-1a9fffff"]))[0] > 359), v1)
check("an alpha colour's variable is rgba() with its alpha", v1["--qs-22242a99"].startswith("rgba(") and v1["--qs-22242a99"].endswith(",0.6)"), v1["--qs-22242a99"])
v2 = sa.variables(rules, rgb("#f4f1ea"), rgb("#2a2b2c"), rgb("#00aa44"), BASE)
check("a different palette changes the variables…", v1 != v2 and v1.keys() == v2.keys())
check("…and not the stylesheet (it has no palette input)", sa.rules_css(rules) == css)
check("an accent-less colour isn't given a variable", all("808080" not in k for k in v1))

# ── Quick CSS: ours is a block, the user's own CSS is never touched ──────────
mine = ".a{color:#fff}\n"
check("added to an empty file", sa.merge_quickcss("", mine).startswith(sa.BEGIN) and sa.merge_quickcss("", mine).rstrip().endswith(sa.END))
user = "/* mine */\nbody { opacity: .99 }\n"
once = sa.merge_quickcss(user, mine)
check("appended after the user's CSS, which is intact", once.startswith(user) and mine in once)
twice = sa.merge_quickcss(once, ".b{color:#000}\n")
check("replaced in place, not stacked", twice.count(sa.BEGIN) == 1 and ".b{color:#000}" in twice and ".a{" not in twice)
check("the user's CSS survives a replace", twice.startswith(user))
after = sa.merge_quickcss(user + sa.BEGIN + "\nold\n" + sa.END + "\n/* tail */\n", mine)
check("CSS after our block survives", after.rstrip().endswith("/* tail */"))
check("merge is idempotent", sa.merge_quickcss(once, mine) == once)
check("strip removes only ours", sa.strip_quickcss(once).strip() == user.strip(), repr(sa.strip_quickcss(once)))
check("an unterminated marker doesn't eat the file", sa.strip_quickcss(user + sa.BEGIN + "\nhalf") == user + sa.BEGIN + "\nhalf")

with tempfile.TemporaryDirectory() as tmp:
    p = os.path.join(tmp, "m", "quick.css")
    check("write creates the file", sa.write_quickcss(p, mine) is True and os.path.exists(p))
    check("an identical write reports no change", sa.write_quickcss(p, mine) is False)
    check("no temp file left", os.listdir(os.path.dirname(p)) == ["quick.css"])

print("%d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
