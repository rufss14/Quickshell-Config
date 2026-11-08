pragma Singleton
import Quickshell
import QtQuick
import "../config"

// ── Terminal ──────────────────────────────────────────────────────────────────
// Which terminal emulator the shell opens things in, resolved in exactly ONE
// place: Config.launcherTerminal, then $TERMINAL, then the fallback. Never
// written back — baking this machine's terminal into a published config is what
// that rule exists for. The launcher's `>` mode and the stats pill's
// middle-click both ask here.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // $TERMINAL is a QVariant, so unset reads as `undefined` — never `""`. The `||`
    // idiom is the one the rest of this shell uses for exactly that reason.
    readonly property string resolved:
        Config.launcherTerminal !== "" ? Config.launcherTerminal
                                       : ((Quickshell.env("TERMINAL") || "")
                                          || Config.launcherTerminalFallback)

    // `-e` is the one flag kitty, foot, alacritty, wezterm, ghostty and xterm all
    // spell the same way. The command goes to a SHELL rather than being split here:
    // splitting it ourselves would mean reimplementing quoting, and getting that
    // subtly wrong is how a launcher runs half of what you typed.
    function run(command) {
        Quickshell.execDetached([root.resolved, "-e", "bash", "-lc", command])
    }

    // A program (argv, not a string — nothing to quote) in `dir`. The login shell is
    // what puts ~/.local/bin on the PATH, where `claude` lives; `exec "$@"` then hands
    // it the arguments exactly as given.
    function runIn(dir, argv) {
        Quickshell.execDetached({
            command: [root.resolved, "-e", "bash", "-lc", 'exec "$@"', "bash"].concat(argv),
            workingDirectory: dir
        })
    }
}
