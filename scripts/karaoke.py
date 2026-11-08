#!/usr/bin/env python3
"""karaoke.py — the microphone, as levels and (optionally) the words sung, as JSON lines.

services/Karaoke.qml runs this while karaoke is on, and nothing else does. It reads the
microphone through `pw-record` (PipeWire) as raw 16 kHz mono, and prints one JSON object
per line on stdout:

    {"type":"ready","words":true,"reason":""}        once, first: can it recognise words?
    {"type":"level","rms":0.0421,"voicing":0.93}     every frame (30 ms): 0..1 each; `voicing` is
                                                     how periodic it is (absent without numpy)
    {"type":"text","text":"we will rock","final":false}   what was heard, partial or final
    {"type":"grammar","ok":true,"phrases":14,"oov":["piroca"]}   a grammar command was applied (or why not);
                                                     `oov` = words of it the model has no word for, so it can
                                                     never hear them (the shell stops holding them against you)
    {"type":"error","msg":"…"}                       then it exits non-zero

and reads one JSON object per line on stdin:

    {"type":"grammar","phrases":["we will rock you","we","will",…]}   listen for these words
    {"type":"quit"}                                                     stop

The decisions — is that a voice, did it match the lyric — are services/karaoke.js's; this
only measures and listens.

── What a frame measures ───────────────────────────────────────────────────────────
`rms` is the level in the SINGING BAND (120 Hz–3.5 kHz), not the raw level: a fan's rumble and
a mic's hiss sit outside it. `voicing` is the strength of the strongest period between 100 Hz
and 1 kHz (the normalised autocorrelation, unbiased for the window): a sung or spoken vowel,
a hum, a whistle is near 1; breath and room noise are low. A level alone cannot tell a voice
from a fan, and that was the weakness this replaced. Both come from ONE FFT per frame, which
needs numpy; without it `rms` is the plain level and `voicing` is absent (the gate then judges
level alone, as before).

── Privacy, which is the point of saying it here ───────────────────────────────────
No audio is written anywhere: it goes pw-record → this process's memory → gone. Only the
level and (with a model) the recognised text leave this process, on the pipe to the shell.
The capture is a real PipeWire input stream, so it shows in the shell's microphone
indicator and Recording list — something IS listening, and it says so.

── Told what to listen for ─────────────────────────────────────────────────────────
Measured on Vosk's small English model against free-form recognition: given the lyric words as
a grammar it recovered a line it had misheard and its words appeared 0.1–0.25 s EARLIER, and
speech outside the grammar came out as [unk] rather than as a lyric word. So the shell sends the
words of the lines around now, and this builds a fresh recogniser with them.

Two measured traps shaped how:
  • `SetGrammar` on a recogniser that is already running does not raise — it ABORTS THE PROCESS
    (Kaldi's fatal error, exit 134). It is never called here. A fresh KaldiRecognizer takes
    about 0.2 ms to build and cannot do that.
  • Swapping the recogniser mid-sentence loses the sentence (the words in flight came out as
    "zero one"). So a new grammar waits for a GAP — right after a final result, or while no
    words are being heard — and is forced in only after FORCE_MS of waiting, for singing with
    no pause at all.

── Words are optional ──────────────────────────────────────────────────────────────
Speech recognition is Vosk (`python-vosk` + a model directory). Without it, "ready" says
`words: false` and why, and the levels still flow — timing alone still works. The recogniser
runs in this loop, so a slow one delays the next level by its own time; Vosk's small models
take a few milliseconds a frame.

    karaoke.py --probe                        what's installed, as JSON, then exit
    karaoke.py [--target NODE] [--model DIR]...   run (--model repeats; the first that exists wins)
"""
import argparse
import array
import ctypes
import json
import math
import os
import queue
import shutil
import signal
import subprocess
import sys
import threading

RATE = 16000
# 30 ms, not 50: the voice gate reacts a frame after you start, so a shorter frame is a
# quicker light. Vosk takes any chunk size; its PARTIAL is asked for every PARTIAL_EVERY frames and
# reported every time (see run()). A word is taken once two partials agree on it, so this cadence is
# the lag between the recogniser hearing a word and it lighting; measured, a call costs ~0.03 ms.
FRAME_MS = 30
PARTIAL_EVERY = 1
# A new grammar waits for a gap, but not forever: singing with no pause would never get one.
FORCE_MS = 8000
# "Quiet" for the swap: no words in the hypothesis for this many frames (about 240 ms).
QUIET_FRAMES = 8

try:
    import numpy as np
except Exception:          # optional: levels still flow, just without `voicing`
    np = None


