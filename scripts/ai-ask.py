#!/usr/bin/env python3
"""Ask a configured AI provider one question, for the launcher's `?` mode.

Reads one JSON object on stdin, writes one on stdout, always exits 0:

    in   {"messages": [{"role":"user","text":"…"},{"role":"model","text":"…"}],
          "provider": "gemini", "model": "", "maxTokens": 600}
    out  {"ok": true, "provider": "gemini", "model": "…", "answer": "…"}
    out  {"ok": false, "error": "no API key for gemini"}

── THIS SENDS THE PROMPT TO A THIRD PARTY ────────────────────────────────────
Worth being plain about, because this config is published and someone else's machine
will run it. Whatever is typed after `?` goes to the configured provider along with
your API key. The launcher only ever runs this on an explicit Enter, never as you
type, and nothing is cached to disk — a file of everything you asked is exactly what
a launcher should not quietly accumulate.

On Gemini's FREE tier specifically, Google's terms have allowed using submitted
prompts to improve their products. The paid tier does not. That is a reason to think
about what you type here, not a bug in this script.

── The thread lives in MEMORY only ───────────────────────────────────────────
A conversation is sent so follow-ups make sense ("and why is it red at sunset?"), and
the whole thread goes to the provider on every turn — that is how these APIs work,
there is no server-side memory being used here.

It is never written to disk. services/Ai.qml holds it for as long as the launcher is
open and drops it when it closes, so nothing accumulates a file of everything you
asked. That was the reason this started out single-shot, and it still is: what changed
is the thread's lifetime, not whether one is stored.

── Keys come from ai-credentials.py, never from argv or the config ───────────
See that file's header. The key is read out of a 0600 file in-process here; it is
never an argument, never an environment variable we set, and never returned to QML.

── Raw HTTP, not the anthropic SDK, on purpose ───────────────────────────────
One code path talks to four providers, and the stdlib covers all four. Pulling in
`anthropic` (or three vendor SDKs) would put pip dependencies into a shell config that
currently needs nothing but python3 — for four ~10-line request builders. If this ever
grows past that, the SDK is the right call and this note is the reason it was not.

Adding a provider is one function and one PROVIDERS entry. `openai` and `xai` already
share one, because xAI's API is OpenAI-shaped down to the field names.
"""

import datetime
import importlib.util
import json
import os
import subprocess
import sys
import uuid
import urllib.error
import urllib.request

