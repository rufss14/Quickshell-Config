#!/usr/bin/env python3
"""Read and write $XDG_STATE_HOME/quicktest/secrets/discord-rpc.json (qspaths.py), without leaking the secret.

    discord-credentials.py --status      # what's configured, secret NOT included
    discord-credentials.py --migrate     # move the secret + presence ids from the file to the keyring
    echo '{"clientId":"…"}' | discord-credentials.py    # merge and save
    echo '{"presenceClientId":"…"}' | discord-credentials.py   # the "Claude Code" card's app id

Exists so the settings page can set up Discord without the user hand-editing JSON, and
without the client secret ever becoming readable from the shell.

── Why the secret goes over STDIN and never argv ─────────────────────────────
Command lines are world-readable on Linux: anything in argv shows up in `/proc/<pid>/
cmdline` and in every `ps` on the machine, for as long as the process lives. A secret
passed as an argument is a secret published to every other user and every process on
the box. Stdin is a pipe between exactly two processes and appears nowhere.

This is also why the shell runs THIS instead of writing the file from QML: Quickshell
has no way to create a file 0600 (`FileView` writes with the default umask), and a
credentials file that is briefly world-readable has already lost.

── Why --status never returns the secret ─────────────────────────────────────
The settings page needs to know whether a secret is SET, never what it is. Returning it
would put it in a QML property, where it lives in memory for the session and lands in
any object dump — for a value the UI has no use for. So the answer is a boolean, and
saving with no `clientSecret` key means "leave the stored one alone", which is what lets
the page edit everything else without ever having held it.

Exit codes: 0 ok · 1 bad input (including a malformed application id) · 2 could not write.
"""

import json, os, sys, tempfile
import sys as _sys; _sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qspaths   # where secret files live (outside the repo)

import secretstore as SS      # the client secret lives in the system keyring when one is running

SECRET_FIELD, SECRET_NAME = "clientSecret", "discord-client-secret"
# The presence apps' ids are not secrets (they go to Discord in the clear), but they are
# per-user config nobody wants lying in a world-readable-by-mistake file either, and the
# daemons read them through secretstore.resolve — so they move with the rest.
# {field in the file: secret name in the keyring}
ID_FIELDS = {
    "presenceClientId":    "discord-presence-client-id",
    "cs2PresenceClientId": "discord-cs2-presence-client-id",
}
STORED = dict(ID_FIELDS, **{SECRET_FIELD: SECRET_NAME})

CONFIG_PATH = qspaths.secret_file("discord-rpc.json")   # outside the repo: qspaths.py

# Written to, and echoed back by --status. Anything else in the file is preserved but
# not advertised — a hand-edited key nobody here knows about is not ours to drop.
KEY_NAMES = ("camera", "screenshare")


def load():
    try:
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            cfg = json.load(f)
    except (OSError, ValueError):
        return {}
    return cfg if isinstance(cfg, dict) else {}


def status():
    cfg = load()
    keys = cfg.get("keys") if isinstance(cfg.get("keys"), dict) else {}
    classes = cfg.get("windowClasses")
    return {
        # The client ID is not a secret — it's sent to Discord in the clear on every
        # handshake — so the page can show it and confirm which app is configured.
        "clientId":    str(cfg.get("clientId") or ""),
        "redirectUri": str(cfg.get("redirectUri") or ""),
        # Deliberately a boolean. See the header.
        "hasSecret":   SS.where(cfg, SECRET_FIELD) != "",
        # "file" · "keyring" · "" — and what the keyring is doing.
        "secretStore": SS.where(cfg, SECRET_FIELD),
        "keyring":     SS.service_state(),
        # Where each keyring-able field lives ("file" · "keyring" · ""), values never.
        "stored":      {f: SS.where(cfg, f) for f in STORED},
        "hasPresenceId": SS.where(cfg, "presenceClientId") != "",
        # Whether the helper may fall back to the shared StreamKit sign-in when no
        # application of your own is set. On unless the file says `false`.
        "sharedApp":   cfg.get("sharedApp") is not False,
        "keys":        {k: str(keys.get(k) or "") for k in KEY_NAMES},
        "windowClasses": classes if isinstance(classes, list) else [],
        "path":        CONFIG_PATH,
    }


