#!/usr/bin/env python3
"""Tests for lyrics-romanize.py's selection, gating and error shapes.

    python3 scripts/test-lyrics-romanize.py

Fully mocked: no network, no disk, no library needed. It pins the rules that matter —
Google is tried before the local libraries, a failure falls through, only lines that HAVE
script are ever sent out, a Latin-only song is "nothing to romanize" rather than an error, and
a reply with no romanization in it is a FAILURE (so the format changing is loud) and not a
silent blank.
"""

import io, os, sys, json, importlib, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
rm = importlib.import_module("lyrics-romanize")

JA = ["こんにちは", "Hello again", "さようなら", ""]     # an English refrain and a blank inside


def run_all(req, table=None, cache=None):
    """Every JSON line the script wrote, in order (a provisional answer, then the final one)."""
    out = io.StringIO()
    with mock.patch.object(rm.T, "read_cache", lambda p: cache), \
         mock.patch.object(rm.T, "write_cache", lambda p, d: None), \
         mock.patch.dict(rm._BACKENDS, table or {}, clear=table is not None), \
         mock.patch("sys.stdin", io.StringIO(json.dumps(req))), \
         mock.patch("sys.stdout", out):
        rm.main()
    return [json.loads(l) for l in out.getvalue().splitlines() if l.strip()]


def run(req, table=None, cache=None):
    """The ANSWER: the last line written."""
    return run_all(req, table, cache)[-1]


class Script(unittest.TestCase):
    def test_has_script(self):
        self.assertTrue(rm.has_script("こんにちは"))
        self.assertTrue(rm.has_script("Привет"))
        self.assertFalse(rm.has_script("Hello again"))
        self.assertFalse(rm.has_script(""))
        self.assertFalse(rm.has_script("♪ ...!"))

    def test_latin_song_is_nothing_to_romanize(self):
        r = run({"lines": ["Hello there", "and you are not alone"]})
        self.assertFalse(r["ok"])
        self.assertTrue(r.get("none"))          # not an error the card should shout about


