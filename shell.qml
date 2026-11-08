//@ pragma UseQApplication
//@ pragma DefaultEnv QSG_RHI_BACKEND=vulkan
// ↑ OpenSSL 3.6.4 segfaults in OSSL_PROVIDER_try_load_ex when Qt's OpenGL
// program-binary cache hashes a shader key — hit on the blob plugin's first
// custom-shader compile. Qt's Vulkan RHI keys its pipeline cache differently and
// never takes that path. `DefaultEnv`, not `Env`: a machine with no Vulkan ICD
// can still `export QSG_RHI_BACKEND=opengl` (or gles) and that wins. Drop this
// whole line once OpenSSL ships a fix. Was scripts/shell-env.sh's job; a pragma
// covers every launch, including a bare `qs -p ~/.config/quicktest`.
//@ pragma DefaultEnv QV4_GC_TIMELIMIT=0
// ↑ Qt 6.11's INCREMENTAL garbage collector swept a live object's method storage
// (QQmlVMEMetaObject::propertyAndMethodStorage, a weak value) during startup. Nothing
// shows until a Connections first gets a target AFTER creation: then
// connectSignalsToMethods() reads a null function and the shell segfaults. Measured
// in five cores (2026-09-30, 2026-10-01 ×4): always MediaPosition's
// `target: root.player` in the bar's MediaPanel, the moment Spotify's MPRIS player
// turned up ~1.4s in, the storage slot null in every one. 0 = Qt's stop-the-world
// collector (qv4mm.cpp GCStateMachine: a limit ≤ 0 runs each cycle to completion),
// which has no in-between state to lose an object in. Costs an occasional longer GC
// pause. `DefaultEnv`, so an explicit export still wins. Re-test without it on the
// next Qt upgrade and drop it if a cold start with Spotify playing survives.
import Quickshell
import QtQuick
import "config"
import "state"
import "modules/bar"
import "modules/dock"
import "modules/panels"
import "modules/hud"
import "modules/desktop"
import "modules/overview"
import "modules/settings"
import "modules/lyrics"
import "modules/notifications"
import "modules/osd"
import "modules/lock"
import "modules/onboard"
import "modules/voice"
import "services" as Services

