#!/usr/bin/env python3
"""Read and write $XDG_STATE_HOME/quicktest/secrets/lyrics-translate-keys.json (qspaths.py), without leaking a key.

    lyrics-translate-credentials.py --status               # which providers have a key
    echo '{"deepl":"…:fx"}' | lyrics-translate-credentials.py     # merge and save
    echo '{"deepl":""}'     | lyrics-translate-credentials.py     # clear it

Same contract as scripts/ai-credentials.py and scripts/discord-credentials.py — read
either one's header for the full reasoning. In short:

  - The key travels over STDIN, never argv (world-readable via /proc and ps) and never
    through QML (FileView cannot create a file 0600).
  - `--status` answers with a boolean per provider, never the key itself.
  - Its own file, not config.json: config.json is written by the running shell and
    committed by anyone who forks this config — the last place a key should land.

A separate file from ai-keys.json on purpose: that one holds the launcher's `?`-mode AI
provider keys, a different feature with a different consumer (ai-ask.py). Folding an
unrelated translation-service key into it would make removing or auditing either feature
mean reading the other's.

Exit codes: 0 ok · 1 bad input · 2 could not write.
"""

import json
import os
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)
import sys
import tempfile

import secretstore as SS      # the key lives in the system keyring when one is running

CONFIG_PATH = qspaths.secret_file("lyrics-translate-keys.json")   # outside the repo: qspaths.py

# The providers this script knows how to talk to. A key for anything else is preserved
# in the file but not advertised — a hand-added provider is not ours to drop.
PROVIDERS = ("deepl",)


def load():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return {}
    return cfg if isinstance(cfg, dict) else {}


def secret_name(provider):
    return provider            # "deepl"


def status():
    cfg = load()
    return {
        "has": {p: SS.where(cfg, p) != "" for p in PROVIDERS},
        "stored": {p: SS.where(cfg, p) for p in PROVIDERS},
        "keyring": SS.service_state(),
        "path": CONFIG_PATH,
    }


def migrate():
    """Move the key from the file into the keyring (verified first)."""
    cfg = load()
    out = SS.migrate(cfg, {p: secret_name(p) for p in PROVIDERS})
    if out["moved"]:
        write_atomic(cfg)
    return out


def key_for(provider):
    """The one place a key is ever returned as a string — for lyrics-translate.py's
    own use."""
    return SS.resolve(load(), provider, secret_name(provider))


def save(patch):
    cfg = load()
    for p in PROVIDERS:
        # Absent means "keep what's stored"; an explicit empty string clears it.
        if p in patch:
            SS.store(cfg, p, secret_name(p), patch[p])
    write_atomic(cfg)
    return cfg


def write_atomic(cfg):
    """Write 0600, atomically — mkstemp creates at 0600 from the START, so the file is
    never briefly world-readable the way open()-then-chmod leaves it."""
    d = os.path.dirname(CONFIG_PATH)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".lyrics-translate-keys.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, CONFIG_PATH)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main():
    if "--migrate" in sys.argv[1:]:
        json.dump(migrate(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    if "--status" in sys.argv[1:]:
        json.dump(status(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    try:
        patch = json.loads(sys.stdin.read())
    except ValueError as e:
        sys.stderr.write("lyrics-translate-credentials: bad JSON on stdin (%s)\n" % e)
        return 1
    if not isinstance(patch, dict):
        sys.stderr.write("lyrics-translate-credentials: expected a JSON object\n")
        return 1
    try:
        save(patch)
    except OSError as e:
        sys.stderr.write("lyrics-translate-credentials: could not write %s (%s)\n"
                          % (CONFIG_PATH, e))
        return 2
    json.dump(status(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