class Selection(unittest.TestCase):
    def table(self, google, local, calls):
        def g(lines, src):
            calls.append("google"); return google
        def l(lines, src):
            calls.append("local"); return local
        return {"google": g, "local": l}

    def test_google_wins_when_both_answer(self):
        calls = []
        g = (["G", "", "G", ""], None, 0)
        l = (["l", "", "l", ""], None, 0)
        r = run({"lines": JA, "key": "k"}, self.table(g, l, calls))
        self.assertTrue(r["ok"])
        self.assertEqual(r["backend"], "google")          # the better answer replaces the quick one
        self.assertEqual(sorted(calls), ["google", "local"])
        self.assertEqual(len(r["lines"]), len(JA))        # index-aligned

    def test_the_local_answer_goes_out_first(self):
        calls = []
        g = (["G", "", "G", ""], None, 0)
        l = (["l", "", "l", ""], None, 0)
        got = run_all({"lines": JA, "key": "k"}, self.table(g, l, calls))
        self.assertEqual(len(got), 2)
        self.assertEqual((got[0]["backend"], got[0]["final"]), ("local", False))
        self.assertEqual((got[1]["backend"], got[1]["final"]), ("google", True))

    def test_a_failed_google_confirms_the_local_one(self):
        calls = []
        l = (["l", "", "l", ""], None, 0)
        got = run_all({"lines": JA, "key": "k"}, self.table((None, "rate-limited (HTTP 429)", 0), l, calls))
        self.assertEqual([g["final"] for g in got], [False, True])
        self.assertEqual(got[-1]["backend"], "local")
        self.assertEqual(got[-1]["google"], "limited")

    def test_failure_falls_through_to_local(self):
        calls = []
        r = run({"lines": JA, "key": "k"},
                self.table((None, "429", 0), (["a", "", "b", ""], None, 0), calls))
        self.assertTrue(r["ok"])
        self.assertEqual(r["backend"], "local")
        self.assertEqual(sorted(calls), ["google", "local"])

    def test_caller_order_and_exclusion(self):
        calls = []
        ok = (["a", "", "b", ""], None, 0)
        r = run({"lines": JA, "key": "k", "backends": ["local"]}, self.table(ok, ok, calls))
        self.assertEqual(calls, ["local"])            # Google never contacted when left out
        self.assertEqual(r["backend"], "local")

    def test_a_429_is_reported_so_the_caller_can_back_off(self):
        calls = []
        r = run({"lines": JA, "key": "k"},
                self.table((None, "rate-limited (HTTP 429)", 0), (["a", "", "b", ""], None, 0), calls))
        self.assertTrue(r["ok"])
        self.assertEqual(r["google"], "limited")      # even though the local library answered

    def test_both_failing_reports_both_reasons(self):
        calls = []
        r = run({"lines": JA, "key": "k"},
                self.table((None, "rate-limited (HTTP 429)", 0),
                           (None, "python-pykakasi is not installed", 0), calls))
        self.assertFalse(r["ok"])
        self.assertIn("429", r["error"])
        self.assertIn("pykakasi", r["error"])
        self.assertEqual(r["google"], "limited")

    def test_nothing_answers_names_the_install(self):
        calls = []
        r = run({"lines": JA, "key": "k"},
                self.table((None, "429", 0), (None, "python-pykakasi is not installed", 0), calls))
        self.assertFalse(r["ok"])
        self.assertIn("pykakasi", r["error"])
        self.assertEqual(r["install"], "python-pykakasi")   # Japanese → its package

    def test_cache_hit_skips_every_backend(self):
        calls = []
        hit = {"ok": True, "script": "ja", "lines": ["a", "", "b", ""], "backend": "google"}
        r = run({"lines": JA, "key": "k"}, self.table((None, "x", 0), (None, "x", 0), calls), cache=hit)
        self.assertTrue(r["cached"])
        self.assertEqual(calls, [])


class CachePolicy(unittest.TestCase):
    """What the disk cache keeps, for how long, and when `cache: false` leaves it alone."""

    def drive(self, req, cache, backends_ok=True):
        calls, reads, writes = [], [], []
        def fake(lines, src):
            calls.append("ask"); return (["x"] * len(lines), None, 0)
        out = io.StringIO()
        with mock.patch.object(rm.T, "read_cache", lambda p: reads.append(p) or cache), \
             mock.patch.object(rm.T, "write_cache", lambda p, d: writes.append(d)), \
             mock.patch.dict(rm._BACKENDS, {"google": fake, "local": fake}, clear=True), \
             mock.patch("sys.stdin", io.StringIO(json.dumps(req))), \
             mock.patch("sys.stdout", out):
            rm.main()
        return json.loads(out.getvalue().splitlines()[-1]), calls, reads, writes

    def entry(self, backend, age_s):
        import time
        return {"ok": True, "script": "ja", "lines": ["a", "", "b", ""], "backend": backend,
                "saved_at": time.time() - age_s}

    def test_a_google_answer_is_served_whatever_its_age(self):
        r, calls, _, _ = self.drive({"lines": JA, "key": "k"}, self.entry("google", 20 * 24 * 3600))
        self.assertTrue(r["cached"])
        self.assertEqual(calls, [])

    def test_a_fresh_on_device_answer_is_served(self):
        r, calls, _, _ = self.drive({"lines": JA, "key": "k"}, self.entry("local", 3600))
        self.assertTrue(r["cached"])
        self.assertEqual(calls, [])

    def test_a_stale_on_device_answer_is_asked_again(self):
        r, calls, _, _ = self.drive({"lines": JA, "key": "k"}, self.entry("local", 2 * 24 * 3600))
        self.assertFalse(r["cached"])
        self.assertTrue(calls)                      # Google gets another chance

    def test_an_unstamped_on_device_answer_is_stale(self):
        old = {"ok": True, "script": "ja", "lines": ["a", "", "b", ""], "backend": "local"}
        r, calls, _, _ = self.drive({"lines": JA, "key": "k"}, old)
        self.assertFalse(r["cached"])

    def test_cache_off_neither_reads_nor_writes(self):
        r, calls, reads, writes = self.drive({"lines": JA, "key": "k", "cache": False},
                                             self.entry("google", 10))
        self.assertEqual((reads, writes), ([], []))
        self.assertTrue(calls)

    def test_an_answer_is_kept_with_its_time_and_backend(self):
        r, _, _, writes = self.drive({"lines": JA, "key": "k"}, None)
        self.assertEqual(len(writes), 1)
        self.assertIn("saved_at", writes[0])
        self.assertEqual(writes[0]["backend"], "google")


