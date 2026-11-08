#!/usr/bin/env python3
# ── hypr-config.py ────────────────────────────────────────────────────────────
# Read (and, later, write) the user's native-Lua Hyprland config for the shell's
# Hyprland customization page. The config is Hyprland 0.56 Lua (the `hl.*` API),
# NOT hyprlang — so hyprctl can't round-trip it (binds show as `__lua` callbacks),
# and the source files are the only honest source of truth for what a bind DOES.
#
# This stage is READ ONLY: it parses binds.lua / blend.lua / appearance.lua /
# animation.lua / hardware.lua / env.lua into JSON,
# carrying each editable value's file + line span so a later write pass can rewrite
# exactly that span and nothing else. Anything it can't round-trip safely (a
# for-loop of binds, a raw `function() ... end` bind) is emitted with editable=false
# rather than guessed at — in-place editing must never touch what it can't re-read.
#
# Usage:  hypr-config.py read [--dir ~/.config/hypr]
import sys, os, re, json, shutil, subprocess, datetime

HYPR_DIR = os.path.expanduser("~/.config/hypr")

# ── Small helpers ─────────────────────────────────────────────────────────────
def read_lines(path):
    try:
        with open(path, "r") as f:
            return f.read().split("\n")
    except FileNotFoundError:
        return None

SECTION_RE = re.compile(r"^\s*--\s*[─-]{2,}\s*(.+?)\s*[─-]{2,}\s*$")
def section_of(line):
    m = SECTION_RE.match(line)
    return m.group(1).strip() if m else None

# ── Alias resolution (env.lua globals) ────────────────────────────────────────
# `mainMod = "SUPER"`, `terminal = "kitty"`, etc. — bare-global string assignments.
ALIAS_RE = re.compile(r'^\s*([A-Za-z_]\w*)\s*=\s*"([^"]*)"\s*(?:--.*)?$')
def parse_aliases(core_lines):
    aliases = {}
    for ln in core_lines or []:
        m = ALIAS_RE.match(ln)
        if m and not ln.lstrip().startswith("--"):
            aliases[m.group(1)] = m.group(2)
    return aliases

# Resolve a Lua string EXPRESSION built from ".."-joined literals and aliases.
# Returns (text, dynamic): dynamic=True if a term couldn't be resolved statically
# (e.g. the loop variable `key`), in which case `text` holds a best-effort form.
def resolve_str(expr, aliases):
    terms = [t.strip() for t in expr.split("..")]
    out, dynamic = [], False
    for t in terms:
        sm = re.fullmatch(r'"([^"]*)"', t)
        if sm:
            out.append(sm.group(1)); continue
        if t in aliases:
            out.append(aliases[t]); continue
        # unresolved identifier (loop var, unknown) — keep a placeholder
        out.append("{" + t + "}")
        dynamic = True
    return "".join(out), dynamic

# Normalise "SUPER  +  C" / "SUPER + SHIFT + F" into a clean combo string.
def norm_combo(s):
    parts = [p.strip() for p in s.split("+") if p.strip()]
    return " + ".join(parts)

# ── binds.lua ─────────────────────────────────────────────────────────────────
# Find every hl.bind(...) call. Balanced-paren scan (options tables and nested
# dispatch calls contain commas we must not split on).
def find_calls(text, name):
    calls, i, n = [], 0, len(text)
    needle = name + "("
    while True:
        j = text.find(needle, i)
        if j < 0:
            break
        k = j + len(needle)
        depth, in_str, esc, quote = 1, False, False, ""
        while k < n and depth > 0:
            c = text[k]
            if in_str:
                if esc: esc = False
                elif c == "\\": esc = True
                elif c == quote: in_str = False
            else:
                if c in "\"'": in_str, quote = True, c
                elif c == "(": depth += 1
                elif c == ")": depth -= 1
            k += 1
        calls.append((j, k, text[j+len(needle):k-1]))  # start, end, inner-args
        i = k
    return calls

# Split top-level comma-separated args, respecting (), {}, strings.
def split_args(s):
    args, depth, in_str, esc, quote, start = [], 0, False, False, "", 0
    for i, c in enumerate(s):
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == quote: in_str = False
        else:
            if c in "\"'": in_str, quote = True, c
            elif c in "([{": depth += 1
            elif c in ")]}": depth -= 1
            elif c == "," and depth == 0:
                args.append(s[start:i]); start = i + 1
    args.append(s[start:])
    return [a.strip() for a in args]

