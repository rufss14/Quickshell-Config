# Quicktest — Quickshell Config

> A Hyprland status bar built with [Quickshell](https://quickshell.outfoxxed.me/), featuring pywal theming, a live audio visualizer, a switchable unified/split pill layout, draggable overlay panels, a BGM player, a workspace overview, and much more.

---

## Preview

<p align="center">
  <img src="./Quickshell Showcase.png" alt="Desktop Preview">
</p>

---

## What it does

**Two bar modes** — toggle between a single unified bar and floating split pills, with smooth fade and slide transitions. You can also switch each pill between rounded and rectangular shapes on the fly. Both modes and all panel states survive reloads via `PersistentProperties`.

**Pywal integration** — colors hot-reload automatically via inotify the moment `wal` regenerates `~/.cache/wal/colors.json`. Falls back to Tokyo Night if pywal isn't running.

**Workspace indicators** — five Hyprland workspace dots where the active one expands to a pill. Click any dot to jump to that workspace. Dots change color to indicate occupied, focused, and workspaces active on another monitor.

**Live audio visualizer** — 16-bar cava visualizer running at 60 fps. Right-click to switch to an inline music controller with scrolling title/artist, prev/play/next buttons, and a seekable progress bar. Falls back to a sine-wave demo animation when cava isn't running.

**Clock pill** — a tiny analog clock alongside a date and digital time. Clicking opens a draggable clock popup panel.

**Volume + equalizer pill** — shows the current volume with a Nerd Font icon. Right-click to expand an inline volume slider. Left-click to toggle the equalizer popup panel. Scroll to adjust volume.

**Wifi pill** — shows the Wi-Fi icon colored by signal strength (red/yellow/blue) and the connected SSID. Right-click to collapse to icon-only. Left-click to open the Wi-Fi panel.

**BGM panel** — dedicated background music player for your own soundtrack files (MP3, etc.). Spins a vinyl icon in the status bar while playing.

**Brightness panel** — drag or scroll the fill bar to adjust screen brightness. Auto-detects DDC (`ddcutil`) or falls back to `brightnessctl`.

**Wallpaper gallery** — a searchable grid/list view of `~/wallpapers/walls`. Applying a wallpaper runs a full theming pipeline across the system (see below).

**System updater** — checks for pacman updates every 10 minutes via `checkupdates`. Clicking opens a terminal-style panel with a sudo prompt and a live progress bar that runs `pacman -Syu` plus `flatpak update`.

**Workspace overview** — a bundled standalone overview module (in `overview/`) showing all workspaces with live window thumbnails. Activate via `Super+Tab` as a separate quickshell instance.

**System tray** — hover a tray icon to reveal a kill badge; left-click to activate, right-click for the native DBus menu, middle-click for secondary activate.

**Keyboard layout pill** — shows the active layout tag (e.g. `US`, `PT`). Click to cycle to the next layout via `hyprctl switchxkblayout`. Updates instantly via Hyprland IPC.

---

## Directory structure

```
quicktest/
├── shell.qml                  # Entry point — mounts statusbar + overlay on every screen
├── statusbar/
│   ├── StatusBarRoot.qml      # Main bar window (unified + split layouts, persistent state)
│   ├── PillRect.qml           # Shared styled background rectangle
│   ├── SplitPill.qml          # Reusable animated pill for split mode
│   └── modules/
│       ├── AudioVisualizer.qml   # Cava bars + inline MPRIS controller
│       ├── BarMode.qml           # Unified ↔ split toggle button
│       ├── BarShape.qml          # Pill ↔ rectangle shape toggle
│       ├── BgmButton.qml         # BGM toggle — spins while playing
│       ├── BrightnessButton.qml  # Opens brightness panel
│       ├── Clock.qml             # Analog + digital clock pill
│       ├── EqualizerButton.qml   # Volume display + inline slider + panel toggle
│       ├── KeyboardLayout.qml    # Active layout tag, click to cycle
│       ├── ReloadButton.qml      # In-process reload with watchdog fallback
│       ├── ResetPanelPosButton.qml # Resets all draggable panel positions
│       ├── Tray.qml              # System tray with animated icons + kill badge
│       ├── UpdateButton.qml      # Update count badge + panel toggle
│       ├── WallpaperButton.qml   # Opens wallpaper gallery
│       ├── WifiButton.qml        # Signal-colored icon + SSID label, panel toggle
│       └── Workspaces.qml        # Expanding workspace dots
├── overlay/
│   ├── OverlayRoot.qml        # All popup panel windows + collision-aware layout
│   └── modules/
│       ├── Panels.qml         # Singleton — panel references + open/close state
│       ├── BgmPanel.qml       # Background music player panel
│       ├── BrightnessPanel.qml
│       ├── ClockPanel.qml
│       ├── EqualizerPanel.qml
│       ├── UpdatePanel.qml    # Full-screen update terminal overlay
│       ├── WallpaperPanel.qml # Searchable wallpaper picker
│       └── WifiPanel.qml
├── bgm/
│   ├── BgmRoot.qml            # BGM audio engine
│   └── soundtracks/           # Drop your MP3s here
├── overview/                  # Standalone workspace overview (separate qs instance)
│   ├── shell.qml
│   ├── common/                # Appearance, Config, ColorUtils, shared widgets
│   ├── services/              # HyprlandData, GlobalStates
│   └── modules/overview/      # Overview, OverviewWidget, OverviewWindow
├── theming/
│   ├── Theme.qml              # Singleton — colors, geometry, animation timings
│   ├── PywalColors.qml        # Singleton — reads + watches colors.json
│   └── icons/                 # SVG icons used throughout
├── VolumeSlider.qml
└── scripts/
    ├── reload-quickshell.sh
    ├── dunst-wal.sh
    └── pacman-update.sh
```

---

## Dependencies

| Tool | Purpose |
|---|---|
| `quickshell` | Shell framework |
| `hyprland` | Window manager (workspace data, IPC) |
| `cava` | Audio visualizer (optional, falls back to demo) |
| `brightnessctl` | Brightness control (fallback) |
| `ddcutil` | Brightness via DDC/CI for external monitors (optional) |
| `inotify-tools` (`inotifywait`) | Watch `colors.json` for pywal changes |
| `pywal` / `wal` | Color scheme generation |
| `awww` | Wallpaper setter (smooth transitions) |
| `checkupdates` (pacman-contrib) | Check for Arch updates without root |
| `flatpak` | Flatpak update support (optional) |
| `swaync` | Notification daemon (reloaded on wallpaper change) |
| `kitty` | Terminal (theme reloaded via `SIGUSR1`) |
| `pywalfox` | Firefox pywal theming (optional) |
| `spicetify` | Spotify theming via `pwspice.py` (optional) |
| CodeNewRoman Nerd Font Propo | Bar font |

---

## Installation

```bash
# Clone to your quickshell config directory
git clone https://github.com/rufss14/Quickshell-Config ~/.config/quicktest

# Drop wallpapers in
mkdir -p ~/wallpapers/walls

# Launch
quickshell -p ~/.config/quicktest/shell.qml
```

Or use the included reload script:

```bash
~/.config/quicktest/scripts/reload-quickshell.sh
```

### Workspace overview (optional, separate instance)

Add to your Hyprland config:

```conf
bind  = Super, TAB, exec, qs ipc -c overview call overview toggle
exec-once = qs -c ~/.config/quicktest/overview/shell.qml
```

---

## Wallpaper pipeline

Hitting **Apply** in the wallpaper panel runs through the following in order:

1. `awww img <path>` — sets the wallpaper with a slide transition at 144 fps
2. `wal -i <path> -n` — generates the pywal color scheme
3. Reloads swaync CSS
4. Updates the Spicetify theme via `pwspice.py`
5. Writes the kitty color config and sends `SIGUSR1` to all live kitty instances
6. `pywalfox update` — pushes colors to Firefox
7. Applies pywal colors to Discord (Vencord / Vesktop)
8. Extracts `color2`/`color3` from `colors.sh`, patches the cava gradient config, sends `SIGUSR2` to cava
9. Copies the wallpaper to `~/wallpapers/pywallpaper.jpg` for reference
10. Runs `dunst-wal.sh` to recolor dunst notifications

A `notify-send` popup confirms success or failure.

---

## Theming

All colors, sizes, and animation durations live in `theming/Theme.qml`. Pywal colors are bound live — any `Theme.*` property updates the instant `wal` writes a new `colors.json`. The fallback palette is Tokyo Night.

To adjust font, bar height, pill geometry, or animation speed, edit `Theme.qml` directly. The key properties are:

| Property | Default | Description |
|---|---|---|
| `fontFamily` | `"CodeNewRoman Nerd Font Propo"` | Bar font |
| `fontSize` | `13` | Base font size |
| `barHeight` | `40` | Total bar height in px |
| `pillHeight` | `24` | Height of each pill |
| `barMargin` | `4` | Gap between bar edge and pills |
| `barRadius` | `18` | Corner radius in unified mode |
| `pillRadius` | `12` | Corner radius in split mode |
| `animFast` | `150ms` | Hover color transitions |
| `animNormal` | `200ms` | Panel open/close |
| `animSlow` | `250ms` | Shape + margin transitions |

---

## Bar controls

| Control | Action |
|---|---|
| Window icon (left) | Toggle pill ↔ rectangle shape |
| Grid icon (left) | Toggle unified ↔ split pill mode |
| Vinyl icon (left) | Open/close BGM player panel |
| Wallpaper icon (left) | Open/close wallpaper gallery |
| Brightness icon (left) | Open/close brightness panel |
| Volume icon (left) | Open/close equalizer panel; scroll to adjust volume; right-click for inline slider |
| Layout tag (center) | Click to cycle keyboard layout |
| Update badge (center) | Shows pending update count; click to open update terminal |
| Workspace dots (center) | Click to switch workspace |
| Reload icon (center) | Reload quickshell |
| Audio visualizer (right) | Right-click to toggle inline MPRIS controller |
| Wi-Fi icon + SSID (right) | Open/close Wi-Fi panel; right-click to collapse to icon-only |
| Clock (right) | Open/close clock popup panel |

---

## Panel layout

Panels open as floating overlay windows that can be dragged. The layout is collision-aware — panels that would overlap automatically push each other aside with animated margins.

```
LEFT SIDE                                   RIGHT SIDE
[ Wallpaper (535px)                    ]    [ WiFi (360px) ][ Clock (340px) ]
[ Equalizer (460px) ][ BGM (528px)     ]
[ Brightness (300px)                   ]
```

Use the **Reset** button (visible in the left pill group) to snap all panels back to their default positions.

---

## Overview module

The bundled `overview/` directory is a standalone workspace overview extracted from [illogical-impulse](https://github.com/end-4/dots-hyprland) and adapted as a separate Quickshell instance.

| Action | Description |
|---|---|
| `Super + Tab` | Toggle overview |
| Arrow keys / `h` `j` `k` `l` | Navigate between windows and workspace rows |
| `1`–`9`, `0` | Jump to Nth workspace |
| `Escape` / `Enter` | Close overview |
| Click window | Focus that window |
| Middle-click window | Close that window |
| Drag window | Move to a different workspace |

Configuration (scale, rows, columns) lives in `overview/common/Config.qml`.
