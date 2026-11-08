#!/usr/bin/env python3
"""
gamemode-art.py — the picture for a Steam game, for the Game Mode panel's banner and history.

    gamemode-art.py <appid> [<appid>…]      → one JSON object on stdout, always; exit 0

out  {"1030300": "/home/u/.local/share/Steam/appcache/librarycache/1030300/<hash>/library_header.jpg", "55": ""}
     "" = no picture found (and none could be fetched)

Answers from XDG_CACHE_HOME/quicktest/gamemode-art/<id>.jpg when it has one. Else it looks in Steam's own
library cache — what the Steam window already shows, so it costs nothing and sends nothing:
<base>/appcache/librarycache/<id>/<hash>/library_header.jpg (the 460x215 header), else the library hero, else
the capsule — for each Steam install (the native one, ~/.steam/steam, the Flatpak) — and COPIES the hit into
that cache folder, so a history row keeps its picture after Steam clears its cache or the game is uninstalled.
Only if Steam has none (a game never shown in its library) it fetches Steam's public header from its CDN
ONCE into the same place; that request names the app id and nothing else. App ids are digits only (they
become a path and a URL).

    python3 scripts/test-gamemode-art.py
"""
import glob
import json
import os
import re
import shutil
import sys
import urllib.request

ID = re.compile(r"^\d{1,10}$")
CDN = "https://cdn.cloudflare.steamstatic.com/steam/apps/%s/header.jpg"
NAMES = ("library_header.jpg", "library_hero.jpg", "library_capsule.jpg")


def bases(env=os.environ):
    home = env.get("HOME") or os.path.expanduser("~")
    data = env.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    return [os.path.join(data, "Steam"), os.path.join(home, ".steam", "steam"),
            os.path.join(home, ".var", "app", "com.valvesoftware.Steam", ".local", "share", "Steam")]


def cache_dir(env=os.environ):
    home = env.get("HOME") or os.path.expanduser("~")
    return os.path.join(env.get("XDG_CACHE_HOME") or os.path.join(home, ".cache"), "quicktest", "gamemode-art")


def steam_cache(appid, roots):
    """The best picture Steam already has for this app, or ""."""
    for name in NAMES:
        for root in roots:
            hits = sorted(glob.glob(os.path.join(root, "appcache", "librarycache", appid, "*", name)))
            if hits:
                return hits[0]
    return ""


def fetch(appid, dest):
    """Download Steam's public header to `dest` (atomic). "" on any failure; JPEG only, ≤ 2 MB."""
    try:
        with urllib.request.urlopen(CDN % appid, timeout=8) as r:
            data = r.read(2_000_001)
    except (OSError, ValueError):
        return ""
    if len(data) > 2_000_000 or data[:2] != b"\xff\xd8":
        return ""
    try:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".part"
        with open(tmp, "wb") as f:
            f.write(data)
        os.replace(tmp, dest)
    except OSError:
        return ""
    return dest


def keep(src, dest):
    """Copy Steam's picture next to ours (atomic) so a history row outlives Steam's cache. dest, or src if it fails."""
    try:
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        tmp = dest + ".part"
        shutil.copyfile(src, tmp)
        os.replace(tmp, dest)
    except OSError:
        return src
    return dest


def find_art(appid, roots, cache, download=fetch):
    dest = os.path.join(cache, appid + ".jpg")
    if os.path.isfile(dest):
        return dest
    hit = steam_cache(appid, roots)
    if hit:
        return keep(hit, dest)
    return download(appid, dest) if download else ""


def main(argv):
    ids = [a for a in argv[1:21] if ID.match(a)]
    if not ids:
        print(json.dumps({}))
        return 0
    roots, cache = bases(), cache_dir()
    print(json.dumps({i: find_art(i, roots, cache) for i in ids}))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
