import Quickshell
import Quickshell.Io
import QtQuick
import "layout.js" as Layout
import "modules.js" as Catalogue
// ConfigEdges — part of Config, split out of Config.qml by area (2026-11-08). The parts form
// one inheritance chain (ConfigShell ← ConfigEdges ← ConfigBarLayout ← ConfigSystem ←
// ConfigDesktop ← Config), so every property still lives on the one `Config` singleton
// and nothing that reads `Config.x` changed. A name declared further down the chain is
// reached as `root.x` here (a base file can't see it statically; `root` is the same object).
ConfigShell {
    id: root

    // ══ Dock ══════════════════════════════════════════════════════════════════
    // The persistent app dock (modules/bar/DockHost.qml, welded into the screen
    // frame by the blob) — pinned + running apps, positioned on whichever screen
    // edge the bar isn't. Off by default: an opt-in surface alongside the bar.
    // The overview keeps its own dock either way; it covers this one while open.
    // On = placed on the sidebar (sidebarLayout, below) — no longer a switch of its own.
    readonly property bool dockEnabled: root.sidebarPlaced("dock")
    // "left" | "right" | "bottom" — never the bar's own edge (top).
    property string dockPosition:   "bottom"
    // "clip" caps the strip at a fixed length (scrollable, faded edges);
    // "grow" lets the surface extend with the icon count, capped at the
    // screen bound — the same two shapes the bar's own regions already
    // choose between (content-hugging vs a fixed ceiling).
    property string dockOverflow:   "clip"
    // "clip"'s cap, as a percentage of the room along the edge (clamped below).
    property int    dockClipLength: 80
    readonly property int dockClipLengthMin: 30
    readonly property int dockClipLengthMax: 100
    readonly property int dockClipPercent:
        Math.max(root.dockClipLengthMin, Math.min(root.dockClipLengthMax, root.dockClipLength))
    // (Auto-hide was the dock's own switch, `dockAutoHide`, and its "dodge"
    // mode `dockDodge`: the whole sidebar hides as one now, sidebarAutoHide /
    // sidebarDodge below, which read the dock's on the way in.)
    // Reserve compositor space (push tiled windows aside) the same way the
    // bar reserves `barExtent` — off by default, so the dock floats over
    // windows rather than shrinking their tiled area unasked. Never while
    // auto-hiding: a reserved band with nothing in it is just a dead strip.
    property bool   dockTakesSpace: false
    // The app icon itself, in px — the button and the dock's thickness grow
    // around it (dockButtonSize / dockThickness below).
    property int    dockIconSize:   32
    // The launcher ("start") button at the dock's leading end.
    property bool   dockShowLauncher: true
    // Live window thumbnails on hover. Off, a hover shows only the app's name.
    property bool   dockPreviews:   true
    // Which running apps a dock shows: "all" of them, those with a window on its
    // own "monitor" (Windows' "taskbar where the window is open"), or those on
    // that monitor's current "workspace". Pins show everywhere regardless.
    property string dockScope:      "all"
    // How the dock's buttons look. "frame" = the bar-styled strip with a swell and a travelling
    // focus pill; "ii" = End-4's: flat buttons, one dot per window, hairlines between groups,
    // a keep button and an overview button. The card around it is the same either way.
    property string dockStyle:      "frame"
    // The Trash and Downloads at the dock's far end, as on macOS.
    property bool   dockShowTrash:     false
    property bool   dockShowDownloads: false
    // The bar's "inner pill", on the dock: a lighter nested surface behind running
    // apps, shared by neighbours — two running apps side by side sit in ONE pill,
    // the way adjacent occupied workspaces merge in the workspaces pill.
    property bool   dockInnerPill:  false
    // Icons swell toward the pointer, growing out of the dock (DockIconStrip).
    property bool   dockMagnify:    false
    // How big the icon under the pointer gets, as a multiple of its size.
    property real   dockMagnifyScale: 1.6
    readonly property real dockMagnifyScaleMin: 1.2
    readonly property real dockMagnifyScaleMax: 2.2
    // Clamped once, here — config.json is hand-editable.
    readonly property real dockMagnifyPeak:
        Math.max(root.dockMagnifyScaleMin, Math.min(root.dockMagnifyScaleMax, root.dockMagnifyScale))
    // Welded, hover previews melt out of the dock as blob lobes rather than float
    // as cards. Needs the weld (Morph + screen frame + anchored bar).
    property bool   dockPreviewFuse: false
    // Windows' Aero Peek: resting on a window in a preview shows its workspace,
    // with that window lit (modules/bar/WindowPeek).
    property bool   dockPeek: true

    readonly property int dockIconSizeMin: 24
    readonly property int dockIconSizeMax: 56

    // The pref, clamped — once, here, the way frameDepth clamps frameThickness.
    // config.json is hand-editable, and a 400px icon would build a dock taller
    // than the screen. Everything that sizes an icon reads THIS, never the pref.
    readonly property int dockIconPx:
        Math.max(root.dockIconSizeMin, Math.min(root.dockIconSizeMax, root.dockIconSize))

    // ── The dock's geometry, derived once ─────────────────────────────────────
    // Its button: the icon, and spacingMd a side for the running pip, the badge
    // and the level bars to sit beside it. The overview's dock and the sidebar's
    // both wear it — so `dockIconSize` (Dock › Icon size) sizes the sidebar too.
    readonly property int dockButtonSize: root.dockIconPx + Tokens.spacingMd * 2
    readonly property int dockThickness:  root.dockButtonSize + Tokens.spacingSm * 2

    // ══ Sidebar — its size ════════════════════════════════════════════════════
    // Sized around the dock (the user's call: it has to fit the dock and the rest
    // of what stands on it), in the top bar's STYLE rather than at its size. A cell
    // is the dock's icon with `sidebarCellPad` round it, whatever module stands in
    // it; the top bar's inner pill goes round that (spacingXs a side), and the top
    // bar's margin (spacingMd) either side of that, across the edge.
    //
    // The cell is the sidebar's own, NOT the dock button (`dockButtonSize`, which
    // the overview's dock still wears): that one keeps spacingMd a side for the
    // pip, badges and level bars beside the icon, and at 32px icons it made the
    // sidebar 68px against the top bar's 50 — "too thick" (2026-10-02). Here the
    // indicators stand in the pad on the windows' side (DockIconStrip
    // `indicatorsInward`) and badges sit over the icon's corner.
    readonly property int sidebarIconPx:    root.dockIconPx
    readonly property int sidebarCellPad:   Tokens.spacingSm
    readonly property int sidebarCell:      root.sidebarIconPx + root.sidebarCellPad * 2
    readonly property int sidebarPillCross: root.sidebarCell + Tokens.spacingXs * 2
    // A glyph in a cell (the small modules): nine tenths of an app icon. It was three
    // quarters when the glyphs were a Nerd Font, whose line box ran half again taller
    // than its ink — at the icon's size they read far too big. Material Symbols
    // draws to its box, and at three quarters every cell was a small mark in a big one
    // (2026-10-17: "glyphs too small/thin"), so it fills more of the cell now.
    readonly property int sidebarGlyphPx:   Math.round(root.sidebarIconPx * 0.9)
    // …and a sturdier stroke than a body icon's: the cell's glyph stands alone at rest,
    // where the bar's sit among text. MaterialIcon adds symbolFillBoost on top as it fills.
    readonly property int sidebarGlyphWeight: Tokens.symbolWeight + 100
    // Between two cells of one module: the dock's gap between its buttons.
    readonly property int sidebarCellGap:   Tokens.spacingXs
    // `n` cells and the gaps between them, along the edge.
    function sidebarRun(n) { return n > 0 ? n * root.sidebarCell + (n - 1) * root.sidebarCellGap : 0 }
    // The surface's own depth across the edge. Where it starts (on the strip, off
    // it, or at the screen edge with the strip inside it) is the top bar's shape,
    // and dock.js `sideSurface` works that out for both SideRail and DockReserve,
    // so drawing and reserving can't disagree.
    readonly property int sidebarDepth:     root.sidebarPillCross + Tokens.spacingMd * 2
    // The corner every sidebar surface wears: the top bar's. The blob's sidebar
    // lobes and the cards melted out of them round to it too, so the two agree.
    readonly property int sidebarRadius: Tokens.corner(root.barShape, root.barRoundness)
    // Each pill sits this far in from the bar's ENDS along the edge — the top bar's
    // first inner pill stands the same spacingSm off the screen's side.
    readonly property int sidebarInset: Tokens.spacingSm

    // Nothing calls this today (SUPER+D's `dock toggle` is the auto-hide reveal,
    // UiState's); kept as the one-line way to switch the dock from a script.
    function toggleDock() { root.sidebarToggle("dock") }

    // ══ Sidebar — the layout ══════════════════════════════════════════════════
    // What stands on the edge the bar doesn't own, where, and grouped how: region →
    // groups → module ids, the top bar's `layout` shape with the same algebra
    // (config/layout.js). The regions run along the edge — `start` the near end
    // (under the bar on a side, the left end along the bottom), `centre`, `end` the
    // far corner — and each keeps the place the clips, the dock and the stats first
    // had (services/dock.js `sideRail`, laid out by SideRail).
    //
    // ── Membership IS visibility, as on the bar ───────────────────────────────
    // A placed module is on; an unplaced one is off and waits in the settings pool.
    // `dockEnabled`, `sidebarStats` and `clips` used to be three switches beside a
    // FIXED order — two facts that could only ever be edited one way. They are this
    // list's answer now, derived, so order and on/off can't disagree.
    //
    // Nothing placed by default, as nothing was switched on before: a published
    // config mustn't grow a surface on first launch. For the same reason a saved
    // layout is never topped up (the bar's reconcile appends modules an upgrade
    // added): a new sidebar module waits in the pool until someone places it.
    //
    // Replaced, never mutated — the same rule as `layout`: every mutator below
    // builds a new object and assigns it, which is what fires the change signal.
    property var sidebarLayout: ({ start: [], centre: [], end: [] })

    readonly property var sidebarRegionIds: Layout.SIDE_REGIONS

    // What each sidebar module IS (never where it sits). `home` is where adding one
    // puts it: the places the three had before the edge could be arranged.
    //
    // `small`: a few cells, drawn by SideGroupHost — any number of them can share a
    // pill, the way the top bar's modules share a group. The stats and the clips are
    // small too: a bar-style button each, whose panel opens beside it (SidePanelDock).
    // The dock is a host of its own (previews, menus) and always stands alone; the
    // rail splits a group round it (dock.js sideGroups). `cells` is how many a small
    // one takes along the edge; `glyph`, how the settings tray draws it.
    readonly property var sidebarModuleList: Catalogue.forSurface("side")

    function sidebarModuleInfo(id) { return root.sidebarModuleList.find(m => m.id === id) ?? null }
    function sidebarIsSmall(id)    { return root.sidebarModuleInfo(id)?.small === true }

    // Anything on the sidebar at all — config only, so a window's size never has to
    // wait on something loading (SideBarHost.bottomReach).
    readonly property bool sidebarAnyPlaced:
        root.sidebarRegionIds.some(r => (root.sidebarLayout[r] ?? []).length > 0)

    function sidebarLocate(id) { return Layout.locate(root.sidebarLayout, id, root.sidebarRegionIds) }
    function sidebarPlaced(id) { return root.sidebarLocate(id) !== null }
    function sidebarRegionOf(id) { return root.sidebarLocate(id)?.region ?? "" }

    // A module has ONE place (config/modules.js): whatever puts it on one surface takes
    // it off the other, so the pool never shows a module placed twice. Called by every
    // mutator that can insert — a settings-tray drop goes through moveIntoGroup and
    // never addModule — and a no-op for a module that only has one form.
    function _leaveBar(id)     { if (root.isPlaced(id))        root.removeModule(id) }
    function _leaveSidebar(id) { if (root.sidebarPlaced(id))   root.sidebarRemove(id) }

    // UI text, like regionLabel(): which end is which depends on the edge (the near
    // end is under the bar on a side, the left end along the bottom).
    function sidebarRegionLabel(region) {
        const side = root.dockPosition === "left" || root.dockPosition === "right"
        return region === "start"  ? (side ? "top" : "left end")
             : region === "centre" ? "middle"
             : region === "end"    ? (side ? "bottom" : "right end")
             :                       ""
    }

    // `null` from addModule = nothing to do (unknown, or already placed): skip the
    // assignment, and the change signal and the write with it.
    function sidebarAdd(id) {
        const next = Layout.addModule(root.sidebarLayout, id, root.sidebarModuleList, root.sidebarRegionIds)
        if (!next) return
        root._leaveBar(id)
        root.sidebarLayout = next
    }
    function sidebarRemove(id) {
        if (root.sidebarPlaced(id))
            root.sidebarLayout = Layout.removeModule(root.sidebarLayout, id, root.sidebarRegionIds)
    }
    function sidebarToggle(id) {
        if (root.sidebarPlaced(id)) root.sidebarRemove(id)
        else root.sidebarAdd(id)
    }
    function sidebarMoveToOwnGroup(id, region, groupIndex) {
        if (root.sidebarRegionIds.indexOf(region) === -1 || !root.sidebarModuleInfo(id)) return
        root._leaveBar(id)
        root.sidebarLayout = Layout.moveToOwnGroup(root.sidebarLayout, id, region, groupIndex,
                                                   root.sidebarRegionIds)
    }
    // Into a group, at `index` among its modules (arranging, SideDrag). The dock never
    // shares one — the rail would only split it back out (dock.js sideGroups) — so a
    // drop that would put it in one, or another module in its, lands beside it instead.
    function sidebarMoveIntoGroup(id, region, groupIndex, index) {
        if (root.sidebarRegionIds.indexOf(region) === -1 || !root.sidebarModuleInfo(id)) return
        const group = (root.sidebarLayout[region] ?? [])[groupIndex] ?? []
        if (!root.sidebarIsSmall(id) || group.some(m => !root.sidebarIsSmall(m))) {
            root.sidebarMoveToOwnGroup(id, region, index <= 0 ? groupIndex : groupIndex + 1)
            return
        }
        root._leaveBar(id)
        root.sidebarLayout = Layout.moveIntoGroup(root.sidebarLayout, id, region, groupIndex, index,
                                                  root.sidebarRegionIds)
    }

    // ── Loading one ───────────────────────────────────────────────────────────
    // A saved layout is reconciled (unknown ids and duplicates dropped, a malformed
    // region ignored) with an empty priorKnown, so nothing is ever appended. A
    // document from before the layout existed has the three old switches instead:
    // they become exactly the layout that edge had — clips near, dock centred,
    // stats far. A document that mentions neither (an older shell preset) leaves
    // the live layout alone, the way every other absent key does.
    function _loadSidebarLayout(v) {
        if (v.sidebarLayout && typeof v.sidebarLayout === "object") {
            root.sidebarLayout = Layout.reconcile(v.sidebarLayout, [], root.sidebarModuleList,
                                                  root.sidebarRegionIds)
            return
        }
        if (v.dockEnabled === undefined && v.sidebarStats === undefined && v.clips === undefined) return
        const on = (key, id) => (v[key] ?? root.sidebarPlaced(id)) === true
        root.sidebarLayout = {
            start:  on("clips", "clips")        ? [["clips"]] : [],
            centre: on("dockEnabled", "dock")   ? [["dock"]]  : [],
            end:    on("sidebarStats", "stats") ? [["stats"]] : []
        }
    }

    // The whole sidebar hides as ONE, in either shape — sinking into the frame until
    // the pointer rests on its edge. It replaced a switch per module (the dock's,
    // the stats', the clips'), which couldn't work once modules could share a pill.
    property bool   sidebarAutoHide: false
    // Auto-hide's gentler mode, as the dock's was: out until a window overlaps it.
    property bool   sidebarDodge: false
    // ii's other two reveal rules, for an auto-hiding sidebar and its dock:
    //   sidebarEmptyReveal — stays out while the monitor's current workspace has no windows
    //                        (nothing to cover, and an empty desktop is where you reach for it)
    //   sidebarEdgeReveal  — resting on the edge brings it out. Off, the edge does nothing:
    //                        it comes out for an empty workspace, SUPER+D or the keep button
    //                        only. (ii's "hover to reveal" switch.)
    property bool   sidebarEmptyReveal: false
    property bool   sidebarEdgeReveal: true

    // Event peeks (modules/panels/EventPeek, 2026-10-31): a card beside a module for a moment
    // when something happens to it, on the focused monitor, when the panel slot is free —
    // the clips peek's rule (clipsPeek), for the rest. One switch each.
    property bool   peekTimer: true        // a countdown finished, an alarm rings
    property bool   peekClaude: true       // a session finished a turn, or needs you
    property bool   peekColour: true       // a colour picked: its swatch and hex
    property bool   peekClipboard: true    // a copy: its preview (password managers' never land)

    // The sidebar's look (2026-10-31, the user: "boring compared to the top"):
    //   sidebarIslands     a pill per group, the top bar's stray islands (false: one per region)
    //   sidebarHero        the module on a primaryContainer chip, the top bar's hero; "" none
    //   barMusicReact      BOTH bars' pills glow with the music (components/MusicRim); it was the
    //                      sidebar's alone, and scaled its pills — "messy", the user said
    property bool   sidebarIslands: true
    property string sidebarHero: "claude"
    property bool   barMusicReact: true

    // ── Karaoke (services/Karaoke) ────────────────────────────────────────────
    // Whether it is ON is deliberately NOT here: the microphone is never opened from a saved
    // preference, only by a click in this session.
    //   karaokeWords               also match the words sung, when a speech model is there
    //                              (timing alone otherwise)
    //   karaokeSkipHeadphoneCheck  run without headphones. The mic then hears the song, so the
    //                              cell can light from the music itself; for a form factor
    //                              PipeWire reports wrong
    //   karaokeModelDir            a Vosk model directory. "" is the default places, resolved in
    //                              exactly one spot (Karaoke.modelDirs), never a literal home here
    property bool   karaokeWords: true
    property bool   karaokeSkipHeadphoneCheck: false
    //   karaokeStayAtEnd           while Karaoke is on, pause the song at its end instead of letting the
    //                              player roll on into the next one — the results are on screen, and the
    //                              next song starting under them (with its first line coming) is the one
    //                              thing that spoils a run. Next and Play again are on the results screen
    property bool   karaokeStayAtEnd: true
    //   karaokeLanguage            the language of the songs, for the speech model and the words it is
    //                              told to listen for: "" is AUTO (detected from each song's lyrics),
    //                              else one of services/karaoke.js LANGS ("en", "pt", "es", "fr", "de",
    //                              "it", "nl", "ru")
    property string karaokeLanguage: ""
    //   karaokeMod*                the mods (services/karaoke.js MODS): Hidden Lyrics, Hard Rock, Time-Hell.
    //                              Read when a run BEGINS and fixed for it — a mod switched on mid-song would
    //                              be changing the rules under a score. Hidden Lyrics is a LEVEL: 0 off, 1 HD
    //                              (only the line being sung shown), 2 HD+ (everything hidden)
    property int    karaokeModHidden: 0
    property bool   karaokeModHardRock: false
    property bool   karaokeModTimeHell: false
    property string karaokeModelDir: ""

    // ══ Sidebar — the system stats ════════════════════════════════════════════
    // A button on the dock's edge with a glance at the first three metrics, and a
    // panel beside it with all of them (modules/bar/SideStats, modules/panels/
    // StatsPanel, services/SysStats). Off by default like the dock: a published
    // config shouldn't grow a new surface on first launch.
    // On = placed on the sidebar (sidebarLayout).
    readonly property bool sidebarStats: root.sidebarPlaced("stats")
    // Which metrics, in order ("cpu", "gpu", "ram", "net", …); the button glances at
    // the first three. GPU drops out by itself where SysInfo has no utilisation to
    // read (NVIDIA; see SysInfo.hasGpu).
    property var    sidebarStatsMetrics: ["cpu", "gpu", "ram", "net"]
    // The network ring's full scale, in Mbit/s. A FIXED scale on purpose (see
    // RadialGauge: a ring that rescaled to its own recent peak would make an idle
    // link look busy) — set it to your line's speed.
    property int    sidebarStatsNetMbps: 100
    readonly property int sidebarStatsNetMbpsMin: 1
    readonly property int sidebarStatsNetMbpsMax: 10000
    readonly property int sidebarStatsNetCeiling:
        Math.max(root.sidebarStatsNetMbpsMin, Math.min(root.sidebarStatsNetMbpsMax, root.sidebarStatsNetMbps))
    // Two arcs on the network ring — download outside, upload inside — instead of
    // the busier direction alone.
    property bool   sidebarStatsNetSplit: false
    // The CPU and GPU temperatures as an inner arc on their part's ring (0..100°C),
    // rather than a ring each.
    property bool   sidebarStatsTempArcs: true
    // A ring that stays over its threshold says so in its card (SysStats), and can
    // send one notification. Load is a percentage (CPU and RAM), temperature °C.
    property bool   sidebarStatsAlerts: true
    property bool   sidebarStatsAlertNotify: false
    property int    sidebarStatsAlertLoad: 90
    property int    sidebarStatsAlertTemp: 85
    // What middle-click opens in the terminal. "" = the first of btop, htop, top
    // that's installed (SysStats resolves it; never written back).
    property string sidebarStatsMonitor: ""

    // ══ Sidebar — clips & recording ═══════════════════════════════════════════
    // A replay buffer and a recorder on the dock's edge: a button, and its controls
    // in a panel beside it (modules/bar/SideClips, modules/panels/ClipsPanel,
    // services/Clips, gpu-screen-recorder). Off by default: a buffer records the
    // screen continuously, which a published config must never start on its own.
    // Every value below is re-validated by clips.js `settings()` before it reaches
    // the recorder — this file is hand-editable.
    // On = placed on the sidebar (sidebarLayout). The button only: `clipsBuffer` is
    // what records.
    readonly property bool clips: root.sidebarPlaced("clips")
    // Clipping: while on, the replay buffer is KEPT running — started with the
    // shell, restarted if it dies — so a clip is always one key away. Its own
    // switch, off by default: turning on the pill must never start a recording.
    property bool   clipsBuffer: false
    // Where clips and recordings land. "" = ~/Videos/Clips (Clips.saveDir resolves
    // it, `~` included; never written back — see Portability in CLAUDE.md).
    property string clipsDir: ""
    // What to capture: "" = the monitor focused when the buffer starts, a connector
    // name ("DP-1"), or "portal" (the desktop portal's own picker, asked once).
    property string clipsTarget: ""
    // The buffer's length, and where it's held ("ram" or "disk").
    property int    clipsBufferSeconds: 120
    property string clipsStorage: "ram"
    // What "clip it" saves: 0 = the whole buffer, else 10/30/60/300/600/1800.
    property int    clipsSaveSeconds: 0
    property int    clipsFps: 60
    // "auto" = constant quality at clipsQuality; "cbr" = clipsKbps, a fixed size.
    property string clipsBitrateMode: "auto"
    property string clipsQuality: "very_high"
    property int    clipsKbps: 40000
    property string clipsCodec: "auto"
    property string clipsContainer: "mp4"
    // Height cap: "original", "2160", "1440", "1080", "720".
    property string clipsResolution: "original"
    property bool   clipsCursor: true
    property bool   clipsDesktopAudio: true
    property bool   clipsMic: false
    // Desktop and mic as separate audio tracks rather than one mix.
    property bool   clipsSplitAudio: false
    // A saved clip opens a card beside the button for a moment (ClipsPeek), with its thumbnail.
    property bool   clipsPeek: true
    // …and sends a notification too (for when the sidebar is hidden).
    property bool   clipsNotify: false
    // The file manager "open folder" / "show in folder" use: "" = automatic (Nautilus if installed, else the first of
    // Dolphin, Thunar, Nemo, PCManFM, Caja), or one of clips.js FILE_MANAGERS' ids. Never the default
    // handler for directories — on some setups that is a terminal browser.
    property string clipsFileManager: ""
    // Name a clip after the window it was cut in ("Elden-Ring_Replay_…"), so the library can group
    // by game. Off leaves the recorder's own "Replay_…" names. (scripts/clips-run.py `window_label`.)
    property bool   clipsNameByWindow: true
    // "Clip it" also keeps recording this many more seconds first (0 = save at once): the end of a
    // play you only reacted to afterwards. Clips.saveClip → clips.js aheadPlan.
    property int    clipsAhead: 0
    // "Stop after…" for a recording: "off", "5m", "10m", "30m", "1g", "2g" or "4g" (clips.js RECORD_LIMITS).
    property string clipsRecordLimit: "off"
}
