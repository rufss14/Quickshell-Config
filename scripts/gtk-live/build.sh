#!/usr/bin/env bash
# ── gtk-live/build.sh ────────────────────────────────────────────────────────
# Builds the live-GTK4 module (livetheme.c, read its header for what it is and why) into
# $XDG_DATA_HOME/quicktest/gio-modules/, the one directory shell-env.sh and hypr/env.lua
# point GIO_EXTRA_MODULES at.
#
#   ./scripts/gtk-live/build.sh            build + install
#   ./scripts/gtk-live/build.sh --remove   delete the module again
#
# Optional, and nothing else depends on it: without the module GTK4 apps repaint when they
# are restarted (reload-theme.sh offers the restart), exactly as before. Needs a C compiler
# and the GLib headers (Arch: base-devel + glib2, both already part of installing this shell).
#
# It only takes effect in apps STARTED with GIO_EXTRA_MODULES set, i.e. launched after the
# env is in place: apps the shell launches get it from shell-env.sh once the shell is
# restarted; apps Hyprland launches (binds, autostart) get it from hypr/env.lua after a
# re-login. Anything already open keeps what it started with.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
OUT="${XDG_DATA_HOME:-$HOME/.local/share}/quicktest/gio-modules"
SO="$OUT/libgiolivetheme.so"

if [[ "${1:-}" == "--remove" ]]; then
    rm -f -- "$SO"
    rmdir -- "$OUT" 2>/dev/null || true
    echo "removed $SO"
    exit 0
fi

command -v gcc >/dev/null          || { echo "gtk-live: gcc not found (Arch: base-devel)" >&2; exit 1; }
pkg-config --exists gio-2.0        || { echo "gtk-live: GLib headers not found (Arch: glib2, pkgconf)" >&2; exit 1; }

mkdir -p "$OUT"
# Build beside the target and rename in: an app starting mid-build must never dlopen half a file.
gcc -shared -fPIC -O2 -Wall -o "$SO.tmp" "$HERE/livetheme.c" $(pkg-config --cflags --libs gio-2.0) -ldl
mv -f -- "$SO.tmp" "$SO"
echo "built $SO"
echo "next: restart the shell (so what it launches gets GIO_EXTRA_MODULES), and log out and in"
echo "      once for apps Hyprland launches. Check an app with:  grep -c livetheme /proc/\$(pgrep -x nautilus)/maps"
