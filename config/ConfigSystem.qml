import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue
// ConfigSystem — part of Config, split out of Config.qml by area (2026-11-08). The parts form
// one inheritance chain (ConfigShell ← ConfigEdges ← ConfigBarLayout ← ConfigSystem ←
// ConfigDesktop ← Config), so every property still lives on the one `Config` singleton
// and nothing that reads `Config.x` changed. A name declared further down the chain is
// reached as `root.x` here (a base file can't see it statically; `root` is the same object).
ConfigBarLayout {
    id: root

    // ══ Motion ════════════════════════════════════════════════════════════════
    // Motion.qml reads these, which is the one place the dependency runs this way
    // round. Tokens must never import Config because the tokens ARE the defaults; but
    // duration is different — the effective duration genuinely is the designed one
    // scaled by a preference, and there is no other place that could live without every
    // Behavior in the shell multiplying it by hand.
    //
    // Config still doesn't import Motion, so there's no cycle: the numbers below are
    // plain literals, not derived from the design system.
    property real motionScale: 1.0        // 0.5 = twice as fast, 2.0 = half speed
    property bool motionEnabled: true     // false ⇒ every duration collapses to 0
    // Reduced motion (2026-11-08): between "full" and "off". Fades and state changes stay;
    // overshoot, parallax, drift, the colour wave and other ambient movement go. Read through
    // Motion.reduced / Motion.ambientOn, never directly. Deliberately NOT in a bar preset's
    // snapshot: it is an accessibility choice, not part of how a bar looks.
    property bool motionReduced: false
    property bool barHoverGrow:  true     // a desktop widget's grow-on-hover (WidgetFrame)

    // ── Launcher ──────────────────────────────────────────────────────────────
    // The terminal the launcher's `>` command mode runs a command in. "" means "work
    // it out": $TERMINAL first, then the fallback below. Resolved in exactly ONE
    // place (the Terminal service), never written back — baking this
    // machine's terminal into a published config is the thing that rule exists for.
    property string launcherTerminal: ""
    readonly property string launcherTerminalFallback: "kitty"

    // Where the launcher's `?` web-search mode sends a query. "%s" is the query,
    // URL-encoded. A property rather than a literal because the whole point of a
    // published config is that someone else's search engine is not this one.
    property string webSearchUrl: "https://duckduckgo.com/?q=%s"
    property string webSearchName: "DuckDuckGo"

    // ── What the launcher answers, and how much of it (Settings › Launcher) ──
    // Rows shown before the list scrolls: the card is a search box, not a menu, so the
    // ceiling is low by default (3–8).
    property int  launcherRows: 5
    // The things beyond apps. Each is a kind of result or a mode the launcher has; off, the
    // launcher simply doesn't offer it — an action row, a setting row, a sum, `+`.
    property bool launcherActions:  true      // shell actions ("night light", "game mode"…)
    property bool launcherSettings: true      // rows that open a settings page
    property bool launcherCalc:     true      // sums and unit conversions
    property bool launcherPackages: true      // `+` installs a package
    property bool launcherClipboard: true     // `;` searches the clipboard history
    property bool launcherEmoji:    true      // `:` finds an emoji and copies it
    // `yt cats` → YouTube's search for "cats": { key, name, url } with %s for the query. Cleaned
    // (http(s) only, a typable key) by launcher.js cleanShortcuts before anything uses it. A
    // starting set, not a path, so a literal default is right here; Settings › Launcher edits it.
    readonly property var webShortcutDefaults: [
        { key: "yt",  name: "YouTube",   url: "https://www.youtube.com/results?search_query=%s" },
        { key: "gh",  name: "GitHub",    url: "https://github.com/search?q=%s" },
        { key: "w",   name: "Wikipedia", url: "https://en.wikipedia.org/w/index.php?search=%s" },
        { key: "map", name: "Maps",      url: "https://www.openstreetmap.org/search?query=%s" },
        { key: "aur", name: "AUR",       url: "https://aur.archlinux.org/packages?K=%s" }
    ]
    property var launcherWebShortcuts: root.webShortcutDefaults
    // The AUR half of `+` sends the longest word typed to aur.archlinux.org. Off keeps `+` to
    // the synced repos on this machine.
    property bool launcherAur:      true
    // Frecency: what you launch rises. Off, ranking is match quality alone, and nothing new
    // is written to launcher-history.json.
    property bool launcherLearn:    true

    // ── The launcher's `?` mode: ask an AI ────────────────────────────────────
    // Which provider answers. The API key is NOT here and never will be: it lives in
    // ai-keys.json, written 0600 by scripts/ai-credentials.py, because config.json is
    // written by the running shell and forked by anyone who clones this repo.
    //   gemini · openai (ChatGPT) · anthropic (Claude) · xai (Grok)
    //   claudecode (Claude Pro, via the CLI — no key) · gemini · anthropic ·
    //   openai (ChatGPT) · xai (Grok) · ollama (a model on this machine)
    // "ollama" by default since 2026-10-24 (the user): free, private, nothing leaves the machine.
    // Until it's set up (services/LocalAi — the overview's Ask page walks you through it) the
    // launcher's `?` falls back to a web search, as with any provider that isn't ready.
    property string aiProvider: "ollama"

    // "" means the provider's default in scripts/ai-ask.py. Model names get retired
    // faster than anything else in this file, so this is the knob to reach for when a
    // provider starts answering 404 — not a code change.
    // On the Claude Pro path "" means "haiku" — cheapest against a subscription's limits (a CLI
    // alias there, not an API model id). On the local one, a pulled model's tag ("qwen3:4b"); ""
    // = the first one pulled. Switching provider in the overview's Ask page clears it.
    property string aiModel: ""

    // The panel is a few hundred pixels tall. This is a ceiling on the reply, not a
    // target; ai-ask.py also asks for at most four short sentences.
    property int aiMaxTokens: 600

    // false ⇒ `?` hands the query to the browser as a plain web search instead. The
    // prompt is the explicit act (you typed `?` and pressed Enter), so this is
    // opt-OUT — but it exists because "my launcher talks to a company" is a thing
    // someone forking this config is entitled to switch off in one place.
    property bool aiEnabled: true

    // Let the model run a web search before answering. This is what stops "what is the
    // latest X" coming back as whatever was true when the model was trained — a date in
    // the prompt only stops it MISDATING what it already knows. Gemini only for now;
    // the other providers ignore it. It costs a round trip, and the query reaches the
    // search backend as well as the model, which is why it is a flag.
    property bool aiGrounding: true

    // Claude's thinking depth: "" | low | medium | high | xhigh | max. Sent as
    // output_config.effort, and ONLY when non-empty — Haiku 4.5 (the default Claude
    // model here) rejects the parameter outright, so an unconditional "low" would 400
    // every request. Set this together with a model that supports it.
    // "low" by default, which the Claude Code CLI accepts on every model. It is only
    // sent to the ANTHROPIC HTTP provider when non-empty there — Haiku 4.5 rejects the
    // API's output_config.effort outright — so switching to that provider means
    // clearing this or picking a model that takes it.
    property string aiEffort: "low"

    // The local provider's address (Ollama's server root; a trailing /v1 is fine). "" = its own
    // default, http://localhost:11434 — resolved in scripts/ai-ask.py and scripts/local-ai.py.
    property string aiLocalUrl: ""
    // Start `ollama serve` when the shell starts, if the local AI is the one in use and installed.
    property bool aiLocalAutostart: true
    // What the overview's AI was asked to remember ("I like warm colours") — short notes, at most 20,
    // sent with every turn (services/Assistant, the `remember`/`forget` actions).
    property var aiMemory: []
    // "Hey Claude" (services/VoiceAssistant): listen for the wake phrase and take a spoken request.
    // Off by default — it keeps the microphone open the whole time it's on (locally; nothing leaves).
    property bool aiVoice: false
    // The phrases that wake it, comma-separated. Every word must be one the speech model knows.
    property string aiWakeWords: "hey claude, okay claude"

    // ── The overview's left face (OverviewFeed) ───────────────────────────────
    // Which page it was left on: 0 What's changed · 1 Ask (the AI) · 2 News. The AI is the
    // default because it is the one that sends nothing anywhere until you type — News fetches
    // as soon as it is shown.
    property int overviewFeedPage: 1
    // The overview's extra panels (the four corner cards, the Ask / News / Changes face and the notification centre)
    // are folded away until asked for: a first look is the workspaces, the search and what is playing. The "More" chip
    // in the overview's top right turns it, and the choice is kept.
    property bool overviewMore: false
    // News (services/News): "local" (your country's top stories) · "world" · "technology" ·
    // "science" · "business" · "sports" · "entertainment" · "health".
    property string newsTopic: "local"
    // Two letters (PT, US…). "" = the weather location's country (Config.weatherCountry), then
    // the system locale's — never an IP lookup. Resolved in News only.
    property string newsCountry: ""
    // Pictures for the top stories (scripts/news-fetch.py --images): each one's publisher page is
    // fetched once for its og:image, which that site sees, like a browser preview.
    property bool newsImages: true
    // The newest patch notes you've seen (OverviewFeed's "What's changed"): versions after this one
    // wear "New". "" = none yet, so a first install shows the current notes as new.
    property string changelogSeen: ""

    readonly property real motionScaleMin: 0.25
    readonly property real motionScaleMax: 2.0

    function resetMotion() {
        root.motionScale   = 1.0
        root.motionEnabled = true
        root.motionReduced = false
        root.barHoverGrow  = true
    }

    // ══ Sound ═════════════════════════════════════════════════════════════════
    // The desktop spectrum behind your windows (modules/panels/CavaBG.qml).
    //
    // This lived in UiState as `cavaBgOpen`, which was the wrong home: UiState answers
    // "what is the shell showing right now" and holds nothing across a restart, so the
    // background silently switched itself off on every login. It's a preference — you
    // turn it on because you want it, not for the current session — so it belongs here,
    // where things are written to disk.
    // Battery saver (services/PowerSaver): "auto" rests the costly ambient effects while
    // on battery, "on"/"off" force it. Costs a machine without a battery nothing.
    property string powerSaver: "auto"
    property bool cavaBg: false

    // Which renderer CavaBG draws: "bars" | "wave" | "dots" | "ring" (2026-10-31: the spectrum
    // as spokes round the screen's middle). See modules/panels/CavaBG.qml for what each one is.
    property string cavaBgStyle: "bars"

    // How tall a full-level bar/wave/dot-column gets, as a multiple of the 180px
    // baseline — replaces what used to be a hardcoded ceiling in CavaBG.qml with
    // something you can actually turn up.
    property real cavaBgIntensity: 1.0

    // Its colours (2026-10-31). First one colour and a "fade to"; then the user: "its
    // configuration should allow me to set it as more colors from the scheme" — picked: BLEND
    // SEVERAL. `cavaBgBlend` is 1–5 colours in order (`cavaBgColors` ids: a scheme colour by
    // name through Colors.role, or "album", the cover's accent); `cavaBgBlendDir` lays them
    // "across" (left to right; round the ring, mirrored) or "up" (base to tips; the circle
    // out). Restored through `_loadCavaBlend`, which also turns an older config's
    // `cavaBgColor`/`cavaBgColor2` into a blend ("palette" was the ramp across).
    // `cavaBgOpacity` is how solid it is.
    property var    cavaBgBlend: ["ramp3"]
    property string cavaBgBlendDir: "across"
    readonly property int cavaBgBlendMax: 5
    property real   cavaBgOpacity: 1.0
    // The same round (the user's picks, 2026-10-31). `cavaBgMusicOnly`: the playing player's own
    // stream, so a call or a notification doesn't move it. `cavaBgPeaks`: a cap over each bar
    // that holds, then falls. `cavaBgGlow`: a soft light round the bars, in their colour.
    // `cavaBgRingCover`: the album cover inside the ring.
    property bool   cavaBgMusicOnly: true
    property bool   cavaBgPeaks: false
    property bool   cavaBgGlow: false
    property bool   cavaBgRingCover: true
    // Every colour of the scheme worth drawing with, and the cover's.
    readonly property var cavaBgColors: [
        { id: "primary", label: "Primary" },
        { id: "focus",   label: "Focus"   },
        { id: "vivid",   label: "Vivid"   },
        { id: "primaryContainer", label: "Tonal" },
        { id: "ramp1",   label: "Scheme 1" },
        { id: "ramp2",   label: "Scheme 2" },
        { id: "ramp3",   label: "Scheme 3" },
        { id: "ramp4",   label: "Scheme 4" },
        { id: "ramp5",   label: "Scheme 5" },
        { id: "ramp9",   label: "Scheme 6" },
        { id: "fg",      label: "Text"    },
        { id: "album",   label: "Album"   }
    ]
    // The whole scheme across, the old "Palette" choice.
    readonly property var cavaBgWholeScheme: ["ramp1", "ramp2", "ramp3", "ramp4", "ramp5"]
    // A blend as stored, made safe: known ids only, no repeats, 1..cavaBgBlendMax of them. A
    // config file is not trusted to hold a list of names.
    function cavaBlendClean(list) {
        const known = root.cavaBgColors.map(c => c.id)
        const out = []
        for (const id of (Array.isArray(list) ? list : []))
            if (typeof id === "string" && known.includes(id) && !out.includes(id) && out.length < root.cavaBgBlendMax)
                out.push(id)
        return out.length > 0 ? out : ["ramp3"]
    }
    function _loadCavaBlend(v) {
        if (v.cavaBgBlend !== undefined) { root.cavaBgBlend = root.cavaBlendClean(v.cavaBgBlend); return }
        if (v.cavaBgColor === undefined) return
        if (v.cavaBgColor === "palette") {
            root.cavaBgBlend = root.cavaBgWholeScheme
            root.cavaBgBlendDir = "across"
        } else {
            // The old fade ran from the base to the tips.
            root.cavaBgBlend = root.cavaBlendClean([v.cavaBgColor, v.cavaBgColor2 || ""])
            if (root.cavaBgBlend.length > 1) root.cavaBgBlendDir = "up"
        }
    }

    // ── Sound effects (services/Sfx) ──────────────────────────────────────────
    // Off by default: a published shell must not make noise the first time it starts.
    // `sfxEnabled` is the master; the three below it are the groups, each its own
    // switch so you can keep the swooshes and drop the typing. Volume is the master
    // level, 0..1 — each sound is already levelled by scripts/gen-sfx.py — and each group
    // has its own level under it (1 = as designed; the two multiply, see sfx.js).
    property bool sfxEnabled: false
    property real sfxVolume:  0.5
    property bool sfxPanels:   true     // a swoosh as a panel / overlay opens and closes
    property bool sfxTyping:   true     // key sounds in the shell's own text fields
    property bool sfxSwitches: true     // a blip when a switch flips
    property bool sfxNotify:   true     // a chime when a notification arrives
    property bool sfxAlerts:   true     // a timer finishing, an alarm going off
    property bool sfxCapture:  true     // a screenshot taken, a clip saved
    // Typing sounds: "shell" = the shell's own text fields; "all" = every key you type in
    // any app, heard through a Hyprland Lua hook (services/SfxKeys). A class of key is read,
    // never which one.
    property string sfxTypingScope:  "shell"
    property real sfxPanelsVolume:   1.0
    property real sfxTypingVolume:   1.0
    property real sfxSwitchesVolume: 1.0
    property real sfxNotifyVolume:   1.0
    property real sfxAlertsVolume:   1.0
    property real sfxCaptureVolume:  1.0

    // ══ Game mode ═════════════════════════════════════════════════════════════
    // One switch — the bar pill, SUPER+G, the Gaming panel, or the `gamemode` IPC —
    // flips several things at once for the length of a play session. Each of those
    // things is individually opt-out here; that is what the Gaming panel edits.
    //
    // None of these is the mode's OWN state (that's transient and lives in
    // services/Gamemode.qml, deliberately not persisted). These are preferences about
    // what the mode should DO when you turn it on, so they belong on disk.
    property bool gamemodeSession:    true   // hold a `gamemoderun` session — lets the
                                             // system gamemoded set the CPU governor,
                                             // GPU performance level and renice
    property bool gamemodeQuiet:      true   // silence notifications while it's on
    property bool gamemodeIdle:       true   // keep the screen awake
    property bool gamemodeWallpaper:  true   // stop the live wallpaper scene
    property bool gamemodeVisualizer: true   // hide the desktop audio visualiser
    property bool gamemodeKeys:       true   // no typing sounds for other apps' keys (a
                                             // game's WASD is not typing)

    // WHEN it turns on, rather than what it does: also while a `gamemoderun` game is
    // registered with gamemoded (and off again when it leaves, if it came on that way).
    // On by default because the trigger has no false positives — only a game launched
    // through gamemode registers; fullscreen video never does. See services/Gamemode.qml.
    property bool gamemodeAuto:       true

    // The three opt-ins (2026-11-07), all OFF by default — each reaches past the shell:
    //   gamemodeSteam       a window of class `steam_app_<id>` also counts as "a game" for the follow
    //                       trigger, so a Steam game needs no `gamemoderun` launch option. The old rule
    //                       was "never follow a fullscreen window"; this follows a CLASS, not a
    //                       fullscreen — a video player or browser never wears it.
    //   gamemodeClips       keep the Clips replay buffer running while the mode is on (Clips.wantBuffer
    //                       reads Gamemode.holdsClips; Config.clipsBuffer is never written).
    //   gamemodeCompositor  blur, shadows and animations off in Hyprland while it is on; put back from
    //                       a snapshot on exit (services/gamemodefx.js).
    property bool gamemodeSteam:      false
    property bool gamemodeClips:      false
    property bool gamemodeCompositor: false

    function resetGamemode() {
        root.gamemodeSession = root.gamemodeQuiet = root.gamemodeIdle
            = root.gamemodeWallpaper = root.gamemodeVisualizer = root.gamemodeKeys
            = root.gamemodeAuto = true
        root.gamemodeSteam = root.gamemodeClips = root.gamemodeCompositor = false
    }

    // ══ On-screen display ═════════════════════════════════════════════════════
    // The overlay that answers a media key: volume, mute, mic mute. See services/Osd.qml
    // for why it observes Pipewire rather than needing its own keybinds — and why
    // brightness is deliberately not part of it.
    property bool osdEnabled: true

    // How long it stays before fading. Short: it is an acknowledgement, not a
    // notification, and it appears while you are looking at something else. Floored at
    // 400ms by the surface, because below that the fade-in has not finished before the
    // fade-out starts and the thing just flickers.
    property int osdMs: 1600

    // ══ Bluetooth ═════════════════════════════════════════════════════════════
    // services/Bt + services/BtBridge (scripts/bt-helper.py). See CLAUDE.md "Bluetooth".
    //
    // The pairing agent: answers BlueZ's "does this code match?" / "type the PIN"
    // by asking you in the Bluetooth panel. On by default — without an agent a
    // phone or keyboard can't pair at all. Off for someone who runs their own
    // (blueman-applet), since only one agent can be the default.
    property bool btAgent: true
    // An OSD when a device connects or disconnects — its glyph, name and battery.
    property bool btConnectOsd: true
    // A notification when a device's battery crosses btBatteryLow, and again at
    // half that. Once per threshold per discharge (bt.js batteryAlert).
    property bool btBatteryWarn: true
    property int  btBatteryLow: 20            // percent
    readonly property int btBatteryLowMin: 5
    readonly property int btBatteryLowMax: 50
    // A thin ring around the bar pill's icon: the lowest battery among connected
    // devices that report one.
    property bool btPillBattery: true
    // Which controller the shell talks to, as its D-Bus path (Bt.adapter resolves it).
    // "" follows whatever BlueZ calls the default. The path is machine-specific, so
    // it is never a literal default: it's picked in Settings → Bluetooth, and a path
    // that vanishes (an unplugged dongle) falls back to the default by itself.
    property string btAdapter: ""

    // ══ Lock screen ═══════════════════════════════════════════════════════════
    // See services/Lock.qml for the safety reasoning behind the defaults; the short
    // version is that a lockscreen which fails leaves you locked OUT, so auto-lock is
    // opt-in rather than opt-out.
    property bool lockIdleEnabled: false        // OFF until you have proven unlocking works
    property int  lockIdleMinutes: 10
    // Lock right before suspend / hibernate (logind's PrepareForSleep). ON by default,
    // unlike the idle timer: waking a laptop to an unlocked session is the hole every
    // desktop closes, and it doesn't fire while you're at the machine. services/Lock.qml.
    property bool lockOnSleep: true

    // The PAM service the lock authenticates against — a FILE in /etc/pam.d.
    //
    // A property rather than a literal because this is the one part of the lockscreen
    // that is not portable. "login" exists on every Arch install and on essentially
    // every Linux, which is why it is the default and why this config ships without
    // requiring anyone to create /etc/pam.d/quickshell first. But a distro with a
    // restrictive login stack (or a user who wants fingerprint auth on the lock and
    // not on the console) needs to point this somewhere else, and editing QML to do
    // that would be worse than a setting.
    property string lockPamConfig: "login"

    // ── What the lock is allowed to show ──────────────────────────────────────
    // Both default ON because both are things you can already read off the desktop
    // this lock is covering, and neither is a control — the media card can skip a
    // track, which is the ceiling for what an unauthenticated person may do.
    //
    // They are settings rather than fixed choices because "what is on my screen while
    // I am away from it" is genuinely personal: a lock in an office shows your music
    // taste and your unread count to everyone who walks past, and the answer to that
    // is a switch, not a lecture in a comment.
    property bool lockShowMedia: true
    // The COUNT only, never a summary or a body — see LockScreen for why the line is
    // drawn exactly there.
    property bool lockShowNotifications: true

    // Log out / Restart / Shut down on the lock's left edge. ON, because someone at the
    // keyboard can already cut the power at the case — but it is a switch because "log
    // out" is the one with teeth: it discards unsaved work in every window behind the
    // lock, and it is reachable by someone who could not get past the password.
    property bool lockShowPower: true

    // The overview's brightness sliders and the desktop's audio spectrum, on the lock.
    // `lockShowCava` is deliberately NOT `cavaBg`: the desktop visualizer competes with
    // your windows and this one competes with nothing, so wanting it in exactly one of
    // the two places is an ordinary preference rather than a contradiction.
    property bool lockShowBrightness: true
    property bool lockShowCava: true
    property bool lockShowStats: true
    property bool lockShowCalendar: true
    // Only ever visible while a call is actually up — an empty call bar on a lockscreen
    // is a widget advertising that you use Discord.
    property bool lockShowDiscord: true

    // ── Lyrics on YouTube ─────────────────────────────────────────────────────
    // OFF by default because the lookup is keyed on artist and title, and YouTube hands
    // MPRIS the VIDEO title ("Artist - Song (Official Music Video) [4K]", a one-hour mix,
    // a stream) with the channel as the artist. That either misses or — worse — matches a
    // different song and scrolls confident wrong words in time with your music. Spotify
    // and friends give real metadata and are unaffected either way.
    property bool lockLyricsOnYouTube: false

    // ── Lyrics motion ─────────────────────────────────────────────────────────
    // How strongly the lyrics card animates, 0 (still) … 1 (full). It scales AMPLITUDES
    // only — travel, glow, the size of the pop. Timings stay keyed to the vocal, because
    // a quieter setting should be calmer, not late: slow the attack down and the motion
    // stops landing on the word it belongs to, which reads as broken rather than subtle.
    //
    // Default 1. The effect is the point of the card, and this is the way back out.
    property real lyricsMotion: 1.0

    // ── Lyrics translation ────────────────────────────────────────────────────
    // A translated line under each lyric. OFF by default, and that default is deliberate
    // rather than cautious: the backend may be `translate-shell`, which sends each line of
    // the track TO GOOGLE. Nothing identifying the listener goes with it and there is no
    // account involved, but the text does leave the machine — and this config is published,
    // so it must not be something a stranger switches on without knowing.
    //
    // Installing argos-translate takes precedence automatically and keeps everything local.
    // See scripts/lyrics-translate.py for the backend order.
    // ── The fallback provider ─────────────────────────────────────────────────
    // On, the shell looks lyrics up itself (NetEase, then LRCLIB) whenever the Spotify
    // bridge has nothing for a track. Off, the bridge is the ONLY source: no track
    // metadata leaves the machine from this shell, and a song the bridge cannot answer
    // simply has no lyrics.
    //
    // Worth switching off for two quite different reasons. The fallback is word- or
    // line-level where the bridge is per-syllable, so a track it answers "successfully"
    // can be a visible downgrade; and it is an outbound request carrying artist, title
    // and album on every new track.
    property bool   lyricsFallback: true

    // ══ The Spotify bridge's own process lifetime ════════════════════════════
    // Off by default: the listener is a normal child of Quickshell, tied to its
    // lifetime — a reload kills it and the next shell start spawns a fresh one. That
    // was itself the fix for a worse bug (see scripts/spotify-bridge.py's
    // die_with_parent doc): an unsupervised listener left running past its shell
    // held the port forever and the NEXT shell could not bind.
    //
    // On, it survives a reload instead: scripts/spotify-bridge-run.sh launches it
    // detached (setsid, reparented to init — the same shape scripts/update-run.sh
    // uses for a live pacman transaction), and the shell reattaches by tailing its
    // log rather than owning its stdout directly. A flock is what makes this safe to
    // flip on repeatedly or across multiple shell starts — a second launch attempt
    // against an already-running listener is a silent no-op, never a second bind.
    //
    // Worth it if a reload dropping the playhead mid-song (until the extension's next
    // ~20s heartbeat re-anchors it) is more annoying than it is rare.
    property bool   spotifyBridgeDetached: false

    property bool   lyricsTranslate: false

    // Target language as a two-letter code. The source is detected from the writing
    // system; a track already in this language is left alone rather than round-tripped.
    property string lyricsTranslateLang: "en"

    // ── Translation backends, in priority order ───────────────────────────────
    // scripts/lyrics-translate.py tries these in the order given and takes the
    // first that answers; an id left out of the list is never contacted. The
    // default is every backend, local-first: "argos" (argostranslate, on-device,
    // nothing leaves the machine), then "deepl" (documented API, needs a key),
    // then "google" and "mymemory" (public endpoints, no key). Reorder or prune
    // it from the Now Playing panel's settings — e.g. drop "google"/"mymemory" to
    // keep every line on DeepL, or lead with "deepl" when its quality matters
    // more than keeping the text on the machine. An empty list falls back to the
    // full default rather than disabling translation — the master toggle does that.
    property var    lyricsTranslateBackends: ["argos", "deepl", "google", "mymemory"]

    // Keep translated tracks on disk (XDG_CACHE_HOME/quickshell/lyrics-translate,
    // seven days, keyed by the lines and the language pair — not by which backend
    // produced them) so replaying a song this week costs nothing and, in
    // particular, spends none of a metered DeepL quota. Off re-translates every
    // play; only worth it while comparing a different backend or model.
    property bool   lyricsTranslateCache: true

    // ── Romanization: a song written in another script, in Latin letters ──────────────
    // scripts/lyrics-romanize.py. The Now Playing toggle appears only on a song that has
    // something to romanize (services/romanize.js), and this is what it flips: the lyric is
    // then shown in Latin letters IN PLACE of its own script, lit syllable by syllable
    // (services/romajialign.js). Off by default
    // for the reason translation is: with `lyricsRomanizeOnline` on, each line is sent to
    // Google's public endpoint, and this config is published.
    property bool   lyricsRomanize: false
    // Google first (the best at kanji), a local library when installed as the fallback. Off
    // keeps every line on this machine: only the local library is tried, and the toggle says
    // what to install when there is none.
    property bool   lyricsRomanizeOnline: true
    // Keep a romanized song on disk (XDG_CACHE_HOME/quickshell/lyrics-romanize, keyed by the
    // lines — not by which backend answered): a Google answer for a month, an on-device one for a
    // day. Replaying a song then costs no request at all, which matters because Google counts
    // them. Off romanizes every play; only worth it while comparing backends.
    property bool   lyricsRomanizeCache: true

    // ── The profile picture ───────────────────────────────────────────────────
    // An absolute path, or "" for "look in the usual places" (~/.face, ~/.face.icon,
    // /var/lib/AccountsService/icons/<user>) and fall back to the monogram.
    //
    // A POINTER rather than a copy: setting this does not write to ~/.face or touch
    // AccountsService. Choosing a picture in a shell's settings should not quietly
    // change what your display manager and every other app show you as — that is a
    // system-wide identity, and this is a lockscreen preference.
    property string lockAvatar: ""

    // ── What the lock draws behind everything ─────────────────────────────────
    //   "auto"   the running Wallpaper Engine scene's preview, else the still wallpaper
    //   "image"  always the still wallpaper, even while a scene is running
    //   "none"   no picture — the palette's own colour and the vignette
    //
    // "auto" matches what is actually on the desktop, which is what it is for. The catch
    // is that a Workshop preview is a ~224px, ~4-second loop (measured) — all Wallpaper
    // Engine publishes — so the lock blurs it hard enough that the resolution stops
    // showing. "image" is the escape hatch for preferring a sharp 4K still over a
    // faithful one; see LockScreen for the full reasoning.
    property string lockBackdrop: "auto"

    // Play the scene preview, or hold its first frame. ON, because a moving backdrop is
    // the point of matching a scene — but a ~4-second loop is a ~4-second loop, and the
    // only thing that removes a loop rather than disguising it is not looping. With the
    // slow drift the lock applies over the top, a held frame still moves; it just never
    // repeats. Turn this off if the loop bothers you more than the stillness does.
    property bool lockSceneAnimate: true

    // ══ The greeter ═══════════════════════════════════════════════════════════
    // Settings for greet.qml — the login screen, which is a SEPARATE Quickshell
    // process run by greetd as the `greeter` user. It reads a copy of this file
    // exported into the greeter's own home, because /home is not world-readable and
    // the greeter has no business in yours.
    //
    // Which is why these live here rather than in a greeter-only file: the greeter
    // cannot present a settings page (there is nowhere to save it to, and nobody has
    // authenticated yet), so every choice about it is made from YOUR session and
    // exported. Changing one and not re-exporting changes nothing.

    // Who the password box logs in as. "" means "the single human account on this
    // machine", which is right on every single-user install and refuses to guess on
    // any other — see Greet.userName.
    property string greetUser: ""

    // Which desktop entry under /usr/share/{wayland-sessions,xsessions} to start, by
    // absolute path. "" means the first one found.
    //
    // A PATH rather than an index or a name: an index is a promise about the order of
    // a directory listing that nobody made, and a name changes when a package
    // rewords its .desktop file. The path is the thing that either exists or does not,
    // and Greet falls back to the first session when it does not.
    property string greetSession: ""

    // ══ Wallpaper engine ══════════════════════════════════════════════════════
    // Options for the linux-wallpaperengine renderer (Settings → Wallpaper).
    //
    // These exist as preferences because the renderer has NO IPC — every one of them
    // is a startup argument, so the only way to have them survive is to own the launch
    // and rebuild the command from stored values. See services/WallpaperEngine.qml.
    //
    // Which workshop item to restore. The service reads what's ACTUALLY running from
    // the live process instead of trusting this — the user can start the renderer by
    // hand — so this is the restore value, not a claim about the current state.
    property string wpeCurrent: ""
    // Start the wallpaper when the shell does. Off by default: something else may
    // already be launching it, and two renderers fight over the same layer surface.
    property bool wpeAutoStart: false

    // 60 rather than the monitor's refresh rate. A wallpaper is the least important
    // thing on screen and the frame rate is pure GPU cost; raise it if you want it.
    property int  wpeFps: 60
    // ── V-Sync ────────────────────────────────────────────────────────────────
    // linux-wallpaperengine (r627) has NO vsync flag — checked against --help, not
    // assumed. But vsync for an OpenGL program is a DRIVER setting, not an app one,
    // and both driver stacks honour an environment variable: `vblank_mode` (Mesa,
    // for AMD/Intel) and `__GL_SYNC_TO_VBLANK` (NVIDIA). On: the launch prepends
    // both, forcing the renderer to sync to the display and cutting tearing. Off:
    // nothing is set, so the driver keeps its own default — today's behaviour, so
    // false changes nothing for an untouched config.
    property bool wpeVsync: false
    // ── Which monitor the scene renders on ────────────────────────────────────
    // "" = every screen (one --screen-root each); otherwise a single screen name.
    // Rendering on ONE screen is also the fix for scenes whose audio doubles across
    // a multi-monitor setup — one scene instance, one soundtrack. Guarded against a
    // stale name in the service, exactly like wallTarget.
    property string wpeTarget: ""
    // ── Per-monitor scene overrides ───────────────────────────────────────────
    // [{ screens: [name,...], id, scaling, clamp }]. A screen not covered by any
    // entry here plays the DEFAULT scene (wpeCurrent) on wpeTarget, exactly as
    // before this existed. screens.length > 1 means those screens share ONE
    // spanned scene (--screen-span), not independent copies of it. Empty by
    // default, so an untouched config launches byte-identically to before.
    property var wpeMonitors: []
    // Scaling/clamp for the DEFAULT assignment only — a per-monitor override
    // carries its own in its wpeMonitors entry. "default"/"clamp" are the CLI's
    // own no-op values, so these add nothing to the launch command until changed.
    property string wpeScaling: "default"  // stretch | fit | fill | default
    property string wpeClamp:   "clamp"    // clamp | border | repeat
    property bool wpeMute: false
    property int  wpeVolume: 50
    // The renderer MUTES ITSELF whenever any other application plays a sound,
    // unless told not to — which read as "wallpaper audio doesn't work" the
    // moment anything (a notification, Discord) made a noise. True = pass
    // --noautomute, the flag the user's own manual launches always carried.
    property bool wpeKeepAudio: true
    // The renderer stops rendering while an app is fullscreen. Right for a game,
    // wrong if you actually want to keep seeing the wallpaper.
    property bool wpePauseFullscreen: true
    // Scenes play in windows of their own that the shell captures (services/ScenePreload):
    // the ones workspaces own, so a switch shows them at once instead of waiting for a load,
    // and the scene applied as the wallpaper, so the pointer parallax reaches it. Costs the
    // GPU of every such scene, all the time. Off: the layer renderer plays them, with the
    // scene's own parallax (when its author enabled it) and only over a bare desktop.
    property bool wpePreload: true
    // Wallpapers that react to whatever is playing. Costs an audio capture.
    property bool wpeAudioProcessing: true
    // Scene wallpapers that follow the cursor. Both cost real work every frame.
    property bool wpeMouse:    true
    property bool wpeParallax: true
    // Particle emitters. Some Workshop scenes crash the RENDERER on these — a
    // real, reproducible segfault inside CParticle construction (verified via
    // coredumpctl against workshop item 3661092645, not a bug in this config).
    // --disable-particles is the CLI's own documented mitigation. Off (this
    // being true) is the normal case; WallpaperEngine also retries a launch
    // ONCE with particles forced off if it never comes up, regardless of this
    // setting — see particlesAutoDisabledFor.
    property bool wpeParticles: true
    // Derive the shell's palette from the scene's preview image when a scene is
    // applied — an animated wallpaper recolours the shell the same way a static
    // one does. On by default: a wallpaper that doesn't theme the shell is the
    // surprising case here, not the normal one.
    property bool wpeScenePalette: true

    // ── The master theming switch ─────────────────────────────────────────────
    // Off: picking a wallpaper changes the PICTURE and nothing else — no pywal,
    // no app repaints, the palette on disk stays put. For people who want their
    // colours hand-picked (or held by a saved scheme) while still changing
    // wallpapers freely.
    property bool wallTheming: true

    // ══ Album-cover colour scheme ═════════════════════════════════════════════
    // The shell takes its palette from the cover of whatever is playing, and hands it
    // back to the wallpaper when the music stops. services/AlbumScheme.qml owns it.
    //
    // OFF by default, deliberately. It repaints the entire desktop on a schedule the
    // user does not control — every track change is a re-theme — which is a delightful
    // thing to opt into and an alarming thing to discover.
    property bool albumScheme: false

    // How far the album palette reaches.
    //
    // Off (default): the SHELL only. Held in memory as an overlay on Colors, so a track
    // change is a repaint and nothing else — no pywal run, no file written, and
    // switching it off restores the wallpaper's palette instantly.
    //
    // On: the whole system, through the same reload-theme.sh every other palette change
    // goes through — GTK, Qt, kitty, cava, Hyprland. That path flips the global GTK
    // theme (and sleeps 0.25s doing it), signals every terminal and rewrites several
    // config files, which is fine every so often and a lot every three minutes. It also
    // WRITES colors.json, so turning album mode off has to regenerate from the
    // wallpaper rather than simply dropping an overlay.
    property bool albumSchemeSystem: false

    // When the music is playing and this is on, the album palette WINS: a fully
    // pinned palette or an applied colour scheme no longer stops it, and it merges
    // ON TOP of held colours instead of under them. Off (default) keeps the old
    // behaviour — hand-pinned colours outrank the album. Config for the album tab
    // in the colours panel.
    property bool albumSchemeLock: false

    // WHERE the album palette goes (services/AlbumScheme, WorkspaceTheme):
    //   "all"        the whole shell (and, with albumSchemeSystem, the whole system) — as it always was;
    //   "workspaces" only the workspaces in `albumWorkspaces`: the shell on the screen showing one, and
    //                the windows, terminals, Discord and Spotify on it;
    //   "spotify"    only the workspace Spotify's window is on, wherever that is right now.
    // A scope narrower than "all" is always the in-memory reach: "Everything" writes the system-wide
    // colour files, which no one workspace can own. Anything else reads as "all".
    property string albumScope: "all"
    // The workspaces (ids) the "workspaces" scope covers.
    property var    albumWorkspaces: []

    // ══ Album colours on the media/lyrics cards ══════════════════════════════
    // A different feature from albumScheme above: this one does NOT repaint the
    // shell. It only decides whether the now-playing and lyrics cards (overview +
    // lockscreen) tint themselves from services/AlbumArt.qml's per-track
    // extraction or fall back to the ordinary wallpaper-derived Colors palette.
    // Off means those cards look like every other card instead of shifting per
    // track. AlbumArt itself keeps extracting either way — the desktop widgets'
    // own per-widget "album vs wallpaper" option still reads it independently.
    property bool albumCardColors: true

    // ══ Icon colourisation ════════════════════════════════════════════════════
    // Off (default) shows icons in their own native colours — a tray icon's own
    // brand palette, the lyrics source badge's fixed pass/fail red/green. On,
    // they're tinted flat with the shell's accent instead, for a more monochrome
    // look. Scoped to the tray and the lyrics check/cross badge for now; other
    // icons can opt in later without a second flag.
    property bool colorizeIcons: false
}
