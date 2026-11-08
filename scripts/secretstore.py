"""Secrets in the system keyring, with the 0600 files as the fallback.

Used by ai-credentials.py, discord-credentials.py and lyrics-translate-credentials.py (and,
through them, by ai-ask.py, discord-rpc.py and lyrics-translate.py). Plain `import
secretstore` works from any script in this directory.

── What it talks to ──────────────────────────────────────────────────────────
The freedesktop Secret Service (GNOME Keyring, KWallet's compat service, KeePassXC…) through
libsecret's `secret-tool`. One item per secret — attributes `application=quicktest`,
`name=<ai-gemini | discord-client-secret | deepl …>` — rather than one JSON blob (ii's
KeyringStorage): a single secret can be replaced or removed without rewriting the rest, and
nothing needs parsing back out.

── Where a secret LIVES, and how a reader finds it ───────────────────────────
Each credentials file stays the document it was. A secret that has moved to the keyring is
absent from it and its field name is listed under "_keyring" instead — names only, never
values. So:

  • `resolve()` returns the file's value if there is one, else asks the keyring, but only for
    a field that is listed (so a machine that never used the keyring never talks to one);
  • `store()` puts a secret in the keyring when it is already there or the Secret Service is
    RUNNING, and otherwise writes the file exactly as before. It reads the value back before
    it forgets the file's copy;
  • `migrate()` moves what is in the file, and is the only thing that may START a Secret
    Service that isn't running (an explicit user action: KWallet may then ask to create or
    unlock a wallet, which must never come as a surprise at login).

── The failure that matters ──────────────────────────────────────────────────
Losing a key. Nothing here deletes the file's copy until the keyring has returned the same
bytes, and a keyring that stops answering later gives "" (the UI says the key is "in the
keyring, not answering"), never a different key.

The value only ever travels over stdin/stdout of `secret-tool`, never argv.
"""

import shutil
import subprocess

APP = "quicktest"
MARK = "_keyring"
TIMEOUT = 15


def _tool():
    return shutil.which("secret-tool")


def service_state():
    """"running" · "activatable" (D-Bus can start one — it may prompt) · "missing" ·
    "no-tool" (secret-tool isn't installed)."""
    if not _tool():
        return "no-tool"
    busctl = shutil.which("busctl")
    if not busctl:
        return "activatable"        # can't look; secret-tool will find out
    try:
        out = subprocess.run([busctl, "--user", "--no-pager", "list"], capture_output=True,
                             text=True, timeout=TIMEOUT).stdout
    except (OSError, subprocess.SubprocessError):
        return "activatable"
    for line in out.splitlines():
        parts = line.split()
        if parts and parts[0] == "org.freedesktop.secrets":
            return "activatable" if "(activatable)" in line else "running"
    return "missing"


def _run(args, stdin=None):
    try:
        return subprocess.run([_tool()] + args, input=stdin, capture_output=True, text=True,
                              timeout=TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        return None


def get(name):
    p = _run(["lookup", "application", APP, "name", name])
    if p is None or p.returncode != 0:
        return None
    return p.stdout or None


def put(name, value):
    """Store, then read back: True only if the keyring now returns exactly `value`."""
    p = _run(["store", "--label=Quicktest: " + name, "application", APP, "name", name],
             stdin=value)
    if p is None or p.returncode != 0:
        return False
    return get(name) == value


def clear(name):
    p = _run(["clear", "application", APP, "name", name])
    return p is not None and p.returncode == 0


# ── The documents ─────────────────────────────────────────────────────────────
def marked(doc):
    m = doc.get(MARK)
    return {x for x in m if isinstance(x, str)} if isinstance(m, list) else set()


def _set_marked(doc, names):
    if names:
        doc[MARK] = sorted(names)
    else:
        doc.pop(MARK, None)


def where(doc, field):
    """"file" · "keyring" · "" — from the document alone (no keyring call, so a status
    check can never start a wallet prompt)."""
    if str(doc.get(field) or "").strip():
        return "file"
    return "keyring" if field in marked(doc) else ""


def resolve(doc, field, name):
    """The secret as a string ("" if there is none or the keyring isn't answering)."""
    v = str(doc.get(field) or "").strip()
    if v:
        return v
    if field in marked(doc):
        return (get(name) or "").strip()
    return ""


def store(doc, field, name, value):
    """Put `value` where it belongs and fix `doc` to match. Returns "keyring", "file" or
    "cleared". The caller writes `doc`."""
    value = str(value or "").strip()
    m = marked(doc)
    if not value:
        if field in m:
            clear(name)
            m.discard(field)
            _set_marked(doc, m)
        doc.pop(field, None)
        return "cleared"
    if field in m or service_state() == "running":
        if put(name, value):
            doc.pop(field, None)
            m.add(field)
            _set_marked(doc, m)
            return "keyring"
    doc[field] = value
    return "file"


def migrate(doc, fields):
    """Move every plaintext secret in `doc` listed in `fields` ({field: secret name}) into
    the keyring, each verified before the file's copy is dropped. May start a Secret
    Service. Returns {"moved": n, "failed": n, "state": …}; `doc` is changed only for the
    ones that moved."""
    state = service_state()
    out = {"moved": 0, "failed": 0, "state": state}
    if state not in ("running", "activatable"):
        return out
    m = marked(doc)
    for field, name in fields.items():
        v = str(doc.get(field) or "").strip()
        if not v:
            continue
        if put(name, v):
            doc.pop(field, None)
            m.add(field)
            out["moved"] += 1
        else:
            out["failed"] += 1
    _set_marked(doc, m)
    return out
