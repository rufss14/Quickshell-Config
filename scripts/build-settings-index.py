#!/usr/bin/env python3
"""Build the settings search index from the page sources.

    python3 scripts/build-settings-index.py          # write the index
    python3 scripts/build-settings-index.py --check   # exit 1 if it is stale

Reads  modules/settings/pages/*.qml
Writes modules/settings/settings-index.json

── Why this is generated and not hand-written ────────────────────────────────
A hand-maintained list of "every setting and which page it is on" is a second
copy of the pages, and it drifts the moment someone adds a row and forgets. The
failure is silent and shaped like the search being bad rather than the index
being stale, which is the worst kind: you distrust the feature instead of
fixing the data.

Generating it means the index cannot describe a row that does not exist, and
`--check` in CI (or by eye before a commit) catches the reverse.

── Why regex and not a QML parser ────────────────────────────────────────────
There isn't one available here, and the thing being extracted is the narrow
declarative subset these pages are written in: `Section`, `SettingRow` and
`SliderRow` with string-literal `title`/`label`/`subtitle`/`detail`. Anything
computed is skipped deliberately rather than half-resolved — a search hit whose
text is `Lyrics.provider + " lyrics"` is worse than no hit at all.

The page's own NAME is not extracted. That lives in SettingsCard's `pages`
array along with its section, glyph and keywords, and having two sources for it
is exactly the drift this file exists to prevent. Entries are keyed by `file`
and the QML joins them.
"""

import json
import re
import sys
from pathlib import Path

# The repo, found from this file — never a literal. This config is published and
# a hardcoded /home/<someone> breaks it for everyone else (CLAUDE.md, Portability).
REPO = Path(__file__).resolve().parent.parent
PAGES = REPO / "modules" / "settings" / "pages"
OUT = REPO / "modules" / "settings" / "settings-index.json"

# The types worth indexing, and which of their properties carry the text.
#
# `QuickToggleTile` earns its place the hard way: the bento pages express a boolean
# as a TILE rather than a SettingRow, and when the first pages converted, eight
# settings silently stopped being searchable. The index is only as good as its list
# of shapes — a new control type that carries a user-visible label belongs here the
# day it is introduced, or search quietly gets worse and the pages look fine.
INDEXED = {
    "Section":         ("title", "subtitle", "section"),
    "SettingRow":      ("label", "detail",   "row"),
    "SliderRow":       ("label", "detail",   "row"),
    "Fader":           ("label", "readout",  "row"),
    "QuickToggleTile": ("label", "subLabel", "row"),
    "FontPicker":      ("label", "detail",   "row"),
    # Page-local, but it is how eight of the lock screen's settings are spelled. Leave
    # it out and searching "notifications" finds the notification page and not the
    # switch that puts them on the lock — the same silent drop QuickToggleTile had.
    "ShowToggle":      ("label", None, "row"),
    # A ToggleChip is how a set of yes/no's is spelled. Chips built from a model (the
    # sidebar's modules, the stats readings) carry computed labels and are skipped here
    # by design; their names ride in the view's `keywords` in SettingsIndex instead.
    "ToggleChip":      ("label", "hint",     "row"),
}

# A row's owning card.
OWNERS = ("Section",)

_STRING = re.compile(r'"((?:[^"\\]|\\.)*)"')
_TR_CALL = re.compile(r'\bTranslation\.tr\(\s*("(?:[^"\\]|\\.)*")\s*\)')


def strip_noise(line):
    """Drop // comments, but not a // that lives inside a string literal."""
    out, in_str, esc = [], False, False
    i = 0
    while i < len(line):
        c = line[i]
        if in_str:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            out.append(c)
        else:
            if c == '"':
                in_str = True
                out.append(c)
            elif c == "/" and i + 1 < len(line) and line[i + 1] == "/":
                break
            else:
                out.append(c)
        i += 1
    return "".join(out)


def literal_value(text):
    """The value of a `prop:` assignment, if it is a plain string literal.

    Handles the `"a " + "b"` continuation these files use for long sentences.
    Returns None for anything computed — a binding, a ternary, an identifier —
    because a half-resolved expression is worse in a search result than an
    absent one.
    """
    text = text.strip()
    # A translated label is still a literal one: Translation.tr("Dock") indexes as "Dock"
    # (the index is built from the English text and is not itself translated).
    text = _TR_CALL.sub(r"\1", text)
    if not text.startswith('"'):
        return None
    parts = []
    rest = text
    while True:
        m = _STRING.match(rest)
        if not m:
            return None
        parts.append(m.group(1))
        rest = rest[m.end():].strip()
        if rest.startswith("+"):
            rest = rest[1:].strip()
            continue
        # Trailing junk means this was an expression that merely started with a
        # string. Only a clean end (or a following property) counts.
        if rest and not rest[0].isalpha():
            return None
        break
    value = "".join(parts).strip()
    return value or None


