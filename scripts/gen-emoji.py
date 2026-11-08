#!/usr/bin/env python3
"""Cut services/emoji.json — the launcher's `:` emoji picker — out of the Unicode emoji list.

    python3 scripts/gen-emoji.py [--max-version 16.0]

Needs the `unicode-emoji` package (/usr/share/unicode/emoji/emoji-test.txt) ONLY to
regenerate; the shell reads the committed JSON and never this file. Output is a list of
[char, name, group] in CLDR order (the order a keyboard palette shows them).

What is left out, on purpose:
  * anything not fully-qualified (the same emoji without its variation selector),
  * skin-tone variants — one entry per person/hand; a tone picker is a feature of its own,
  * emoji newer than --max-version: the font installed on a user's machine lags the list,
    and a codepoint it cannot draw is a blank square in a picker.
"""
import argparse, json, os, re, sys

SRC = "/usr/share/unicode/emoji/emoji-test.txt"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "services", "emoji.json")
TONES = {0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF}
LINE = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E(\d+\.\d+)\s+(.+)$")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-version", default="16.0")
    ap.add_argument("--src", default=SRC)
    args = ap.parse_args()
    cap = float(args.max_version)
    if not os.path.exists(args.src):
        sys.exit(f"{args.src} not found — install the unicode-emoji package (only needed to regenerate)")

    out, group = [], ""
    for raw in open(args.src, encoding="utf-8"):
        if raw.startswith("# group:"):
            group = raw.split(":", 1)[1].strip()
            continue
        m = LINE.match(raw.strip())
        if not m or group == "Component":
            continue
        cps = [int(c, 16) for c in m.group(1).split()]
        if any(c in TONES for c in cps) or float(m.group(2)) > cap:
            continue
        out.append(["".join(chr(c) for c in cps), m.group(3).strip(), group])

    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
        f.write("\n")
    print(f"{len(out)} emoji -> {os.path.normpath(OUT)}")


main()