# ── Reading the key from ai-credentials.py, which cannot be imported by name ──
# The filename is hyphenated (house style, matching discord-credentials.py) and a
# hyphen is not valid in a module name. Loading it by PATH rather than copying its
# five-line reader here keeps ONE definition of where the key file lives — a second
# copy of that path is a second thing to get wrong the day it moves.
def _load_credentials():
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        "ai-credentials.py")
    spec = importlib.util.spec_from_file_location("ai_credentials", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


key_for = _load_credentials().key_for

TIMEOUT = 30

# Model names move fast — these are defaults, not promises. Config.aiModel overrides
# per provider, which is the knob to reach for when one is retired.
PROVIDERS = {
    # gemini-2.0-flash was retired and answered HTTP 404 naming its own replacement —
    # which is exactly why the HTTPError branch below digs the message out of the body
    # instead of printing the status. Take the API's word over anything hardcoded here.
    "gemini":    {"label": "Gemini",  "model": "gemini-3.6-flash"},
    "openai":    {"label": "ChatGPT", "model": "gpt-4o-mini"},
    # Exactly as published — Claude model ids are complete as-is and a date suffix
    # (claude-haiku-4-5-20251001) is NOT a valid id here.
    "anthropic": {"label": "Claude",  "model": "claude-haiku-4-5"},
    "xai":       {"label": "Grok",    "model": "grok-2-latest"},
    # Not an HTTP provider at all — see the claude_code() branch. `model` is a CLI
    # alias here, not an API model id.
    "claudecode": {"label": "Claude Pro", "model": "haiku", "effort": "low"},
    # A model on this machine, through Ollama's OpenAI-shaped endpoint — no key, nothing leaves
    # the box. `localUrl` in the request (Config.aiLocalUrl) points it elsewhere; "" = Ollama's
    # default port. The model must already be pulled (`ollama pull llama3.2`).
    "ollama":    {"label": "Local",   "model": "llama3.2"},
}

LOCAL_URL_DEFAULT = "http://localhost:11434"


def local_base():
    """The OpenAI-shaped endpoint under Config.aiLocalUrl: the server root, with or without /v1."""
    u = (LOCAL_URL or LOCAL_URL_DEFAULT).strip().rstrip("/")
    return u if u.endswith("/v1") else u + "/v1"


def local_default_model(v1):
    """No model chosen: the first one the server has (local-ai.py pulled it). "" when none."""
    try:
        with urllib.request.urlopen(v1[:-3] + "/api/tags", timeout=3) as r:
            ms = json.loads(r.read().decode("utf-8", "replace")).get("models") or []
        return (ms[0].get("name") or "") if ms else ""
    except (urllib.error.URLError, OSError, ValueError, AttributeError):
        return ""


# The overview's Ask page (STRUCTURED) asks a local model for this shape instead of fenced blocks:
# Ollama constrains the output to it (`format`), which is what makes a 4B model reliable — it can't
# ramble, think out loud or forget the block. The answer is turned back into text + ```action blocks
# (`blocks_from`), so services/assistant.js reads every provider the same way.
# ONE SHAPE PER VERB, each with its own required fields (anyOf). It used to be one loose object where
# every field was optional, and a 4B model filled the wrong ones and skipped the one that mattered —
# measured: "spotify to 125%" → {"do": "appvolume", "app": …, "target": …, "user": …} and no value.
# services/assistant.js still checks every action; this only makes a wrong shape impossible to write.
_N, _S, _B, _I = {"type": "number"}, {"type": "string"}, {"type": "boolean"}, {"type": "integer"}
_ANY = {"type": ["number", "string", "boolean"]}
_VERBS = {
    # verb: (required fields, optional fields)
    "scheme":         ({"name": _S, "background": _S, "foreground": _S, "colors": {"type": "array", "items": _S}}, {}),
    "set":            ({"key": _S, "value": _ANY}, {}),
    "action":         ({"id": _S}, {"on": _B}),
    "volume":         ({"value": _N}, {}),
    "brightness":     ({"value": _N}, {}),
    "wallpaper":      ({"pick": _S}, {}),
    "scene":          ({"pick": _S}, {}),
    "preset":         ({"name": _S}, {}),
    "play":           ({"query": _S}, {"kind": {"type": "string", "enum": ["track", "album", "playlist", "artist"]}}),
    "media":          ({"command": {"type": "string", "enum": ["play", "pause", "toggle", "next", "previous"]}}, {}),
    "open":           ({"url": _S}, {}),
    "search":         ({"query": _S}, {}),
    "workspace":      ({"id": _I}, {}),
    "launch":         ({"app": _S}, {}),
    "timer":          ({"minutes": _N}, {}),
    "remind":         ({"text": _S}, {"in": _N, "at": _S, "date": _S}),
    "todo":           ({"text": _S}, {}),
    "alarm":          ({"at": _S}, {"days": _S}),
    "window":         ({"app": _S}, {"workspace": _I, "float": _B, "fullscreen": _B, "focus": _B}),
    "output":         ({"device": _S}, {}),
    "appvolume":      ({"app": _S, "value": _N}, {}),
    "bluetooth":      ({"device": _S}, {"connect": _B}),
    "clip":           ({}, {"seconds": _I}),
    "screenshot":     ({}, {}),
    "look":           ({"workspaces": {"type": "array", "items": _I}}, {"wallpaper": _S, "scheme": _S}),
    "discord":        ({"command": {"type": "string", "enum": ["mute", "unmute", "deafen", "undeafen", "leave",
                                                                "camera", "screenshare"]}}, {}),
    "discordvolume":  ({"target": _S, "value": _N}, {}),
    "discorduser":    ({"user": _S}, {"mute": _B}),
    "discordsetting": ({"setting": {"type": "string", "enum": ["noise", "echo", "agc", "pushtotalk"]}, "on": _B}, {}),
    "findsetting":    ({"query": _S}, {}),
    "remember":       ({"fact": _S}, {}),
    "forget":         ({"fact": _S}, {}),
}


def _verb_shape(verb, req, opt):
    props = {"do": {"type": "string", "enum": [verb]}}
    props.update(req)
    props.update(opt)
    return {"type": "object", "properties": props, "required": ["do"] + list(req.keys()),
            "additionalProperties": False}


ACTION_SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string"},
        "actions": {"type": "array", "maxItems": 6,
                    "items": {"anyOf": [_verb_shape(v, r, o) for v, (r, o) in _VERBS.items()]}},
    },
    "required": ["reply", "actions"],
}


def blocks_from(content):
    """The JSON shape → the reply, then one ```action block holding the actions (if any)."""
    try:
        d = json.loads(content)
    except ValueError:
        return strip_think(content)
    if not isinstance(d, dict):
        return ""
    text = strip_think(str(d.get("reply") or ""))
    acts = [a for a in (d.get("actions") or []) if isinstance(a, dict)]
    if acts:
        text += "\n\n```action\n" + json.dumps(acts) + "\n```"
    return text


