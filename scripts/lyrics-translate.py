#!/usr/bin/env python3
"""Translate a set of lyric lines, entirely on this machine.

Reads one JSON object on stdin, writes one on stdout, always exits 0:

    in   {"lines": ["…", "…"], "to": "en", "key": "spotify:track:…",
          "backends": ["argos", "deepl", "google", "mymemory"], "cache": true}
    out  {"ok": true, "from": "ja", "to": "en", "lines": ["…", "…"], "cached": false}
    out  {"ok": false, "error": "…", "install": "argos-translate"}

`backends` is the priority order to try (first that answers wins); an id left out
is never contacted. Missing or empty ⇒ the full default order below. `cache`
false skips the disk cache entirely, for both the read and the write.

── Four backends, local preferred, NONE required ───────────────────────────────
  1. argostranslate — runs the model on this machine. Nothing leaves it, no key, no cost,
     works with the network down. Weaker on idiom, which lyrics are full of. Optional AUR
     build plus a per-pair model.
  2. DeepL's API — a real, documented, official service. Needs a free API key (no card,
     500,000 chars/month) from scripts/lyrics-translate-credentials.py. Skipped entirely
     when no key is configured, the same "not installed" shape argostranslate uses.
  3. Google's translate endpoint over plain HTTP. Needs NOTHING installed — python3 is
     already a dependency of this shell — and no key or account.
  4. MyMemory's public translate API — also no key, an actual documented service rather
     than a reverse-engineered one, but a smaller free daily quota and a notch behind on
     idiom-heavy lines. Reached only once DeepL and Google have both already refused, so
     it's what keeps a rate-limited session (or a network that blocks the others
     specifically) from being stuck with nothing.

Whichever works is used, in that order, so installing argos or configuring a DeepL key
later silently upgrades the privacy/reliability without changing anything here. The
order — and which backends are eligible at all — is the CALLER's to set (the "backends"
field): the list above is only the default.

── Backends 2 through 4 SEND THE LYRICS OUT ────────────────────────────────────
Worth being plain about, because this config is published and someone else's machine will
run it. Each line of the track goes to whichever of DeepL/Google/MyMemory answers. No
account (beyond DeepL's own signup, held only in its key), no key transmitted anywhere but
to its own service, and nothing identifying the listener travels with it — but the text
does leave the machine, and that is why the setting is off by default rather than on.

Google's is an UNDOCUMENTED endpoint, the same one every "free translate" tool leans on.
It can change shape or start refusing without notice — and does refuse under sustained use
from one IP (measured: HTTP 429 after a burst of testing). DeepL, tried first of the three
network backends, does not have that problem — a documented API answering documented
status codes — which is the whole reason to configure a key at all. Any refusal, from any
of the three, falls through to the next rather than leaving the lyrics blank, and a total
failure leaves the lyrics exactly as they were, with the reason on
`qs ipc … call lyricstranslate status`.

── A failure is a `kind` the shell can render ────────────────────────────────
Never a crash, never a traceback. A missing model, an unsupported pair, an absent library
— each comes back as `ok: false` with an `install` hint the settings page can show, the
same contract scripts/lyrics.py already follows.

── Detection is by SCRIPT, not by a language model ───────────────────────────
Which alphabet the text is written in is a cheap, reliable signal and needs no extra
dependency. It cannot tell Japanese from Chinese where they share ideographs, so kana
decide it when present — and it does not need to be perfect, because getting the source
wrong produces a bad translation, not a broken shell.
"""

import sys, os, json, re, hashlib, unicodedata, importlib.util

# ── Reading the key from lyrics-translate-credentials.py, which cannot be imported by
# name ─────────────────────────────────────────────────────────────────────────────
# The filename is hyphenated (house style, matching ai-credentials.py) and a hyphen is
# not valid in a module name. Loading it by PATH rather than copying its reader here
# keeps ONE definition of where the key file lives.
def _load_credentials():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "lyrics-translate-credentials.py")
    spec = importlib.util.spec_from_file_location("lyrics_translate_credentials", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_key_for = _load_credentials().key_for

CACHE_DIR = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell", "lyrics-translate",
)