DISPATCH_LABEL = {
    "window.close": "Close active window",
    "exit": "Exit Hyprland",
    "window.fullscreen": "Toggle fullscreen",
    "window.fullscreen_state": "Fake fullscreen",
    "window.float": "Toggle floating",
    "window.move": "Move window to workspace",
    "window.drag": "Drag window (mouse)",
    "window.resize": "Resize window (mouse)",
    "layout": "Layout action",
    "focus": "Focus",
    "exec_cmd": "Run",
}

def offset_to_line(text, off):
    return text.count("\n", 0, off) + 1

# Character spans of `for ... do ... end` blocks, so bind calls generated by a
# loop are handled once (as a range) instead of also counted as literal binds.
def loop_spans(text):
    return [(m.start(), m.end())
            for m in re.finditer(r"\bfor\b.*?\bdo\b.*?\bend\b", text, re.S)]

def in_any_span(off, spans):
    return any(a <= off < b for (a, b) in spans)

def parse_binds(text, aliases):
    binds = []
    spans = loop_spans(text)
    # section headers by line
    lines = text.split("\n")
    sec_by_line, cur = {}, ""
    for idx, ln in enumerate(lines, 1):
        s = section_of(ln)
        if s: cur = s
        sec_by_line[idx] = cur

    for (start, end, inner) in find_calls(text, "hl.bind"):
        if in_any_span(start, spans):
            continue  # generated by a for-loop — see parse_bind_loops
        line = offset_to_line(text, start)
        end_line = offset_to_line(text, end)
        args = split_args(inner)
        if len(args) < 2:
            continue
        key_expr, action_expr = args[0], args[1]
        opts_expr = args[2] if len(args) > 2 else ""

        combo, dyn = resolve_str(key_expr, aliases)
        combo = norm_combo(combo)

        desc = ""
        dm = re.search(r'description\s*=\s*"([^"]*)"', opts_expr)
        if dm: desc = dm.group(1)
        mouse = "mouse = true" in opts_expr or "mouse:" in key_expr

        editable = True
        act = {"type": "unknown", "name": "", "args": "", "text": action_expr.strip()}
        a = action_expr.strip()
        if a.startswith("function"):
            act = {"type": "function", "name": "", "args": "", "text": "custom Lua function"}
            editable = False
        else:
            dm2 = re.match(r"hl\.dsp\.([A-Za-z_][\w.]*)\s*\((.*)\)\s*$", a, re.S)
            if dm2:
                dname, dargs = dm2.group(1), dm2.group(2).strip()
                if dname == "exec_cmd":
                    cmd, cdyn = resolve_str(dargs, aliases) if dargs else ("", False)
                    act = {"type": "exec", "name": "exec_cmd", "args": cmd,
                           "text": "Run: " + cmd}
                else:
                    label = DISPATCH_LABEL.get(dname, dname)
                    detail = ""
                    tm = re.search(r'workspace\s*=\s*"?([\w+-]+)"?', dargs)
                    dm3 = re.search(r'direction\s*=\s*"(\w+)"', dargs)
                    if dm3: detail = " " + dm3.group(1)
                    elif tm: detail = " " + tm.group(1)
                    act = {"type": "dispatch", "name": dname, "args": dargs,
                           "text": label + detail}
        if dyn:
            editable = False  # loop-generated / unresolved key — read-only

        binds.append({
            "combo": combo, "dynamic": dyn, "desc": desc, "mouse": mouse,
            "action": act, "section": sec_by_line.get(line, ""),
            "line": line, "endLine": end_line, "editable": editable,
        })
    return binds

# Expand `for i = 1, N do hl.bind(...) end` loops into read-only virtual binds so
# they show in the cheatsheet even though they can't be edited individually.
# Safely evaluate a small integer arithmetic expression (loop bodies use `i % 10`).
def eval_int(expr, env):
    expr = expr.strip()
    if not re.fullmatch(r"[\w\s%+\-*/().]+", expr):
        return None
    try:
        return int(eval(expr, {"__builtins__": {}}, dict(env)))  # env is int-only
    except Exception:
        return None

