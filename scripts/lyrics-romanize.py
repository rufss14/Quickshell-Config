#!/usr/bin/env python3
"""Romanize a set of lyric lines — Japanese, Korean, Chinese, Cyrillic and friends in Latin letters.

Reads one JSON object on stdin, writes one on stdout, always exits 0:

    in   {"lines": ["…", "…"], "key": "<hash>", "backends": ["google", "local"], "cache": true}
    out  {"ok": true, "script": "ja", "lines": ["…", "…"], "backend": "google",
          "cached": false, "failed": 0}
    out  {"ok": false, "error": "…", "install": "python-pykakasi python-pypinyin …"}

`lines` comes back index-aligned with what went in, "" for a line with nothing to romanize (a
blank, or a phrase already in Latin letters — an English refrain inside a Japanese song). It is
the card's job to draw nothing under those.

── Google first, a local library as the fallback ─────────────────────────────────
  1. Google's public translate endpoint over plain HTTP (`dt=rm` asks for the SOURCE's
     transliteration alongside the translation). Needs nothing installed, and is the best at
     the hard case — kanji read as Japanese rather than as Chinese. **Each line is sent to
     Google**, which is why `Config.lyricsRomanize` is off by default and why the toggle only
     appears on a song that has something to romanize. The same trade-off, and the same
     one-request-per-line rule, as scripts/lyrics-translate.py — whose helpers this reuses
     rather than copies: the HTTP pool, the retry, the script detector and the disk cache.
  2. A local library, when installed: nothing leaves the machine and no network is needed.
     pykakasi (Japanese), pypinyin (Chinese), korean-romanizer (Korean), unidecode (Cyrillic,
     Greek, Thai, Arabic and Hebrew — rough for the last two, which carry no vowels).

`backends` is the caller's order and may drop either; the default is the order above. A missing
library is not an error until it is the only option left: the answer then names what to install.

── UNVERIFIED against the live endpoint ──────────────────────────────────────────
The `dt=rm` reply was written from the documented shape and could not be checked: the endpoint
answered HTTP 429 to every request on the day this was written (it does, under sustained use —
see lyrics-translate.py). It reads the SOURCE transliteration from the trailing
`[null, null, <of the translation>, <of the source>]` entry of the first array. If the shape is
not that, every line comes back empty, which is reported as a failure naming this — never as
"nothing to romanize" — so the fallback runs and the cause is in the error text.
"""

import sys, os, json, importlib.util, threading, time

# ── The translate script's helpers, loaded by PATH (its name has a hyphen) ────────
def _load_translate():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lyrics-translate.py")
    spec = importlib.util.spec_from_file_location("lyrics_translate", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


T = _load_translate()

# Romanization is deterministic, so it keeps far longer than a translation (which may improve) —
# but not all answers are equal. Google reads kanji in context and is the one worth keeping; the
# on-device library is the quick fallback (the answer when Google refused, or while it is still
# on its way), and cached for a month it would stand in for Google's long after Google is
# reachable again. So a Google answer lives 30 days and an on-device one a day.
CACHE_TTL = 30 * 24 * 3600
LOCAL_TTL = 24 * 3600
T.CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell", "lyrics-romanize",
)
T.CACHE_TTL = CACHE_TTL

# A shorter first timeout than translation's 5 s: every line is asked at once and the answer is
# only complete when the slowest lands, so one stalled socket sets the time for the whole song.
# Failing fast and asking once more costs less than waiting (one retry, from the shared pool).
T.LINE_TIMEOUT = 3

# The languages (as the detector names them) that have a Latin form worth showing.
ROMANIZABLE = {"ja", "ko", "zh", "ru", "el", "th", "ar", "he"}

DEFAULT_BACKENDS = ["google", "local"]


def has_script(text):
    """Does this line contain a letter outside the Latin range at all? A refrain in English
    inside a Japanese song has none and is left alone, as is a blank."""
    for ch in text:
        if ord(ch) > 0x24F and ch.isalpha():
            return True
    return False


# ── Google ────────────────────────────────────────────────────────────────────
LIMITED = "rate-limited (HTTP 429)"

# Set by the first 429: every other line, and every retry, then fails at once without a request.
# Forty lines asked at once of a service that has just said no is how a block is prolonged.
_limited = threading.Event()


