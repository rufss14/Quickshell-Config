#!/usr/bin/env python3
# ── test-gamemode-profile.py ─────────────────────────────────────────────────
# Tests for gamemode-profile.py. Fully mocked and SAFE TO RUN: the pure functions
# are tested on a fake sysfs tree, and the end-to-end cases run the script with
# XDG_CONFIG_HOME pointed at a throwaway dir and D-Bus pointed at nothing, so the
# real ~/.config/gamemode.ini and the running gamemoded are never touched. Same
# contract as test-generate-mangohud-config.py.
#
#   python3 scripts/test-gamemode-profile.py
#
# The points worth testing: the card is found by driver and VRAM, not by number;
# renice never asks for more than the session may use; and install/remove leave a
# hand-written gamemode.ini exactly as they found it.
# ─────────────────────────────────────────────────────────────────────────────
import importlib.util
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "gamemode-profile.py")

spec = importlib.util.spec_from_file_location("gamemode_profile", SCRIPT)
gp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gp)

PASS = 0
FAIL = 0


def check(name, ok, detail=""):
    global PASS, FAIL
    if ok:
        PASS += 1
    else:
        FAIL += 1
        print("  FAIL  %s%s" % (name, ("\n        " + detail) if detail else ""))


def fake_sysfs(cards):
    """cards: {n: (driver, has_dpm, vram_bytes)} → a sysfs root with class/drm/cardN."""
    root = tempfile.mkdtemp(prefix="qt-sysfs-")
    for n, (driver, dpm, vram) in cards.items():
        dev = os.path.join(root, "devices", "pci0000:00", "card%d" % n)
        os.makedirs(dev)
        drv = os.path.join(root, "bus", "pci", "drivers", driver)
        os.makedirs(drv, exist_ok=True)
        os.symlink(drv, os.path.join(dev, "driver"))
        if dpm:
            open(os.path.join(dev, "power_dpm_force_performance_level"), "w").write("auto\n")
        if vram is not None:
            open(os.path.join(dev, "mem_info_vram_total"), "w").write("%d\n" % vram)
        card = os.path.join(root, "class", "drm", "card%d" % n)
        os.makedirs(card)
        os.symlink(dev, os.path.join(card, "device"))
    os.makedirs(os.path.join(root, "class", "drm"), exist_ok=True)
    # A connector node, which is not a card and must be skipped by name.
    os.makedirs(os.path.join(root, "class", "drm", "card1-DP-2"), exist_ok=True)
    return root


# ── find_amd_gpu ──────────────────────────────────────────────────────────────
# This machine's shape: card0 gone (simpledrm handed over), the real GPU is card1.
check("amdgpu on card1 is card 1",
      gp.find_amd_gpu(fake_sysfs({1: ("amdgpu", True, 12 << 30)})) == 1)
check("an APU beside a dGPU picks the one with more VRAM",
      gp.find_amd_gpu(fake_sysfs({0: ("amdgpu", True, 512 << 20),
                                  1: ("amdgpu", True, 12 << 30)})) == 1)
check("…whatever order the numbers come in",
      gp.find_amd_gpu(fake_sysfs({0: ("amdgpu", True, 16 << 30),
                                  2: ("amdgpu", True, 1 << 30)})) == 0)
check("NVIDIA is not an amdgpu card",
      gp.find_amd_gpu(fake_sysfs({0: ("nvidia", True, 8 << 30)})) is None)
check("amdgpu without the DPM knob is skipped",
      gp.find_amd_gpu(fake_sysfs({0: ("amdgpu", False, 8 << 30)})) is None)
check("missing VRAM file still counts, as the smallest",
      gp.find_amd_gpu(fake_sysfs({0: ("amdgpu", True, None),
                                  1: ("i915", True, 1 << 30)})) == 0)
check("no drm directory at all",
      gp.find_amd_gpu(tempfile.mkdtemp()) is None)

# ── renice_for ────────────────────────────────────────────────────────────────
for rl, want in ((30, 10), (20, 0), (25, 5), (40, 10), (0, 0)):
    got = gp.renice_for(rl)
    check("RLIMIT_NICE %d → renice %d" % (rl, want), got == want, "got %r" % got)

# ── regions ───────────────────────────────────────────────────────────────────
r = gp.user_region(10)
check("user region is bracketed by the markers", r[0] == gp.BEGIN and r[-1] == gp.END)
check("user region asks for renice 10 and top I/O", "renice=10" in r and "ioprio=0" in r)
check("user region never holds [gpu] — gamemode ignores it there",
      "[gpu]" not in r and not any(l.startswith("gpu_device") for l in r))
check("renice 0 is not written as a key", not any(l.startswith("renice=") for l in gp.user_region(0)))
r = gp.system_region(1)
check("system region asks for the GPU on the right card",
      r[0] == gp.BEGIN and r[-1] == gp.END and "[gpu]" in r and "gpu_device=1" in r
      and "amd_performance_level=high" in r
      and "apply_gpu_optimisations=accept-responsibility" in r)