# Seven days, matching what the reference extension keeps. Lyrics for a given track do not
# change, so the only reason to expire at all is to pick up a better model later.
CACHE_TTL = 7 * 24 * 3600

# ── Script ranges ─────────────────────────────────────────────────────────────
KANA      = re.compile(r"[぀-ヿ]")           # hiragana + katakana → Japanese
HANGUL    = re.compile(r"[가-힯ᄀ-ᇿ]")
CYRILLIC  = re.compile(r"[Ѐ-ӿ]")
IDEOGRAPH = re.compile(r"[一-鿿㐀-䶿]")
ARABIC    = re.compile(r"[؀-ۿ]")
HEBREW    = re.compile(r"[֐-׿]")
GREEK     = re.compile(r"[Ͱ-Ͽ]")
THAI      = re.compile(r"[฀-๿]")
LATIN     = re.compile(r"[A-Za-z]")

# ── Latin-script languages, disambiguated by function word ────────────────────
# The writing system alone cannot tell French from English — both are Latin script — so
# every non-English European lyric used to be detected as "en" and, with English as the
# usual target, silently reported "already in the target language" and never translated.
# These are the handful of very common, near-exclusive function words per language: cheap,
# no extra dependency, same "does not need to be perfect" contract as the script check
# above.
#
# English gets its OWN entry — it used to be the silent default for anything that scored
# zero elsewhere, which is backwards: an ad-lib, an interjection, a proper noun, or an
# English word borrowed into another language's lyric (routine in Brazilian pop) scored
# zero against fr/es/pt/de/it and fell back to "en" by default, and enough of those in one
# track could outvote the language it actually was in dominant()'s weighted tally. Now a
# line with no real signal abstains instead — see _latin_lang.
LATIN_HINTS = {
    "en": re.compile(r"\b(the|and|you|your|is|are|was|were|that|this|with|for|not|but"
                      r"|what|all|when|from|they|have|will|just|love|know|there|been)\b", re.I),
    "fr": re.compile(r"\b(le|la|les|de|des|un|une|est|et|je|tu|il|elle|nous|vous|ils|elles"
                      r"|dans|pour|que|qui|pas|avec|sur|ce|cette|mon|ton|son|ma|ta|sa)\b", re.I),
    "es": re.compile(r"\b(el|los|las|un|una|es|yo|tú|él|ella|nosotros|para|que|con|por"
                      r"|no|te|se|mi|tu|su|está|muy|más)\b", re.I),
    "pt": re.compile(r"\b(o|os|as|um|uma|é|eu|tu|ele|ela|nós|para|que|com|não|se|meu|teu"
                      r"|seu|está|muito|mais|te|você|vc|tá|pra|pro)\b", re.I),
    "de": re.compile(r"\b(der|die|das|ein|eine|und|ich|du|er|sie|wir|ihr|nicht|ist|für"
                      r"|mit|auf|dass|wie|was|nein|sehr)\b", re.I),
    "it": re.compile(r"\b(il|lo|gli|di|un|una|è|io|tu|lui|lei|noi|voi|per|che|con|non"
                      r"|questo|sono|molto|più)\b", re.I),
    # Added when a Dutch sentence was tagged English (it shares "is") and skipped as "already in
    # the target language". These are the words that language does NOT share with its
    # neighbours, so a Dutch/Swedish/Danish/Norwegian line scores for the right one.
    "nl": re.compile(r"\b(het|een|niet|zijn|voor|ook|maar|geen|naar|nog|deze|mijn|ik|jij|hij|wij"
                      r"|wat|hoe|waar|heeft|hebben|wordt|worden|kan|wil|zal|dit|dat|van|met|bij|aan"
                      r"|zij|dan|toch|nooit|altijd|goed|heel|veel)\b", re.I),
    "sv": re.compile(r"\b(och|inte|är|jag|mig|att|som|för|från|men|vad|nu|ska|kan|det|den|ett"
                      r"|någon|bara|också|hur|var|där)\b", re.I),
    "da": re.compile(r"\b(og|ikke|jeg|af|hvad|også|mig|fra|men|skal|kan|hvordan|noget|bare|der"
                      r"|det|den|et|hvor|meget)\b", re.I),
    "no": re.compile(r"\b(og|ikke|jeg|er|av|også|hva|fra|skal|kan|hvordan|noe|bare|det|den|et"
                      r"|hvor|veldig|på|å)\b", re.I),
    "pl": re.compile(r"\b(nie|jest|się|że|jak|ale|tak|czy|nic|już|ja|ty|on|ona|my|wy|po|co|to"
                      r"|bardzo|tylko|dla|przez)\b", re.I),
    "cs": re.compile(r"\b(není|jsem|jsi|jsme|také|jako|ale|že|ještě|když|nebo|já|ty|on|ona|my"
                      r"|vy|co|to|se|jak|velmi|jen|pro|přes)\b", re.I),
    "tr": re.compile(r"\b(bir|ve|bu|için|ile|ne|ben|sen|biz|siz|ama|çok|değil|var|yok|gibi|daha"
                      r"|şey|ya|mi|mı)\b", re.I),
    "id": re.compile(r"\b(yang|dan|di|ke|dari|ini|itu|untuk|dengan|tidak|saya|kamu|dia|kami|kita"
                      r"|akan|ada|juga|sudah|bisa|apa)\b", re.I),
    "ro": re.compile(r"\b(și|în|cu|pe|nu|un|o|este|sunt|pentru|că|mai|din|dar|eu|tu|el|ea|noi"
                      r"|foarte|doar)\b", re.I),
    "fi": re.compile(r"\b(ja|on|ei|että|se|oli|en|sinä|minä|me|te|he|mutta|kun|tämä|niin|olen"
                      r"|ole|vain|kanssa)\b", re.I),
    "hu": re.compile(r"\b(és|az|hogy|nem|egy|van|meg|de|is|mint|én|te|mi|ti|ők|nagyon|csak"
                      r"|vagyok|vagy)\b", re.I),
}