class Dedupe(unittest.TestCase):
    def test_a_repeated_line_is_asked_once_and_filled_back_in(self):
        song = ["こんにちは", "さようなら", "こんにちは", "こんにちは"]
        asked = []
        def fake(lines, src):
            asked.append(list(lines))
            return ([l.upper() + "!" for l in lines], None, 0)
        r = run({"lines": song, "key": "k", "backends": ["local"]}, {"local": fake})
        self.assertEqual(asked, [["こんにちは", "さようなら"]])          # two asked, not four
        self.assertEqual(len(r["lines"]), 4)                              # four back, aligned
        self.assertEqual(r["lines"][0], r["lines"][2])
        self.assertEqual(r["lines"][0], r["lines"][3])
        self.assertNotEqual(r["lines"][0], r["lines"][1])


class GoogleReply(unittest.TestCase):
    """_google() with the per-line fetch replaced: what it sends, and what it trusts."""

    def test_only_lines_with_script_are_sent(self):
        sent = []
        def fetch(text, src):
            sent.append(text); return "romaji"
        with mock.patch.object(rm, "_google_line", fetch):
            done, err, failed = rm._google(JA, "ja")
        self.assertIsNone(err)
        self.assertEqual(sorted(sent), sorted(["こんにちは", "さようなら"]))
        self.assertEqual(done[1], "")      # the English refrain is never sent, and stays blank
        self.assertEqual(done[3], "")      # nor is a blank

    def test_an_empty_reply_is_a_failure_not_silence(self):
        with mock.patch.object(rm, "_google_line", lambda t, s: ""):
            done, err, failed = rm._google(JA, "ja")
        self.assertIsNone(done)
        self.assertIn("no romanization", err)


class ParseReply(unittest.TestCase):
    def reply(self, data):
        class R:
            def __enter__(s): return s
            def __exit__(s, *a): return False
            def read(s): return json.dumps(data).encode()
        return R()

    def test_source_transliteration_is_read_from_the_trailing_entry(self):
        data = [[["Thank you", "ありがとう", None, None, 10],
                 [None, None, "Arigato", "arigatō"]], None, "ja"]
        with mock.patch("urllib.request.urlopen", lambda *a, **k: self.reply(data)):
            self.assertEqual(rm._google_line("ありがとう", "ja"), "arigatō")

    def test_several_entries_join_in_order(self):
        data = [[["a", "x", None, None], [None, None, "A", "one"],
                 ["b", "y", None, None], [None, None, "B", "two"]]]
        with mock.patch("urllib.request.urlopen", lambda *a, **k: self.reply(data)):
            self.assertEqual(rm._google_line("xy", "ja"), "one two")

    def test_a_reply_without_it_is_empty(self):
        data = [[["Thank you", "ありがとう", None, None, 10]], None, "ja"]
        with mock.patch("urllib.request.urlopen", lambda *a, **k: self.reply(data)):
            self.assertEqual(rm._google_line("ありがとう", "ja"), "")


if __name__ == "__main__":
    unittest.main(verbosity=1)
