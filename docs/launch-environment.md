# Launch environment and entry point

Read before touching shell.qml, scripts/shell-env.sh or the reload scripts. Moved out of CLAUDE.md verbatim.

## The launch environment

`scripts/shell-env.sh` is the one copy of the variables Quickshell must start
with. Both `~/.config/hypr/autostart.lua` (boot) and `scripts/reload-quickshell.sh`
(`ALT+Q`) `source` it, so a reloaded shell and a booted one start identically.

- `QML_IMPORT_PATH` is NOT what finds the optional `Quicktest.Blobs` plugin: `scripts/build-blobs-plugin.sh`
  installs it system-wide, to `/usr/lib/qt6/qml/Quicktest/Blobs`, because Qt doesn't search a user dir
  and Quickshell has no `--import-path` (the script's header has the reasoning). Without it,
  `state/Morph.qml`'s probe finds nothing and the panel morph falls back silently, with no warning
  anywhere. Harmless when the plugin was never built. (This bullet used to say the cache dir.)
- `QSG_RHI_BACKEND=vulkan`. OpenSSL 3.6.4 segfaults in `OSSL_PROVIDER_try_load_ex`
  when Qt's OpenGL program-binary cache hashes a shader key with
  `QCryptographicHash` — hit on the blob's first custom-shader compile, made worse
  by Quickshell's bundled jemalloc. Qt's Vulkan RHI backend keys its pipeline
  cache differently and never takes that path. Drop this once OpenSSL ships a fix.
- `QV4_GC_TIMELIMIT=0` (a `DefaultEnv` pragma in `shell.qml`, so a bare `qs -p` gets
  it too). Qt 6.11's INCREMENTAL GC swept a live object's method storage
  (`QQmlVMEMetaObject::propertyAndMethodStorage`, a weak value) during startup; it
  shows only when a `Connections` first gets a target after creation —
  `connectSignalsToMethods` reads a null function and the shell SEGFAULTS. Five cores,
  one trace: `MediaPosition`'s `target: root.player` in the bar's `MediaPanel`, the
  moment Spotify's MPRIS player turned up ~1.4s in. A/B-measured: `QV4_GC_TIMELIMIT=5`
  crashed, 0 (stop-the-world) didn't. The log shows NOTHING before the crash — read
  the core: `coredumpctl debug <pid>` with `-iex 'set debuginfod enabled on'`.
  Re-test without it on a Qt upgrade (cold start with Spotify playing).

`reload-quickshell.sh` also refuses to run while a privileged update holds the
flock (`flock -n -s` failing = a run is live), and its `pkill` matches BOTH `qs`
and `quickshell` with `-x` — the binary is installed twice, Hyprland autostarts
it as `qs`, and this script relaunches it as `quickshell`. Matching one name only
killed nothing on a boot-started shell.

## shell.qml — the entry point

`//@ pragma UseQApplication` on line 1. The file is a list of per-screen surfaces
(`Variants` over `Quickshell.screens`) plus a few single toplevels (`Settings`,
`LockScreen`) that the compositor places, and nothing else. UI state lives in
`state/UiState.qml`.

- **Eager singleton references.** A singleton is created lazily on first use. A
  service that must run *before* anything looks at it has to be forced into existence
  here, and **`readonly property var _x: Services.X` does not do that** — measured on
  the installed Quickshell 0.3.1 / Qt 6.11: the `Cursor` service, referenced that way,
  had no `cursor` IPC target in `qs ipc show` (its `IpcHandler` was never built), never
  ran after a reload, and only came alive once its settings page happened to be opened.
  `Connections { target: Services.X }` does (a Connections evaluates its `target` when
  it is created), and so does any real use — `Setup` works because of the `Connections`
  and the `Services.Setup.coreProbed` read below, not because of `_setup`. `Cursor` and
  `CursorEffects` use `Connections`. **Check any eager service the same way:** if it
  has an `IpcHandler`, `qs ipc -c ~/.config/quicktest show` must list its target.
  - **2026-10-07:** `Clipboard`, `AlbumScheme`, `Osd` and `Reminders` moved to
    `Connections` (built, not yet cold-start verified — after a fresh launch,
    `qs ipc show` should list `albumscheme` and `osd`; the other two have no IPC target).
    `_setup` is really used (`coreProbed`), so it is fine as is.
  - **Still the property form, deliberately:** `WallpaperEngine` (its autostart timer).
    Switching it starts a service that may have been dormant — it would start Wallpaper
    Engine's autostart if `Config.wpeAutoStart` is on — so ask first.
- The launcher lives INSIDE `Bar.qml`'s own window
  (`BarPanelDock`'s centre slot), not its own `PanelWindow`. The blob's
  metaball fusion only blends pixels within one Qt Quick scene graph.
- The persistent dock lives INSIDE `Bar.qml`'s window too (`modules/bar/DockHost`),
  for the same reason — it welds into the frame. Only its exclusive zone is its own
  window (`modules/dock/DockReserve`). Off by default (`Config.dockEnabled`); see
  "The dock" below.
