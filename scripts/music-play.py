#!/usr/bin/env python3
"""Play something on Spotify by name — for the overview's AI ("play Bohemian Rhapsody").

    music-play.py "<what>" [--kind track|album|playlist|artist]
    music-play.py --selftest

Prints one JSON object, always exits 0:
    {"ok": true, "uri": "spotify:track:…", "title": "Bohemian Rhapsody - song by Queen", "how": "played"}
    {"ok": false, "error": "…"}

It NEVER opens Spotify's search page as a last resort: that went through OpenUri, which stopped
whatever was playing and played nothing (the user, 2026-10-24). Not found = said so, music untouched.

── First: Spotify itself, through the bridge (scripts/spotify-bridge.py, POST /play) ─
The bridge passes the words to the Spicetify extension (its mailbox), which searches inside Spotify
and plays the hit — exact and instant. Needs this repo's extension applied (spicetify apply) and the
bridge restarted; otherwise it answers 503/504 and the two below run.

── Then: finding it with no Spotify account or key ────────────────────────────
Spotify's search API wants an app key and a login; this shell has neither and shouldn't need one. A
web search does it: DuckDuckGo's HTML page for `site:open.spotify.com/<kind> <what>`, and the first
result's id. That query goes to DuckDuckGo — the same place the launcher's web search sends things
(Config.webSearchUrl's default), and only when you asked the AI to play something.

── Playing it ─────────────────────────────────────────────────────────────────
Spotify running: its MPRIS interface's OpenUri plays the URI at once (gdbus, part of glib2 — on every
Arch desktop). Not running: `xdg-open spotify:…` starts it on that page via its URI handler (the
official app, the Flatpak and spotify-launcher all register one); the user presses play.
"""

import html
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

KINDS = ("track", "album", "playlist", "artist")
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Quicktest"}
ID = r"[A-Za-z0-9]{22}"


def find(query, kind, page=None):
    """The first open.spotify.com/<kind>/<id> in a DuckDuckGo result page → (uri, title) or None."""
    if page is None:
        q = urllib.parse.urlencode({"q": "site:open.spotify.com/%s %s" % (kind, query)})
        req = urllib.request.Request("https://html.duckduckgo.com/html/?" + q, headers=UA)
        with urllib.request.urlopen(req, timeout=10) as r:
            page = r.read().decode("utf-8", "replace")
    # A result's link is DuckDuckGo's redirect with the real URL encoded inside it, and its title is
    # the anchor's text.
    for m in re.finditer(r'<a[^>]+class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>', page, re.S):
        href = urllib.parse.unquote(html.unescape(m.group(1)))
        hit = re.search(r"open\.spotify\.com/(?:intl-[a-z]+/)?%s/(%s)" % (kind, ID), href)
        if hit:
            title = html.unescape(re.sub(r"<[^>]+>", "", m.group(2))).strip()
            title = re.sub(r"\s*\|\s*Spotify\s*$", "", title)
            return "spotify:%s:%s" % (kind, hit.group(1)), title
    hit = re.search(r"open\.spotify\.com(?:%2F|/)" + kind + r"(?:%2F|/)(" + ID + ")", page)
    return ("spotify:%s:%s" % (kind, hit.group(1)), "") if hit else None


def via_bridge(query, kind):
    """The bridge's /play → its answer dict; None when the bridge isn't there at all."""
    port = int(os.environ.get("QS_SPOTIFY_BRIDGE_PORT") or 47821)
    req = urllib.request.Request("http://127.0.0.1:%d/play" % port, method="POST",
                                 data=json.dumps({"query": query, "kind": kind}).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=12) as r:
            doc = json.loads(r.read().decode("utf-8", "replace"))
        return dict(doc, how="played") if doc.get("ok") else None
    except urllib.error.HTTPError as e:
        try:
            doc = json.loads(e.read().decode("utf-8", "replace"))
        except ValueError:
            doc = {}
        err = doc.get("error") or ""
        # Spotify searched and found nothing: an answer, not a reason to try anything else.
        if e.code == 404:
            return {"ok": False, "error": "Spotify found nothing for that"}
        # Anything else (Spotify closed, an extension without the mailbox) → the web search below, with
        # the reason kept for when that fails too.
        return {"ok": False, "fallback": True, "error":
                "Spotify isn't open (or its Quicktest extension isn't loaded)" if err == "spotify-not-listening"
                else "Spotify didn't answer — re-apply the Quicktest Spicetify extension (spicetify apply)" if err == "spotify-no-answer"
                else "Spotify couldn't search: " + (err or "HTTP %d" % e.code)}
    except (urllib.error.URLError, OSError, ValueError):
        return None


def spotify_on_bus():
    try:
        out = subprocess.run(["gdbus", "call", "--session", "--dest", "org.freedesktop.DBus",
                              "--object-path", "/org/freedesktop/DBus", "--method", "org.freedesktop.DBus.ListNames"],
                             capture_output=True, text=True, timeout=3).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""
    m = re.search(r"'(org\.mpris\.MediaPlayer2\.spotify[^']*)'", out)
    return m.group(1) if m else ""


def play(uri):
    """→ "played" (Spotify was running) | "opened" (started on it) | "" (couldn't)."""
    bus = spotify_on_bus()
    if bus and shutil.which("gdbus"):
        r = subprocess.run(["gdbus", "call", "--session", "--dest", bus, "--object-path", "/org/mpris/MediaPlayer2",
                            "--method", "org.mpris.MediaPlayer2.Player.OpenUri", uri],
                           capture_output=True, text=True, timeout=5)
        if r.returncode == 0:
            return "played"
    if shutil.which("xdg-open"):
        subprocess.Popen(["xdg-open", uri], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        return "opened"
    return ""


SAMPLE = '''<div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fopen.spotify.com%2Ftrack%2F2JiDi0qAXsPwhPqA2qaKGt&amp;rut=x">Bohemian Rhapsody - song and lyrics by <b>Queen</b> | Spotify</a></div>
<div class="result"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fopen.spotify.com%2Falbum%2F1GbtB4zTqAsyfZEsm1RZfx">A Night At The Opera</a></div>'''


def selftest():
    assert find("x", "track", SAMPLE) == ("spotify:track:2JiDi0qAXsPwhPqA2qaKGt", "Bohemian Rhapsody - song and lyrics by Queen")
    assert find("x", "album", SAMPLE)[0] == "spotify:album:1GbtB4zTqAsyfZEsm1RZfx"
    assert find("x", "playlist", SAMPLE) is None
    assert find("x", "track", "<p>nothing</p>") is None
    print("music-play selftest: ok")


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        selftest()
        return
    kind = "track"
    if "--kind" in args:
        i = args.index("--kind")
        kind = args[i + 1] if i + 1 < len(args) and args[i + 1] in KINDS else "track"
        del args[i:i + 2]
    query = " ".join(args).strip()[:120]
    if not query:
        print(json.dumps({"ok": False, "error": "play what?"}))
        return
    got = via_bridge(query, kind)
    if got is not None and not got.get("fallback"):
        print(json.dumps(got))
        return
    why = got.get("error") if got else "the Spotify bridge isn't running"
    try:
        hit = find(query, kind)
    except (urllib.error.URLError, OSError) as e:
        hit = None
    if not hit:
        print(json.dumps({"ok": False, "error": "Couldn't find it — " + why}))
        return
    uri, title = hit
    how = play(uri)
    print(json.dumps({"ok": bool(how), "uri": uri, "title": title or query, "how": how,
                      "error": "" if how else "couldn't reach Spotify"}))


if __name__ == "__main__":
    main()
