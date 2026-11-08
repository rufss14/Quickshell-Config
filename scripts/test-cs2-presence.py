#!/usr/bin/env python3
"""Tests for cs2-presence.py. Fully mocked — safe to run any time.

    python3 scripts/test-cs2-presence.py

Binds no socket, spawns no process, talks to no Discord. Covers the payload parsing,
the card composition, and the Runner's carry-forward rules (elapsed clock resets on a
map change, K/D survives a spectator gap, a stale feed clears the card). What it can't
cover is whether Discord accepts the frames — the live probe during the build did.
"""

import os, sys, time, unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Both XDG dirs point at a temp dir BEFORE any script is imported: the credential
# scripts resolve their files through qspaths.py at import, which would otherwise move a
# real ~/.config/quicktest/discord-rpc.json into a real ~/.local/state (or read one).
import tempfile as _tf
_iso = _tf.mkdtemp(prefix="qs-test-xdg-")
os.environ["XDG_STATE_HOME"] = os.path.join(_iso, "state")
os.environ["XDG_CONFIG_HOME"] = os.path.join(_iso, "config")
import importlib
cs2 = importlib.import_module("cs2-presence")


LIVE = {
    "provider": {"steamid": "76561198000000001"},
    "map": {"name": "de_dust2", "mode": "competitive", "phase": "live",
            "team_ct": {"score": 7}, "team_t": {"score": 5}},
    "player": {"steamid": "76561198000000001", "team": "CT",
               "match_stats": {"kills": 12, "deaths": 8, "assists": 3}},
}


# ══ Pretty names ══════════════════════════════════════════════════════════════

class Pretty(unittest.TestCase):
    def test_active_duty_maps(self):
        self.assertEqual(cs2.pretty_map("de_dust2"), "Dust II")
        self.assertEqual(cs2.pretty_map("de_mirage"), "Mirage")

    def test_unknown_map_is_deprefixed_and_titled(self):
        self.assertEqual(cs2.pretty_map("de_cbble_night"), "Cbble Night")
        self.assertEqual(cs2.pretty_map("workshop_awp_lego_2"), "Awp Lego 2")

    def test_empty_map(self):
        self.assertEqual(cs2.pretty_map(""), "a map")

    def test_modes(self):
        self.assertEqual(cs2.pretty_mode("competitive"), "Competitive")
        self.assertEqual(cs2.pretty_mode("scrimcomp2v2"), "Wingman")
        self.assertEqual(cs2.pretty_mode("gungameprogressive"), "Arms Race")

    def test_unknown_mode(self):
        self.assertEqual(cs2.pretty_mode("some_new_mode"), "Some New Mode")
        self.assertEqual(cs2.pretty_mode(""), "Casual")


# ══ normalise() ═══════════════════════════════════════════════════════════════

class Normalise(unittest.TestCase):
    def test_menu_has_no_map(self):
        got = cs2.normalise({"provider": {"steamid": "1"},
                             "player": {"steamid": "1", "activity": "menu"}})
        self.assertEqual(got, {"menu": True})

    def test_live_match(self):
        got = cs2.normalise(LIVE)
        self.assertEqual(got["menu"], False)
        self.assertEqual(got["map"], "de_dust2")
        self.assertEqual((got["ct"], got["t"]), (7, 5))
        self.assertEqual((got["kills"], got["deaths"]), (12, 8))

    def test_stats_ignored_while_spectating_someone_else(self):
        """`player` follows your spectator target once you're dead, so its
        match_stats are then someone else's and must not be shown as yours."""
        spec = dict(LIVE)
        spec["player"] = {"steamid": "76561198000000999", "team": "T",
                          "match_stats": {"kills": 1, "deaths": 1}}
        got = cs2.normalise(spec)
        self.assertIsNone(got["kills"])
        self.assertIsNone(got["deaths"])
        self.assertEqual((got["ct"], got["t"]), (7, 5))   # score still comes through

    def test_missing_scores_are_none_not_zero(self):
        got = cs2.normalise({"provider": {"steamid": "1"},
                             "map": {"name": "de_nuke", "mode": "casual"},
                             "player": {"steamid": "1"}})
        self.assertIsNone(got["ct"])
        self.assertIsNone(got["t"])

    def test_non_dict_is_none(self):
        self.assertIsNone(cs2.normalise(["not", "a", "dict"]))


# ══ build_activity() ══════════════════════════════════════════════════════════

OPTS = {"showScore": True, "showKd": True, "showMode": True,
        "appName": "Counter-Strike 2", "largeImage": ""}


