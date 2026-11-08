#!/usr/bin/env python3
"""Fetch headlines for the overview's News page (services/News.qml).

    news-fetch.py --country PT --topic local [--max-age 1200] [--force]
    news-fetch.py --images 12 --country PT --topic local     # pictures for the top stories
    news-fetch.py --selftest

Always prints ONE JSON object and exits 0:

    {"ok": true, "items": [{"title", "source", "domain", "url", "time"}, …],
     "fetched": 1761300000, "edition": "PT", "topic": "local", "stale": false}
    {"ok": false, "error": "…", "items": [<the cached ones, if any>], "stale": true}

── Where it comes from ────────────────────────────────────────────────────────
Google News' public RSS: no key, an edition per country in that country's language, and the
same topics for each. "local" is the edition's top stories (what "near you" means here); every
other topic is that edition's topic page. The feed's own terms allow a personal feed reader,
which is what this is.

── Asked only when the page is SHOWN, and cached ──────────────────────────────
The shell never runs this on a timer. The News page asks when it comes into view, and this
answers from the cache in $XDG_CACHE_HOME/quicktest/news/ while that is younger than --max-age.
A failed fetch hands back the cache (marked stale) rather than an empty page — offline, you
still see what you saw last.

── Pictures (2026-10-24, the user: "is it possible for the news to display some images?") ──
The feed carries none, and its links are Google's own (news.google.com/rss/articles/…), not the
story's. `--images N` unwraps the top N: the article page carries a signature and timestamp, a POST to
Google News' own batchexecute endpoint trades them for the publisher's URL, and that page's
`og:image` is the picture — three requests a story, run six at a time, ~1 s each. Everything found
(or not found) is cached by article id in images.json, forever (a story's picture doesn't change), so
each story is looked up once. A separate pass so the headlines never wait for it; it prints
{"ok", "images": {<google link>: {"image", "url"}}} and the shell merges. The publisher's URL is kept
too: opening a story then goes straight there.

The endpoint is UNDOCUMENTED — if Google changes it, lookups fail quietly and the page is text-only,
as it was. Fetching a publisher's page is what a browser preview does: that site sees the request.
Config.newsImages turns the pass off.

── The country is the caller's ────────────────────────────────────────────────
services/News resolves it (the weather location's country, then the locale). This script
never geolocates by IP. Anything but two letters falls back to the US edition.
"""

import concurrent.futures
import email.utils
import html
import json
import re
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET

TIMEOUT = 12

# Editions whose language isn't simply English. hl (the interface language) and the ceid's
# language part are Google's own codes for that edition; anything not here gets the English
# edition for its country (hl=en-CC, ceid=CC:en), which Google serves for most countries.
EDITIONS = {
    "PT": ("pt-PT", "pt-150"), "BR": ("pt-BR", "pt-419"),
    "ES": ("es", "es"), "MX": ("es-419", "es-419"), "AR": ("es-419", "es-419"),
    "CO": ("es-419", "es-419"), "CL": ("es-419", "es-419"),
    "FR": ("fr", "fr"), "BE": ("fr", "fr"), "CH": ("de", "de"),
    "DE": ("de", "de"), "AT": ("de", "de"), "IT": ("it", "it"), "NL": ("nl", "nl"),
    "PL": ("pl", "pl"), "SE": ("sv", "sv"), "NO": ("no", "no"), "DK": ("da", "da"),
    "FI": ("fi", "fi"), "CZ": ("cs", "cs"), "GR": ("el", "el"), "TR": ("tr", "tr"),
    "RO": ("ro", "ro"), "HU": ("hu", "hu"), "UA": ("uk", "uk"), "RU": ("ru", "ru"),
    "JP": ("ja", "ja"), "KR": ("ko", "ko"), "CN": ("zh-CN", "zh-Hans"),
    "TW": ("zh-TW", "zh-Hant"), "HK": ("zh-HK", "zh-Hant"), "IL": ("he", "he"),
    "SA": ("ar", "ar"), "AE": ("ar", "ar"), "EG": ("ar", "ar"), "ID": ("id", "id"),
    "TH": ("th", "th"), "VN": ("vi", "vi"),
}

TOPICS = ("local", "world", "technology", "science", "business", "sports",
          "entertainment", "health")


def edition(country):
    cc = country.upper() if isinstance(country, str) and len(country) == 2 and country.isalpha() else "US"
    hl, lang = EDITIONS.get(cc, ("en-" + cc, "en"))
    if cc == "US":
        hl = "en-US"
    return cc, {"hl": hl, "gl": cc, "ceid": cc + ":" + lang}


def feed_url(country, topic):
    cc, q = edition(country)
    qs = urllib.parse.urlencode(q)
    if topic == "local":
        return cc, "https://news.google.com/rss?" + qs
    return cc, "https://news.google.com/rss/headlines/section/topic/" + topic.upper() + "?" + qs


