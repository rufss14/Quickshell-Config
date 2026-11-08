pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../config"

// ── Greet ─────────────────────────────────────────────────────────────────────
// The login conversation, as a state machine. Drives scripts/greetd-ipc.py and
// exposes "what should the greeter be showing right now" — no UI in this file.
//
// Same split as Lock: the policy and the system integration live in a service, the
// surface lives in modules/greet/. Where Lock is a thin POLICY object because the
// PAM conversation belongs to the lock surface itself, this one is the opposite —
// the conversation is the whole job, and the surface just draws it.
//
// ── This is not the lock screen, and the difference is structural ─────────────
// LockScreen holds a PamContext and authenticates directly, because it runs AS you
// and is only ever proving that you are still there. A greeter cannot do that: it
// runs as the unprivileged `greeter` user, before any session exists, and has no
// business holding a PAM handle for an account it does not own. greetd is the thing
// with that privilege. So this asks greetd, greetd runs PAM, and the prompts come
// back over a socket. The shape of the conversation is identical (prompt → answer →
// success or failure); the mechanism has nothing in common.
//
// ── The conversation, and why there is a queue ───────────────────────────────
// greetd is STRICTLY request/response: one reply per request, in order, no
// unsolicited events. That sounds like it removes the need for any bookkeeping, and
// it very nearly does — except that `{"e":"ok"}` is the reply to four different
// requests and means something different after each one. "Authentication succeeded"
// and "the failed session was cleaned up" arrive as the same event.
//
// So `_awaiting` records what each outstanding reply is FOR. It is a queue rather
// than a single slot because a cancel can be sent while a reply is still in flight,
// and mis-pairing those two would take a wrong password straight into start_session.
//
// ── What must never happen ───────────────────────────────────────────────────
// A greeter that hangs is a machine you cannot log into. Every path out of `busy`
// is therefore driven by an event from the helper, and the helper reports its own
// death (`fatal`) rather than going quiet — a lost connection puts this into
// "fatal" with a reason on screen, not into a spinner that never stops.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ══ What the surface reads ════════════════════════════════════════════════
    //
    //   "starting"  helper launching; greetd has not said hello yet
    //   "idle"      connected, no session open — ready to take a password
    //   "prompt"    greetd asked something this service cannot answer by itself
    //   "busy"      waiting on greetd
    //   "launching" authenticated; greetd is starting the session
    //   "done"      the session is up; this process is about to be replaced
    //   "fatal"     no greetd, or the connection died. Nothing will work.
    //
    // Named `phase` rather than `state` because `state` is taken on anything that
    // ends up parented to an Item, and a silently-shadowed state machine is not a
    // debugging session anyone wants to have at a login screen.
    readonly property string phase: root._phase
    property string _phase: "starting"

    // True exactly when a password can usefully be submitted.
    readonly property bool ready: root._phase === "idle" || root._phase === "prompt"

    // One line of feedback, mirroring the lock screen's single notice line.
    property string notice: ""
    property bool   noticeIsError: false
    property int    attempts: 0

    // What to put in the box, and whether to mask it. For an ordinary password stack
    // this is "Password" and true, from first frame to last — but a stack with a
    // fingerprint or an OTP module in it will ask for other things, by name, and the
    // box should say what it is asking for rather than lying about it.
    property string promptText:   "Password"
    property bool   promptSecret: true

    // ── Design mode ───────────────────────────────────────────────────────────
    // Running greet.qml in your own session is how the greeter gets DESIGNED, and
    // there is no greetd there to talk to. That is a first-class state rather than
    // an error: the surface draws itself completely and the box refuses to submit,
    // saying why. Distinguished from a real failure (`fatal` with a socket present)
    // because those need opposite reactions — one is Tuesday afternoon, the other is
    // a machine nobody can log into.
    //
    // `|| ""` is load-bearing, not defensive noise. Quickshell.env returns a QVariant,
    // and an UNSET variable comes back as `undefined` — not "". So the obvious
    // `Quickshell.env("GREETD_SOCK") !== ""` is `undefined !== ""`, which is TRUE, and
    // the greeter concludes it is running under greetd precisely when it is not. That
    // is the exact inversion this property exists to prevent, and it cost a preview
    // that showed a real error instead of a preview banner.
    readonly property bool underGreetd: (Quickshell.env("GREETD_SOCK") || "") !== ""
    readonly property bool demoMode: !root.underGreetd

    // ══ The bundle ════════════════════════════════════════════════════════════
    // Everything the greeter needs to know about YOU, exported from your session into
    // the greeter's own home. Written by scripts/greet-export.sh; absent until that
    // has run, which is a perfectly good state — the greeter falls back to a probed
    // username, the palette's own colour, and a monogram.
    //
    // ── Why a bundle rather than exporting config.json ────────────────────────
    // The greeter is a DIFFERENT process, run as a different user, with a different
    // home. Handing it your whole config would mean every setting in this shell
    // becoming something a login screen might act on — and the greeter has no
    // settings page to correct any of it from, because nobody has authenticated yet.
    // Three fields, written deliberately, is the entire contract.
    //
    // Read from $XDG_CACHE_HOME rather than a hardcoded /var/lib/greeter, so the same
    // file is found when greet.qml is run in your own session for design work.
    //
    // Same `||` idiom as Clipboard and Updates, and for the same reason as underGreetd
    // above: an unset XDG_CACHE_HOME is `undefined`, so a `!== ""` test takes the wrong
    // branch and builds the literal path "undefined/quickshell-greet/greet.json". The
    // bundle then silently never loads — no backdrop, no avatar, no exported user — and
    // nothing anywhere reports an error, because a missing bundle is a legitimate state.
    readonly property string bundlePath:
        (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
        + "/quickshell-greet/greet.json"

    // The wallpaper, as an absolute path in the GREETER's filesystem — a copy, not a
    // pointer into your home. /home is not world-readable on a normal install, and a
    // greeter that reads out of it either fails or means you have loosened permissions
    // on your own files to make a login screen prettier.
    property string backdrop: ""
    property string avatar:   ""
    property string _bundleUser: ""

    // ══ Ambient facts the greeter is allowed to state ═════════════════════════
    // Read straight out of /proc. All three files are world-readable, so none of this
    // needs a session, a bus, or any privilege the greeter does not already have.
    property string hostName: ""
    property string kernel:   ""

    // Uptime is stored as the moment the machine BOOTED, not as a duration. A duration
    // would need a timer to keep it honest; an epoch is read once and stays true, and
    // the card derives the difference against a clock it already has for other reasons.
    property double bootEpoch: 0

    // ══ One probe, not three ══════════════════════════════════════════════════
    // Who can log in, what they can log into, and what machine this is — all answered
    // by a single `sh`. It was three separate Processes, which on a surface whose whole
    // job is to appear quickly meant three fork/execs of a shell before the first
    // frame, for three questions that are each about a hundred microseconds of work.
    //
    // Two things inside it are also deliberately fork-free:
    //
    //   · `read h < /proc/…` instead of `$(cat /proc/…)` — the builtin, no process.
    //   · ONE `awk` over every .desktop file instead of grep×2 + sed×3 + head×3 per
    //     file. That was roughly eight processes per session entry to read four
    //     `Key=value` lines out of it.
    //
    // The awk tracks file boundaries with FNR==1 rather than gawk's ENDFILE, which is
    // an extension mawk does not have and this config ships to other people's machines.
    property Process _probe: Process {
        running: true
        command: ["sh", "-c",
            // ── People ────────────────────────────────────────────────────────
            // uid 1000–65533 is the login range on every distro this config targets;
            // 65534 is `nobody`. The shell test separates a person from a service
            // account that happens to have a high uid.
            "getent passwd | awk -F: '$3>=1000 && $3<65534 && $7 !~ /(nologin|false|sync)$/ "
          + "{ print \"USER=\" $1 }'; "

            // ── This machine ──────────────────────────────────────────────────
          + "read h < /proc/sys/kernel/hostname  && printf 'HOST=%s\\n'   \"$h\"; "
          + "read k < /proc/sys/kernel/osrelease && printf 'KERNEL=%s\\n' \"$k\"; "
          + "read u < /proc/uptime               && printf 'UPTIME=%s\\n' \"${u%% *}\"; "

            // ── Sessions ──────────────────────────────────────────────────────
            // Built as a positional list first so a missing directory cannot leave an
            // unexpanded glob for awk to choke on.
          + "set --; "
          + "for d in /usr/share/wayland-sessions /usr/share/xsessions; do "
          + "  [ -d \"$d\" ] || continue; "
          + "  for f in \"$d\"/*.desktop; do [ -r \"$f\" ] && set -- \"$@\" \"$f\"; done; "
          + "done; "
          + "[ $# -gt 0 ] && awk '"
          + "function emit() { if (f != \"\" && e != \"\" && hid == 0) "
          + "  printf \"SESSION=%s\\t%s\\t%s\\t%s\\t%s\\n\", t, (n != \"\" ? n : f), e, d, f } "
          + "FNR==1 { emit(); f=FILENAME; n=\"\"; e=\"\"; d=\"\"; hid=0; "
          + "         t=(FILENAME ~ /xsessions/) ? \"x11\" : \"wayland\" } "
          + "/^Name=/          { if (n==\"\") n=substr($0,6) } "
          + "/^Exec=/          { if (e==\"\") e=substr($0,6) } "
          + "/^DesktopNames=/  { if (d==\"\") d=substr($0,14) } "
          + "/^Hidden=true/    { hid=1 } "
          + "/^NoDisplay=true/ { hid=1 } "
          + "END { emit() }' \"$@\""]

        stdout: StdioCollector {
            onStreamFinished: {
                const names = []
                const found = []

                for (const line of text.split("\n")) {
                    const eq = line.indexOf("=")
                    if (eq < 0) continue
                    const key = line.substring(0, eq)
                    const val = line.substring(eq + 1)

                    if (key === "USER")   { names.push(val.trim()); continue }
                    if (key === "HOST")   { root.hostName = val.trim(); continue }
                    if (key === "KERNEL") { root.kernel   = val.trim(); continue }
                    if (key === "UPTIME") {
                        root.bootEpoch = Date.now() - parseFloat(val) * 1000
                        continue
                    }
                    if (key === "SESSION") {
                        const p = val.split("\t")
                        if (p.length < 5) continue
                        found.push({ type: p[0], name: p[1], exec: p[2],
                                     desktopNames: p[3], file: p[4] })
                    }
                }

                root.users       = names
                root._probedUser = names.length === 1 ? names[0] : ""
                root.sessions    = found
                root.mark("probe done — " + names.length + " user(s), "
                           + found.length + " session(s)")
            }
        }
    }

    // "3 days, 4h" / "4h 12m" / "6m". Called by the card against its own ticking clock,
    // so this service runs no timer of its own — same rule as Discord.durationText().
    function uptimeText(now) {
        if (root.bootEpoch <= 0) return ""
        const s = Math.max(0, Math.floor((now - root.bootEpoch) / 1000))
        const d = Math.floor(s / 86400)
        const h = Math.floor((s % 86400) / 3600)
        const m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + (d === 1 ? " day, " : " days, ") + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    // ══ Caps Lock ═════════════════════════════════════════════════════════════
    // The single most useful thing a login screen can tell you, and the one failure it
    // can explain before you have wasted three attempts on it.
    //
    // ── Read from the LED, because nothing else will say ──────────────────────
    // Qt does not expose Caps Lock state: it is not in a key event's modifiers, and
    // there is no QML property for it. The kernel does though — every keyboard gets a
    // /sys/class/leds/<input>::capslock/brightness, world-readable, 0 or 1. Several of
    // them on a machine with several keyboards, hence the OR across the glob.
    //
    // ── One long-lived shell, not a process per tick ──────────────────────────
    // sysfs LED attributes do not deliver inotify events, so this has to be polled —
    // but polling by respawning a Process three times a second on a LOGIN SCREEN would
    // be an absurd thing to do. One `sh` lives for the greeter's lifetime and prints a
    // line only when the state actually CHANGES, so the QML side sees an event stream
    // and does no work at all while nothing is happening.
    property bool capsLock: false

    // ── `read` and not `cat`, and it is not a micro-optimisation ──────────────
    // `v=$(cat "$f")` forks and execs a process PER FILE PER TICK. With four keyboards
    // at 0.3s that is thirteen processes a second, for as long as the login screen is
    // up, to answer a question whose answer is almost always "no".
    //
    // `read v < "$f"` is a shell BUILTIN — no fork, no exec, just an open and a read.
    // Measured here over 200 iterations of the same four files: 638ms with cat, 24ms
    // with read. Twenty-six times cheaper, and the loop now costs approximately nothing
    // between state changes.
    property Process _capsProbe: Process {
        running: true
        command: ["sh", "-c",
            "prev=; while :; do v=0; "
          + "for f in /sys/class/leds/*capslock/brightness; do "
          + "  [ -r \"$f\" ] || continue; "
          + "  read x < \"$f\" 2>/dev/null || continue; "
          + "  [ \"$x\" != \"0\" ] && v=1; "
          + "done; "
          + "[ \"$v\" != \"$prev\" ] && { printf '%s\\n' \"$v\"; prev=$v; }; "
          + "sleep 0.3; done"]
        stdout: SplitParser {
            onRead: function(line) { root.capsLock = line.trim() === "1" }
        }
    }

    // ══ Timing ════════════════════════════════════════════════════════════════
    // Milestones, to stderr, with a delta from when the greeter started. This exists
    // because a login that takes five seconds is invisible from the outside: greetd
    // logs create_session and then nothing at all until the session switches, and the
    // greeter's own output dies with its session unless the wrapper redirects it.
    //
    // Cheap enough to leave in permanently — a handful of lines per login, only ever on
    // the path that ends in a session starting.
    property double _t0: Date.now()
    function mark(what) {
        console.log("Greet [+" + Math.round(Date.now() - root._t0) + "ms] " + what)
    }

    FileView {
        id: bundleFile
        path: root.bundlePath
        // FileView is lazy; without this it does not read until something asks, and
        // the first thing that asks is a binding that has already resolved to "".
        preload: true
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(bundleFile.text())
                root.backdrop    = v.backdrop ?? ""
                root.avatar      = v.avatar   ?? ""
                root._bundleUser = v.user     ?? ""

                // ── Weather goes into Config, not into a property here ────────
                // services/Weather.qml reads Config.weatherLat/Lon/Place directly, and
                // gates its fetch on `hasLocation`, which is itself bound to
                // Config.weatherPlace. So there is no override to set from outside —
                // the only way to give the greeter a location is to put it where the
                // service already looks.
                //
                // The greeter's Config is otherwise entirely defaults (no config.json
                // is exported, deliberately), so this is not clobbering a preference
                // anybody set. Assigning it does trip Config's own _writePrefs(), which
                // writes to the GREETER's state directory — a file that user owns, in
                // its own home, and a harmless cache of the export.
                if ((v.weatherPlace ?? "") !== "") {
                    Config.weatherPlace  = v.weatherPlace
                    Config.weatherLat    = v.weatherLat   ?? 0
                    Config.weatherLon    = v.weatherLon   ?? 0
                    Config.weatherMetric = v.weatherMetric ?? true
                }
            } catch (e) {
                console.warn("Greet: greet.json is not valid JSON —", e)
            }
        }
        // Not an error worth shouting about: no bundle is the state before the export
        // has ever been run, and everything downstream has a fallback.
        onLoadFailed: function(error) {
            console.log("Greet: no bundle at", root.bundlePath, "—", error)
        }
    }

    // ══ Who is logging in ═════════════════════════════════════════════════════
    // Config, then the bundle, then the single obvious human account on the machine.
    //
    // Config comes first even though the greeter will almost never have one — it is
    // what makes greet.qml behave identically when run in YOUR session for design
    // work, where Config is real and the bundle may not exist.
    //
    // "Obvious" is doing real work in that last fallback: uid in the login range, and
    // a shell that is not a refusal. If that turns up exactly one name it is not a
    // guess, it is the answer. If it turns up several, this service will not pick for
    // you — `userName` stays empty, and the surface says so rather than sending
    // greetd a username nobody has.
    readonly property string userName: Config.greetUser !== "" ? Config.greetUser
                                     : root._bundleUser  !== "" ? root._bundleUser
                                     :                            root._probedUser
    property string _probedUser: ""
    // Every candidate, so the surface can say "which of these?" rather than just
    // failing on a multi-user machine.
    property var users: []

    // ══ What gets started ═════════════════════════════════════════════════════
    // The desktop entries under /usr/share/{wayland-sessions,xsessions}, which is
    // where every display manager looks and therefore the only list that agrees with
    // what the rest of the system thinks is installed. Read rather than hardcoded:
    // this config ships to people who do not run Hyprland from the same path, or at
    // all.
    //
    // Each entry: { type, name, exec, desktopNames, file }.
    property var sessions: []

    // The chosen one. Config names a FILE rather than an index, because an index is
    // a promise about the order of a directory listing that nobody made.
    readonly property var session: {
        if (root.sessions.length === 0) return null
        if (Config.greetSession !== "") {
            for (let i = 0; i < root.sessions.length; i++)
                if (root.sessions[i].file === Config.greetSession) return root.sessions[i]
        }
        return root.sessions[0]
    }

    // Exec, split into an argv for greetd — which execs the command directly and so
    // needs a real vector, not a string.
    //
    // Whitespace splitting, plus the desktop spec's `%f %u %U %i %c %k` field codes
    // dropped. Those codes are for launching an application against a file; a session
    // entry has no file to be launched against, and passing `%U` through to exec would
    // hand the compositor a literal argument it does not understand. Quoted arguments
    // are not handled, and no session entry in the wild has one.
    function _argv(exec) {
        return exec.split(/\s+/)
                   .filter(a => a !== "" && !/^%[fFuUdDnNickvm]$/.test(a))
    }

    // The environment greetd should put the session in. greetd and PAM set the rest
    // (XDG_RUNTIME_DIR, the seat, the vt); these three are the display manager's own
    // job, and things downstream — portals picking a backend, toolkits picking a
    // theme, `loginctl show-session` — read them.
    function _env(s) {
        const env = ["XDG_SESSION_TYPE=" + s.type]
        if (s.desktopNames !== "") env.push("XDG_CURRENT_DESKTOP=" + s.desktopNames)
        const base = s.file.split("/").pop().replace(/\.desktop$/, "")
        env.push("XDG_SESSION_DESKTOP=" + base)
        return env
    }

    // ══ The helper ════════════════════════════════════════════════════════════
    property Process _proc: Process {
        running: true
        command: ["python3", Quickshell.shellPath("scripts/greetd-ipc.py")]
        stdinEnabled: true

        stdout: SplitParser { onRead: function(line) { root._ingest(line) } }

        // Diagnostics only — the helper's header is explicit that secrets never go
        // here. Same treatment as the Discord helper: console, not UI, because
        // `notice` already carries everything a person can act on.
        stderr: SplitParser { onRead: function(line) { console.log("Greet:", line) } }

        onExited: function(code) {
            // Three ways to get here, and only one of them is news.
            //
            //   · `done` — greetd started the session, and this whole process is
            //     moments from being replaced. Expected.
            //   · `fatal` — the helper ALREADY said why it is stopping, and this exit
            //     is the consequence of that, not a second problem. Overwriting the
            //     reason here would replace the one useful sentence on the screen with
            //     a generic one; the case that actually bit was previewing greet.qml
            //     outside greetd, where "GREETD_SOCK is not set" got clobbered by "the
            //     login helper stopped unexpectedly" a tick later.
            //   · anything else — it died without saying why, which is worth reporting.
            //
            // Note the helper exits 0 on a reported fatal ON PURPOSE (not running under
            // greetd is a state, not a crash), so the exit CODE cannot be used to tell
            // these apart. The phase can.
            if (root._phase === "done" || root._phase === "fatal") return
            root._fail(code === 0 ? "The login helper stopped unexpectedly."
                                  : "The login helper exited (" + code + ").")
        }
    }

    // ── Request/reply bookkeeping ─────────────────────────────────────────────
    // See the header: `ok` alone does not say what succeeded.
    property var _awaiting: []
    // The answer the user typed, held only until greetd asks for it. Cleared the
    // instant it is spent — same rule as LockScreen's `pending`, for the same reason.
    property string _answer: ""

    function _send(obj, tag) {
        if (!root._proc.running) return
        root._awaiting = root._awaiting.concat([tag])
        root._proc.write(JSON.stringify(obj) + "\n")
    }

    // ══ What the surface calls ════════════════════════════════════════════════

    // The one entry point. Whether this opens the session or answers a prompt inside
    // one is this service's problem, not the box's — the surface has a text field and
    // an Enter key, and that is the whole of its involvement.
    function submit(text) {
        if (!root.ready) return

        root.notice = ""
        root.noticeIsError = false

        if (root._phase === "prompt") {
            root._phase = "busy"
            root._send({ c: "reply", response: text }, "reply")
            return
        }

        if (root.userName === "") {
            root._reject("Nobody to log in as — set the user in Settings → Lock.")
            return
        }

        // Held rather than sent: create_session does not carry a password. greetd
        // opens the PAM conversation and PAM then ASKS, and the answer goes back in
        // the reply to that question.
        root._answer = text
        root._phase  = "busy"
        root.mark("password submitted → create_session")
        root._send({ c: "auth", user: root.userName }, "auth")
    }

    // Abandon a half-open session. Also the recovery path after a failure — greetd
    // will not accept a fresh create_session while a broken one is still open.
    function cancel() {
        root._answer = ""
        root._send({ c: "cancel" }, "cancel")
    }

    // ══ Events from the helper ════════════════════════════════════════════════
    function _ingest(line) {
        let msg
        try {
            msg = JSON.parse(line)
        } catch (e) {
            console.warn("Greet: unparseable line from helper:", line.substring(0, 120))
            return
        }

        // Neither of these is a reply to anything, so neither touches the queue.
        if (msg.e === "ready") {
            root._phase = "idle"
            return
        }
        if (msg.e === "fatal") {
            root._fail(msg.text ?? "The connection to greetd was lost.")
            return
        }

        const tag = root._awaiting.length > 0 ? root._awaiting[0] : ""
        root._awaiting = root._awaiting.slice(1)

        if (msg.e === "prompt")     root._onPrompt(tag, msg)
        else if (msg.e === "ok")    root._onOk(tag)
        else if (msg.e === "error") root._onError(tag, msg)
    }

    function _onPrompt(tag, msg) {
        // `info` and `error` carry no question. They still need acknowledging — PAM's
        // conversation does not move on until every message is answered — but the
        // reply deliberately carries no `response` field at all; see the helper.
        if (msg.kind === "info" || msg.kind === "error") {
            root.notice = msg.text ?? ""
            root.noticeIsError = (msg.kind === "error")
            root._send({ c: "reply" }, "reply")
            return
        }

        // A real question. If it is the one we already have an answer for, answer it
        // and never show it — the user typed their password once and should not be
        // asked for it again a frame later.
        if (root._answer !== "") {
            const answer = root._answer
            root._answer = ""
            root._send({ c: "reply", response: answer }, "reply")
            return
        }

        // Anything else — a second factor, a token, an expired-password change — gets
        // asked out loud, with PAM's own wording. Trimmed of its trailing ": " so it
        // reads as a label rather than a fragment of a terminal.
        root.promptText   = (msg.text ?? "").replace(/:\s*$/, "") || "Password"
        root.promptSecret = msg.kind !== "visible"
        root._phase = "prompt"
    }

    function _onOk(tag) {
        if (tag === "cancel") {
            // The failed attempt has been cleaned up. NOW a new one can start.
            root._phase = "idle"
            root.promptText = "Password"
            root.promptSecret = true
            return
        }

        if (tag === "start") {
            root._phase = "done"
            root.mark("start_session accepted — greetd is now waiting on US to exit")

            // ── Get out of the way, immediately ───────────────────────────────
            // greetd does NOT start your session until the greeter's session ends. It
            // has already accepted start_session at this point and is doing nothing but
            // waiting for this process to go away — so every millisecond spent here is
            // added directly to how long the login takes.
            //
            // Measured on this machine, from the journal: sysc-greet took 0.24–0.58s
            // from create_session to the user session opening. This greeter took
            // 5.18–5.94s, and the entire difference was greetd waiting on a greeter that
            // had latched `done` and then just sat there until it got killed.
            //
            // Exiting the COMPOSITOR rather than this process, because that is the thing
            // whose lifetime greetd is actually watching: greet-session.lua runs
            // scripts/greet-run.sh, which runs `qs` and then dispatches `hl.dsp.exit()`,
            // so killing Quickshell alone would still leave Hyprland to shut down
            // afterwards. One step instead of two, and it is the same call the wrapper
            // makes on the other path.
            //
            // Fired unconditionally rather than behind a `Config.motionEnabled`-style
            // grace period: there is no animation worth 5 seconds of your morning.
            //
            // ── SIGTERM to our own pid, and nothing cleverer ──────────────────
            // Two earlier attempts failed, and the instrumented log is what settled it:
            //
            //   · `hyprctl dispatch exit` via execDetached — no measurable effect
            //     (5.94s before, 5.22s after). Never verified to reach a socket. Likely
            //     explained since: that is the legacy spelling, and under the Lua config
            //     manager a bare `exit` is not a dispatcher (see Hypr.exitSession).
            //   · `Qt.quit()` — provably a no-op here. The mark placed immediately
            //     after it printed, so the process was still running.
            //
            // What the log DID establish is the shape of the problem: "asking the
            // session to end" at +4750ms, teardown at +9760ms — 5.01 seconds, which is
            // a fixed timeout, not a slow shutdown. greetd waits five seconds for the
            // greeter to leave of its own accord and then force-kills it. Every login
            // was paying that timeout in full.
            //
            // Measured separately against a bare `ShellRoot {}` instance: Quickshell
            // exits on SIGTERM in 104ms. It does not ignore the signal — nothing had
            // ever actually sent it one. `Quickshell.processId` gives us our own pid, so
            // this is simply that signal, and the wrapper's `hl.dsp.exit()` dispatch
            // takes the compositor down behind us — the same shape sysc-greet used, and
            // sysc-greet logged in in 0.24s.
            root.mark("SIGTERM → self (pid " + Quickshell.processId + ")")
            Quickshell.execDetached(["kill", "-TERM", String(Quickshell.processId)])
            return
        }

        // Authentication succeeded. Everything from here is launching, which can still
        // fail on its own terms — a session entry naming a binary that is not there.
        const s = root.session
        if (!s) {
            root._reject("No session to start — nothing in /usr/share/wayland-sessions.")
            return
        }

        root.mark("authenticated → start_session")
        root._phase = "launching"
        root._send({ c: "start", cmd: root._argv(s.exec), env: root._env(s) }, "start")
    }

    function _onError(tag, msg) {
        // A cancel that itself failed leaves nothing to clean up and nothing to say.
        // Going back to idle is the only useful move; greetd will refuse the next
        // create_session if it really is still wedged, and that error gets shown.
        if (tag === "cancel") {
            root._phase = "idle"
            return
        }

        // `auth` is a wrong password; `other` is a broken stack. Kept apart because
        // they need different reactions from the person standing there — one is a
        // typo, the other is a machine that needs a TTY and a text editor.
        const text = msg.text ?? ""
        root._reject(msg.kind === "auth"
            ? (text || "Incorrect password.")
            : ("Login is unavailable: " + (text || "PAM refused to start.")))
    }

    // A failed attempt. greetd's session is left half-open by the failure, so the
    // cancel is not optional housekeeping — without it every subsequent attempt is
    // refused, and the greeter reads as having locked you out after one typo.
    function _reject(message) {
        root._answer = ""
        root.attempts++
        root.notice = message
        root.noticeIsError = true
        root._phase = "busy"
        root._send({ c: "cancel" }, "cancel")
        rejected()
    }

    // For the surface's shake. A signal rather than a property the surface watches,
    // because two identical rejections in a row have to produce two shakes.
    signal rejected()

    // Unrecoverable. No cancel, no retry: whatever this is, it is not fixable from
    // inside a greeter, and pretending otherwise means a password box that silently
    // does nothing.
    function _fail(reason) {
        root._phase = "fatal"
        root._answer = ""
        root._awaiting = []

        // In demo mode there is no failure to report. "GREETD_SOCK is not set" is the
        // DEFINITION of previewing this outside greetd, the surface already carries a
        // banner saying exactly that in calmer words, and a red error line under the
        // box repeating it reads as two separate things having gone wrong.
        if (root.demoMode) return

        root.notice = reason
        root.noticeIsError = true
    }
}
