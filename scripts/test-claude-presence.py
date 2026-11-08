#!/usr/bin/env python3
"""Tests for claude-presence.py. Fully mocked — safe to run any time.

    python3 scripts/test-claude-presence.py

Touches no socket, spawns no process and never talks to Discord. Every filesystem read
is redirected at a temporary directory built per test. The one thing it cannot cover is
whether Discord accepts the frames, which is what the live probe was for.
"""

import json, os, sys, tempfile, shutil, unittest
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
cp = importlib.import_module("claude-presence")


class Tmp(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="claude-presence-test-")
        self.sessions = os.path.join(self.dir, "sessions")
        self.projects = os.path.join(self.dir, "projects")
        os.makedirs(self.sessions)
        os.makedirs(self.projects)
        self._patches = [
            mock.patch.object(cp, "SESSIONS_DIR", self.sessions),
            mock.patch.object(cp, "PROJECTS_DIR", self.projects),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self):
        for p in self._patches:
            p.stop()
        shutil.rmtree(self.dir, ignore_errors=True)

    def write_session(self, pid, **kw):
        s = {"pid": pid, "sessionId": "sid-%d" % pid, "cwd": "/home/u/proj",
             "startedAt": 1700000000000, "procStart": "111", "version": "2.1.221",
             "kind": "interactive", "name": "sess-%d" % pid, "status": "idle",
             "updatedAt": 1700000001000}
        s.update(kw)
        with open(os.path.join(self.sessions, "%d.json" % pid), "w") as fh:
            json.dump(s, fh)
        return s


# ══ /proc parsing ═════════════════════════════════════════════════════════════

class ProcParsing(unittest.TestCase):
    """Field 2 of /proc/<pid>/stat is the comm in parentheses and CAN CONTAIN SPACES.
    Splitting the whole line shifts every later field; these lock that down."""

    # Fields 3..21 (state, ppid, then filler) so that starttime — field 22, index 19
    # once the parenthesised comm is stripped — lands where the parser looks for it.
    SIMPLE = "39211 (claude) S 39007 39007 39007 0 -1 4194304 " + \
             " ".join(str(i) for i in range(9, 21)) + " 808051 " + \
             " ".join(str(i) for i in range(23, 40))

    SPACED = SIMPLE.replace("(claude)", "(Web Content)")
    PARENS = SIMPLE.replace("(claude)", "(weird (name))")

    def _read(self, content):
        m = mock.mock_open(read_data=content)
        with mock.patch("builtins.open", m):
            return cp.proc_start(1), cp.parent_pid(1)

    def test_simple(self):
        self.assertEqual(self._read(self.SIMPLE), ("808051", 39007))

    def test_comm_with_space(self):
        self.assertEqual(self._read(self.SPACED), ("808051", 39007))

    def test_comm_with_parens(self):
        """rfind(')') is why a nested paren doesn't break it."""
        self.assertEqual(self._read(self.PARENS), ("808051", 39007))

    def test_missing_process(self):
        with mock.patch("builtins.open", side_effect=OSError):
            self.assertIsNone(cp.proc_start(1))
            self.assertIsNone(cp.parent_pid(1))

    def test_garbage(self):
        self.assertEqual(self._read("no parens here"), (None, None))

    def test_against_real_proc(self):
        """Ground truth: the indices are asserted against this very process rather than
        against a fixture I wrote, because a fixture can be miscounted in the same
        direction as the parser and agree with it while both are wrong."""
        self.assertEqual(cp.parent_pid(os.getpid()), os.getppid())
        self.assertTrue((cp.proc_start(os.getpid()) or "").isdigit())


# ══ The registry ══════════════════════════════════════════════════════════════