def parse_bind_loops(text, aliases):
    out = []
    for m in re.finditer(r"for\s+(\w+)\s*=\s*(\d+)\s*,\s*(\d+)\s*do(.*?)\bend\b", text, re.S):
        var, lo, hi, body = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        line = offset_to_line(text, m.start())
        # `local key = i % 10` style intermediates, resolved per iteration.
        locals_ = re.findall(r"local\s+(\w+)\s*=\s*([^\n]+)", body)

        def combo_at(key_expr, i):
            env = {var: i}
            for lv, lexpr in locals_:
                val = eval_int(lexpr, env)
                if val is not None:
                    env[lv] = val
            # substitute resolved numeric vars into the string expression
            amap = {k: v for k, v in aliases.items()}
            for k, v in env.items():
                amap[k] = str(v)
            txt, _ = resolve_str(key_expr, amap)
            return norm_combo(txt)

        for (s, e, inner) in find_calls(body, "hl.bind"):
            args = split_args(inner)
            if len(args) < 2:
                continue
            combo = combo_at(args[0], lo) + " … " + combo_at(args[0], hi)
            a = args[1].strip()
            dm2 = re.match(r"hl\.dsp\.([A-Za-z_][\w.]*)\s*\((.*)\)\s*$", a, re.S)
            name = dm2.group(1) if dm2 else a
            out.append({
                "combo": combo,
                "dynamic": True, "desc": "", "mouse": False,
                "action": {"type": "dispatch", "name": name, "args": "",
                           "text": DISPATCH_LABEL.get(name, name) + " %d–%d" % (lo, hi)},
                "section": "Workspaces", "line": line, "endLine": line,
                "editable": False, "generated": True,
            })
    return out

# ── Settings schema ───────────────────────────────────────────────────────────
# name -> (file, lua_key, type). We find `lua_key = <value>` and carry its line so
# a write pass can rewrite exactly that. Schema-driven so read and write agree.
#
# Geometry / opacity / blur live in blend.lua — the file hypr shares with this
# shell — so editing "rounding" here also moves the shell's card corners. Only
# the shadow/blur ENABLED toggles stay in appearance.lua (they're not shared).
APPEARANCE = [
    ("gaps_in", "blend.lua", "gaps_in", "int"),
    ("gaps_out", "blend.lua", "gaps_out", "int"),
    ("border_size", "blend.lua", "border_size", "int"),
    ("rounding", "blend.lua", "rounding", "int"),
    ("rounding_power", "blend.lua", "rounding_power", "float"),
    ("active_opacity", "blend.lua", "active_opacity", "float"),
    ("inactive_opacity", "blend.lua", "inactive_opacity", "float"),
    ("shadow_enabled", "appearance.lua", "enabled", "bool"),  # first `enabled` = shadow
    ("blur_enabled", "appearance.lua", "enabled", "bool"),    # handled specially below
    ("wobble_enabled", "appearance.lua", "enabled", "bool"),  # third `enabled` (Hyprland 0.57+)
    ("wobble_mesh", "appearance.lua", "mesh", "int"),
    ("wobble_stiffness", "appearance.lua", "stiffness", "float"),
    ("wobble_damping", "appearance.lua", "damping", "float"),
    ("wobble_mass", "appearance.lua", "mass", "float"),
    ("blur_size", "blend.lua", "blur_size", "int"),
    ("blur_passes", "blend.lua", "blur_passes", "int"),
    ("blur_vibrancy", "blend.lua", "blur_vibrancy", "float"),
    # The tiling layout (dwindle / master / scrolling / monocle): services/HyprLayout
    # switches it live and writes it here so the next start keeps it.
    ("layout", "appearance.lua", "layout", "str"),
]
INPUT = [
    ("kb_layout", "hardware.lua", "kb_layout", "str"),
    ("sensitivity", "hardware.lua", "sensitivity", "float"),
    ("follow_mouse", "hardware.lua", "follow_mouse", "int"),
    ("natural_scroll", "hardware.lua", "natural_scroll", "bool"),
]

