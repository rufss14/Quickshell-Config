#!/usr/bin/env python3
"""
The Quicktest Discord theme: its palette script, and the rules its CSS keeps.

    python3 scripts/test-discord-theme.py             run the checks
    python3 scripts/test-discord-theme.py --hashes    list the hashed Discord classes the theme depends on

Not a render: nothing here loads Discord. A pass means "the palette is the shell's palette, the
file is well-formed and keeps the project's colour rule", not "it looks right".
"""
import json, os, re, shutil, subprocess, sys, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # derived: this config is published
THEME = os.path.join(ROOT, "vencord", "quicktest.theme.css")
PALETTE = os.path.join(ROOT, "scripts", "themes", "discord", "quicktest-theme.py")
PWSPICE = os.path.join(ROOT, "scripts", "themes", "spotify", "pwspice.py")

BEGIN, END = "/* qs-palette:begin", "/* qs-palette:end */"
SHAPE_BEGIN, SHAPE_END = "/* qs-shape:begin", "/* qs-shape:end */"
DEFAULT_MOTION = ("respond", "fast", "standard", "emphasized", "exit", "slow", "ripple", "spring-fast", "spring")


def strip_comments_and_strings(css):
    css = re.sub(r"/\*.*?\*/", " ", css, flags=re.S)
    return re.sub(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', '""', css)


def outside_palette(css):
    a, b = css.index(BEGIN), css.index(END) + len(END)
    return css[:a] + css[b:]


def hashed_classes(css):
    body = strip_comments_and_strings(outside_palette(css))
    return sorted(set(re.findall(r"\.[A-Za-z][A-Za-z0-9]*_{1,2}[0-9a-f]{5,6}\b", body)))


if "--hashes" in sys.argv:
    for c in hashed_classes(open(THEME, encoding="utf-8").read()):
        print(c)
    sys.exit(0)


def ok(msg):
    print("  ok  " + msg)


def luminance(h):
    def lin(v):
        s = v / 255
        return s / 12.92 if s <= 0.03928 else ((s + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(int(h.lstrip("#")[i:i + 2], 16)) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)


tmp = tempfile.mkdtemp(prefix="qs-discord-theme-")
os.environ["XDG_RUNTIME_DIR"] = tmp   # the script's lock lives here, not in the real runtime dir


def run(css, colors, *extra):
    return subprocess.run([sys.executable, PALETTE, "--css", css, "--colors", colors, *extra],
                          capture_output=True, text=True)


def wal(name, background, foreground, ramp):
    p = os.path.join(tmp, name)
    json.dump({"special": {"background": background, "foreground": foreground, "cursor": foreground},
               "colors": {f"color{i}": c for i, c in enumerate(ramp)}}, open(p, "w"))
    return p


def read_block(css_path):
    text = open(css_path, encoding="utf-8").read()
    return dict(re.findall(r"--qs-([\w-]+):\s*([^;]+);", text[text.index(BEGIN):text.index(END)]))


# The two palettes: a dark one whose color1 is deliberately illegible against its background
# (the shell measured exactly that on a real wallpaper), and a light one.
DARK = wal("dark.json", "#0a1f3a", "#e0f0ff",
           ["#0a1f3a", "#1a2f4a", "#4a5f7a", "#324762", "#4c5f77", "#70839b", "#263b56", "#e0f0ff",
            "#55687f", "#43546b", "#6b7c92", "#57687e", "#6c7c90", "#899aad", "#4d5e74", "#e5f2ff"])
LIGHT = wal("light.json", "#f4f1ea", "#1c1c1c",
            ["#f4f1ea", "#7a2e2e", "#2e6b3a", "#8a6a1a", "#2d4f8a", "#6a3a7a", "#1f6a6a", "#1c1c1c",
             "#666666", "#9a4040", "#408a50", "#a88530", "#4068a8", "#8a5098", "#308a8a", "#101010"])

print("=== the palette script ===")
css = os.path.join(tmp, "quicktest.theme.css")
shutil.copy(THEME, css)
before = open(css, encoding="utf-8").read()

r = run(css, DARK)
assert r.returncode == 0, r.stderr
b = read_block(css)
assert b["base"] == "#0a1f3a", b["base"]
assert contrast(b["primary"], b["base"]) >= 4.5, "primary must clear the shell's 4.5:1 floor"
assert contrast(b["focus"], b["base"]) >= 4.5, "focus must clear the shell's 4.5:1 floor"
assert b["on-primary"] == b["base"], "text drawn ON the accent is the base (fgOnPrimary)"
assert (b["a-outline"], b["a-dim"], b["a-faint"]) == ("22%", "58%", "30%"), b
ok("dark palette: base kept, primary and focus floored at 4.5:1, dark-mode alphas")

spec = __import__("importlib.util").util.spec_from_file_location("pwspice", PWSPICE)
pw = __import__("importlib.util").util.module_from_spec(spec); spec.loader.exec_module(pw)
palette, special = pw.load_pywal(__import__("pathlib").Path(DARK))
want = pw.generate_spicetify_colors(palette, special)
assert b["primary"] == "#" + want["button"].lower() and b["focus"] == "#" + want["button-active"].lower()
ok("primary/focus are the SAME colours QuickSpice gets (one derivation, pwspice.py)")

after = open(css, encoding="utf-8").read()
a1, a2 = before.index(BEGIN), before.index(END) + len(END)
c1, c2 = after.index(BEGIN), after.index(END) + len(END)
assert before[:a1] == after[:c1] and before[a2:] == after[c2:], "only the marker block may change"
ok("everything outside the marker block is byte-identical")

m1 = os.stat(css).st_mtime_ns
r = run(css, DARK)
assert r.returncode == 0 and os.stat(css).st_mtime_ns == m1, "an unchanged palette must not rewrite the file"
ok("unchanged palette: no write (Vencord re-parses the theme on any write)")
assert not os.path.exists(css + ".qs-new"), "temp file left behind"
ok("atomic write leaves no .qs-new behind")

r = run(css, LIGHT)
assert r.returncode == 0, r.stderr
b = read_block(css)
assert contrast(b["primary"], b["base"]) >= 4.5 and b["base"] == "#f4f1ea"
assert (b["a-outline"], b["a-dim"], b["a-faint"]) == ("32%", "62%", "45%"), b
assert (b["a-shadow-card"], b["a-shadow-popup"]) == ("16%", "22%"), b
ok("light palette: legible accent on a light base, the shell's light-mode alphas and softer shadows")

for k, v in read_block(css).items():
    if k.startswith(("base", "text", "primary", "focus", "on-primary", "shadow")):
        assert re.fullmatch(r"#[0-9a-f]{6}", v), (k, v)
ok("every colour in the block is a lowercase #rrggbb")

untouched = open(css, encoding="utf-8").read()
r = run(css, os.path.join(tmp, "missing.json"))
assert r.returncode == 2 and open(css, encoding="utf-8").read() == untouched
ok("no palette file: exit 2, theme untouched")
open(os.path.join(tmp, "empty.json"), "w").write("{}")
r = run(css, os.path.join(tmp, "empty.json"))
assert r.returncode == 2 and open(css, encoding="utf-8").read() == untouched
ok("empty palette: exit 2, theme untouched")
for name, text in (("none", "body { color: red }\n"), ("twice", before + before)):
    bad = os.path.join(tmp, f"{name}.css")
    open(bad, "w").write(text)
    r = run(bad, DARK)
    assert r.returncode == 2 and open(bad).read() == text, name
ok("a theme without exactly one marker block is refused, not overwritten")
r = run(css, DARK, "--preview")
assert r.returncode == 0 and BEGIN in r.stdout and open(css, encoding="utf-8").read() == untouched
ok("--preview prints the block and writes nothing")

print("\n=== Type & Shape ===")
def shape(css_path, obj, *extra):
    return subprocess.run([sys.executable, PALETTE, "--css", css_path, "--shape", json.dumps(obj), *extra],
                          capture_output=True, text=True)

def read_shape(css_path):
    text = open(css_path, encoding="utf-8").read()
    return dict(re.findall(r"--qs-([\w-]+):\s*([^;]+);", text[text.index(SHAPE_BEGIN):text.index(SHAPE_END)]))

# The committed block IS the script's defaults, and so the shell's defaults: a first push at launch
# on an untouched install must change nothing.
css2 = os.path.join(tmp, "shape.theme.css")
shutil.copy(THEME, css2)
m0 = os.stat(css2).st_mtime_ns
assert shape(css2, {}).returncode == 0 and os.stat(css2).st_mtime_ns == m0, "defaults must be byte-identical to the committed block"
ok("the committed shape block is exactly the defaults (a launch-time push on a fresh install writes nothing)")

# What Settings -> Type & Shape would send at 1.25x spacing, 0.5x roundness, square corners off, a
# different face, no animations and no shadows.
custom = {"spacing": {"xs": 3, "sm": 5, "md": 10, "lg": 15, "xl": 20, "xxl": 30},
          "radius": {"xs": 2, "sm": 4, "pill": 6, "card": 8, "xl": 12},
          "font": "Noto Sans (CJK)", "mono": "Fira Code",
          "motion": {k: 0 for k in DEFAULT_MOTION}, "shadow": None}
r = shape(css2, custom)
assert r.returncode == 0, r.stderr
sh = read_shape(css2)
assert sh["sp-lg"] == "15px" and sh["r-card"] == "8px" and sh["t-slow"] == "0ms" and sh["shadow-card"] == "none", sh
assert sh["font"].startswith('"Noto Sans (CJK)", ') and sh["font"].endswith("monospace"), sh["font"]
ok("scaled spacing and radii, another face, motion off and shadows off all reach the block")
before_pal = read_block(css2)
r = run(css2, DARK)
assert r.returncode == 0 and read_shape(css2) == sh, "a palette run must not touch the shape block"
assert read_block(css2)["base"] == "#0a1f3a" and before_pal["base"] != "#0a1f3a"
ok("a palette recolour leaves Type & Shape alone, and a shape push leaves the palette alone")

m1 = os.stat(css2).st_mtime_ns
assert shape(css2, custom).returncode == 0 and os.stat(css2).st_mtime_ns == m1
ok("an unchanged shape writes nothing")
snapshot = open(css2, encoding="utf-8").read()
for name, bad in (("font closes the string", {"font": 'x"; } body { display:none } /*'}),
                  ("font has a backslash", {"font": "a\\b"}), ("font is empty", {"font": ""}),
                  ("not a number", {"spacing": {"lg": "12px"}}), ("negative radius", {"radius": {"card": -1}}),
                  ("absurd duration", {"motion": {"slow": 10**9}}), ("NaN", {"radius": {"card": float("nan")}}),
                  ("unknown group", {"colors": {}}), ("unknown spacing key", {"spacing": {"huge": 1}}),
                  ("shadow wrong type", {"shadow": "big"}), ("bool as number", {"radius": {"card": True}})):
    r = subprocess.run([sys.executable, PALETTE, "--css", css2, "--shape", json.dumps(bad, allow_nan=True)], capture_output=True, text=True)
    assert r.returncode == 2 and open(css2, encoding="utf-8").read() == snapshot, (name, r.returncode, r.stderr)
r = subprocess.run([sys.executable, PALETTE, "--css", css2, "--shape", "{not json"], capture_output=True, text=True)
assert r.returncode == 2 and open(css2, encoding="utf-8").read() == snapshot
ok("hostile or malformed shapes (a font that closes the string, wrong types, NaN, unknown keys) are refused and write nothing")

# Icon shape. The petalled outlines are generated, not typed: WHEN the committed theme defines
# them at all (it doesn't while scaled back to colours + progress bar only, 2026-11-01 — nothing
# in the file references an icon-shape clip-path any more), they must be what the generator makes,
# and the cookie must be the one QuickSpice already draws (so the two themes show the same shape).
spec2 = __import__("importlib.util").util.spec_from_file_location("qt", PALETTE)
qt = __import__("importlib.util").util.module_from_spec(spec2); spec2.loader.exec_module(qt)
src_all = open(THEME, encoding="utf-8").read()
def committed(name):
    m = re.search(r"--qs-clip-%s: ([^;]+);" % name, src_all)
    return m.group(1) if m else None
if committed("cookie") is not None:
    for name, (n, depth) in qt.PETALS.items():
        assert committed(name) == qt.scallop_polygon(n, depth), name
        assert committed(name + "-hot") == qt.scallop_polygon(n, depth + qt.HOT_DEPTH), name + "-hot"
        assert committed(name).count("%,") + 1 == committed(name + "-hot").count("%,") + 1 == 120, "rest and hot must have equal vertex counts to interpolate"
    qs_css = open(os.path.join(ROOT, "spicetify", "Themes", "QuickSpice", "user.css"), encoding="utf-8").read()
    assert committed("cookie") == re.search(r"--qs-mark: (polygon\([^;]*\));", qs_css).group(1), "the cookie must be QuickSpice's"
    ok("the committed cookie and clover outlines are the generator's (rest and hot, 120 vertices each); the cookie is QuickSpice's")
else:
    ok("icon-shape polygons aren't defined in this theme right now (colours + progress bar only) — skipped")

expect = {"default": ("cookie", "cookie-hot", "rounded", "rounded"), "cookie": ("cookie", "cookie-hot", "cookie", "cookie-hot"),
          "clover": ("clover", "clover-hot", "clover", "clover-hot"), "squircle": ("squircle",) * 4, "circle": ("circle",) * 4}
for icon, (h, hh, b, bh) in expect.items():
    css4 = os.path.join(tmp, f"icon-{icon}.css"); shutil.copy(THEME, css4)
    assert shape(css4, {"icon": icon}).returncode == 0
    got = read_shape(css4)
    assert (got["clip-holder"], got["clip-holder-hot"], got["clip-button"], got["clip-button-hot"]) == tuple(f"var(--qs-clip-{x})" for x in (h, hh, b, bh)), (icon, got)
ok("each Icon shape maps to the right holder and button outline (default = cookie holder, rounded-square button; petalled ones deepen on hover)")
assert shape(css2, {"icon": "triangle"}).returncode == 2 and shape(css2, {"icon": 3}).returncode == 2
ok("an icon shape the shell doesn't have is refused")

# Two writers, one file: the wave's recolour and a Type & Shape push. A race between two fast processes
# almost never lands inside the read-modify-write window, so this does not try to catch one: it holds the
# lock itself and checks that a writer WAITS for it, which is the whole mechanism (and fails without it).
import fcntl, time
css3 = os.path.join(tmp, "race.theme.css"); shutil.copy(THEME, css3)
held = open(os.path.join(tmp, "quicktest-discord-theme.lock"), "w")
fcntl.flock(held, fcntl.LOCK_EX)
procs = [subprocess.Popen([sys.executable, PALETTE, "--css", css3, *a], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
         for a in (["--colors", DARK], ["--shape", json.dumps({"radius": {"card": 9}})])]
time.sleep(0.8)
assert all(p.poll() is None for p in procs), "a writer ran while another held the lock"
assert open(css3, encoding="utf-8").read() == open(THEME, encoding="utf-8").read(), "a writer wrote without the lock"
fcntl.flock(held, fcntl.LOCK_UN)
for p in procs:
    p.wait(timeout=10); assert p.returncode == 0, p.stderr.read()
assert read_shape(css3)["r-card"] == "9px" and read_block(css3)["base"] == "#0a1f3a", "after the lock is released BOTH updates must land"
assert not os.path.exists(css3 + ".qs-new")
ok("a recolour and a Type & Shape push both wait for the lock, then both land (neither overwrites the other)")
assert subprocess.run([sys.executable, PALETTE, "--css", css3, "--shape", "{}", "--colors", DARK, "--preview"],
                      capture_output=True, text=True).stdout.count("qs-") > 0
ok("--preview prints both blocks when both are asked for")

print("\n=== the theme file ===")
src = open(THEME, encoding="utf-8").read()
assert src.count(BEGIN) == 1 and src.count(END) == 1 and src.index(BEGIN) < src.index(END)
assert src.count(SHAPE_BEGIN) == 1 and src.count(SHAPE_END) == 1 and src.index(SHAPE_BEGIN) < src.index(SHAPE_END)
ok("exactly one palette block and one shape block")
assert re.search(r"@name\s+Quicktest\b", src[:600]), "Vencord reads @name from the header"
ok("header carries the @name Vencord reads")

body = strip_comments_and_strings(src)
stack, pairs = [], {")": "(", "]": "[", "}": "{"}
for i, ch in enumerate(body):
    if ch in "([{":
        stack.append(ch)
    elif ch in ")]}":
        assert stack and stack.pop() == pairs[ch], f"unbalanced {ch!r} near: {body[max(0, i - 60):i + 10]!r}"
assert not stack, f"unclosed {stack}"
ok("(), [] and {} balance")

assert "@import" not in body and not re.search(r"url\(\s*['\"]?https?:", src), "the theme must not load anything remote"
ok("no @import and no remote url(): nothing third-party is fetched at runtime")

# The colour rule: there is no hex colour (or rgb()/hsl()/oklch(), or a colour name) outside the palette block.
NAMED = r"\b(white|black|red|green|blue|yellow|orange|purple|pink|gray|grey|lime|magenta|cyan|brown|navy|teal|gold)\b"
rest = strip_comments_and_strings(outside_palette(src))
bad = []
for blk in re.findall(r"\{([^{}]*)\}", rest):
    for decl in blk.split(";"):
        if ":" not in decl:
            continue
        prop, val = decl.split(":", 1)
        val = re.sub(r"var\(--[\w-]+", "var(", val)          # a variable NAME is not a colour word
        if re.search(r"#[0-9a-fA-F]{3,8}\b|\b(rgba?|hsla?|hwb|lab|lch|oklab|oklch)\(", val) or re.search(NAMED, val, re.I):
            bad.append(decl.strip())
assert not bad, "hardcoded colour outside the palette block:\n    " + "\n    ".join(bad)
ok("no hardcoded colour outside the palette block")

used = set(re.findall(r"var\(\s*(--qs-[\w-]+)", rest))
defined = set(re.findall(r"(--qs-[\w-]+)\s*:", src))
missing = sorted(used - defined)
assert not missing, f"var() of a --qs token nothing defines: {missing}"
ok(f"all {len(used)} --qs tokens in use are defined")

dupes = []
for blk in re.findall(r"\{([^{}]*)\}", rest):
    seen = set()
    for decl in blk.split(";"):
        if ":" not in decl:
            continue
        prop = decl.split(":", 1)[0].strip()
        if prop in seen:
            dupes.append(prop)
        seen.add(prop)
assert not dupes, f"a property set twice in one rule: {sorted(set(dupes))}"
ok("no property is set twice in one rule")

if "@container qs" in body:
    assert re.search(r"\bbody\s*\{[^}]*container-name:\s*qs\b", body), "@container qs needs a named ancestor"
    ok("every @container qs has its container-name on <body>")

# Scaled back to colours + a guild-rail selection highlight + the WaveSlider progress bar
# (2026-11-01, docs/discord.md): no panel shapes, no icon clips, no top-rail rotation, no
# settings-modal reposition — those are left to Discord's own look or another theme (Discord
# Mica) layered alongside this one. Guards against any of that creeping back in under a
# different name rather than asserting what replaced it, since nothing did.
for leftover in ("--qs-rail", "rotate: -90deg", "--qs-mica-", "--qs-track-fill", "layer__960e4"):
    assert leftover not in body, f"scaled back — {leftover!r} shouldn't be back"
ok("stays colours + guild-rail highlight + WaveSlider progress bar only — no panel/shape/modal styling crept back in")

shutil.rmtree(tmp, ignore_errors=True)
print(f"\nPASSED  ({len(hashed_classes(src))} hashed Discord classes depended on; --hashes lists them)")
