#!/usr/bin/env python3
"""The local AI (Ollama) for the shell's AI features — what services/LocalAi.qml asks.

    local-ai.py status [--url URL]          one JSON object: installed, running, models, gpu, packages
    local-ai.py serve  [--url URL]          start `ollama serve` detached, wait until it answers
    local-ai.py pull MODEL [--url URL]      download a model; one JSON line per progress step
    local-ai.py --selftest

── Why Ollama ─────────────────────────────────────────────────────────────────
It's in Arch's own repos, runs as a plain user process, speaks an OpenAI-shaped API that
scripts/ai-ask.py already talks, and downloads models itself. The shell's setup (FeedAssistant)
is three steps: install (the update panel, `Updates.installPackages` — the password prompt is
pacman's, not ours), start, pick a model.

── Which packages ─────────────────────────────────────────────────────────────
`ollama` runs on the CPU. With a GPU, `ollama-vulkan` (a few MB) adds the Vulkan backend, which
works on AMD, NVIDIA and Intel alike — the CUDA and ROCm builds are 0.8–1 GB and vendor-locked, so
they're left for someone who wants them. The GPU vendor is read from /sys (PCI class 0x03…),
never from a subprocess.

── `serve` is a user process ──────────────────────────────────────────────────
Started detached (its own session), models under ~/.ollama. Arch's packaged system service
(ollama.service, root, /var/lib/ollama) works too: if it's already listening, `serve` sees the
port answering and starts nothing. Only for the default local address — a remote URL is
somebody else's server.

Always exits 0; errors are JSON.
"""

import glob
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request

DEFAULT_URL = "http://localhost:11434"
NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,80}$")
VENDORS = {"0x1002": "amd", "0x10de": "nvidia", "0x8086": "intel"}


def base(url):
    """The server's root. Config.aiLocalUrl may carry ai-ask.py's /v1; status and pull don't."""
    u = (url or DEFAULT_URL).strip().rstrip("/")
    if u.endswith("/v1"):
        u = u[:-3]
    return u if u.startswith(("http://", "https://")) else DEFAULT_URL


def is_local(url):
    return re.match(r"^https?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$", base(url)) is not None


def gpu(sys_root="/sys"):
    """The display adapter's vendor ("amd" | "nvidia" | "intel" | "none"). A discrete card wins
    over an integrated Intel one."""
    found = []
    for dev in glob.glob(os.path.join(sys_root, "bus/pci/devices/*")):
        try:
            with open(os.path.join(dev, "class")) as f:
                if not f.read().strip().startswith("0x03"):
                    continue
            with open(os.path.join(dev, "vendor")) as f:
                v = VENDORS.get(f.read().strip())
            if v:
                found.append(v)
        except OSError:
            continue
    for v in ("nvidia", "amd", "intel"):
        if v in found:
            return v
    return "none"


def packages(vendor):
    return ["ollama", "ollama-vulkan"] if vendor != "none" else ["ollama"]


def _get(url, timeout=1.5):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def models(url):
    """Installed models, or None when nothing answers."""
    try:
        doc = _get(base(url) + "/api/tags")
    except (urllib.error.URLError, OSError, ValueError):
        return None
    out = []
    for m in doc.get("models") or []:
        name = m.get("name") or m.get("model") or ""
        if name:
            out.append({"name": name, "size": int(m.get("size") or 0)})
    return out


def status(url):
    vendor = gpu()
    ms = models(url)
    return {"ok": True, "installed": shutil.which("ollama") is not None, "running": ms is not None,
            "models": ms or [], "gpu": vendor, "packages": packages(vendor),
            "local": is_local(url), "url": base(url)}


def serve(url):
    if models(url) is not None:
        return {"ok": True, "running": True}
    if not is_local(url):
        return {"ok": False, "error": "the local AI address isn't this machine — start it there"}
    exe = shutil.which("ollama")
    if not exe:
        return {"ok": False, "error": "ollama isn't installed"}
    # Ollama's Vulkan backend has been opt-in (OLLAMA_VULKAN=1); set with a GPU, ignored without one.
    env = dict(os.environ)
    if gpu() != "none":
        env.setdefault("OLLAMA_VULKAN", "1")
    subprocess.Popen([exe, "serve"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, start_new_session=True, env=env)
    for _ in range(40):
        time.sleep(0.25)
        if models(url) is not None:
            return {"ok": True, "running": True}
    return {"ok": False, "error": "ollama didn't start answering"}


def emit(obj):
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def pull(url, name):
    """Ollama's streamed pull, one line per step: {"t":"progress","status","completed","total"},
    then {"t":"done"} or {"t":"error"}."""
    if not NAME.match(name or ""):
        emit({"t": "error", "error": "not a model name"})
        return
    req = urllib.request.Request(base(url) + "/api/pull", method="POST",
                                 data=json.dumps({"model": name, "stream": True}).encode(),
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            last = 0.0
            for raw in r:
                try:
                    d = json.loads(raw.decode("utf-8", "replace"))
                except ValueError:
                    continue
                if d.get("error"):
                    emit({"t": "error", "error": str(d["error"])[:200]})
                    return
                now = time.monotonic()
                # A few lines a second is plenty for a progress bar.
                if d.get("status") == "success":
                    emit({"t": "done"})
                    return
                if now - last >= 0.25 or not d.get("total"):
                    last = now
                    emit({"t": "progress", "status": d.get("status", ""),
                          "completed": int(d.get("completed") or 0), "total": int(d.get("total") or 0)})
        emit({"t": "done"})
    except (urllib.error.URLError, OSError) as e:
        emit({"t": "error", "error": "couldn't reach Ollama — " + str(getattr(e, "reason", e))[:160]})


def selftest():
    import tempfile
    assert base("") == DEFAULT_URL and base("http://localhost:11434/v1/") == DEFAULT_URL
    assert base("file:///etc") == DEFAULT_URL
    assert is_local("") and is_local("http://127.0.0.1:9000") and not is_local("https://ai.example.com")
    assert NAME.match("qwen3:4b") and NAME.match("library/llama3.2:3b") and not NAME.match("; rm -rf ~") and not NAME.match("")
    assert packages("amd") == ["ollama", "ollama-vulkan"] and packages("none") == ["ollama"]
    with tempfile.TemporaryDirectory() as t:
        def dev(n, cls, vendor):
            d = os.path.join(t, "bus/pci/devices", n)
            os.makedirs(d)
            open(os.path.join(d, "class"), "w").write(cls + "\n")
            open(os.path.join(d, "vendor"), "w").write(vendor + "\n")
        assert gpu(t) == "none"
        dev("a", "0x060400", "0x1002")          # an AMD bridge: not a display
        assert gpu(t) == "none"
        dev("b", "0x030000", "0x8086")          # Intel graphics
        assert gpu(t) == "intel"
        dev("c", "0x030000", "0x1002")          # plus an AMD card: the card wins
        assert gpu(t) == "amd"
    print("local-ai selftest: ok")


def main():
    args = sys.argv[1:]
    if "--selftest" in args:
        selftest()
        return
    url = args[args.index("--url") + 1] if "--url" in args and args.index("--url") + 1 < len(args) else ""
    cmd = args[0] if args else "status"
    if cmd == "status":
        print(json.dumps(status(url)))
    elif cmd == "serve":
        print(json.dumps(serve(url)))
    elif cmd == "pull":
        pull(url, args[1] if len(args) > 1 else "")
    else:
        print(json.dumps({"ok": False, "error": "unknown command"}))


if __name__ == "__main__":
    main()