def find_kv(lines, key, kind, occurrence=1):
    # returns (value, line) for the `occurrence`-th `key = value`. Tries a
    # line-anchored match first, then an inline one (e.g. natural_scroll living
    # inside `touchpad = { natural_scroll = false }`).
    anchored = re.compile(r"^\s*" + re.escape(key) + r"\s*=\s*(.+?)\s*,?\s*(?:--.*)?$")
    inline   = re.compile(r"\b" + re.escape(key) + r"\s*=\s*([^,}\n]+)")
    seen = 0
    for idx, ln in enumerate(lines, 1):
        if ln.lstrip().startswith("--"):
            continue
        m = anchored.match(ln) or inline.search(ln)
        if m:
            seen += 1
            if seen == occurrence:
                return coerce(m.group(1).rstrip(",").strip(), kind), idx
    return None, None

def coerce(raw, kind):
    raw = raw.strip()
    if kind == "int":
        try: return int(raw)
        except: return raw
    if kind == "float":
        try: return float(raw)
        except: return raw
    if kind == "bool":
        return raw == "true"
    if kind == "str":
        m = re.fullmatch(r'"([^"]*)"', raw)
        return m.group(1) if m else raw
    return raw

def parse_settings(files):
    appr = files.get("appearance.lua", [])
    appearance = {}
    # Disambiguated by order in appearance.lua (shadow, then blur, then wobble).
    enabled_hits = [i for i, ln in enumerate(appr, 1)
                    if re.match(r"^\s*enabled\s*=", ln) and not ln.lstrip().startswith("--")]
    # Shadow, blur and wobble all use `enabled`: the n-th hit in appearance.lua.
    nth = {"shadow_enabled": 0, "blur_enabled": 1, "wobble_enabled": 2}
    for name, fname, key, kind in APPEARANCE:
        if name in nth:
            i = nth[name]
            hit = enabled_hits[i] if len(enabled_hits) > i else None
            val = (appr[hit-1].split("=")[1].strip().rstrip(",") == "true") if hit else None
            appearance[name] = {"value": val, "file": fname, "line": hit, "type": kind}
        else:
            v, line = find_kv(files.get(fname, []), key, kind)
            appearance[name] = {"value": v, "file": fname, "line": line, "type": kind}
    inp = {}
    for name, fname, key, kind in INPUT:
        v, line = find_kv(files.get(fname, []), key, kind)
        inp[name] = {"value": v, "file": fname, "line": line, "type": kind}
    return appearance, inp

# ── Pointer & touchpad (Settings › Keyboard & mouse) ─────────────────────────
# Keys that live in a specific TABLE of hardware.lua's hl.config: `input = { … }` or
# its `touchpad = { … }`. Looked up by table, not by first match: scroll_factor and
# natural_scroll exist in both, and the INPUT list above (first match in the file)
# would read the wrong one. Absent keys read as Hyprland's default, and set-input
# INSERTS them (an older hardware.lua has none of these).
#   (name, table path, lua key, type, Hyprland's default)
POINTER = [
    ("accel_profile",          ("input",),             "accel_profile",        "str",   "adaptive"),
    ("left_handed",            ("input",),             "left_handed",          "bool",  False),
    ("mouse_scroll_factor",    ("input",),             "scroll_factor",        "float", 1.0),
    ("tap_to_click",           ("input", "touchpad"),  "tap_to_click",         "bool",  True),
    ("disable_while_typing",   ("input", "touchpad"),  "disable_while_typing", "bool",  True),
    ("clickfinger_behavior",   ("input", "touchpad"),  "clickfinger_behavior", "bool",  False),
    ("tap_and_drag",           ("input", "touchpad"),  "tap_and_drag",         "bool",  True),
    ("touchpad_scroll_factor", ("input", "touchpad"),  "scroll_factor",        "float", 1.0),
]
# Hyprland 0.56's Lua config refuses "" ("allowed values are: adaptive, flat, custom*"),
# measured with --verify-config; "custom" needs curve points this page doesn't offer.
ACCEL_PROFILES = ("adaptive", "flat")


def _match_brace(text, i):
    """Index of the `}` closing the `{` at text[i], skipping strings and -- comments."""
    depth, j, n = 0, i, len(text)
    while j < n:
        c = text[j]
        if c == '"':
            j = text.index('"', j + 1)
        elif text.startswith("--", j):
            nl = text.find("\n", j)
            j = n - 1 if nl < 0 else nl
        elif c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return j
        j += 1
    return -1