def _latin_scores(text):
    """{language: function-word hits} for a Latin-script text."""
    return {lang: len(pat.findall(text)) for lang, pat in LATIN_HINTS.items()}


def latin_sure(lines):
    """Is the Latin-script guess strong enough to ACT on — to skip a translation as "already
    in the target language"? Needs a few real hits and a clear lead over the runner-up. A
    short line, a name, or a language that shares its everyday words with another scores
    thinly, and acting on a thin guess is how a Dutch sentence was reported as English."""
    total = {}
    for line in lines:
        if not isinstance(line, str):
            continue
        for lang, n in _latin_scores(line).items():
            total[lang] = total.get(lang, 0) + n
    ranked = sorted(total.values(), reverse=True)
    best = ranked[0] if ranked else 0
    second = ranked[1] if len(ranked) > 1 else 0
    return best >= 3 and best >= 2 * second


def _latin_lang(text):
    """Which Latin-script language a line most likely is, "" (abstain) if none clearly
    wins — an unmatched line contributes no opinion to dominant()'s tally rather than
    silently voting English."""
    best, bestN = "", 0
    for lang, pat in LATIN_HINTS.items():
        n = len(pat.findall(text))
        if n > bestN:
            best, bestN = lang, n
    return best


def detect(text):
    """Best guess at the source language from the writing system.

    Kana are checked BEFORE ideographs: Japanese uses both, Chinese only the latter, so a
    line containing any kana is Japanese and one with ideographs alone is Chinese. Getting
    that order wrong sends every Japanese lyric to a Chinese model.
    """
    if KANA.search(text):      return "ja"
    if HANGUL.search(text):    return "ko"
    if IDEOGRAPH.search(text): return "zh"
    if CYRILLIC.search(text):  return "ru"
    if ARABIC.search(text):    return "ar"
    if HEBREW.search(text):    return "he"
    if GREEK.search(text):     return "el"
    if THAI.search(text):      return "th"
    if LATIN.search(text):     return _latin_lang(text)
    return ""


