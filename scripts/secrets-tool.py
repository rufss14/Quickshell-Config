#!/usr/bin/env python3
"""One view over the shell's secrets: where they live, and moving them to the keyring.

    secrets-tool.py status     # {"keyring": …, "inFile": n, "inKeyring": n}  — never a value
    secrets-tool.py migrate    # move every key still in a file into the keyring (verified)

The three credential scripts own their files and say where each secret is
(ai-credentials.py, discord-credentials.py, lyrics-translate-credentials.py); this adds
them up for the Setup page (services/Secrets). `migrate` is the one place a Secret Service
that is not running may be STARTED, because it is only ever run on an explicit click —
KWallet may then ask to create or unlock a wallet.

Exit codes: 0 ok · 1 bad usage.
"""
import importlib.util
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import secretstore as SS

MODULES = ("ai-credentials", "discord-credentials", "lyrics-translate-credentials")


def _load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"),
                                                  os.path.join(HERE, name + ".py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def status():
    in_file = in_keyring = 0
    for name in MODULES:
        st = _load(name).status()
        for where in st["stored"].values():
            if where == "file":
                in_file += 1
            elif where == "keyring":
                in_keyring += 1
    return {"keyring": SS.service_state(), "inFile": in_file, "inKeyring": in_keyring}


def migrate():
    total = {"moved": 0, "failed": 0, "state": SS.service_state()}
    for name in MODULES:
        r = _load(name).migrate()
        total["moved"] += r["moved"]
        total["failed"] += r["failed"]
    return total


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "status":
        out = status()
    elif cmd == "migrate":
        out = dict(migrate(), **{k: v for k, v in status().items() if k != "keyring"})
    else:
        sys.stderr.write("usage: secrets-tool.py status|migrate\n")
        return 1
    json.dump(out, sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