def table_span(text, path, start=0, end=None):
    """(open, close) offsets of the braces of the table at `path`, or None."""
    end = len(text) if end is None else end
    for name in path:
        m = None
        for cand in re.finditer(r"\b" + re.escape(name) + r"\s*=\s*\{", text[start:end]):
            pos = start + cand.start()
            line_start = text.rfind("\n", 0, pos) + 1
            if "--" in text[line_start:pos]:
                continue
            m = cand
            break
        if not m:
            return None
        open_i = start + m.end() - 1
        close_i = _match_brace(text, open_i)
        if close_i < 0:
            return None
        start, end = open_i + 1, close_i
    return (start - 1, end)


def _direct_key(text, span, key):
    """Offset of `key =` directly inside the table (not in a nested table), or -1."""
    o, c = span
    depth, j = 0, o + 1
    while j < c:
        ch = text[j]
        if ch == '"':
            j = text.index('"', j + 1)
        elif text.startswith("--", j):
            nl = text.find("\n", j)
            j = c if nl < 0 else nl
            continue
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
        elif depth == 0 and re.match(r"\b" + re.escape(key) + r"\s*=", text[j:]) and not re.match(r"\w", text[j - 1]):
            return j
        j += 1
    return -1


def parse_pointer(text):
    out = {}
    for name, path, key, kind, default in POINTER:
        span = table_span(text, path)
        at = _direct_key(text, span, key) if span else -1
        if at < 0:
            out[name] = {"value": default, "present": False, "type": kind}
            continue
        m = re.match(re.escape(key) + r"\s*=\s*(\"[^\"]*\"|[^,}\n]+)", text[at:])
        out[name] = {"value": coerce(m.group(1).strip(), kind) if m else default,
                     "present": True, "type": kind}
    return out


def cmd_set_input(flags):
    name, value = flags.get("name", ""), flags.get("value", "")
    spec = {n: (p, k, t) for n, p, k, t, _d in POINTER}.get(name)
    if not spec:
        return {"ok": False, "error": "unknown setting: " + name}
    path_t, key, kind = spec
    try:
        if kind == "float":
            v = float(value)
            if not (0.05 <= v <= 10):
                return {"ok": False, "error": "out of range"}
        if kind == "str" and value not in ACCEL_PROFILES:
            return {"ok": False, "error": "unknown accel profile"}
    except ValueError:
        return {"ok": False, "error": "not a number"}
    lit = fmt_literal(value, kind)
    path = os.path.join(HYPR_DIR, "hardware.lua")
    lines = read_lines(path)
    if lines is None:
        return {"ok": False, "error": "no hardware.lua"}
    text = "\n".join(lines)
    span = table_span(text, path_t)
    if span:
        at = _direct_key(text, span, key)
        if at >= 0:
            m = re.match(r"(" + re.escape(key) + r"\s*=\s*)(\"[^\"]*\"|[^\s,}]+)", text[at:])
            if not m:
                return {"ok": False, "error": "could not locate value for " + key}
            new = text[:at + m.start(2)] + lit + text[at + m.end(2):]
        else:
            o, c = span
            inner = text[o + 1:c]
            if "\n" not in inner:                    # inline: `touchpad = { a = 1 }`
                body = inner.strip()
                ins = (body + ", " if body else "") + key + " = " + lit
                new = text[:o + 1] + " " + ins + " " + text[c:]
            else:                                    # multi-line: a new line after `{`
                nl = text.index("\n", o)
                nxt = text[nl + 1:]
                indent = re.match(r"[ \t]*", nxt).group(0) or "    "
                new = text[:nl + 1] + indent + key + " = " + lit + ",\n" + text[nl + 1:]
    elif path_t == ("input", "touchpad"):
        ispan = table_span(text, ("input",))
        if not ispan:
            return {"ok": False, "error": "hardware.lua has no input table"}
        nl = text.index("\n", ispan[0])
        indent = re.match(r"[ \t]*", text[nl + 1:]).group(0) or "    "
        new = text[:nl + 1] + indent + "touchpad = { " + key + " = " + lit + " },\n" + text[nl + 1:]
    else:
        return {"ok": False, "error": "hardware.lua has no input table"}
    want = coerce(lit, kind)
    return guarded_write(path, new,
                         verify=lambda d: d["pointer"][name]["value"] == want and d["pointer"][name]["present"])


