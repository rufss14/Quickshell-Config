#!/usr/bin/env python3
"""Every place that opens settings AT a page must name a page that exists.

A settings link is a page KEY: a file in modules/settings/pages/, optionally `#anchor`. One that
names a file the catalogue no longer lists does not fail anywhere: `openSettingsTo()` drops an
unknown key without a word, and the button just stops doing anything. This finds them first.

A key is valid when its file is
  - a page file in SettingsIndex's `_catalogue`,
  - an `aliases` key in services/SettingsIndex.qml (a file that is gone, mapped to its successor), or
  - a `_moduleOfPage` key in state/UiState.qml (a page that became a Bar module),
and, when it carries `#anchor`, the file it resolves to declares that anchor in the catalogue (a
mistyped anchor would otherwise land silently on the file's first page).

Scanned, because these are what really mean "open settings at":
  - `openSettingsTo("…")` in .qml / .js
  - string literals naming a page in any `island.js` (the Dashboard switches' SWITCH_PAGES)
  - `page: "…Page.qml"` fields in .qml / .js (SysStats' tiles)
  - `settingsPage: "…"` defaults in config/*.qml; `"settingsPage"` / `"settingsPinned"` in presets/*.json
  - scripts that open a page: `settings page X`, `settings-open.sh X`, `$OPENER X`
Comment lines are skipped. A component file whose name merely ends in Page.qml
(modules/onboard/wizard/WizardStylePage.qml) is never matched: only these patterns' VALUES are read.

Also checks the catalogue itself: every page file exists, no key is listed twice, and every alias
target resolves to a page.

    python3 scripts/check-settings-links.py        prints findings and `settings-links=N`; exit 1 if N > 0
"""
import json, os, re, sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".git", "node_modules"}
SKIP_PATHS = ("config/settings/", "plugin/build/")

INDEX = os.path.join(REPO, "services", "SettingsIndex.qml")
UISTATE = os.path.join(REPO, "state", "UiState.qml")
PAGES_DIR = os.path.join(REPO, "modules", "settings", "pages")

KEY = r"[A-Za-z0-9_]+Page\.qml(?:#[\w-]+)?"


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def block(text, start, end):
    """The text between the first `start` and the next `end` after it ('' when absent)."""
    a = text.find(start)
    if a < 0:
        return ""
    b = text.find(end, a + len(start))
    return text[a:b if b >= 0 else len(text)]


def strip_comments(text):
    return "\n".join(l.split("//", 1)[0] if not l.lstrip().startswith("//") else "" for l in text.split("\n"))


# ── What is allowed ──────────────────────────────────────────────────────────
index = read(INDEX)
catalogue = strip_comments(block(index, "property var _catalogue:", "readonly property var memberPages"))
pages = []  # (file, anchor)
# An object ends at a `}` followed by `,` or `]`: a glyph like "\u{F01C0}" has a `}` inside it.
for m in re.finditer(r"\{\s*file:\s*\"([^\"]+)\"(.*?)\}\s*(?=[,\]])", catalogue, re.S):
    anchor = re.search(r"\banchor:\s*\"([^\"]*)\"", m.group(2))
    pages.append((m.group(1), anchor.group(1) if anchor else ""))
page_files = {f for f, _ in pages}

alias_text = strip_comments(block(index, "property var aliases:", "})"))
aliases = dict(re.findall(r"\"([^\"]+)\"\s*:\s*\"([^\"]+)\"", alias_text))

module_text = block(read(UISTATE), "_moduleOfPage:", "})")
module_pages = set(re.findall(r"\"([^\"]+Page\.qml)\"\s*:", module_text))

findings = []

if not pages:
    findings.append("services/SettingsIndex.qml: no catalogue pages found (did `_catalogue` move?)")

# ── The catalogue itself ─────────────────────────────────────────────────────
seen = set()
for f, a in pages:
    key = f + ("#" + a if a else "")
    if key in seen:
        findings.append("services/SettingsIndex.qml: \"%s\" is listed twice in the catalogue" % key)
    seen.add(key)
    if not os.path.isfile(os.path.join(PAGES_DIR, f)):
        findings.append("services/SettingsIndex.qml: catalogue page \"%s\" has no file in modules/settings/pages/" % f)