class ReadSessions(Tmp):
    def test_live_session_is_kept(self):
        self.write_session(100)
        with mock.patch.object(cp, "proc_start", return_value="111"):
            got = cp.read_sessions()
        self.assertEqual([s["pid"] for s in got], [100])

    def test_dead_pid_is_dropped(self):
        self.write_session(100)
        with mock.patch.object(cp, "proc_start", return_value=None):
            self.assertEqual(cp.read_sessions(), [])

    def test_recycled_pid_is_dropped(self):
        """Same pid, different start time — a stale file about a session that ended."""
        self.write_session(100, procStart="111")
        with mock.patch.object(cp, "proc_start", return_value="999"):
            self.assertEqual(cp.read_sessions(), [])

    def test_non_interactive_is_dropped(self):
        self.write_session(100, kind="print")
        with mock.patch.object(cp, "proc_start", return_value="111"):
            self.assertEqual(cp.read_sessions(), [])

    def test_sorted_newest_first(self):
        self.write_session(1, updatedAt=10)
        self.write_session(2, updatedAt=30)
        self.write_session(3, updatedAt=20)
        with mock.patch.object(cp, "proc_start", return_value="111"):
            got = cp.read_sessions()
        self.assertEqual([s["pid"] for s in got], [2, 3, 1])

    def test_corrupt_file_is_skipped_not_fatal(self):
        self.write_session(1)
        with open(os.path.join(self.sessions, "2.json"), "w") as fh:
            fh.write("{not json")
        with mock.patch.object(cp, "proc_start", return_value="111"):
            got = cp.read_sessions()
        self.assertEqual([s["pid"] for s in got], [1])

    def test_missing_directory_is_empty_not_error(self):
        shutil.rmtree(self.sessions)
        self.assertEqual(cp.read_sessions(), [])


class PickSession(unittest.TestCase):
    def test_none_when_empty(self):
        self.assertIsNone(cp.pick_session([]))

    def test_busy_beats_more_recent_idle(self):
        idle = {"pid": 1, "status": "idle", "updatedAt": 99}
        busy = {"pid": 2, "status": "busy", "updatedAt": 1}
        self.assertEqual(cp.pick_session([idle, busy])["pid"], 2)

    def test_falls_back_to_first_when_none_busy(self):
        a = {"pid": 1, "status": "idle"}
        b = {"pid": 2, "status": "idle"}
        self.assertEqual(cp.pick_session([a, b])["pid"], 1)


class ProjectDir(unittest.TestCase):
    def test_munging_matches_claude_code(self):
        cases = [
            ("/home/user/.config/quicktest", "-home-user--config-quicktest"),
            ("/home/user", "-home-user"),
            ("/home/user/Projects/some-game/3.0",
             "-home-user-Projects-some-game-3-0"),
        ]
        for cwd, expected in cases:
            with self.subTest(cwd=cwd):
                self.assertEqual(os.path.basename(cp.project_dir_for(cwd)), expected)


