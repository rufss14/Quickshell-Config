#!/usr/bin/env python3
"""Change Spotify's queue through the bridge: move a song, or remove one. For the media page's Queue tab.

    spotify-queue.py '<json>'

where the JSON is the bridge's /queue-op body:
    {"op": "reorder", "uid": "…", "uri": "spotify:track:…", "anchorUid": "…", "anchorUri": "…", "where": "before"|"after"}
    {"op": "remove",  "uid": "…", "uri": "spotify:track:…"}

Prints one JSON object and always exits 0:
    {"ok": true}
    {"ok": false, "error": "…"}   (a sentence the page can show)

The bridge (scripts/spotify-bridge.py, POST /queue-op) hands the request to the Spicetify extension, which calls
Spotify's own queue API and reports back. It needs this repo's extension applied (`spicetify apply`) and the bridge
restarted; an older extension never answers, which shows as "Spotify didn't answer".
"""

import json
import os
import sys
import urllib.error
import urllib.request


def ask(body):
    port = int(os.environ.get("QS_SPOTIFY_BRIDGE_PORT") or 47821)
    req = urllib.request.Request("http://127.0.0.1:%d/queue-op" % port, method="POST",
                                 data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            doc = json.loads(r.read().decode("utf-8", "replace"))
        return {"ok": bool(doc.get("ok")), "error": str(doc.get("error") or ""), "link": str(doc.get("link") or "")}
    except urllib.error.HTTPError as e:
        try:
            err = (json.loads(e.read().decode("utf-8", "replace")) or {}).get("error") or ""
        except ValueError:
            err = ""
        # Spotify's own client error names no reason; say what happened in words the page can show.
        if err == "HttpResponseError":
            err = "Spotify refused that change"
        if e.code == 400 and err.startswith("not-understood"):
            err = "The shell sent a queue request the bridge would not take: " + err.split(": ", 1)[-1]
        return {"ok": False, "error":
                "Spotify isn't open, or its Quicktest extension isn't loaded" if err == "spotify-not-listening"
                else "Spotify didn't answer. Re-apply the Quicktest extension (spicetify apply)" if err == "spotify-no-answer"
                else err if err.startswith("The shell sent")
                else err or "Spotify refused (HTTP %d)" % e.code}
    except (urllib.error.URLError, OSError, ValueError):
        return {"ok": False, "error": "The Spotify bridge isn't running"}


def main():
    try:
        body = json.loads(sys.argv[1]) if len(sys.argv) > 1 else None
    except ValueError:
        body = None
    out = ask(body) if isinstance(body, dict) else {"ok": False, "error": "No request given"}
    print(json.dumps(out))


if __name__ == "__main__":
    main()