def ask_local(model, messages, max_tokens):
    """A local model through Ollama's NATIVE chat API — not its OpenAI-shaped one: only the native
    one switches thinking off (`think: false`; a "thinking" model like qwen3 otherwise spends the
    whole token budget reasoning and answers nothing — measured, 1500 tokens, empty reply), and only
    it takes a JSON schema as `format`."""
    v1 = local_base()
    root = v1[:-3]
    if not (root.startswith("http://") or root.startswith("https://")):
        return None, "the local AI address must start with http:// or https://"
    # Config.aiModel may still name another provider's model (it's shared): only a name the
    # server has, else its first. Model tags carry ":" (qwen3:4b); the clouds' ids don't here.
    name = model if model and ":" in model else (local_default_model(v1) or PROVIDERS["ollama"]["model"])
    body = {"model": name, "stream": False, "think": False,
            # Low temperature: this is picking the right action, not writing prose — a 4B model at the
            # default (0.8) chose a scheme for "light mode" and invented setting names.
            # 8k of context: the prompt carries the shell's state and its lists now (~3k tokens), and
            # Ollama's default 4k would cut the conversation's start off without a word.
            "options": {"num_predict": max_tokens, "temperature": 0.3, "num_ctx": 8192},
            "messages": [{"role": "system", "content": system_prompt()}] + to_chat(EXAMPLES) + to_chat(messages)}
    if STRUCTURED:
        body["format"] = ACTION_SCHEMA

    def post(b):
        req = urllib.request.Request(root + "/api/chat", method="POST", data=json.dumps(b).encode("utf-8"),
                                     headers={"Content-Type": "application/json"})
        # A local model on a CPU can take a while for its first token; 30 s is for clouds.
        with urllib.request.urlopen(req, timeout=180) as r:
            return json.loads(r.read().decode("utf-8", "replace"))

    try:
        try:
            doc = post(body)
        except urllib.error.HTTPError as e:
            # A model with no thinking mode may refuse the switch; ask again without it.
            if e.code == 400 and "think" in _http_detail(e).lower():
                body.pop("think")
                doc = post(body)
            else:
                raise
    except urllib.error.URLError as e:
        if isinstance(e, urllib.error.HTTPError):
            raise
        return None, "no local AI answering at " + root + " — is Ollama running?"
    content = ((doc.get("message") or {}).get("content") or "")
    return (blocks_from(content) if STRUCTURED else strip_think(content)), None


def strip_think(text):
    """A reasoning model (qwen3, deepseek-r1) writes its working in <think>…</think> first."""
    import re as _re
    return _re.sub(r"<think>[\s\S]*?</think>", "", text or "").strip()

# ── Per-request context, set by main() from the request ──────────────────────
# The overview's AI page (services/Assistant.qml) is a second caller with its own needs: its
# OWN Claude Pro session (a separate conversation from the launcher's), its own system prompt
# (the shell's action protocol, services/assistant.js) and possibly a local model's URL. Both
# are module state because the session helpers below are called from several places; main()
# sets them once, before anything runs. The session name is one of SESSIONS, never free text —
# it ends up in a file name.
SESSIONS = {"AppLauncher": "quickshell-launcher-claude-session",
            "Overview":    "quickshell-overview-claude-session"}
SYSTEM_OVERRIDE = ""
LOCAL_URL = ""
STRUCTURED = False
EXAMPLES = []     # worked example turns, before the conversation (a small model follows turns, not text)

# ── The Claude Pro path ───────────────────────────────────────────────────────
# Runs the `claude` CLI headless (-p) and reads its JSON. That matters because it
# bills against a Claude Pro/Max SUBSCRIPTION rather than API credits — the CLI uses
# whatever the user is already logged into. It is the only provider here that needs
# no API key, and the only one whose cost is already paid.
#
# ── One session, named, cleared on reboot ─────────────────────────────────────
# Claude Code session ids must be UUIDs, so "AppLauncher" is turned into a stable one
# with uuid5 — same name, same id, every time, on every machine. The marker that says
# "this session has been started" lives in $XDG_RUNTIME_DIR, which is tmpfs: it goes
# away on reboot by construction rather than by anything remembering to delete it.
# `--session-id` opens it the first time; `--resume` continues it after, which is what
# makes a follow-up in the launcher carry context.
SESSION_NAME = "AppLauncher"


def _session_generation():
    try:
        with open(_session_marker()) as f:
            return int((f.read() or "0").strip() or 0)
    except (OSError, ValueError):
        return 0


def _boot_id():
    """This boot's id. Linux mints a fresh one on every boot."""
    try:
        with open("/proc/sys/kernel/random/boot_id") as f:
            return f.read().strip()
    except OSError:
        return ""


def session_id():
    """A stable UUID for the AppLauncher session, scoped to this boot and generation.

    Claude Code session ids must be UUIDs, so the NAME is turned into one with uuid5 —
    same inputs, same id, every time.

    The boot id is in there because "clears on reboot" has to be true even though the
    session TRANSCRIPT lives on disk in ~/.claude and survives one. A marker file alone
    could not do it: after a reboot the marker is gone but the transcript is not, so the
    next question would resume yesterday's conversation. A new boot means a new id means
    a new session, with nothing to remember to delete.

    The generation is the on-demand clear: bumping it changes the id, which abandons the
    old session rather than trying to erase Claude Code's own storage.
    """
    return str(uuid.uuid5(
        uuid.NAMESPACE_DNS,
        "quickshell-launcher-%s-%s-%d" % (SESSION_NAME, _boot_id(), _session_generation())))