# ── Animations (animation.lua) ───────────────────────────────────────────────
def parse_animations(text):
    out = []
    for (s, e, inner) in find_calls(text, "hl.animation"):
        line = offset_to_line(text, s)
        leaf = re.search(r'leaf\s*=\s*"(\w+)"', inner)
        en = re.search(r'enabled\s*=\s*(\w+)', inner)
        sp = re.search(r'speed\s*=\s*([\d.]+)', inner)
        bez = re.search(r'bezier\s*=\s*"(\w+)"', inner)
        sty = re.search(r'style\s*=\s*"(\w+)"', inner)
        if not leaf:
            continue
        out.append({
            "leaf": leaf.group(1),
            "enabled": (en.group(1) == "true") if en else True,
            "speed": float(sp.group(1)) if sp else None,
            "bezier": bez.group(1) if bez else "",
            "style": sty.group(1) if sty else "",
            "line": line,
        })
    curves = []
    for (s, e, inner) in find_calls(text, "hl.curve"):
        nm = re.search(r'"(\w+)"', inner)
        if nm: curves.append(nm.group(1))
    return out, curves

# ── Entry ─────────────────────────────────────────────────────────────────────
def cmd_read(hypr_dir):
    files = {}
    for name in ("env.lua", "hardware.lua", "appearance.lua", "animation.lua",
                 "blend.lua", "binds.lua", "rules.lua"):
        lines = read_lines(os.path.join(hypr_dir, name))
        if lines is not None:
            files[name] = lines
    aliases = parse_aliases(files.get("env.lua", []))

    binds_text = "\n".join(files.get("binds.lua", []))
    binds = parse_binds(binds_text, aliases) + parse_bind_loops(binds_text, aliases)
    appearance, inp = parse_settings(files)
    anims, curves = parse_animations("\n".join(files.get("animation.lua", [])))

    return {
        "meta": {"dir": hypr_dir, "aliases": aliases,
                 "mainMod": aliases.get("mainMod", "SUPER")},
        "binds": binds,
        "appearance": appearance,
        "input": inp,
        "pointer": parse_pointer("\n".join(files.get("hardware.lua", []))),
        "animations": anims,
        "curves": curves,
    }

# ══ WRITE ENGINE ══════════════════════════════════════════════════════════════
# Every write: back up the target file, apply, then GUARD — the file must still pass
# `luac -p` (real Lua syntax check), the whole config must still re-parse, and the
# intended change must be verifiably present. Any failure restores the original byte
# for byte. Nothing is applied to the live session here — the caller runs
# `hyprctl reload` when the user hits Apply.

def backup(path):
    d = os.path.join(os.path.dirname(path), ".bak")
    os.makedirs(d, exist_ok=True)
    ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    dst = os.path.join(d, os.path.basename(path) + "." + ts)
    shutil.copy2(path, dst)
    return dst

def guarded_write(path, new_text, verify=None):
    with open(path, "r") as f:
        old = f.read()
    bak = backup(path)
    with open(path, "w") as f:
        f.write(new_text)
    # 1) real Lua syntax check
    r = subprocess.run(["luac", "-p", path], capture_output=True, text=True)
    if r.returncode != 0:
        with open(path, "w") as f: f.write(old)
        return {"ok": False, "backup": bak, "error": "lua syntax: " + r.stderr.strip()[:300]}
    # 2) the whole config must still parse into structured data
    try:
        data = cmd_read(HYPR_DIR)
    except Exception as ex:
        with open(path, "w") as f: f.write(old)
        return {"ok": False, "backup": bak, "error": "re-parse failed: " + str(ex)}
    # 3) the intended change must be present
    if verify is not None:
        try:
            ok = verify(data)
        except Exception as ex:
            ok = False
        if not ok:
            with open(path, "w") as f: f.write(old)
            return {"ok": False, "backup": bak, "error": "change did not verify"}
    return {"ok": True, "backup": bak, "file": os.path.basename(path), "data": data}

