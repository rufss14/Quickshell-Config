#!/usr/bin/env python3
"""The shell's translation catalogue: find every translatable string, and report coverage.

    python3 scripts/translations.py extract      # rewrite translations/en_US.json
    python3 scripts/translations.py check        # exit 1 if en_US.json is out of date
    python3 scripts/translations.py status       # per language: translated / missing / stale
    python3 scripts/translations.py sync [CODE…] # add missing keys (empty) to every language file
    python3 scripts/translations.py new CODE     # start a language, e.g. new fr_FR

── The model ─────────────────────────────────────────────────────────────────
The English text IS the key. `Translation.tr("Reload failed")` in QML looks that exact
string up in translations/<code>.json and returns it unchanged when there is no entry —
so an untranslated string, a missing file and a language that was never installed all
read as English, never as a blank or a key name. A file is one flat JSON object,
{"English text": "translation"}; an empty value counts as untranslated.

What the scan finds (QML and JS under the repo, minus config/settings/ and scripts/):
    Translation.tr("literal")   and   Translation.tr('literal')
    N_("literal")               a no-op marker for text that lives in data (a catalogue in
                                a .js file, a model array) and is translated where it is
                                drawn with Translation.tr(modelData.label)

Only a single string literal is found. `tr("a " + b)` and `tr("a " + "b")` are not
translatable and are reported by `check` as dynamic calls — build the sentence with a
placeholder instead: `Translation.tr("Moved %1 keys").arg(n)`. A call with no quote in it at
all (`Translation.tr(modelData.label)`) is the "data" pattern and is fine. Text in
comments is ignored.

The reference file en_US.json maps every key to itself. It is generated, never edited:
`check` fails when it has drifted, and test-translations.py runs that in `check-all.sh`.
"""
import json
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
DIR = REPO / "translations"
SKIP = ("config/settings/", "scripts/", "translations/", ".git/", ".claude/", "docs/")
REFERENCE = "en_US"

_STR = r'''(?:"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*')'''
_CALL = re.compile(r"\b(?:Translation\.tr|N_)\(\s*(" + _STR + r")\s*[,)]")
_ANY = re.compile(r"\bTranslation\.tr\(")
_LOOKS_LITERAL = re.compile(r"\bTranslation\.tr\(\s*" + _STR + r"\s*[,)]")
_QUOTE = re.compile(r"""["']""")


def strip_noise(line):
    """Drop a // comment, but not a // inside a string literal."""
    out, quote, esc = [], "", False
    i = 0
    while i < len(line):
        c = line[i]
        if quote:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
        elif c == "/" and line[i + 1:i + 2] == "/":
            break
        out.append(c)
        i += 1
    return "".join(out)


def _args(text, start):
    """The text of a call's arguments from just after its '(' to the matching ')'."""
    depth, quote, esc = 1, "", False
    for i in range(start, len(text)):
        c = text[i]
        if quote:
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
        elif c == "(":
            depth += 1
        elif c == ")":
            depth -= 1
            if depth == 0:
                return text[start:i]
    return text[start:]


def decode(lit):
    """A JS string literal's value."""
    body = lit[1:-1]
    if lit[0] == "'":
        body = body.replace('\\\'', "'").replace('"', '\\"')
        body = re.sub(r"(?<!\\)\\'", "'", body)
    try:
        return json.loads('"' + body + '"') if lit[0] == "'" else json.loads(lit)
    except ValueError:
        return body


def scan(root=REPO):
    """({key: [file, …]}, [(file, line) of calls that are not a single literal])."""
    keys, dynamic = {}, []
    for path in sorted(Path(root).rglob("*")):
        if path.suffix not in (".qml", ".js") or not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if any(rel.startswith(s) or ("/" + s) in ("/" + rel) for s in SKIP):
            continue
        # Comments are prose that mentions tr() ("Translation.tr("English text")"); they are
        # not strings the shell shows.
        text = "\n".join(strip_noise(l) for l in
                         path.read_text(encoding="utf-8", errors="replace").split("\n"))
        for m in _CALL.finditer(text):
            keys.setdefault(decode(m.group(1)), []).append(rel)
        for m in _ANY.finditer(text):
            if _LOOKS_LITERAL.match(text, m.start()):
                continue
            # tr(modelData.label) — data, marked where it is written with N_() — has no
            # quote in it and is fine. A quote that is NOT a lone literal ("a " + b) is not.
            if _QUOTE.search(_args(text, m.end())):
                dynamic.append((rel, text.count("\n", 0, m.start()) + 1))
    return keys, dynamic


def load(code):
    try:
        data = json.loads((DIR / (code + ".json")).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    return data if isinstance(data, dict) else {}


def dump(code, table):
    DIR.mkdir(exist_ok=True)
    (DIR / (code + ".json")).write_text(
        json.dumps(dict(sorted(table.items())), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def languages():
    return sorted(p.stem for p in DIR.glob("*.json")) if DIR.is_dir() else []


def reference_table(keys):
    return {k: k for k in keys}


def main(argv):
    cmd = argv[1] if len(argv) > 1 else "status"
    keys, dynamic = scan()

    if cmd == "extract":
        dump(REFERENCE, reference_table(keys))
        print("%s.json: %d strings" % (REFERENCE, len(keys)))
        for rel, line in dynamic:
            print("  not translatable (not one literal): %s:%d" % (rel, line))
        return 0

    if cmd == "check":
        stale = load(REFERENCE) != reference_table(keys)
        if stale:
            print("translations/%s.json is out of date — run: python3 scripts/translations.py extract" % REFERENCE)
        for rel, line in dynamic:
            print("dynamic Translation.tr() call: %s:%d" % (rel, line))
        return 1 if (stale or dynamic) else 0

    if cmd == "status":
        print("%d strings" % len(keys))
        for code in languages():
            if code == REFERENCE:
                continue
            t = load(code)
            done = sum(1 for k in keys if str(t.get(k, "")).strip())
            stale = sum(1 for k in t if k not in keys)
            print("  %-8s %4d / %d translated, %d missing, %d stale"
                  % (code, done, len(keys), len(keys) - done, stale))
        return 0

    if cmd in ("sync", "new"):
        targets = argv[2:]
        if cmd == "new" and not targets:
            print("usage: translations.py new CODE")
            return 1
        if cmd == "sync" and not targets:
            targets = [c for c in languages() if c != REFERENCE]
        for code in targets:
            if not re.fullmatch(r"[a-z]{2,3}(_[A-Z]{2})?", code):
                print("not a locale code: %r (expected like fr_FR)" % code)
                return 1
            t = load(code)
            added = 0
            for k in keys:
                if k not in t:
                    t[k] = ""
                    added += 1
            dump(code, t)
            print("%s.json: +%d keys (%d total)" % (code, added, len(t)))
        return 0

    print(__doc__)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
