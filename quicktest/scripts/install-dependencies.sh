#!/usr/bin/env bash
# InstalDependencies.sh
# Installs the system dependencies needed by this quickshell config on Arch Linux.
# Third-party app integrations (Spicetify, Vencord, Vesktop, Zen Browser, GTK4 apps)
# are intentionally NOT installed here since they're optional and user-specific.
#
# NOTE: "zlaunch" (used by the dock's app launcher button) is not a known/standard
# package and is skipped. Install/build it yourself if you use that button.

set -euo pipefail

echo "=== Quickshell config dependency installer ==="

# ── Ensure yay is available (needed for quickshell, pywal16) ────────────────
if ! command -v yay &>/dev/null; then
    echo "yay not found — installing it first..."
    sudo pacman -S --needed --noconfirm git base-devel
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay"
    (cd "$tmpdir/yay" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
fi

# ── Official repo packages ───────────────────────────────────────────────────
echo
echo "--- Installing official repo packages ---"
sudo pacman -S --needed --noconfirm \
    hyprland \
    qt6-base \
    qt6-declarative \
    qt6-wayland \
    qt6-svg \
    qt6-5compat \
    pipewire \
    pipewire-pulse \
    wireplumber \
    networkmanager \
    libnotify \
    brightnessctl \
    ddcutil \
    cava \
    pacman-contrib \
    flatpak \
    python \
    inotify-tools \
    otf-codenewroman-nerd

# ── AUR packages ──────────────────────────────────────────────────────────────
echo
echo "--- Installing AUR packages via yay ---"
yay -S --needed --noconfirm \
    quickshell \
    python-pywal16

echo
echo "=== Done ==="
echo "Reminder: 'zlaunch' and third-party integrations"
echo "(Spicetify/Vencord/Vesktop/Zen Browser/GTK4 theming) were NOT installed."