def fmt_literal(value, kind):
    if kind == "bool":
        return "true" if str(value).lower() in ("true", "1", "yes", "on") else "false"
    if kind == "int":
        return str(int(float(value)))
    if kind == "float":
        f = float(value)
        return str(int(f)) if f == int(f) else repr(round(f, 4))
    if kind == "str":
        return '"%s"' % str(value).replace('"', '\\"')
    return str(value)

# Replace the value token after `key =` on a single line, preserving indent, any
# trailing comma, and any comment.
def set_value_on_line(line, key, literal):
    m = re.search(r"(\b" + re.escape(key) + r"\s*=\s*)(\"[^\"]*\"|[^\s,}]+)", line)
    if not m:
        return None
    return line[:m.start(2)] + literal + line[m.end(2):]

def reverse_combo(combo, aliases):
    mm = aliases.get("mainMod", "SUPER")
    parts = [p.strip() for p in combo.split("+") if p.strip()]
    if parts and parts[0].upper() == mm.upper():
        rest = parts[1:]
        return ('mainMod .. " + %s"' % " + ".join(rest)) if rest else "mainMod"
    return '"%s"' % combo

def build_action(kind, value, args):
    if kind == "exec":
        return 'hl.dsp.exec_cmd("%s")' % value.replace('"', '\\"')
    if kind == "dispatch":
        return "hl.dsp.%s(%s)" % (value, args or "")
    return value  # raw Lua passthrough

def first_comma_rel(inner):
    depth, in_str, esc, quote = 0, False, False, ""
    for i, c in enumerate(inner):
        if in_str:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == quote: in_str = False
        else:
            if c in "\"'": in_str, quote = True, c
            elif c in "([{": depth += 1
            elif c in ")]}": depth -= 1
            elif c == "," and depth == 0:
                return i
    return -1

def bind_call_at(text, line):
    for (s, e, inner) in find_calls(text, "hl.bind"):
        if offset_to_line(text, s) == line:
            return (s, e, inner)
    return None

def combos_in(data):
    return [norm_combo(b["combo"]) for b in data["binds"]]

def cmd_set(flags):
    path = os.path.join(HYPR_DIR, flags["file"])
    line = int(flags["line"])
    key, kind, value = flags["key"], flags.get("type", "int"), flags["value"]
    # The page passes the schema NAME (shadow_enabled, wobble_stiffness); the line
    # holds the Lua key (enabled, stiffness). Without this the stale-line check
    # below rejects every setting whose name differs from its Lua key.
    key = {n: k for n, _f, k, _t in APPEARANCE + INPUT}.get(key, key)
    lines = read_lines(path)
    if lines is None or line < 1 or line > len(lines):
        return {"ok": False, "error": "line out of range"}
    if key not in lines[line - 1]:
        return {"ok": False, "error": "stale line: '%s' not on line %d" % (key, line)}
    lit = fmt_literal(value, kind)
    nl = set_value_on_line(lines[line - 1], key, lit)
    if nl is None:
        return {"ok": False, "error": "could not locate value for " + key}
    lines[line - 1] = nl
    return guarded_write(path, "\n".join(lines))

def cmd_anim(flags):
    path = os.path.join(HYPR_DIR, "animation.lua")
    line = int(flags["line"])
    field, value = flags["field"], flags["value"]
    kind = {"enabled": "bool", "speed": "float", "bezier": "str", "style": "str"}.get(field, "str")
    lines = read_lines(path)
    if lines is None or line < 1 or line > len(lines) or "hl.animation" not in lines[line - 1]:
        return {"ok": False, "error": "no animation at line %d" % line}
    nl = set_value_on_line(lines[line - 1], field, fmt_literal(value, kind))
    if nl is None:
        return {"ok": False, "error": "field not present: " + field}
    lines[line - 1] = nl
    return guarded_write(path, "\n".join(lines))

def cmd_rebind(flags):
    path = os.path.join(HYPR_DIR, "binds.lua")
    line, combo = int(flags["line"]), norm_combo(flags["combo"])
    aliases = parse_aliases(read_lines(os.path.join(HYPR_DIR, "env.lua")))
    with open(path) as f: text = f.read()
    call = bind_call_at(text, line)
    if not call:
        return {"ok": False, "error": "no bind at line %d" % line}
    s, e, inner = call
    cr = first_comma_rel(inner)
    if cr < 0:
        return {"ok": False, "error": "malformed bind"}
    a = s + len("hl.bind(")
    new_text = text[:a] + reverse_combo(combo, aliases) + text[a + cr:]
    return guarded_write(path, new_text, verify=lambda d: combo in combos_in(d))

