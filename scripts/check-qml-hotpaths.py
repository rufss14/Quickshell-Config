#!/usr/bin/env python3
"""check-qml-hotpaths.py — everything that can wake the shell every frame, and what stops it.

    python3 scripts/check-qml-hotpaths.py            the ungated ones, then the full table
    python3 scripts/check-qml-hotpaths.py --ungated  only the ungated ones
    python3 scripts/check-qml-hotpaths.py --count    one number: how many are ungated (scripts/check-all.sh)

A shell that is "idle" costs what its always-running animations cost, at the display's refresh rate
(165 Hz here). Four things run on their own: a FrameAnimation (every frame), a repeating Timer of
33 ms or less, an `onFrameSwapped` handler, and an animation with `loops: Animation.Infinite`. Each
is fine when its `running:` is a binding that goes false when nobody is looking, and a standing cost
when it is absent or literally `true`. This lists them with the gate each has.

UNGATED does not mean wrong: the file may only be loaded while it is on screen (a Loader), or the
thing may be meant to run always. It means "check", which grep `Animation.Infinite` by hand cannot
keep up with. Exit status is always 0: it informs, it does not gate (check-all.sh prints the count).
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
START = re.compile(r"\b(FrameAnimation|Timer|(?:Sequential|Parallel|Number|Color|Property|Rotation|Scale|Opacity|Pause)?Animation(?: on \w+)?)\s*\{")


def blocks(src):
    """(kind, line, own_text, start, end) for each matching object; own_text has nested {…} blanked out."""
    for m in START.finditer(src):
        i, depth, own = m.end(), 1, []
        while i < len(src) and depth:
            c = src[i]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
            elif depth == 1:
                own.append(c)
            i += 1
        yield m.group(1), src.count("\n", 0, m.start()) + 1, "".join(own), m.start(), i


def running_of(own):
    m = re.search(r"(?:^|\n)\s*(?:running|paused)\s*:\s*([^\n;]+)", own)
    return m.group(1).strip() if m else None


def scan():
    rows = []
    files = [f for f in glob.glob(ROOT + "/**/*.qml", recursive=True)
             if "/config/settings/" not in f and "/plugin/build/" not in f]
    for f in sorted(files):
        src = open(f, errors="replace").read()
        rel = os.path.relpath(f, ROOT)
        found = list(blocks(src))
        outer_gated = [(a, b) for _, _, o, a, b in found
                       if running_of(o) is not None and running_of(o) != "true"]
        for kind, line, own, start, end in found:
            run = running_of(own)
            gated = run is not None and run != "true"
            if not gated and kind != "FrameAnimation" and kind != "Timer" \
                    and any(a < start and end <= b for a, b in outer_gated):
                run, gated = "(inside a gated animation)", True
            if kind == "FrameAnimation" and not gated:
                # Started and stopped by hand (a spring that runs until it settles).
                head = src[src.rfind("\n", 0, start) + 1:start]
                name = re.search(r"(\w+)\s*:\s*$", head) or re.search(r"\bid\s*:\s*(\w+)", own)
                if name and re.search(r"\b%s\.(start|restart)\(" % re.escape(name.group(1)), src):
                    run, gated = "(start()/stop() by hand)", True
            if kind == "FrameAnimation":
                rows.append((rel, line, "FrameAnimation", run, gated))
            elif kind == "Timer":
                iv = re.search(r"interval\s*:\s*(\d+)\s*(?:\n|;|$)", own)
                if iv and int(iv.group(1)) <= 33 and re.search(r"repeat\s*:\s*true", own):
                    rows.append((rel, line, f"Timer {iv.group(1)}ms", run, gated))
            elif re.search(r"loops\s*:\s*Animation\.Infinite", own):
                rows.append((rel, line, kind, run, gated))
        for m in re.finditer(r"onFrameSwapped\s*:", src):
            rows.append((rel, src.count("\n", 0, m.start()) + 1, "onFrameSwapped", None, False))
    return rows


def main():
    rows = scan()
    ungated = [r for r in rows if not r[4]]
    if "--count" in sys.argv:
        print(len(ungated))
        return 0
    def show(rs):
        for rel, line, kind, run, gated in rs:
            print(f"  {rel}:{line:<5} {kind:<22} {'running: ' + run if run else '— no running: —'}")
    print(f"UNGATED ({len(ungated)}) — no `running:`, or literally true:")
    show(ungated)
    if "--ungated" not in sys.argv:
        print(f"\ngated ({len(rows) - len(ungated)}):")
        show([r for r in rows if r[4]])
    print(f"\n{len(rows)} per-frame sources, {len(ungated)} ungated")
    return 0


if __name__ == "__main__":
    sys.exit(main())
