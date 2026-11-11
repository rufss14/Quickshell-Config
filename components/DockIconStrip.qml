pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Pipewire
import "../config"
import "../services"
import "../state"
import "../services/dock.js" as DockJs
import "../services/workspaces.js" as Wsp
import "dock"

// ── DockIconStrip ────────────────────────────────────────────────────────────
// The row of app buttons both docks draw — the persistent one (DockHost, welded
// into the screen frame) and the overview's (OverviewDock). What it shows and
// what a click does come from the Taskbar service; this file is presentation and
// gesture only.
//
//     [ ⊞ ] [ pinned… ] [ running, unpinned… ]
//
// ── Windows' rules ────────────────────────────────────────────────────────────
//   click         launch · bring the app forward · (already focused) next window
//   shift-click   a new window
//   middle-click  close its most recent window (one per click, never all at once)
//   right-click   the jump list: the app's own actions, new window, pin, close
//   hover         after a dwell, a live preview of every window it has open
//   drag          reorder the pins; drop a running app among them to pin it
//
// ── One list, one Repeater, and not a JS array ────────────────────────────────
// This used to be two strips (pinned, running) behind a divider, each a Loader
// with `width: item ? item.width : 0`. A Loader whose size is set explicitly
// RESIZES ITS ITEM to match — so a strip loaded while nothing was running pinned
// its Row to 0px and then read that 0 back forever. That is why the persistent
// dock never showed an app: it is built at shell start, before any window is
// known. (The overview's copy is built on open, with apps already running, so it
// froze at whatever count it opened with instead.)
//
// Now: one list in Windows' order (see Taskbar.apps), fed through a ScriptModel.
// A bare JS array as a Repeater model rebuilds EVERY delegate on any change, so
// an app opening would reset every button's hover, press and entrance state.
// ScriptModel diffs, so an app opening adds one button and a pin moving moves
// one — the rest are never touched.
//
// ── Buttons are placed by hand ────────────────────────────────────────────────
// Slot i sits at `lead + i*slot`, animated. No positioner: a Row skips 0-sized
// children and owns its children's x, and both got in the way of the two things
// this needs — the neighbours of a dragged button stepping aside (dock.js
// shift()), and every button gliding to its new slot when an app opens, closes
// or moves. `animLength` eases the strip's own length on the same curve, so the
// dock's edge and its last button travel together.
//
// ── What it doesn't own ───────────────────────────────────────────────────────
// Its surface, the preview card and the context menu all belong to the host.
// The strip decides WHEN the preview is up (`previewKey`) and where it points
// (`previewCenter`); the host draws DockPreview outside any clip — a card
// parented in here would be cut off by the very dock it hangs from.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    // DockAppButton maps drag points into the track; its own file can't see the id.
    readonly property Item trackItem: track

    // ══ Set by the host ═══════════════════════════════════════════════════════
    // Which screen edge the strip sits against. Decides the main axis, which side
    // of a button is "outward" (the running indicator's side) and which way a
    // hovered icon lifts. "top" is the dock as a TOP-BAR module (widgets/DockPill): the
    // indicators sit on the windows' side (below), menus anchor under a button. Anything
    // else reads as "bottom".
    property string edge: "bottom"
    readonly property bool vertical: root.edge === "left" || root.edge === "right"

    // Where a launcher opened from here should appear (null = the first screen),
    // and the monitor a focus should land on — see Hypr.goToToplevel.
    property var screen:  null
    property var monitor: null

    // The host's ContextMenu. A menu parented in here could only ever open inside
    // the strip, a few dozen px deep, at the very edge of the screen.
    property var contextMenu: null

    // The most the strip may take along its main axis; past it, it scrolls.
    property real maxLength: Infinity

    // The host binds this to its DockPreview's hover, so moving from a button up
    // onto the preview keeps the preview open.
    property bool previewHovered: false

    // Which running apps this strip shows (Config.dockScope): "all", only those
    // with a window on `monitor`, or only those on its current "workspace". Pins
    // still show everywhere; an app with no window in scope draws as not running
    // here, and a click on it still switches to it wherever it is.
    property string scope: "all"

    // Arranging only (the settings page's copy): drags reorder and pin exactly as
    // on the dock, but nothing launches, focuses, previews or opens a menu.
    property bool editMode: false

    // ── Its size, and whose hover it wears ─────────────────────────────────────
    // The sidebar's dock is a sidebar module, sized and answering like a bar
    // module (Config.sidebarCell, and CellFeedback's ladder: a tint on hover, a
    // ripple on press, no bounce). The overview's dock and the settings page's
    // pictures keep the dock's own size and feel: these defaults.
    property int  buttonSize: Config.dockButtonSize
    property int  iconPx:     Config.dockIconPx
    property bool barFeedback: false
    // ── The ii look (Config.dockStyle === "ii") ───────────────────────────────
    // End-4's dock, as far as the buttons go: flat rounded buttons with the bar's quiet
    // wash (no swell, no lift — `flat`), one dot per window up to three instead of the
    // pip and the travelling glider, a hairline between groups, a keep button before the
    // apps (auto-hide only: it holds the dock out) and an overview button after them.
    // The card around the strip stays whatever the host makes it (welded or floating).
    // The bar's dock opts out of both (2026-11-08, the user's pick: "bar-sized, no
    // magnification"): a bar module is a row of pills, not a dock of its own style.
    property bool iiAllowed: true
    property bool magnifyAllowed: true
    readonly property bool ii:   root.iiAllowed && Config.dockStyle === "ii"
    readonly property bool flat: root.barFeedback || root.ii
    // Magnification is a swell; a flat dock has none.
    readonly property bool magnifyOn: Config.dockMagnify && !root.ii && root.magnifyAllowed
    // Icons in the palette's colours, when the shell asks for it (Config.colorizeIcons — the
    // tray pill's rule): since 2026-10-31 end-4's way (MonoIconEffect — the whole icon,
    // mostly desaturated, a tenth of the primary over it), where it was the whole icon
    // colorized, which sank a logo on a disc into a flat blob, and then for a day a glyph
    // cut out of it (ThemedAppIcon), which drew some blank. Off: the icons' own colours.
    readonly property bool  tinted:   Config.colorizeIcons
    // The dock is out (its host's reveal). Each time it comes out the icons rise
    // out of the edge one after another (AppButton's `rise`). The overview's dock
    // is built on open, which its own entrance covers, so it leaves this true.
    property bool shown: true
    // Every rounded thing on a button: the bar's corner with its feedback, the
    // dock's own otherwise. With the feedback it is the sidebar's inner pill less the gap
    // it keeps round a cell, so the wash, run pills and focus ring are concentric with it.
    // The pill it stands in: the sidebar's (its own roundness once unlinked in Style).
    property int roundness: Config.sideRoundness
    readonly property real cellRadius: root.barFeedback ? Tokens.corner(Config.barShape, Math.max(0, root.roundness - Tokens.spacingXs))
                                     : root.ii          ? Tokens.radiusPill
                                                        : Tokens.radiusSm

    // ══ What this strip draws ═════════════════════════════════════════════════
    // Taskbar's lists, or this monitor's cut of them. Everything below reads these,
    // never Taskbar.apps/groups directly, so a per-monitor dock is consistent all
    // the way down (and DockPreview asks groupFor() too).
    readonly property bool _scoped: (root.scope === "monitor" || root.scope === "workspace")
                                    && root.monitor !== null
    readonly property var _local: !root._scoped ? null
        : root.scope === "monitor"
        ? (Taskbar.monitorGroups[root.monitor.name] ?? null)
        : (Taskbar.workspaceGroups[root.monitor.activeWorkspace?.id ?? -1] ?? null)
    readonly property var groups: root._scoped ? (root._local ? root._local.byKey : ({}))
                                               : Taskbar.groups
    readonly property var apps:   root._scoped ? DockJs.order(Taskbar.pinned, root._local ? root._local.order : [])
                                               : Taskbar.apps
    function groupFor(key) { return root.groups[key] ?? null }

    // ── The inner pill's runs (Config.dockInnerPill) ──────────────────────────
    // Running apps side by side share one pill: the same run arithmetic as the
    // bar's workspaces pill and its inner pills (workspaces.js runs()), looked up
    // by a run's first slot. A plain map, NOT a Repeater model — see RunPill.
    readonly property var runLengths: {
        const out = ({})
        const runs = Wsp.runs(root.apps.map(k => root.groups[k] !== undefined))
        for (let i = 0; i < runs.length; i++) out[runs[i].start] = runs[i].length
        return out
    }

    // ══ Read by the host ══════════════════════════════════════════════════════
    // The app whose preview should be up, "" for none. Owned by the timers below;
    // the host only reads it (and DockPreview calls closePreview()).
    property string previewKey: ""

    // Centre of that app's button along the main axis, in THIS item's
    // coordinates — the slot it will rest in, not its animated position, so the
    // preview glides on its own curve instead of chasing the button's.
    readonly property real previewCenter: {
        const k = root.previewKey
        let at = -1
        if (k === "__launcher")      at = root.launcherAt
        else if (k === "__keep")     at = 0
        else if (root.isSpecial(k))  at = root.tailPos(k)
        else {
            const i = root.apps.indexOf(k)
            if (i >= 0) at = root.slotPos(i)
        }
        return at < 0 ? -1 : at + root.button / 2 - root.scroll
    }

    // The buttons that aren't apps get the same hover label as a pinned app that
    // isn't running (DockPreview shows a name and a line about it), through these
    // reserved keys — "__" can't begin a desktop-entry id.
    function isSpecial(key) { return key.startsWith("__") }

    // Anything that must keep an auto-hidden dock on screen: a drag in flight, its
    // menu open, its preview up or being reached for.
    readonly property bool engaged: root.dragKey !== "" || root._menuOpen
                                    || root.previewKey !== "" || root.previewHovered
                                    || root.fileDropActive || root.insertKey !== ""

    // Something was launched or focused. The overview closes itself on this.
    signal activated()

    // ══ Geometry ══════════════════════════════════════════════════════════════
    readonly property int button: root.buttonSize
    readonly property int gap:    Tokens.spacingXs
    readonly property int slot:   root.button + root.gap
    // What stands before the apps: the keep button (ii, auto-hide on) and the start
    // button, a slot each, then — ii only — a gap for the hairline between the groups.
    readonly property bool keepShown: root.ii && Config.sidebarAutoHide && !root.editMode
    readonly property int  leadSlots: (Config.dockShowLauncher ? 1 : 0) + (root.keepShown ? 1 : 0)
    readonly property int  launcherAt: root.keepShown ? root.slot : 0
    // The sidebar's dock gets the same gap after its start button (2026-10-31): the launcher
    // is the dock's main button there, set apart from the apps by a divider.
    readonly property int  lead:   root.leadSlots * root.slot
                                   + ((root.ii || root.barFeedback) && root.leadSlots > 0 ? root.divider : 0)

    readonly property int count:    root.apps.length
    // Pins come first in Taskbar.apps (dock.js order()), so the first `pinCount`
    // slots are exactly the pins.
    readonly property int pinCount: Taskbar.pinned.length

    // ── Pinned | running ──────────────────────────────────────────────────────
    // On the sidebar a divider stands between the pins and the apps that are only running
    // (2026-10-31, the user's pick), in a gap of `divider` after the last pin. Only at rest:
    // a drag or an app coming in from the launcher closes it, so every bit of drag and drop
    // arithmetic (dock.js dropTarget/insertTarget/shift, all in whole slots) stays as it was;
    // the buttons glide shut and open again on their own position Behavior. Every place that
    // says where a slot IS asks `slotPos`; a point back to a slot goes through `unGap`.
    readonly property real pinGap: root.barFeedback && root.pinCount > 0 && root.count > root.pinCount
                                   && root.dragKey === "" && root.insertAt < 0 ? root.divider : 0
    function slotPos(i) { return root.lead + i * root.slot + (i >= root.pinCount ? root.pinGap : 0) }
    // A distance along the apps (from `lead`) with the pin gap taken out, so whole slots work.
    function unGap(main) { return main >= root.pinCount * root.slot + root.pinGap ? main - root.pinGap : main }

    // One extra slot while an app the dock doesn't have yet is being dragged in —
    // the gap it will land in (see insertAt).
    readonly property int drawnCount: root.count + (root.insertAt >= 0 && root.insertFrom < 0 ? 1 : 0)

    // ── The far end: Downloads and Trash, after a divider (macOS's stacks) ────
    readonly property bool showDownloads: Config.dockShowDownloads
    readonly property bool showTrash:     Config.dockShowTrash
    readonly property var  pinnedFiles: FilePins.files
    // A file dragged over the dock opens a "+" slot at the end of the pinned
    // files: drop it there to pin it (FilePins).
    readonly property bool pinSlot: root.fileDropActive && !root.editMode

    // The far end, in order — pinned files and folders, the drop slot, Downloads,
    // Trash. Each key doubles as its button's preview key ("__" = not an app).
    readonly property var tailKeys: {
        const k = []
        for (let i = 0; i < root.pinnedFiles.length; i++) k.push("__file:" + i)
        if (root.pinSlot)       k.push("__pin")
        if (root.showDownloads) k.push("__downloads")
        if (root.showTrash)     k.push("__trash")
        if (root.ii)            k.push("__overview")
        return k
    }
    readonly property int  tailCount: root.tailKeys.length
    // What the keyboard can land on at the far end: everything but the drop slot.
    readonly property var  kbTail: root.tailKeys.filter(k => k !== "__pin")

    function tailPos(key) {
        const j = root.tailKeys.indexOf(key)
        return j < 0 ? -1 : root.tailStart + j * root.slot
    }
    function fileFor(key) {
        return key.startsWith("__file:") ? (root.pinnedFiles[parseInt(key.slice(7))] ?? null) : null
    }
    readonly property int  divider:   Tokens.spacingLg

    // Where the apps end (past the last one's gap), and where the tail begins.
    readonly property real appsEnd:   root.lead + root.drawnCount * root.slot + root.pinGap
    readonly property real tailStart: root.appsEnd + (root.tailCount > 0 && root.appsEnd > 0 ? root.divider : 0)

    readonly property real fullLength:
        root.tailCount > 0 ? root.tailStart + root.tailCount * root.slot - root.gap
                           : Math.max(0, root.appsEnd - root.gap)

    property real animLength: root.fullLength
    Behavior on animLength {
        NumberAnimation {
            duration: Motion.emphasized
            easing.bezierCurve: Motion.emphasizedDecel
            easing.type: Easing.BezierSpline
        }
    }

    // How far the content runs past `maxLength`, and how far it's scrolled in.
    readonly property real overflow: Math.max(0, root.fullLength - root.maxLength)
    property real scroll: 0
    onOverflowChanged: root.scroll = Math.max(0, Math.min(root.overflow, root.scroll))

    implicitWidth:  root.vertical ? root.button : Math.min(root.animLength, root.maxLength)
    implicitHeight: root.vertical ? Math.min(root.animLength, root.maxLength) : root.button

    // ── Motion character of a button ──────────────────────────────────────────
    // Scale factors, not distances, so there is no token for them; named once so
    // the icon, its sourceSize and the press all agree.
    // With the bar's feedback there's no bounce or lift: the tint and the ripple
    // say it, as they do on every top-bar control.
    readonly property real hoverScale: root.flat ? 1.0 : 1.08
    readonly property real pressScale: root.flat ? 1.0 : 0.86
    readonly property int  hoverLift:  root.flat ? 0 : Tokens.spacingXs

    // ── Arriving as a row ─────────────────────────────────────────────────────
    // True until the first frame: buttons built with the strip swell in one after
    // another; one built later (an app opening) swells in at once.
    property bool _fresh: true
    Component.onCompleted: Qt.callLater(() => root._fresh = false)
    // Never negative: a delegate that is being built or torn down can report index -1, and a
    // PauseAnimation then warns "Cannot set a duration of < 0" (it did, 4 times in the log).
    function entranceDelay(i) { return Math.max(0, Math.min(i * Motion.stagger, Motion.staggerCap)) }

    // ── Where the indicators stand ────────────────────────────────────────────
    // The running pip, the level bars and the focus glider sit on ONE side of the
    // button, across the strip. The overview's dock keeps them on the outward side
    // (Windows 11's pill). The sidebar's (`barFeedback`) puts them on the edge
    // toward the windows, a little heavier, and a running app is a dot — the
    // user's pick (2026-10-02), with the sidebar's cells tightened round the icon.
    //
    // ── One calm mark (2026-10-31) ────────────────────────────────────────────
    // On the sidebar the dock's marks are the sidebar's OWN active mark (CellFeedback): a
    // borderChrome line spacingXs in from the cell's inner edge, the glyph's length for the
    // focused app. Running is the same line short and muted rather than a dot, and an app
    // making sound stretches its line with how loud it is rather than growing three level
    // bars — one line per app, whatever it's doing (the user's pick for a quieter sidebar:
    // a dot, a long pill and three bars side by side read as noise).
    readonly property bool indicatorsInward: root.barFeedback
    readonly property int  indicatorThick: root.barFeedback ? Tokens.borderChrome : Tokens.spacingXs
    // The focused app's mark on the sidebar: CellFeedback's length, so every active mark on
    // the edge is one size.
    readonly property real focusMarkLen: root.barFeedback
        ? Math.max(0, Math.min(Config.sidebarGlyphPx, root.button - Tokens.spacingMd * 2))
        : Tokens.spacingXl
    // Across the strip, where an indicator `w` deep goes (x on a side, y along
    // the bottom), measured as the button's own coordinates.
    function indicatorAt(w) {
        const fromEdge = root.indicatorsInward ? root.button - w - Tokens.spacingXs : Tokens.spacingXs
        return root.edge === "left" || root.edge === "top" ? fromEdge : root.button - w - fromEdge
    }
    // The indicator hugs the button's low-coordinate side (x 0 on a side, y 0
    // along the bottom): what grows (the level bars) grows away from it.
    readonly property bool indicatorLow:
        root.vertical ? (root.edge === "left") !== root.indicatorsInward
                      : root.edge === "top" ? !root.indicatorsInward : root.indicatorsInward

    // ── The focus indicator ───────────────────────────────────────────────────
    // ONE accent pill that travels to the focused app, stretching across the
    // ground it covers (the workspace indicator's two edges, Motion.trail), rather
    // than one pip shrinking while another grows. Only while positions are at rest
    // and the focused app's own indicator says nothing more: a drag or an app
    // coming in from the launcher moves slots under it, a playing app shows level
    // bars in that place, an urgent one its warning pip. The button's own pip
    // takes over then (AppButton's `pip`), as it always did.
    readonly property int focusIndex: {
        for (let i = 0; i < root.apps.length; i++) {
            const g = root.groups[root.apps[i]]
            if (g && g.focused) return i
        }
        return -1
    }
    readonly property bool gliding: {
        if (root.ii || root.focusIndex < 0 || root.dragKey !== "" || root.insertAt >= 0) return false
        const k = root.apps[root.focusIndex]
        const g = root.groups[k]
        return (Taskbar.audio[k] ?? null) === null && !(g && g.urgent)
            && !(Taskbar.reported[k]?.urgent ?? false)
    }

    // ── Leaving ───────────────────────────────────────────────────────────────
    // A Repeater destroys a button the moment its app goes, so what leaves is a
    // copy: its icon where it stood, sinking and fading while the neighbours close
    // the gap. Only for an app that left the dock everywhere (closed, or unpinned
    // from the menu): a scoped dock dropping an app another monitor or workspace
    // still shows isn't an exit, and an icon dragged off already has its poof.
    ListModel { id: ghosts }
    property int    _ghostSeq: 0
    property string _poofKey: ""
    function _leave(key, iconPath, x, y) {
        if (key === root._poofKey) { root._poofKey = ""; return }
        if (Taskbar.apps.indexOf(key) >= 0 || Motion.exit <= 0) return
        ghosts.append({ uid: ++root._ghostSeq, iconPath: iconPath, gx: x, gy: y })
    }
    function _ghostDone(uid) {
        for (let i = 0; i < ghosts.count; i++)
            if (ghosts.get(i).uid === uid) { ghosts.remove(i); return }
    }

    // ── Magnification (Config.dockMagnify) ────────────────────────────────────
    // Icons swell toward the pointer on a cosine falloff (dock.js magnify), growing
    // OUT of the dock from its outer edge, macOS-style. The host gives its clip
    // `magnifyHeadroom` of room on the inward side for that (the blob lobe and the
    // input mask stay the dock's own box). A dock that scrolls has to clip its
    // strip, so there the swell stays inside each button instead.
    // ── How much it's magnifying right now, 0 → 1 ─────────────────────────────
    // Eased both ways, so icons swell as the pointer arrives and settle back as
    // it leaves — rather than snapping flat the frame the pointer is gone. While
    // it eases out, the icons stay swollen around the LAST place the pointer was.
    // Held while a preview is up, too: moving from the dock onto its preview leaves
    // the strip, and the swell (which the preview stands on) must not sink under
    // it. It stays around the last pointer position until the preview closes.
    //
    // Except under a MELTED preview or menu (`flatUnderPreview`, set by the host):
    // those weld flush onto the dock's face, and a swell there pokes up into the
    // join as a bump. So while one is open the swell relaxes and the face lies flat.
    property bool flatUnderPreview: false
    readonly property bool wantMagnify: root.magnifyOn
                                        && (root.pointerIn || root.previewKey !== "")
                                        && !(root.flatUnderPreview && (root.previewKey !== "" || root._menuOpen))
                                        && root.dragKey === "" && !root.editMode
    property real magnifyAmount: root.wantMagnify ? 1 : 0
    Behavior on magnifyAmount {
        NumberAnimation {
            duration: root.wantMagnify ? Motion.standard : Motion.emphasized
            easing.type: root.wantMagnify ? Motion.enter : Motion.travel
        }
    }
    readonly property bool magnifying: root.magnifyOn && root.magnifyAmount > 0.001
                                       && root.dragKey === "" && !root.editMode

    readonly property bool magnifyOut: root.magnifyOn && root.overflow === 0
    // Config.dockMagnifyPeak is the setting (Settings › Dock). Inside a scrolling
    // dock the swell has to fit its button, so it's capped at button ÷ icon there.
    readonly property real magnifyMax: root.magnifyOut
        ? Config.dockMagnifyPeak
        : Math.min(Config.dockMagnifyPeak, root.button / root.iconPx)
    // What an icon grows from: the dock's outer edge (so it rises into the
    // screen), or its own centre when it has to stay inside.
    readonly property int magnifyOrigin: !root.magnifyOut        ? Item.Center
                                       : root.edge === "left"    ? Item.Left
                                       : root.edge === "right"   ? Item.Right
                                       :                           Item.Bottom
    // How far past the dock's inner face a fully swollen button reaches.
    readonly property int magnifyHeadroom:
        root.magnifyOut ? Math.ceil(root.button * (root.magnifyMax - 1)) + root.hoverLift : 0
    readonly property real magnifyRange: root.slot * 2

    // The pointer along the dock, remembered while it's outside so the ease-out
    // above settles around where it was (a HoverHandler's point resets on exit).
    readonly property real _pointerLive:
        (root.vertical ? stripHover.point.position.y : stripHover.point.position.x) + root.scroll
    property real pointerMain: 0
    on_PointerLiveChanged: if (stripHover.hovered) root.pointerMain = root._pointerLive
    readonly property bool pointerIn: stripHover.hovered
    onPointerInChanged: if (root.pointerIn) root.pointerMain = root._pointerLive

    // One button's scale at `center` (along the track), at the current strength.
    function magnifyAt(center) {
        return 1 + (DockJs.magnify(center - root.pointerMain, root.magnifyRange, root.magnifyMax) - 1)
                 * root.magnifyAmount
    }

    // ── The blob swells with it ───────────────────────────────────────────────
    // The swell, for the welded dock's host to hand the blob — so the material
    // bulges around the magnified icons instead of the icons poking out of the
    // dock's outline. In THIS item's coordinates.
    // How far the swell rises past the strip's inner face right now — its peak,
    // at the current strength. The host stands the preview on this.
    readonly property real magnifyPeakNow: root.magnifying && root.magnifyOut
        ? root.button * (root.magnifyMax - 1) * root.magnifyAmount + root.hoverLift : 0

    // Keeps the swell off the dock's rounded ends (the host sets it to the
    // corner's reach inside the strip); a layer ending ON the corner notched it.
    property real swellInset: 0

    readonly property var magnifyBoxes: {
        if (!root.magnifying || !root.magnifyOut) return []
        // A smooth bell under the pointer (dock.js magnifyBell), five layers deep,
        // kept within the dock's own length.
        return DockJs.magnifyBell(root.pointerMain - root.scroll, root.magnifyRange, root.magnifyMax,
                                  root.magnifyAmount, root.button, root.hoverLift, root.edge,
                                  root.swellInset, root.fullLength - root.swellInset, 4)
    }

    // The icon is rasterised at the largest size it can be shown at.
    readonly property int iconRaster:
        Math.ceil(root.iconPx * Math.max(root.hoverScale, root.magnifyOn ? root.magnifyMax : 1))

    // ══ Preview timing ════════════════════════════════════════════════════════
    // Interaction timings, not animation durations, so they don't come from
    // Motion: Motion's durations drop to 0 with motion switched off, and a 0ms
    // dwell would flash a preview open under every icon the pointer crossed.
    // 400ms is Windows' own hover time; the grace is what lets the pointer cross
    // the gap from a button to its preview without the preview closing.
    readonly property int previewDwell: 400
    readonly property int previewGrace: 250

    property string hoverKey: ""
    // The button just clicked. Its preview stays down until the pointer leaves it,
    // or clicking an app to focus it would pop a preview straight back up over the
    // window you just asked for.
    property string _suppressKey: ""

    Timer {
        id: dwell
        interval: root.previewDwell
        onTriggered: root._openPreview()
    }
    Timer {
        id: grace
        interval: root.previewGrace
        onTriggered: root.previewKey = ""
    }

    function _openPreview() {
        if (root.hoverKey === "" || root.hoverKey === root._suppressKey) return
        if (root.dragKey !== "" || root._menuOpen) return
        root.previewKey = root.hoverKey
    }

    function closePreview() {
        dwell.stop()
        grace.stop()
        root.previewKey = ""
    }

    // One button per wheel notch (120 = one notch, Qt's own unit).
    function _scrollBy(delta) {
        root.scroll = Math.max(0, Math.min(root.overflow, root.scroll - delta / 120 * root.slot))
    }

    function _hover(key, on) {
        if (root.editMode) return
        if (on) root.hoverKey = key
        else if (root.hoverKey === key) root.hoverKey = ""
    }

    onHoverKeyChanged: {
        if (root.hoverKey !== root._suppressKey) root._suppressKey = ""
        if (root.hoverKey !== "") {
            grace.stop()
            // Already showing one: follow the pointer at once, the way Windows'
            // previews slide from icon to icon. Otherwise wait out the dwell.
            if (root.previewKey !== "" && root.hoverKey !== root._suppressKey)
                root.previewKey = root.hoverKey
            else
                dwell.restart()
        } else {
            dwell.stop()
            if (!root.previewHovered) grace.restart()
        }
    }

    onPreviewHoveredChanged: {
        if (root.previewHovered) grace.stop()
        else if (root.hoverKey === "") grace.restart()
    }

    // The previewed app left the dock (its last window closed, and it isn't
    // pinned) — there's no button left for the preview to hang from.
    Connections {
        target: root
        function onAppsChanged() {
            if (root.previewKey !== "" && !root.isSpecial(root.previewKey)
                && root.apps.indexOf(root.previewKey) < 0)
                root.closePreview()
        }
    }

    // ══ Drag ══════════════════════════════════════════════════════════════════
    // Tracked by KEY, not index: committing a move reorders the model, and an
    // index-keyed "which button is dragged" would hand the drag to whichever
    // neighbour inherited the old index for the frame in between.
    property string dragKey:  ""
    property int    dragFrom: -1
    property int    dragTo:   -1
    // Main-axis position of the dragged button, in `track` coordinates.
    property real   dragPos:  0
    // Pulled well clear of the dock, into the screen: letting go unpins it (a pin
    // only — a running app has nothing to unpin). macOS's "drag off to remove".
    property bool   dragOff:  false
    // Where the pointer is, in scene coordinates, while dragging — for the poof.
    property point  dragScene: Qt.point(0, 0)

    // An icon was dragged off and unpinned, here (scene coordinates). The host
    // plays the poof; it can't be drawn in the strip, whose clip ends at the dock.
    signal unpinnedAt(real sceneX, real sceneY, string iconPath)

    // ── An app coming in from the launcher ────────────────────────────────────
    // The host sets these from UiState's drag while the pointer is over the dock:
    // the key being dragged, and the pin slot it would land in (-1 = not over the
    // dock). `insertFrom` is where the dock already draws it (-1 if nowhere), so
    // the neighbours shift exactly as they would for an internal drag.
    property string insertKey: ""
    property int    insertAt:  -1
    readonly property int insertFrom: root.insertKey !== "" ? root.apps.indexOf(root.insertKey) : -1

    // The slot under a point on the dock, in THIS item's coordinates — for the
    // host's hit-test while an app is dragged in (center measured like dropTarget).
    function insertionAt(x, y) {
        const main = root.unGap((root.vertical ? y : x) + root.scroll - root.lead)
        return DockJs.insertTarget(root.insertFrom, main, root.slot, root.count, root.pinCount)
    }

    function _beginDrag(key, index, pos) {
        root.closePreview()
        root.dragKey  = key
        root.dragFrom = index
        root.dragTo   = index
        root.dragPos  = pos
        root.dragOff  = false
    }

    function _dragTo(pos) {
        root.dragPos = pos
        root.dragTo = DockJs.dropTarget(root.dragFrom, pos + root.button / 2 - root.lead,
                                        root.slot, root.count, root.pinCount)
    }

    // Commit BEFORE clearing the drag: while dragKey is still set the dragged
    // button's position isn't animated, so the model move lands it without a
    // detour, and clearing afterwards lets it glide from the pointer to its slot.
    // The neighbours are already standing where the move puts them (shift()
    // predicted it), so they don't move at all.
    function _endDrag(commit) {
        const from = root.dragFrom
        const to   = root.dragTo
        const key  = root.dragKey
        if (commit && root.dragOff && from >= 0 && from < root.pinCount) {
            root._poofKey = key
            root.unpinnedAt(root.dragScene.x, root.dragScene.y, Taskbar.iconFor(key))
            Taskbar.unpin(key)
            // Still running: its button stays, so there's no exit for the poof to replace.
            if (Taskbar.apps.indexOf(key) >= 0) root._poofKey = ""
        } else if (commit && !root.dragOff && from >= 0 && to >= 0 && to !== from) {
            if (from < root.pinCount) Taskbar.movePin(from, to)
            else                      Taskbar.pin(key, to)
        }
        root.dragKey  = ""
        root.dragFrom = -1
        root.dragTo   = -1
        root.dragOff  = false
    }

    // ══ Clicks ════════════════════════════════════════════════════════════════
    function _activate(key, btn) {
        if (root.editMode) return
        const wasRunning = root.groupFor(key) !== null || Taskbar.groupFor(key) !== null
        root._suppressKey = key
        root.closePreview()
        if (!Taskbar.activate(key, root.monitor, root.groups)) return
        if (!wasRunning) btn.bounce()
        root.activated()
    }

    function _newWindow(key, btn) {
        if (root.editMode) return
        root.closePreview()
        if (!Taskbar.launch(key)) return
        btn.bounce()
        root.activated()
    }

    // One window per middle-click, the one you had in front last: closing a whole
    // app on one click is how a stray middle-button press loses work.
    function _closeRecent(key) {
        if (root.editMode) return
        const g = root.groupFor(key)
        if (!g) return
        root.closePreview()
        Taskbar.close(g.recent ?? g.windows[0])
    }

    function _toggleLauncher() {
        if (root.editMode) return
        root.closePreview()
        UiState.overviewOpen = false
        if (UiState.launcherOpen) {
            UiState.launcherOpen = false
            return
        }
        UiState.activeScreen = root.screen
        UiState.launcherOpen = true
    }

    // ══ Keyboard ══════════════════════════════════════════════════════════════
    // SUPER+T puts the keyboard on the dock (the host calls kbStart()): arrows walk
    // it, Home/End jump, Enter or Space opens, the Menu key or Shift+F10 opens the
    // jump list, Escape leaves. The focused app's preview is up while it's
    // focused, the way Windows shows thumbnails for a keyboard-focused button.
    // -1 is the launcher button, -2 is "not in keyboard mode".
    property int kbIndex: -2
    readonly property bool kbActive: root.kbIndex > -2
    signal kbDone()

    function kbStart() {
        root.kbIndex = root.kbSpan > 0 ? 0 : (Config.dockShowLauncher ? -1 : -2)
        if (!root.kbActive) { root.kbDone(); return }
        root.forceActiveFocus()
        root._kbFollow()
    }

    function kbStop() {
        if (!root.kbActive) return
        root.kbIndex = -2
        root.closePreview()
        root.kbDone()
    }

    // Keep the focused button on screen, and its preview up.
    function _kbFollow() {
        if (root.kbIndex >= 0) {
            const start = root.kbTailKey !== "" ? root.tailPos(root.kbTailKey)
                                                : root.slotPos(root.kbIndex)
            const view  = Math.min(root.fullLength, root.maxLength)
            if (start < root.scroll) root.scroll = start
            else if (start + root.button > root.scroll + view)
                root.scroll = Math.min(root.overflow, start + root.button - view)
            dwell.stop()
            grace.stop()
            root.previewKey = root.kbTailKey !== "" ? root.kbTailKey : (root.apps[root.kbIndex] ?? "")
        } else {
            root.closePreview()
        }
    }

    function _kbOpen() {
        if (root.kbIndex === -1) {
            root.kbStop()
            root._toggleLauncher()
            return
        }
        if (root.kbTailKey !== "") {
            const key = root.kbTailKey
            const p = root._tailScene(key)
            root.kbStop()
            root._activateTail(key, p.x, p.y)
            return
        }
        const btn = buttons.itemAt(root.kbIndex)
        const key = root.apps[root.kbIndex]
        root.kbStop()
        if (btn && key) root._activate(key, btn)
    }

    // A far-end button's anchor point for a menu, in scene coordinates.
    function _tailScene(key) {
        const b = tailButtons.itemAt(root.tailKeys.indexOf(key))
        return b ? b.mapToItem(null, b.width / 2, root.edge === "bottom" ? 0 : root.edge === "top" ? b.height : b.height / 2)
                 : Qt.point(0, 0)
    }

    function _kbMenu() {
        if (root.kbTailKey !== "") {
            const p = root._tailScene(root.kbTailKey)
            root._openTail(root.kbTailKey, p.x, p.y)
            return
        }
        const btn = buttons.itemAt(root.kbIndex)
        if (!btn) return
        const p = btn.mapToItem(null, btn.width / 2, root.edge === "bottom" ? 0 : root.edge === "top" ? btn.height : btn.height / 2)
        root._openMenu(btn.key, p.x, p.y)
    }

    // The app at `index` in this strip's order — SUPER+ALT+n.
    function activateAt(index) {
        const btn = buttons.itemAt(index)
        const key = root.apps[index]
        if (btn && key) root._activate(key, btn)
    }

    Keys.onPressed: function(event) {
        if (!root.kbActive) return
        const back = root.vertical ? Qt.Key_Up   : Qt.Key_Left
        const fwd  = root.vertical ? Qt.Key_Down : Qt.Key_Right
        let move = null
        if (event.key === back)                move = -1
        else if (event.key === fwd)            move = 1
        else if (event.key === Qt.Key_Home)    move = "home"
        else if (event.key === Qt.Key_End)     move = "end"

        if (move !== null) {
            root.kbIndex = DockJs.stepFocus(root.kbIndex, move, root.count + root.kbTail.length,
                                            Config.dockShowLauncher)
            root._kbFollow()
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
                   || event.key === Qt.Key_Space) {
            root._kbOpen()
        } else if (event.key === Qt.Key_Menu
                   || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root._kbMenu()
        } else if (event.key === Qt.Key_Escape) {
            root.kbStop()
        } else {
            return
        }
        event.accepted = true
    }

    // An app leaving the strip under the keyboard's cursor.
    readonly property int kbSpan: root.count + root.kbTail.length
    onKbSpanChanged: if (root.kbIndex >= root.kbSpan) root.kbIndex = Math.max(-1, root.kbSpan - 1)

    // The far-end key the keyboard is on, or "".
    readonly property string kbTailKey:
        root.kbIndex >= root.count ? (root.kbTail[root.kbIndex - root.count] ?? "") : ""

    // ══ The jump list ═════════════════════════════════════════════════════════
    // Windows' order: the app's own tasks, then launch/pin, then close. `_menuKey`
    // outlives the menu's `opened` — ContextMenu closes itself BEFORE emitting
    // triggered(), so a key cleared on close would be gone by the time the choice
    // arrives.
    property string _menuKey:  ""
    property bool   _menuOpen: false

    function _openMenu(key, sceneX, sceneY) {
        if (!root.contextMenu || root.editMode) return
        root.closePreview()
        root._menuKey  = key
        root._menuOpen = true
        root.contextMenu.items = root._menuItems(key)
        root.contextMenu.openAt(sceneX, sceneY)
    }

    // ── The dock's own menu ───────────────────────────────────────────────────
    // Right-click anywhere on the dock that isn't a button: Windows' "Taskbar
    // settings" — the few things you'd change from the dock itself, and the page
    // with the rest. The host calls this for its surface's padding too.
    function openDockMenu(sceneX, sceneY) {
        if (!root.contextMenu || root.editMode) return
        root.closePreview()
        root._menuKey  = "__dock"
        root._menuOpen = true
        const pos = Config.dockPosition
        // On the bar (DockPill, `edge: "top"`) the sidebar's edge and auto-hide aren't the
        // dock's to set: it offers the way back to the sidebar instead. On the sidebar, the
        // way onto the bar. Either move is Config.placeModule (one place per module).
        const items = root.edge === "top" ? [
            { key: "toSidebar", glyph: "\u{F10A9}", label: "Move to the sidebar" },
            { separator: true },
            { key: "settings", glyph: "\u{F0493}", label: "Dock settings…" }
        ] : [
            { key: "", label: "Position", enabled: false },
            { key: "pos:left",   glyph: pos === "left"   ? "\u{F012C}" : "", label: "Left"   },
            { key: "pos:bottom", glyph: pos === "bottom" ? "\u{F012C}" : "", label: "Bottom" },
            { key: "pos:right",  glyph: pos === "right"  ? "\u{F012C}" : "", label: "Right"  },
            { separator: true },
            { key: "autohide", glyph: Config.sidebarAutoHide ? "\u{F012C}" : "", label: "Auto-hide" },
            { key: "toBar", glyph: "\u{F10A9}", label: "Move to the bar" },
            { separator: true },
            { key: "settings", glyph: "\u{F0493}", label: "Dock settings…" }
        ]
        root.contextMenu.items = items
        root.contextMenu.openAt(sceneX, sceneY)
    }

    // ── The far end's menus ───────────────────────────────────────────────────
    // Emptying the trash is the one destructive thing on the dock, so it arms
    // first: the menu arms the latch, the trash button turns red and says so, and
    // only a second click on it empties. It disarms on its own (ArmLatch).
    ArmLatch {
        id: trashLatch
        onConfirmed: Places.emptyTrash()
    }
    readonly property bool trashArmed: trashLatch.armed

    property var _menuDownloads: []
    readonly property int downloadsShown: 8

    function _openTail(key, sceneX, sceneY) {
        if (!root.contextMenu || root.editMode || key === "__overview") return
        root.closePreview()
        root._menuKey  = key
        root._menuOpen = true
        const items = []
        const file = root.fileFor(key)
        if (file) {
            items.push({ key: "open", glyph: file.dir ? "\u{F0770}" : "\u{F03CC}",
                         label: file.dir ? "Open folder" : "Open" })
            if (!file.dir)
                items.push({ key: "reveal", glyph: "\u{F024B}", label: "Show in folder" })
            items.push({ separator: true })
            items.push({ key: "unpin", glyph: "\u{F0404}", label: "Remove from dock" })
        } else if (key === "__trash") {
            items.push({ key: "open", glyph: "\u{F01B4}", label: "Open trash" })
            items.push({ separator: true })
            items.push({ key: "empty", glyph: "\u{F06CC}", tint: Colors.of(QsWindow.window).danger,
                         enabled: Places.trashFull,
                         label: Places.trashFull ? "Empty trash (" + Places.trashCount + ")…" : "Trash is empty" })
        } else {
            root._menuDownloads = Places.recentDownloads(root.downloadsShown)
            if (root._menuDownloads.length === 0)
                items.push({ key: "", label: "No downloads yet", enabled: false })
            for (let i = 0; i < root._menuDownloads.length; i++)
                items.push({ key: "dl:" + i, glyph: "\u{F0214}", label: root._menuDownloads[i].name })
            items.push({ separator: true })
            items.push({ key: "folder", glyph: "\u{F024D}", label: "Open Downloads" })
        }
        root.contextMenu.items = items
        root.contextMenu.openAt(sceneX, sceneY)
    }

    function _activateTail(key, sceneX, sceneY) {
        if (root.editMode) return
        const file = root.fileFor(key)
        if (file) Places.openFile(file.path)
        else if (key === "__trash") {
            if (root.trashArmed) trashLatch.trigger()      // the confirming click
            else                 Places.openTrash()
        } else if (key === "__downloads") root._openTail(key, sceneX, sceneY)
        else if (key === "__overview") {
            root.closePreview()
            UiState.launcherOpen = false
            UiState.overviewOpen = !UiState.overviewOpen
        }
    }

    // The recent files the open menu listed, so a choice resolves to the file it
    // showed even if the store changes while the menu is up.
    property var _menuRecent: []
    property var _menuPinned: []

    function _menuItems(key) {
        const g = root.groupFor(key)
        const items = []

        // Windows' jump list opens with the files the app had open recently.
        // Only for an app that can take a file back — otherwise a click could
        // only start it empty.
        // Pinned files first (Windows keeps them above Recent), then the recent ones
        // that aren't pinned. Every row has a pin/unpin at its end (ContextMenu's
        // `trail`), shown on hover.
        const takesFiles = Taskbar.acceptsFiles(key)
        root._menuPinned = takesFiles ? FilePins.jumpFor(key) : []
        const pinnedPaths = root._menuPinned.map(f => f.path)
        root._menuRecent = takesFiles
            ? Taskbar.recentFor(key).filter(f => pinnedPaths.indexOf(f.path) < 0) : []
        if (root._menuPinned.length > 0) {
            items.push({ key: "", label: "Pinned", enabled: false })
            for (let i = 0; i < root._menuPinned.length; i++)
                items.push({ key: "jump:" + i, glyph: "\u{F0214}", label: root._menuPinned[i].name,
                             trail: { key: "jumpUnpin:" + i, glyph: "\u{F0404}" } })
            items.push({ separator: true })
        }
        if (root._menuRecent.length > 0) {
            items.push({ key: "", label: "Recent", enabled: false })
            for (let i = 0; i < root._menuRecent.length; i++)
                items.push({ key: "recent:" + i, glyph: "\u{F0214}", label: root._menuRecent[i].name,
                             trail: { key: "jumpPin:" + i, glyph: "\u{F0403}" } })
            items.push({ separator: true })
        }

        const actions = Taskbar.actionsFor(key)
        for (let i = 0; i < actions.length; i++)
            items.push({ key: "action:" + i, label: actions[i].name })
        if (actions.length > 0) items.push({ separator: true })

        // No entry, no way to start it: one disabled row that says so, rather than
        // a "New window" and a "Pin" that both silently do nothing.
        if (Taskbar.canPin(key)) {
            items.push({ key: "launch", glyph: "󰐊", label: g ? "New window" : "Open" })
            items.push(Taskbar.isPinned(key)
                ? { key: "unpin", glyph: "󰐃", label: "Unpin from dock" }
                : { key: "pin",   glyph: "󰐃", label: "Pin to dock" })
        } else {
            items.push({ key: "launch", glyph: "󰐊", enabled: false,
                         label: Translation.tr("Can't launch — no desktop entry") })
            if (Taskbar.isPinned(key))
                items.push({ key: "unpin", glyph: "󰐃", label: "Unpin from dock" })
        }

        const sound = Taskbar.audio[key] ?? null
        if (sound) {
            items.push({ separator: true })
            items.push({ key: "mute", glyph: Audio.glyph(sound.muted ? 1 : 0, !sound.muted),
                         label: sound.muted ? "Unmute" : "Mute" })
        }

        if (g) {
            items.push({ separator: true })
            items.push({ key: "close", glyph: "󰅖", tint: Colors.of(QsWindow.window).danger,
                         label: g.count > 1 ? "Close all windows (" + g.count + ")"
                                            : "Close window" })
        }
        return items
    }

    Connections {
        target: root.contextMenu
        enabled: root.contextMenu !== null

        function onOpenedChanged() {
            if (root.contextMenu.opened) return
            root._menuOpen = false
            if (root.kbActive) root.forceActiveFocus()
        }

        function onTriggered(choice) {
            const key = root._menuKey
            root._menuKey = ""
            if (key === "") return

            if (key === "__dock") {
                if (choice.startsWith("pos:"))  Config.dockPosition = choice.slice(4)
                else if (choice === "autohide") Config.sidebarAutoHide = !Config.sidebarAutoHide
                else if (choice === "toSidebar") Config.placeModule("dock", "side")
                else if (choice === "toBar")     Config.placeModule("dock", "bar")
                else if (choice === "settings") UiState.openSettingsTo("DockPage.qml")
                return
            }
            const file = root.fileFor(key)
            if (file) {
                if (choice === "open")   Places.openFile(file.path)
                if (choice === "reveal") Places.openFile(file.path.substring(0, file.path.lastIndexOf("/")) || "/")
                if (choice === "unpin")  FilePins.unpin(file.path)
                return
            }
            if (key === "__trash") {
                if (choice === "open")  Places.openTrash()
                if (choice === "empty") trashLatch.trigger()
                return
            }
            if (key === "__downloads") {
                if (choice === "folder") Places.openDownloads()
                else if (choice.startsWith("dl:")) {
                    const f = root._menuDownloads[parseInt(choice.slice(3))]
                    if (f) Places.openFile(f.path)
                }
                return
            }

            if (choice.startsWith("jump:")) {
                const f = root._menuPinned[parseInt(choice.slice(5))]
                if (f && Taskbar.openWith(key, [f.path])) root.activated()
                return
            }
            if (choice.startsWith("jumpUnpin:")) {
                const f = root._menuPinned[parseInt(choice.slice(10))]
                if (f) FilePins.unpinJump(key, f.path)
                return
            }
            if (choice.startsWith("jumpPin:")) {
                const f = root._menuRecent[parseInt(choice.slice(8))]
                if (f) FilePins.pinJump(key, f.path)
                return
            }
            if (choice.startsWith("recent:")) {
                const f = root._menuRecent[parseInt(choice.slice(7))]
                if (f && Taskbar.openWith(key, [f.path])) root.activated()
                return
            }
            if (choice.startsWith("action:")) {
                Taskbar.runAction(key, parseInt(choice.slice(7)))
                root.activated()
                return
            }
            switch (choice) {
                case "launch": if (Taskbar.launch(key)) root.activated(); break
                case "pin":    Taskbar.pin(key);   break
                case "unpin":  Taskbar.unpin(key); break
                case "mute":   Taskbar.toggleMute(key); break
                case "close": {
                    const g = root.groupFor(key)
                    if (!g) break
                    if (g.count > 1) Taskbar.closeAll(key, root.groups)
                    else             Taskbar.close(g.windows[0])
                    break
                }
            }
        }
    }

    // ══ The strip ═════════════════════════════════════════════════════════════
    // Always clipped, so a button arriving at the end is uncovered by the strip
    // growing toward it rather than drawn past the dock's edge first. Hover and
    // the launch bounce stay inside a button's own box, which the clip never cuts.
    Item {
        id: viewport
        width:  root.implicitWidth
        height: root.implicitHeight
        // Clipped, except while magnified icons are allowed out of the dock.
        clip: !root.magnifyOut

        // Past `maxLength` the ends fade out, so a strip that scrolls says so.
        // Only while overflowing — the layer costs an offscreen pass.
        layer.enabled: root.overflow > 0
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fadeMask
            maskThresholdMin: 0.0
            maskSpreadAtMin: 1.0
        }

        // Where the pointer is along the dock — magnification's input. Passive, so
        // it never takes hover from the buttons' own MouseAreas.
        HoverHandler { id: stripHover }

        // Scrolling the STRIP is Shift+wheel, or a sideways wheel/touchpad swipe —
        // a plain wheel belongs to the button under the pointer (volume, windows).
        // Handlers on a button see the event first; the modifier filter is what
        // lets a Shift+wheel fall through to these.
        WheelHandler {
            enabled: root.overflow > 0
            acceptedModifiers: Qt.ShiftModifier
            onWheel: function(event) { root._scrollBy(event.angleDelta.y || event.angleDelta.x) }
        }
        WheelHandler {
            enabled: root.overflow > 0 && !root.vertical
            orientation: Qt.Horizontal
            acceptedModifiers: Qt.KeyboardModifierMask
            onWheel: function(event) { root._scrollBy(event.angleDelta.x) }
        }

        Item {
            id: track
            x: root.vertical ? 0 : -root.scroll
            y: root.vertical ? -root.scroll : 0
            width:  root.vertical ? root.button : root.fullLength
            height: root.vertical ? root.fullLength : root.button

            // Under every button: a right-click that lands between them.
            MouseArea {
                id: bgMouse
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: function(m) {
                    const s = bgMouse.mapToItem(null, m.x, m.y)
                    root.openDockMenu(s.x, s.y)
                }
            }

            DockStartCell { strip: root;
                visible: root.keepShown
                hoverKey: "__keep"
                symbol: "keep"
                open: UiState.dockRevealed
                at: 0
                onClicked: { root.closePreview(); UiState.toggleDockRevealed() }
            }
            DockStartCell { strip: root;
                visible: Config.dockShowLauncher
                hoverKey: "__launcher"
                hero: root.barFeedback
                glyph: "󰀻"                                     // 󰀻 apps
                open: UiState.launcherOpen
                      && (UiState.activeScreen === root.screen || root.screen === null)
                kbRing: root.kbIndex === -1
                at: root.launcherAt
                onClicked: root._toggleLauncher()
            }

            // The sidebar's: the same place, the sidebar's own divider (SideRegionPills).
            Divider {
                visible: root.barFeedback && !root.ii && root.leadSlots > 0
                readonly property real at: (root.leadSlots * root.slot - root.gap + root.lead) / 2
                readonly property real span: root.button - Tokens.spacingMd * 2
                orientation: root.vertical ? Qt.Horizontal : Qt.Vertical
                width:  root.vertical ? span : Tokens.borderWidth
                height: root.vertical ? Tokens.borderWidth : span
                x: root.vertical ? (root.button - width) / 2 : at - width / 2
                y: root.vertical ? at - height / 2 : (root.button - height) / 2
            }
            // Pinned | running ("Pinned | running" above): in the pin gap, fading with it.
            Divider {
                readonly property real at: root.lead + root.pinCount * root.slot + (root.pinGap - root.gap) / 2
                readonly property real span: root.button - Tokens.spacingMd * 2
                orientation: root.vertical ? Qt.Horizontal : Qt.Vertical
                width:  root.vertical ? span : Tokens.borderWidth
                height: root.vertical ? Tokens.borderWidth : span
                x: root.vertical ? (root.button - width) / 2 : at - width / 2
                y: root.vertical ? at - height / 2 : (root.button - height) / 2
                opacity: root.pinGap > 0 ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // ii: a hairline between the start group and the apps, centred in its gap.
            Rectangle {
                visible: root.ii && root.leadSlots > 0
                readonly property real at: (root.leadSlots * root.slot - root.gap + root.lead) / 2
                width:  root.vertical ? root.iconPx : Tokens.borderWidth
                height: root.vertical ? Tokens.borderWidth : root.iconPx
                x: root.vertical ? (root.button - width) / 2 : at - width / 2
                y: root.vertical ? at - height / 2 : (root.button - height) / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.15)
            }

            // Behind every button, so their hover washes and icons sit ON it.
            Repeater {
                model: ScriptModel { values: root.apps }
                delegate: DockRunPill { strip: root }
            }

            // Under the buttons, so the neighbours close over a leaving icon.
            Repeater {
                model: ghosts
                delegate: DockGhost { strip: root }
            }

            Repeater {
                id: buttons
                model: ScriptModel { values: root.apps }
                delegate: DockAppButton { strip: root }
            }

            // Over the buttons, exactly on the focused one's pip.
            Rectangle {
                id: glider

                readonly property real thick: root.indicatorThick
                readonly property real len:   root.focusMarkLen
                // The focused button's centre along the strip — its resting slot, so
                // nothing here eases toward a value that is itself easing. Held
                // where it was while nothing is focused, so it fades in place.
                property real at: 0
                Binding on at {
                    when: root.focusIndex >= 0
                    value: root.slotPos(root.focusIndex) + root.button / 2
                    restoreMode: Binding.RestoreNone
                }
                // Two edges, one target, two speeds (WorkspacesPill's indicator).
                // Invisible, it jumps: arriving from nowhere must not slide in from
                // wherever it was last.
                property real leadPos:  glider.at
                property real trailPos: glider.at
                Behavior on leadPos {
                    enabled: glider.opacity > 0.05
                    NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
                }
                Behavior on trailPos {
                    enabled: glider.opacity > 0.05
                    NumberAnimation { duration: Motion.trail;    easing.type: Motion.travel }
                }
                readonly property real lo:   Math.min(glider.leadPos, glider.trailPos) - glider.len / 2
                readonly property real span: Math.abs(glider.leadPos - glider.trailPos) + glider.len

                width:  root.vertical ? glider.thick : glider.span
                height: root.vertical ? glider.span  : glider.thick
                x: root.vertical ? root.indicatorAt(glider.thick) : glider.lo
                y: root.vertical ? glider.lo : root.indicatorAt(glider.thick)
                radius: glider.thick / 2
                color: Colors.of(QsWindow.window).focus

                opacity: root.gliding ? 1 : 0
                visible: glider.opacity > 0
                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
            }

            // The divider before the far end, centred in its gap.
            Rectangle {
                visible: root.tailCount > 0 && root.appsEnd > 0
                readonly property real at: (root.appsEnd - root.gap + root.tailStart) / 2
                width:  root.vertical ? root.iconPx : Tokens.borderWidth
                height: root.vertical ? Tokens.borderWidth : root.iconPx
                x: root.vertical ? (root.button - width) / 2 : at - width / 2
                y: root.vertical ? at - height / 2 : (root.button - height) / 2
                color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.15)
            }

            // Diffed, so the drop slot opening mid-drag slides its neighbours along
            // instead of rebuilding them.
            Repeater {
                id: tailButtons
                model: ScriptModel { values: root.tailKeys }
                delegate: DockTailButton { strip: root }
            }
        }
    }

    // ══ Files dropped on an icon ═════════════════════════════════════════════
    // Drag a file from a file manager onto an app and let go: it opens in that app
    // (Taskbar.openWith). One DropArea over the whole strip rather than one per
    // button, so it keeps receiving positions as the drag crosses apps that CAN'T
    // take a file — those simply aren't highlighted, and a drop on one is refused.
    property int fileDropIndex: -1
    readonly property bool fileDropActive: fileDrop.containsDrag

    // Held over a RUNNING app for a moment, the drag brings that app's window
    // forward so the file can be dropped straight into it — Windows' gesture. Only
    // possible without a pointer warp (hypr: cursor.no_warps), which would yank the
    // drag out from under the hand. An interaction timing, like previewDwell.
    readonly property int dragFocusDwell: 700
    onFileDropIndexChanged: {
        if (root.fileDropIndex >= 0 && root.groupFor(root.apps[root.fileDropIndex])) dragFocus.restart()
        else dragFocus.stop()
    }
    Timer {
        id: dragFocus
        interval: root.dragFocusDwell
        onTriggered: {
            const g = root.groupFor(root.apps[root.fileDropIndex] ?? "")
            if (g) Taskbar.focus(g.recent, root.monitor)
        }
    }

    // An app's index; `trashSlot` over the trash (files dropped there go to the
    // trash — the macOS gesture); `pinSlotIndex` anywhere else past the apps (they
    // get pinned to the dock); or -1.
    readonly property int trashSlot:    -100
    readonly property int pinSlotIndex: -200
    function _slotAt(x, y) {
        const along = (root.vertical ? y : x) + root.scroll
        const t = root.tailPos("__trash")
        if (t >= 0 && along >= t && along < t + root.button) return root.trashSlot
        // The ii overview button is a button, not a place to drop a file.
        const ov = root.tailPos("__overview")
        if (ov >= 0 && along >= ov) return -1
        if (along >= root.appsEnd - root.gap) return root.pinSlotIndex
        const main = root.unGap(along - root.lead)
        if (main < 0) return -1
        const i = Math.floor(main / root.slot)
        return i < root.count ? i : -1
    }

    DropArea {
        id: fileDrop
        anchors.fill: viewport
        enabled: !root.editMode
        keys: ["text/uri-list"]
        onEntered: function(drag) {
            root.closePreview()
            root.fileDropIndex = root._slotAt(drag.x, drag.y)
        }
        onPositionChanged: function(drag) { root.fileDropIndex = root._slotAt(drag.x, drag.y) }
        onExited: root.fileDropIndex = -1
        onDropped: function(drop) {
            const i = root.fileDropIndex
            root.fileDropIndex = -1
            if (i === root.trashSlot || i === root.pinSlotIndex) {
                const paths = []
                for (let j = 0; j < drop.urls.length; j++) {
                    const p = DockJs.fileUrlToPath(drop.urls[j].toString())
                    if (p !== "") paths.push(p)
                }
                if (paths.length === 0) return
                if (i === root.trashSlot) {
                    if (Places.trashFiles(paths)) drop.acceptProposedAction()
                } else {
                    for (let j = 0; j < paths.length; j++) FilePins.pin(paths[j])
                    drop.acceptProposedAction()
                }
                return
            }
            const key = root.apps[i]
            if (!key || !Taskbar.acceptsFiles(key)) return
            const paths = []
            for (let j = 0; j < drop.urls.length; j++) {
                const p = DockJs.fileUrlToPath(drop.urls[j].toString())
                if (p !== "") paths.push(p)
            }
            if (paths.length === 0 || !Taskbar.openWith(key, paths)) return
            drop.acceptProposedAction()
            buttons.itemAt(i)?.bounce()
            root.activated()
        }
    }

    Item {
        id: fadeMask
        width:  viewport.width
        height: viewport.height
        visible: false
        layer.enabled: true

        // Fade only an end there's more content past.
        readonly property real frac: root.maxLength > 0 && isFinite(root.maxLength)
                                     ? Math.min(0.25, root.button / root.maxLength) : 0
        readonly property real head: root.scroll > 0             ? fadeMask.frac : 0
        readonly property real tail: root.scroll < root.overflow ? fadeMask.frac : 0

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: root.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: fadeMask.head > 0 ? "transparent" : "white" }
                GradientStop { position: fadeMask.head;       color: "white" }
                GradientStop { position: 1.0 - fadeMask.tail; color: "white" }
                GradientStop { position: 1.0; color: fadeMask.tail > 0 ? "transparent" : "white" }
            }
        }
    }

    // ══ Buttons ═══════════════════════════════════════════════════════════════

}