# Nothing that touches the machine. A launcher answer is a sentence; a model that can
# read files or run commands from a box you type into by reflex is a different and much
# larger thing to have agreed to. Web tools are off for the same reason the HTTP
# providers' grounding is a flag.
NO_TOOLS = ("Bash Edit Write Read Glob Grep WebFetch WebSearch "
            "NotebookEdit Task TodoWrite")


def _session_marker():
    rt = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(rt, SESSIONS.get(SESSION_NAME, SESSIONS["AppLauncher"]))


def claude_code_reset():
    """Start a new session next time, by bumping the generation.

    Not by deleting the marker — that only forgets which session we were in, and the
    retry below would find the old one still there and resume it. The id itself has to
    change.
    """
    # Read BEFORE opening for write. `open(path, "w")` truncates immediately, so
    # computing the next generation inside the with-block read an already-empty file,
    # got 0, and wrote 1 — every single time. Reset appeared to work and the session
    # never actually changed.
    nxt = _session_generation() + 1
    try:
        with open(_session_marker(), "w") as f:
            f.write(str(nxt) + "\n")
    except OSError:
        pass


def last_user(messages):
    """The newest thing the user actually said.

    Only the LAST user message is sent: the CLI keeps the conversation itself, so
    replaying our copy of the thread would say everything twice.
    """
    for m in reversed(messages or []):
        if m.get("role") != "model" and (m.get("text") or "").strip():
            return m["text"].strip()
    return ""


def build_claude_cmd(sid, prompt, model, effort, resuming, streaming):
    """The argv for one `claude` call. Shared by the streaming and one-shot paths so
    they cannot drift on the flags that matter (tools off, session, model, effort)."""
    cmd = ["claude", "-p",
           "--resume" if resuming else "--session-id", sid,
           "--model", model or PROVIDERS["claudecode"]["model"],
           "--disallowedTools", NO_TOOLS,
           "--disable-slash-commands"]
    if streaming:
        # --verbose is REQUIRED alongside stream-json; without it the CLI refuses the
        # combination rather than streaming quietly.
        cmd += ["--output-format", "stream-json", "--include-partial-messages",
                "--verbose"]
    else:
        cmd += ["--output-format", "json"]
    if effort:
        cmd += ["--effort", effort]
    # The caller's own instructions (the overview's action protocol) ride ON TOP of Claude
    # Code's — appended, not replacing, so the CLI's own behaviour is untouched.
    if SYSTEM_OVERRIDE:
        cmd += ["--append-system-prompt", SYSTEM_OVERRIDE]
    cmd.append(prompt)
    return cmd


def claude_code(messages, model, effort):
    """One-shot ask, for callers that do not want the stream."""
    prompt = last_user(messages)
    if not prompt:
        return None, "empty question"

    # The script owns the default, config overrides it. An existing config.json written
    # before this setting existed stores "" for it, and "" would otherwise mean "send no
    # --effort at all" — so the documented default would silently not apply to anyone
    # who had already run this shell once.
    effort = effort or PROVIDERS["claudecode"]["effort"]
    sid = session_id()

    def run(resuming):
        # cwd is the user's home, not this repo: `claude` reads CLAUDE.md from where it
        # runs, and a launcher question should not arrive with a shell config's
        # contributor guide attached to it.
        return subprocess.run(build_claude_cmd(sid, prompt, model, effort, resuming, False),
                              capture_output=True, text=True, timeout=180,
                              cwd=os.path.expanduser("~"))

    # ── Resume first, create if there is nothing to resume ────────────────────
    # Whether the session already exists is not tracked anywhere: the id is derived, so
    # the only question is whether Claude Code has a transcript for it, and asking is
    # cheaper and more reliable than remembering. Guessing wrong is a hard error either
    # way — "no conversation found" one direction, "session ID is already in use" the
    # other — so the wrong guess just flips and retries once.
    try:
        proc = run(True)
        if proc.returncode != 0:
            proc = run(False)
    except FileNotFoundError:
        return None, "claude CLI not found — install Claude Code for the Pro option"
    except subprocess.TimeoutExpired:
        return None, "claude timed out"

    if proc.returncode != 0:
        return None, (proc.stderr or proc.stdout or "claude failed").strip()[:200]

    try:
        doc = json.loads(proc.stdout)
    except ValueError:
        return None, "claude returned no JSON"

    if doc.get("is_error"):
        return None, str(doc.get("result") or "claude reported an error")[:200]

    return (doc.get("result") or "").strip(), None