def _google_line(text, src):
    import urllib.request, urllib.parse, urllib.error
    if _limited.is_set():
        raise RuntimeError(LIMITED)

    url = T.GOOGLE + "?" + urllib.parse.urlencode(
        {"client": "gtx", "sl": src, "tl": "en", "dt": ["t", "rm"], "q": text}, doseq=True)
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    try:
        with urllib.request.urlopen(req, timeout=T.LINE_TIMEOUT) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        # 429 is Google's "Sorry…" block page: it is refusing THIS connection, and asking again
        # only prolongs it — named so the caller can stop asking for a while.
        if e.code == 429:
            _limited.set()
        raise RuntimeError(LIMITED if e.code == 429 else "HTTP %d" % e.code)

    if not data or not isinstance(data[0], list):
        return ""
    # The transliteration entry has no translated text: [null, null, <of the translation>,
    # <of the source>]. A long line may carry several; they join in order.
    parts = []
    for seg in data[0]:
        if (isinstance(seg, list) and len(seg) > 3 and seg[0] is None
                and isinstance(seg[3], str) and seg[3].strip() != ""):
            parts.append(seg[3].strip())
    return " ".join(parts)


def _google(lines, src):
    """(lines, error, failed). Only lines with something to romanize are sent — an English
    refrain, or a blank, never leaves the machine."""
    todo = [l if (isinstance(l, str) and has_script(l)) else "" for l in lines]
    # The pool retries each line once; against a 429 that is cut short by `_limited`. A line that
    # fails otherwise is simply blank; all of them failing is a failure.
    done, err, failed = T._threaded_lines(todo, T.CONCURRENCY, lambda t: _google_line(t, src))
    if done is None:
        return None, err, failed
    # Everything empty from lines that DID have script means the reply was not what this
    # expects (see the note at the top) — not that there was nothing to say.
    if any(todo) and not any(done):
        return None, "Google's reply carried no romanization (its format may have changed)", failed
    return done, None, failed


# ── Local libraries ───────────────────────────────────────────────────────────
def _local_ja():
    import pykakasi
    kks = pykakasi.kakasi()
    return lambda s: " ".join(p.get("hepburn", "") for p in kks.convert(s)).strip()


def _local_zh():
    from pypinyin import lazy_pinyin, Style
    return lambda s: " ".join(lazy_pinyin(s, style=Style.TONE)).strip()


def _local_ko():
    from korean_romanizer.romanizer import Romanizer
    return lambda s: Romanizer(s).romanize().strip()


def _local_translit():
    from unidecode import unidecode
    return lambda s: unidecode(s).strip()


_LOCAL = {
    "ja": (_local_ja,       "python-pykakasi"),
    "zh": (_local_zh,       "python-pypinyin"),
    "ko": (_local_ko,       "python-korean-romanizer"),
    "ru": (_local_translit, "python-unidecode"),
    "el": (_local_translit, "python-unidecode"),
    "th": (_local_translit, "python-unidecode"),
    "ar": (_local_translit, "python-unidecode"),
    "he": (_local_translit, "python-unidecode"),
}


def _local(lines, src):
    """(lines, error, failed). One bad line must not lose the other ninety."""
    entry = _LOCAL.get(src)
    if entry is None:
        return None, "no local romanizer for %s" % src, 0
    make, pkg = entry
    try:
        fn = make()
    except Exception:
        return None, "%s is not installed" % pkg, 0

    done, failed = [], 0
    for l in lines:
        if not (isinstance(l, str) and has_script(l)):
            done.append("")
            continue
        try:
            done.append(fn(l))
        except Exception:
            done.append("")
            failed += 1
    return done, None, failed


_BACKENDS = {"google": _google, "local": _local}


def _unique(lines):
    """(unique lines, back) — `back[i]` is where line i's answer lives in the unique list. A
    chorus sung four times is asked about once: fewer requests is faster, and it is one fewer
    thing for Google to count."""
    seen, uniq, back = {}, [], []
    for l in lines:
        key = l if isinstance(l, str) else ""
        if key not in seen:
            seen[key] = len(uniq)
            uniq.append(key)
        back.append(seen[key])
    return uniq, back


def _call(name, lines, src):
    """One backend over the unique lines, expanded back to the song's own. (lines|None, err, failed)"""
    uniq, back = _unique(lines)
    done, err, failed = _BACKENDS[name](uniq, src)
    if done is None:
        return None, err, failed
    return [done[i] for i in back], None, failed


