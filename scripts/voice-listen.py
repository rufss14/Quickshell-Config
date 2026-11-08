#!/usr/bin/env python3
""""Hey Claude" — the shell's wake word and voice commands (services/VoiceAssistant.qml).

    voice-listen.py --model DIR [--model DIR …] [--wake "hey claude"] [--wake "okay claude"]
    voice-listen.py --selftest

Listens on the default microphone (pw-record, 16 kHz mono) and prints one JSON object per line:

    {"t": "ready", "ok": true, "reason": "", "unknown": []}     once: can it listen? (and wake words the model lacks)
    {"t": "wake"}                                              the wake phrase was heard
    {"t": "partial", "text": "play odo"}                       the command so far
    {"t": "level", "v": 0.12}                                  the mic level while listening (~10 a second)
    {"t": "final", "text": "play odo by ado"}                  the command, wake phrase taken off
    {"t": "timeout"}                                           woken, then nothing said
    {"t": "error", "msg": "…"}

Commands on stdin, one per line: `listen` (skip the wake word: a key or a click asked), `cancel`.

── Two recognisers, one stream ────────────────────────────────────────────────
Idle, a Vosk recogniser limited to a GRAMMAR of the wake phrases (and "[unk]" for everything else) runs
on every chunk. It decides on the FINISHED utterance only, with Vosk's per-word confidence (WAKE_CONF):
a grammar that knows nothing but "hey claude" pulls any sound towards it, and deciding on partials woke it
on music and room noise within seconds (measured 2026-10-24). On a wake it behaves like Siri (the user, 2026-10-24: it "barely listens before starting to think"):
"hey claude" OPENS it, then you say what you want. A free recogniser is fed the last RING_S of audio (so a
request said in the same breath isn't lost — it becomes the START of what's heard, never the end), then
keeps listening ACROSS Vosk's own pauses — each finished segment is added on — and the request ends only
when you've been quiet END_SILENCE_S after saying something (quiet = the mic level near the room's own
noise floor, measured while idle), or after SILENT_S of saying nothing at all, or at COMMAND_S.

── Nothing is kept ────────────────────────────────────────────────────────────
Audio goes pw-record → this process's memory → gone, as with Karaoke (scripts/karaoke.py, whose helpers
this reuses). Only the events above leave. The capture is a real PipeWire input stream, so the shell's
microphone indicator shows that something is listening — it is, the whole time it's on.
"""

import argparse
import collections
import importlib.util
import json
import os
import queue
import re
import subprocess
import sys
import time

# Karaoke's mic and Vosk helpers, loaded by path (a hyphen-free name, but one definition of each).
_spec = importlib.util.spec_from_file_location(
    "karaoke", os.path.join(os.path.dirname(os.path.abspath(__file__)), "karaoke.py"))
K = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(K)

RATE = 16000
CHUNK = 3200                 # 0.1 s of s16 mono
RING_S = 8.0                 # what's fed to the command recogniser from before the wake: the whole breath
WAKE_CONF = 0.8              # every wake word must be at least this sure
COMMAND_S = 15.0             # the longest a request may take
SILENT_S = 6.0               # woken, and nothing at all said → timeout
END_SILENCE_S = 1.4          # quiet this long after saying something → that's the request


def norm(text):
    return re.sub(r"[^a-z0-9' ]+", " ", (text or "").lower()).split()


def has_wake(text, phrases):
    """Is one of the wake phrases in `text` (word-aligned)?"""
    words = " " + " ".join(norm(text)) + " "
    return any((" " + " ".join(norm(p)) + " ") in words for p in phrases if norm(p))


def strip_wake(text, phrases):
    """The command: everything after the LAST wake phrase in `text` (it may be said twice)."""
    words = norm(text)
    cut = 0
    for p in phrases:
        pw = norm(p)
        for i in range(len(words) - len(pw) + 1):
            if pw and words[i:i + len(pw)] == pw:
                cut = max(cut, i + len(pw))
    return " ".join(words[cut:]).strip()


