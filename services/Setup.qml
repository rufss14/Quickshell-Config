pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../config"
import "../state"
import "setupplan.js" as Plan

// ── Setup ─────────────────────────────────────────────────────────────────────
// The setup hub: what the machine still needs, and the jobs that provide it.
//
// ── A plan, not a pile of buttons ────────────────────────────────────────────
// Not seven pages of fifteen install buttons, one job at a time: `steps` is the
// whole catalogue (services/setupplan.js, tested) with what the machine already has marked done, `selectedIds`
// the ticked ones (the recommended set until you choose otherwise), and `startPlan()` runs them in order as one
// queue: dependencies pulled in (an AUR step brings the AUR helper, which brings the base tools), a failed step
// skipping only what needed it, every failure explained (`explainFailure`). Root is asked for ONCE: a typed
// password reused by every step, or — with no password and a polkit agent running — the system's own dialog.
// The facts it plans from come from one read-only scan (scripts/setup-scan.sh) plus the probes below.
//
// ── Two halves ───────────────────────────────────────────────────────────────
//   Probes   read-only. The compositor's config (autostart / keybinds / bar
//            blur), and whether the core packages and pywal are installed. Every
//            feature-specific check stays with the service that owns it
//            (NightLight.blocker(), WallpaperEngine.blocker(), …).
//   Runner   one job at a time, streamed to a live terminal in the panel.
//            `--core` through `sudo -S`, the unprivileged scripts (blob build,
//            hypr config, autostart), AND the AUR install (installAur) — yay/paru
//            run as the user and only elevate the final pacman step, so a primed
//            credential cache is enough. `./setup.sh` remains the full terminal
//            path for anyone who wants it.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    readonly property string _home: Quickshell.env("HOME") || ""
    readonly property string _xdgConfig:
        Quickshell.env("XDG_CONFIG_HOME") || (root._home + "/.config")
    readonly property string hyprDir: root._xdgConfig + "/hypr"

    readonly property string repoDir: Quickshell.shellDir
    readonly property string setupCommand: "cd " + root.repoDir + " && ./setup.sh"

    // ══ Probes ═══════════════════════════════════════════════════════════════

    property bool _probed:       false
    property bool _hyprPresent:  false
    property bool _autostart:    false
    property int  _bindCount:    0
    property string _barBlur:    "absent"   // "on" | "off" | "absent"
    property string _hyprConfig: "absent"   // "bundled" | "other" | "absent"

    readonly property bool probed:      root._probed
    readonly property bool hyprPresent: root._hyprPresent
    readonly property bool autostart:   root._autostart
    readonly property int  bindCount:   root._bindCount
    readonly property string barBlur:   root._barBlur

    // Is the config in ~/.config/hypr THIS repo's bundled Lua config? Detected by
    // its distinctive entry point (hyprland.lua require()ing the module set) plus
    // the shared blend.lua — not just "a hyprland config exists". "other" means
    // the user runs their own; the wizard then offers either the full bundle or
    // just quicktest.lua (see hyprMinimalActive).
    readonly property bool hyprConfigActive: root._hyprConfig === "bundled"

    // quicktest.lua present — someone kept their own Hyprland config and
    // require()'d just the shell's essentials in, instead of the full bundle.
    // Filesystem-only, same as hyprConfigActive above: it can't tell whether
    // hyprland.lua actually require()s the file, only that it's there.
    readonly property bool hyprMinimalActive: root._hyprConfig === "minimal"

    readonly property bool hyprReady:
        root._hyprPresent && root._autostart && root._bindCount > 0

    // Where quicktest.lua lands, and the line the user adds to their own
    // hyprland.lua to actually load it — shown in the wizard, never assumed done.
    readonly property string hyprMinimalPath: root.hyprDir + "/quicktest.lua"
    readonly property string hyprMinimalRequireLine: "require(\"quicktest\")"

    property Process _probe: Process {
        running: true
        command: ["bash", "-c",
              "d=" + root._shq(root.hyprDir) + "; "
            + "[ -d \"$d\" ] || { echo '0 0 0 absent absent'; exit 0; }; "
            // Commented-out lines (Lua `--`, hyprlang `#`) don't count: a disabled autostart or bind is not wired.
            + "live() { grep -rhvE '^[[:space:]]*(--|#)' \"$d\" 2>/dev/null; }; "
            + "live | grep -qE '(qs|quickshell)[[:space:]]+-[pc][[:space:]]' && A=1 || A=0; "
            + "B=$(live | grep -E 'bind.*qs[[:space:]]+ipc' | wc -l); "
            + "if live | grep -E 'layer_rule|layerrule' | grep -q 'quickshell-bar'; then "
            + "  if live | grep -E 'layer_rule|layerrule' | grep 'quickshell-bar' | grep -qE 'blur[^,}]*(true|1|on)'; then B2=on; else B2=off; fi; "
            + "else B2=absent; fi; "
            + "if [ -f \"$d/hyprland.lua\" ] && [ -f \"$d/blend.lua\" ] "
            + "  && grep -q 'require(\"appearance\")' \"$d/hyprland.lua\" 2>/dev/null "
            + "  && grep -q 'require(\"animation\")' \"$d/hyprland.lua\" 2>/dev/null; then H=bundled; "
            + "elif [ -f \"$d/quicktest.lua\" ]; then H=minimal; "
            + "elif [ -f \"$d/hyprland.lua\" ] || [ -f \"$d/hyprland.conf\" ]; then H=other; "
            + "else H=absent; fi; "
            + "echo \"1 $A $B $B2 $H\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                root._hyprPresent = p[0] === "1"
                root._autostart   = p[1] === "1"
                root._bindCount   = parseInt(p[2] || "0", 10) || 0
                root._barBlur     = p[3] || "absent"
                root._hyprConfig  = p[4] || "absent"
                root._probed      = true
            }
        }
    }

    // ── Rivals ───────────────────────────────────────────────────────────────
    // Processes that fight the shell for something only one thing can own: the
    // notification service on D-Bus (dunst/mako/swaync — the shell IS the daemon, and a
    // second one means no toasts at all), the session's polkit agent, and a second bar.
    // Detected, never killed: ending somebody's program is not setup's call, so the page
    // shows the command and the autostart line to remove. `comm` is cut at 15 characters
    // by the kernel, hence the prefixes (polkit-gnome-au…, lxqt-policykit…).
    property var _running: []
    readonly property var rivalNotifiers: root._running.filter(n => /^(mako|dunst|swaync)$/.test(n))
    readonly property var rivalAgents:    root._running.filter(n => /^(hyprpolkitagent|polkit-gnome-au|polkit-kde-auth|lxqt-policykit|xfce-polkit|mate-polkit)/.test(n))
    readonly property var rivalBars:      root._running.filter(n => /^(waybar|eww|ags)$/.test(n))

    property Process _rivalProbe: Process {
        running: true
        command: ["sh", "-c", "ps -eo comm= | grep -E '^(mako|dunst|swaync|waybar|eww|ags|hyprpolkitagent|polkit-gnome-au|polkit-kde-auth|lxqt-policykit|xfce-polkit|mate-polkit)' | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root._running = text.split("\n").map(l => l.trim()).filter(l => l !== "")
        }
    }

    // ── Core packages + pywal ───────────────────────────────────────────────
    // `pacman -Q` against install-dependencies.sh's own --official list (its one
    // source of truth) plus a `command -v wal` — the AUR pywal is what the
    // wallpaper and colour-scheme pipelines actually call, and without it they
    // both fail. -1 until checked.
    readonly property string _depScript: Quickshell.shellPath("scripts/install-dependencies.sh")
    // One argument for a bash command string, single-quoted (a path with a quote in it stays one word).
    function _shq(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    property int  _missingCore: -1
    property bool _walOk:       false
    property bool _pkgProbed:   false
    property string _aurHelper: ""          // "yay" | "paru" | "none" | "" (unprobed)

    readonly property bool coreProbed: root._pkgProbed
    readonly property bool coreReady:  root._missingCore === 0 && root._walOk
    readonly property int  missingCore: Math.max(0, root._missingCore)
    readonly property bool pywalReady:  root._walOk

    // Which AUR helper is on PATH — the wizard drives it directly rather than
    // showing a copy-paste line (see installAur). "none" = neither is installed
    // (yay/paru are themselves AUR, so this can't be bootstrapped from here).
    readonly property string aurHelper:      root._aurHelper === "" ? "yay" : root._aurHelper
    readonly property bool   aurHelperReady: root._aurHelper === "yay" || root._aurHelper === "paru"

    property Process _pkgProbe: Process {
        running: true
        command: ["bash", "-c",
              "m=$(for p in $(" + root._shq(root._depScript) + " --official 2>/dev/null); do "
            + "  pacman -T \"$p\" >/dev/null 2>&1 || pacman -Qg \"$p\" >/dev/null 2>&1 || echo x; "
            + "done | grep -c x || true); "
            // The text font is installed by --core but is not in --official (it must never be upgraded or
            // downgraded under a running shell), so it is counted here.
            + "pacman -Qq otf-codenewroman-nerd >/dev/null 2>&1 || m=$((m+1)); "
            + "command -v wal >/dev/null 2>&1 && w=1 || w=0; "
            + "if command -v yay >/dev/null 2>&1; then h=yay; "
            + "elif command -v paru >/dev/null 2>&1; then h=paru; else h=none; fi; "
            + "echo \"$m $w $h\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                root._missingCore = parseInt(p[0] || "0", 10) || 0
                root._walOk       = p[1] === "1"
                root._aurHelper   = p[2] || "none"
                root._pkgProbed   = true
            }
        }
    }

    // ── Optional integration package names + presence ───────────────────────
    // install-dependencies.sh's OPTIONAL_PKGS table is the one place these
    // names live (see that file). This resolves a key to a package name for
    // the install jobs below, so a rename there is a one-line change instead
    // of a hunt through this file and WelcomePanel.qml for a hardcoded string.
    // The fallback argument covers the one tick before the probe answers —
    // correct as of writing, just not the thing to trust if it ever drifts.
    //
    // Also checks whether each one is ALREADY installed (`pacman -Qq`), same
    // idea as _pkgProbe's core-package loop above. Without this the wizard had
    // no way to tell "already installed" from "never installed" for a package
    // no other service already probes for itself (Wallpaper Engine and
    // Spicetify each have their own; lyrics translation's argos backend did
    // not) — so that row always read "Install", never "Reinstall", regardless
    // of what was actually on the machine.
    property var _optionalPkgs: ({})
    property var _optionalInstalled: ({})
    function optionalPkg(key, fallback) { return root._optionalPkgs[key] || fallback }
    function optionalInstalled(key) { return root._optionalInstalled[key] === true }

    property Process _optPkgProbe: Process {
        running: true
        command: ["bash", "-c",
              "for kv in $(" + root._shq(root._depScript) + " --optional); do "
            + "  k=\"${kv%%=*}\"; p=\"${kv#*=}\"; "
            + "  pacman -Qq \"$p\" >/dev/null 2>&1 && i=1 || i=0; "
            + "  echo \"$k=$p=$i\"; "
            + "done"]
        stdout: SplitParser {
            property var _pkgs: ({})
            property var _installed: ({})
            onRead: function(line) {
                const parts = line.split("=")
                if (parts.length < 3) return
                const key = parts[0]
                _pkgs[key] = parts[1]
                _installed[key] = parts[2] === "1"
            }
        }
        onExited: {
            root._optionalPkgs = Object.assign({}, _optPkgProbe.stdout._pkgs)
            root._optionalInstalled = Object.assign({}, _optPkgProbe.stdout._installed)
        }
    }

    // ── Feature packs (install-dependencies.sh PACK_PKGS) ────────────────────
    // Whether every package of each pack is installed: key → bool. `pacman -Qq a b c`
    // exits 0 only when all of them are. The names stay in the script (`--packs`);
    // packPkgs carries them through for the step drawers' "what will this do".
    property var packsInstalled: ({})
    property var packPkgs: ({})
    function packInstalled(key) { return root.packsInstalled[key] === true }

    property Process _packProbe: Process {
        running: true
        command: ["bash", "-c",
              "for kv in $(" + root._shq(root._depScript) + " --packs); do "
            + "  k=\"${kv%%=*}\"; p=\"${kv#*=}\"; "
            + "  pacman -Qq ${p//,/ } >/dev/null 2>&1 && i=1 || i=0; "
            + "  echo \"$k=$i=$p\"; "
            + "done"]
        stdout: SplitParser {
            property var _seen: ({})
            property var _pkgs: ({})
            onRead: function(line) {
                const parts = line.split("=")
                if (parts.length < 3 || !/^[a-z]+$/.test(parts[0])) return
                _seen[parts[0]] = parts[1] === "1"
                _pkgs[parts[0]] = parts[2].split(",").filter(x => /^[a-z0-9][a-z0-9+._-]*$/.test(x)).join(" ")
            }
        }
        onExited: {
            root.packsInstalled = Object.assign({}, _packProbe.stdout._seen)
            root.packPkgs = Object.assign({}, _packProbe.stdout._pkgs)
        }
    }

    // ── App theming (scripts/theme-setup.sh) ─────────────────────────────────
    // GTK, Qt, Discord, Spotify and Steam: whether each already follows the palette,
    // can be set up from here, needs the user first, or isn't installed at all. All of
    // the detection is the script's (`theme-setup.sh status`, tested by
    // scripts/test-theme-setup.sh); this only reads its lines.
    //   themes[id] = { state: ready|todo|blocked|absent, sudo: bool, detail }
    readonly property string _themeScript: Quickshell.shellPath("scripts/theme-setup.sh")
    readonly property var themeIds: ["gtk", "qt", "discord", "spotify", "steam"]
    property var themes: ({})
    property bool themesProbed: false
    function theme(id) { return root.themes[id] || ({ state: "", sudo: false, detail: "" }) }
    // How many could be set up right now — the "Set up all" button and the todo count.
    readonly property int themesTodo:
        root.themeIds.filter(id => root.theme(id).state === "todo").length

    property Process _themeProbe: Process {
        running: true
        command: ["bash", root._themeScript, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = ({})
                for (const line of text.split("\n")) {
                    const f = line.split("|")
                    if (f.length < 4) continue
                    out[f[0]] = { state: f[1], sudo: f[2] === "1", detail: f.slice(3).join("|") }
                }
                root.themes = out
                root.themesProbed = true
            }
        }
    }

    // ── The scan: the machine itself ──────────────────────────────────────────
    // One read-only script (arch, network, a pacman lock, free disk, versions, the GPU and its driver, the
    // AUR helper, whether the Morph plugin is on disk). `parseScan` turns its lines into facts.
    property var scan: Plan.parseScan("")
    property bool scanned: false
    property Process _scan: Process {
        running: true
        command: ["bash", Quickshell.shellPath("scripts/setup-scan.sh")]
        stdout: StdioCollector {
            onStreamFinished: { root.scan = Plan.parseScan(text); root.scanned = true }
        }
    }

    function recheck() {
        root._scan.running = false
        root._scan.running = true
        root._bakProbe.running = false
        root._bakProbe.running = true

        root._rivalProbe.running = false
        root._rivalProbe.running = true

        root._themeProbe.running = false
        root._themeProbe.running = true

        root._probed = false
        root._probe.running = false
        root._probe.running = true

        root._pkgProbed = false
        root._pkgProbe.running = false
        root._pkgProbe.running = true

        root._optPkgProbe.stdout._pkgs = ({})
        root._optPkgProbe.stdout._installed = ({})
        root._optPkgProbe.running = false
        root._optPkgProbe.running = true

        root._packProbe.stdout._seen = ({})
        root._packProbe.stdout._pkgs = ({})
        root._packProbe.running = false
        root._packProbe.running = true
    }

    // ══ The plan ═════════════════════════════════════════════════════════════
    // Every probe above has answered (the scan, packages, Hyprland, app theming): before that the facts are
    // zeros and "everything is missing" would be a lie.
    readonly property bool ready: root.scanned && root._pkgProbed && root._probed && root.themesProbed

    // The facts setupplan.js plans from — the scan, the probes above, and what the services that own a feature say.
    readonly property var facts: ({
        arch: root.scan.arch, network: root.scan.network, pacmanLock: root.scan.pacmanLock,
        pacmanRunning: root.scan.pacmanRunning, diskMiB: root.scan.diskMiB, sudo: root.scan.sudo,
        // The shell's own agent counts: with it on, pkexec's dialog is drawn by the shell.
        polkitAgent: root.scan.polkitAgent || (Config.polkitAgent && AuthAgent.blocker() === ""),
        quickshell: root.scan.quickshell, hyprland: root.scan.hyprland, qt: root.scan.qt,
        gpu: root.scan.gpu, vulkan: root.scan.vulkan, nvidiaProprietary: root.scan.nvidiaProprietary,
        aurHelper: root.aurHelperReady ? root._aurHelper : root.scan.aurHelper,
        coreMissing: root.missingCore, pywal: root.pywalReady,
        blobInstalled: root.scan.blobInstalled, morph: Morph.available,
        hyprConfig: root._hyprConfig === "bundled" || root._hyprConfig === "minimal" || root._hyprConfig === "other"
                    ? root._hyprConfig : "absent",
        autostart: root._autostart, bindCount: root._bindCount,
        themes: root.themes, palette: Colors.fileState === "ok",
        optional: {
            wpe:       WallpaperEngine.blocker() === "" || root.optionalInstalled("wallpaperengine"),
            argos:     root.optionalInstalled("argostranslate"),
            songrec:   root.optionalInstalled("songrec") || SongRec.blocker(false) === "",
            spicetify: SpotifyBridge.spicetifyPresent,
            bridge:    SpotifyBridge.extensionPresent && SpotifyBridge.extensionEnabled,
            awww:      root.optionalInstalled("awww")
        },
        packs: root.packsInstalled, packPkgs: root.packPkgs
    })

    // How the shell is wired into Hyprland: left to the facts (your own config → one extra file; none → the bundle)
    // until you choose.
    property string hyprModeChoice: ""
    readonly property string hyprMode: root.hyprModeChoice !== "" ? root.hyprModeChoice : Plan.hyprMode(root.facts.hyprConfig)

    readonly property var steps:    Plan.catalogue(root.facts, root.hyprMode)
    readonly property var blockers: Plan.blockers(root.facts)
    readonly property var compat:   Plan.compat(root.facts)
    readonly property bool fatalBlock: root.blockers.some(b => b.level === "fatal")

    // The ticked steps: the recommended ones that are still to do, until somebody ticks one.
    property var  selectedIds: []
    property bool _selTouched: false
    readonly property var defaultIds: Plan.defaultSelection(root.steps)
    onDefaultIdsChanged: if (!root._selTouched) root.selectedIds = root.defaultIds.slice()
    readonly property var plan: Plan.buildPlan(root.steps, root.selectedIds)

    function isSelected(id) { return root.selectedIds.indexOf(id) >= 0 }
    function toggleStep(id) {
        root._selTouched = true
        const i = root.selectedIds.indexOf(id)
        root.selectedIds = i >= 0 ? root.selectedIds.filter(x => x !== id) : root.selectedIds.concat([id])
    }
    function selectRecommended() { root._selTouched = false; root.selectedIds = root.defaultIds.slice() }
    function selectNone() { root._selTouched = true; root.selectedIds = [] }
    function selectGroup(group, on) {
        root._selTouched = true
        const ids = root.steps.filter(x => x.group === group && (on ? x.state === "todo" : true)).map(x => x.id)
        root.selectedIds = on ? Array.from(new Set(root.selectedIds.concat(ids))) : root.selectedIds.filter(x => ids.indexOf(x) < 0)
    }

    // True when a polkit agent is up, so "no password" is an answer rather than a mistake.
    readonly property bool polkitReady: root.facts.polkitAgent

    // ── Running it ────────────────────────────────────────────────────────────
    // `run`: { active, done, items, current, polkit, started, ended, aborted }. `items` are the plan's steps with
    // a state each — queued | running | ok | failed | skipped — and, once finished, their last lines and what the
    // failure means. Replaced (never mutated) so a binding sees every change.
    property var run: ({ active: false, done: false, items: [], current: -1, polkit: false, started: 0, ended: 0, aborted: "" })
    readonly property bool planning: root.run.active
    property bool _polkit: false
    property string _planPw: ""
    property bool _stopAfter: false
    property bool _abortPw: false
    signal planFinished(bool allOk)

    // The steps worth a reload when they succeed: the plugin is loaded at start, the Hyprland files at its own reload.
    readonly property bool reloadNeeded: root.run.done && root.run.items.some(it => it.state === "ok" && (it.id === "blob" || it.id === "core"))

    function startPlan(password) {
        if (root.run.active || root.busy) return false
        const p = root.plan
        if (p.count === 0) return false
        const pw = password ?? ""
        if (p.root && pw === "" && !root.polkitReady) return false
        root._polkit = p.root && pw === ""
        root._planPw = pw
        root._stopAfter = false
        root._abortPw = false
        root.run = {
            active: true, done: false, current: -1, polkit: root._polkit, started: Date.now(), ended: 0, aborted: "",
            items: p.run.map(s => ({ id: s.id, title: s.title, jobs: s.jobs, deps: s.deps, auto: s.auto, root: s.root, eta: s.eta,
                                     state: "queued", job: 0, why: "", log: [], explain: null, startedAt: 0, endedAt: 0 }))
        }
        root._advance()
        return true
    }
    function stopAfterCurrent() { root._stopAfter = true }
    function clearRun() {
        if (root.run.active) return
        root.run = { active: false, done: false, items: [], current: -1, polkit: false, started: 0, ended: 0, aborted: "" }
        // Back to the recommended ticks: the finished steps were selected, and would run again.
        root.selectRecommended()
    }
    function selectOnly(ids) { root._selTouched = true; root.selectedIds = ids.slice() }

    function _setItem(i, patch) {
        const items = root.run.items.slice()
        items[i] = Object.assign({}, items[i], patch)
        root.run = Object.assign({}, root.run, { items: items })
    }
    function _finishPlan() {
        const ok = root.run.items.every(it => it.state === "ok" || it.state === "skipped")
                   && root.run.items.some(it => it.state === "ok") && !root.run.items.some(it => it.state === "failed")
        root.run = Object.assign({}, root.run, { active: false, done: true, current: -1, ended: Date.now() })
        root._planPw = ""
        root._polkit = false
        root._stopAfter = false
        root.recheck()
        root.planFinished(ok)
    }
    // The next queued step: skipped when something it needs did not finish, or you stopped; else started.
    function _advance() {
        const items = root.run.items
        const i = items.findIndex(it => it.state === "queued")
        if (i < 0) { root._finishPlan(); return }
        const it = items[i]
        if (root._stopAfter || root._abortPw) {
            root._setItem(i, { state: "skipped", why: root._abortPw ? "Stopped: the password wasn't accepted" : "Stopped by you" })
            root._advance()
            return
        }
        const lost = it.deps.map(d => items.find(x => x.id === d)).find(x => x && (x.state === "failed" || x.state === "skipped"))
        if (lost) {
            root._setItem(i, { state: "skipped", why: "Needs " + lost.title + ", which didn't finish" })
            root._advance()
            return
        }
        root.run = Object.assign({}, root.run, { current: i })
        root._setItem(i, { state: "running", job: 0, startedAt: Date.now() })
        root._startItemJob(i)
    }
    function _startItemJob(i) {
        const it = root.run.items[i]
        const id = it.jobs[it.job]
        if (id === "colours") { root._coloursJob(); return }
        if (!root.startJob(id, root._planPw))
            root._jobDone(false, [{ text: root.passwordNote !== "" ? root.passwordNote : "This step couldn't start.", err: true }])
    }
    // A job (or the colours pseudo-job) ended: the next job of this step, or the step's verdict, then the next step.
    function _jobDone(ok, lines) {
        const i = root.run.current
        if (!root.run.active || i < 0) return
        const it = root.run.items[i]
        const log = it.log.concat(lines.slice(-30)).slice(-60)
        if (!ok) {
            root._setItem(i, { state: "failed", log: log, endedAt: Date.now(),
                               explain: root._abortPw ? { title: "The password wasn't accepted", retry: true,
                                                          text: "Nothing was installed. Retype it (each wrong try counts toward a ten-minute sudo lockout)." }
                                                      : Plan.explainFailure(it.id, lines) })
            root._advance()
        } else if (it.job + 1 < it.jobs.length) {
            root._setItem(i, { job: it.job + 1, log: log })
            root._startItemJob(i)
        } else {
            root._setItem(i, { state: "ok", log: log, endedAt: Date.now() })
            root._advance()
        }
    }
    onPasswordRejected: root._abortPw = true
    onFinished: function (id, ok) {
        if (!root.run.active || root.run.current < 0 || root._waitingColours) return
        root._jobDone(ok, root.logLines)
    }

    // "Colours from your wallpaper" is not a process of ours: it is the wallpaper service's own palette extraction
    // (the same call its bootstrap makes when colors.json is missing).
    property bool _waitingColours: false
    function _coloursJob() {
        const why = Wallpaper.pywalBlocker() !== "" ? Wallpaper.pywalBlocker()
                  : !Config.wallTheming ? "Wallpaper theming is switched off (Settings › Wallpaper)."
                  : Wallpaper.currentPath === "" && !WallpaperEngine.running ? "No wallpaper has been applied yet — pick one in the Wallpaper panel, then run this again."
                  : ""
        if (why !== "") { root._jobDone(false, [{ text: why, err: true }]); return }
        root._waitingColours = true
        Wallpaper.reapplyPalette()
        if (!Wallpaper.runner.running) { root._waitingColours = false; root._jobDone(true, []) }
    }
    property Connections _coloursDone: Connections {
        target: Wallpaper.runner
        function onFinished(code) {
            if (!root._waitingColours) return
            root._waitingColours = false
            const ok = code === 0 && !Wallpaper.runner.failed
            root._jobDone(ok, ok ? [] : [{ text: "The palette extraction failed — the Wallpaper panel has the detail.", err: true }])
        }
    }

    // ══ Runner ═══════════════════════════════════════════════════════════════
    // One job at a time. Root comes from the panel's own password field, written
    // to the job's stdin and picked up by `sudo -S -p ''` — the same shape as
    // Updates and Storage, so there is one password box, not a stack of polkit
    // dialogs. `needsPassword(id)` says which jobs use it.

    property string runningId: ""
    property string lastId:    ""
    property bool   lastOk:    false
    // ── When sudo says no ─────────────────────────────────────────────────────
    // The guard against the ten-minute sudo lockout (a rejected password isn't sent
    // twice, nothing is sent while sudo is locked) lives in SudoProcess.
    readonly property string passwordNote: job.passwordNote
    signal passwordRejected()

    function needsPassword(id) {
        // A theme job asks only when its status said it installs a package or fixes
        // permissions; "all" when any of the ones it would run does.
        if (id === "theme-all")
            return root.themeIds.some(t => root.theme(t).state === "todo" && root.theme(t).sudo)
        if (id.indexOf("theme-") === 0) return root.theme(id.slice(6)).sudo
        return id === "core" || id === "blob" || id === "all" || id === "aur" || id === "aurhelper"
            || id === "wpe" || id === "argos" || id === "songrec" || id === "awww"
    }

    // Every line the job printed, { text, err }, for the live terminal. Capped —
    // an install is chatty and this is a settings card.
    property var logLines: []
    readonly property int _logCap: 800

    readonly property bool busy: root.runningId !== ""
    signal finished(string id, bool ok)

    function _append(line, err) {
        const next = root.logLines.concat([{ text: line, err: !!err }])
        root.logLines = next.length > root._logCap ? next.slice(-root._logCap) : next
    }

    function _run(id, argv, password) {
        if (root.busy || !id || !argv || argv.length === 0) return false
        // With polkit there is no password to ask for or guard: the system's dialog does both.
        const typed = root.needsPassword(id) && !root._polkit
        if (typed && !(password ?? "").length) return false
        // The theming script reads SETUP_ELEVATE to elevate through pkexec instead of reading a password.
        // The password goes in whenever one was given (a feature pack's job isn't in needsPassword but
        // needs it); with polkit the callers give none.
        if (!job.launch(argv, password ?? "", root._polkit ? ({ "SETUP_ELEVATE": "pkexec" }) : ({})))
            return false
        root.lastId    = ""
        root.logLines  = []
        root.runningId = id
        return true
    }

    function clearLog() { root.logLines = []; root.lastId = "" }

    property SudoProcess _job: SudoProcess {
        id: job
        onPasswordRejected: root.passwordRejected()

        stdout: SplitParser { onRead: line => root._append(line, false) }
        stderr: SplitParser { onRead: line => root._append(line, true) }
        onExited: function(code) {
            root.lastId    = root.runningId
            root.lastOk    = code === 0
            root.runningId = ""
            job.judge(code, root.logLines)
            root.recheck()
            // Jobs that install something a DIFFERENT service probes for itself —
            // this runner only re-checks its own core/pywal probe above. Without
            // this, SetupPage still shows "not installed" after a successful run
            // until something else happens to trigger that service's own reprobe.
            if (root.lastOk) {
                if (root.lastId === "spicetify" || root.lastId === "bridge"
                        || root.lastId === "theme-spotify" || root.lastId === "theme-all")
                    SpotifyBridge.recheckSetup()
                else if (root.lastId === "wpe")
                    WallpaperEngine.probe()
            }
            root.finished(root.lastId, root.lastOk)
        }
    }

    // ── The jobs ────────────────────────────────────────────────────────────
    readonly property string _blobScript: Quickshell.shellPath("scripts/build-blobs-plugin.sh")
    readonly property string _hyprScript:    Quickshell.shellPath("scripts/install-hypr-config.sh")
    readonly property string _hyprMinScript: Quickshell.shellPath("scripts/install-hypr-minimal.sh")
    readonly property string _autoScript:    Quickshell.shellPath("scripts/install-autostart.sh")

    // `set -e` so a rejected password stops the run instead of being buried under
    // whatever the next command prints. --core is run AS root (sudo -S), so the
    // script's inner `SUDO` array resolves to empty and pacman runs directly.
    function installCore(password) {
        if (root._polkit) return root._run("core", ["pkexec", "bash", root._depScript, "--core"], "")
        return root._run("core",
            ["bash", "-c", "set -e\nsudo -S -p '' bash " + root._shq(root._depScript) + " --core"],
            password)
    }
    // Builds as you; only `cmake --install` into the system Qt dir is elevated,
    // via --stdin-sudo (sudo -S). The password waits in stdin for that step.
    function buildBlob(password) {
        // No tty and no --stdin-sudo: the script's own rule picks pkexec for the install step.
        if (root._polkit) return root._run("blob", ["bash", "-lc", root._shq(root._blobScript)], "")
        return root._run("blob", ["bash", "-lc", root._shq(root._blobScript) + " --stdin-sudo"], password)
    }
    // One feature pack (install-dependencies.sh --pack <key>), elevated the way --core is.
    // The key goes into a command string, so it must be one the script printed.
    function installPack(key, password) {
        if (!/^[a-z]+$/.test(key) || !(key in root.packsInstalled)) return false
        const id = "pack-" + key
        if (root._polkit) return root._run(id, ["pkexec", "bash", root._depScript, "--pack", key], "")
        return root._run(id,
            ["bash", "-c", "set -e\nsudo -S -p '' bash " + root._shq(root._depScript) + " --pack " + key],
            password)
    }
    readonly property string _aurHelperScript: Quickshell.shellPath("scripts/install-aur-helper.sh")
    // An AUR helper, built as you; only the final pacman -U is root.
    function installAurHelper(password) {
        if (root._polkit) return root._run("aurhelper", ["bash", "-lc", root._shq(root._aurHelperScript)], "")
        return root._run("aurhelper", ["bash", "-lc", root._shq(root._aurHelperScript) + " --stdin-sudo"], password)
    }
    function installHypr()   { return root._run("hypr", ["bash", "-lc", root._shq(root._hyprScript) + " --force"]) }
    // No sudo — writes one file (quicktest.lua), never touches the rest of
    // ~/.config/hypr. See scripts/install-hypr-minimal.sh.
    function installHyprMinimal() {
        return root._run("hyprMin", ["bash", "-lc", root._shq(root._hyprMinScript) + " --force"])
    }
    function installAuto()   { return root._run("auto", ["bash", "-lc", root._shq(root._autoScript)]) }

    // ── Rebuild everything ──────────────────────────────────────────────────
    // Core packages, the blob plugin, the Hyprland config — in order, one job,
    // one password. For fixing a broken install. `$(cat)` slurps the one
    // password line off stdin (the panel closes stdin after writing it), then
    // each `sudo -S` gets its own copy. `set -e` stops at the first failure.
    // The Hyprland step backs the existing config up before replacing it.
    function rebuildAll(password) {
        const sh =
            'set -e\n'
          + 'PW="$(cat)"\n'
          + 'echo "== Core packages =="\n'
          + 'printf "%s\\n" "$PW" | sudo -S -p "" bash ' + root._shq(root._depScript) + ' --core\n'
          + 'echo "== Blob plugin =="\n'
          + 'printf "%s\\n" "$PW" | ' + root._shq(root._blobScript) + ' --stdin-sudo\n'
          + 'echo "== Hyprland config =="\n'
          + root._shq(root._hyprScript) + ' --force\n'
          + 'echo "== Rebuild complete — reload the shell =="\n'
        return root._run("all", ["bash", "-c", sh], password)
    }

    // ── Spotify bridge (Spicetify) ──────────────────────────────────────────
    // Two independent steps, matching SpotifyBridge.setupBlocker()'s own order —
    // installing the client patcher needs root; wiring the extension into it
    // doesn't. Kept apart rather than one combined job so a machine that already
    // has spicetify-cli (a normal case) only ever needs the second.
    //
    // spicetify-cli is NOT in the official repos (AUR only), so a `pacman -S` fails
    // for everyone. Spicetify's own recommended route is a user-level
    // install into ~/.spicetify — no root, any distro — which theme-setup.sh does.
    // `password` is unused; kept so callers needn't change.
    function installSpicetify(password) {
        return root._run("spicetify", ["bash", root._themeScript, "spicetify"])
    }

    // ── Theming jobs ────────────────────────────────────────────────────────
    function setupTheme(id, password) {
        return root._run("theme-" + id, ["bash", root._themeScript, id], password)
    }
    function setupAllThemes(password) {
        return root._run("theme-all", ["bash", root._themeScript, "all"], password)
    }

    // No sudo: copies the extension this repo ships at spicetify/Extensions/ into
    // Spicetify's own userdata dir, configures it, and applies — the three steps
    // a user would otherwise do by hand from copy-paste commands.
    readonly property string _bridgeExtSrc:
        Quickshell.shellPath("spicetify/Extensions/quickshell-bridge.js")
    function enableSpotifyBridge() {
        const sh =
            'set -e\n'
          + 'command -v spicetify >/dev/null 2>&1 || { echo "spicetify is not installed yet" >&2; exit 1; }\n'
          + 'd="$(spicetify path userdata)"\n'
          + '[ -n "$d" ] || { echo "spicetify path userdata returned nothing" >&2; exit 1; }\n'
          + 'mkdir -p "$d/Extensions"\n'
          + 'cp ' + root._shq(root._bridgeExtSrc) + ' "$d/Extensions/quickshell-bridge.js"\n'
          + 'spicetify config extensions quickshell-bridge.js\n'
          + 'spicetify apply\n'
        return root._run("bridge", ["bash", "-c", sh])
    }

    // ── One optional AUR package ────────────────────────────────────────────
    // Same sudo-priming shape as installAur below, for a single package picked by
    // the caller — Wallpaper Engine and the lyrics-translation backend both use
    // this rather than each growing their own copy of the yay/paru dance.
    function installOptionalAur(id, pkg, password) {
        const h = root._aurHelper === "paru" ? "paru" : "yay"
        // polkit: the helper asks pkexec for its one elevated step; typed: a primed sudo timestamp.
        const el = root._polkit ? "--sudo pkexec" : "--sudoloop"
        const flags = h === "paru" ? "--skipreview " + el
                                   : "--answerdiff None --answerclean None --answeredit None " + el
        return root._run(id,
            ["bash", "-c",
               "set -e\n"
             + (root._polkit ? "" : "sudo -S -v -p ''\n")
             + "exec " + h + " " + flags + " -S --needed --noconfirm " + root._shq(pkg)],
            password)
    }

    // ── AUR packages ────────────────────────────────────────────────────────
    // python-pywal16 (theming). No icon font: the icons are
    // bundled in assets/fonts/ (see Tokens).
    // Mirrors install-dependencies.sh's AUR_PKGS (quickshell itself is in [extra] now).
    readonly property var _aurPkgs:
        ["python-pywal16"]

    // The copy-paste fallback, for when no helper is installed (it can't be
    // bootstrapped from here — yay/paru are themselves AUR builds).
    readonly property string aurLine:
        root.aurHelper + " -S --needed " + root._aurPkgs.join(" ")

    // ── Run the AUR install from the panel ──────────────────────────────────
    // The old objection — "makepkg refuses to run as root" — only bites if you
    // try to run the WHOLE thing elevated. yay/paru run as YOU and elevate only
    // the final `pacman -U`. `sudo -S -v` primes the credential cache from the
    // one password line on stdin (same no-tty namespace as installCore, so the
    // helper's own sudo reuses it); `--sudoloop` keeps it warm through a long
    // build; the answer flags make review non-interactive. `set -e` aborts on a
    // rejected password before the helper prints anything.
    function installAur(password) {
        const h = root._aurHelper === "paru" ? "paru" : "yay"
        const flags = h === "paru"
            ? "--skipreview --sudoloop"
            : "--answerdiff None --answerclean None --answeredit None --sudoloop"
        const pkgs = root._aurPkgs.map(root._shq).join(" ")
        const el = root._polkit ? "--sudo pkexec" : "--sudoloop"
        const fl = h === "paru" ? "--skipreview " + el
                                : "--answerdiff None --answerclean None --answeredit None " + el
        return root._run("aur",
            ["bash", "-c",
               "set -e\n"
             + (root._polkit ? "" : "sudo -S -v -p ''\n")
             + "exec " + h + " " + fl + " -S --needed --noconfirm " + pkgs],
            password)
    }

    // ── The way back, and what has drifted ────────────────────────────────────
    // Backups the Hyprland step made (scripts/restore-hypr-config.sh --list): [{ kind: "dir"|"file", path, epoch }],
    // newest first. "dir" is a whole ~/.config/hypr, "file" an earlier quicktest.lua. Restoring sets what is there
    // aside instead of deleting it.
    readonly property string _restoreScript: Quickshell.shellPath("scripts/restore-hypr-config.sh")
    property var hyprBackups: []
    readonly property var hyprDirBackups: root.hyprBackups.filter(b => b.kind === "dir")
    property Process _bakProbe: Process {
        running: true
        command: ["bash", root._restoreScript, "--list"]
        stdout: StdioCollector {
            onStreamFinished: root.hyprBackups = text.split("\n").filter(l => l.trim() !== "").map(function (l) {
                const p = l.split("|")
                return { kind: p[0], path: p[1], epoch: parseInt(p[2], 10) || 0 }
            })
        }
    }
    function restoreHypr(path) {
        return root._run("hyprRestore", ["bash", root._restoreScript, "--restore"].concat(path ? [path] : []))
    }
    function restoreHyprMinimal() {
        return root._run("hyprRestoreMin", ["bash", root._restoreScript, "--restore-minimal"])
    }

    // What has drifted since setup (setupplan.js health): a plugin that stopped loading, another notification daemon,
    // nothing starting the shell… Most urgent first. The welcome page lists them; each links to the page that fixes it.
    readonly property var healthIssues: Plan.health(root.facts, {
        rivalNotifiers: root.rivalNotifiers, rivalBars: root.rivalBars, rivalAgents: root.rivalAgents,
        polkitConfig: Config.polkitAgent, barBlur: root._barBlur, barOpacity: Config.barOpacity
    })

    // A report to paste into a bug report: the machine, the plan, how each step ended, a failure's last lines.
    // The home directory is shown as "~" (setupplan.js formatReport), and no secret is in it.
    function reportText() {
        return Plan.formatReport(root.facts, root.run, {
            home: (Quickshell.env("HOME") || ""), now: Date.now(), polkit: root.run.polkit
        })
    }
    function copyReport() { Clipboard.copyText(root.reportText()) }

    // ── Starting a job by its id ──────────────────────────────────────────────
    // The one place a job id means a function (it was a switch in the wizard's QML). `colours` is not here: it
    // is the colour service's apply, started by the plan runner.
    function startJob(id, password) {
        switch (id) {
        case "core":      return root.installCore(password)
        case "aurhelper": return root.installAurHelper(password)
        case "aur":       return root.installAur(password)
        case "blob":      return root.buildBlob(password)
        case "hypr":      return root.installHypr()
        case "hyprMin":   return root.installHyprMinimal()
        case "auto":      return root.installAuto()
        case "spicetify": return root.installSpicetify(password)
        case "bridge":    return root.enableSpotifyBridge()
        case "wpe":       return root.installOptionalAur("wpe", root.optionalPkg("wallpaperengine", "linux-wallpaperengine"), password)
        case "argos":     return root.installOptionalAur("argos", root.optionalPkg("argostranslate", "python-argostranslate"), password)
        case "songrec":   return root.installOptionalAur("songrec", root.optionalPkg("songrec", "songrec"), password)
        case "awww":      return root.installOptionalAur("awww", root.optionalPkg("awww", "awww"), password)
        case "theme-all": return root.setupAllThemes(password)
        }
        if (id.indexOf("theme-") === 0) return root.setupTheme(id.slice(6), password)
        if (id.indexOf("pack-") === 0)  return root.installPack(id.slice(5), password)
        return false
    }

    // ── States and counts, for diagnosing ─────────────────────────────────────
    //     qs ipc -c ~/.config/quicktest call setup status
    IpcHandler {
        target: "setup"
        function status(): string {
            return JSON.stringify({
                ready: root.ready, blockers: root.blockers.map(b => b.id), mode: root.hyprMode,
                todo: root.steps.filter(x => x.state === "todo").map(x => x.id),
                blocked: root.steps.filter(x => x.state === "blocked").map(x => x.id),
                selected: root.selectedIds, plan: root.plan.run.map(x => x.id), planRoot: root.plan.root,
                polkitReady: root.polkitReady, running: root.run.active, health: root.healthIssues.map(h => h.id),
                backups: root.hyprBackups.length,
                items: root.run.items.map(x => x.id + ":" + x.state)
            })
        }
    }
}
