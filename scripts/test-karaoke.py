#!/usr/bin/env python3
"""
test-karaoke.py — tests for scripts/karaoke.py.

    python3 scripts/test-karaoke.py

Safe: pure functions and in-memory streams. It never opens a microphone and never
launches pw-record; the recogniser is a fake with Vosk's three-method shape.
"""
import importlib.util
import io
import json
import math
import os
import struct
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("karaoke", os.path.join(HERE, "karaoke.py"))
k = importlib.util.module_from_spec(spec)
spec.loader.exec_module(k)

passed = failed = 0


def quietly(fn, *args):
    """Run fn with the C-level stderr silenced: Vosk's library prints its own complaint about a
    directory with no model in it, and that is the thing under test here, not news."""
    saved = os.dup(2)
    with open(os.devnull, "w") as dn:
        os.dup2(dn.fileno(), 2)
        try:
            return fn(*args)
        finally:
            os.dup2(saved, 2)
            os.close(saved)



def check(name, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {name}\n   want {want!r}\n   got  {got!r}")


def close(name, got, want, tol=0.01):
    check(name, abs(got - want) <= tol, True)


FRAME = k.RATE * k.FRAME_MS // 1000          # samples a frame


def pcm(samples):
    return struct.pack("<%dh" % len(samples), *samples)


def silence(frames):
    return pcm([0] * FRAME * frames)


def tone(frames, amp=16384):
    return pcm([int(amp * math.sin(2 * math.pi * 220 * i / k.RATE)) for i in range(FRAME * frames)])


# ── Level ─────────────────────────────────────────────────────────────────────
check("rms: silence", k.rms(silence(1)), 0.0)
close("rms: a half-scale sine is about 0.354", k.rms(tone(1)), 0.5 / math.sqrt(2))
close("rms: full-scale square is 1", k.rms(pcm([32767, -32768] * 400)), 1.0, 0.001)
check("rms: nothing", k.rms(b""), 0.0)
check("rms: an odd trailing byte is dropped, not a crash", k.rms(silence(1) + b"\x01"), 0.0)

# ── read_exact ────────────────────────────────────────────────────────────────
s = io.BytesIO(b"abcdefg")
check("read_exact: a full read", k.read_exact(s, 3), b"abc")
check("read_exact: what's left at the end", k.read_exact(s, 10), b"defg")
check("read_exact: nothing after the end", k.read_exact(s, 3), b"")


# ── run: levels ───────────────────────────────────────────────────────────────
def collect(stream, recognizer=None):
    out = []
    n = k.run(stream, out.append, recognizer)
    return n, out


n, out = collect(io.BytesIO(silence(3) + tone(2)))
check("run: a message per frame", (n, len(out)), (5, 5))
check("run: all levels", {o["type"] for o in out}, {"level"})
check("run: silence then voice", [o["rms"] > 0.1 for o in out], [False, False, False, True, True])
n, out = collect(io.BytesIO(tone(1)[:-10]))
check("run: a short last frame is dropped", (n, out), (0, []))
check("run: an empty stream ends at once", collect(io.BytesIO(b""))[0], 0)


# ── run: words ────────────────────────────────────────────────────────────────
class Fake:
    """Vosk's shape: AcceptWaveform(bytes) -> bool, then Result() / PartialResult() as JSON."""
    def __init__(self, script):
        self.script = list(script)
        self.last = None

    def AcceptWaveform(self, chunk):
        self.last = self.script.pop(0)
        return self.last[0] == "final"

    def Result(self):
        return json.dumps({"text": self.last[1]})

    def PartialResult(self):
        return json.dumps({"partial": self.last[1]})


# The partial is asked for every PARTIAL_EVERY-th frame; a final is reported whenever the
# recogniser says one. (A repeated partial is said once, whatever the cadence.)
fake = Fake([("part", "we"), ("part", "we"), ("part", "we"), ("part", "we"),
             ("part", "we will"), ("part", "we will"), ("part", "we will"), ("part", "we will"),
             ("final", "we will rock"), ("final", ""), ("part", ""), ("part", "")])
n, out = collect(io.BytesIO(tone(12)), fake)
texts = [o for o in out if o["type"] == "text"]
partials = [t["text"] for t in texts if not t["final"]]
check("words: a partial is reported EVERY frame it is non-empty, repeats included (the shell needs two agreeing)",
      partials, ["we"] * 4 + ["we will"] * 4)
check("words: a final is said", [t["text"] for t in texts if t["final"]], ["we will rock"])
check("words: an empty final and an empty partial say nothing", len(texts), 9)
check("words: levels still flow with a recogniser", sum(1 for o in out if o["type"] == "level"), 12)


class Boom:
    def AcceptWaveform(self, chunk):
        raise RuntimeError("model fell over")


n, out = collect(io.BytesIO(tone(4)), Boom())
check("words: a failing recogniser reports and stops", [o["type"] for o in out], ["level", "error"])
check("words: and says why", "model fell over" in out[-1]["msg"], True)

# ── The analyzer: level in the singing band, and how periodic ─────────────────
import random
rnd = random.Random(7)


def noise(frames, amp=3000):
    return pcm([int(rnd.gauss(0, amp)) for _ in range(FRAME * frames)])


def vowel(frames, f0=196, amp=3000):
    """A voice-like signal: a fundamental and its first harmonics, 1/n."""
    return pcm([int(sum(amp / (h + 1) * math.sin(2 * math.pi * f0 * (h + 1) * i / k.RATE) for h in range(6)))
                for i in range(FRAME * frames)])


fast = k.Analyzer()
if fast.fast:
    lvl, voi = fast(tone(1))
    close("analyzer: a half-scale sine's band level is 0.354", lvl, 0.5 / math.sqrt(2), 0.01)
    check("analyzer: and it is periodic", voi > 0.9, True)
    check("analyzer: silence is level 0, voicing 0", fast(silence(1)), (0.0, 0.0))
    check("analyzer: a vowel is periodic", fast(vowel(1))[1] > 0.9, True)
    check("analyzer: a vowel at a high pitch too", fast(vowel(1, 660))[1] > 0.9, True)
    voicings = [fast(noise(1))[1] for _ in range(60)]
    check("analyzer: white noise is not (never past 0.55)", max(voicings) < 0.55, True)
    sung = struct.unpack("<%dh" % FRAME, vowel(1))
    hiss = struct.unpack("<%dh" % FRAME, noise(1, 1500))
    check("analyzer: a vowel in moderate noise stays voiced",
          fast(pcm([a + b for a, b in zip(sung, hiss)]))[1] > 0.7, True)
    # The band: a 40 Hz rumble is outside it, a 440 Hz tone is inside.
    rumble = pcm([int(12000 * math.sin(2 * math.pi * 40 * i / k.RATE)) for i in range(FRAME)])
    check("analyzer: a 40 Hz rumble is outside the singing band", fast(rumble)[0] < 0.02, True)
    check("analyzer: a short frame doesn't crash", len(fast(tone(1)[:200])), 2)
    n, out = collect(io.BytesIO(silence(2) + vowel(2)))
    check("run: levels carry voicing with numpy", all("voicing" in o for o in out), True)
    check("run: silence is not periodic, a vowel is", [o["voicing"] > 0.5 for o in out], [False, False, True, True])
else:
    print("note: numpy missing — the analyzer's fast path went untested")

plain = k.Analyzer(use_numpy=False)
check("analyzer: without numpy it is the plain level and no voicing", plain(silence(1)), (0.0, None))
close("analyzer: without numpy a sine's level is the plain rms", plain(tone(1))[0], 0.5 / math.sqrt(2), 0.01)
msgs = []
k.run(io.BytesIO(tone(2)), msgs.append, None, analyzer=plain)
check("run: without numpy a level has no voicing key", [("voicing" in m) for m in msgs], [False, False])

# ── The gain the recogniser hears ─────────────────────────────────────────────
quiet = pcm([int(500 * math.sin(2 * math.pi * 220 * i / k.RATE)) for i in range(FRAME)])      # rms ~0.011
agc = k.Agc()
heard_level = k.rms(quiet)
out = quiet
for _ in range(40):
    out = agc(quiet, heard_level)
check("agc: a faint voice is brought up", k.rms(out) > heard_level * 2, True)
check("agc: but not past the cap", agc.gain <= k.Agc.MAX_GAIN + 1e-9, True)
loud_agc = k.Agc()
loud = tone(1)
for _ in range(40):
    out2 = loud_agc(loud, k.rms(loud))
check("agc: a loud voice is left alone", out2 == loud, True)
hush = k.Agc()
for _ in range(80):
    out3 = hush(silence(1), 0.0)
check("agc: silence never raises the gain", (hush.gain, out3 == silence(1)), (1.0, True))
held = k.Agc()
for _ in range(40):
    held(quiet, heard_level)
g = held.gain
for _ in range(40):
    held(silence(1), 0.0)
check("agc: a pause keeps the gain (the singer is still there)", held.gain, g)
clip = k.Agc()
clip.gain = 6.0
big = clip(pcm([30000, -30000] * 240), 0.5)
# With a periodicity score: a quiet voice (level 0.006, far under the plain-level floor) is boosted,
# a quiet NOISE (same level, not periodic) is not.
quiet_voice = k.Agc()
for _ in range(40):
    quiet_voice(quiet, 0.006, 0.9)
check("agc: a quiet voice that the level alone could not tell from noise is boosted", quiet_voice.gain > 2, True)
quiet_noise = k.Agc()
for _ in range(40):
    quiet_noise(quiet, 0.006, 0.2)
check("agc: the same level with no periodicity (noise) is not", quiet_noise.gain, 1.0)
check("agc: too quiet to be worth boosting at all", (lambda a: [a(quiet, 0.002, 0.95) for _ in range(40)] and a.gain)(k.Agc()), 1.0)
check("agc: samples clip, they don't wrap", struct.unpack("<4h", big[:8]), (32767, -32768, 32767, -32768))
check("agc: the odd trailing byte is dropped, not a crash", len(clip(silence(1) + b"\x01", 0.5)) % 2, 0)

# The recogniser is handed the amplified audio; the level reported is the original's.
class Spy:
    def __init__(self): self.rms = []
    def AcceptWaveform(self, chunk): self.rms.append(k.rms(chunk)); return False
    def PartialResult(self): return json.dumps({"partial": ""})
    def Result(self): return json.dumps({"text": ""})
spy = Spy()
msgs = []
k.run(io.BytesIO(quiet * 30), msgs.append, spy)
check("run: the level reported is the untouched one", all(abs(m["rms"] - heard_level) < 0.003 for m in msgs), True)
check("run: the recogniser hears it louder as the gain comes up", spy.rms[-1] > spy.rms[0] * 2, True)

# ── Told what to listen for: the control channel ──────────────────────────────
import queue


class Scripted:
    """A recogniser that follows a script — one item per frame: ("part", text) or ("final", text) —
    and logs every frame it handled, so a test can see WHICH recogniser heard which frame."""
    def __init__(self, name, log, script=()):
        self.name, self.log, self.script, self.last = name, log, list(script), ("part", "")

    def AcceptWaveform(self, chunk):
        self.log.append(self.name)
        self.last = self.script.pop(0) if self.script else ("part", "")
        return self.last[0] == "final"

    def Result(self):
        return json.dumps({"text": self.last[1]})

    def PartialResult(self):
        return json.dumps({"partial": self.last[1]})


def swap_run(first_script, commands, frames=30, factory_fail=False, force_ms=None):
    """Feed `frames` frames of voice-free audio through run() with the given command queue.
    Returns (frames handled by name, messages, grammars the factory was asked for)."""
    log, built, msgs = [], [], []
    first = Scripted("A", log, first_script)

    def factory(phrases):
        built.append(list(phrases))
        if factory_fail:
            raise RuntimeError("boom")
        return Scripted("B%d" % len(built), log)
    saved = k.FORCE_MS
    if force_ms is not None:
        k.FORCE_MS = force_ms
    try:
        k.run(io.BytesIO(silence(frames)), msgs.append, first, commands=commands, factory=factory)
    finally:
        k.FORCE_MS = saved
    return log, msgs, built


def asked(*phrase_lists):
    q = queue.Queue()
    for p in phrase_lists:
        q.put({"type": "grammar", "phrases": p})
    return q


# 1. Nothing is being heard, so it swaps at once (after the first frame).
log, msgs, built = swap_run([], asked(["we will rock you", "we"]), frames=6)
check("grammar: with nothing in flight it is built at once", built, [["we will rock you", "we"]])
check("grammar: the first recogniser heard one frame, the new one the rest", log, ["A", "B1", "B1", "B1", "B1", "B1"])
check("grammar: it says so", [m for m in msgs if m["type"] == "grammar"], [{"type": "grammar", "ok": True, "phrases": 2, "forced": False, "oov": []}])

# 1b. Words the model has no word for are reported with the grammar, so the shell stops holding them against you.
class FakeModel:
    def vosk_model_find_word(self, w):
        return -1 if w in ("piroca", "yeah") else 7
check("oov: only the words the model lacks, once each, [unk] aside",
      k.unknown_words(FakeModel(), ["quero piroca yeah", "yeah", "amor", "[unk]"]), ["piroca", "yeah"])
check("oov: a model without the lookup says none rather than raising", k.unknown_words(object(), ["a b"]), [])
log, msgs, built = [], [], []
first = Scripted("A", log, [])
def oov_factory(phrases):
    built.append(list(phrases))
    return Scripted("B", log)
oov_factory.oov = lambda phrases: ["piroca"]
k.run(io.BytesIO(silence(4)), msgs.append, first, commands=asked(["quero piroca"]), factory=oov_factory)
check("oov: the grammar message carries them", [m.get("oov") for m in msgs if m["type"] == "grammar"], [["piroca"]])

# 2. A sentence in flight is never cut: the swap waits for its final result.
words_then_final = [("part", "we")] * 3 + [("part", "we will")] * 4 + [("final", "we will rock")]
log, msgs, built = swap_run(words_then_final, asked(["a"]), frames=20)
check("grammar: mid-sentence it waits (frames 1-8 are the first recogniser's)", log[:8], ["A"] * 8)
check("grammar: and swaps the frame after the final", log[8:11], ["B1", "B1", "B1"])
kinds = [m["type"] + (":final" if m.get("final") else "") for m in msgs if m["type"] in ("text", "grammar")]
check("grammar: the final is reported BEFORE the swap is", kinds[-2:], ["text:final", "grammar"])

# 3. Singing with no pause at all still gets its grammar, after FORCE_MS.
log, msgs, built = swap_run([("part", "oh")] * 100, asked(["x"]), frames=40, force_ms=300)      # 10 frames
check("grammar: with no gap it is forced in after FORCE_MS", [log.index("B1") if "B1" in log else -1], [10])
check("grammar: and says it was forced", [m.get("forced") for m in msgs if m["type"] == "grammar"], [True])

# 4. The latest command wins.
log, msgs, built = swap_run([], asked(["first"], ["second"]), frames=4)
check("grammar: two commands before a frame build one recogniser, the latest", built, [["second"]])

# 5. A grammar that can't be built leaves the old recogniser listening.
log, msgs, built = swap_run([], asked(["x"]), frames=5, factory_fail=True)
check("grammar: a failing build keeps the old recogniser", set(log), {"A"})
check("grammar: and says why", [(m["ok"], m["reason"]) for m in msgs if m["type"] == "grammar"], [(False, "boom")])

# 6. No phrases is free-form again (the factory is asked with an empty list).
log, msgs, built = swap_run([], asked([]), frames=3)
check("grammar: an empty grammar is a request for free-form", built, [[]])

# 7. quit ends the run; without a factory a grammar is ignored.
q = queue.Queue(); q.put({"type": "quit"})
check("control: quit ends it before any frame", k.run(io.BytesIO(silence(5)), [].append, None, commands=q), 0)
msgs = []
k.run(io.BytesIO(silence(3)), msgs.append, Scripted("A", []), commands=asked(["x"]), factory=None)
check("control: with no engine a grammar command does nothing", [m for m in msgs if m["type"] == "grammar"], [])

# 8. The reader: JSON lines in, junk skipped, and EOF is NOT a quit.
q = queue.Queue()
th = k.start_control(io.StringIO('{"type":"grammar","phrases":["a"]}\nnot json\n[1,2]\n{"type":"quit"}\n'), q)
th.join(2)
check("control: valid objects are queued, junk is skipped", [m["type"] for m in list(q.queue)], ["grammar", "quit"])
q = queue.Queue()
k.start_control(io.StringIO(""), q).join(2)
check("control: end of input queues nothing (it is not a quit)", q.empty(), True)

# 9. The real thing, where it is installed: a grammar recogniser builds and runs on silence.
real = "/usr/share/vosk-models/small-en-us"
if os.path.isdir(real) and k.probe()["vosk"]:
    factory, why = quietly(k.load_engine, [real])
    check("engine: the real model loads", (factory is not None, why), (True, ""))
    if factory:
        got = []
        for phrases in ([], ["we will rock you", "we", "will", "rock", "you"], ["zxqvbn"], ["don't stop believing"]):
            r = quietly(factory, phrases)
            quietly(r.AcceptWaveform, silence(3))
            got.append(True)
        check("engine: free-form, a grammar, an all-unknown grammar and an apostrophe all build and run", got, [True] * 4)
        check("engine: its own vocabulary says which words it lacks", factory.oov(["we will", "zxqvbn"]), ["zxqvbn"])
else:
    print("note: no Vosk model here — the real-engine check was skipped")

# ── load_recognizer: a reason, never a crash ──────────────────────────────────
check("model: none set", k.load_recognizer("")[0], None)
check("model: none set says so", k.load_recognizer("")[1], "no speech model set")
check("model: an empty list is none set", k.load_recognizer([])[1], "no speech model set")
check("model: empty entries are skipped", k.load_recognizer(["", ""])[1], "no speech model set")
r, why = k.load_recognizer("/definitely/not/here")
check("model: a missing directory says where it looked",
      (r, why), (None, "no speech model found (looked in /definitely/not/here)"))
r, why = k.load_recognizer(["/nope/a", "/nope/b"])
check("model: every candidate is named", why, "no speech model found (looked in /nope/a, /nope/b)")
here = os.path.dirname(os.path.abspath(__file__))


r, why = quietly(k.load_recognizer, ["/nope/a", here])
check("model: the first candidate that exists is used (then vosk or the model may still say no)",
      r is None and why != "" and "looked in" not in why, True)

# ── probe ─────────────────────────────────────────────────────────────────────
p = k.probe()
check("probe: its keys", sorted(p), ["numpy", "pwRecord", "vosk", "voskVersion"])
check("probe: booleans", (type(p["pwRecord"]), type(p["vosk"]), type(p["numpy"])), (bool, bool, bool))

# ── emit: one JSON object per line, UTF-8 kept ────────────────────────────────
buf = io.StringIO()
k.emit({"type": "text", "text": "café あ", "final": True}, buf)
check("emit: one line", buf.getvalue().count("\n"), 1)
check("emit: round-trips with non-ASCII", json.loads(buf.getvalue())["text"], "café あ")

print(f"{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