class Machine:
    """The listen state, fed recogniser text and "voice now" ticks — no audio in here, so it can be
    tested. Each method returns the events to emit."""

    def __init__(self, phrases, now=time.monotonic):
        self.phrases = phrases
        self.now = now
        self.state = "idle"
        self.since = 0.0
        self.last_voice = 0.0
        self.committed = ""      # finished segments of the request
        self.partial = ""        # the segment being heard
        self.heard = ""

    def wake(self):
        t = self.now()
        self.state, self.since, self.last_voice = "listening", t, t
        self.committed = self.partial = self.heard = ""
        return [{"t": "wake"}]

    def idle_result(self, words):
        """A FINISHED grammar result while idle: [{"word", "conf"}]. Wakes when a wake phrase is in it,
        every one of its words at least WAKE_CONF sure."""
        if self.state != "idle":
            return []
        seq = [w for w in words if w.get("word") and w["word"] != "[unk]"]
        for p in self.phrases:
            pw = norm(p)
            for i in range(len(seq) - len(pw) + 1):
                hit = seq[i:i + len(pw)]
                if [w["word"] for w in hit] == pw and all(float(w.get("conf", 0)) >= WAKE_CONF for w in hit):
                    return self.wake()
        return []

    def idle_text(self, text):
        """Plain text (no confidences) while idle — for the tests and a manual feed."""
        return self.idle_result([{"word": w, "conf": 1.0} for w in norm(text)])

    def command_text(self, text, final):
        """Free recogniser output while listening: a segment so far, or (final) a finished one, which
        is ADDED to the request rather than ending it."""
        if self.state != "listening":
            return []
        seg = strip_wake(text, self.phrases) if has_wake(text, self.phrases) else " ".join(norm(text))
        if final:
            self.committed = (self.committed + " " + seg).strip()
            self.partial = ""
        else:
            self.partial = seg
        heard = (self.committed + " " + self.partial).strip()
        if heard != self.heard:
            self.heard = heard
            self.last_voice = self.now()
            return [{"t": "partial", "text": heard}]
        return []

    def voice(self):
        """The mic is above the room's noise: someone's still talking."""
        if self.state == "listening":
            self.last_voice = self.now()

    def due(self):
        """Is the request over? "final", "timeout" or None."""
        if self.state != "listening":
            return None
        t = self.now()
        if self.heard and t - self.last_voice >= END_SILENCE_S:
            return "final"
        if not self.heard and t - self.since >= SILENT_S:
            return "timeout"
        if t - self.since >= COMMAND_S:
            return "final" if self.heard else "timeout"
        return None

    def finish(self):
        kind = self.due() or ("final" if self.heard else "timeout")
        self.state = "idle"
        return [{"t": "final", "text": self.heard}] if kind == "final" and self.heard else [{"t": "timeout"}]


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def run(models, phrases):
    exe = K.shutil.which("pw-record")
    if not exe:
        emit({"t": "ready", "ok": False, "reason": "pw-record is not installed (it ships with pipewire)", "unknown": []})
        return 2
    factory, reason = K.load_engine(models, RATE)
    if factory is None:
        emit({"t": "ready", "ok": False, "reason": reason, "unknown": []})
        return 2
    unknown = factory.oov(phrases)
    usable = [p for p in phrases if not any(w in unknown for w in norm(p))]
    if not usable:
        emit({"t": "ready", "ok": False, "unknown": unknown,
              "reason": "the speech model doesn't know the wake words (" + ", ".join(unknown) + ")"})
        return 2
    K.die_with_parent()
    wake_rec = factory(usable)
    wake_rec.SetWords(True)
    cmd_rec = None
    emit({"t": "ready", "ok": True, "reason": "", "unknown": unknown})

    commands = queue.Queue()
    K.start_control(sys.stdin, commands)
    proc = subprocess.Popen([exe, "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16",
                             "--latency", "50ms", "-"],
                            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                            preexec_fn=K.die_with_parent)
    m = Machine(usable)
    ring = collections.deque(maxlen=int(RING_S * RATE * 2 / CHUNK))
    last_level = 0.0
    floor = 0.01                 # the room's own level, learned while idle
    while True:
        chunk = K.read_exact(proc.stdout, CHUNK)
        if not chunk:
            emit({"t": "error", "msg": "the microphone stream ended"})
            return 1
        while not commands.empty():
            c = commands.get_nowait().strip()
            if c == "listen" and m.state == "idle":
                for ev in m.wake():
                    emit(ev)
                cmd_rec = factory([])
            elif c == "cancel":
                m.state = "idle"
                cmd_rec = None
        if m.state == "listening" and cmd_rec is None:
            cmd_rec = factory([])
        level = K.rms(chunk)
        if m.state == "idle":
            floor = floor * 0.97 + min(level, 0.2) * 0.03
            ring.append(chunk)
            if not wake_rec.AcceptWaveform(chunk):
                continue                    # partials don't wake (see the header)
            evs = m.idle_result(json.loads(wake_rec.Result()).get("result", []))
            if evs:
                for ev in evs:
                    emit(ev)
                # The breath the wake came in: whatever followed "hey claude" in it is the START of the
                # request (never its end) — then a fresh recogniser listens on.
                cmd_rec = factory([])
                for old in list(ring):
                    cmd_rec.AcceptWaveform(old)
                ring.clear()
                text = json.loads(cmd_rec.FinalResult()).get("text", "")
                if strip_wake(text, m.phrases):
                    for ev in m.command_text(text, True):
                        emit(ev)
                cmd_rec = factory([])
            continue
        # Listening.
        now = time.monotonic()
        if now - last_level >= 0.1:
            last_level = now
            emit({"t": "level", "v": round(level, 3)})
        if level > max(0.015, floor * 3):
            m.voice()
        done = cmd_rec.AcceptWaveform(chunk)
        res = json.loads(cmd_rec.Result() if done else cmd_rec.PartialResult())
        for ev in m.command_text(res.get("text" if done else "partial", ""), done):
            emit(ev)
        if m.due():
            # The words still in the recogniser are the request's last ones.
            for ev in m.command_text(json.loads(cmd_rec.FinalResult()).get("text", ""), True):
                emit(ev)
            for ev in m.finish():
                emit(ev)
            cmd_rec = None


