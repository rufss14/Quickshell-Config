//@ pragma UseQApplication
import Quickshell
import "modules/bar"
import "modules/panels"
import "modules/desktop"
import "modules/overview"
import "modules/notifications"
import "services" as Services

// ── shell.qml ─────────────────────────────────────────────────────────────────
// Entry point. Instantiates the shell's surfaces per screen, and nothing else.
//
// It used to also OWN `dockOpen` — declaring the property, passing it down into
// every bar and taking a signal back up to toggle it. All shell-wide UI state now
// lives in UiState, so this file is just a list of what exists per screen.
//
// The dock was removed entirely (its app list is preserved in
// ~/quickshell-salvage/ to be merged into the overview later). Its power menu,
// confine-floats toggle and overview trigger went with it, deliberately.
// ─────────────────────────────────────────────────────────────────────────────
ShellRoot {
    // A lazy singleton's timers don't exist until something references it, and
    // nothing always-loaded referenced WallpaperEngine — so its "start with the
    // shell" autostart could only ever fire if the settings page happened to be
    // opened first. This reference is the fix: it instantiates the service at
    // launch, and the service's own guarded timer does the rest.
    readonly property var _wallpaperEngine: Services.WallpaperEngine

    // Same reasoning, and the stakes are higher: clipboard history has to be recording
    // BEFORE you want it, or the thing you copied five minutes ago was never captured.
    // The overview's clipboard card does reference this singleton, and the overview
    // happens to be instantiated eagerly — but that makes "does the shell record your
    // clipboard" depend on a card's placement, and page 2's SettingsCard is already
    // behind a Loader. Naming it here ties the watcher to the shell's lifetime instead.
    readonly property var _clipboard: Services.Clipboard

    // The screen frame: strips down the sides and bottom that make the desktop read
    // as inset into the shell. The bar is its top edge (Bar.qml paints the frame
    // material itself when it's on). Costs nothing while Config.screenFrame is off —
    // every window in it is invisible.
    Variants {
        model: Quickshell.screens
        delegate: ScreenFrame {}
    }

    Variants {
        model: Quickshell.screens
        delegate: Bar {
            required property var modelData
            screen: modelData
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: PanelHost {
            required property var modelData
            screen: modelData
        }
    }

    // The launcher owns its own window rather than living inside PanelHost — two
    // PanelWindows sharing the "quickshell-launcher" namespace fight over keyboard
    // focus. It is reachable by keybind and IPC:
    //     qs ipc -c ~/.config/quicktest call launcher toggle
    Variants {
        model: Quickshell.screens
        delegate: AppLauncherPopup {
            required property var modelData
            screen: modelData
        }
    }

    // The overview: a full-screen overlay (workspace grid, dock, glance info).
    // Replaces what used to be an entirely separate Quickshell process.
    //     qs ipc -c ~/.config/quicktest call overview toggle
    Variants {
        model: Quickshell.screens
        delegate: Overview {
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

}