# ── install_text / remove_text ────────────────────────────────────────────────
USER = "[general]\n; my own tweak\nreaper_freq=5\n\n[filter]\nblacklist=glxgears\n"
for name, text in (("empty file", ""), ("hand-written file", USER),
                   ("file ending in blank lines", "[general]\nrenice=4\n\n\n")):
    once = gp.install_text(text, gp.user_region(10))
    check(name + ": region lands at the end", once.rstrip("\n").endswith(gp.END), repr(once[-60:]))
    check(name + ": install is idempotent", gp.install_text(once, gp.user_region(10)) == once)
    back, found = gp.remove_text(once)
    check(name + ": remove gives the original back", found and back == text,
          "want %r\n        got  %r" % (text, back))
back, found = gp.remove_text(USER)
check("remove on a file without the region changes nothing", not found and back == USER)
moved = gp.install_text("a=1\n\n" + "\n".join(gp.user_region(5)) + "\nb=2\n", gp.user_region(10))
check("a region in the middle moves to the end, keeping what followed it",
      moved.startswith("a=1\nb=2\n\n" + gp.BEGIN) and "renice=10" in moved
      and "renice=5" not in moved, repr(moved))
check("an unterminated region is replaced, not duplicated",
      gp.install_text("x=1\n\n" + gp.BEGIN + "\nrenice=3\n", gp.user_region(10)).count(gp.BEGIN) == 1)

# ── End to end, isolated ──────────────────────────────────────────────────────
def run(cfg, *args):
    env = dict(os.environ, XDG_CONFIG_HOME=cfg,
               DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent/qt-test-bus")
    return subprocess.run([sys.executable, SCRIPT] + list(args), env=env,
                          capture_output=True, text=True, timeout=20)

cfg = tempfile.mkdtemp(prefix="qt-gm-")
ini = os.path.join(cfg, "gamemode.ini")
p = run(cfg, "install")
check("install exits 0", p.returncode == 0, p.stderr)
check("install creates gamemode.ini with the region",
      os.path.exists(ini) and gp.BEGIN in open(ini).read())
p = run(cfg, "remove")
check("remove on a region-only file deletes it", p.returncode == 0 and not os.path.exists(ini))

open(ini, "w").write(USER)
run(cfg, "install")
run(cfg, "remove")
check("install + remove leaves a hand-written file byte-for-byte", open(ini).read() == USER)
check("remove with no file is a clean no-op", run(tempfile.mkdtemp(), "remove").returncode == 0)
p = run(cfg, "show")
check("show prints the region and writes nothing",
      p.returncode == 0 and gp.BEGIN in p.stdout and open(ini).read() == USER)
check("an unknown command is refused", run(cfg, "enable").returncode == 2)
if os.geteuid() != 0:
    p = run(cfg, "install", "--system")
    check("--system without root is refused, touching nothing",
          p.returncode in (3, 4) and not os.path.exists(os.path.join(cfg, "gamemode.ini.new")))

# ── The --system branch, in-process against a temp file ──────────────────────
# Root, the card and the daemon are faked on the module itself, so this exercises
# main()'s real path without writing /etc or needing sudo.
tmp_etc = os.path.join(tempfile.mkdtemp(prefix="qt-etc-"), "gamemode.ini")
saved = (gp.SYSTEM_CONF, gp.find_amd_gpu, gp.refresh_daemon, gp.os.geteuid)
gp.SYSTEM_CONF = tmp_etc
gp.find_amd_gpu = lambda sysfs="/sys": 1
gp.refresh_daemon = lambda: None
gp.os.geteuid = lambda: 0
try:
    check("system install exits 0", gp.main(["install", "--system"]) == 0)
    body = open(tmp_etc).read()
    check("system install writes the [gpu] region", "[gpu]" in body and "gpu_device=1" in body)
    check("…and never the user half", "renice" not in body)
    check("system remove deletes a region-only file",
          gp.main(["remove", "--system"]) == 0 and not os.path.exists(tmp_etc))
    gp.find_amd_gpu = lambda sysfs="/sys": None
    check("no amdgpu card → install --system refuses (3)", gp.main(["install", "--system"]) == 3)
    check("…but remove --system still works (nothing to do)", gp.main(["remove", "--system"]) == 0)
    gp.os.geteuid = lambda: 1000
    gp.find_amd_gpu = lambda sysfs="/sys": 1
    check("not root → install --system refuses (4)", gp.main(["install", "--system"]) == 4)
    check("…and wrote nothing", not os.path.exists(tmp_etc))
finally:
    gp.SYSTEM_CONF, gp.find_amd_gpu, gp.refresh_daemon, gp.os.geteuid = saved

print("gamemode-profile: %d passed, %d failed" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
