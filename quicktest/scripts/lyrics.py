#!/usr/bin/env python3
"""Fetch time-synced lyrics for a track, preferring WORD-level timing.

    lyrics.py --artist … --title … --album … --duration …

Prints JSON, always, and always exits 0. A failure is a `kind` the shell knows how to
render — never a crash, never a stack trace on the terminal.

    {"ok": true,
     "kind": "word" | "line" | "plain" | "instrumental" | "none",
     "source": "netease" | "lrclib" | "cache",
     "lines": [{"t": 35.98, "dur": 3.36,
                "words": [{"t": 35.98, "d": 0.63, "text": "Feels "}, …]}]}

── Why two providers ─────────────────────────────────────────────────────────
LRCLIB only has LINE-level LRC, so a lyrics view built on it can only ever guess where
each word falls. NetEase's `yrc` format carries a start AND a duration per word, which is
what the vocal actually does — "disgrace" held for 1.29s is 1.29s in the data.

They're queried CONCURRENTLY and the best answer wins (word > line > plain), not the first
one back. LRCLIB is also slow and flaky in practice (measured 5–10s, with timeouts), so
waiting on it before even trying NetEase would throw away the whole speed win.

── The failure that matters ──────────────────────────────────────────────────
Not "no lyrics" — that's obvious and harmless. It's the WRONG song's lyrics, confidently
displayed and perfectly in sync with nothing. So a NetEase search hit is only accepted if
its duration is within a few seconds of the track we actually asked for.
"""

import sys, os, json, re, time, hashlib, argparse
import urllib.request, urllib.parse, urllib.error
import threading, queue

TIMEOUT = 6            # per HTTP request
DURATION_SLOP = 3.0    # seconds; how far a search hit may be from the real track
UA = "Mozilla/5.0 (X11; Linux x86_64)"

CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell", "lyrics",
)

RANK = {"word": 4, "line": 3, "plain": 2, "instrumental": 1, "none": 0}


def get(url, timeout=TIMEOUT):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read().decode("utf-8", "replace")


# ── NetEase ──────────────────────────────────────────────────────────────────
# `yrc` lines look like:
#   [35980,3360](35980,630,0)Feels (36610,300,0)like (36910,210,0)I'll …
# i.e. [lineStart,lineDuration] then (wordStart,wordDuration,0)text per word. All ms.
YRC_LINE = re.compile(r"^\[(\d+),(\d+)\](.*)$")
YRC_WORD = re.compile(r"\((\d+),(\d+),\d+\)([^(]*)")
LRC_LINE = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")


def norm(s):
    """Casefold and strip everything that isn't a letter or digit, so
    'Given Up - Remastered' and 'given up' compare equal."""
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


def netease_search(artist, title, duration):
    q = urllib.parse.quote(f"{title} {artist}".strip())
    raw = get(f"https://music.163.com/api/search/get?s={q}&type=1&limit=10")
    songs = (json.loads(raw).get("result") or {}).get("songs") or []
    if not songs:
        return None

    want_t = norm(title)
    want_a = norm(artist)

    # ── Score, don't take the first acceptable hit ────────────────────────────
    # Taking the first result inside the duration window is why lyrics were sometimes
    # subtly out of sync: a remaster, a live cut or a different mix can sit within a few
    # seconds of the original and still have every line land at a different moment. The
    # closest duration among the plausible candidates is the one whose timings will match
    # the audio you are actually hearing.
    best, best_score = None, -1e9
    for s in songs:
        sd = s.get("duration", 0) / 1000
        delta = abs(sd - duration) if duration > 0 else 0

        # A hard gate first: outside the window it is simply a different recording.
        if duration > 0 and delta > DURATION_SLOP:
            continue

        st = norm(s.get("name"))
        sa = norm(", ".join(a["name"] for a in s.get("artists", [])))

        score = 0.0
        score -= delta * 2.0                                   # every second of drift hurts
        if st == want_t:                    score += 3.0       # exact title
        elif want_t and want_t in st:       score += 1.5
        if want_a and (want_a in sa or sa in want_a): score += 2.0

        if score > best_score:
            best, best_score = s, score

    if best:
        return best["id"]

    # Nothing survived the duration gate. With no duration to check against we can still
    # take the top hit; otherwise refuse — no lyrics beats the wrong song's lyrics.
    return songs[0]["id"] if duration <= 0 else None


def parse_yrc(text):
    out = []
    for raw in text.split("\n"):
        m = YRC_LINE.match(raw.strip())
        if not m:
            continue
        words = [
            {"t": int(a) / 1000, "d": int(b) / 1000, "text": t}
            for a, b, t in YRC_WORD.findall(m.group(3))
            if t
        ]
        if not words:
            continue
        out.append({
            "t": int(m.group(1)) / 1000,
            "dur": int(m.group(2)) / 1000,
            "words": words,
        })
    out.sort(key=lambda l: l["t"])
    return out


def parse_lrc(text):
    """Line-level LRC. A row may carry several timestamps (a repeated chorus)."""
    out = []
    for raw in text.split("\n"):
        stamps = LRC_LINE.findall(raw)
        if not stamps:
            continue
        body = raw[raw.rfind("]") + 1:].strip()
        for mm, ss in stamps:
            out.append({"t": int(mm) * 60 + float(ss.replace(":", ".")), "dur": 0, "words": None})
            out[-1]["text"] = body
    out.sort(key=lambda l: l["t"])
    return out


def strip_credits(lines):
    """NetEase prefixes songs with 作词/作曲 credit lines. They aren't lyrics."""
    def is_credit(l):
        t = l.get("text") or "".join(w["text"] for w in (l.get("words") or []))
        return bool(re.match(r"^\s*(作词|作曲|编曲|制作人|Produced|Written)\s*[:：]", t))
    return [l for l in lines if not is_credit(l)]


