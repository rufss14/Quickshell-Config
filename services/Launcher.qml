pragma Singleton
import Quickshell
import QtQuick
import "../config"
import "../state"
import "launcher.js" as Logic

// ── Launcher ──────────────────────────────────────────────────────────────────
// What the app launcher knows, so its panel only has to show it: the searchable
// index of installed apps, the launch history that orders them, and the one place an
// app is actually started.
//
// It also finds what the SHELL can do (services/ShellActions, kind "action", in the same
// index and ranking — a hair under an app that matches as well) and settings pages and
// rows (SettingsIndex's own search, after them, three at most).
//
// The ranking itself is services/launcher.js (`bun scripts/test-launcher.js`). This is
// the thin QML half — it owns the things a pure function can't: the DesktopEntries
// model, the history file, and the clock.
//
// ── History ───────────────────────────────────────────────────────────────────
// How often and how recently you launched each app, in `launcher-history.json` under
// XDG_STATE_HOME (your own data, like pins.json — not config.json, which is rewritten
// on every slider drag). Only ids and counts: it never records what you typed. It
// orders matches of the same quality, nothing more; see launcher.js for why it is
// capped.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    JsonStore {
        id: store
        path: Quickshell.statePath("launcher-history.json")
        defaults: ({})
    }

    // The file is hand-editable; only well-formed records come through.
    readonly property var history: Logic.cleanHistory(store.value)

    // What the empty launcher field types after "Search apps" — each prefix and what
    // it does. Here rather than in the panel so Settings › Bar › Launcher can show the
    // same field typing the same hints. (`Ai` is a sibling singleton in services/.)
    readonly property var idleHints: [
        { key: ">",           text: "run a command" },
        { key: "?",           text: Ai.blocker() === "" ? "ask " + Ai.label : "search the web" },
        { key: "12*8",        text: "calculate",         on: Config.launcherCalc },
        { key: "10 km to mi", text: "convert",           on: Config.launcherCalc },
        { key: "+",           text: "install a package", on: Config.launcherPackages },
        { key: ";",           text: "clipboard history", on: Config.launcherClipboard },
        { key: ":",           text: "find an emoji",     on: Config.launcherEmoji && Emoji.blocker() === "" },
        { key: "yt cats",     text: "search a site",     on: root.webShortcuts.length > 0 }
    ].filter(h => h.on !== false)

    // The user's site shortcuts, cleaned (http(s) only, typable keys) — the one place the
    // raw setting is read.
    readonly property var webShortcuts: Logic.cleanShortcuts(Config.launcherWebShortcuts)

    // Plain copies of the fields the search reads, rebuilt when the application list
    // (or one entry's own fields) changes — a keystroke then only scores strings.
    readonly property var index: Logic.buildIndex(
        DesktopEntries.applications.values.map(e => ({
            id: e.id, name: e.name, genericName: e.genericName, comment: e.comment,
            keywords: Array.from(e.keywords || []), execString: e.execString,
            noDisplay: e.noDisplay
        })))

    // The shell's actions, as index records (built once; the table is static).
    readonly property var _actionIndex: Logic.buildIndex(ShellActions.table.map(a => ({
        id: "action:" + a.id, name: a.name, keywords: a.keywords, comment: a.detail,
        kind: "action", penalty: 5
    })))
    readonly property var _fullIndex: root.index.concat(root._actionIndex)
    readonly property int maxActions: 4
    readonly property int maxSettings: 3

    // Matches for `query`, best first. Empty for an empty query — at rest the launcher
    // is only its field. Reads index, history and the pins, so a binding on it re-runs
    // when any of them moves. Every result has `kind`:
    //   app      { id, name, ranges, generic, entry }
    //   action   { id, name, ranges, generic (what it does), symbol, action }
    //   setting  { id, name, ranges, generic ("Settings › page"), symbol, file }
    //   web      { id, name, ranges, generic (the host), symbol, url }   `yt cats`, first when typed
    // (`;` and `:` have their own searches below / in services/Emoji: kinds clip and emoji.)
    function search(query, limit) {
        // Actions, settings and "learning" are each a switch (Settings › Launcher): off, the
        // index is apps alone, and history is not consulted.
        const out = []
        // `yt cats`: the site search comes first — you typed its key on purpose.
        const web = Logic.webShortcut(query, root.webShortcuts)
        if (web) {
            const host = /^https?:\/\/([^\/?#]+)/.exec(web.url)
            out.push({ kind: "web", id: "web:" + web.key + ":" + web.query,
                       name: "Search " + web.name + " for “" + web.query + "”", ranges: [],
                       generic: host ? host[1] : web.url, symbol: "language", url: web.url })
        }
        const hits = Logic.capKinds(Logic.search(Config.launcherActions ? root._fullIndex : root.index, query, {
            pinned: Pins.ids, history: Config.launcherLearn ? root.history : ({}),
            now: Date.now(), limit: limit || 50
        }), { action: root.maxActions })
        for (const h of hits) {
            if (h.kind === "action") {
                const id = h.id.slice("action:".length)
                const a = ShellActions.table.find(x => x.id === id)
                if (!a) continue
                out.push({ kind: "action", id: h.id, name: h.name, ranges: h.ranges,
                           generic: a.detail, symbol: a.symbol, action: id })
                continue
            }
            const entry = DesktopEntries.byId(h.id)
            if (!entry) continue
            out.push({ kind: "app", id: h.id, name: h.name, ranges: h.ranges,
                       generic: entry.genericName || "", entry: entry })
        }
        // Settings: their own search (settingssearch.js), after apps and actions — three
        // letters at least, or "a" lists half the settings app.
        const q = String(query || "").trim()
        if (Config.launcherSettings && q.length >= 3) {
            const found = SettingsIndex.search(q, root.maxSettings)
            for (let i = 0; i < found.length; i++) {
                const r = found[i]
                const title = String(r.title || "")
                out.push({
                    // Unique even for two rows with one title (the list is keyed on id).
                    kind: "setting", id: "setting:" + r.file + "#" + r.kind + "#" + title + "#" + i,
                    name: title, ranges: Logic.scoreText(title.toLowerCase(), q.toLowerCase()).ranges,
                    generic: r.kind === "page" ? "Settings" + (r.group ? " › " + r.group : "")
                                               : "Settings › " + (r.page || r.group || ""),
                    symbol: "settings", file: r.file
                })
            }
        }
        return out
    }

    // The one place an app is started from the launcher, so a launch always counts
    // toward the history regardless of which row, key or menu asked for it.
    function launch(entry) {
        if (!entry) return
        if (Config.launcherLearn) store.value = Logic.recordLaunch(root.history, entry.id, Date.now())
        entry.execute()
    }

    // Any result: an app launches, an action runs (and counts toward the history, so a
    // habit rises), a setting opens its page. false when nothing happened — an action
    // whose blocker() said no — so the launcher stays open to say why.
    function open(result) {
        if (!result) return false
        if (result.kind === "action") {
            if (!ShellActions.run(result.action)) return false
            if (Config.launcherLearn) store.value = Logic.recordLaunch(root.history, result.id, Date.now())
            return true
        }
        if (result.kind === "setting") {
            UiState.openSettingsTo(result.file)
            return true
        }
        if (result.kind === "web") {
            Quickshell.execDetached(["xdg-open", result.url])
            return true
        }
        if (result.kind === "clip") {
            Clipboard.copy(result.entry)
            return true
        }
        if (result.kind === "emoji") {
            Emoji.pick(result)
            return true
        }
        root.launch(result.entry)
        return !!result.entry
    }

    // `;`: the clipboard history as rows, newest first when the query is empty. Image entries
    // answer to "image". The text of an entry is private; nothing here leaves the machine.
    function searchClip(query, limit) {
        const entries = Clipboard.entries
        const items = entries.map(e => ({ label: Clipboard.label(e),
                                          text: e.kind === "image" ? "image" : (e.preview || "") }))
        return Logic.searchClip(items, query, limit).map(h => {
            const e = entries[h.i]
            return { kind: "clip", id: "clip:" + e.hash, name: items[h.i].label, ranges: h.ranges,
                     generic: Clipboard.detail(e), entry: e,
                     symbol: e.kind === "image" ? "image" : Clipboard.isLink(e) ? "link" : "content_paste" }
        })
    }

    // What Tab / right-click offers on an app row: open it, its own desktop actions ("New
    // private window"), pin it to the dock, forget what it learned. { id, name, symbol, closes,
    // run() } — `closes` false for the ones that change a row and leave the launcher up.
    function quickActions(result) {
        if (!result || result.kind !== "app" || !result.entry) return []
        const e = result.entry
        const out = [{ id: "open", name: "Open", symbol: "open_in_new", closes: true,
                       run: () => root.launch(e) }]
        for (const a of Array.from(e.actions || [])) {
            out.push({ id: "act:" + a.id, name: a.name, symbol: "chevron_right", closes: true,
                       run: () => a.execute() })
        }
        const pinned = !!Pins.isPinned(e.id)
        out.push({ id: "pin", name: pinned ? "Unpin from dock" : "Pin to dock", symbol: "keep",
                   fill: pinned ? 1 : 0, closes: false, run: () => Pins.toggle(e.id) })
        if (root.history[e.id])
            out.push({ id: "forget", name: "Forget launches", symbol: "history",
                       closes: false, run: () => root.forget(e.id) })
        return out
    }

    function forget(id) { store.value = Logic.forget(root.history, id) }

    // Is the mode a prefix character starts switched on? (`>` and `?` always are: `?` falls
    // back to a web search by itself.) Asked by the field before it takes the character.
    function modeEnabled(mode) {
        return mode === "pkg"   ? Config.launcherPackages
             : mode === "clip"  ? Config.launcherClipboard
             : mode === "emoji" ? Config.launcherEmoji
             :                    true
    }

    // Forget what you've launched, so matches fall back to plain quality order.
    function clearHistory() { store.value = ({}) }
}