# The panel is a few hundred pixels tall, so a wall of markdown is worse than useless.
#
# The DATE is in here because a model has no clock. Left to itself it answers from its
# training data and states it as current — "who is the champion", "what version is out"
# — with total confidence and no way for the reader to tell how old the answer is. One
# line fixes the confident-but-stale case; `grounding` below fixes the rest.
def system_prompt():
    if SYSTEM_OVERRIDE:
        return SYSTEM_OVERRIDE
    today = datetime.date.today().isoformat()
    return ("Today's date is " + today + ". "
            "Answer in at most 4 short sentences. Plain text only — no markdown, "
            "no bullet points, no code fences unless the answer is literally code. "
            "If something may have changed since your training data and you cannot "
            "look it up, say so rather than answering from memory.")


def _post(url, body, headers):
    req = urllib.request.Request(
        url, data=json.dumps(body).encode("utf-8"), method="POST",
        headers=dict({"Content-Type": "application/json"}, **headers))
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


# ── Response shapes ──────────────────────────────────────────────────────────
# Split out from the requests so they can be tested offline against fixed payloads;
# each returns "" rather than raising on a shape it does not recognise, so a provider
# changing its envelope degrades to "empty answer" instead of a traceback.

def parse_gemini(doc):
    for cand in (doc.get("candidates") or []):
        parts = ((cand.get("content") or {}).get("parts") or [])
        text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
        if text.strip():
            return text.strip()
    return ""


def parse_openai(doc):
    for ch in (doc.get("choices") or []):
        text = ((ch.get("message") or {}).get("content") or "")
        if text.strip():
            return text.strip()
    return ""


def parse_anthropic(doc):
    out = "".join(b.get("text", "") for b in (doc.get("content") or [])
                  if isinstance(b, dict) and b.get("type") == "text")
    return out.strip()


def to_gemini(messages):
    """Gemini calls the assistant "model"; everything else calls it "assistant"."""
    return [{"role": ("model" if m.get("role") == "model" else "user"),
             "parts": [{"text": m.get("text") or ""}]} for m in messages]


def to_chat(messages):
    """OpenAI/Anthropic shape. Both take the same role names and field."""
    return [{"role": ("assistant" if m.get("role") == "model" else "user"),
             "content": m.get("text") or ""} for m in messages]


def ask(provider, model, messages, max_tokens, grounding=False, effort=""):
    # The subscription path needs no key at all — it borrows the CLI's own login.
    if provider == "claudecode":
        return claude_code(messages, model, effort)

    if provider == "ollama":
        return ask_local(model, messages, max_tokens)

    key = key_for(provider)
    if not key:
        return None, "no API key for " + PROVIDERS.get(provider, {}).get("label", provider)

    model = model or PROVIDERS[provider]["model"]

    if provider == "gemini":
        url = ("https://generativelanguage.googleapis.com/v1beta/models/"
               + model + ":generateContent")
        body = {
            "systemInstruction": {"parts": [{"text": system_prompt()}]},
            "contents": to_gemini(messages),
            "generationConfig": {"maxOutputTokens": max_tokens},
        }
        # ── Grounding ─────────────────────────────────────────────────────────
        # Lets the model run a Google search before answering, so "what is the
        # latest X" comes back current instead of confidently reciting whatever was
        # true when it was trained. This is the actual fix for a stale answer; the
        # date in the prompt only stops it from misdating what it already knows.
        #
        # It costs a round trip and it means the QUERY reaches Google Search as well
        # as the model, which is why it is a config flag rather than always on.
        if grounding:
            body["tools"] = [{"google_search": {}}]
        doc = _post(url, body, {"x-goog-api-key": key})
        return parse_gemini(doc), None

    if provider in ("openai", "xai"):
        base = ("https://api.openai.com/v1" if provider == "openai"
                else "https://api.x.ai/v1")
        doc = _post(base + "/chat/completions", {
            "model": model,
            "max_tokens": max_tokens,
            "messages": [{"role": "system", "content": system_prompt()}] + to_chat(messages),
        }, {"Authorization": "Bearer " + key})
        return parse_openai(doc), None

    if provider == "anthropic":
        body = {
            "model": model,
            "max_tokens": max_tokens,
            "system": system_prompt(),
            "messages": to_chat(messages),
        }
        # ── effort is NOT universal, and sending it wrongly is a 400 ───────────
        # `output_config.effort` (low|medium|high|xhigh|max) is how you dial Claude's
        # thinking depth — but it is REJECTED on Haiku 4.5, which is this provider's
        # default model because it is the cheapest and a launcher answer is short.
        # So it is only sent when explicitly configured: the default asks for nothing
        # and cannot 400, and someone who sets it has chosen a model that takes it.
        # Haiku 4.5 rejects output_config.effort outright, and "low" is now the shared
        # default because the Claude Pro CLI path wants it — so a user switching from
        # Claude Pro to the API provider would 400 on every request without this. The
        # CLI accepts effort on every model; the API does not.
        if effort and "haiku" not in (model or "").lower():
            body["output_config"] = {"effort": effort}
        doc = _post("https://api.anthropic.com/v1/messages", body,
                    {"x-api-key": key, "anthropic-version": "2023-06-01"})
        return parse_anthropic(doc), None

    return None, "unknown provider: " + str(provider)


