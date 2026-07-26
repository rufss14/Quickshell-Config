pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// ── Icons ─────────────────────────────────────────────────────────────────────
// Two jobs: resolve the shell's OWN bundled svg assets, and resolve a
// Hyprland/PipeWire app identifier to an icon the theme ships.
//
// The app-id half used to live in Theme, which meant a *theming* singleton owned
// a desktop-entry lookup table — a system-integration concern.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Bundled assets ────────────────────────────────────────────────────────
    // Call this instead of writing a relative path to an svg. Never write
    // `icon: "../../theming/icons/foo.svg"`.
    //
    // Relative urls in QML resolve against the file the BINDING is written in,
    // which meant the same asset was spelled "../../theming/…" from modules/bar/
    // and "../../../theming/…" from modules/bar/widgets/ — already fragile. Worse,
    // it silently BREAKS when a component is used as the root type of a derived
    // file: a relative-url literal assigned to a base-type property on a derived
    // root never gets resolved at all. IconButton's Image then received a raw
    // relative string, couldn't open it, and Quickshell substituted its
    // `qs-blackhole` placeholder — an icon that simply never appeared, with only
    // a cryptic warning to show for it.
    //
    // Qt.resolvedUrl() here resolves against THIS file, once, so every caller
    // gets a correct absolute url no matter what directory it lives in, and
    // moving the asset folder is a one-line change. (It just was: theming/icons
    // became assets/icons, and this line is the entire migration.)
    readonly property url assetDir: Qt.resolvedUrl("../assets/icons/")

    function asset(name) { return root.assetDir + name + ".svg" }

    // ── Third-party logos ─────────────────────────────────────────────────────
    // Separate directory, and deliberately a separate accessor rather than a name in
    // `asset()`: assets/icons is this project's own artwork, assets/logos is other
    // people's trademarks. The split is where the provenance and licence question
    // lives (see assets/logos/README.md), and it should be visible at the call site
    // rather than buried in a filename.
    //
    // No `.svg` assumed — the Wayland mark is only published as a PNG. Callers pass
    // the extension.
    readonly property url logoDir: Qt.resolvedUrl("../assets/logos/")

    function logo(file) { return root.logoDir + file }

    // A filesystem PATH, not a url — for handing to a subprocess (notify-send
    // --icon takes a path, not file://). Several call sites hardcoded
    // `Quickshell.env("HOME") + "/.config/quicktest/theming/icons/foo.svg"`,
    // which silently breaks the moment the config lives anywhere else — a
    // different directory name, an XDG_CONFIG_HOME override, a second checkout.
    // Derived from assetDir, so it can't drift from it.
    function assetPath(name) {
        return root.assetDir.toString().replace("file://", "") + name + ".svg"
    }

    // Known mismatches that heuristicLookup can't catch — almost always apps
    // with no installed .desktop entry, or whose entry id differs from the
    // window's appId. Keep this SHORT: every entry here is manual maintenance,
    // and the lookup below resolves the large majority without one.
    readonly property var _alias: ({
        "zen":              "zen-browser",
        "code-oss":         "com.visualstudio.code-oss",
        "code":             "com.visualstudio.code",
        "cursor":           "cursor",
        "vesktop":          "vesktop",
        "telegram-desktop": "telegram",
        "google-chrome":    "google-chrome",
        "brave-browser":    "brave-browser",
        "signal":           "signal-desktop",
        "steam":            "steam",
        "nautilus":         "org.gnome.Nautilus",
        "thunar":           "org.xfce.thunar",
    })

    // Best icon name for an appId, or "" if nothing resolves.
    //
    // Order, each step tried only if the previous produced nothing that
    // Quickshell.iconPath can actually find:
    //   1. the app's own .desktop "Icon=" — correct far more often than any
    //      hardcoded guess, and needs no maintenance per-app
    //   2. the alias table above
    //   3. the raw appId, then its lowercased form
    //
    // Returns "" rather than "application-x-executable" on a miss: callers pass
    // their own fallback as iconPath's second argument, and returning the
    // fallback here would mean asking for the fallback icon *with itself as its
    // own fallback*.
    function forAppId(appId) {
        if (!appId) return ""

        const candidates = []

        const entry = DesktopEntries.heuristicLookup(appId)
        if (entry && entry.icon) candidates.push(entry.icon)

        const lower = appId.toLowerCase()
        if (_alias[lower]) candidates.push(_alias[lower])

        candidates.push(appId, lower)

        for (let i = 0; i < candidates.length; i++) {
            if (!candidates[i]) continue
            // `check: true` returns "" for a miss instead of a broken-icon
            // texture, so candidates can be probed without ever rendering one.
            if (Quickshell.iconPath(candidates[i], true) !== "")
                return candidates[i]
        }
        return ""
    }

    // The app's .desktop "Name=", falling back to the raw appId for windows
    // with no installed desktop entry.
    function nameForAppId(appId) {
        if (!appId) return ""
        const entry = DesktopEntries.heuristicLookup(appId)
        return (entry && entry.name) ? entry.name : appId
    }

    // NOTE: there is deliberately no "always returns an icon" helper.
    //
    // The obvious one — fall back to "application-x-executable" — does not work:
    // that name is not guaranteed to exist in an icon theme, and it is NOT in this
    // one. Asking for it just produces a different missing-icon warning. And
    // `Quickshell.iconPath("", fallback)` doesn't fall back either; it builds a
    // bogus "?fallback=…" request and warns.
    //
    // So callers use pathForAppId(), which returns "" honestly, and render a GLYPH
    // when it does. A glyph always renders.

    // ── Papirus ───────────────────────────────────────────────────────────────
    // Resolved straight off disk, ahead of Qt's theme lookup.
    //
    // Quickshell.iconPath() goes through QIcon::fromTheme, which asks the Qt platform
    // theme which icon set to use. Qt does NOT read the GTK setting, so having
    // gtk-icon-theme-name=Papirus-Dark buys the shell nothing, and with
    // QT_QPA_PLATFORMTHEME=qt5ct and no qt5ct/qt6ct config to read, Qt falls back to
    // whatever it can find. That's why app icons were inconsistent.
    //
    // The alternative — writing icon_theme into ~/.config/qt6ct/qt6ct.conf — would
    // change the icon theme for every Qt app on the system to fix one shell. This stays
    // inside the config.
    //
    // Two Papirus details worth knowing, both found the hard way:
    //   • Papirus-DARK is nearly empty for apps: its index.theme inherits
    //     "breeze-dark,hicolor", not Papirus. The app icons live in plain `Papirus`.
    //   • Icons are per-size directories (16x16 … 128x128), not one flat folder, and an
    //     app may only ship one size. So the map keeps the LARGEST it finds.
    readonly property string papirusRoot: "/usr/share/icons/Papirus"

    property var _papirus: ({})
    property bool papirusReady: false

    // Scanned once, at startup. Sizes are walked LARGEST FIRST and awk keeps only the
    // first hit per name, so the biggest available icon wins and the shell sees one line
    // per app rather than one per app-per-size — Papirus ships ~57,000 files across
    // seven size directories, and pushing all of them through a SplitParser to throw
    // 85% away would be a visible startup cost for nothing. Awk emits "name<TAB>path".
    Process {
        id: scanPapirus
        running: true
        command: ["sh", "-c",
            "for d in 128x128 64x64 48x48 32x32 24x24 22x22 16x16; do " +
            "  ls " + root.papirusRoot + "/$d/apps/ 2>/dev/null | sed \"s|^|$d/apps/|\"; " +
            "done | awk -F/ '{ n = $NF; sub(/\\.[^.]*$/, \"\", n); " +
            "                  if (!(n in seen)) { seen[n] = 1; print n \"\\t\" $0 } }'"]

        property var found: ({})

        stdout: SplitParser {
            onRead: function(line) {
                const tab = line.indexOf("\t")
                if (tab <= 0) return
                scanPapirus.found[line.substring(0, tab).toLowerCase()] =
                    root.papirusRoot + "/" + line.substring(tab + 1).trim()
            }
        }

        onExited: {
            root._papirus     = scanPapirus.found
            root.papirusReady = true
        }
    }

    // The Papirus file for an appId, or "" — tried against the same candidates
    // forAppId() uses, so the alias table and .desktop lookup benefit it too.
    function papirusFor(appId) {
        if (!appId || !root.papirusReady) return ""

        const candidates = []
        const entry = DesktopEntries.heuristicLookup(appId)
        if (entry && entry.icon) candidates.push(entry.icon)

        const lower = appId.toLowerCase()
        if (_alias[lower]) candidates.push(_alias[lower])
        candidates.push(appId, lower)

        for (let i = 0; i < candidates.length; i++) {
            const c = candidates[i]
            if (!c) continue
            const hit = root._papirus[c.toLowerCase()]
            if (hit) return hit
        }
        return ""
    }

    // Same as forAppId, but returns a usable image path instead of an icon name.
    // "" when nothing resolves, so the caller can fall back to a glyph rather
    // than handing an empty url to an Image (which becomes the qs-blackhole
    // placeholder and warns).
    //
    // Papirus first, then the theme — so the shell looks like Papirus wherever Papirus
    // has an answer, and still resolves anything Papirus is missing.
    function pathForAppId(appId) {
        const p = root.papirusFor(appId)
        if (p) return p

        const name = root.forAppId(appId)
        return name ? Quickshell.iconPath(name, true) : ""
    }

    // Icon names that identify "some audio thing" rather than a specific app.
    // PipeWire streams routinely declare these, and rendering one tells the user
    // nothing about WHICH app the row belongs to — so they're rejected in favour
    // of a per-app glyph.
    readonly property var _genericAudioIcons: [
        "audio-src", "audio-x-generic", "audio-volume-high", "audio-volume-medium",
        "audio-volume-low", "audio-volume-muted", "multimedia-volume-control",
        "audio-card", "applications-multimedia"
    ]

    // Best icon path for a PipeWire stream, given the icon name it declares for
    // itself and an app id to fall back on. Tried in order:
    //   1. the declared icon, unless it's one of the generic audio icons above
    //   2. the app id, through the full desktop-entry lookup (forAppId)
    // Returns "" if neither resolves.
    function pathForStream(declaredIcon, appId) {
        if (declaredIcon && root._genericAudioIcons.indexOf(declaredIcon) < 0) {
            const p = Quickshell.iconPath(declaredIcon, true)
            if (p) return p
        }
        return root.pathForAppId(appId)
    }
}
