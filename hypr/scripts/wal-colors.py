#!/usr/bin/env python3
"""
wal-colors.py
Delegates all color writing (palette.lua) and Hyprland reloading to wal-reload.sh.
Called automatically by WallpaperPanel.qml after `wal -i` succeeds,
and from autostart.lua's hyprland.start hook on login.
"""
import os, sys, subprocess

RELOAD = os.path.expanduser("~/.config/hypr/scripts/wal-reload.sh")

if not os.path.exists(RELOAD):
    print(f"[wal-colors] reload script not found: {RELOAD}", file=sys.stderr)
    sys.exit(1)

try:
    subprocess.run([RELOAD], check=True)
    print(f"[wal-colors] ran {RELOAD}")
except subprocess.CalledProcessError as e:
    print(f"[wal-colors] reload script exited with code {e.returncode}", file=sys.stderr)
    sys.exit(e.returncode)