def selftest():
    assert parse_gemini({"candidates": [{"content": {"parts": [
        {"text": "the "}, {"text": "sky"}]}}]}) == "the sky"
    assert parse_gemini({}) == "" and parse_gemini({"candidates": [{}]}) == ""
    assert parse_openai({"choices": [{"message": {"content": " hi "}}]}) == "hi"
    assert parse_openai({"choices": [{}]}) == ""
    assert parse_anthropic({"content": [
        {"type": "text", "text": "a"}, {"type": "thinking", "text": "no"},
        {"type": "text", "text": "b"}]}) == "ab"
    assert parse_anthropic({}) == ""
    # An empty candidate must not shadow a later good one.
    assert parse_gemini({"candidates": [
        {"content": {"parts": [{"text": "  "}]}},
        {"content": {"parts": [{"text": "real"}]}}]}) == "real"
    thread = [{"role": "user", "text": "a"}, {"role": "model", "text": "b"},
              {"role": "user", "text": "c"}]
    g = to_gemini(thread)
    assert [m["role"] for m in g] == ["user", "model", "user"], g
    assert g[1]["parts"][0]["text"] == "b"
    c = to_chat(thread)
    assert [m["role"] for m in c] == ["user", "assistant", "user"], c
    assert c[1]["content"] == "b"
    # An unknown role must fall to "user", never be passed through — Gemini rejects
    # any role it does not know and the whole turn fails.
    assert to_gemini([{"role": "system", "text": "x"}])[0]["role"] == "user"

    # ── the stream translator ────────────────────────────────────────────────
    st = ({})
    assert translate('not json', st) == []
    assert translate(json.dumps({"type": "system", "subtype": "status",
                                 "status": "requesting"}), st) == [{"t": "thinking"}]
    # thinking is announced ONCE, not per delta
    assert translate(json.dumps({"type": "stream_event", "event": {
        "type": "content_block_delta", "delta": {"type": "thinking_delta",
                                                 "thinking": "hmm"}}}), st) == []
    # thinking text is never forwarded as answer text
    out = translate(json.dumps({"type": "stream_event", "event": {
        "type": "content_block_delta", "delta": {"type": "text_delta",
                                                 "text": "hi"}}}), st)
    assert out == [{"t": "delta", "text": "hi"}], out
    assert st["got_text"] is True
    done = translate(json.dumps({"is_error": False, "result": "hi",
                                 "total_cost_usd": 0.5, "duration_api_ms": 12}), st)
    # already streamed, so the summary must not repeat the answer
    assert done == [{"t": "done", "cost": 0.5, "ms": 12}], done

    # a reply that never streamed still surfaces, from `result`
    st2 = ({})
    out2 = translate(json.dumps({"is_error": False, "result": "whole",
                                 "total_cost_usd": 0, "duration_api_ms": 1}), st2)
    assert out2[0] == {"t": "delta", "text": "whole"}, out2
    assert out2[1]["t"] == "done"

    err = translate(json.dumps({"is_error": True, "result": "boom"}), ({}))
    assert err == [{"t": "error", "error": "boom"}], err

    # ── the per-request context ───────────────────────────────────────────────
    _context({"session": "Overview", "system": "SYS"})
    assert SESSION_NAME == "Overview" and system_prompt() == "SYS"
    assert "--append-system-prompt" in build_claude_cmd("x", "q", "", "", True, False)
    assert _session_marker().endswith("quickshell-overview-claude-session")
    _context({"session": "../../etc/passwd"})
    assert SESSION_NAME == "AppLauncher" and _session_marker().endswith("quickshell-launcher-claude-session")
    assert "--append-system-prompt" not in build_claude_cmd("x", "q", "", "", True, False)
    assert system_prompt().startswith("Today's date is")
    # The launcher's session id must not have changed shape (it would orphan its session).
    _context({})
    assert SESSION_NAME == "AppLauncher"
    assert strip_think("<think>hmm\nok</think>\n\nHello") == "Hello"
    b = blocks_from(json.dumps({"reply": "Rounder.", "actions": [{"do": "set", "key": "radiusScale", "value": 1.2}]}))
    assert b.startswith("Rounder.\n\n```action\n") and '"radiusScale"' in b and b.endswith("```"), b
    assert blocks_from(json.dumps({"reply": "Hi!", "actions": []})) == "Hi!"
    assert blocks_from("not json") == "not json"
    _context({"localUrl": "http://localhost:11434"})
    assert local_base() == "http://localhost:11434/v1"
    _context({"localUrl": "http://box:8080/v1/"})
    assert local_base() == "http://box:8080/v1"
    _context({"localUrl": "file:///etc"})
    assert ask("ollama", "", [{"role": "user", "text": "hi"}], 10)[1].startswith("the local AI address")
    _context({})

    # The local model's shapes and the shell's checker must know the same verbs: a verb only in the
    # checker can never be written by a local model; one only here is refused after it was written.
    import re as _re
    js_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "services", "assistant.js")
    with open(js_path, encoding="utf-8") as f:
        js = f.read()
    body = js[js.index("function validate("):js.index("function parseReply")]
    js_verbs = set(_re.findall(r'case "([a-z]+)":', body))
    assert js_verbs == set(_VERBS), ("verbs differ", set(_VERBS) - js_verbs, js_verbs - set(_VERBS))
    for v, (req, opt) in _VERBS.items():
        assert not set(req) & set(opt), v

    print("ai-ask selftest: ok")


