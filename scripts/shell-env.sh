#!/usr/bin/env bash
# ── shell-env.sh ─────────────────────────────────────────────────────────────
# `source` this before launching Quickshell. It exports, plus one idempotent side effect (Steam's
# debug-port flag, below).
#
# Used by:
#   · ~/.config/hypr/autostart.lua   — the boot autostart
#   · scripts/reload-quickshell.sh   — the ALT+Q reload
#
# ── It is now mostly redundant, on purpose ─────────────────────────────────
# Both things it used to carry moved somewhere every launch sees, so that a bare
# `qs -p ~/.config/quicktest` behaves the same as a sourced one:
#
#   QSG_RHI_BACKEND=vulkan   → `//@ pragma DefaultEnv` in shell.qml (still
#                              overridable with an explicit export, which is why
#                              it is re-stated here — harmless, and explicit).
#   the blob plugin path     → build-blobs-plugin.sh installs into the system Qt
#                              QML dir, which Qt searches by default. No
#                              QML_IMPORT_PATH needed.
#
# Kept as the one file the autostart and reload both source, so anything that
# genuinely must differ between a booted and a reloaded shell has a home.
export QSG_RHI_BACKEND="${QSG_RHI_BACKEND:-vulkan}"

# ── The cursor theme, for the shell's own windows and everything it launches ─────
# Clients that load their own cursor read XCURSOR_THEME when they start. Only exported
# once Settings › Cursor has generated the theme: a name that points at nothing gives a
# client NO cursor rather than the default one. An explicit XCURSOR_THEME still wins.
_qs_icons="${XDG_DATA_HOME:-$HOME/.local/share}/icons/quicktest"
[[ -f "$_qs_icons/index.theme" ]] && export XCURSOR_THEME="${XCURSOR_THEME:-quicktest}"
unset _qs_icons

# ── Spicetify's own install location ─────────────────────────────────────────────
# Its installer (and theme-setup.sh) puts it in ~/.spicetify and adds that to the PATH of
# whichever login shell it finds — bash's, zsh's — which Hyprland may never read. Added here
# so the shell finds it however the user's login shell is set up.
[[ -d "$HOME/.spicetify" && ":$PATH:" != *":$HOME/.spicetify:"* ]] && export PATH="$PATH:$HOME/.spicetify"

# ── Live GTK4 recolouring, for everything the shell launches ─────────────────────
# scripts/gtk-live/build.sh installs a GIO module that lets an already-open GTK4 / libadwaita
# app (Nautilus, Mission Center…) reload gtk.css when a theme run rewrites it. GTK4 only scans
# GIO modules at app start, so the app has to START with this set. Only exported once the
# module is built: GIO ignores a missing directory, but there's no reason to hand every
# process a path that holds nothing. Appended to, never replacing, an existing list.
_qs_gio="${XDG_DATA_HOME:-$HOME/.local/share}/quicktest/gio-modules"
[[ -f "$_qs_gio/libgiolivetheme.so" ]] && export GIO_EXTRA_MODULES="$_qs_gio${GIO_EXTRA_MODULES:+:$GIO_EXTRA_MODULES}"
unset _qs_gio

# ── Steam's live-recolour flag (opt-in) ──────────────────────────────────────────
# Steam opens its debug port only when ~/.local/share/Steam/.cef-enable-remote-debugging exists
# AT START, and deletes it as it reads it. Put it back at every shell start so the next Steam
# launch can be repainted live; theme runs and ThemeRunner's Restart button do the same. A
# no-op unless `scripts/steam-live.py enable` was run — that port is unauthenticated (see the
# header of that script), so nothing here opens it for anyone who hasn't asked.
python3 "$(dirname "${BASH_SOURCE[0]}")/steam-live.py" flag >/dev/null 2>&1 || true
