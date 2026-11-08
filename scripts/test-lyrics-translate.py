#!/usr/bin/env python3
"""Tests for lyrics-translate.py's backend selection and cache gating.

    python3 scripts/test-lyrics-translate.py

Fully mocked — every backend callable and both cache functions are replaced, so this
talks to no network and touches no disk. It covers exactly the logic the Now Playing
panel's new controls drive: the priority order is honoured, an unknown or empty list
falls back to the default, the first backend that answers wins, and `cache: false`
skips both the read and the write. It does NOT exercise the real translators — the
live checks during the build did that.
"""

import io, os, sys, json, importlib, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Both XDG dirs point at a temp dir BEFORE any script is imported: the credential
# scripts resolve their files through qspaths.py at import, which would otherwise move a
# real ~/.config/quicktest/discord-rpc.json into a real ~/.local/state (or read one).
import tempfile as _tf
_iso = _tf.mkdtemp(prefix="qs-test-xdg-")
os.environ["XDG_STATE_HOME"] = os.path.join(_iso, "state")
os.environ["XDG_CONFIG_HOME"] = os.path.join(_iso, "config")
lt = importlib.import_module("lyrics-translate")


JA = ["こんにちは", "さようなら"]          # detects as ja, so ja→en is a real request


def run(req, backends_impl, cache=None):
    """Drive main() with stdin = `req`, the backend table swapped for `backends_impl`
    ({name: (lines|None, err, failed)}), and read/write_cache spied on. Returns
    (parsed_output, list_of_backends_actually_called, cache_reads, cache_writes)."""
    called = []
    reads, writes = [], []

    def make(name, result):
        def fn(lines, src, dst):
            called.append(name)
            if result[0] is None:
                return None, result[1], result[2]
            # index-aligned dummy translation
            return (["<%s>" % l for l in lines], None, result[2])
        return fn

    table = {name: make(name, res) for name, res in backends_impl.items()}

    def fake_read(path):
        reads.append(path)
        return cache

    def fake_write(path, payload):
        writes.append((path, payload))

    out = io.StringIO()
    with mock.patch.dict(lt._BACKENDS, table, clear=True), \
         mock.patch.object(lt, "read_cache", fake_read), \
         mock.patch.object(lt, "write_cache", fake_write), \
         mock.patch.object(sys, "stdin", io.StringIO(json.dumps(req))), \
         mock.patch.object(sys, "stdout", out):
        lt.main()

    return json.loads(out.getvalue()), called, reads, writes


class Detection(unittest.TestCase):
    """The Latin-script guess, and when it is sure enough to act on."""

    def test_dutch_is_dutch_not_english(self):
        # It shares "is" with English; the Dutch-only words must outvote it.
        self.assertEqual(lt.detect("Dit is een test van de vertaling, ik hoop dat het werkt"), "nl")

    def test_other_nordic_and_european_languages(self):
        self.assertEqual(lt.detect("Jag vet inte vad det är som du vill"), "sv")
        self.assertEqual(lt.detect("Nie wiem, ale to jest bardzo dobre, jak ty"), "pl")
        self.assertEqual(lt.detect("Bu çok güzel bir şey ama ben bilmiyorum"), "tr")
        self.assertEqual(lt.detect("Saya tidak tahu yang kamu mau untuk itu"), "id")

    def test_the_old_ones_still_win(self):
        self.assertEqual(lt.detect("Je ne sais pas ce que tu veux dans la vie"), "fr")
        self.assertEqual(lt.detect("What are you doing with all the love that you have"), "en")

    def test_a_clear_english_text_is_sure(self):
        self.assertTrue(lt.latin_sure(["What are you doing with all the love that you have"]))

    def test_a_clear_dutch_text_is_sure(self):
        self.assertTrue(lt.latin_sure(["Dit is een test van de vertaling, ik hoop dat het werkt"]))

    def test_a_short_or_nameless_line_is_not_sure(self):
        self.assertFalse(lt.latin_sure(["Hello"]))
        self.assertFalse(lt.latin_sure(["Amsterdam Centraal"]))
        self.assertFalse(lt.latin_sure([""]))

    def test_one_language_barely_ahead_is_not_sure(self):
        # "is" scores for English and Dutch alike: no clear lead, so don't act on it.
        self.assertFalse(lt.latin_sure(["is is"]))