def dominant(lines):
    """The language of the track, not of one line.

    Per-line detection is wrong for lyrics: an English phrase inside a Japanese song would
    be detected as English and left untranslated, and a line of pure punctuation detects as
    nothing at all. One answer for the whole set, by weight of characters.
    """
    tally = {}
    for line in lines:
        lang = detect(line)
        if lang:
            tally[lang] = tally.get(lang, 0) + len(line)
    if not tally:
        return ""
    # Latin loses ties: a mostly-Japanese song peppered with English is a Japanese song.
    return max(tally.items(), key=lambda kv: (kv[1], kv[0] != "en"))[0]


def cache_path(key, src, dst):
    h = hashlib.sha1(("%s|%s|%s" % (key, src, dst)).encode()).hexdigest()
    return os.path.join(CACHE_DIR, h + ".json")


def read_cache(path):
    try:
        import time
        if time.time() - os.stat(path).st_mtime > CACHE_TTL:
            return None
        with open(path) as f:
            return json.load(f)
    except Exception:
        return None


def write_cache(path, payload):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w") as f:
            json.dump(payload, f)
        os.replace(tmp, path)      # atomic: never leave a half-written entry
    except Exception:
        pass


# ── Backends ──────────────────────────────────────────────────────────────────
def _argos(lines, src, dst):
    """Local model. Returns (lines, error) — either may be None."""
    try:
        import argostranslate.translate as at
    except Exception:
        return None, "argostranslate is not installed"

    try:
        langs = at.get_installed_languages()
        from_lang = next((l for l in langs if l.code == src), None)
        to_lang   = next((l for l in langs if l.code == dst), None)
        if from_lang is None or to_lang is None:
            return None, "no %s → %s model installed" % (src, dst)

        tr = from_lang.get_translation(to_lang)
        if tr is None:
            return None, "no direct %s → %s model" % (src, dst)

        done = []
        for line in lines:
            if not isinstance(line, str) or line.strip() == "":
                done.append("")
                continue
            try:
                done.append(tr.translate(line))
            except Exception:
                done.append("")     # one bad line must not lose the other ninety
        return done, None
    except Exception as e:
        return None, str(e)


# ── DeepL ─────────────────────────────────────────────────────────────────────
# https://api-free.deepl.com/v2/translate — free-tier host, matching the free-tier key
# scripts/lyrics-translate-credentials.py holds. A paid key would need api.deepl.com
# instead; not worth detecting automatically for a shell config where the free tier
# (500,000 chars/month) is the whole point of choosing DeepL over a card-requiring
# service. Verified live against the current API docs 2026-09: JSON body, `text` as an
# array (translations come back index-aligned with it — unlike Google/MyMemory, this is
# an OFFICIAL guarantee, so unlike `_threaded_lines` below, one request for every line
# in the track is safe rather than one request per line), `Authorization: DeepL-Auth-Key
# <key>` header. Errors are JSON `{"message": …, "code": …}`; 456 specifically means the
# monthly character quota ran out, worth its own message rather than a bare "HTTP 456".
DEEPL = "https://api-free.deepl.com/v2/translate"


