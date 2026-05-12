# Quicktest — Quickshell Config

A Hyprland status bar built with [Quickshell](https://quickshell.outfoxxed.me/), featuring pywal theming, a live audio visualizer, a switchable unified/split pill layout, and a bunch more.

-----

## What it does

**Two bar modes** — toggle between a single unified bar and floating split pills, with smooth fade and slide transitions. You can also switch each pill between a rounded and rectangular shape on the fly.

**Pywal integration** — colors hot-reload automatically via inotify the moment `wal` regenerates `~/.cache/wal/colors.json`. Falls back to Tokyo Night if pywal isn’t around.

**Workspace indicators** — five Hyprland workspace dots where the active one expands. Click any dot to jump to that workspace.

**Live audio visualizer** — 16-bar cava visualizer running at 60fps. Falls back to a sine-wave animation when cava isn’t running.

**Clock** — an analog mini-clock alongside a date and digital time. Clicking it opens a draggable clock popup.

**Brightness slider** — iPhone-style fill bar that auto-detects DDC (`ddcutil`) or falls back to `brightnessctl`. Scroll-wheel works too.

**Wallpaper gallery** — a searchable grid/list view of `~/wallpapers/walls`. Applying a wallpaper runs a full theming pipeline across the system (see below).

**System updater** — checks for pacman updates every 10 minutes via `checkupdates`. Clicking opens a sudo password prompt and runs `pacman -Syu` plus `flatpak update` with a live progress bar.

**Persistent state** — bar mode, shape, and open panels all survive quickshell reloads via `PersistentProperties`.

**System tray** — shows tray items only when they’re present, hidden otherwise.

-----

## Directory structure

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

-----

## Dependencies

|Tool                           |Purpose                                               |
|-------------------------------|------------------------------------------------------|
|`quickshell`                   |Shell framework                                       |
|`hyprland`                     |Window manager (workspace data)                       |
|`cava`                         |Audio visualizer (optional, falls back to demo mode)  |
|`brightnessctl`                |Brightness control (fallback)                         |
|`ddcutil`                      |Brightness via DDC/CI for external monitors (optional)|
|`inotifywait` (inotify-tools)  |Watch `colors.json` for pywal changes                 |
|`pywal` / `wal`                |Color scheme generation                               |
|`awww`                         |Wallpaper setter (smooth transitions)                 |
|`checkupdates` (pacman-contrib)|Check for Arch updates without root                   |
|`flatpak`                      |Flatpak update support                                |
|`swaync`                       |Notification daemon (reloaded on wallpaper change)    |
|`kitty`                        |Terminal (theme reloaded via `killall -USR1`)         |
|`pywalfox`                     |Firefox pywal theming (optional)                      |
|`spicetify`                    |Spotify theming via `pwspice.py` (optional)           |
|CodeNewRoman Nerd Font Propo   |Bar font                                              |

-----

## Installation

Clone or copy this directory to `~/.config/quicktest/`, drop your wallpapers in `~/wallpapers/walls/`, then launch with:

```bash
quickshell -p ~/.config/quicktest/shell.qml
```

Or use the included reload script:

```bash
~/.config/quicktest/scripts/reload-quickshell.sh
```

-----

## Wallpaper pipeline

Hitting **Apply** on any wallpaper runs through the following in order:

1. `awww img <path>` — sets the wallpaper with a slide transition at 144fps
1. `wal -i <path> -n` — generates the pywal color scheme (no wallpaper setter, awww handles it)
1. Reloads swaync CSS
1. Updates the Spicetify theme via `pwspice.py`
1. Writes the kitty color config and sends `SIGUSR1` to reload live kitty instances
1. `pywalfox update` — pushes colors to Firefox
1. Applies pywal colors to Discord (Vencord / Vesktop)
1. Extracts `color2`/`color3` from `colors.sh`, patches the cava gradient config, then sends `SIGUSR2` to cava
1. Copies the wallpaper to `~/wallpapers/pywallpaper.jpg` for reference
1. Runs `dunst-wal.sh` to recolor dunst notifications

A `notify-send` notification pops up at the end confirming success or failure.

-----

## Theming

All colors, sizes, and animation durations live in `theming/Theme.qml`. Pywal colors are bound live, so any `Theme.*` property updates the instant `wal` writes a new `colors.json`. The fallback palette is Tokyo Night.

To tweak static values like font, bar height, pill geometry, or animation speed, just edit `Theme.qml` directly.

-----

## Bar controls

|Control                |Action                                    |
|-----------------------|------------------------------------------|
|Window icon (left pill)|Toggle bar shape (pill ↔ rectangle)       |
|Grid icon (left pill)  |Toggle unified ↔ split pill mode          |
|Wallpaper icon         |Open/close wallpaper gallery              |
|Brightness slider      |Drag or scroll to adjust screen brightness|
|Update icon (center)   |Check pending updates; click to run update|
|Workspace dots         |Click to switch workspace                 |
|Reload icon (center)   |Reload quickshell                         |
|Clock (right)          |Open/close clock popup                    |