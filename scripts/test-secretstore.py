#!/usr/bin/env python3
"""Tests for scripts/secretstore.py — against a fake `secret-tool` and a fake `busctl`.

    python3 scripts/test-secretstore.py

No real keyring is touched: two small shell scripts stand in for the tools, keeping their
"keyring" in a temp directory, and PATH is pointed at them. What matters here is the
policy — when a secret moves, when it must NOT, and that a value is never lost — not
libsecret.
"""
import os, stat, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

tmp = tempfile.mkdtemp(prefix="secretstore-test-")
bindir = os.path.join(tmp, "bin")
vault = os.path.join(tmp, "vault")
os.makedirs(bindir)
os.makedirs(vault)

def script(name, body):
    p = os.path.join(bindir, name)
    with open(p, "w") as f:
        f.write("#!/bin/sh\n" + body)
    os.chmod(p, os.stat(p).st_mode | stat.S_IEXEC)

# fake secret-tool: <vault>/<name> holds the value. FAIL_STORE=1 simulates a refusing keyring;
# CORRUPT=1 simulates one that stores something different from what it was given.
script("secret-tool", '''
cmd=$1; shift
case "$cmd" in
  store)  shift  # --label
          shift; shift  # application quicktest
          shift; name=$1
          [ -n "$FAIL_STORE" ] && exit 1
          v=$(cat); [ -n "$CORRUPT" ] && v="${v}X"
          printf %s "$v" > "'''+vault+'''/$name" ;;
  lookup) shift; shift; shift; name=$1
          [ -f "'''+vault+'''/$name" ] || exit 1
          cat "'''+vault+'''/$name" ;;
  clear)  shift; shift; shift; name=$1; rm -f "'''+vault+'''/$name" ;;
esac
''')
# fake busctl: BUS_STATE=running|activatable|missing
script("busctl", '''
case "$BUS_STATE" in
  running)     echo "org.freedesktop.secrets 1234 gnome-keyring-d rufss :1.9 -" ;;
  activatable) echo "org.freedesktop.secrets - - - (activatable) - -" ;;
esac
exit 0
''')
os.environ["PATH"] = bindir + os.pathsep + os.environ["PATH"]

import secretstore as S

passed = failed = 0
def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
    else:
        failed += 1
        print("  FAIL  %s %s" % (name, detail))
def eq(name, got, want):
    check(name, got == want, "got %r, want %r" % (got, want))
def vault_has(name):
    return os.path.exists(os.path.join(vault, name))
def reset():
    for f in os.listdir(vault):
        os.unlink(os.path.join(vault, f))
    for k in ("FAIL_STORE", "CORRUPT"):
        os.environ.pop(k, None)

# ── service_state ────────────────────────────────────────────────────────────
for state in ("running", "activatable", "missing"):
    os.environ["BUS_STATE"] = state
    eq("state " + state, S.service_state(), state)

# ── store: running service ───────────────────────────────────────────────────
os.environ["BUS_STATE"] = "running"; reset()
doc = {"other": 1}
eq("stores in the keyring", S.store(doc, "gemini", "ai-gemini", " AIza123 "), "keyring")
eq("the secret is trimmed in the vault", open(os.path.join(vault, "ai-gemini")).read(), "AIza123")
check("the file copy is gone", "gemini" not in doc)
eq("the field is marked", doc["_keyring"], ["gemini"])
eq("unrelated keys survive", doc["other"], 1)
eq("where says keyring", S.where(doc, "gemini"), "keyring")
eq("resolve reads it back", S.resolve(doc, "gemini", "ai-gemini"), "AIza123")

# ── store: not running → the file, as before ────────────────────────────────
os.environ["BUS_STATE"] = "activatable"; reset()
doc = {}
eq("a service that isn't running is not started", S.store(doc, "gemini", "ai-gemini", "k"), "file")
eq("kept in the file", doc["gemini"], "k")
check("nothing in the vault", not vault_has("ai-gemini"))
os.environ["BUS_STATE"] = "missing"
eq("no service: the file", S.store(doc, "gemini", "ai-gemini", "k2"), "file")

# ── a refusing keyring never loses the value ────────────────────────────────
os.environ["BUS_STATE"] = "running"; reset(); os.environ["FAIL_STORE"] = "1"
doc = {}
eq("refused store falls back to the file", S.store(doc, "gemini", "ai-gemini", "k"), "file")
eq("and the value is still there", doc["gemini"], "k")
check("and not marked", "_keyring" not in doc)

# ── a keyring that stores something else is caught by the readback ──────────
reset(); os.environ["CORRUPT"] = "1"
doc = {}
eq("mismatched readback is a failure", S.store(doc, "gemini", "ai-gemini", "k"), "file")
eq("so the file keeps the real value", doc["gemini"], "k")

