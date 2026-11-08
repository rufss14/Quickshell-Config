#!/bin/bash
# ── build-blobs-plugin.sh ───────────────────────────────────────────────────
# Builds plugin/ (the Quicktest.Blobs QML module — the metaball fusion of the
# bar and its panels) and installs it into the SYSTEM Qt QML directory, which is
# the only path every launch searches without an env var.
#
# ── Why the system dir ─────────────────────────────────────────────────────
# Qt doesn't search ~/.local or an XDG cache path for QML modules, and Quickshell
# has no --import-path flag. `qs -p ~/.config/quicktest` therefore couldn't find
# a plugin installed anywhere else, and the environment.d / shell-env.sh route
# only reaches a display-manager session after a relogin. One namespaced .so in
# /usr/lib/qt6/qml/Quicktest/Blobs is the price of "blob works however you launch".
#
# The shell still treats the module as optional (state/Morph.qml probes for it via
# Qt.createComponent), so a machine that never runs this degrades to the plain
# morph — nothing here is a hard dependency.
#
# The RHI backend (QSG_RHI_BACKEND=vulkan, the OpenSSL-segfault workaround) is a
# `//@ pragma DefaultEnv` in shell.qml now, so it needs nothing from here.
#
# Repo root is derived from this script's own location, never a literal.
#
#   build-blobs-plugin.sh              build + install (sudo/pkexec at the install step)
#   build-blobs-plugin.sh --stdin-sudo build, then `sudo -S` reads the password from
#                                     stdin for the install (the Setup panel's field)
#   build-blobs-plugin.sh --uninstall remove the installed module
set -euo pipefail

STDIN_SUDO=0
if [ "${1:-}" = "--stdin-sudo" ]; then STDIN_SUDO=1; shift; fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$REPO_ROOT/plugin"
BUILD_DIR="$PLUGIN_DIR/build"

QML_DIR="/usr/lib/qt6/qml"
MODULE_DIR="$QML_DIR/Quicktest/Blobs"

# How to get root for the install step:
#   already root         → nothing
#   --stdin-sudo         → sudo -S, password fed on stdin by the Setup panel
#   a terminal           → sudo (prompts normally)
#   otherwise (no tty)   → pkexec (GUI polkit dialog)
if   [ "$(id -u)" -eq 0 ]; then AS_ROOT=()
elif [ "$STDIN_SUDO" = 1 ]; then AS_ROOT=(sudo -S -p '')
elif [ -t 0 ];             then AS_ROOT=(sudo)
else                            AS_ROOT=(pkexec)
fi

if [ "${1:-}" = "--uninstall" ]; then
    "${AS_ROOT[@]}" rm -rf "$QML_DIR/Quicktest"
    echo "Removed $MODULE_DIR"
    echo "Reload the shell — Morph.available goes false and the plain morph takes over."
    exit 0
fi

# ── Build tools ────────────────────────────────────────────────────────────
# base-devel, cmake and qt6-shadertools are in install-dependencies.sh's
# --official list, so "Install core packages" on the Setup page covers them.
# This is the fallback message for a machine that skipped that.
_have_shadertools() {
    [ -e /usr/lib/cmake/Qt6ShaderTools/Qt6ShaderToolsConfig.cmake ] && return 0
    [ -x /usr/lib/qt6/bin/qsb ] && return 0
    command -v qsb >/dev/null 2>&1
}
_missing=()
command -v cmake >/dev/null 2>&1 || _missing+=(cmake)
{ command -v c++ >/dev/null 2>&1 || command -v g++ >/dev/null 2>&1; } || _missing+=(base-devel)
_have_shadertools || _missing+=(qt6-shadertools)
if [ "${#_missing[@]}" -gt 0 ]; then
    echo "Missing build tools: ${_missing[*]}" >&2
    echo "Install them with:  sudo pacman -S --needed ${_missing[*]}" >&2
    exit 1
fi

# Always from scratch. A CMakeCache.txt carries the absolute source and build
# paths it was generated with — a build/ tree that rode along in a clone (or a
# sync from another machine's home) makes cmake abort with "does not match the
# source used to generate cache". Nuking it removes the whole failure class.
rm -rf "$BUILD_DIR"

cmake -S "$PLUGIN_DIR" -B "$BUILD_DIR" \
    -DCMAKE_BUILD_TYPE=Release \
    -DINSTALL_QMLDIR="$QML_DIR"

cmake --build "$BUILD_DIR" --parallel "$(nproc)"

echo
echo "Installing to $QML_DIR (needs root)…"
"${AS_ROOT[@]}" cmake --install "$BUILD_DIR"

echo
echo "Installed Quicktest.Blobs to $MODULE_DIR"
echo "Reload the shell (ALT+Q) — no relogin, no env vars. Morph.available goes true."
echo
echo "After a qt6-base major upgrade, re-run this: the .so is linked against Qt's"
echo "private ABI and pacman won't rebuild it. Same caveat as the quickshell package."