def _deepl(lines, src, dst):
    """One request for the whole track. Returns (lines, error, failed) to match the
    shape `translate()` expects from every network backend."""
    key = _key_for("deepl")
    if not key:
        return None, "no DeepL API key configured", 0

    import urllib.request, urllib.error

    idx = [i for i, l in enumerate(lines) if isinstance(l, str) and l.strip() != ""]
    if not idx:
        return [""] * len(lines), None, 0

    # DeepL's own codes where they differ from ISO 639-1 (Norwegian is NB); an unknown source
    # ("auto") is simply left out and DeepL detects it.
    fields = {"text": [lines[i] for i in idx], "target_lang": dst.upper()}
    if src != "auto":
        fields["source_lang"] = {"no": "NB"}.get(src, src.upper())
    body = json.dumps(fields).encode("utf-8")
    req = urllib.request.Request(DEEPL, data=body, method="POST", headers={
        "Content-Type": "application/json",
        "Authorization": "DeepL-Auth-Key " + key,
    })

    try:
        with urllib.request.urlopen(req, timeout=LINE_TIMEOUT * 2) as r:
            data = json.loads(r.read().decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        msg = None
        try:
            msg = json.loads(e.read().decode("utf-8", "replace")).get("message")
        except Exception:
            pass
        if e.code == 456:
            return None, "deepl: monthly character quota used up", len(idx)
        return None, "deepl: " + (msg or ("HTTP %d" % e.code)), len(idx)
    except Exception as e:
        return None, "deepl: " + str(e), len(idx)

    translations = data.get("translations") or []
    if len(translations) != len(idx):
        return None, "deepl: reply did not match the request", len(idx)

    done = [""] * len(lines)
    for slot, t in zip(idx, translations):
        done[slot] = t.get("text") or ""
    return done, None, 0


GOOGLE = "https://translate.googleapis.com/translate_a/single"

# Measured against the live endpoint, 60 distinct lines, three interleaved runs each so
# the comparison is not just network weather:
#
#     12 in flight → 751 ms      32 in flight → 386 ms
#     24 in flight → 490 ms      48 in flight → 367 ms
#
# It scales cleanly to 32 and then stops paying — 48 buys 19ms for half again as many
# sockets. No failures at any level. The endpoint publishes no rate limit and answers 429
# when it has had enough, so this stays deliberately short of "as many as possible": a
# translated track is worth half a second, not a ban.
CONCURRENCY = 32

# One retry, and a SHORT first timeout rather than a long one.
#
# Both numbers are about the tail, not the average. Every line is fetched in parallel and
# the answer is only complete when the slowest of them lands, so one straggler sets the
# time for the whole track — measured at 5+ seconds against a 400ms median while every
# other line was already in. A 12-second ceiling meant a single stalled socket held the
# lyrics blank for twelve seconds; failing fast and asking again costs less than waiting.
LINE_TIMEOUT = 5
LINE_RETRIES = 1


def _google_line(text, src, dst, timeout=LINE_TIMEOUT):
    """One line, one request. Raises on failure so the caller can count it."""
    import urllib.request, urllib.parse

    url = GOOGLE + "?" + urllib.parse.urlencode({
        "client": "gtx", "sl": src, "tl": dst, "dt": "t", "q": text,
    })
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))

    # [[[translated, original, …], …], …] — the first element holds the segments, which
    # are joined because a long line comes back split at punctuation.
    if not data or not isinstance(data[0], list):
        return ""
    return "".join(seg[0] for seg in data[0] if seg and seg[0])


MYMEMORY = "https://api.mymemory.translated.net/get"

# A courteous fraction of Google's 32 — MyMemory is a much smaller free service (a real
# documented daily word quota, not just an undocumented endpoint tolerating abuse), and
# it is already the LAST resort, reached only when the other two have failed.
MYMEMORY_CONCURRENCY = 8


def _mymemory_line(text, src, dst, timeout=LINE_TIMEOUT):
    """One line, one request. Raises on failure so the caller can count it.

    ── `responseData` is not always the right answer ──────────────────────────
    MyMemory's top-level "best match" is pulled from its translation-memory database by a
    similarity score, and a wrong human-submitted entry can outrank the correct machine
    translation — measured live: "Tourner dans le vide" came back as "13. Whisper" (an
    unrelated 0.89-match memory hit) while `matches` held the right answer, tagged
    created-by "MT!", at 0.85. That fresh machine translation is always present when the
    pair is supported, so it is preferred over the memory-database pick.
    """
    import urllib.request, urllib.parse

    url = MYMEMORY + "?" + urllib.parse.urlencode({
        "q": text, "langpair": "%s|%s" % ("Autodetect" if src == "auto" else src, dst),
    })
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        data = json.loads(r.read().decode("utf-8", "replace"))

    # The free daily quota ran out — a real, distinct failure from a dropped line, so it
    # is worth its own message rather than reading as a generic network error.
    if data.get("quotaFinished"):
        raise RuntimeError("mymemory: daily free quota used up")

    for m in data.get("matches") or []:
        if m.get("created-by") == "MT!":
            return m.get("translation") or ""

    return ((data.get("responseData") or {}).get("translatedText")) or ""