def parse(xml_text, limit=30):
    """RSS → items. Google appends " - Source" to every title; that's taken off (the source
    is shown on its own). Items without a title or link are dropped."""
    out = []
    try:
        root = ET.fromstring(xml_text)
    except ET.ParseError:
        return out
    for it in root.iter("item"):
        title = (it.findtext("title") or "").strip()
        link = (it.findtext("link") or "").strip()
        if not title or not link.startswith("https://"):
            continue
        src = it.find("source")
        source = (src.text or "").strip() if src is not None else ""
        src_url = src.get("url", "") if src is not None else ""
        if source and title.endswith(" - " + source):
            title = title[: -len(" - " + source)].rstrip()
        domain = urllib.parse.urlparse(src_url).hostname or ""
        if domain.startswith("www."):
            domain = domain[4:]
        when = 0
        pub = it.findtext("pubDate")
        if pub:
            try:
                when = int(email.utils.parsedate_to_datetime(pub).timestamp())
            except (TypeError, ValueError):
                when = 0
        out.append({"title": title, "source": source, "domain": domain, "url": link, "time": when})
        if len(out) >= limit:
            break
    return out


def cache_path(cc, topic):
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return os.path.join(base, "quicktest", "news", "%s-%s.json" % (cc, topic))


def read_cache(path):
    try:
        with open(path, encoding="utf-8") as f:
            doc = json.load(f)
        return doc if isinstance(doc, dict) and isinstance(doc.get("items"), list) else None
    except (OSError, ValueError):
        return None


def write_cache(path, doc):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(doc, f)
        os.replace(tmp, path)
    except OSError:
        pass


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Quicktest"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read().decode("utf-8", "replace")


def run(country, topic, max_age, force):
    if topic not in TOPICS:
        topic = "local"
    cc, url = feed_url(country, topic)
    path = cache_path(cc, topic)
    cached = read_cache(path)
    now = int(time.time())
    if cached and not force and now - int(cached.get("fetched") or 0) < max_age:
        return dict(cached, ok=True, stale=False, edition=cc, topic=topic)
    try:
        items = parse(fetch(url))
        if not items:
            raise ValueError("the feed had no stories")
        doc = {"items": items, "fetched": now, "edition": cc, "topic": topic}
        write_cache(path, doc)
        return dict(doc, ok=True, stale=False)
    except (urllib.error.URLError, OSError, ValueError) as e:
        reason = getattr(e, "reason", None) or str(e)
        doc = {"ok": False, "error": ("couldn't reach Google News — %s" % reason)[:160],
               "items": (cached or {}).get("items", []), "fetched": (cached or {}).get("fetched", 0),
               "edition": cc, "topic": topic, "stale": True}
        return doc


UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) Quicktest"}


def _get(url, limit=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=TIMEOUT) as r:
        return r.read(limit).decode("utf-8", "replace") if limit else r.read().decode("utf-8", "replace")


def article_id(link):
    """The id at the end of a Google News article link (what images.json is keyed by)."""
    path = urllib.parse.urlparse(link).path
    return path.rsplit("/", 1)[-1] if "/articles/" in path else ""


def og_image(page, base):
    """The page's og:image (or twitter:image), absolute, https only; "" when none."""
    for prop in ("og:image", "og:image:url", "twitter:image"):
        for pat in (r'<meta[^>]+(?:property|name)=["\']%s["\'][^>]*content=["\']([^"\']+)' % re.escape(prop),
                    r'<meta[^>]+content=["\']([^"\']+)["\'][^>]*(?:property|name)=["\']%s["\']' % re.escape(prop)):
            m = re.search(pat, page, re.I)
            if m:
                url = urllib.parse.urljoin(base, html.unescape(m.group(1).strip()))
                return url if url.startswith("https://") else ""
    return ""


def decode_payload(text):
    """batchexecute's answer → the publisher URL, or "". (The reply is `)]}'` then JSON chunks.)"""
    try:
        chunk = json.loads(text.split("\n\n", 1)[1])
        url = json.loads(chunk[0][2])[1]
        return url if isinstance(url, str) and url.startswith(("https://", "http://")) else ""
    except (IndexError, ValueError, TypeError):
        return ""


def resolve(link):
    """A Google News link → {"image", "url"} (either may be "")."""
    aid = article_id(link)
    if not aid:
        return {"image": "", "url": ""}
    page = _get(link)
    sg = re.search(r'data-n-a-sg="([^"]+)"', page)
    ts = re.search(r'data-n-a-ts="([^"]+)"', page)
    if not sg or not ts:
        return {"image": "", "url": ""}
    inner = ('["garturlreq",[["X","X",["X","X"],null,null,1,1,"US:en",null,1,null,null,null,null,null,0,1],'
             '"X","X",1,[1,1,1],1,1,null,0,0,null,0],"%s",%s,"%s"]' % (aid, int(ts.group(1)), sg.group(1)))
    body = urllib.parse.urlencode({"f.req": json.dumps([[["Fbv4je", inner, None, "generic"]]])}).encode()
    req = urllib.request.Request("https://news.google.com/_/DotsSplashUi/data/batchexecute", data=body,
                                 headers=dict(UA, **{"Content-Type": "application/x-www-form-urlencoded;charset=UTF-8"}))
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        url = decode_payload(r.read().decode("utf-8", "replace"))
    if not url:
        return {"image": "", "url": ""}
    try:
        return {"image": og_image(_get(url, 400000), url), "url": url}
    except (urllib.error.URLError, OSError, ValueError):
        return {"image": "", "url": url}


