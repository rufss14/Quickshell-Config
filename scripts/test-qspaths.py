#!/usr/bin/env python3
"""scripts/qspaths.py: where secret files go, and the move from the old place.
Runs entirely in temporary XDG dirs; never touches the real ones."""
import os
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

passed = failed = 0


def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print("FAIL %s\n      got  %r\n      want %r" % (name, got, want))


def fresh():
    t = tempfile.mkdtemp(prefix="qspaths-test-")
    os.environ["XDG_STATE_HOME"] = os.path.join(t, "state")
    os.environ["XDG_CONFIG_HOME"] = os.path.join(t, "config")
    os.makedirs(os.path.join(t, "config", "quicktest"))
    return t


import qspaths as Q  # noqa: E402  (after sys.path)

# Nothing anywhere: the new path, in a 0700 dir.
t = fresh()
p = Q.secret_file("ai-keys.json")
check("new path", p, os.path.join(t, "state", "quicktest", "secrets", "ai-keys.json"))
check("dir is 0700", stat.S_IMODE(os.stat(os.path.dirname(p)).st_mode), 0o700)
check("nothing created but the dir", os.path.exists(p), False)

# An old file: moved, 0600, identical, old one gone.
t = fresh()
old = os.path.join(t, "config", "quicktest", "discord-rpc.json")
with open(old, "w") as f:
    f.write('{"clientId": "123", "clientSecret": "s3cret"}')
os.chmod(old, 0o600)
p = Q.secret_file("discord-rpc.json")
check("moved: new path returned", p.startswith(os.path.join(t, "state")), True)
check("moved: same bytes", open(p).read(), '{"clientId": "123", "clientSecret": "s3cret"}')
check("moved: 0600", stat.S_IMODE(os.stat(p).st_mode), 0o600)
check("moved: old removed", os.path.exists(old), False)
check("moved: no temp left", [n for n in os.listdir(os.path.dirname(p)) if n.endswith(".tmp")], [])
check("second call is a no-op", Q.secret_file("discord-rpc.json"), p)

# Both exist: the new one wins, the old is left alone.
t = fresh()
old = os.path.join(t, "config", "quicktest", "ai-keys.json")
open(old, "w").write("old")
new = os.path.join(Q.secrets_dir(), "ai-keys.json")
open(new, "w").write("new")
check("both: new wins", open(Q.secret_file("ai-keys.json")).read(), "new")
check("both: old untouched", open(old).read(), "old")

# The new place can't be written: keep using the old file, never lose it.
t = fresh()
old = os.path.join(t, "config", "quicktest", "cs2-gsi.json")
open(old, "w").write('{"port": 3000}')
os.makedirs(os.path.join(t, "state", "quicktest"))
open(os.path.join(t, "state", "quicktest", "secrets"), "w").write("a file where the dir should be")
p = Q.secret_file("cs2-gsi.json")
check("unwritable: old path returned", p, old)
check("unwritable: old file intact", open(old).read(), '{"port": 3000}')

# Names are names.
try:
    Q.secret_file("../etc/passwd")
    check("a path is refused", False, True)
except ValueError:
    check("a path is refused", True, True)

print("%d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