def _google_state(done, err):
    return "ok" if done is not None else ("limited" if err and "429" in err else "failed")


def romanize(lines, src, backends):
    """First backend that answers wins. Returns (lines, backend, error, failed, google):
    lines is None, with every backend's reason in `error`, when none did. `google` is how
    Google fared — "" (not asked), "ok", "limited" (HTTP 429: stop asking for a while) or
    "failed" — so the caller can back off even when the local library then answered."""
    reasons, google = [], ""
    for name in backends:
        if name not in _BACKENDS:
            continue
        done, err, failed = _call(name, lines, src)
        if name == "google":
            google = _google_state(done, err)
        if done is not None:
            return done, name, None, failed, google
        reasons.append(err)
    return None, "", "; ".join(r for r in reasons if r) or "no backend available", 0, google


def _fresh(entry):
    """Is a cached answer still worth showing? An on-device one goes stale after a day (see
    LOCAL_TTL); one with no stamp predates it and is treated as on-device's age."""
    if entry.get("backend") != "local":
        return True
    return time.time() - float(entry.get("saved_at") or 0) < LOCAL_TTL


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.write("\n")
    sys.stdout.flush()


def main():
    try:
        req = json.load(sys.stdin)
    except Exception as e:
        out({"ok": False, "error": "bad request: %s" % e})
        return 0

    lines = req.get("lines") or []
    key = req.get("key") or ""
    use_cache = req.get("cache", True)
    wanted = [b for b in (req.get("backends") or DEFAULT_BACKENDS) if b in _BACKENDS]
    if not wanted:
        wanted = DEFAULT_BACKENDS

    src = T.dominant([l for l in lines if isinstance(l, str)])
    if src not in ROMANIZABLE:
        out({"ok": False, "error": "nothing to romanize", "none": True, "script": src})
        return 0

    path = T.cache_path(key, src, "rm") if (key and use_cache) else None
    if path:
        hit = T.read_cache(path)
        if hit and len(hit.get("lines") or []) == len(lines) and _fresh(hit):
            hit["cached"] = True
            hit["final"] = True
            out(hit)
            return 0

    # ── Two sources at once: the first answer is not the best one ─────────────
    # The local library answers in a fraction of a second and Google in about one, but Google
    # reads kanji in context and is the better of the two. So with both wanted they run side by
    # side, and the local answer goes out the moment it is ready — marked `final: false`, a line
    # to show NOW — with Google's following to replace it when it lands. If Google fails, the
    # local one is simply confirmed as the answer.
    if "google" in wanted and "local" in wanted:
        box = {}
        th = threading.Thread(target=lambda: box.update(r=_call("google", lines, src)), daemon=True)
        th.start()
        ldone, lerr, lfailed = _call("local", lines, src)
        if ldone is not None:
            out({"ok": True, "script": src, "lines": ldone, "backend": "local", "cached": False,
                 "failed": lfailed, "google": "", "final": False})
        th.join(timeout=60)
        gdone, gerr, gfailed = box.get("r", (None, "google did not answer", 0))
        google = _google_state(gdone, gerr)

        if gdone is not None:
            done, backend, failed = gdone, "google", gfailed
        elif ldone is not None:
            done, backend, failed = ldone, "local", lfailed
        else:
            pkg = _LOCAL.get(src, (None, ""))[1]
            out({"ok": False, "error": "; ".join(r for r in (gerr, lerr) if r), "script": src,
                 "google": google, "install": pkg or "", "none": False, "final": True})
            return 0
    else:
        done, backend, err, failed, google = romanize(lines, src, wanted)
        if done is None:
            pkg = _LOCAL.get(src, (None, ""))[1]
            out({"ok": False, "error": err, "script": src, "google": google,
                 "install": pkg or "", "none": False, "final": True})
            return 0

    payload = {"ok": True, "script": src, "lines": done, "backend": backend,
               "cached": False, "failed": failed, "google": google, "final": True}
    # A partial answer is shown but never kept (see lyrics-translate.py): a dropped line would
    # otherwise stay missing for a month.
    if failed == 0 and path:
        payload["saved_at"] = time.time()
        T.write_cache(path, payload)
    out(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