def expand(path, seen=()):
    """The page's lines, with each part from a subfolder it imports (WallpaperPage →
    `import "wallpaper"`) spliced in where the page instantiates it — so its rows land
    in the page's own order and under the Section that holds them, as before the split."""
    text = path.read_text(encoding="utf-8")
    parts = {}
    for sub in re.findall(r'^import "(\w+)"\s*$', text, re.M):
        d = path.parent / sub
        if d.is_dir():
            parts.update({f.stem: f for f in d.glob("*.qml")})
    out = []
    for raw in text.splitlines():
        m = re.match(r"\s*(?:delegate:\s*)?(\w+)\s*\{", strip_noise(raw))
        if m and m.group(1) in parts and parts[m.group(1)] not in seen:
            out.extend(expand(parts[m.group(1)], seen + (path,)))
            continue
        out.append(raw)
    return out


def scan(path):
    """Yield index entries for one page file, tracking which Section owns each row."""
    entries = []
    # Stack of [brace_depth_at_open, type_name, collected_props]. A row's owning
    # Section is found by looking DOWN this stack while the row closes — the Section
    # is still open at that moment, and its `title:` has already been read because
    # these files declare it before the rows. Recording sections as they CLOSE
    # instead does not work: by then every row inside has already been emitted, which
    # is why the first version attributed nothing to anything.
    open_blocks = []
    depth = 0

    lines = expand(path)
    for raw in lines:
        line = strip_noise(raw)

        # A property assignment belonging to the innermost open block.
        if open_blocks:
            m = re.match(r"\s*(\w+)\s*:\s*(.+?)\s*$", line)
            if m and m.group(1) in ("title", "subtitle", "label", "detail", "help"):
                val = literal_value(m.group(2))
                if val:
                    open_blocks[-1][2].setdefault(m.group(1), val)

        # Opening one of the types we index. `\b` so `SettingRow` does not also
        # match a hypothetical `MySettingRow`.
        m = re.search(r"\b(" + "|".join(INDEXED) + r")\s*\{", line)
        if m:
            open_blocks.append([depth, m.group(1), {}])

        for c in line:
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                # Close any block whose opening depth we have come back to.
                while open_blocks and open_blocks[-1][0] >= depth:
                    _, kind, props = open_blocks.pop()
                    title_key, detail_key, tag = INDEXED[kind]
                    title = props.get(title_key)
                    if title:
                        entry = {
                            "file": path.name,
                            "kind": tag,
                            "title": title,
                        }
                        # The explanation moved out of the layout into `help` (a tip on
                        # the control, components/HelpTip) — it is still the best text
                        # to match a search against when the state line is computed.
                        detail = props.get(detail_key) or props.get("help")
                        if detail:
                            entry["detail"] = detail
                        if tag == "row":
                            # The Section this row sits inside, so a result can say
                            # "Appearance › Type › Text scale" rather than just the row.
                            # Still on the stack at this point — see the note above.
                            owner = next(
                                (b[2].get("title") for b in reversed(open_blocks)
                                 if b[1] in OWNERS),
                                None,
                            )
                            if owner:
                                entry["section"] = owner
                        entries.append(entry)

    return entries


def build():
    if not PAGES.is_dir():
        print(f"error: {PAGES} not found", file=sys.stderr)
        return None
    out = []
    for path in sorted(PAGES.glob("*.qml")):
        # A split page's parts are spliced in where it uses them (expand, above).
        out.extend(scan(path))
    return {"version": 1, "entries": out}


def main():
    index = build()
    if index is None:
        return 2

    text = json.dumps(index, indent=2, ensure_ascii=False) + "\n"

    if "--check" in sys.argv:
        if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
            print("settings-index.json is stale — run build-settings-index.py", file=sys.stderr)
            return 1
        print(f"settings-index.json is current ({len(index['entries'])} entries)")
        return 0

    OUT.write_text(text, encoding="utf-8")
    per_page = {}
    for e in index["entries"]:
        per_page[e["file"]] = per_page.get(e["file"], 0) + 1
    print(f"wrote {OUT.relative_to(REPO)} — {len(index['entries'])} entries")
    for f, n in sorted(per_page.items(), key=lambda kv: -kv[1]):
        print(f"  {n:4d}  {f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
