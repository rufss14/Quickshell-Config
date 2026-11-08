#!/usr/bin/env python3
"""Every user-facing `property` in config/Config.qml must be in `_persisted`.

    python3 scripts/check-config-persisted.py      # exit 1 and list what's missing

A preference survives a shell reload ONLY if `_persisted` names it. Forget it and the
setting works until the next reload and then quietly goes back to its default — which
reads as "it doesn't stick", never as "I missed a list". The runtime audit in Config
(`_auditPrefs`) only catches the opposite mistake, a name in the list with no property
behind it. This catches the omission. It found the cursor's own settings and eleven
older ones (night light, the wallpaper paths, the screenshot options).

What is NOT a preference, and so is skipped:
  · `_`-prefixed properties            internal state
  · `xPref`                            covered when `x` is persisted (object entries in
                                        `_persisted` map the on-disk key to the Pref)
  · EXEMPT below                       each is stored some other way, with the reason
"""
import os
import re
import sys

CONFIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "config", "Config.qml")
# Config is split by area into an inheritance chain (ConfigShell.qml … ConfigDesktop.qml,
# then Config.qml); its properties are declared across all of them.
PARTS = ["ConfigShell", "ConfigEdges", "ConfigBarLayout", "ConfigSystem", "ConfigDesktop", "Config"]

EXEMPT = {
    "presets":       "own file, presets/bar.json",
    "shellPresets":  "own file, presets/shell.json",
    "cursorPresets": "own file, presets/cursor.json",
    "prefsLoaded":   "runtime flag, true once config.json has been read",
    "frameMerge":    "legacy key, read by barLayout's loader and never written",
}


def main():
    src = "\n".join(open(os.path.join(os.path.dirname(CONFIG), p + ".qml")).read() for p in PARTS)
    props = re.findall(r"^    property\s+(?:bool|int|real|double|string|var|color)\s+(\w+)", src, re.M)

    start = src.index("readonly property var _persisted")
    end = src.index("\n    ]", start)
    block = src[start:end]
    named = set(re.findall(r'"(\w+)"', block)) | set(re.findall(r'key:\s*"(\w+)"', block))

    missing = []
    for p in props:
        if p.startswith("_") or p in EXEMPT or p in named:
            continue
        if p.endswith("Pref") and p[:-4] in named:
            continue
        missing.append(p)

    if missing:
        print("Config properties not in _persisted (they reset on every shell reload):")
        for p in missing:
            print("  " + p)
        print("Add each to _persisted, or to EXEMPT in this script with the reason.")
        return 1
    print("persisted=ok (%d properties checked)" % len(props))
    return 0


if __name__ == "__main__":
    sys.exit(main())