def _threaded_lines(lines, concurrency, fetch_one):
    """Run `fetch_one(text)` for every non-empty line, in parallel, aligned by index.

    Shared by every network backend — one request per line, deliberately: batching is
    faster and cannot be lined back up. The endpoint re-segments whatever it is given —
    a long line comes back split, a short pair comes back merged — so joining the track
    and splitting the reply drifts, and every later translation ends up under the wrong
    lyric. That is worse than no translation, because it looks correct. One line per
    request is aligned BY CONSTRUCTION; the threads pay for the latency.
    """
    import threading

    idx = [i for i, l in enumerate(lines)
           if isinstance(l, str) and l.strip() != ""]
    if not idx:
        return [""] * len(lines), None, 0

    done = [""] * len(lines)
    failures = []
    lock = threading.Lock()
    cursor = [0]

    def worker():
        while True:
            with lock:
                if cursor[0] >= len(idx):
                    return
                slot = idx[cursor[0]]
                cursor[0] += 1

            # Retried, because a line that fails here is not merely missing — it is
            # missing PERMANENTLY. The result is written to the disk cache, so one
            # dropped socket used to blank that lyric for the next seven days, and
            # replaying the track produced the identical gap with nothing to suggest
            # it was ever an error.
            last = None
            for attempt in range(LINE_RETRIES + 1):
                try:
                    done[slot] = fetch_one(lines[slot])
                    last = None
                    break
                except Exception as e:
                    last = str(e)
            if last is not None:
                with lock:
                    failures.append(last)

    threads = [threading.Thread(target=worker, daemon=True)
               for _ in range(min(concurrency, len(idx)))]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=90)

    # Every line failing is a real failure — no network, or the endpoint refusing us. A
    # few failing is a blank line here and there, which is survivable and not worth
    # throwing the rest away for.
    if len(failures) >= len(idx):
        return None, (failures[0] if failures else "translation failed")[:160], len(failures)

    return done, None, len(failures)


def _google(lines, src, dst):
    """Google's translate endpoint over plain HTTP. Needs nothing installed.

    Measured against the live endpoint, 60 distinct lines, three interleaved runs each so
    the comparison is not just network weather:

        12 in flight → 751 ms      32 in flight → 386 ms
        24 in flight → 490 ms      48 in flight → 367 ms

    It scales cleanly to 32 and then stops paying — 48 buys 19ms for half again as many
    sockets. No failures at any level. The endpoint publishes no rate limit and answers 429
    when it has had enough, so this stays deliberately short of "as many as possible": a
    translated track is worth half a second, not a ban.
    """
    return _threaded_lines(lines, CONCURRENCY, lambda t: _google_line(t, src, dst))


def _mymemory(lines, src, dst):
    """MyMemory's public translate API. The third resort: unlike Google's endpoint, this
    one is an actual documented service meant to be called this way, but its free daily
    quota is smaller and translation quality for idiom-heavy lyrics is a notch behind.
    """
    return _threaded_lines(lines, MYMEMORY_CONCURRENCY, lambda t: _mymemory_line(t, src, dst))


# The default order, and the set of ids `backends` is filtered against. Local first
# (argos — nothing leaves the machine), then DeepL (a documented API answering
# documented status codes, which is why it leads the network backends when a key is
# set), then Google's and MyMemory's public endpoints as the no-key fallbacks.
BACKEND_ORDER = ["argos", "deepl", "google", "mymemory"]