# ── Streaming ────────────────────────────────────────────────────────────────
# One simplified NDJSON line per event, so QML applies deltas instead of parsing an
# agent protocol:
#
#     {"t":"thinking"}                     the model is reasoning, no text yet
#     {"t":"delta","text":"…"}             append this to the answer
#     {"t":"done","cost":0.03,"ms":1468}   finished, with what it cost
#     {"t":"error","error":"…"}
#
# The translation lives here rather than in the shell for the usual reason: it is real
# parsing of somebody else's event stream, and here it can be tested. `emit` flushes
# every line — a buffered pipe would deliver the whole "stream" at once on exit, which
# is the entire thing this exists to avoid.

def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def translate(line, state):
    """One raw CLI line -> zero or more simplified events."""
    try:
        d = json.loads(line)
    except ValueError:
        return []
    t = d.get("type")

    if t == "stream_event":
        ev = d.get("event") or {}
        if ev.get("type") == "content_block_delta":
            delta = ev.get("delta") or {}
            # `thinking_delta` is the model reasoning. It is NOT shown: it is not the
            # answer, it is often longer than the answer, and streaming it into the
            # bubble would replace the reply with its own working.
            if delta.get("type") == "text_delta" and delta.get("text"):
                state["got_text"] = True
                return [{"t": "delta", "text": delta["text"]}]
            if delta.get("type") == "thinking_delta" and not state.get("thinking_sent"):
                state["thinking_sent"] = True
                return [{"t": "thinking"}]
        return []

    if t == "system" and d.get("subtype") == "status" and not state.get("thinking_sent"):
        state["thinking_sent"] = True
        return [{"t": "thinking"}]

    # The final summary line has no "type" at all — it is recognised by carrying
    # `is_error`, which every completed run has and no event does.
    if "is_error" in d:
        if d.get("is_error"):
            return [{"t": "error", "error": str(d.get("result") or "claude failed")[:200]}]
        out = []
        # A run that produced no text_delta still has its answer in `result` — a very
        # short reply can arrive whole before the partial stream starts.
        if not state.get("got_text") and (d.get("result") or "").strip():
            out.append({"t": "delta", "text": d["result"].strip()})
        out.append({"t": "done",
                    "cost": d.get("total_cost_usd") or 0,
                    "ms": d.get("duration_api_ms") or 0})
        return out
    return []


def stream_claude_code(messages, model, effort):
    prompt = last_user(messages)
    if not prompt:
        emit({"t": "error", "error": "empty question"})
        return
    effort = effort or PROVIDERS["claudecode"]["effort"]
    sid = session_id()

    def attempt(resuming):
        return subprocess.Popen(
            build_claude_cmd(sid, prompt, model, effort, resuming, True),
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            cwd=os.path.expanduser("~"))

    for resuming in (True, False):
        try:
            proc = attempt(resuming)
        except FileNotFoundError:
            emit({"t": "error", "error": "claude CLI not found — install Claude Code"})
            return

        state = ({})
        saw_any = False
        # An error before anything else is HELD, not shown: the CLI (2026-10) answers a resume of a
        # session that doesn't exist yet with a result line, is_error, "No conversation found" — it
        # used to print nothing — and passing that on as the answer stopped the create-retry below
        # from ever running. The overview's Ask page hit it on every new thread; the launcher's `?`
        # on the first question of a boot.
        held = []
        for line in proc.stdout:
            for ev in translate(line, state):
                if ev.get("t") == "error" and not saw_any:
                    held.append(ev)
                    continue
                saw_any = True
                emit(ev)
        proc.wait()

        if saw_any:
            return
        if proc.returncode == 0 and not held:
            return
        if resuming:
            continue
        for ev in held:
            emit(ev)
        if held:
            return
        # Nothing came out and it failed: wrong resume/create guess. Flip and retry,
        # exactly as the non-streaming path does — but only once, hence the for-loop
        # over the two possibilities rather than recursion.
        if resuming:
            continue
        emit({"t": "error",
              "error": (proc.stderr.read() or "claude failed").strip()[:200]})


