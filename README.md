# Quicktest — Quickshell Config

A Hyprland status bar built with [Quickshell](https://quickshell.outfoxxed.me/), featuring pywal theming, a live audio visualizer,a switchable unified/split pill layoutand much more in the future!

---

## Features

- **Dual bar modes** — toggle between a single unified bar and floating split pills, with smooth fade + slide transitions
- **Bar shape toggle** — switch between rounded pill and rectangular shapes per pill
- **Pywal integration** — colors hot-reload automatically via inotify whenever `wal` regenerates `~/.cache/wal/colors.json`; falls back to Tokyo Night if pywal isn't available
- **Workspace indicators** — 5 Hyprland workspace dots, active dot expands; clicking a dot switches workspace
- **System tray** — shows tray items only when present, hidden otherwise
- **Live audio visualizer** — 16-bar cava visualizer at 60 fps; falls back to a sine-wave animation when cava isn't running
- **Clock** — analog mini-clock + date + digital time; clicking opens a draggable clock popup
- **Brightness slider** — iPhone-style fill bar; auto-detects DDC (`ddcutil`) or falls back to `brightnessctl`; scroll-wheel supported
- **Wallpaper gallery** — searchable grid/list view of `~/wallpapers/walls`; applying a wallpaper runs a full theming pipeline (see below)
- **System updater** — checks for pacman updates every 10 minutes via `checkupdates`; clicking opens a sudo password prompt and runs `pacman -Syu` + `flatpak update` with a live progress bar
- **Persistent state** — bar mode, shape, and open panels survive quickshell reloads via `PersistentProperties`

---

## Directory Structure

```
quicktest/
├── shell.qml                  # Entry point — mounts bar + update panel on every screen
├── statusbar/
│   ├── StatusBarRoot.qml      # Main bar window (unified + split layouts)
│   ├── PillRect.qml           # Shared styled rectangle used for all pills
│   └── modules/
│       ├── AudioVisualizer.qml
│       ├── BarMode.qml
│       ├── BarShape.qml
│       ├── BrightnessSlider.qml
│       ├── Clock.qml
│       ├── ReloadButton.qml
│       ├── Tray.qml
│       ├── UpdateButton.qml
│       ├── WallpaperButton.qml
│       └── Workspaces.qml
├── overlay/
│   ├── OverlayRoot.qml
│   └── modules/
│       ├── Panels.qml         # Singleton that holds panel references
│       ├── UpdatePanel.qml    # Full-screen overlay for system updates
│       └── WallpaperPanel.qml # Draggable wallpaper picker popup
├── theming/
│   ├── Theme.qml              # Singleton — colors, geometry, animation timings
│   ├── PywalColors.qml        # Singleton — reads + watches colors.json
│   └── icons/                 # SVG icons used throughout
└── scripts/
    ├── reload-quickshell.sh   # Safe restart script
    ├── dunst-wal.sh           # Apply pywal colors to dunst
    └── pacman-update.sh
```

---

## Dependencies

| Tool | Purpose |
|------|---------|
| `quickshell` | Shell framework |
| `hyprland` | Window manager (workspace data) |
| `cava` | Audio visualizer (optional, falls back to demo mode) |
| `brightnessctl` | Brightness control (fallback) |
| `ddcutil` | Brightness via DDC/CI for external monitors (optional) |
| `inotifywait` (inotify-tools) | Watch `colors.json` for pywal changes |
| `pywal` / `wal` | Color scheme generation |
| `awww` | Wallpaper setter (smooth transitions) |
| `checkupdates` (pacman-contrib) | Check for Arch updates without root |
| `flatpak` | Flatpak update support |
| `swaync` | Notification daemon (reloaded on wallpaper change) |
| `kitty` | Terminal (theme reloaded via `killall -USR1`) |
| `pywalfox` | Firefox pywal theming (optional) |
| `spicetify` | Spotify theming via `pwspice.py` (optional) |
| CodeNewRoman Nerd Font Propo | Bar font |

---

## Installation

1. Clone or copy this directory to `~/.config/quicktest/`
2. Place wallpapers in `~/wallpapers/walls/`
3. Run quickshell pointing at the config:
   ```bash
   quickshell -p ~/.config/quicktest/shell.qml
   ```
   Or use the included reload script:
   ```bash
   ~/.config/quicktest/scripts/reload-quickshell.sh
   ```

---

## Wallpaper Pipeline

Clicking **Apply** on any wallpaper runs the following in order:

1. `awww img <path>` — set wallpaper with a slide transition at 144 fps
2. `wal -i <path> -n` — generate pywal color scheme (no wallpaper setter, awww handles it)
3. Reload swaync CSS
4. Update Spicetify theme via `pwspice.py`
5. Write kitty color config and send `SIGUSR1` to reload live kitty instances
6. `pywalfox update` — update Firefox colors
7. Apply pywal colors to Discord (Vencord / Vesktop)
8. Extract `color2`/`color3` from `colors.sh` and patch cava gradient config, then send `SIGUSR2` to cava
9. Copy wallpaper to `~/wallpapers/pywallpaper.jpg` (for reference)
10. Run `dunst-wal.sh` to recolor dunst notifications

A `notify-send` notification confirms success or failure.

---

## Theming

All colors, sizes, and animation durations are defined in `theming/Theme.qml`. Pywal colors are bound live — any `Theme.*` property updates the moment `wal` writes a new `colors.json`.

The fallback palette is **Tokyo Night**.

To customize static values (font, bar height, pill geometry, animation speed) edit `Theme.qml` directly.

---

## Bar Controls

| Control | Action |
|---------|--------|
| Window icon (left pill) | Toggle bar shape (pill ↔ rectangle) |
| Grid icon (left pill) | Toggle unified ↔ split pill mode |
| Wallpaper icon | Open/close wallpaper gallery popup |
| Brightness slider | Drag or scroll to adjust screen brightness |
| Update icon (center) | Check/show pending updates; click to run update |
| Workspace dots | Click to switch workspace |
| Reload icon (center) | Reload quickshell |
| Clock (right) | Open/close clock popup |
