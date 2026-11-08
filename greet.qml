//@ pragma UseQApplication
import Quickshell
import "modules/greet"

// ── greet.qml ─────────────────────────────────────────────────────────────────
// The greeter's entry point. A SECOND, separate Quickshell configuration in the same
// repository, run by greetd as the `greeter` user before any session exists:
//
//     qs -p ~/.config/quicktest/greet.qml
//
// ── Why this is not a flag on shell.qml ───────────────────────────────────────
// It is a different process, run as a different user, with a different home, at a
// point where there is no session, no D-Bus session bus, no Hyprland IPC belonging
// to you, and no wallpaper daemon. A "greeter mode" inside shell.qml would mean
// every service in the shell growing a branch for a state it can never be in, and
// one missed branch is a login screen that crashed.
//
// ── What is NOT here ──────────────────────────────────────────────────────────
// No bar, no notification daemon, no Discord, no clipboard watcher, no updater, no
// desktop widgets, no lock. Not switched off — never named. Every service in this
// shell is a lazy singleton, so the ones that instantiate are exactly the ones
// GreetScreen reaches for: Greet, Colors, Config, Tokens, Motion.
//
// That is the whole safety argument for the file being this short. The notification
// daemon in particular MUST NOT load: it binds a D-Bus name, and the greeter's bus is
// not the one your session will use — but the two overlap for the seconds after
// login while the greeter is being torn down, and a name conflict there is a
// notification daemon you do not have for the rest of the boot.
// ─────────────────────────────────────────────────────────────────────────────
ShellRoot {
    GreetScreen {}
}
