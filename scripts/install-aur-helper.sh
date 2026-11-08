#!/usr/bin/env bash
# ── install-aur-helper.sh ─────────────────────────────────────────────────────
# Installs an AUR helper (paru, the prebuilt paru-bin) when the machine has none — the setup wizard
# could only tell you to go and do this yourself; the terminal script could do it, the panel could not.
#
#   install-aur-helper.sh              build, then install with sudo (a terminal) or pkexec (no tty)
#   install-aur-helper.sh --stdin-sudo build, then `sudo -S` reads the password from stdin
#                                      (the Setup panel's password field — the same convention as
#                                      build-blobs-plugin.sh)
#
# It builds AS YOU (makepkg refuses to run as root) and only the final `pacman -U` is elevated. A helper
# that is already installed is left alone. Needs git and base-devel — the system-packages step installs
# both, and runs first.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

STDIN_SUDO=0
if [ "${1:-}" = "--stdin-sudo" ]; then STDIN_SUDO=1; shift; fi

if command -v paru >/dev/null 2>&1 || command -v yay >/dev/null 2>&1; then
    echo "An AUR helper is already installed."
    exit 0
fi
if [ "$(id -u)" -eq 0 ]; then
    echo "Run this as your own user: makepkg refuses to build as root." >&2
    exit 1
fi
for t in git makepkg; do
    command -v "$t" >/dev/null 2>&1 || { echo "Missing $t — install git and base-devel first (the system-packages step does)." >&2; exit 1; }
done

if   [ "$STDIN_SUDO" = 1 ]; then AS_ROOT=(sudo -S -p '')
elif [ -t 0 ];             then AS_ROOT=(sudo)
else                            AS_ROOT=(pkexec)
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "--- Fetching paru-bin from the AUR ---"
git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
cd "$tmp/paru-bin"

echo "--- Building it (as you) ---"
makepkg -f --noconfirm

pkg="$(ls -1 ./*.pkg.tar.* 2>/dev/null | grep -v -- '-debug-' | head -1)"
[ -n "$pkg" ] || { echo "makepkg produced no package." >&2; exit 1; }

echo "--- Installing $pkg (needs root) ---"
"${AS_ROOT[@]}" pacman -U --noconfirm "$pkg"
echo "paru is installed."
