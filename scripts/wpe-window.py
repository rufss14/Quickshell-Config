#!/usr/bin/env python3
"""
wpe-window.py — run linux-wallpaperengine in WINDOW mode. services/ScenePreload.qml
starts one per scene a workspace owns.

    wpe-window.py LOGFILE ARG...   (LOGFILE: where its output goes; ARG...: the
                                    renderer's own arguments, passed through)

Started by `setsid --fork`, so it OUTLIVES a shell reload and the next shell adopts it
(a scene is not loaded again). It ends with the session, or when ScenePreload kills it.
No shell, no string building: argv is handed to the renderer untouched. The log goes to a
FILE in the runtime dir, never a pipe nobody reads (a renderer that fills one blocks).
"""
import os
import sys

# The log lives in the runtime dir, which is the only place the shell asks for.
log = sys.argv[1] if len(sys.argv) > 1 else ""
root = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
if not (os.path.isabs(log) and os.path.realpath(os.path.dirname(log)) == os.path.realpath(root)):
    print("wpe-window: the log file must sit directly in %s" % root, file=sys.stderr)
    sys.exit(2)
fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
os.dup2(fd, 1)
os.dup2(fd, 2)

try:
    os.execvp("linux-wallpaperengine", ["linux-wallpaperengine"] + sys.argv[2:])
except OSError as e:
    print("wpe-window: cannot start linux-wallpaperengine: %s" % e, file=sys.stderr)
    sys.exit(127)
