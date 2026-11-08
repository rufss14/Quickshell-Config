#!/usr/bin/env python3
"""merge-overrides.py <overrides.json> <colors.json> — lay the user's held colours
over a palette, in place.

The held colours are theming/pywal-overrides.json, written by services/ColorScheme
(a pinned slot, or a whole applied scheme). They win over whatever pywal extracted,
on every wallpaper, until released.

Two scripts need this and it used to live inline in one of them: reload-theme.sh
merges into the live palette, and apply-wallpaper.sh merges into its PRIVATE copy
before the one commit the shell sees (the wave — see its header). Two inline copies
is how the halves of the theming pipeline drifted before.

The overrides file is hand-editable, so only real slots holding real colours are
taken; anything else is skipped with a warning rather than written into the palette
every themed app reads. The write is atomic: the shell watches colors.json, and a
read mid-write is how "colors.json is not valid JSON" got into its log.

    merge-overrides.py <overrides.json> <colors.json>
    merge-overrides.py --selftest
"""
import json
import os
import re
import sys
import tempfile

SLOTS = {"special": {"background", "foreground", "cursor"},
         "colors": {f"color{i}" for i in range(16)}}
HEX = re.compile(r"^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")


def merge(base: dict, ovr: dict) -> tuple[dict, list[str]]:
    """base with every valid override laid over it; the skipped keys, for a warning."""
    skipped = []
    for section, allowed in SLOTS.items():
        held = ovr.get(section) or {}
        if not isinstance(held, dict):
            skipped.append(section)
            continue
        for k, v in held.items():
            if k in allowed and isinstance(v, str) and HEX.match(v):
                base.setdefault(section, {})[k] = v
            else:
                skipped.append(f"{section}.{k}")
    return base, skipped


def write_atomic(path: str, doc: dict) -> None:
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path) or ".", suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(doc, f, indent=2)
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(ovr_path: str, colors_path: str) -> int:
    with open(ovr_path) as f:
        ovr = json.load(f)
    with open(colors_path) as f:
        base = json.load(f)
    if not isinstance(ovr, dict) or not isinstance(base, dict):
        print("merge-overrides: not a palette document", file=sys.stderr)
        return 1
    doc, skipped = merge(base, ovr)
    if skipped:
        print("merge-overrides: skipped " + ", ".join(skipped), file=sys.stderr)
    write_atomic(colors_path, doc)
    return 0


def _selftest() -> int:
    base = {"wallpaper": "/w.png", "special": {"background": "#000000"},
            "colors": {f"color{i}": "#111111" for i in range(16)}}
    ovr = {"special": {"background": "#abcdef", "evil": "#ffffff"},
           "colors": {"color1": "#FF0000", "color2": "red", "color99": "#000000"}}
    doc, skipped = merge(json.loads(json.dumps(base)), ovr)
    assert doc["special"]["background"] == "#abcdef", doc
    assert doc["colors"]["color1"] == "#FF0000", doc
    assert doc["colors"]["color2"] == "#111111", doc          # "red" is not a colour here
    assert "evil" not in doc["special"] and "color99" not in doc["colors"], doc
    assert doc["wallpaper"] == "/w.png", doc                  # untouched
    assert sorted(skipped) == ["colors.color2", "colors.color99", "special.evil"], skipped
    doc2, skipped2 = merge({}, {"special": ["#ffffff"], "colors": {}})
    assert doc2 == {} and skipped2 == ["special"], (doc2, skipped2)
    print("ok")
    return 0


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        sys.exit(_selftest())
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