class UnsureSource(unittest.TestCase):
    """A thin guess must never skip a translation, and must not name the wrong source."""

    def test_thin_english_guess_is_not_skipped_when_the_target_is_english(self):
        # One English-looking word: the old code reported "already in the target language".
        seen = {}
        def fake(lines, src, dst):
            seen["src"] = src
            return (["<%s>" % l for l in lines], None, 0)
        out_, called, _, _ = run({"lines": ["Amsterdam is mooi"], "to": "en", "backends": ["google"],
                                   "cache": False}, {"google": (["x"], None, 0)})
        self.assertTrue(out_["ok"])
        self.assertNotIn("skipped", out_)
        self.assertEqual(out_["from"], "auto")
        self.assertEqual(called, ["google"])

    def test_clear_english_is_still_skipped(self):
        out_, called, _, _ = run({"lines": ["What are you doing with all the love that you have"], "to": "en",
                                   "backends": ["google"], "cache": False}, {"google": (["x"], None, 0)})
        self.assertTrue(out_.get("skipped"))
        self.assertEqual(called, [])

    def test_argos_steps_aside_for_an_unknown_source(self):
        out_, called, _, _ = run({"lines": ["Amsterdam is mooi"], "to": "en", "backends": ["argos", "google"],
                                   "cache": False},
                                  {"argos": (None, "x", 0), "google": (["x"], None, 0)})
        self.assertEqual(called, ["google"])
        self.assertEqual(out_["backend"], "google")

    def test_dutch_sentence_is_translated_from_nl(self):
        out_, called, _, _ = run({"lines": ["Dit is een test van de vertaling, ik hoop dat het werkt"], "to": "en",
                                   "backends": ["google"], "cache": False}, {"google": (["x"], None, 0)})
        self.assertTrue(out_["ok"])
        self.assertEqual(out_["from"], "nl")
        self.assertEqual(called, ["google"])


class Order(unittest.TestCase):
    def test_priority_order_is_honoured(self):
        # google first in the list, and it answers → deepl is never tried.
        res, called, _, _ = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["google", "deepl"]},
            {"google": (JA, None, 0), "deepl": (JA, None, 0)})
        self.assertTrue(res["ok"])
        self.assertEqual(res["backend"], "google")
        self.assertEqual(called, ["google"])

    def test_first_failure_falls_through(self):
        res, called, _, _ = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["deepl", "google"]},
            {"deepl": (None, "no DeepL API key configured", 0),
             "google": (JA, None, 0)})
        self.assertEqual(res["backend"], "google")
        self.assertEqual(called, ["deepl", "google"])

    def test_unknown_ids_are_filtered_out(self):
        res, called, _, _ = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["bogus", "deepl"]},
            {"deepl": (JA, None, 0)})
        self.assertEqual(called, ["deepl"])

    def test_empty_list_falls_back_to_default_order(self):
        res, called, _, _ = run(
            {"lines": JA, "to": "en", "key": "k", "backends": []},
            {name: (None, "nope", 0) for name in lt.BACKEND_ORDER})
        self.assertFalse(res["ok"])
        self.assertEqual(called, lt.BACKEND_ORDER)

    def test_missing_list_falls_back_to_default_order(self):
        _, called, _, _ = run(
            {"lines": JA, "to": "en", "key": "k"},
            {name: (None, "nope", 0) for name in lt.BACKEND_ORDER})
        self.assertEqual(called, lt.BACKEND_ORDER)

    def test_all_backends_failing_is_an_error(self):
        res, _, _, _ = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["deepl", "google"]},
            {"deepl": (None, "no key", 0), "google": (None, "HTTP 429", 0)})
        self.assertFalse(res["ok"])
        self.assertIn("deepl", res["error"])
        self.assertIn("google", res["error"])


class Cache(unittest.TestCase):
    def test_default_reads_and_writes_the_cache(self):
        _, _, reads, writes = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["deepl"]},
            {"deepl": (JA, None, 0)})
        self.assertEqual(len(reads), 1)
        self.assertEqual(len(writes), 1)

    def test_cache_false_skips_read_and_write(self):
        _, _, reads, writes = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["deepl"], "cache": False},
            {"deepl": (JA, None, 0)})
        self.assertEqual(reads, [])
        self.assertEqual(writes, [])

    def test_cache_hit_short_circuits_every_backend(self):
        res, called, _, writes = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["deepl"]},
            {"deepl": (JA, None, 0)},
            cache={"ok": True, "from": "ja", "to": "en", "lines": ["a", "b"]})
        self.assertTrue(res["cached"])
        self.assertEqual(called, [])
        self.assertEqual(writes, [])

    def test_partial_failure_is_returned_but_not_cached(self):
        _, _, _, writes = run(
            {"lines": JA, "to": "en", "key": "k", "backends": ["google"]},
            {"google": (JA, None, 1)})     # one line dropped
        self.assertEqual(writes, [])


if __name__ == "__main__":
    unittest.main()