def resolve(key):
    """(file, anchor) after following aliases; None on a cycle."""
    file, _, anchor = key.partition("#")
    hops = 0
    while file in aliases:
        hops += 1
        if hops > 8:
            return None
        t_file, _, t_anchor = aliases[file].partition("#")
        file, anchor = t_file, (t_anchor or anchor)
    return file, anchor


for k, v in aliases.items():
    r = resolve(k)
    if r is None:
        findings.append("services/SettingsIndex.qml: alias cycle through \"%s\"" % k)
    elif r[0] not in page_files:
        findings.append("services/SettingsIndex.qml: alias \"%s\" -> \"%s\" names no catalogue page" % (k, v))


def problem(key):
    """Why `key` is not a valid settings link, or None."""
    file, _, anchor = key.partition("#")
    if file in module_pages and not anchor:
        return None
    if file not in page_files and file not in aliases:
        return "names no settings page or alias"
    if anchor:
        r = resolve(key)
        if r is None:
            return "alias cycle"
        if (r[0], r[1]) not in pages:
            return "anchor #%s is not declared for %s in the catalogue" % (anchor, r[0])
    return None


# ── The scan ─────────────────────────────────────────────────────────────────
OPEN_TO = re.compile(r"openSettingsTo\(\s*\"([^\"]*)\"\s*\)")
LITERAL = re.compile(r"\"(" + KEY + r")\"")
PAGE_FIELD = re.compile(r"\bpage:\s*\"(" + KEY + r")\"")
CONFIG_DEFAULT = re.compile(r"\bsettingsPage:\s*\"([^\"]*)\"")
SCRIPT_OPEN = re.compile(r"(?:settings page|settings-open\.sh|\$\{?OPENER\}?)\s+[\"']?(" + KEY + r")")


def is_comment(line):
    s = line.lstrip()
    return s.startswith("//") or s.startswith("#") or s.startswith("*")


def check(rel, lineno, key):
    why = problem(key) if key else "is empty"
    if why:
        findings.append("%s:%d: \"%s\" %s" % (rel, lineno, key, why))


for dirpath, dirnames, filenames in os.walk(REPO):
    dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
    rel_dir = os.path.relpath(dirpath, REPO).replace(os.sep, "/")
    rel_dir = "" if rel_dir == "." else rel_dir + "/"
    if rel_dir.startswith(SKIP_PATHS):
        dirnames[:] = []
        continue
    for name in filenames:
        rel = rel_dir + name
        ext = os.path.splitext(name)[1]
        is_code = ext in (".qml", ".js")
        is_script = rel.startswith("scripts/") and ext in (".sh", ".py")
        is_config = rel.startswith("config/") and ext == ".qml"
        is_preset = rel.startswith("presets/") and ext == ".json"
        if not (is_code or is_script or is_config or is_preset):
            continue
        if rel == "scripts/check-settings-links.py":
            continue
        try:
            text = read(os.path.join(dirpath, name))
        except (OSError, UnicodeDecodeError):
            continue

        if is_preset:
            try:
                doc = json.loads(text)
            except ValueError:
                continue
            found = []

            def walk(o):
                if isinstance(o, dict):
                    for k, v in o.items():
                        if k == "settingsPage" and isinstance(v, str):
                            found.append(v)
                        elif k == "settingsPinned" and isinstance(v, list):
                            found.extend(x for x in v if isinstance(x, str))
                        else:
                            walk(v)
                elif isinstance(o, list):
                    for v in o:
                        walk(v)
            walk(doc)
            lines = text.split("\n")
            for key in found:
                lineno = next((i + 1 for i, l in enumerate(lines) if "\"%s\"" % key in l), 1)
                check(rel, lineno, key)
            continue

        for i, line in enumerate(text.split("\n"), 1):
            if is_comment(line):
                continue
            keys = []
            if is_code:
                keys += OPEN_TO.findall(line)
                keys += PAGE_FIELD.findall(line)
                if name == "island.js":
                    keys += [k for k in LITERAL.findall(line) if k not in keys]
            if is_config:
                keys += CONFIG_DEFAULT.findall(line)
            if is_script:
                keys += SCRIPT_OPEN.findall(line)
            for key in keys:
                check(rel, i, key)

for f in findings:
    print(f)
print("settings-links=%d" % len(findings))
sys.exit(1 if findings else 0)