def die_with_parent():
    """The shell can be killed without cleaning up (a reload, `pkill -9`), which orphans its
    children — and this one holds the microphone open. PR_SET_PDEATHSIG (1) is the Linux
    answer and needs no supervision from either side. Best-effort."""
    try:
        ctypes.CDLL("libc.so.6", use_errno=True).prctl(1, signal.SIGTERM, 0, 0, 0)
    except Exception:
        pass


def emit(obj, out=None):
    (out or sys.stdout).write(json.dumps(obj, separators=(",", ":"), ensure_ascii=False) + "\n")
    (out or sys.stdout).flush()


def rms(chunk):
    """RMS of little-endian signed 16-bit PCM, 0..1. A half sample at the end is dropped."""
    a = array.array("h")
    a.frombytes(bytes(chunk[: len(chunk) // 2 * 2]))
    if sys.byteorder == "big":
        a.byteswap()
    if not a:
        return 0.0
    return math.sqrt(sum(x * x for x in a) / len(a)) / 32768.0


class Analyzer:
    """One frame of PCM -> (band rms 0..1, voicing 0..1 or None).

    With numpy: a Hann-windowed frame, one FFT, the band's energy by Parseval and its
    autocorrelation by Wiener–Khinchin from the SAME spectrum, the window's own
    autocorrelation divided out so a long lag isn't penalised for the taper. About 0.03 ms
    a frame. Without it: plain rms, no voicing."""

    NFFT = 1024
    BAND = (120.0, 3500.0)
    PITCH = (100.0, 1000.0)               # the periods looked for, in Hz

    def __init__(self, rate=RATE, frame_samples=None, use_numpy=True):
        self.rate = rate
        self.n = frame_samples or rate * FRAME_MS // 1000
        self.fast = bool(use_numpy and np is not None)
        if not self.fast:
            return
        N = self.NFFT
        self.win = np.hanning(self.n)
        self.win_sq = float((self.win ** 2).sum())
        spec = np.fft.rfft(self.win, N)
        hac = np.fft.irfft(spec.real ** 2 + spec.imag ** 2, N)
        self.win_ac = hac / hac[0]
        hz = rate / N
        self.mask = np.zeros(N // 2 + 1)
        self.mask[int(self.BAND[0] / hz): int(self.BAND[1] / hz) + 1] = 1.0
        self.lag_lo = max(2, int(rate / self.PITCH[1]))
        self.lag_hi = min(N // 2 - 1, int(rate / self.PITCH[0]))

    def __call__(self, chunk):
        if not self.fast:
            return rms(chunk), None
        x = np.frombuffer(bytes(chunk[: len(chunk) // 2 * 2]), dtype="<i2").astype(np.float64) / 32768.0
        if x.size == 0:
            return 0.0, 0.0
        if x.size != self.n:                       # a short or long frame: window what there is
            x = np.resize(x, self.n) if x.size > self.n else np.pad(x, (0, self.n - x.size))
        spec = np.fft.rfft(x * self.win, self.NFFT)
        band = (spec.real ** 2 + spec.imag ** 2) * self.mask
        level = math.sqrt(max(0.0, 2.0 * float(band.sum()) / (self.NFFT * self.win_sq)))
        ac = np.fft.irfft(band, self.NFFT)
        if ac[0] <= 1e-12:
            return level, 0.0
        r = ac[self.lag_lo: self.lag_hi + 1] / ac[0] / self.win_ac[self.lag_lo: self.lag_hi + 1]
        return level, float(min(1.0, max(0.0, r.max())))


class Agc:
    """Brings a quietly sung line up to a level a speech model hears well — for the RECOGNISER
    only: the levels the shell's gate reads are measured before it, untouched.

    A model given a faint voice mishears or hears nothing, and singing into a headset is often
    faint. The gain eases toward target / level (capped at MAX_GAIN), and moves ONLY while a
    voice is there: in silence it holds, so room noise is never turned up, and a pause between
    verses doesn't forget the singer. Samples clip rather than wrap.

    "A voice is there" is the PERIODICITY score when there is one (>= VOICING, and a little level),
    not the level alone: the level alone had to be high enough to tell a voice from noise, which a
    quiet headset never reaches — measured on a recording whose speech sat at 0.01–0.02, it never
    adapted. Without numpy (no voicing) it falls back to the level at FLOOR."""

    TARGET = 0.12
    MAX_GAIN = 6.0
    FLOOR = 0.01             # the level that counts as a voice when there is no periodicity score
    QUIET = 0.004            # the least level worth boosting, with one
    VOICING = 0.6

    def __init__(self):
        self.gain = 1.0
        self.level = 0.0

    def __call__(self, chunk, level, voicing=None):
        voice = (level >= self.FLOOR) if voicing is None else (level >= self.QUIET and voicing >= self.VOICING)
        if voice:
            self.level = level if self.level == 0.0 else self.level + (level - self.level) * 0.15
            want = min(self.MAX_GAIN, max(1.0, self.TARGET / max(self.level, 1e-4)))
            self.gain += (want - self.gain) * 0.1
        if self.gain <= 1.02:
            return chunk
        a = array.array("h")
        a.frombytes(bytes(chunk[: len(chunk) // 2 * 2]))
        if sys.byteorder == "big":
            a.byteswap()
        g = self.gain
        out = array.array("h", [max(-32768, min(32767, int(x * g))) for x in a])
        if sys.byteorder == "big":
            out.byteswap()
        return out.tobytes()


def read_exact(stream, n):
    """Exactly n bytes, or whatever is left at the end of the stream (b'' when it is over)."""
    buf = b""
    while len(buf) < n:
        part = stream.read(n - len(buf))
        if not part:
            break
        buf += part
    return buf


def start_control(stream, commands):
    """Read JSON-line commands from `stream` on a thread, into `commands` (a queue). End of
    input is NOT a quit: a shell that did not open our stdin gives EOF at once, and the shell
    going away is already handled (PR_SET_PDEATHSIG, and a broken stdout pipe)."""
    def pump():
        try:
            for line in stream:
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                if isinstance(msg, dict):
                    commands.put(msg)
        except Exception:
            pass
    t = threading.Thread(target=pump, daemon=True)
    t.start()
    return t


def probe():
    info = {"pwRecord": shutil.which("pw-record") is not None, "vosk": False, "voskVersion": "",
            "numpy": np is not None}
    try:
        import vosk  # noqa: F401
        info["vosk"] = True
        info["voskVersion"] = str(getattr(vosk, "__version__", ""))
    except Exception:
        pass
    return info


def make_recognizer(model, rate, phrases):
    """A recogniser listening for `phrases` (lowercase words and phrases) and [unk], or — with none —
    free-form. Always a NEW object: see the header on why `SetGrammar` is never called."""
    import vosk
    if phrases:
        return vosk.KaldiRecognizer(model, rate, json.dumps(list(phrases)[:240] + ["[unk]"], ensure_ascii=False))
    return vosk.KaldiRecognizer(model, rate)


def unknown_words(model, phrases):
    """The words of `phrases` the model's vocabulary lacks: Vosk ignores such a word in a grammar, and no
    recogniser built on the model can ever output it. Never raises (an old vosk without the lookup says none)."""
    out, seen = [], set()
    try:
        for p in phrases:
            for w in str(p).split():
                if w in seen or w == "[unk]":
                    continue
                seen.add(w)
                if model.vosk_model_find_word(w) == -1:
                    out.append(w)
    except Exception:
        return []
    return out[:400]


def load_engine(model_dirs, rate=RATE):
    """(factory, reason): `factory(phrases)` builds a recogniser. Never raises."""
    if isinstance(model_dirs, str):
        model_dirs = [model_dirs]
    model_dirs = [d for d in (model_dirs or []) if d]
    if not model_dirs:
        return None, "no speech model set"
    model_dir = next((d for d in model_dirs if os.path.isdir(d)), "")
    if not model_dir:
        return None, "no speech model found (looked in " + ", ".join(model_dirs) + ")"
    try:
        import vosk
    except Exception:
        return None, "vosk is not installed"
    try:
        vosk.SetLogLevel(-1)
        model = vosk.Model(model_dir)
    except Exception as e:
        return None, "the model would not load: " + str(e)
    def factory(phrases):
        return make_recognizer(model, rate, phrases)
    factory.oov = lambda phrases: unknown_words(model, phrases)
    return factory, ""


def load_recognizer(model_dirs, rate=RATE):
    """(recognizer, reason). `model_dirs` are candidates, best first; the first that is a
    directory is the model. Never raises: a missing piece is a reason to show, not a crash."""
    if isinstance(model_dirs, str):
        model_dirs = [model_dirs]
    model_dirs = [d for d in (model_dirs or []) if d]
    if not model_dirs:
        return None, "no speech model set"
    model_dir = next((d for d in model_dirs if os.path.isdir(d)), "")
    if not model_dir:
        return None, "no speech model found (looked in " + ", ".join(model_dirs) + ")"
    try:
        import vosk
    except Exception:
        return None, "vosk is not installed"
    try:
        vosk.SetLogLevel(-1)
        return vosk.KaldiRecognizer(vosk.Model(model_dir), rate), ""
    except Exception as e:
        return None, "the model would not load: " + str(e)


def run(stream, out, recognizer=None, rate=RATE, frame_ms=FRAME_MS, analyzer=None,
        commands=None, factory=None):
    """Frames from `stream` to `out(obj)` until it ends or a quit arrives. Returns the number of
    frames. `commands` is a queue of the shell's JSON commands; `factory(phrases)` builds a
    recogniser for a grammar command."""
    frame_bytes = rate * frame_ms // 1000 * 2
    analyzer = analyzer or Analyzer(rate, frame_bytes // 2)
    agc = Agc()
    last_partial = ""
    quiet = QUIET_FRAMES                   # a recogniser that has heard nothing yet is quiet
    pending = None                         # a grammar waiting for a gap: a list of phrases
    waited = 0
    force_frames = max(1, FORCE_MS // frame_ms)
    frames = 0
    while True:
        # What the shell has asked since the last frame. The latest grammar wins.
        while commands is not None:
            try:
                msg = commands.get_nowait()
            except queue.Empty:
                break
            if msg.get("type") == "quit":
                return frames
            if msg.get("type") == "grammar" and factory is not None:
                phrases = msg.get("phrases")
                pending = [str(p) for p in phrases] if isinstance(phrases, list) else []
                waited = 0

        chunk = read_exact(stream, frame_bytes)
        if len(chunk) < frame_bytes:
            break
        frames += 1
        level, voicing = analyzer(chunk)
        msg = {"type": "level", "rms": round(level, 5)}
        if voicing is not None:
            msg["voicing"] = round(voicing, 3)
        out(msg)

        just_final = False
        if recognizer is not None:
            try:
                if recognizer.AcceptWaveform(agc(chunk, level, voicing)):
                    text = json.loads(recognizer.Result()).get("text", "")
                    last_partial = ""
                    just_final = True
                    if text:
                        out({"type": "text", "text": text, "final": True})
                elif frames % PARTIAL_EVERY == 0:
                    partial = json.loads(recognizer.PartialResult()).get("partial", "")
                    # EVERY frame it is non-empty, even unchanged: the shell takes a word once two
                    # consecutive partials agree on it, so a de-duplicated stream never confirmed the
                    # LAST word of a line (it only changes when a next word comes) and it waited for the
                    # final result, ~0.7 s later. Found by replaying a real recording through the loop.
                    if partial:
                        out({"type": "text", "text": partial, "final": False})
                    last_partial = partial
            except Exception as e:
                out({"type": "error", "msg": "recognition failed: " + str(e)})
                return frames

        quiet = 0 if (last_partial or just_final) else quiet + 1

        if pending is not None:
            waited += 1
            gap = just_final or quiet >= QUIET_FRAMES
            if gap or waited >= force_frames:
                try:
                    recognizer = factory(pending)
                    last_partial = ""
                    quiet = QUIET_FRAMES
                    oov = getattr(factory, "oov", None)
                    out({"type": "grammar", "ok": True, "phrases": len(pending), "forced": not gap,
                         "oov": oov(pending) if oov else []})
                except Exception as e:
                    out({"type": "grammar", "ok": False, "reason": str(e)})
                pending = None
    return frames


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--target", default="", help="the PipeWire source node name; empty is the default")
    ap.add_argument("--model", action="append", default=[],
                    help="a Vosk model directory, best first; repeat for fallbacks. None is no word recognition")
    a = ap.parse_args(argv)

    if a.probe:
        emit(probe())
        return 0

    exe = shutil.which("pw-record")
    if not exe:
        emit({"type": "error", "msg": "pw-record is not installed (it ships with pipewire)"})
        return 2

    die_with_parent()
    factory, reason = load_engine(a.model)
    recognizer = None
    if factory is not None:
        try:
            recognizer = factory([])                 # free-form until the shell says what to listen for
        except Exception as e:
            factory, reason = None, "the recogniser would not start: " + str(e)
    emit({"type": "ready", "words": recognizer is not None, "grammar": factory is not None,
          "reason": reason if any(a.model) else ""})
    commands = queue.Queue()
    start_control(sys.stdin, commands)

    cmd = [exe, "--raw", "--rate", str(RATE), "--channels", "1", "--format", "s16", "--latency", "50ms"]
    if a.target:
        cmd += ["--target", a.target]
    cmd.append("-")
    try:
        # Its own stdin: ours is the shell's control channel, and pw-record must not read it.
        proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                preexec_fn=die_with_parent)
    except OSError as e:
        emit({"type": "error", "msg": "could not start pw-record: " + str(e)})
        return 2

    def stop(*_):
        proc.terminate()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    try:
        run(proc.stdout, emit, recognizer, commands=commands, factory=factory)
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except Exception:
            proc.kill()
    # The stream ended without us asking: the device went away, or PipeWire did.
    if proc.returncode not in (0, -signal.SIGTERM, None):
        emit({"type": "error", "msg": "the microphone stream ended"})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
