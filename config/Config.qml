pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue

// ── Config ────────────────────────────────────────────────────────────────────
// The user's PREFERENCES — the things the settings app writes and the shell reads.
// Persisted, and the single source of truth for all of them.
//
// ── Config vs UiState ─────────────────────────────────────────────────────────
// UiState answers "what is the shell showing right NOW" (which panel is open, is the
// overview up) — transient, and deliberately not restored across a reload. This answers
// "how has the user set the shell up" — durable, and restored every time.
//
// `barShape`/`barMode` used to live in UiState, which even said so itself: "Only the
// appearance preferences persist. Panel state is transient by design." Those two were
// the odd ones out in a file about transient state, and now that there are twenty more
// of them they've moved here where they belong.
//
// Defaults mirror Tokens — Tokens stays the design system's baseline, and this is the
// user's departure from it. (Tokens must never import Config: the tokens are what the
// defaults are DEFINED as, so the dependency only runs one way.)
// ─────────────────────────────────────────────────────────────────────────────
ConfigDesktop {
    id: root

    // ── The shell's own version ───────────────────────────────────────────────
    // Hand-maintained, and it has to be: this config isn't a git checkout (no .git
    // anywhere), so there's nothing to derive a version FROM at runtime. Upstream is
    // https://github.com/rufss14/Quickshell-Config, which tags releases — v0.1, v0.2 —
    // and the update check compares this string against the newest tag there.
    //
    // BUMP THIS when you tag a release, or the shell will report itself as whatever
    // the last person to think about it said. It is the one number here that a
    // machine can't check for you.
    readonly property string version: "0.4"
    readonly property string repo:    "rufss14/Quickshell-Config"

    // ShellPresets (ConfigBarLayout) waits on this store; that file can't see its id.
    readonly property var _shellPresetsStore: shellPresetsStore

    // ══ Persistence ═══════════════════════════════════════════════════════════
    // ── What was wrong before ─────────────────────────────────────────────────
    // All of this was one PersistentProperties block. That type has NO disk I/O — it
    // carries values from one config generation to the next across a hot reload, in
    // memory, and that is all it does. So every setting on this page — presets, the
    // layout, thickness, motion, the lot — was lost the moment the shell exited. The
    // saved-preset list looked like it worked right up until you logged out.
    //
    // ── Two documents ─────────────────────────────────────────────────────────
    //   prefs    The live settings. Rewritten on every slider drag, so it lives in the
    //            STATE dir — deliberately OUTSIDE the shell directory, because the docs
    //            for `watchFiles` say "the configuration will be reloaded whenever any
    //            files change" and don't scope that to QML. A file that changes on every
    //            frame of a drag is not one to gamble on.
    //   presets  Named snapshots. Written only when you press Save, and meant to be
    //            read, hand-edited, shared and backed up — so it sits in the shell
    //            directory beside colorschemes/, where you'd look for it.
    //
    // Both go through the same JsonStore. Neither is watched: we are the only writer.

    JsonStore {
        id: prefsStore
        path: Quickshell.statePath("config.json")

        onLoaded: {
            const doc = prefsStore.value ?? {}
            root._firstBoot = Object.keys(doc).length === 0

            root._loading = true
            root._applyPrefsDoc(doc)
            root._loading = false

            // Re-emit the document immediately, then check it. The write costs one
            // debounced save at startup and MIGRATES the file: a config written before
            // a preference existed gains its key here rather than on the next slider
            // drag, which is what lets the audit below see the real document instead of
            // whatever shape happened to be on disk.
            root._writePrefs()
            root._auditPrefs()
            root.prefsLoaded = true
            root._maybeApplyDefaultPreset()
        }
    }

    // False until config.json has been read (or confirmed absent). shell.qml's
    // first-run check waits on this so it doesn't act on a default `setupSeen`
    // before the real value has loaded.
    property bool prefsLoaded: false

    // A { name: number } map from a hand-editable document, keeping only the numbers
    // that are in range. Anything else is dropped rather than trusted.
    function _numberMap(raw, lo, hi) {
        const m = {}
        if (raw && typeof raw === "object" && !Array.isArray(raw))
            for (const k in raw)
                if (typeof raw[k] === "number" && raw[k] >= lo && raw[k] <= hi) m[k] = raw[k]
        return m
    }

    // ── Apply a whole prefs document ──────────────────────────────────────────
    // The shape config.json has on disk, and the shape a Shell preset's `config` has.
    // Used by prefsStore.onLoaded (restore) and applyShellPreset (swap the lot).
    //
    // `?? root[k]` rather than a bare assign: a key absent from the document (first run,
    // an older version of this file, or an older shell preset) must keep the property's
    // own default, not overwrite it with undefined.
    //
    // An object entry restores through its own `load`; one that only has a `save` is
    // derived and has nothing to restore into. Caller owns `_loading`.
    function _applyPrefsDoc(v) {
        for (const e of root._persisted) {
            if (typeof e === "string")   { root[e] = v[e] ?? root[e]; continue }
            if (e.load)                  { e.load(v); continue }
            if (e.save === undefined)    root[e.key] = v[e.key] ?? root[e.key]
        }
    }

    // The inverse: every persisted preference as a plain object. This IS config.json's
    // content, and a Shell preset's `config`.
    function _dumpPrefs() {
        const out = {}
        for (const e of root._persisted) {
            if (typeof e === "string") { out[e] = root[e]; continue }
            out[e.key] = e.save ? e.save() : root[e.key]
        }
        return out
    }

    JsonStore {
        id: presetsStore
        path: Quickshell.shellPath("presets/bar.json")

        // An object rather than a bare array, so the file has somewhere to grow a
        // version tag or a second kind of preset without breaking every reader.
        defaults: ({ presets: [] })

        onLoaded: {
            const list = (presetsStore.value ?? {}).presets
            if (!Array.isArray(list)) return

            root._loading = true
            // Hand-editable file: drop anything without the shape the rest of this
            // section assumes, rather than letting a malformed entry reach loadPreset()
            // and throw on `c.layout`.
            root.presets = list.filter(p => p && typeof p.name === "string" && p.config)
            root._loading = false
        }
    }

    // The cursor's presets, one file over from the bar's and read the same way.
    JsonStore {
        id: cursorPresetsStore
        path: Quickshell.shellPath("presets/cursor.json")
        defaults: ({ presets: [] })

        onLoaded: {
            const list = (cursorPresetsStore.value ?? {}).presets
            if (!Array.isArray(list)) return
            root._loading = true
            root.cursorPresets = list.filter(p => p && typeof p.name === "string"
                                               && p.name !== root.cursorDefaultPresetName && p.config)
            root._loading = false
        }
    }

    // Same shape as presetsStore, one file over: the whole-config presets.
    JsonStore {
        id: shellPresetsStore
        path: Quickshell.shellPath("presets/shell.json")
        defaults: ({ presets: [] })

        onLoaded: {
            const list = (shellPresetsStore.value ?? {}).presets
            if (Array.isArray(list)) {
                root._loading = true
                root.shellPresets = list.filter(p => p && typeof p.name === "string" && p.config)
                root._loading = false
            }
            root._maybeApplyDefaultPreset()
        }
    }

    // Guards the write-back while the stores are populating us. Without it, restoring
    // nine properties one at a time would queue nine documents built from a half-applied
    // state. The debounce would collapse them to one correct write, so this is about not
    // doing pointless work rather than correctness.
    property bool _loading: false

    // ── The persisted set: ONE list, not three ────────────────────────────────
    // Every preference that survives a restart is named here exactly once. The load
    // (prefsStore.onLoaded), the write (_writePrefs) and the change notification
    // (Component.onCompleted, further down) all iterate THIS list, so a property
    // cannot be in one of them and missing from another.
    //
    // ── What this replaced, and why ───────────────────────────────────────────
    // Three hand-maintained lists. The comment that used to sit here was right about
    // the danger: "A preference only survives a restart if it appears in ALL THREE of
    // the load, this document, and a change handler at the bottom of this file. Miss
    // one and the failure is silent and shaped like something else entirely."
    //
    // It was missing one 27 times — every lockShow* toggle, all four lyrics keys, all
    // four fastfetch keys, both greet keys, both albumScheme keys and the lock*
    // avatar/backdrop/idle keys were written and loaded but had NO change handler.
    //
    // Because _writePrefs() serialises the WHOLE document, that never read as "this
    // setting doesn't save". It read as "this setting saves only when I also change
    // something else" — a bar tweak in the same session made it stick, which is
    // exactly the kind of intermittent that gets blamed on anything but the cause.
    // `barBorderWidth` was this same bug caught by hand, one at a time; these were
    // the rest.
    //
    // ── Entries ───────────────────────────────────────────────────────────────
    // A bare string is the ordinary case: restored with `?? default`, written verbatim,
    // notified on its own change signal. An object customises exactly one of those:
    //   load(v)       restore needs the whole document, or isn't a plain assign
    //   save()        the written value is derived, not a property read
    //   notify: false there is no property behind it to change
    //
    // ORDER IS THE ON-DISK KEY ORDER. JSON.stringify emits insertion order, so keeping
    // it stable is what keeps a config.json diff readable between versions.
    readonly property var _persisted: [
        // Bar — look, geometry, motion
        //
        // `barThickness`/`barInset`/`barFontScale`/`barIconScale` are object entries
        // rather than bare strings: the actual editable number now lives in
        // `*Pref` (see that property's own comment), but the on-disk key stays the
        // OLD bare name — an existing config.json, and every preset in
        // presets/bar.json, already uses it. Renaming the key would silently
        // orphan both on the next load.
        "barShape",
        { key: "barThickness", load: function (v) { root.barThicknessPref = v.barThickness ?? root.barThicknessPref },
                                save: function ()  { return root.barThicknessPref } },
        "barRoundness",
        { key: "barInset", load: function (v) { root.barInsetPref = v.barInset ?? root.barInsetPref },
                            save: function ()  { return root.barInsetPref } },
        "barBorderWidth", "frameBorderWidth", "barOpacity",
        "barCentreAnchor",
        { key: "barFontScale", load: function (v) { root.barFontScalePref = v.barFontScale ?? root.barFontScalePref },
                                save: function ()  { return root.barFontScalePref } },
        { key: "barIconScale", load: function (v) { root.barIconScalePref = v.barIconScale ?? root.barIconScalePref },
                                save: function ()  { return root.barIconScalePref } },
        "barInnerPill", "railCollapsed",
        "motionScale", "motionEnabled", "barHoverGrow", "cavaBg", "cavaBgStyle", "cavaBgIntensity",
        "sfxEnabled", "sfxVolume", "sfxPanels", "sfxTyping", "sfxSwitches", "sfxNotify",
        "sfxAlerts", "sfxCapture",
        "sfxTypingScope",
        "sfxPanelsVolume", "sfxTypingVolume", "sfxSwitchesVolume", "sfxNotifyVolume",
        "sfxAlertsVolume", "sfxCaptureVolume",

        // Game mode — what the one switch does, not whether it's on
        "gamemodeSession", "gamemodeQuiet", "gamemodeIdle", "gamemodeWallpaper",
        "gamemodeVisualizer", "gamemodeKeys", "gamemodeAuto",
        "gamemodeSteam", "gamemodeClips", "gamemodeCompositor",

        // Launcher — the `>` terminal, and the AI behind `?`.
        // The KEY is not here and never will be: it lives in ai-keys.json, written
        // 0600 by scripts/ai-credentials.py. config.json is a normal readable file
        // that anyone forking this config ends up with.
        "launcherTerminal", "launcherRows", "launcherActions", "launcherSettings", "launcherCalc",
        "launcherPackages", "launcherAur", "launcherLearn", "launcherClipboard", "launcherEmoji",
        "launcherWebShortcuts",
        "aiEnabled", "aiProvider", "aiModel", "aiMaxTokens", "aiGrounding", "aiEffort",
        "aiLocalUrl", "aiLocalAutostart", "aiMemory", "aiVoice", "aiWakeWords", "overviewFeedPage", "overviewMore", "newsTopic", "newsCountry", "newsImages", "changelogSeen",
        "webSearchUrl", "webSearchName",

        // On-screen display
        "osdEnabled", "osdMs",

        // Bluetooth
        "btAgent", "btConnectOsd", "btBatteryWarn", "btBatteryLow", "btPillBattery",
        "btAdapter",

        // Lock screen
        "lockIdleEnabled", "lockIdleMinutes", "lockOnSleep", "lockPamConfig",

        // Battery saver
        "powerSaver",
        "lockShowMedia", "lockShowNotifications", "lockShowPower", "lockShowBrightness",
        "lockShowCava", "lockShowStats", "lockShowCalendar", "lockShowDiscord",
        "lockLyricsOnYouTube",

        // Lyrics
        "lyricsMotion", "lyricsFallback", "spotifyBridgeDetached",
        "lyricsTranslate", "lyricsTranslateLang",
        "lyricsTranslateBackends", "lyricsTranslateCache",
        "lyricsRomanize", "lyricsRomanizeOnline", "lyricsRomanizeCache",

        // Lock screen — avatar and backdrop
        "lockAvatar", "lockSceneAnimate", "lockBackdrop",

        // Greeter
        "greetUser", "greetSession",

        // Settings app, and the feature switches
        "settingsPage", "settingsPanel", "settingsPanelSide", "settingsPinned", "panelCookies", "barCookies", "barCookiesFrom",
        "setupSeen", "setupAutoOpenDisabled", "defaultPresetApplied", "widgetsEnabled", "discordEnabled",
        "claudePresenceEnabled", "claudePresenceUseAiTitle", "claudePresenceShowWorkspace",
        "claudePresenceShowModel", "claudePresenceShowTokens", "claudePresenceShowSessionCount",
        "cs2PresenceEnabled", "cs2PresenceShowScore", "cs2PresenceShowKd",
        "cs2PresenceShowMode",

        // Desktop widgets
        "widgetGrid", "widgetOpacity", "widgetRoundness", "widgetGlass",
        "widgetParallax", "widgetParallaxStrength", "widgetEntrance",

        // Weather
        "weatherPlace", "weatherLat", "weatherLon", "weatherMetric", "weatherCountry",

        // Calendar
        "calendarLocalColor", "calendarFeeds",

        // World clocks
        "worldClocks",

        // Screen frame
        "screenFrame", "frameThickness", "frameRoundness",

        // Sidebar — what's on it, where. Loaded BEFORE anything reads the three
        // derived switches below; its loader migrates a document that only has those.
        { key: "sidebarLayout", load: function (v) { root._loadSidebarLayout(v) } },

        // Dock. `dockEnabled`, `sidebarStats` and `clips` are the layout's answer now
        // (derived, never restored): still written, so config.json reads as it always
        // did and an older checkout of this file still finds them.
        { key: "dockEnabled", notify: false, save: function () { return root.dockEnabled } },
        "dockPosition", "dockOverflow", "dockTakesSpace",
        "dockIconSize", "dockShowLauncher", "dockPreviews",
        // Replaced a `dockPerMonitor` bool: an older document's true means "monitor".
        { key: "dockScope",
          load: function (v) {
              root.dockScope = v.dockScope ?? (v.dockPerMonitor ? "monitor" : "all")
          } },
        "dockStyle", "dockShowTrash", "dockShowDownloads", "dockInnerPill", "dockMagnify", "dockMagnifyScale", "dockPreviewFuse", "dockClipLength", "dockPeek",
        // One auto-hide for the whole sidebar now. A document from when each module
        // hid on its own, with separate pills, brings the dock's along: it was the
        // one that mattered, and the rest of the edge now goes with it.
        { key: "sidebarAutoHide",
          load: function (v) {
              root.sidebarAutoHide = (v.sidebarUnified === false && v.dockAutoHide === true)
                  || (v.sidebarAutoHide ?? root.sidebarAutoHide)
          } },
        { key: "sidebarDodge",
          load: function (v) {
              root.sidebarDodge = (v.sidebarUnified === false && v.dockDodge === true)
                  || (v.sidebarDodge ?? root.sidebarDodge)
          } },
        "sidebarEmptyReveal", "sidebarEdgeReveal",
        "peekTimer", "peekClaude", "peekColour", "peekClipboard",
        "sidebarIslands", "sidebarHero", "barMusicReact",
        "karaokeWords", "karaokeSkipHeadphoneCheck", "karaokeStayAtEnd", "karaokeLanguage", "karaokeModHidden", "karaokeModHardRock", "karaokeModTimeHell", "karaokeModelDir",
        { key: "sidebarStats", notify: false, save: function () { return root.sidebarStats } },
        "sidebarStatsMetrics", "sidebarStatsNetMbps",
        "sidebarStatsNetSplit", "sidebarStatsTempArcs",
        "sidebarStatsAlerts", "sidebarStatsAlertNotify", "sidebarStatsAlertLoad", "sidebarStatsAlertTemp",
        "sidebarStatsMonitor",
        { key: "clips", notify: false, save: function () { return root.clips } },
        "clipsBuffer", "clipsDir", "clipsTarget", "clipsBufferSeconds", "clipsStorage", "clipsSaveSeconds",
        "clipsFps", "clipsBitrateMode", "clipsQuality", "clipsKbps", "clipsCodec", "clipsContainer",
        "clipsResolution", "clipsCursor", "clipsDesktopAudio", "clipsMic", "clipsSplitAudio",
        "clipsPeek", "clipsNotify", "clipsNameByWindow", "clipsAhead", "clipsRecordLimit", "clipsFileManager",

        // Night light — the switch, the temperature and the schedule. Without these the
        // warmth turned itself off on every shell reload, and the schedule reset.
        { key: "lensOcrLangs",
          load: function (v) {
              const x = v.lensOcrLangs
              root.lensOcrLangs = (typeof x === "string" && x !== "" && x !== "eng") ? x : "auto"
          } },
        "lensTranslateLang", "snapZones", "snapToGrid", "screenTime", "screenTimeKeepDays", "screenTimeIdleMinutes", "antiFlash", "antiFlashNightOnly", "antiFlashThreshold", "antiFlashFloor",
        "nightLight", "nightLightTemp", "nightLightAuto", "nightLightFollowSun",
        "nightLightFrom", "nightLightTo",

        // User-facing paths and lists with no settings UI of their own: persisted so an
        // edit to config.json is honoured instead of being ignored on load. A path's
        // default stays "" (see the Portability notes) — only what the user set is saved.
        "wallLibraryDir", "wallExportPath", "screenshotApps", "screenshotDir", "screenshotToastMs", "polkitAgent", "reloadPopup", "uiLanguage", "snipAction",

        // Cursor — the theme and its motion effects. Without these, the switch works until
        // the next shell reload and then quietly turns itself off.
        "cursorTheme", "cursorColor", "cursorCustom", "cursorSize",
        "cursorEffects", "cursorEffectMode", "cursorEffectSensitivity", "cursorShake",

        // ── barLayout, with its migration ─────────────────────────────────────
        // An object entry rather than a bare string: a document may hold a pills
        // shape, scrapped since, or predate barLayout and carry `frameMerge`.
        // layout.js `unifiedLayout` maps each to its unified twin. No `save`, so the
        // first write records the migrated value; a no-op forever after.
        { key: "barLayout",
          load: function (v) { root.barLayout = Layout.unifiedLayout(v.barLayout, v.frameMerge) } },


        // Wallpaper Engine
        "wpeCurrent", "wpeAutoStart", "wpeFps", "wpeVsync", "wpeTarget",
        "wpeMonitors", "wpeScaling", "wpeClamp",
        "wpeMute", "wpeVolume", "wpeKeepAudio", "wpePauseFullscreen", "wpePreload",
        "wpeAudioProcessing", "wpeMouse", "wpeParallax", "wpeParticles", "wpeScenePalette",

        // Theming and wallpaper
        "themeMode", "wallTheming", "albumScheme", "albumSchemeSystem", "albumSchemeLock", "albumScope",
        "albumCardColors", "colorizeIcons",
        "wallTarget", "wallShuffle", "wallShuffleMins", "wallShuffleFavs", "wallSort", "wallApplyDebug", "colorApplyDebug", "colorFavorites", "mixerBoost",
        "wallShellRender", "wallMaterial", "wallMaterialRole", "wallMaterialContrast",
        "wallMaterialSoftness", "wallMaterialSize", "wallMaterialSeed", "wallMaterialRole2",
        "wallMaterialStack", "wallMaterialCentre", "wallMaterialSide", "wallMaterialCorner",
        "wallMaterialBackdrop", "wallMaterialMirror", "wallMaterialDrift", "wallMaterialDriftSpeed", "wallMaterialSpin", "wallMaterialFallback", "wallMaterialSaved", "wallMaterialLinks", "wallParallax", "wallParallaxWorkspace",
        "wallFx", "wallFxIntensity", "wallFxMix", "wallFxSyncMs", "cavaBgBlendDir",
        { key: "cavaBgBlend", load: function (v) { root._loadCavaBlend(v) } }, "cavaBgOpacity",
        "cavaBgMusicOnly", "cavaBgPeaks", "cavaBgGlow", "cavaBgRingCover",
        "wallParallaxZoom", "wallParallaxMouse", "wallDepth", "wallDepthScale", "wallDepthDepth", "wallDepthSoft", "wallDepthDate",
        "wallDepthHour12", "wallDepthInk", "wallDepthPlaces", "wallDepthPrepare", "wallFavorites", "wpeFavorites", "wpeUnsubPending",
        "updateHold", "updateCheckMins", "updateQuiet", "updateQuietFrom", "updateQuietTo", "updateSnapshot",
        "shellUpdateCheck", "shellUpdateNotified",

        // Appearance
        "fontFamily", "fontMonoFamily", "fontBlockFamily", "fontScale", "densityScale", "radiusScale", "cornerStyle", "iconShape", "surfaceOpacity",
        "shadowScale",
        "accentRole",

        // ── The three that aren't plain assignments ───────────────────────────

        // Truthiness rather than `??`, which is the test the hand-written load used: a
        // document carrying a falsy moduleSettings is malformed, not meaningful.
        { key: "moduleSettings",
          load: function(v) { if (v.moduleSettings) root.moduleSettings = v.moduleSettings } },

        // Per-group spacing overrides — same shape and the same reasoning as
        // moduleSettings just above.
        { key: "groupSettings",
          load: function(v) { if (v.groupSettings) root.groupSettings = v.groupSettings } },

        // Workspaces' own wallpapers. Hand-editable: only "<id>": "<absolute path>" or
        // "scene:<Workshop id>" pairs come through (and still have to exist to be used).
        { key: "wallWorkspaces",
          load: function(v) {
              const m = {}
              const w = v.wallWorkspaces
              if (w && typeof w === "object" && !Array.isArray(w))
                  for (const k in w)
                      if (/^[1-9][0-9]{0,3}$/.test(k) && typeof w[k] === "string"
                          && (w[k].charAt(0) === "/" || /^scene:[A-Za-z0-9._-]{1,64}$/.test(w[k]))) m[k] = w[k]
              root.wallWorkspaces = m
          } },

        // The workspaces the album's "workspaces" scope covers: positive whole numbers, once each.
        { key: "albumWorkspaces",
          load: function(v) {
              const w = v.albumWorkspaces
              const out = []
              if (Array.isArray(w))
                  for (const n of w)
                      if (Number.isInteger(n) && n > 0 && n < 10000 && out.indexOf(n) < 0) out.push(n)
              root.albumWorkspaces = out.sort((a, b) => a - b)
          } },

        // Workspaces' own colour schemes. Hand-editable: only "<id>": "<scheme name>" pairs come
        // through (a name that no longer exists in colorschemes/ is simply not worn).
        { key: "schemeWorkspaces",
          load: function(v) {
              const m = {}
              const w = v.schemeWorkspaces
              if (w && typeof w === "object" && !Array.isArray(w))
                  for (const k in w)
                      if (/^[1-9][0-9]{0,3}$/.test(k) && typeof w[k] === "string"
                          && /^[^\/\n\r\0]{1,128}$/.test(w[k])) m[k] = w[k]
              root.schemeWorkspaces = m
          } },

        // Apps' own names and icons. Hand-editable: only "<app id>": { name, icon } with a
        // short single-line name and a symbol-shaped icon name come through.
        { key: "appLabels",
          load: function(v) {
              const m = {}
              const w = v.appLabels
              if (w && typeof w === "object" && !Array.isArray(w))
                  for (const k in w) {
                      const e = w[k]
                      if (!/^[A-Za-z0-9._-]{1,128}$/.test(k) || !e || typeof e !== "object") continue
                      const name = typeof e.name === "string" && /^[^\n\r\0]{0,32}$/.test(e.name) ? e.name : ""
                      const icon = typeof e.icon === "string" && /^[a-z_]{1,40}$/.test(e.icon) ? e.icon : ""
                      if (name !== "" || icon !== "") m[k] = { name: name, icon: icon }
                  }
              root.appLabels = m
          } },

        // Output limits and remembered levels. Hand-editable, so only `name: number`
        // pairs inside their legal range come through.
        { key: "audioDeviceCaps",
          load: function(v) { root.audioDeviceCaps = root._numberMap(v.audioDeviceCaps, 0.1, 0.99) } },
        { key: "audioDeviceLevels",
          load: function(v) { root.audioDeviceLevels = root._numberMap(v.audioDeviceLevels, 0, 1.5) } },
        "audioRememberLevels",

        // Which side each panel opens on — same shape and reasoning again.
        { key: "panelPlacement",
          load: function(v) { if (v.panelPlacement) root.panelPlacement = v.panelPlacement } },

        // Per-panel size overrides — same shape and reasoning again.
        { key: "panelZoom",
          load: function(v) { if (v.panelZoom) root.panelZoom = v.panelZoom } },

        // ── A saved layout can't be trusted, and this is why ──────────────────
        // It was written by a previous version of this file. Modules added since aren't
        // in it (they'd silently never appear), and modules REMOVED since still are
        // (the bar would try to build a widget that no longer exists). So it's
        // reconciled against the catalogue rather than assigned: keep what still
        // exists, append what's new to its home region.
        { key: "layout",
          load: function(v) {
                    if (v.layout && Object.keys(v.layout).length > 0)
                        root.layout = root._reconcile(v.layout, root._barKnown(v.knownModules ?? []))
                } },

        // The catalogue as it stood when this was last written. Kept BESIDE the layout,
        // not inside it: every mutator rebuilds the layout through _clone(), which only
        // copies the three regions, so a marker stored in the layout object would be
        // dropped by the first drag and never seen again.
        //
        // Derived, so there is no property to restore into and nothing to notify on.
        { key: "knownModules", notify: false,
          save: function() { return root.moduleList.map(m => m.id) } }
    ]

    function _writePrefs() {
        if (root._loading || !prefsStore.ready) return
        prefsStore.value = root._dumpPrefs()
    }

    function _writePresets() {
        if (root._loading || !presetsStore.ready) return
        presetsStore.value = { presets: root.presets }
    }

    function _writeCursorPresets() {
        if (root._loading || !cursorPresetsStore.ready) return
        cursorPresetsStore.value = { presets: root.cursorPresets }
    }

    function _writeShellPresets() {
        if (root._loading || !shellPresetsStore.ready) return
        shellPresetsStore.value = { presets: root.shellPresets }
    }

    // A saved layout is reconciled against the live catalogue rather than trusted. The
    // rule — "the user removed this" vs "this didn't exist yet", which look identical
    // in a saved layout — lives in layout.js with the tests that pin it.
    // What counts as "not new" to the bar: what it knew last time, plus every module
    // with a sidebar form. A sidebar module that gains a bar form (2026-10-07: all of
    // them) is not a new module — appending it would put it on BOTH surfaces, which
    // the one-place rule exists to prevent; it waits in the pool instead, as the
    // sidebar's own reconcile never appends either. An empty list stays empty
    // (reconcile's "a config from before this was tracked").
    function _barKnown(known) {
        if (known.length === 0) return known
        return known.concat(root.sidebarModuleList.map(m => m.id))
    }
    function _reconcile(saved, priorKnown) {
        return Layout.reconcile(saved, priorKnown, root.moduleList, root.regionIds)
    }

    // ── Change notification, wired from the same list ─────────────────────────
    // Every persisted property has its change signal connected to _writePrefs() here,
    // so "is this one notified?" stops being a separate thing to remember — it follows
    // from being in `_persisted` at all. This replaces 65 hand-written
    // `on<Name>Changed: root._writePrefs()` lines that should have been 92.
    //
    // `notify: false` opts out, for an entry with no property behind it to change.
    //
    // Connecting before the store is ready is harmless: _writePrefs() returns early
    // while `_loading` is set or the store hasn't loaded, which is the same guard the
    // hand-written handlers relied on.
    //
    // A missing signal means `_persisted` names something that isn't a declared
    // property — see _auditPrefs() for why that is the one new way to get this wrong.
    Component.onCompleted: {
        for (const e of root._persisted) {
            if (typeof e !== "string" && e.notify === false) continue
            const key = (typeof e === "string") ? e : e.key
            const sig = root[key + "Changed"]
            if (sig && typeof sig.connect === "function") sig.connect(root._writePrefs)
        }
    }

    onPresetsChanged:        root._writePresets()
    onShellPresetsChanged:   root._writeShellPresets()
    onCursorPresetsChanged:  root._writeCursorPresets()

    // ── The invariants, checked ───────────────────────────────────────────────
    // With load, write and notify all derived from `_persisted`, a preference can no
    // longer be in one list and missing from another — that bug class is gone by
    // construction. Two ways to get this wrong remain, and both are typos:
    //
    //   1. `_persisted` names something that is not a declared property. It would
    //      write `undefined` into the document and restore nothing. Caught by asking
    //      for the property's change signal: every declared property has one, and a
    //      misspelling has none. (Entries with a `save` are derived and exempt.)
    //   2. A preset field is not persisted. Every key `_snapshot()` can carry has to
    //      survive a restart, or loading that preset is a lie the moment you reload —
    //      which is exactly how the barBorderWidth omission surfaced. Checked against
    //      `_persisted` itself rather than the emitted document, so it no longer
    //      depends on the store having settled first.
    //
    // Warnings rather than fix-ups: the repair is one entry in one list now, and
    // silently papering over a missing key would hide which one.
    function _auditPrefs() {
        const keys = root._persisted.map(e => (typeof e === "string") ? e : e.key)

        const bogus = root._persisted
            .filter(e => (typeof e === "string") || e.save === undefined)
            .map(e => (typeof e === "string") ? e : e.key)
            .filter(k => root[k + "Changed"] === undefined)
        if (bogus.length > 0)
            console.warn("Config: _persisted names undeclared propert(ies) —", bogus.join(", "),
                         "\n  These save as undefined and restore nothing. Fix the spelling.")

        const missing = Object.keys(root._snapshot()).filter(k => keys.indexOf(k) === -1)
        if (missing.length > 0)
            console.warn("Config: preset field(s) not persisted —", missing.join(", "),
                         "\n  Add each to _persisted, or presets will not survive a reload.")
    }

    // ── IPC: the bar's shape ──────────────────────────────────────────────────
    // Same shape as the overview/launcher/idle handlers. Exists so the four modes
    // are reachable from a keybind without hunting for the settings page, and so
    // they can be switched from a script while looking at the result.
    //
    //   qs ipc -c ~/.config/quicktest call bar layout unifiedAnchored
    //   qs ipc -c ~/.config/quicktest call bar cycle
    //   qs ipc -c ~/.config/quicktest call bar status
    property var _barIpc: IpcHandler {
        target: "bar"

        function cycle(): void { root.cycleBarLayout() }

        // Rejects an unknown name rather than storing it — an invalid barLayout
        // would make every `=== "unified"` test false and silently render the
        // pills shape while the config claimed otherwise.
        function layout(name: string): string {
            if (root.barLayoutOrder.indexOf(name) === -1)
                return "unknown layout '" + name + "' — expected one of: "
                     + root.barLayoutOrder.join(", ")
            root.barLayout = name
            return name
        }

        // `qs ipc … call bar add <id>` / `remove <id>` — the module pool from a script,
        // the sidebar's `place`/`remove` twin. An id with no bar form is refused.
        function add(id: string): string {
            if (!Catalogue.hasForm(id, "bar")) return "no bar module '" + id + "'"
            root.addModule(id)
            return "added " + id
        }
        function remove(id: string): string {
            if (!root.isPlaced(id)) return "'" + id + "' isn't on the bar"
            root.removeModule(id)
            return "removed " + id
        }

        function status(): string {
            return root.barLayout
                 + "  (anchored=" + root.barAnchored
                 + " frame=" + root.screenFrame
                 + " band=" + root.frameBandVisible + ")"
        }
    }
}