class Card(unittest.TestCase):
    def test_none_state_is_no_card(self):
        self.assertIsNone(cs2.build_activity(None, OPTS, 0))

    def test_menu_card(self):
        act = cs2.build_activity({"menu": True}, OPTS, 0)
        self.assertEqual(act["details"], "In the main menu")
        self.assertNotIn("state", act)

    def test_full_line(self):
        act = cs2.build_activity(cs2.normalise(LIVE), OPTS, 1700000000)
        self.assertEqual(act["details"], "Competitive · Dust II")
        self.assertEqual(act["state"], "CT 7 : 5 T · 12/8 K/D")
        self.assertEqual(act["timestamps"], {"start": 1700000000})
        self.assertEqual(act["name"], "Counter-Strike 2")

    def test_score_hidden(self):
        act = cs2.build_activity(cs2.normalise(LIVE),
                                 dict(OPTS, showScore=False), 1)
        self.assertEqual(act["state"], "12/8 K/D")

    def test_both_halves_hidden_drops_state(self):
        act = cs2.build_activity(cs2.normalise(LIVE),
                                 dict(OPTS, showScore=False, showKd=False), 1)
        self.assertNotIn("state", act)

    def test_mode_hidden(self):
        act = cs2.build_activity(cs2.normalise(LIVE),
                                 dict(OPTS, showMode=False), 1)
        self.assertEqual(act["details"], "Dust II")

    def test_warmup_overrides_the_score_line(self):
        warm = dict(LIVE)
        warm["map"] = dict(LIVE["map"], phase="warmup",
                           team_ct={"score": 0}, team_t={"score": 0})
        act = cs2.build_activity(cs2.normalise(warm), OPTS, 1)
        self.assertEqual(act["state"], "Warming up")

    def test_gameover_keeps_the_tally(self):
        over = dict(LIVE)
        over["map"] = dict(LIVE["map"], phase="gameover")
        act = cs2.build_activity(cs2.normalise(over), OPTS, 1)
        self.assertTrue(act["state"].startswith("Match over — "))
        self.assertIn("CT 7 : 5 T", act["state"])


# ══ Runner carry-forward ══════════════════════════════════════════════════════

class RunnerLogic(unittest.TestCase):
    def setUp(self):
        # Runner() opens a pipe and builds a (never-connected) Discord object. No
        # socket work happens until run(), which the tests don't call.
        with mock.patch.object(cs2, "load_gsi_config", return_value=(3000, "")):
            self.r = cs2.Runner()
        self.r.emit_state = lambda: None          # silence the state emitter
        self._feed = (None, float("inf"))
        self.r.gsi.latest = lambda: self._feed

    def tearDown(self):
        os.close(self.r.wake_r)
        os.close(self.r.wake_w)

    def feed(self, payload, age=0.0):
        self._feed = (payload, age)
        self.r.refresh()

    def test_stale_feed_clears_the_card(self):
        self.feed(LIVE, age=1.0)
        self.assertIsNotNone(self.r.activity)
        self.feed(LIVE, age=cs2.GSI_STALE_SECONDS + 5)
        self.assertIsNone(self.r.activity)

    def test_kd_survives_a_spectator_gap(self):
        self.feed(LIVE)
        self.assertEqual(self.r.activity["state"], "CT 7 : 5 T · 12/8 K/D")
        spec = dict(LIVE)
        spec["player"] = {"steamid": "76561198000000999", "team": "T"}
        self.feed(spec)
        self.assertIn("12/8 K/D", self.r.activity["state"])   # last real pair held

    def test_new_map_resets_the_clock_and_kd(self):
        self.feed(LIVE)
        started = self.r.since
        self.assertGreater(started, 0)
        self.r.since = started - 500                          # pretend the map is older
        self.feed(LIVE)
        self.assertEqual(self.r.since, started - 500)         # same map, clock untouched

        other = dict(LIVE)
        other["map"] = dict(LIVE["map"], name="de_nuke")
        other["player"] = {"steamid": "76561198000000001", "team": "T"}   # no stats yet
        self.feed(other)
        self.assertGreater(self.r.since, started - 500)       # clock restarted
        self.assertNotIn("K/D", self.r.activity["state"])     # carry was cleared

    def test_menu_then_match(self):
        self.feed({"provider": {"steamid": "1"}, "player": {"steamid": "1"}})
        self.assertEqual(self.r.activity["details"], "In the main menu")
        self.feed(LIVE)
        self.assertEqual(self.r.activity["details"], "Competitive · Dust II")


# ══ Client id default ═════════════════════════════════════════════════════════

class ClientId(unittest.TestCase):
    def test_defaults_to_valves_registered_app(self):
        with mock.patch.object(cs2, "CONFIG_PATH", "/nonexistent/none.json"):
            self.assertEqual(cs2.load_client_id(), cs2.DEFAULT_CLIENT_ID)

    def test_override_wins(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write('{"cs2PresenceClientId": "999"}')
            path = fh.name
        try:
            with mock.patch.object(cs2, "CONFIG_PATH", path):
                self.assertEqual(cs2.load_client_id(), "999")
        finally:
            os.unlink(path)

    def test_override_in_keyring(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write('{"_keyring": ["cs2PresenceClientId"]}')
            path = fh.name
        try:
            with mock.patch.object(cs2, "CONFIG_PATH", path), \
                 mock.patch.object(cs2.secretstore, "get", return_value="888"):
                self.assertEqual(cs2.load_client_id(), "888")
            with mock.patch.object(cs2, "CONFIG_PATH", path), \
                 mock.patch.object(cs2.secretstore, "get", return_value=None):
                self.assertEqual(cs2.load_client_id(), cs2.DEFAULT_CLIENT_ID)
        finally:
            os.unlink(path)

    def test_empty_override_falls_back_to_default(self):
        import tempfile
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write('{"cs2PresenceClientId": ""}')
            path = fh.name
        try:
            with mock.patch.object(cs2, "CONFIG_PATH", path):
                self.assertEqual(cs2.load_client_id(), cs2.DEFAULT_CLIENT_ID)
        finally:
            os.unlink(path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
