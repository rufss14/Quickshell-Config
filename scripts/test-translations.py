#!/usr/bin/env python3
"""Tests for scripts/translations.py — the string scan — and that en_US.json is current.

    python3 scripts/test-translations.py
"""
import os, sys, tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import translations as T

passed = failed = 0
def eq(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("  FAIL  %s\n      got  %r\n      want %r" % (name, got, want))

# ── decode ───────────────────────────────────────────────────────────────────
eq("plain", T.decode('"Reload failed"'), "Reload failed")
eq("escaped quote", T.decode('"Say \\"hi\\""'), 'Say "hi"')
eq("newline", T.decode('"a\\nb"'), "a\nb")
eq("single quoted", T.decode("'It\\'s done'"), "It's done")
eq("single quoted with a double quote inside", T.decode("'say \"x\"'"), 'say "x"')
eq("unicode escape", T.decode('"caf\\u00e9"'), "café")

# ── scan, on a throwaway tree ───────────────────────────────────────────────
tmp = Path(tempfile.mkdtemp(prefix="trtest-"))
def put(rel, text):
    p = tmp / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text, encoding="utf-8")
put("a.qml", '''Item {
    text: Translation.tr("Reload failed")
    title: Translation.tr('Moved %1 keys').arg(n)
    other: Translation.tr("Reload failed")
    x: foo(Translation.tr("Inside a call"), 1)
}''')
put("lib.js", 'var cat = [{ label: N_("Crosshair") }, { label: N_("Performance") }]\n')
put("dyn.qml", 'T { a: Translation.tr("a " + b); b: Translation.tr(c.label); ok: Translation.tr("fine") }\n// Translation.tr("only in a comment")\nT { x: 1 } // Translation.tr("trailing comment") \n')
put("config/settings/skip.qml", 'T { a: Translation.tr("friend app") }\n')
put("scripts/skip.js", 'var a = N_("script")\n')
put("sub/b.qml", 'T { a: Translation.tr("Escaped \\"quote\\" and \\\\ backslash") }\n')
keys, dyn = T.scan(tmp)
eq("literals found", sorted(keys), sorted(["Reload failed", "Moved %1 keys", "Inside a call", "Crosshair",
                                          "Performance", "fine", 'Escaped "quote" and \\ backslash']))
eq("a repeated key lists both files", sorted(set(keys["Reload failed"])), ["a.qml"])
eq("only the concatenation is reported as dynamic", dyn, [("dyn.qml", 1)])
eq("comments are ignored", "only in a comment" in keys or "trailing comment" in keys, False)
eq("the friend's app is skipped", "friend app" in keys, False)
eq("scripts are skipped", "script" in keys, False)

# ── the real tree: the reference file is current, and nothing is dynamic ─────
real, real_dyn = T.scan()
eq("no dynamic Translation.tr() calls in the repo", real_dyn, [])
eq("translations/en_US.json is current (run: python3 scripts/translations.py extract)",
   T.load(T.REFERENCE), T.reference_table(real))

print("%s  %d passed, %d failed" % ("ok" if not failed else "FAIL", passed, failed))
sys.exit(1 if failed else 0)