class AiTitle(Tmp):
    def _transcript(self, cwd, sid, lines):
        d = cp.project_dir_for(cwd)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, sid + ".jsonl"), "w") as fh:
            for l in lines:
                fh.write(json.dumps(l) + "\n")

    def test_last_title_wins(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._transcript("/home/u/proj", "s1", [
            {"type": "ai-title", "aiTitle": "first"},
            {"type": "user"},
            {"type": "ai-title", "aiTitle": "second"},
        ])
        self.assertEqual(cp.ai_title(s), "second")

    def test_absent_transcript_is_empty(self):
        self.assertEqual(cp.ai_title({"sessionId": "nope", "cwd": "/home/u/proj"}), "")

    def test_no_title_yet(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._transcript("/home/u/proj", "s1", [{"type": "user"}])
        self.assertEqual(cp.ai_title(s), "")

    def test_partial_first_line_from_tail_seek_is_skipped(self):
        """Seeking into a huge file lands mid-record; that fragment must not be fatal."""
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        d = cp.project_dir_for("/home/u/proj")
        os.makedirs(d, exist_ok=True)
        path = os.path.join(d, "s1.jsonl")
        filler = json.dumps({"type": "user", "pad": "x" * 4000}) + "\n"
        with open(path, "w") as fh:
            fh.write(filler * 100)                       # > TRANSCRIPT_TAIL_BYTES
            fh.write(json.dumps({"type": "ai-title", "aiTitle": "tail"}) + "\n")
        self.assertEqual(cp.ai_title(s), "tail")

    def test_missing_fields(self):
        self.assertEqual(cp.ai_title({}), "")


# ══ The card ══════════════════════════════════════════════════════════════════

class PrettyModel(unittest.TestCase):
    def test_known_ids(self):
        cases = [
            ("claude-opus-5", "Opus 5"),
            ("claude-sonnet-5", "Sonnet 5"),
            ("claude-fable-5", "Fable 5"),
            ("claude-haiku-4-5-20251001", "Haiku 4.5"),
            ("us.anthropic.claude-sonnet-5", "Sonnet 5"),
            ("anthropic/claude-opus-5", "Opus 5"),
            ("anthropic.claude-haiku-4-5-v1:0", "Haiku 4.5"),
        ]
        for mid, expected in cases:
            with self.subTest(mid=mid):
                self.assertEqual(cp.pretty_model(mid), expected)

    def test_synthetic_is_not_a_model(self):
        """A real value in the transcript, marking CLI-injected messages. Taking it at
        face value makes the card announce a model called "<synthetic>"."""
        self.assertEqual(cp.pretty_model("<synthetic>"), "")

    def test_empty(self):
        self.assertEqual(cp.pretty_model(""), "")
        self.assertEqual(cp.pretty_model(None), "")

    def test_unknown_shape_degrades_rather_than_vanishing(self):
        """A model this doesn't recognise is likelier to be newer than it is to be a
        bug, so it should still render something."""
        self.assertEqual(cp.pretty_model("claude-newmodel-9"), "Newmodel 9")


class FmtTokens(unittest.TestCase):
    def test_values(self):
        for n, expected in [(0, ""), (-5, ""), (999, "999"), (1000, "1k"),
                            (204441, "204k"), (999499, "999k"), (1500000, "1.5M")]:
            with self.subTest(n=n):
                self.assertEqual(cp.fmt_tokens(n), expected)


class ReadTranscript(Tmp):
    def _write(self, cwd, sid, records):
        d = cp.project_dir_for(cwd)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, sid + ".jsonl"), "w") as fh:
            for r in records:
                fh.write(json.dumps(r) + "\n")

    def _assistant(self, model, ctx_read, out=100):
        return {"type": "assistant", "message": {"model": model, "usage": {
            "input_tokens": 2, "cache_read_input_tokens": ctx_read,
            "cache_creation_input_tokens": 0, "output_tokens": out}}}

    def test_model_and_context_from_last_turn(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._write("/home/u/proj", "s1", [
            self._assistant("claude-opus-5", 50000),
            self._assistant("claude-opus-5", 204439),
        ])
        got = cp.read_transcript(s)
        self.assertEqual(got["model"], "claude-opus-5")
        self.assertEqual(got["context"], 204441)

    def test_context_is_not_accumulated(self):
        """Summing every turn's cache reads gives tens of millions for a window holding
        a couple of hundred thousand — real arithmetic, meaningless number."""
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._write("/home/u/proj", "s1",
                    [self._assistant("claude-opus-5", 100000) for _ in range(20)])
        self.assertEqual(cp.read_transcript(s)["context"], 100002)

    def test_synthetic_turn_does_not_overwrite_the_real_model(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._write("/home/u/proj", "s1", [
            self._assistant("claude-opus-5", 1000),
            self._assistant("<synthetic>", 0),
        ])
        self.assertEqual(cp.read_transcript(s)["model"], "claude-opus-5")

    def test_title_and_usage_in_one_pass(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._write("/home/u/proj", "s1", [
            {"type": "ai-title", "aiTitle": "A title"},
            self._assistant("claude-sonnet-5", 3000),
        ])
        got = cp.read_transcript(s)
        self.assertEqual(got["title"], "A title")
        self.assertEqual(got["model"], "claude-sonnet-5")

    def test_no_assistant_turn_yet(self):
        s = {"sessionId": "s1", "cwd": "/home/u/proj"}
        self._write("/home/u/proj", "s1", [{"type": "user"}])
        got = cp.read_transcript(s)
        self.assertEqual((got["model"], got["context"]), ("", 0))

    def test_missing_transcript(self):
        got = cp.read_transcript({"sessionId": "nope", "cwd": "/home/u/proj"})
        self.assertEqual(got, {"title": "", "model": "", "context": 0})


class BuildActivity(unittest.TestCase):
    SESSION = {"pid": 1, "name": "RPC-implementation", "cwd": "/home/u/quicktest",
               "startedAt": 1700000000000, "version": "2.1.221", "status": "busy",
               "sessionId": "s1"}
    OPTS = {"useAiTitle": False, "showWorkspace": True, "showModel": True,
            "showTokens": True, "largeImage": "claude", "appName": "Claude Code"}
    EMPTY = {"title": "", "model": "", "context": 0}

    def test_name_overrides_the_application_name(self):
        """The card's bold line. Without this it falls back to the Discord app's own
        name, which had to be registered as "Claw'd Code" — the portal rejects
        "Claude"."""
        self.assertEqual(cp.build_activity(self.SESSION, "", self.OPTS)["name"],
                         "Claude Code")

    def test_no_name_key_when_unset(self):
        """Omitted, not empty: an empty string would blank the line rather than let
        Discord fall back to the application name."""
        opts = dict(self.OPTS, appName="")
        self.assertNotIn("name", cp.build_activity(self.SESSION, "", opts))

    def test_none_session_clears(self):
        self.assertIsNone(cp.build_activity(None, "3", self.OPTS))

    def test_details_is_session_name(self):
        a = cp.build_activity(self.SESSION, "", self.OPTS)
        self.assertEqual(a["details"], "RPC-implementation")

    def test_state_is_folder_and_workspace(self):
        a = cp.build_activity(self.SESSION, "3", self.OPTS)
        self.assertEqual(a["state"], "quicktest · workspace 3")

    def test_state_is_folder_alone_without_workspace(self):
        a = cp.build_activity(self.SESSION, "", self.OPTS)
        self.assertEqual(a["state"], "quicktest")

    def test_workspace_suppressed_by_option(self):
        opts = dict(self.OPTS, showWorkspace=False)
        self.assertEqual(cp.build_activity(self.SESSION, "3", opts)["state"], "quicktest")

    def test_named_workspace(self):
        self.assertIn("workspace chat",
                      cp.build_activity(self.SESSION, "chat", self.OPTS)["state"])

    def test_timestamp_is_seconds_not_millis(self):
        a = cp.build_activity(self.SESSION, "", self.OPTS)
        self.assertEqual(a["timestamps"]["start"], 1700000000)

    def test_asset_carries_version(self):
        a = cp.build_activity(self.SESSION, "", self.OPTS)
        self.assertEqual(a["assets"]["large_image"], "claude")
        self.assertEqual(a["assets"]["large_text"], "Claude Code 2.1.221")

    def test_no_assets_key_without_image(self):
        opts = dict(self.OPTS, largeImage="")
        self.assertNotIn("assets", cp.build_activity(self.SESSION, "", opts))

    def test_ai_title_option(self):
        opts = dict(self.OPTS, useAiTitle=True)
        a = cp.build_activity(self.SESSION, "", opts,
                              _tr={"title": "A much longer title", "model": "", "context": 0})
        self.assertEqual(a["details"], "A much longer title")

    def test_ai_title_falls_back_to_name(self):
        opts = dict(self.OPTS, useAiTitle=True)
        a = cp.build_activity(self.SESSION, "", opts, _tr=self.EMPTY)
        self.assertEqual(a["details"], "RPC-implementation")

    def test_unnamed_session_still_shows_something(self):
        s = dict(self.SESSION, name="")
        self.assertEqual(
            cp.build_activity(s, "", self.OPTS, _tr=self.EMPTY)["details"], "Claude Code")

    # ── Line two, with the model and token count in play ──────────────────────
    FULL = {"title": "", "model": "claude-opus-5", "context": 204441}

    def test_model_goes_on_line_one_after_the_session_name(self):
        a = cp.build_activity(self.SESSION, "2", self.OPTS, _tr=self.FULL)
        self.assertEqual(a["details"], "RPC-implementation · Opus 5")
        self.assertEqual(a["state"], "quicktest · ws 2 · 204k")

    def test_model_joins_the_ai_title_too(self):
        opts = dict(self.OPTS, useAiTitle=True)
        tr = dict(self.FULL, title="A generated title")
        a = cp.build_activity(self.SESSION, "", opts, _tr=tr)
        self.assertEqual(a["details"], "A generated title · Opus 5")

    def test_workspace_spelled_out_when_it_has_room(self):
        """"workspace 2" when alone, "ws 2" when sharing with the token count."""
        opts = dict(self.OPTS, showTokens=False)
        a = cp.build_activity(self.SESSION, "2", opts, _tr=self.FULL)
        self.assertEqual(a["state"], "quicktest · workspace 2")

    def test_model_off_leaves_line_one_as_the_name(self):
        opts = dict(self.OPTS, showModel=False)
        a = cp.build_activity(self.SESSION, "2", opts, _tr=self.FULL)
        self.assertEqual(a["details"], "RPC-implementation")
        self.assertEqual(a["state"], "quicktest · ws 2 · 204k")

    def test_no_stray_separator_when_parts_are_missing(self):
        """The whole reason both lines are joined from a list rather than
        concatenated."""
        a = cp.build_activity(self.SESSION, "", self.OPTS, _tr=self.EMPTY)
        self.assertEqual(a["state"], "quicktest")
        self.assertEqual(a["details"], "RPC-implementation")
        self.assertNotIn("·", a["state"])
        self.assertNotIn("·", a["details"])

    def test_synthetic_model_contributes_nothing(self):
        tr = {"title": "", "model": "<synthetic>", "context": 0}
        a = cp.build_activity(self.SESSION, "2", self.OPTS, _tr=tr)
        self.assertEqual(a["details"], "RPC-implementation")
        self.assertEqual(a["state"], "quicktest · workspace 2")

    def test_home_cwd_does_not_produce_empty_state(self):
        s = dict(self.SESSION, cwd="/")
        self.assertEqual(cp.build_activity(s, "", self.OPTS)["state"], "~")

    def test_trailing_slash_cwd(self):
        s = dict(self.SESSION, cwd="/home/u/quicktest/")
        self.assertEqual(cp.build_activity(s, "", self.OPTS)["state"], "quicktest")

    def test_long_fields_are_trimmed(self):
        s = dict(self.SESSION, name="x" * 400)
        a = cp.build_activity(s, "", self.OPTS)
        self.assertLessEqual(len(a["details"]), 128)

    def test_single_session_has_no_count_suffix(self):
        """The default session_count=1 must not print "+0 more"."""
        a = cp.build_activity(self.SESSION, "", self.OPTS)
        self.assertNotIn("more", a["state"])

    def test_other_sessions_are_appended(self):
        a = cp.build_activity(self.SESSION, "", self.OPTS, session_count=3)
        self.assertEqual(a["state"], "quicktest · +2 more")

    def test_session_count_suffix_shares_the_line(self):
        a = cp.build_activity(self.SESSION, "2", self.OPTS, _tr=self.FULL,
                               session_count=2)
        self.assertEqual(a["state"], "quicktest · ws 2 · 204k · +1 more")

    def test_session_count_suppressed_by_option(self):
        opts = dict(self.OPTS, showSessionCount=False)
        a = cp.build_activity(self.SESSION, "", opts, session_count=4)
        self.assertNotIn("more", a["state"])
        self.assertEqual(a["state"], "quicktest")


# ══ Hyprland resolution ═══════════════════════════════════════════════════════

class HyprWorkspace(unittest.TestCase):
    CLIENTS = [
        {"address": "0xaaa", "pid": 38993, "workspace": {"id": 3, "name": "3"}},
        {"address": "0xbbb", "pid": 500, "workspace": {"id": 1, "name": "1"}},
    ]

    def setUp(self):
        self.h = cp.Hypr()

    def test_walks_ancestors_to_the_terminal(self):
        """claude(39211) → bash(39007) → kitty(38993), and only kitty is a window."""
        chain = {39211: 39007, 39007: 38993, 38993: 1298}
        with mock.patch.object(self.h, "_clients", return_value=self.CLIENTS), \
             mock.patch.object(cp, "parent_pid", side_effect=lambda p: chain.get(p)):
            self.assertEqual(self.h.workspace_for(39211), "3")

    def test_unmatched_pid_is_empty(self):
        with mock.patch.object(self.h, "_clients", return_value=self.CLIENTS), \
             mock.patch.object(cp, "parent_pid", return_value=1):
            self.assertEqual(self.h.workspace_for(77777), "")

    def test_address_is_cached_across_calls(self):
        """A window's pid never changes, so the walk runs once per session."""
        chain = {39211: 38993}
        clients = mock.Mock(return_value=self.CLIENTS)
        with mock.patch.object(self.h, "_clients", clients), \
             mock.patch.object(cp, "parent_pid", side_effect=lambda p: chain.get(p, 1)):
            self.h.workspace_for(39211)
            calls_after_first = clients.call_count
            self.h.workspace_for(39211)
            self.assertEqual(clients.call_count, calls_after_first)

    def test_invalidate_refetches_workspace_but_not_address(self):
        chain = {39211: 38993}
        moved = [{"address": "0xaaa", "pid": 38993, "workspace": {"id": 7, "name": "7"}}]
        with mock.patch.object(cp, "parent_pid", side_effect=lambda p: chain.get(p, 1)):
            with mock.patch.object(self.h, "_clients", return_value=self.CLIENTS):
                self.assertEqual(self.h.workspace_for(39211), "3")
            self.h.invalidate()
            with mock.patch.object(self.h, "_clients", return_value=moved):
                self.assertEqual(self.h.workspace_for(39211), "7")

    def test_hyprctl_failure_is_empty_not_crash(self):
        with mock.patch.object(self.h, "_clients", return_value=[]):
            self.assertEqual(self.h.workspace_for(39211), "")

    def test_no_pid(self):
        self.assertEqual(self.h.workspace_for(None), "")

    def test_hop_limit(self):
        """A pathological chain must terminate rather than walk to init forever."""
        with mock.patch.object(self.h, "_clients", return_value=self.CLIENTS), \
             mock.patch.object(cp, "parent_pid", side_effect=lambda p: p + 1) as pp:
            self.assertEqual(self.h.workspace_for(1), "")
            self.assertLessEqual(pp.call_count, cp.MAX_ANCESTOR_HOPS)


# ══ Discord framing and rate limiting ═════════════════════════════════════════

class FakeSock:
    def __init__(self):
        self.sent = b""

    def sendall(self, b):
        self.sent += b

    def close(self):
        pass


def frames(buf):
    """Decode a stream of op/length/JSON frames back into objects."""
    out, i = [], 0
    while i + 8 <= len(buf):
        op, ln = int.from_bytes(buf[i:i + 4], "little"), int.from_bytes(buf[i + 4:i + 8], "little")
        out.append((op, json.loads(buf[i + 8:i + 8 + ln])))
        i += 8 + ln
    return out


class RateLimit(unittest.TestCase):
    def setUp(self):
        self.d = cp.Discord("123")
        self.d.sock = FakeSock()
        self.d.ready = True

    def test_first_update_sends(self):
        self.assertIsNone(self.d.apply({"details": "a"}))
        sent = frames(self.d.sock.sent)
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0][1]["cmd"], "SET_ACTIVITY")
        self.assertEqual(sent[0][1]["args"]["activity"]["details"], "a")

    def test_identical_update_is_not_resent(self):
        self.d.apply({"details": "a"})
        before = len(self.d.sock.sent)
        self.d.apply({"details": "a"})
        self.assertEqual(len(self.d.sock.sent), before)

    def test_rapid_change_is_held_and_returns_wait(self):
        self.d.apply({"details": "a"})
        before = len(self.d.sock.sent)
        wait = self.d.apply({"details": "b"})
        self.assertEqual(len(self.d.sock.sent), before, "second frame should be held")
        self.assertIsNotNone(wait)
        self.assertGreater(wait, 0)
        self.assertLessEqual(wait, cp.MIN_UPDATE_INTERVAL)

    def test_coalesces_to_the_newest(self):
        """Held updates must not queue — the newest payload is the one that goes."""
        self.d.apply({"details": "a"})
        self.d.apply({"details": "b"})
        self.d.apply({"details": "c"})
        self.d.last_send = 0                       # window reopens
        self.d.apply({"details": "c"})
        sent = [f[1]["args"]["activity"]["details"] for f in frames(self.d.sock.sent)]
        self.assertEqual(sent, ["a", "c"])

    def test_clear_is_sent_as_null(self):
        self.d.apply({"details": "a"})
        self.d.last_send = 0
        self.d.apply(None)
        self.assertIsNone(frames(self.d.sock.sent)[-1][1]["args"]["activity"])

    def test_nothing_sent_before_ready(self):
        self.d.ready = False
        self.assertIsNone(self.d.apply({"details": "a"}))
        self.assertEqual(self.d.sock.sent, b"")

    def test_nothing_sent_without_socket(self):
        self.d.sock = None
        self.assertIsNone(self.d.apply({"details": "a"}))


class Framing(unittest.TestCase):
    def test_handshake_shape(self):
        d = cp.Discord("9876")
        d.sock = FakeSock()
        d._send_frame(cp.OP_HANDSHAKE, {"v": 1, "client_id": d.client_id})
        op, msg = frames(d.sock.sent)[0]
        self.assertEqual(op, cp.OP_HANDSHAKE)
        self.assertEqual(msg, {"v": 1, "client_id": "9876"})

    def test_ping_is_ponged(self):
        d = cp.Discord("1")
        d.sock = FakeSock()
        body = json.dumps({"hi": 1}).encode()
        d.sock.recv = mock.Mock(side_effect=[
            struct_frame(cp.OP_PING, body), BlockingIOError()])
        d.pump()
        self.assertEqual(frames(d.sock.sent)[0][0], cp.OP_PONG)

    def test_ready_sets_connected(self):
        d = cp.Discord("1")
        d.sock = FakeSock()
        body = json.dumps({"cmd": "DISPATCH", "evt": "READY", "data": {}}).encode()
        d.sock.recv = mock.Mock(side_effect=[
            struct_frame(cp.OP_FRAME, body), BlockingIOError()])
        d.pump()
        self.assertTrue(d.ready)

    def test_error_frame_is_recorded(self):
        d = cp.Discord("1")
        d.sock = FakeSock()
        body = json.dumps({"evt": "ERROR",
                           "data": {"code": 4006, "message": "Not authenticated"}}).encode()
        d.sock.recv = mock.Mock(side_effect=[
            struct_frame(cp.OP_FRAME, body), BlockingIOError()])
        d.pump()
        self.assertIn("4006", d.error)

    def test_split_frame_is_reassembled(self):
        """A frame arriving in two reads must not be dropped or mis-parsed."""
        d = cp.Discord("1")
        d.sock = FakeSock()
        full = struct_frame(cp.OP_FRAME,
                            json.dumps({"cmd": "DISPATCH", "evt": "READY"}).encode())
        # Each pump reads until the socket would block, so the halves must be separated
        # by a BlockingIOError or the first pump swallows both and proves nothing.
        d.sock.recv = mock.Mock(side_effect=[
            full[:5], BlockingIOError(), full[5:], BlockingIOError()])
        d.pump()
        self.assertFalse(d.ready, "half a frame must not be parsed")
        d.pump()
        self.assertTrue(d.ready)


def struct_frame(op, body):
    import struct as _s
    return _s.pack("<II", op, len(body)) + body


# ══ Client id ═════════════════════════════════════════════════════════════════

class ClientId(unittest.TestCase):
    def _with(self, content):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as fh:
            fh.write(content)
            path = fh.name
        try:
            with mock.patch.object(cp, "CONFIG_PATH", path):
                return cp.load_client_id()
        finally:
            os.unlink(path)

    def test_reads_presence_key(self):
        self.assertEqual(self._with('{"presenceClientId": "555"}'), "555")

    def test_does_not_fall_back_to_voice_client_id(self):
        """The voice app has a different NAME, which is the card's title. Reusing it
        would silently label every session with the wrong application."""
        self.assertEqual(self._with('{"clientId": "111"}'), "")

    def test_missing_file_is_empty(self):
        with mock.patch.object(cp, "CONFIG_PATH", "/nonexistent/nope.json"):
            self.assertEqual(cp.load_client_id(), "")

    def test_corrupt_file_is_empty(self):
        self.assertEqual(self._with("{not json"), "")

    def test_id_in_keyring_is_found_only_when_listed(self):
        """A moved id is absent from the file and named under _keyring; the daemon asks
        the keyring for it — and only then, so no keyring means no lookup."""
        with mock.patch.object(cp.secretstore, "get", return_value="777\n") as get:
            self.assertEqual(self._with('{"_keyring": ["presenceClientId"]}'), "777")
            get.assert_called_once_with("discord-presence-client-id")
            get.reset_mock()
            self.assertEqual(self._with('{}'), "")
            get.assert_not_called()

    def test_file_value_beats_keyring(self):
        with mock.patch.object(cp.secretstore, "get", return_value="777") as get:
            self.assertEqual(self._with('{"presenceClientId": "555", '
                                        '"_keyring": ["presenceClientId"]}'), "555")
            get.assert_not_called()

    def test_numeric_id_is_stringified(self):
        self.assertEqual(self._with('{"presenceClientId": 555}'), "555")


if __name__ == "__main__":
    unittest.main(verbosity=2)