// ── shell.qml ─────────────────────────────────────────────────────────────────
// Entry point. Instantiates the shell's surfaces per screen, and nothing else.
//
// It used to also OWN `dockOpen` — declaring the property, passing it down into
// every bar and taking a signal back up to toggle it. All shell-wide UI state now
// lives in UiState, so this file is just a list of what exists per screen.
//
// The old dock's app list was folded into the overview as OverviewDock, then
// promoted back out into a real, persistent, positionable dock — off by default
// (Config.dockEnabled). It's drawn inside Bar's window (modules/bar/DockHost), so
// the blob can weld it into the screen frame; only its exclusive zone is its own
// window (DockReserve, below). Its power menu and confine-floats toggle never
// came back; those stayed the overview's job.
// ─────────────────────────────────────────────────────────────────────────────
ShellRoot {
    id: root

    // A lazy singleton's timers don't exist until something references it, and
    // nothing always-loaded referenced WallpaperEngine — so its "start with the
    // shell" autostart could only ever fire if the settings page happened to be
    // opened first. This reference is the fix: it instantiates the service at
    // launch, and the service's own guarded timer does the rest.
    readonly property var _wallpaperEngine: Services.WallpaperEngine

    // These four each have to exist from launch with nothing on screen to reference
    // them, so they use `Connections` (see the Cursor note below for why not the
    // property form above):
    //  - Clipboard: history has to be recording BEFORE you want it. The overview's
    //    clipboard card references it, but tying the watcher to a card's placement is
    //    fragile; this ties it to the shell's lifetime.
    //  - AlbumScheme: re-themes the shell per track, so it must be alive whenever music
    //    is, not only while the overview is open. Inert while Config.albumScheme is off:
    //    no extraction, no process.
    //  - Osd: observes Pipewire and ARMS itself once audio settles; too late if it only
    //    starts when something already wants to draw it. Also registers the `osd` IPC
    //    target from shell start.
    //  - Reminders: posts a notification when due, when the clock panel is most likely
    //    closed; its minute check runs from launch.
    // (2026-10-07, not yet cold-start verified: confirm with `qs ipc -c ~/.config/quicktest
    // show` after a fresh launch — `albumscheme` and `osd` should list.)
    Connections { target: Services.Clipboard }
    Connections { target: Services.AlbumScheme }
    Connections { target: Services.Osd }
    Connections { target: Services.Reminders }

    // The cursor watches the palette and regenerates its theme when it moves, and its
    // motion effects re-apply the plugin's settings when Hyprland reloads its config —
    // both with no settings page open, so both have to exist from launch. Inert while
    // Config.cursorTheme / cursorEffects are off.
    //
    // `Connections`, NOT `readonly property var _x: Services.X` like WallpaperEngine above:
    // measured here, that form did not create the singleton. `qs ipc … show` listed no
    // `cursor` target (its IpcHandler was never built), the service only ever ran after
    // the Cursor settings page happened to be opened, and after any reload it sat dead —
    // so the palette never reliably drove the pointer. A Connections evaluates its
    // `target` when it is created, which is what forces the singleton into existence.
    // Links between a colour scheme and a Material Wallpaper look load by themselves when the scheme
    // is applied, with no panel open.
    Connections { target: Services.MaterialPresets }
    Connections { target: Services.Cursor }
    Connections { target: Services.CursorEffects }
    // The Discord theme follows Settings → Type & Shape; it pushes once at launch and on every change.
    Connections { target: Services.DiscordTheme }
    // Sound effects hear the panels open and close with nothing on screen, so it must
    // exist from the start (inert while Config.sfxEnabled is off: no files, no player).
    Connections { target: Services.Sfx }

    // Bluetooth: the pairing agent must be registered BEFORE a pairing starts —
    // including one the phone starts with no panel open — and the connect OSD and
    // low-battery warnings watch devices with nothing on screen. BtBridge's helper
    // only runs while an adapter exists; Bt is pure bindings.
    Connections { target: Services.Bt }
    Connections { target: Services.BtBridge }

    // Clips: its `clips` IPC target is what the save-a-clip keybind calls, so it
    // must exist before anything opens; and a buffer left running across a reload
    // (the runner is detached) is picked back up at once. Idle it's two FileViews
    // and one probe — the recorder only runs when the user starts it.
    Connections { target: Services.Clips }

    // Brightness: its `brightness` IPC target is what the XF86MonBrightness binds call,
    // so it must exist before anything opens. Creating the singleton is free — the
    // `ddcutil detect` probe is still lazy, and runs on the first key (or first panel).
    Connections { target: Services.Brightness }

    // The wave (a wallpaper or colour change arriving as one front from the bottom
    // middle): its `wallwave` IPC target (status, demo) from launch, and Contagion —
    // which recolours the OTHER apps as the front reaches them — listening before the
    // first change. Idle, both are a few properties; nothing runs between waves.
    Connections { target: Services.WallWave }
    Connections { target: Services.Contagion }
    // Frame-drop logger: its `framewatch` IPC target must exist to be started. Off until asked.
    Connections { target: Services.FrameWatch }
    // Shell updates: its 6-hourly release check and the "updated to X" notice after
    // an install's restart have nothing on screen to create them.
    Connections { target: Services.ShellUpdate }
    // Alt+Tab: it follows focus from launch (the recent-windows order) and hears the
    // binds' events on Hyprland's socket — it has to exist before the first Tab.
    Connections { target: Services.Switcher }
    // The magnifier hears its keys the same way (custom events), so it exists from launch.
    Connections { target: Services.Magnifier }
    // Screen time counts from launch whether or not a view of it is open (inert while off).
    Connections { target: Services.ScreenTime }
    // Workspaces with their own wallpaper wear its colours from launch (shell + apps).
    Connections { target: Services.WorkspaceTheme }
    // The inactivity rules run from launch (one idle monitor each; inert while the master switch is off).
    Connections { target: Services.Inactivity }
    // The polkit agent registers from launch (inert while Config.polkitAgent is off) —
    // a request can arrive before anything has looked at it.
    Connections { target: Services.AuthAgent }
    // songrec's IPC target (`qs ipc call songrec toggle`) exists from launch, for a keybind.
    Connections { target: Services.SongRec }
    // The HUD's IPC target (`qs ipc call hud open` — the overview, a card tuned) exists from launch.
    Connections { target: Services.Hud }
    // Hears every reload (a failed one reaches only the generation still running).
    Connections { target: Services.ReloadWatch }
    // The snip tool's IPC target (`qs ipc call snip copy|save|edit|text|translate|record`).
    Connections { target: Services.Snip }
    // Pinned snips' IPC target (`qs ipc call snippins closeAll`), and the sweep of a dead shell's files.
    Connections { target: Services.SnipPins }

    // ── First-run: open the Setup page, once ─────────────────────────────────
    // A fresh clone runs but nothing is wired up — no packages beyond what the
    // machine already had, no autostart, no blob. Nothing would tell a new user
    // where any of that lives. This opens the Setup page the first time the shell
    // starts; `setupSeen` persists the moment they press "Got it, don't show
    // again", so it is genuinely once.
    //
    // Shows when the profile is fresh (`!setupSeen`) OR the core packages aren't
    // all in yet (`!Setup.coreReady`) — so dismissing it on a half-set-up machine
    // doesn't make it vanish for good; it's back next launch until setup.sh has
    // actually run. Waits on prefsLoaded (so `setupSeen` is the real value) and on
    // both Setup probes having answered.
    //
    // `setupAutoOpenDisabled` is the deliberate override for that: a checkbox on
    // the wizard's first page for someone who wants to run with an unfinished
    // setup and never be asked again. Checked before the probe wait, since a
    // machine that opted out doesn't need to wait on it either.
    //
    // Eager ref so `Setup` probes at launch rather than on first settings open —
    // same reason as the four services above.
    readonly property var _setup: Services.Setup
    property bool _firstRunShown: false

    function _maybeShowFirstRun() {
        if (root._firstRunShown) return
        if (!Config.prefsLoaded) return
        if (Config.setupAutoOpenDisabled) { root._firstRunShown = true; return }
        if (!Services.Setup.coreProbed) return
        if (Config.setupSeen && Services.Setup.coreReady) return
        root._firstRunShown = true
        UiState.welcomeOpen = true
    }

    Component.onCompleted: root._maybeShowFirstRun()
    Connections {
        target: Config
        function onPrefsLoadedChanged() { root._maybeShowFirstRun() }
    }
    Connections {
        target: Services.Setup
        function onCoreProbedChanged() { root._maybeShowFirstRun() }
    }

    // The static wallpaper, rendered by the shell (Config.wallShellRender) on the
    // background layer, one surface per screen — this is what makes the parallax
    // possible. Hides itself when awww is chosen or a Wallpaper Engine scene runs.
    Variants {
        model: Quickshell.screens
        // Declares its own `required property var modelData`, which Variants fills —
        // same as ScreenFrame and WidgetLayer above.
        delegate: WallpaperView {}
    }

    // ── Bar BEFORE ScreenFrame — map order is load-bearing ────────────────────
    // Both anchor to the screen edges with an exclusive zone, and the compositor
    // arranges layer surfaces in MAP order, subtracting each zone as it goes. The
    // bar spans the full width and reserves the top; ScreenFrame's side strips then
    // take the leftover side columns below it — which is exactly what ScreenFrame's
    // "starts below the bar (the bar already reserves its own zone)" comment
    // assumes. Declared the other way round, the side strips reserved first and the
    // bar came up ~frameDepth px narrower and inset, so BarFrameEdge's stubs landed
    // that far inboard of ScreenFrame's edge strips — a doubled frame on every
    // reload that only a screenFrame off/on toggle (which re-maps the strips after
    // the bar) put right.
    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    // The screen frame: strips down the sides and bottom that make the desktop read
    // as inset into the shell. The bar is its top edge (Bar.qml paints the frame
    // material itself when it's on). Costs nothing while Config.screenFrame is off —
    // every window in it is invisible.
    Variants {
        model: Quickshell.screens
        delegate: ScreenFrame {}
    }

    // The wave's curtain (a wallpaper/colour change): mapped only during a change,
    // it covers every app window with a copy of itself while the apps recolour
    // underneath, and the wave's front reveals them — see WaveCurtain and Contagion.
    Variants {
        model: Quickshell.screens
        delegate: WaveCurtain {}
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelHost {
            required property var modelData
            screen: modelData
        }
    }

    // The persistent dock's exclusive zone — Config.dockTakesSpace. The dock itself
    // is drawn in Bar's window (DockHost), which can only reserve the top edge.
    // Declared after ScreenFrame on purpose: map order stacks zones, so this one
    // lands on top of the frame's strip, which is where the dock actually sits.
    // Unmapped (costs nothing) unless the dock is on, reserving, and not hiding.
    Variants {
        model: Quickshell.screens
        delegate: DockReserve {
            required property var modelData
            screen: modelData
        }
    }

    // The launcher lives in Bar's own window now (BarPanelDock's centre slot, sharing
    // it with the update panel), so the blob can melt it out of the bar — the same
    // move the panels made, and for the same reason: metaball
    // fusion only works within one Qt Quick scene graph. Its old PanelWindow
    // (AppLauncherPopup) is gone with it. Still reachable by keybind and IPC:
    //     qs ipc -c ~/.config/quicktest call launcher toggle

    // The keybind cheatsheet — the binds from the user's own Hyprland config, read
    // through HyprConfig. Its own window for the same reason the launcher has one, and
    // its content is Loader-gated so a closed sheet parses nothing.
    //     qs ipc -c ~/.config/quicktest call cheatsheet toggle
    Variants {
        model: Quickshell.screens
        delegate: CheatsheetPopup {
            required property var modelData
            screen: modelData
        }
    }

    // The polkit password dialog (services/AuthAgent) — one screen, content-light, so no
    // Loader: a closed one is an unmapped window holding a handful of items.
    Variants {
        model: Quickshell.screens
        delegate: PolkitPopup {
            required property var modelData
            screen: modelData
        }
    }
    // The snip tool (services/Snip) — a window per screen, mapped only while it is open.
    Variants {
        model: Quickshell.screens
        delegate: SnipOverlay {
            required property var modelData
            screen: modelData
        }
    }

    // Pinned snips (services/SnipPins) — a window per screen, mapped only while that screen has a pin.
    Variants {
        model: Quickshell.screens
        delegate: PinLayer {
            required property var modelData
            screen: modelData
            screenName: modelData.name
        }
    }

    // A card when a reload fails (services/ReloadWatch) — one screen, its own window.
    Variants {
        model: Quickshell.screens
        delegate: ReloadPopup {
            required property var modelData
            screen: modelData
        }
    }

    // The HUD's PINNED widgets over a fullscreen game (services/Hud; the cards themselves live
    // in the overview). One window per screen, mapped only on the focused one while it shows a
    // fullscreen window; unmapped, it is a handful of items and no widget bodies (each is
    // Loader-gated in HudWidget).
    Variants {
        model: Quickshell.screens
        delegate: HudLayer {
            required property var modelData
            screen: modelData
        }
    }
    Variants {
        model: Quickshell.screens
        delegate: LensOverlay {
            required property var modelData
            screen: modelData
        }
    }

    // The clip library (services/Clips) — the cheatsheet's shape: its own window,
    // one screen, content Loader-gated so a closed gallery decodes no thumbnails.
    //     qs ipc -c ~/.config/quicktest call clips gallery
    Variants {
        model: Quickshell.screens
        delegate: ClipsGallery {
            required property var modelData
            screen: modelData
        }
    }

    // The first-run welcome — its own overlay card, shown once on a fresh profile
    // (Config.setupSeen), driven above by _maybeShowFirstRun. A dismissed one is an
    // unmapped PanelWindow holding a handful of Text items — nothing worth a Loader.
    //     qs ipc -c ~/.config/quicktest call welcome toggle
    Variants {
        model: Quickshell.screens
        delegate: WelcomePanel {
            required property var modelData
            screen: modelData
        }
    }


    // The overview: a full-screen overlay (recent windows + Alt+Tab, window search,
    // the workspace grid, power, volume and brightness).
    //     qs ipc -c ~/.config/quicktest call overview toggle
    Variants {
        model: Quickshell.screens
        delegate: Overview {
            required property var modelData
            screen: modelData
        }
    }

    // Snap zones: where a SUPER-dragged floating window will land (services/Snap).
    // Mapped only while one is carried.
    Variants {
        model: Quickshell.screens
        delegate: SnapOverlay {
            required property var modelData
            screen: modelData
        }
    }

    // Desktop widgets — clock, calendar, weather, notes and reminders, on a
    // background-layer surface per screen. One surface holds every widget on that
    // screen; see WidgetLayer for why that beats a window per widget.
    Variants {
        model: Quickshell.screens
        // WidgetLayer declares its own `required property var modelData`, which Variants
        // fills — same shape as ScreenFrame above. Redeclaring it here would shadow it.
        delegate: WidgetLayer {}
    }

    // Desktop clock — a background-layer surface behind every window, toggled by
    // the bar's clock pill. It gates its own timer on the toggle, so it costs
    // nothing while off.
    Variants {
        model: Quickshell.screens
        delegate: DesktopClock {
            required property var modelData
            screen: modelData
        }
    }

    // The screenshot annotator. Opened from the toast's Edit button (or
    // UiState.openAnnotate); `annotatePath` being "" is what keeps it closed.
    Variants {
        model: Quickshell.screens
        delegate: AnnotateWindow {
            required property var modelData
            screen: modelData
        }
    }

    // The post-capture screenshot toast: the picture, and what to do with it. Replaces
    // the screenshot tool's own "saved" notification (see Screenshot.consume).
    Variants {
        model: Quickshell.screens
        delegate: ScreenshotToast {
            required property var modelData
            screen: modelData
        }
    }

    // ── The reload carry ──────────────────────────────────────────────────────
    // Keeps the settings window OPEN across an in-process reload
    // (Quickshell.reload(), the bar's ReloadPill) instead of shutting it.
    //
    // ── Why this object sits HERE, and why the position is load-bearing ──────
    // Three facts from Quickshell's own reload machinery decide the placement:
    //
    //   1. EngineGeneration::onReload reloads the ROOT SCENE FIRST and the
    //      SINGLETONS SECOND. So a PersistentProperties inside UiState would
    //      restore the flag AFTER every window here had already reloaded — too
    //      late to matter.
    //   2. ProxyWindowBase::onReload adopts its previous toplevel ONLY if the
    //      window is already `visible` at the moment it reloads. Otherwise the old
    //      surface is dropped and a brand-new one maps once `visible` flips —
    //      which the compositor treats as a new window, so hypr/rules.lua re-centres
    //      it and the "it stayed open" illusion dies.
    //   3. ShellRoot is a ReloadPropagator: it reloads its children POSITIONALLY,
    //      in declaration order.
    //
    // Put together: restoring the flag from a child declared BEFORE SettingsWindow
    // sets the window's `visible` while its own reload is still pending, so it
    // adopts its existing surface and never unmaps. Declared AFTER, it would be
    // exactly the too-late case in (1). Keep it above SettingsWindow.
    //
    // Setting `visible` this early is safe, and deliberately so: ProxyWindowBase::
    // setVisible only records the flag while `reloadComplete` is false — no window
    // is built until the reload reaches it.
    //
    // ── It is a COURIER, not an owner ────────────────────────────────────────
    // UiState remains the single answer to "is settings open". This only mirrors
    // that value so there is something to hand the next generation, and hands it
    // back on the way in. Two sources of truth would be the usual disaster; this
    // has one, plus a slot that survives a teardown.
    //
    // Assigned from Connections rather than bound to UiState/Config, because
    // PersistentProperties restores by writing each property — which would destroy
    // a binding on the way in, and with it the carry for the NEXT reload.
    //
    // This does NOT survive a full process restart (ALT+Q / reload-quickshell.sh
    // pkills the shell); nothing in-process can. That is a separate job.
    PersistentProperties {
        id: reloadCarry
        reloadableId: "reloadCarry"

        property bool settingsWindowOpen: false

        // Config is a singleton, so it reloads AFTER this runs and its JsonStore
        // re-reads from disk asynchronously on top of that — meaning
        // `Config.settingsPanel` is still its default `false` here no matter what
        // the user actually set. Carrying the value is the only way to know the
        // mode at this instant. Without it, a panel-mode user's reload would map
        // the floating window for a few frames before Config loaded and hid it
        // again — a flash that reads as a bug.
        //
        // In panel mode the carry simply declines: the docked panel lives inside
        // Bar's window (SettingsPanelHost) and is a different surface with a
        // different lifetime.
        property bool settingsPanel: false

        // `reloaded` fires ONLY when an old instance was actually adopted, so a
        // cold start falls through here untouched. (`loaded` fires either way —
        // that is the wrong one.)
        onReloaded: {
            if (reloadCarry.settingsPanel) return
            if (!reloadCarry.settingsWindowOpen) return

            // Bracket the assignment: SettingsWindow's _sync() runs synchronously
            // inside this change signal, and it resets the window to its opening
            // size on every open. A resume is not an open — the adopted surface
            // already carries the size the user left it at, and clobbering that is
            // the one visible difference between "it stayed open" and "it didn't".
            UiState.settingsWindowResuming = true
            UiState.settingsWindowOpen = true
            UiState.settingsWindowResuming = false
        }
    }

    Connections {
        target: UiState
        function onSettingsWindowOpenChanged() {
            reloadCarry.settingsWindowOpen = UiState.settingsWindowOpen
        }
    }

    Connections {
        target: Config
        function onSettingsPanelChanged() {
            reloadCarry.settingsPanel = Config.settingsPanel
        }
    }

    // ── Settings ───────────────────────────────────────────────────────────────
    // An xdg-toplevel (FloatingWindow), NOT a layer surface — a layer overlay was
    // tried and reverted (it sat above the bar and broke the Bar page's arrange
    // drag). Floated + centred by a window rule in hypr/rules.lua; SettingsWindow
    // resets its own size on every open so it always launches the same.
    //
    // Reachable from the launcher (scripts/install-desktop-entry.sh), the bar's
    // gear, the hardware pills, and IPC:
    //     qs ipc -p ~/.config/quicktest call settings open
    SettingsWindow {}

    // ── Lyrics ─────────────────────────────────────────────────────────────────
    // A second real toplevel, same reasoning as Settings: resizable, focusable,
    // tileable, and launchable by typing its name. Floated + centred by the same
    // kind of window rule in hypr/rules.lua, matched on its own title.
    //
    // Reachable from the launcher (scripts/install-lyrics-entry.sh) and IPC:
    //     qs ipc -p ~/.config/quicktest call lyricswindow open
    LyricsWindow {}

    // The docked alternative (Config.settingsPanel on) is NOT here — it lives
    // INSIDE Bar's own window as SettingsPanelHost, so Quicktest.Blobs can melt it
    // out of the frame (a separate surface cannot blend with the frame's). See
    // modules/bar/SettingsPanelHost.qml.

    // ── The session lock ────────────────────────────────────────────────────────
    // Deliberately NOT in a Variants, unlike everything else here. WlSessionLock owns
    // the whole session rather than one output: it builds and destroys its own surface
    // per monitor as they come and go, which is what stops a monitor plugged in while
    // locked from appearing as an unlocked gap. One per screen would be N locks
    // fighting over one session.
    //
    // Reachable by keybind and IPC:
    //     qs ipc -c ~/.config/quicktest call lock lock
    LockScreen {}

    // ── Notifications ───────────────────────────────────────────────────────────
    // The daemon lives in the Notifications singleton (it binds the D-Bus name the
    // moment the shell loads). These are just its two surfaces: toasts on the focused
    // monitor, and the history centre.
    Variants {
        model: Quickshell.screens
        delegate: NotificationOverlay {
            required property var modelData
            screen: modelData
        }
    }

    // "Hey Claude" (services/VoiceAssistant): the request on screen while it's going — on the focused
    // screen (ScreenOwner), never taking the keyboard. Built on every screen like the OSD, so it can
    // appear the moment the wake word is heard; nothing reaches the compositor while it's hidden.
    Variants {
        model: Quickshell.screens
        delegate: VoiceOrb {
            required property var modelData
            screen: modelData
        }
    }
    // ── The OSD, for while a window is fullscreen ───────────────────────────────
    // Answers a media key: volume, mute, mic mute, brightness — and the announcements (a
    // Bluetooth device, the magnifier). Normally that is OsdDock, welded into the bar's
    // window; Hyprland hides the bar's layer under a fullscreen window, so this Overlay-layer
    // copy answers then. The Osd singleton observes Pipewire directly, so neither needs
    // keybind changes — whatever your volume keys already run, the shell sees the result.
    //
    // Always instantiated but invisible, matching ScreenshotToast rather than the
    // Loader-gated popups: it has to be able to appear within a frame of a keypress.
    // Nothing is committed to the compositor while `visible` is false.
    //     qs ipc -c ~/.config/quicktest call osd status
    Variants {
        model: Quickshell.screens
        delegate: OsdSliders {
            required property var modelData
            screen: modelData
        }
    }

}
