# Quicktest — My Quickshell Config

> A Hyprland status bar built with [Quickshell](https://quickshell.outfoxxed.me/), featuring pywal theming, lots of overlay panels, a switchable unified/split pill layout, a workspace overview, and much more.
---

## Preview

<p align="center">
  <img src="./Quickshell Showcase.png" alt="Desktop Preview">
</p>

---

## Directory structure

```
quicktest/
├── shell.qml                  # Entry point
├── statusbar/
│   ├── StatusBarRoot.qml      # Main bar (unified + split layouts, persistent state)
│   ├── PillRect.qml           # Shared background rectangle
│   ├── SplitPill.qml          # Animated pill for split mode
│   └── modules/               # All bar pills (clock, workspaces, tray, wifi, volume…)
├── overlay/
│   ├── OverlayRoot.qml        # Popup windows + collision-aware layout
│   └── modules/               # Panels singleton + all panel QML files
├── bgm/
│   ├── BgmRoot.qml            # BGM audio engine
│   └── soundtracks/           # Drop your MP3s here
├── overview/                  # Standalone workspace overview (separate qs instance)
├── theming/
│   ├── Theme.qml              # Colors, geometry, animation timings
│   ├── PywalColors.qml        # Reads + watches colors.json
│   └── icons/
└── scripts/
    ├── reload-quickshell.sh
    ├── dunst-wal.sh
    └── pacman-update.sh
```

---

## Dependencies
```bash
# Pacman
sudo pacman -S cava brightnessctl ddcuinotify-tools python-pywal pacman-contrib swaync

# AUR
yay -S quickshell-git awww
```

---

## Installation

```bash
git clone https://github.com/rufss14/Quickshell-Config ~/.config/quicktest
mkdir -p ~/wallpapers/walls
quickshell -p ~/.config/quicktest/shell.qml
```

### Workspace overview (optional)

The bundled `overview/` is a standalone module extracted from [illogical-impulse](https://github.com/end-4/dots-hyprland). Add to your Hyprland config:

```conf
bind      = Super, TAB, exec, qs ipc -c overview call overview toggle
exec-once = qs -c ~/.config/quicktest/overview/shell.qml
```
