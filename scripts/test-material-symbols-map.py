#!/usr/bin/env python3
"""Tests for scripts/material-symbols-map.py — the MDI → Material Symbols resolver.

    python3 scripts/test-material-symbols-map.py

Fully mocked and safe to run: no fonts are opened, nothing is written, and the
repo is not scanned. The ligature set is a fixture, so these pass on a machine
that does not have the AUR font installed — which is the point, since that is
exactly the machine the fallback path exists for.

What is worth testing here is the PRECEDENCE, not the table. The table is data
and `--residue` keeps it honest. The order of the rules is logic, and getting it
wrong is silent: an `_outline` strip that ran before MANUAL would quietly ignore
a hand-written correction, and the icon would still render — just the wrong one.
"""

import importlib.util
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("msm", HERE / "material-symbols-map.py")
msm = importlib.util.module_from_spec(spec)
spec.loader.exec_module(msm)

# A stand-in for the font's ligature table.
VALID = {
    "close", "search", "delete", "palette", "warning", "info", "notifications",
    "settings", "wifi", "wifi_off", "battery_full", "keyboard_arrow_down",
    "play_arrow", "visibility", "cloud", "music_note",
}

passed = failed = 0


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"  FAIL  {label}\n          got  {got!r}\n          want {want!r}")


def resolve(mdi, valid=VALID):
    return msm.resolve(mdi, valid)


# ── The rules, one at a time ──────────────────────────────────────────────────
check("exact match wins",            resolve("close"),   ("close", "exact"))
check("alias for a renamed icon",    resolve("magnify"), ("search", "alias"))
check("MANUAL entry",                resolve("play"),    ("play_arrow", "manual"))

# Symbols has no outline NAMES — it has a FILL axis — so the suffix is dropped
# and the base name used. This resolves a large slice of the set on its own.
check("trailing _outline is stripped", resolve("palette_outline"), ("palette", "outline"))

# Brand marks are a decision, not a failure: they must be distinguishable from
# "we could not map this", or --residue never empties and stops being read.
check("brand mark is no-symbol",     resolve("discord"), (None, "no-symbol"))
check("letter badge is no-symbol",   resolve("alpha_b_box"), (None, "no-symbol"))

check("unknown name is UNMATCHED",   resolve("totally_made_up"), (None, "UNMATCHED"))

# ── Precedence ────────────────────────────────────────────────────────────────
# NO_SYMBOL is checked first: a deliberate exclusion must not be overridden by a
# lucky exact match against the font.
saved_valid = VALID | {"discord"}
check("no-symbol beats an exact match",
      msm.resolve("discord", saved_valid), (None, "no-symbol"))

# MANUAL beats everything else, because it is the hand-written correction.
msm.MANUAL["close"] = "cancel"
msm.ALIASES["close"] = "highlight_off"
check("MANUAL beats exact and alias",
      msm.resolve("close", VALID | {"cancel", "highlight_off"}), ("cancel", "manual"))
del msm.MANUAL["close"]
del msm.ALIASES["close"]

# An outline strip must not pre-empt a MANUAL entry for the full name.
msm.MANUAL["visibility_outline"] = "visibility_off"
check("MANUAL beats the outline strip",
      msm.resolve("visibility_outline", VALID | {"visibility_off"}),
      ("visibility_off", "manual"))
del msm.MANUAL["visibility_outline"]

# ── Validation against the font ───────────────────────────────────────────────
# A name the font does not define must NOT be proposed — that is the whole
# defence against an icon rendering as an English word on someone else's machine.
check("a name absent from the font is not proposed",
      msm.resolve("cloud", {"something_else"}), (None, "UNMATCHED"))

check("an alias whose target is absent is reported, not used",
      msm.resolve("magnify", {"close"}), (None, "UNMATCHED"))

# With no font available, validation is skipped and everything is taken on trust —
# so --emit-js still works on a machine without the AUR package.
check("valid=None accepts an exact name", msm.resolve("anything", None), ("anything", "exact"))

# ── nerd_font_names normalisation ─────────────────────────────────────────────
# U+F0388 is named `music-note` in this font, not `md-music_note`. Requiring the
# prefix dropped it into the residue as an unknown glyph; requiring underscores
# would have done the same.
check("hyphens normalise to underscores",
      "music_note" in VALID and resolve("music_note"), ("music_note", "exact"))

print(f"\n{passed} passed, {failed} failed")
sys.exit(0 if failed == 0 else 1)