def _context(req):
    """Set the per-request module state (see SESSIONS) from a request."""
    global SESSION_NAME, SYSTEM_OVERRIDE, LOCAL_URL, STRUCTURED, EXAMPLES
    name = str(req.get("session") or "AppLauncher")
    SESSION_NAME = name if name in SESSIONS else "AppLauncher"
    SYSTEM_OVERRIDE = str(req.get("system") or "")[:20000]
    LOCAL_URL = str(req.get("localUrl") or "").strip()
    STRUCTURED = bool(req.get("structured"))
    ex = req.get("examples")
    EXAMPLES = [m for m in ex if isinstance(m, dict)][:40] if isinstance(ex, list) else []


def _http_detail(e):
    """An HTTPError's real reason — the body says it (bad key, quota, retired model)."""
    try:
        return json.loads(e.read().decode("utf-8", "replace")).get("error", {}).get("message", "") or e.reason
    except Exception:
        return e.reason


def main():
    if "--stream" in sys.argv:
        try:
            req = json.load(sys.stdin)
        except Exception as e:
            emit({"t": "error", "error": "bad request: %s" % e})
            return
        _context(req)
        q = (req.get("q") or "").strip()
        messages = req.get("messages") or ([{"role": "user", "text": q}] if q else [])
        provider = (req.get("provider") or "gemini").strip()

        if provider == "claudecode":
            stream_claude_code(messages, (req.get("model") or "").strip(),
                               (req.get("effort") or "").strip())
            return

        # The HTTP providers have no incremental mode here, so the whole answer is one
        # delta. The shell reveals it a character at a time either way, so it still
        # reads as typing — it just cannot start before the reply is complete.
        emit({"t": "thinking"})
        try:
            answer, err = ask(provider, (req.get("model") or "").strip(), messages,
                              int(req.get("maxTokens") or 600),
                              bool(req.get("grounding")),
                              (req.get("effort") or "").strip())
            if err:
                emit({"t": "error", "error": err})
            else:
                emit({"t": "delta", "text": answer or ""})
                emit({"t": "done", "cost": 0, "ms": 0})
        except urllib.error.HTTPError as e:
            emit({"t": "error", "error": ("HTTP %s: %s" % (e.code, _http_detail(e)))[:200]})
        except Exception as e:
            emit({"t": "error", "error": type(e).__name__ + ": " + str(e)[:160]})
        return

    if "--reset-session" in sys.argv:
        # `--reset-session Overview` resets the overview's conversation; bare = the launcher's.
        i = sys.argv.index("--reset-session")
        _context({"session": sys.argv[i + 1] if i + 1 < len(sys.argv) else ""})
        claude_code_reset()
        print(json.dumps({"ok": True}))
        return
    if "--selftest" in sys.argv:
        selftest()
        return
    try:
        req = json.load(sys.stdin)
    except Exception as e:
        print(json.dumps({"ok": False, "error": "bad request: %s" % e}))
        return

    _context(req)
    provider = (req.get("provider") or "gemini").strip()
    # A bare `q` is still accepted, as a one-turn thread — it is what the selftest and
    # any hand-run `echo … | ai-ask.py` uses, and it costs one line to keep working.
    messages = req.get("messages")
    if not isinstance(messages, list) or not messages:
        q = (req.get("q") or "").strip()
        messages = [{"role": "user", "text": q}] if q else []
    messages = [m for m in messages
                if isinstance(m, dict) and (m.get("text") or "").strip()]
    if not messages:
        print(json.dumps({"ok": False, "error": "empty question"}))
        return
    if provider not in PROVIDERS:
        print(json.dumps({"ok": False, "error": "unknown provider: " + provider}))
        return

    model = (req.get("model") or "").strip()
    try:
        answer, err = ask(provider, model, messages, int(req.get("maxTokens") or 600),
                          bool(req.get("grounding")),
                          (req.get("effort") or "").strip())
        if err:
            print(json.dumps({"ok": False, "error": err}))
            return
        print(json.dumps({"ok": True, "provider": provider,
                          "model": model or PROVIDERS[provider]["model"],
                          "answer": answer or ""}))
    except urllib.error.HTTPError as e:
        # The body carries the real reason (bad key, quota, retired model) and the
        # status alone does not — "400" on screen would send you to the wrong place.
        detail = ""
        try:
            detail = json.loads(e.read().decode("utf-8", "replace")) \
                         .get("error", {}).get("message", "")
        except Exception:
            pass
        print(json.dumps({"ok": False,
                          "error": "HTTP %s: %s" % (e.code, (detail or e.reason))[:200]}))
    except Exception as e:
        print(json.dumps({"ok": False,
                          "error": type(e).__name__ + ": " + str(e)[:160]}))


if __name__ == "__main__":
    main()