def netease(artist, title, album, duration):
    sid = netease_search(artist, title, duration)
    if not sid:
        return {"kind": "none", "lines": [], "source": "netease"}

    raw = get(f"https://music.163.com/api/song/lyric?id={sid}&lv=1&kv=1&tv=1&yv=1")
    d = json.loads(raw)

    yrc = (d.get("yrc") or {}).get("lyric")
    if yrc:
        lines = strip_credits(parse_yrc(yrc))
        if lines:
            return {"kind": "word", "lines": lines, "source": "netease"}

    lrc = (d.get("lrc") or {}).get("lyric")
    if lrc:
        lines = strip_credits(parse_lrc(lrc))
        if lines:
            return {"kind": "line", "lines": lines, "source": "netease"}

    return {"kind": "none", "lines": [], "source": "netease"}


# ── LRCLIB ───────────────────────────────────────────────────────────────────
def lrclib(artist, title, album, duration):
    url = ("https://lrclib.net/api/get"
           f"?artist_name={urllib.parse.quote(artist)}"
           f"&track_name={urllib.parse.quote(title)}"
           f"&album_name={urllib.parse.quote(album)}"
           f"&duration={int(round(duration))}")
    try:
        d = json.loads(get(url))
    except urllib.error.HTTPError as e:
        if e.code == 404:
            return {"kind": "none", "lines": [], "source": "lrclib"}
        raise

    if d.get("instrumental"):
        return {"kind": "instrumental", "lines": [], "source": "lrclib"}
    if d.get("syncedLyrics"):
        lines = parse_lrc(d["syncedLyrics"])
        if lines:
            return {"kind": "line", "lines": lines, "source": "lrclib"}
    if d.get("plainLyrics"):
        return {"kind": "plain", "lines": [], "plain": d["plainLyrics"], "source": "lrclib"}
    return {"kind": "none", "lines": [], "source": "lrclib"}


# ── Orchestration ────────────────────────────────────────────────────────────
def cache_path(artist, title, album, duration):
    key = f"{artist}|{title}|{album}|{int(round(duration))}".lower()
    return os.path.join(CACHE_DIR, hashlib.sha1(key.encode()).hexdigest() + ".json")


def fetch(artist, title, album, duration):
    """Query every provider at once; take the best answer, don't wait for the rest.

    ── Why raw daemon threads and not ThreadPoolExecutor ─────────────────────
    Because the executor will not let us leave. Its workers are non-daemon and
    `concurrent.futures` registers an atexit hook that JOINS them at interpreter
    shutdown — so returning early from a short-circuit gets you nothing: the process
    still sits blocking on the slow provider's socket before it can exit, and
    `shutdown(cancel_futures=True)` doesn't help because it only drops work that hasn't
    STARTED. Measured: 6.2s with the executor, ~1s with daemon threads. Same logic, same
    requests; the difference is entirely in who is allowed to abandon a thread.

    LRCLIB is the slow one (5–10s, sometimes a timeout). NetEase usually answers in ~1s
    with word-level timing — and once we have word-level there is nothing LRCLIB could
    add, so we stop waiting and let its thread die with the process.
    """
    out = queue.Queue()

    def run(fn):
        try:
            out.put(fn(artist, title, album, duration))
        except Exception:
            # A provider being down is not an error for US — the other may still answer,
            # and if neither does the card simply says "no lyrics". One failing endpoint
            # must never take the whole lookup with it.
            out.put(None)

    workers = [threading.Thread(target=run, args=(fn,), daemon=True)
               for fn in (netease, lrclib)]
    for w in workers:
        w.start()

    results = []
    deadline = time.monotonic() + TIMEOUT + 2

    for _ in workers:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            break
        try:
            r = out.get(timeout=remaining)
        except queue.Empty:
            break
        if not r:
            continue
        results.append(r)
        if r["kind"] == "word":
            break          # nothing can beat this; walk away from whatever's still running

    if not results:
        return {"ok": True, "kind": "none", "lines": [], "source": "none"}

    # Best, not first: a word-level answer beats a line-level one even if it arrived later.
    best = max(results, key=lambda r: RANK.get(r["kind"], 0))
    best["ok"] = True
    return best


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--artist", default="")
    p.add_argument("--title", default="")
    p.add_argument("--album", default="")
    p.add_argument("--duration", type=float, default=0)
    a = p.parse_args()

    if not a.title:
        print(json.dumps({"ok": True, "kind": "none", "lines": [], "source": "none"}))
        return

    path = cache_path(a.artist, a.title, a.album, a.duration)

    # Disk cache. Replaying a track — or restarting the shell — costs nothing. This is the
    # biggest single win on how fast the card *feels*.
    try:
        with open(path) as f:
            cached = json.load(f)
        cached["source"] = "cache"
        print(json.dumps(cached))
        return
    except Exception:
        pass

    try:
        result = fetch(a.artist, a.title, a.album, a.duration)
    except Exception as e:
        print(json.dumps({"ok": False, "kind": "none", "lines": [], "error": str(e)}))
        return

    # Only cache a real answer. Caching "none" would make a transient network blip
    # permanent for that track.
    if result.get("kind") in ("word", "line", "plain", "instrumental"):
        try:
            os.makedirs(CACHE_DIR, exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w") as f:
                json.dump(result, f)
            os.replace(tmp, path)     # atomic: never leave a half-written cache entry
        except Exception:
            pass

    print(json.dumps(result))


if __name__ == "__main__":
    main()
