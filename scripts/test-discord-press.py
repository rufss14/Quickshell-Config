#!/usr/bin/env python3
"""Does keystroke injection actually reach Discord? (Runs against LIVE Discord.)

Uses Ctrl+Shift+M (toggle mute) — hardcoded in Discord, harmless, and observable over
RPC — rather than the screen-share bind, which would start a real share to a real call.
Restores the original mute state at the end.
"""
import json, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # derived, not literal: this config is published
SP = os.path.dirname(os.path.abspath(__file__))

proc = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts/discord-rpc.py")],
                        stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                        stderr=subprocess.DEVNULL, text=True, bufsize=1)

state = {}
def pump(timeout=50):
    """Read state lines until one arrives (or timeout)."""
    end = time.time() + timeout
    while time.time() < end:
        line = proc.stdout.readline()
        if not line:
            return False
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("t") == "state" and m.get("connected"):
            state.clear(); state.update(m)
            return True
    return False

print("connecting (Discord queues new clients, this can take ~15s)...")
if not pump():
    print("FAIL: never got a connected state"); proc.kill(); sys.exit(1)
print("  connected. inCall=%s mute=%s" % (state["inCall"], state["mute"]))
before = state["mute"]

# ── Press, via the real helper the shell uses ────────────────────────────────
r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts/discord-press.py"),
                    "ctrl+shift+m"], capture_output=True, text=True)
print("  discord-press exit=%d stderr=%r" % (r.returncode, r.stderr.strip()[:100]))

# ── Did Discord notice? ───────────────────────────────────────────────────────
end = time.time() + 6
changed = False
while time.time() < end:
    line = proc.stdout.readline()
    if not line:
        break
    try:
        m = json.loads(line)
    except ValueError:
        continue
    if m.get("t") == "state" and m.get("mute") != before:
        changed = True
        print("\n>>> mute flipped %s -> %s : INJECTION WORKS" % (before, m["mute"]))
        break

if not changed:
    print("\n>>> mute never changed : INJECTION DID NOT REACH DISCORD")

# ── Restore ───────────────────────────────────────────────────────────────────
if changed:
    proc.stdin.write(json.dumps({"c": "mute", "v": before}) + "\n")
    proc.stdin.flush()
    time.sleep(1.5)
    print("    restored mute to %s" % before)

proc.stdin.close()
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()