def cmd_set_action(flags):
    path = os.path.join(HYPR_DIR, "binds.lua")
    line = int(flags["line"])
    action = build_action(flags["kind"], flags["value"], flags.get("args", ""))
    with open(path) as f: text = f.read()
    call = bind_call_at(text, line)
    if not call:
        return {"ok": False, "error": "no bind at line %d" % line}
    s, e, inner = call
    cr = first_comma_rel(inner)
    if cr < 0:
        return {"ok": False, "error": "malformed bind"}
    # second arg runs from after the first comma to the next top-level comma (opts) or end
    rest = inner[cr + 1:]
    cr2 = first_comma_rel(rest)
    a = s + len("hl.bind(") + cr + 1           # start of action arg (incl. leading space)
    b = (a + cr2) if cr2 >= 0 else (e - 1)     # end of action arg
    new_text = text[:a] + " " + action + text[b:]
    return guarded_write(path, new_text)

def cmd_add(flags):
    path = os.path.join(HYPR_DIR, "binds.lua")
    aliases = parse_aliases(read_lines(os.path.join(HYPR_DIR, "env.lua")))
    combo = norm_combo(flags["combo"])
    combo_expr = reverse_combo(combo, aliases)
    action = build_action(flags["kind"], flags["value"], flags.get("args", ""))
    lines = read_lines(path)
    before = len(parse_binds("\n".join(lines), aliases))
    header = "-- ── Custom (added from Quickshell) ──"
    if header not in "\n".join(lines):
        # drop a trailing empty line, then header
        while lines and lines[-1].strip() == "":
            lines.pop()
        lines.append("")
        lines.append(header)
    lines.append("hl.bind(%s, %s)" % (combo_expr, action))
    return guarded_write(path, "\n".join(lines),
                         verify=lambda d: len([b for b in d["binds"] if not b.get("generated")]) > before)

def cmd_remove(flags):
    path = os.path.join(HYPR_DIR, "binds.lua")
    line = int(flags["line"])
    with open(path) as f: text = f.read()
    call = bind_call_at(text, line)
    if not call:
        return {"ok": False, "error": "no bind at line %d" % line}
    s, e, inner = call
    start_line = offset_to_line(text, s)
    end_line = offset_to_line(text, e - 1)
    lines = text.split("\n")
    target_combo = None
    aliases = parse_aliases(read_lines(os.path.join(HYPR_DIR, "env.lua")))
    args = split_args(inner)
    if args:
        c, _ = resolve_str(args[0], aliases); target_combo = norm_combo(c)
    del lines[start_line - 1:end_line]
    return guarded_write(path, "\n".join(lines),
                         verify=lambda d: target_combo not in combos_in(d))

def parse_flags(argv):
    flags = {}
    i = 0
    while i < len(argv):
        if argv[i].startswith("--"):
            k = argv[i][2:]
            v = argv[i + 1] if i + 1 < len(argv) and not argv[i + 1].startswith("--") else "true"
            flags[k] = v
            i += 2
        else:
            i += 1
    return flags

def main():
    global HYPR_DIR
    argv = sys.argv[1:]
    if "--dir" in argv:
        HYPR_DIR = os.path.expanduser(argv[argv.index("--dir") + 1])
    cmd = argv[0] if argv else "read"
    flags = parse_flags(argv[1:])
    handlers = {
        "set": cmd_set, "anim": cmd_anim, "rebind": cmd_rebind,
        "set-action": cmd_set_action, "add": cmd_add, "remove": cmd_remove,
        "set-input": cmd_set_input,
    }
    if cmd == "read":
        print(json.dumps(cmd_read(HYPR_DIR)))
    elif cmd in handlers:
        print(json.dumps(handlers[cmd](flags)))
    else:
        print(json.dumps({"ok": False, "error": "unknown command: " + cmd}))
        sys.exit(2)

if __name__ == "__main__":
    main()