def selftest():
    P = ["hey claude", "okay claude"]
    assert has_wake("hey claude play music", P) and has_wake("Okay, Claude!", P)
    assert not has_wake("they claudette", P) and not has_wake("", P)
    assert strip_wake("hey claude play odo by ado", P) == "play odo by ado"
    assert strip_wake("hey claude hey claude lights", P) == "lights"
    assert strip_wake("play something", P) == "play something"
    t = [100.0]
    m = Machine(P, now=lambda: t[0])
    assert m.idle_text("the weather") == []
    # confidence: one unsure wake word doesn't wake
    assert m.idle_result([{"word": "hey", "conf": 0.95}, {"word": "claude", "conf": 0.5}]) == []
    assert m.idle_result([{"word": "[unk]", "conf": 1}, {"word": "hey", "conf": 0.9},
                          {"word": "claude", "conf": 0.85}]) == [{"t": "wake"}]
    # Siri-like: a pause between segments does NOT end it
    assert m.command_text("play", False) == [{"t": "partial", "text": "play"}]
    assert m.command_text("play odo", True) == [{"t": "partial", "text": "play odo"}]
    t[0] += 0.8
    assert m.due() is None                                   # a short pause: still listening
    assert m.command_text("by ado", True) == [{"t": "partial", "text": "play odo by ado"}]
    t[0] += 0.5
    m.voice()                                                # still talking
    t[0] += END_SILENCE_S - 0.1
    assert m.due() is None
    t[0] += 0.2
    assert m.due() == "final"
    assert m.finish() == [{"t": "final", "text": "play odo by ado"}] and m.state == "idle"
    # woken, then nothing said → timeout after SILENT_S, not before
    m.idle_text("okay claude")
    t[0] += SILENT_S - 0.5
    assert m.due() is None
    t[0] += 1
    assert m.due() == "timeout" and m.finish() == [{"t": "timeout"}]
    # one breath: what follows the wake starts the request, and it keeps listening
    m.idle_text("hey claude")
    assert m.command_text("hey claude turn the night", True) == [{"t": "partial", "text": "turn the night"}]
    assert m.state == "listening"
    m.command_text("light on", True)
    assert m.heard == "turn the night light on"
    # talking forever → what was heard, at COMMAND_S
    t[0] += COMMAND_S + 0.1
    assert m.due() == "final"
    # a final that's only the wake phrase adds nothing and keeps listening
    m.idle_text("hey claude")
    assert m.command_text("hey claude", True) == [] and m.state == "listening"
    print("voice-listen selftest: ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--model", action="append", default=[])
    ap.add_argument("--wake", action="append", default=[])
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    if a.selftest:
        selftest()
        return 0
    phrases = [p.strip().lower() for p in a.wake if p.strip()] or ["hey claude", "okay claude"]
    return run(a.model, phrases)


if __name__ == "__main__":
    sys.exit(main())
