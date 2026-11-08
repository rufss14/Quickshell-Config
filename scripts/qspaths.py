"""Where the shell's secret files live: $XDG_STATE_HOME/quicktest/secrets/.

    import qspaths
    CONFIG_PATH = qspaths.secret_file("discord-rpc.json")

The credential documents (discord-rpc.json, ai-keys.json, lyrics-translate-keys.json,
cs2-gsi.json) used to sit in $XDG_CONFIG_HOME/quicktest — which IS this repo, protected
only by .gitignore, one `git add -f` from being published. They now live outside it, in a
0700 directory, each file 0600. (The keyring, when one runs, still holds the secrets
themselves — secretstore.py; these are the fallback files and the non-secret settings
beside them.)

── Moving an existing file ───────────────────────────────────────────────────
The first call for a name that exists at the OLD path and not the new one moves it:
copied to a temporary file in the new directory (0600, O_EXCL), flushed, renamed into
place, read back, and only when the bytes match is the old file removed. Any failure
along the way leaves the old file where it was and returns ITS path, so the caller keeps
working exactly as before — losing a key is the one outcome that must not happen. Two
processes migrating at once is safe: the rename is atomic and the loser sees the new
file already there.

If both exist (a copy restored by hand), the new one wins and the old is left alone.

Tested by scripts/test-qspaths.py (temporary XDG dirs only).
"""

import os

SECRETS = ("quicktest", "secrets")


def _state_home():
    return os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")


def _config_home():
    return os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")


def secrets_dir(create=True):
    d = os.path.join(_state_home(), *SECRETS)
    if create:
        os.makedirs(d, mode=0o700, exist_ok=True)
        os.chmod(d, 0o700)
    return d


def legacy_file(name):
    return os.path.join(_config_home(), "quicktest", name)


def _read(path):
    with open(path, "rb") as f:
        return f.read()


def _migrate(old, new):
    data = _read(old)
    tmp = "%s.%d.tmp" % (new, os.getpid())
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        if os.path.exists(new):          # someone else won the race
            os.unlink(tmp)
        else:
            os.rename(tmp, new)
    except BaseException:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise
    if _read(new) != data:
        raise IOError("read-back mismatch")
    try:
        os.unlink(old)
    except FileNotFoundError:
        pass


def secret_file(name):
    """The path to use for `name`, moving an old copy first (see the module doc)."""
    if os.sep in name or name.startswith("."):
        raise ValueError("a bare file name, please")
    old = legacy_file(name)
    try:
        new = os.path.join(secrets_dir(), name)
    except OSError:
        return old
    if os.path.exists(new) or not os.path.exists(old):
        return new
    try:
        _migrate(old, new)
    except (OSError, IOError):
        return old if os.path.exists(old) else new
    return new