_BACKENDS = {
    "argos":    lambda ls, s, d: _argos(ls, s, d) + (0,),   # (lines, err) → (lines, err, failed)
    "deepl":    _deepl,
    "google":   _google,
    "mymemory": _mymemory,
}


def translate(lines, src, dst, backends):
    """The requested backends, in the requested order — first that answers wins.

    Returns (lines, backend, error, failed). `failed` is how many individual lines
    could not be fetched even after a retry. It is not an error — the rest of the track
    is perfectly usable — but it decides whether the answer is fit to CACHE, which is a
    different question. See main().
    """
    errors = []
    for name in backends:
        fn = _BACKENDS.get(name)
        if fn is None:
            continue
        if src == "auto" and name == "argos":
            # A local model is chosen BY source language; with none known there is nothing to pick.
            errors.append("argos: needs a known source language")
            continue
        done, err, failed = fn(lines, src, dst)
        if done is not None:
            return done, name, None, failed
        # A backend that simply isn't configured (no argos install, no DeepL key) still
        # reports a reason; it lands in the combined error only if EVERY backend failed.
        errors.append("%s: %s" % (name, err))

    return None, "", ("; ".join(errors) or "no translation backend is enabled"), len(lines)


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
    dst   = req.get("to") or "en"
    key   = req.get("key") or ""

    # Caller-chosen priority order, filtered to known ids and never empty — an empty or
    # missing list means "the default order", not "translate with nothing".
    backends = [b for b in (req.get("backends") or []) if b in BACKEND_ORDER] or BACKEND_ORDER

    # `cache` defaults to on; only an explicit false disables the disk cache. Off skips
    # the read (so a stale entry can't hide a backend change) AND the write.
    use_cache = req.get("cache", True) is not False

    if not lines:
        out({"ok": True, "from": "", "to": dst, "lines": [], "cached": False})
        return 0

    strs = [l for l in lines if isinstance(l, str)]
    src = dominant(strs)

    # ── How sure is "what language is this?" ──────────────────────────────────
    # By SCRIPT it is a fact (kana, hangul, cyrillic…). Within the Latin script it is a guess
    # from function words, and a thin one for short or loan-word-heavy text. A thin guess is
    # never acted on: it must not skip the translation ("already in the target language") and
    # must not name the source to a backend that would then translate from the wrong one. The
    # source becomes "auto" — Google, DeepL and MyMemory detect it themselves; Argos, which
    # cannot, steps aside (see translate()).
    latin = (not src) or src in LATIN_HINTS
    sure = latin_sure(strs) if latin else True
    if not sure:
        if any(LATIN.search(l) for l in strs):
            src = "auto"
        elif not src:
            out({"ok": False, "error": "could not tell what language this is"})
            return 0
    if not src:
        out({"ok": False, "error": "could not tell what language this is"})
        return 0
    if src == dst:
        # Already in the target language. Reported as a normal answer rather than an
        # error — there is nothing wrong, there is just nothing to do.
        out({"ok": True, "from": src, "to": dst, "lines": list(lines),
             "cached": False, "skipped": True})
        return 0

    path = cache_path(key or "|".join(lines)[:400], src, dst)
    hit = read_cache(path) if use_cache else None
    if hit and len(hit.get("lines") or []) == len(lines):
        hit["cached"] = True
        out(hit)
        return 0

    done, backend, err, failed = translate(lines, src, dst, backends)

    if done is None:
        out({"ok": False, "error": err,
             "install": "translate-shell   (or: argos-translate, for offline)",
             "from": src, "to": dst})
        return 0

    payload = {"ok": True, "from": src, "to": dst, "lines": done,
               "backend": backend, "cached": False, "failed": failed}

    # ── A partial answer is shown, but never KEPT ─────────────────────────────
    # Cached, this would be indistinguishable from a track that genuinely has blank lines,
    # and it would stay that way for a week. The lines that did arrive are still returned —
    # there is no reason to throw away fifty-eight good translations over two — but the
    # next play gets a real attempt instead of a preserved bad night on the network.
    if failed == 0 and use_cache:
        write_cache(path, payload)

    out(payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
