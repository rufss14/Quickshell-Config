import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "../panels"
import "../../services/island.js" as Rules
import "../../config/islands.js" as Islands

// ── IslandCard ────────────────────────────────────────────────────────────────
// What the island holds: the pages on its rail (UiState.islandPagesOf: Settings › Desktop › Island's board decides
// which and in what order) beside a navigation rail (IslandRail: one filled indicator that stretches between the pages on two springs
// and becomes each page's shape), with the pin under it. The pages follow Caelestia's dashboard for what they hold
// (design only) and the clock panel for how they look: flat tonal cards, a loud accent-container hero, M3E shapes,
// springs. The page you were on is remembered (`Config.islandTab`); an opening can land elsewhere for once
// (UiState.islandPageOf: the live handle's song opens Media). A wheel over the card steps through the pages, where
// nothing under the pointer wants the wheel itself (the lyrics, a slider).
//
// The dock sizes its lobe to this item's implicit size, on a spring. Each page has its own size (Rules.BODY):
// switching grows the card at once and shrinks it only once the new page is in. The page itself leaves on the side
// you came from and the next arrives from the other on a spring, so the content crosses while the box resizes —
// vertically, the way the rail runs. `reveal` (0..1) is the dock's animation number; the rail and the page ride it one
// after another.
//
// All three of the bar's islands hold this card (`side`). Any page can be on any rail (config/islands.js layoutOf):
// the island's own (Dashboard, Media, Performance, Weather), the bar's panels and the sidebar's. A panel
// built for an island says its size (`body` in islands.js); one that is still the bar's panel is shown at the
// island's width and its own height, never shorter than the Dashboard and never taller than `maxBodyH`.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root


    property real reveal: 1

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int gutter: Tokens.spacingXl

    function lead(i) { return Math.max(0, Math.min(1, root.reveal * 1.6 - i * 0.2)) }

    // The island's id (config/islands.js SIDES): "left" | "center" | "right" | "bottomLeft" | "bottomCenter" | "bottomRight".
    property string side: "center"
    // The tallest a panel's page may ask to be (the dock knows the screen).
    property real maxBodyH: 640

    readonly property var pages: UiState.islandPagesOf(root.side)
    // The page on show; it changes once the old one has left. Set once, never bound: a binding to `wanted` would follow
    // it before the hand-over could see the change.
    property string shown: ""
    readonly property string wanted: UiState.islandWanted(root.side)
    function indexOf(tab) { return root.pages.indexOf(tab) }
    function pick(tab) { UiState.islandPick(root.side, tab) }
    function pageMeta(id) { return Islands.pageMeta(id) }
    // Leaving a page puts its island form back for next time.
    onShownChanged: if (root.shown !== root.classicOf) root.classicOf = ""

    // ── The size ──────────────────────────────────────────────────────────────
    // The larger of the page on show and the one coming, each way: the card grows at once and shrinks
    // only after the new page is in.
    // An island page covers the everyday; where the bar's full panel has more (Bluetooth's renaming
    // and files, Game Mode's tuning and setup), the page asks for it (`classicRequested`) and the card
    // shows that panel in its place until the page is left: `classicOf` is whose.
    property string classicOf: ""
    // Bluetooth's also shows by itself while BlueZ waits on an answer or a file is staged: a question
    // nobody can see is a pairing that times out.
    readonly property bool btWaiting: BtBridge.prompt !== null || BtBridge.staged !== ""
    function classic(id) { return root.classicOf === id || (id === "bluetooth" && root.btWaiting) }
    // A page built for an island says its size; null = a bar panel, sized by its own content.
    function fixedSize(id) {
        if (root.classic(id)) return null
        return Rules.BODY[id] || Islands.pageMeta(id).body || null
    }
    readonly property real panelH: {
        const it = body.item
        if (!it || root.fixedSize(root.shown)) return 0
        return it.pinnedHeight > 0 ? it.pinnedHeight : it.implicitHeight
    }
    function sizeOf(id) {
        const fixed = root.fixedSize(id)
        if (fixed) return fixed
        const h = id === root.shown ? Math.min(root.panelH, root.maxBodyH) : 0
        return { w: Rules.BODY.today.w, h: Math.max(Rules.BODY.today.h, h) }
    }
    readonly property var size: {
        const a = root.sizeOf(root.shown), b = root.sizeOf(root.wanted)
        return { w: Math.max(a.w, b.w), h: Math.max(a.h, b.h) }
    }
    Component.onCompleted: root.shown = root.wanted

    // ── The hand-over ─────────────────────────────────────────────────────────
    property int  dir: 1
    property real bodyAlpha: 1
    readonly property real travel: Tokens.spacingXxl * 1.5
    SpringValue { id: slide; spec: Motion.springSpatial; epsilon: 0.2 }
    onWantedChanged: {
        if (root.wanted === root.shown) return
        root.dir = root.indexOf(root.wanted) > root.indexOf(root.shown) ? 1 : -1
        swap.restart()
    }
    SequentialAnimation {
        id: swap
        ScriptAction { script: slide.target = -root.dir * root.travel }
        NumberAnimation { target: root; property: "bodyAlpha"; to: 0; duration: Motion.exit; easing.type: Motion.exitCurve }
        ScriptAction { script: { root.shown = root.wanted; slide.jump(root.dir * root.travel); slide.target = 0 } }
        NumberAnimation { target: root; property: "bodyAlpha"; to: 1; duration: Motion.standard; easing.type: Motion.respondCurve }
    }

    // One notch a page; a touchpad's small deltas are summed to a notch first. Only with Ctrl held: a plain
    // wheel belongs to whatever is under it (a list, a gallery), never to the island.
    WheelHandler {
        id: wheel
        property real acc: 0
        enabled: root.pages.length > 1
        acceptedModifiers: Qt.ControlModifier
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function (e) {
            wheel.acc += e.angleDelta.y
            if (Math.abs(wheel.acc) < 120) return
            const next = Islands.step(root.pages, root.wanted, wheel.acc > 0 ? -1 : 1)
            wheel.acc = 0
            if (next !== root.wanted) root.pick(next)
        }
    }

    implicitWidth: rail.implicitWidth + Tokens.spacingMd + root.size.w + root.gutter * 2
    implicitHeight: root.size.h + root.gutter * 2

    Component { id: tToday;   IslandToday {} }
    Component { id: tMedia;   IslandMedia {} }
    Component { id: tSystem;  IslandSystem {} }
    Component { id: tWeather; IslandWeather {} }
    Component { id: tDesk;    IslandDesk {} }
    Component { id: tTimer;   IslandTimer {} }
    Component { id: tCaptures; IslandCaptures {} }
    Component { id: tNetwork;  IslandNetwork {} }
    Component { id: tPower;    IslandPower {} }
    Component { id: tFiles;    IslandFiles {} }
    Component { id: tWorkout;  IslandWorkout {} }
    Component { id: tTablet;   IslandTablet {} }
    Component { id: tAgenda;   IslandAgenda {} }
    Component { id: tDisplays; IslandDisplays {} }
    Component { id: tAssistant; IslandAssistant {} }
    // The panels on a rail: the same files the bar's plain dock and the sidebar open.
    // The bar's own panels, re-laid for the island (`island`): no title row or outer padding, the
    // main card fixed in a column on the left and the rest beside it.
    Component { id: pWallpaper;     WallpaperPanel { island: true } }
    Component { id: pColorScheme;   ColorSchemePanel { island: true } }
    Component { id: pEqualizer;     EqualizerPanel { island: true } }
    Component { id: pClock;         ClockPanel { island: true } }
    Component { id: pBluetooth;     BluetoothPanel {} }
    Component { id: iBluetooth;     IslandBluetooth { onClassicRequested: root.classicOf = "bluetooth" } }
    Component { id: iWifi;          IslandWifi {} }
    Component { id: iBrightness;    IslandBrightness {} }
    Component { id: iWindow;        IslandWindow {} }
    Component { id: iLayout;        IslandLayout {} }
    Component { id: iNotifications; IslandNotifications {} }
    Component { id: pGaming;        GamingPanel { island: true } }
    Component { id: sStats;         StatsPanel {} }
    Component { id: sClipboard;     ClipboardPanel {} }
    Component { id: sClaude;        ClaudePanel { island: true } }
    Component { id: sScreenTime;    ScreenTimePanel { island: true } }
    Component { id: sInactivity;    InactivityPanel {} }
    Component { id: sTasks;         TasksPanel {} }
    Component { id: sClips;         ClipsPanel { island: true } }
    Component { id: sVoice;         VoicePanel { island: true } }
    Component { id: sUpdate;        UpdatePanel { island: true } }
    function componentFor(id) {
        switch (id) {
        case "media":         return tMedia
        case "system":        return tSystem
        case "weather":       return tWeather
        case "wallpaper":     return pWallpaper
        case "colorScheme":   return pColorScheme
        case "equalizer":     return pEqualizer
        case "window":        return iWindow
        case "layout":        return iLayout
        case "clock":         return pClock
        case "notifications": return iNotifications
        case "wifi":          return iWifi
        case "bluetooth":     return root.classic("bluetooth") ? pBluetooth : iBluetooth
        case "brightness":    return iBrightness
        case "gaming":        return pGaming
        case "today":         return tToday
        case "desk":          return tDesk
        case "captures":      return tCaptures
        case "network":       return tNetwork
        case "power":         return tPower
        case "files":         return tFiles
        case "workout":       return tWorkout
        case "tablet":        return tTablet
        case "agenda":        return tAgenda
        case "displays":      return tDisplays
        case "assistant":     return tAssistant
        // The sidebar's panels, on a rail since 2026-11-14: the panel as the bar's plain dock shows it, at the
        // island's width and its own height until one is rebuilt for an island.
        case "stats":         return sStats
        case "clipboard":     return sClipboard
        // The timer as a dashboard (2026-11-15); the sidebar keeps TimerPanel's tabs.
        case "timer":         return tTimer
        case "claude":        return sClaude
        case "screentime":    return sScreenTime
        case "inactivity":    return sInactivity
        case "tasks":         return sTasks
        case "clips":         return sClips
        case "voice":         return sVoice
        case "update":        return sUpdate
        // An id this build has no page for draws nothing, never another page in its place.
        default:              return null
        }
    }
    // The page on show, for the dock's keys (a panel may answer handleEscape() / handleKey(event)).
    readonly property Item page: body.item

    IslandRail {
        id: rail
        x: root.gutter - (1 - root.lead(0)) * Tokens.spacingXl
        y: root.gutter
        height: root.size.h
        opacity: root.lead(0)
        pages: root.pages
        current: root.wanted
        metaOf: root.pageMeta
        pinned: UiState.islandIsPinned(root.side)
        onPicked: v => root.pick(v)
        onPinToggled: UiState.setIslandPinned(root.side, !UiState.islandIsPinned(root.side))
    }

    // The wrapper carries the arrival (reveal); the Loader inside is the page that crosses between pages.
    Item {
        x: rail.x + rail.width + Tokens.spacingMd
        // It arrives the way the card grows: down with a top island's, up with a bottom one's. (It used to rise
        // on both, against a top island's box.)
        y: root.gutter + (Islands.rowOf(root.side) === "bottom" ? 1 : -1) * (1 - root.lead(1)) * Tokens.spacingLg
        width: root.size.w
        height: root.size.h
        opacity: root.lead(1)

        Loader {
            id: body
            anchors.fill: parent
            active: root.shown !== ""
            sourceComponent: root.componentFor(root.shown)
            opacity: root.bodyAlpha
            transform: Translate { y: slide.value }
        }
    }
}