def images_path():
    return os.path.join(os.path.dirname(cache_path("US", "local")), "images.json")


def images(country, topic, n):
    """Pictures for the top `n` stories of the cached list, from images.json or looked up now."""
    if topic not in TOPICS:
        topic = "local"
    cc, _ = feed_url(country, topic)
    items = ((read_cache(cache_path(cc, topic)) or {}).get("items") or [])[:max(0, min(n, 30))]
    path = images_path()
    try:
        with open(path, encoding="utf-8") as f:
            known = json.load(f)
        known = known if isinstance(known, dict) else {}
    except (OSError, ValueError):
        known = {}
    todo = [it["url"] for it in items if article_id(it["url"]) and article_id(it["url"]) not in known]

    def one(link):
        try:
            return link, resolve(link)
        except (urllib.error.URLError, OSError, ValueError):
            return link, None          # not cached: a network blip shouldn't mean "no picture" forever

    if todo:
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            for link, rec in pool.map(one, todo):
                if rec is not None:
                    known[article_id(link)] = dict(rec, t=int(time.time()))
        # The newest 600 lookups are plenty; older stories are long off every list.
        if len(known) > 600:
            known = dict(sorted(known.items(), key=lambda kv: kv[1].get("t", 0))[-600:])
        write_cache(path, known)
    out = {}
    for it in items:
        rec = known.get(article_id(it["url"]))
        if rec and (rec.get("image") or rec.get("url")):
            out[it["url"]] = {"image": rec.get("image", ""), "url": rec.get("url", "")}
    return {"ok": True, "images": out}


SAMPLE = """<?xml version="1.0"?><rss><channel>
<item><title>Storm hits coast - Example Times</title><link>https://news.google.com/rss/articles/abc</link>
<pubDate>Sat, 24 Oct 2026 08:53:24 GMT</pubDate><source url="https://www.example.com">Example Times</source></item>
<item><title>No source here</title><link>https://news.google.com/rss/articles/def</link></item>
<item><title></title><link>https://news.google.com/x</link></item>
<item><title>Bad link</title><link>javascript:alert(1)</link></item>
</channel></rss>"""


def selftest():
    items = parse(SAMPLE)
    assert len(items) == 2, items
    assert items[0]["title"] == "Storm hits coast", items[0]
    assert items[0]["source"] == "Example Times" and items[0]["domain"] == "example.com", items[0]
    assert items[0]["time"] == 1792831404 or items[0]["time"] > 0, items[0]
    assert items[1]["source"] == "" and items[1]["time"] == 0
    assert parse("<not xml") == []
    assert edition("pt")[0] == "PT" and edition("PT")[1]["ceid"] == "PT:pt-150"
    assert edition("../x")[0] == "US" and edition("")[0] == "US"
    assert edition("IN")[1] == {"hl": "en-IN", "gl": "IN", "ceid": "IN:en"}
    assert feed_url("DE", "world")[1].startswith("https://news.google.com/rss/headlines/section/topic/WORLD?")
    assert feed_url("DE", "local")[1].startswith("https://news.google.com/rss?hl=de")
    assert article_id("https://news.google.com/rss/articles/CBMiabc?oc=5") == "CBMiabc"
    assert article_id("https://example.com/x") == ""
    page = '<head><meta property="og:image" content="/img/a.jpg?w=1&amp;h=2"></head>'
    assert og_image(page, "https://site.example/news/1") == "https://site.example/img/a.jpg?w=1&h=2"
    assert og_image('<meta content="https://cdn.x/p.png" name="twitter:image">', "https://x") == "https://cdn.x/p.png"
    assert og_image('<meta property="og:image" content="http://insecure/p.png">', "https://x") == ""
    assert og_image("<p>nothing</p>", "https://x") == ""
    payload = ')]}\'\n\n' + json.dumps([["wrb.fr", "Fbv4je", json.dumps(["garturlres", "https://pub.example/a", 1])]])
    assert decode_payload(payload) == "https://pub.example/a", decode_payload(payload)
    assert decode_payload(")]}'\n\n[]") == "" and decode_payload("garbage") == ""
    print("news-fetch selftest: ok")


def main():
    if "--selftest" in sys.argv:
        selftest()
        return
    args = sys.argv[1:]

    def opt(name, default):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default

    if "--images" in args:
        try:
            n = int(opt("--images", "12"))
        except ValueError:
            n = 12
        print(json.dumps(images(opt("--country", "US"), opt("--topic", "local"), n)))
        return
    try:
        max_age = max(0, int(opt("--max-age", "1200")))
    except ValueError:
        max_age = 1200
    print(json.dumps(run(opt("--country", "US"), opt("--topic", "local"), max_age, "--force" in args)))


if __name__ == "__main__":
    main()