# ── clearing ────────────────────────────────────────────────────────────────
reset(); os.environ["BUS_STATE"] = "running"
doc = {}
S.store(doc, "gemini", "ai-gemini", "k")
eq("clear reports", S.store(doc, "gemini", "ai-gemini", ""), "cleared")
check("clear removes it from the vault", not vault_has("ai-gemini"))
check("and the mark", "_keyring" not in doc)
eq("and resolve is empty", S.resolve(doc, "gemini", "ai-gemini"), "")

# ── a marked field is used even if the service has to be started ─────────────
reset(); os.environ["BUS_STATE"] = "running"
doc = {}
S.store(doc, "gemini", "ai-gemini", "k")
os.environ["BUS_STATE"] = "activatable"
eq("a marked field is replaced in the keyring", S.store(doc, "gemini", "ai-gemini", "k2"), "keyring")
eq("resolve returns the new one", S.resolve(doc, "gemini", "ai-gemini"), "k2")

# ── resolve never asks the keyring about an unmarked field ──────────────────
reset(); os.environ["BUS_STATE"] = "running"
open(os.path.join(vault, "ai-gemini"), "w").write("stray")
eq("an unmarked field ignores the keyring", S.resolve({}, "gemini", "ai-gemini"), "")
eq("the file wins", S.resolve({"gemini": "fromfile"}, "gemini", "ai-gemini"), "fromfile")

# ── migrate ─────────────────────────────────────────────────────────────────
reset(); os.environ["BUS_STATE"] = "activatable"
doc = {"gemini": "g", "openai": " o ", "anthropic": ""}
fields = {"gemini": "ai-gemini", "openai": "ai-openai", "anthropic": "ai-anthropic"}
r = S.migrate(doc, fields)
eq("moved two", r["moved"], 2)
eq("failed none", r["failed"], 0)
check("moved ones leave the file", "gemini" not in doc and "openai" not in doc)
eq("both marked", doc["_keyring"], ["gemini", "openai"])
eq("the vault has the trimmed value", open(os.path.join(vault, "ai-openai")).read(), "o")

reset(); os.environ["BUS_STATE"] = "missing"
doc = {"gemini": "g"}
r = S.migrate(doc, fields)
eq("no service: nothing moved", r["moved"], 0)
eq("and the file is untouched", doc, {"gemini": "g"})

reset(); os.environ["BUS_STATE"] = "running"; os.environ["CORRUPT"] = "1"
doc = {"gemini": "g"}
r = S.migrate(doc, fields)
eq("a bad readback is a failure", (r["moved"], r["failed"]), (0, 1))
eq("and the file keeps the key", doc.get("gemini"), "g")

# ── discord-credentials.py: the presence ids ride the same rails ─────────────
import importlib.util, json
os.environ["XDG_CONFIG_HOME"] = os.path.join(tmp, "cfg")
os.environ["XDG_STATE_HOME"] = os.path.join(tmp, "state")   # qspaths: keep it off the real one
spec = importlib.util.spec_from_file_location("dc", os.path.join(HERE, "discord-credentials.py"))
dc = importlib.util.module_from_spec(spec); spec.loader.exec_module(dc)

reset(); os.environ["BUS_STATE"] = "missing"
dc.save({"presenceClientId": "555000000000000001", "clientId": "111"})
eq("no keyring: the id stays in the file", dc.load().get("presenceClientId"), "555000000000000001")
eq("status says file", dc.status()["stored"]["presenceClientId"], "file")
check("status never carries the id", "555000000000000001" not in json.dumps(dc.status()))

os.environ["BUS_STATE"] = "activatable"
r = dc.migrate()
eq("migrate moves the id", r["moved"], 1)
doc = dc.load()
check("and drops it from the file", "presenceClientId" not in doc)
eq("the public clientId is not a keyring field", doc.get("clientId"), "111")
eq("the vault holds it under its own name", open(os.path.join(vault, "discord-presence-client-id")).read(), "555000000000000001")
eq("resolve finds it", S.resolve(doc, "presenceClientId", "discord-presence-client-id"), "555000000000000001")

os.environ["BUS_STATE"] = "running"
dc.save({"cs2PresenceClientId": "888000000000000001", "presenceClientId": ""})
doc = dc.load()
eq("a new cs2 id goes straight to a running keyring", doc["_keyring"], ["cs2PresenceClientId"])
check("clearing the presence id empties its vault entry", not vault_has("discord-presence-client-id"))

for bad in ("YOUR_APP_ID", "12345", "1234567890123456789012", "１２３４５６７８９０１２３４５６"):
    try:
        dc.save({"presenceClientId": bad}); ok = False
    except ValueError:
        ok = True
    check("rejects a non-snowflake id %r" % bad, ok)

reset(); os.environ["BUS_STATE"] = "no-tool"
os.environ["PATH"] = "/nonexistent"
eq("no secret-tool", S.service_state(), "no-tool")

print("%s  %d passed, %d failed" % ("ok" if not failed else "FAIL", passed, failed))
sys.exit(1 if failed else 0)
