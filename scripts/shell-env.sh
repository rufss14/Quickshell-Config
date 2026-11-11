#!/usr/bin/env bash
# ── shell-env.sh ─────────────────────────────────────────────────────────────
# `source` this before launching Quickshell. It exports the environment the shell needs.
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

# ── Log noise that is not ours ───────────────────────────────────────────────
# "Error updating property …StatusNotifierItem:IconName … error occurred in Get": a tray app (Discord,
# measured) that doesn't implement a property of its own StatusNotifierItem. Quickshell logs it per
# property and nothing in the shell can fix it. Only this category's warnings. It has to be in the
# environment BEFORE Quickshell starts: it reads QT_LOGGING_RULES when it sets up logging, ahead of the
# `//@ pragma DefaultEnv` lines in shell.qml, so a pragma there does nothing. A bare `qs -p` still logs it.
# Rules the user already exports are kept.
export QT_LOGGING_RULES="${QT_LOGGING_RULES:+$QT_LOGGING_RULES;}quickshell.dbus.properties.warning=false"

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
