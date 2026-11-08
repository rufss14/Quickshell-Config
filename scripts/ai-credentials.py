#!/usr/bin/env python3
"""Read and write the launcher's AI provider keys, without leaking them.

    ai-credentials.py --status                       # which providers have a key (booleans)
    ai-credentials.py --migrate                      # move keys from the file to the keyring
    echo '{"gemini":"AIza…"}' | ai-credentials.py     # merge and save
    echo '{"gemini":""}'      | ai-credentials.py     # clear that one

── Why the key goes over STDIN and never argv ────────────────────────────────
Command lines are world-readable on Linux: anything in argv shows up in
`/proc/<pid>/cmdline` and in every `ps` on the machine, for as long as the process
lives. A key passed as an argument is a key published to every other process on the
box. Stdin is a pipe between exactly two processes and appears nowhere.

This is also why the shell runs THIS instead of writing the file from QML: Quickshell
has no way to create a file 0600 (`FileView` writes with the default umask), and a
credentials file that is briefly world-readable has already lost. Same contract as
scripts/discord-credentials.py, for the same reasons — read that one's header too.

── Why --status never returns a key ──────────────────────────────────────────
The settings page and the launcher need to know whether a key is SET, never what it
is. Returning it would put it in a QML property, where it lives in memory for the
session and lands in any object dump — for a value the UI has no use for. So the
answer is a map of booleans, and saving without a provider's field means "leave the
stored one alone".

── This file is NOT config.json ──────────────────────────────────────────────
Deliberately its own file. config.json is written by the running shell, is committed
by anyone who forks this config, and is the last place an API key should be able to
end up by accident.

Exit codes: 0 ok · 1 bad input · 2 could not write.
"""

import json
import os
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)
import sys
import tempfile

import secretstore as SS      # keys live in the system keyring when one is running

CONFIG_PATH = qspaths.secret_file("ai-keys.json")   # outside the repo: qspaths.py

# The providers this shell knows how to talk to. A key for anything else is preserved
# in the file but not advertised — a hand-added provider is not ours to drop.
PROVIDERS = ("gemini", "openai", "anthropic", "xai")


def load():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return {}
    return cfg if isinstance(cfg, dict) else {}


def secret_name(provider):
    return "ai-" + provider


def status():
    cfg = load()
    return {
        # Booleans only. See the header.
        "has": {p: SS.where(cfg, p) != "" for p in PROVIDERS},
        # Where each one lives ("file" · "keyring" · ""), and what the keyring is doing.
        "stored": {p: SS.where(cfg, p) for p in PROVIDERS},
        "keyring": SS.service_state(),
        "path": CONFIG_PATH,
    }


def key_for(provider):
    """The one place a key is ever returned as a string — for ai-ask.py's own use."""
    return SS.resolve(load(), provider, secret_name(provider))


def migrate():
    """Move the keys still in the file into the keyring (verified one by one)."""
    cfg = load()
    out = SS.migrate(cfg, {p: secret_name(p) for p in PROVIDERS})
    if out["moved"]:
        write_atomic(cfg)
    return out


def save(patch):
    cfg = load()
    for p in PROVIDERS:
        # Absent means "keep what's stored"; an explicit empty string clears it, so
        # there is a way to remove one.
        if p in patch:
            SS.store(cfg, p, secret_name(p), patch[p])
    write_atomic(cfg)
    return cfg


def write_atomic(cfg):
    """Write 0600, atomically — mkstemp creates at 0600 from the START, so the file is
    never briefly world-readable the way open()-then-chmod leaves it."""
    d = os.path.dirname(CONFIG_PATH)
    os.makedirs(d, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=d, prefix=".ai-keys.", suffix=".tmp")
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
        sys.stderr.write("ai-credentials: bad JSON on stdin (%s)\n" % e)
        return 1
    if not isinstance(patch, dict):
        sys.stderr.write("ai-credentials: expected a JSON object\n")
        return 1
    try:
        save(patch)
    except OSError as e:
        sys.stderr.write("ai-credentials: could not write %s (%s)\n" % (CONFIG_PATH, e))
        return 2
    json.dump(status(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