def save(patch):
    cfg = load()

    for field in ("clientId", "redirectUri"):
        if field in patch:
            cfg[field] = str(patch[field] or "").strip()

    # Absent means "keep what's stored" — that's the whole reason the page can work
    # without ever reading the secret. An explicit empty string still clears it, so
    # there is a way to remove one.
    if SECRET_FIELD in patch:
        SS.store(cfg, SECRET_FIELD, SECRET_NAME, patch[SECRET_FIELD])

    for field, name in ID_FIELDS.items():
        if field in patch:
            val = str(patch[field] or "").strip()
            # An application id is a snowflake: digits only. Refusing anything else keeps a
            # pasted placeholder or a stray secret from being saved as an id (empty clears).
            if val and not (val.isascii() and val.isdigit() and 15 <= len(val) <= 20):
                raise ValueError("%s must be the application's numeric id" % field)
            SS.store(cfg, field, name, val)

    # The default is ON, so only the opt-out is stored.
    if isinstance(patch.get("sharedApp"), bool):
        if patch["sharedApp"]:
            cfg.pop("sharedApp", None)
        else:
            cfg["sharedApp"] = False

    if isinstance(patch.get("keys"), dict):
        keys = cfg.get("keys")
        if not isinstance(keys, dict):
            keys = {}
        for k in KEY_NAMES:
            if k in patch["keys"]:
                keys[k] = str(patch["keys"][k] or "").strip()
        cfg["keys"] = keys

    if isinstance(patch.get("windowClasses"), list):
        cleaned = [str(c).strip().lower() for c in patch["windowClasses"]
                   if str(c).strip()]
        if cleaned:
            cfg["windowClasses"] = cleaned
        else:
            cfg.pop("windowClasses", None)

    write_atomic(cfg)
    return cfg


def write_atomic(cfg):
    """Write 0600, atomically.

    Two things being bought here. `mkstemp` creates at 0600 from the START, so the file
    is never briefly world-readable the way open()-then-chmod leaves it — a window that
    is short but real, and this is a credentials file. And the rename is atomic, so the
    helper polling this path every few seconds can only ever see the old file or the new
    one, never a half-written one it would reject as malformed.
    """
    d = os.path.dirname(CONFIG_PATH)
    os.makedirs(d, exist_ok=True)

    fd, tmp = tempfile.mkstemp(dir=d, prefix=".discord-rpc.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(cfg, f, indent=2, sort_keys=True)
            f.write("\n")
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, CONFIG_PATH)
    except BaseException:
        # Never leave a temp file holding a secret behind on a failed write.
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def migrate():
    """Move the client secret and the presence ids from the file into the keyring
    (verified first)."""
    cfg = load()
    out = SS.migrate(cfg, STORED)
    if out["moved"]:
        write_atomic(cfg)
    return out


def main():
    if "--migrate" in sys.argv[1:]:
        json.dump(migrate(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0
    if "--status" in sys.argv[1:]:
        json.dump(status(), sys.stdout, separators=(",", ":"))
        sys.stdout.write("\n")
        return 0

    raw = sys.stdin.read()
    try:
        patch = json.loads(raw)
    except ValueError as e:
        sys.stderr.write("discord-credentials: bad JSON on stdin (%s)\n" % e)
        return 1
    if not isinstance(patch, dict):
        sys.stderr.write("discord-credentials: expected a JSON object\n")
        return 1

    try:
        save(patch)
    except ValueError as e:
        sys.stderr.write("discord-credentials: %s\n" % e)
        return 1
    except OSError as e:
        sys.stderr.write("discord-credentials: could not write %s (%s)\n"
                         % (CONFIG_PATH, e))
        return 2

    # The reply is a fresh status, so the caller updates from what was actually stored
    # rather than from what it hoped it sent.
    json.dump(status(), sys.stdout, separators=(",", ":"))
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
