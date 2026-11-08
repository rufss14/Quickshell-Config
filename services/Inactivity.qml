pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "../config"
import "inactivity.js" as Ia

// ── Inactivity ────────────────────────────────────────────────────────────────
// "After N minutes without input, do X" — a list of rules, each with its own timeout
// and action: lock, screen off, suspend, hibernate, log out, power off, or a command
// of your own. The Inactivity panel (bar / sidebar) edits the list; this runs it.
//
// The decisions — what a rule may contain, how a command line becomes an argv — are in
// inactivity.js (`bun scripts/test-inactivity.js`). This file is the part that needs a
// compositor: one IdleMonitor per rule, and the carrying-out.
//
// ── Inhibitors win ────────────────────────────────────────────────────────────
// Every monitor has `respectInhibitors: true`, so Stay awake (the Idle service's
// IdleInhibitor in Bar.qml) and Gamemode's hold suppress EVERY rule, not just screen
// blanking — same reasoning as Lock.qml's auto-lock: an inhibitor that still lets the
// machine suspend under a film would make the inhibitor a lie. Video players that
// inhibit through the portal are respected the same way.
//
// ── Where the rules live, and why not in Config ───────────────────────────────
// `statePath("inactivity.json")`, like Timers. Not config.json, because config.json's
// contents are also what a Shell PRESET carries (Config._dumpPrefs): a rule can power
// the machine off or run a command, and a preset someone shares must not be able to
// arm either on your machine. Not the repo either (`.gitignore`: state is per-machine).
//
// ── The old Lock › auto-lock setting ──────────────────────────────────────────
// `Config.lockIdleEnabled` / `lockIdleMinutes` become a "Lock" rule, once
// (`migrated` in the document). Stage 3 retires Lock.qml's own IdleMonitor; until then
// BOTH exist, which locks twice at worst, never zero times.
//
// ── Log out and power off warn first ──────────────────────────────────────────
// They are the actions that can lose unsaved work. Their monitor trips WARN_SECONDS
// early, a critical notification says what is about to happen, and the action runs
// when that window ends — unless input (or switching the rule off) cancels it first.
//
// ── Screen off needs a way back ───────────────────────────────────────────────
// Hyprland does not wake a blanked monitor on input unless `misc.mouse_move_enables_dpms`
// / `key_press_enables_dpms` are set (neither is, in hypr/). So the screen-off rule wakes
// the screen ITSELF when its monitor reports activity again (`isIdle` → false), and when
// the rule is switched off or edited while the screen is off. If the shell dies while
// the screen is off, only those two Hyprland options bring it back — see the panel's
// notes.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── The document ──────────────────────────────────────────────────────────
    // Master switch: off, no monitor is enabled and nothing ever fires — the rules stay
    // as they are for when it comes back.
    property bool enabled: false
    property var _rules: []
    readonly property var rules: root._rules
    readonly property bool ready: store.ready

    // What last fired, for the panel's "Last: Lock, 14:02". `rule` is a copy (a rule
    // since deleted still has a name); `at` is epoch ms.
    property var last: null

    function _save() {
        if (!store.ready) return
        store.value = { version: 1, migrated: true, enabled: root.enabled, rules: root._rules }
    }

    function setEnabled(on) {
        if (root.enabled === on) return
        root.enabled = on
        root._save()
    }

    function addRule() {
        if (root._rules.length >= Ia.MAX_RULES) return
        root._rules = Ia.normalizeRules(root._rules.concat([Ia.newRule(root._rules)]))
        root._save()
    }

    // `patch` is a plain object of the fields to change; the result is re-normalised,
    // so a clamp or a re-sort happens here and the panel just reads `rules` back.
    function patchRule(id, patch) {
        root._rules = Ia.normalizeRules(root._rules.map(r => r.id === id ? Object.assign({}, r, patch) : r))
        root._save()
    }

    function removeRule(id) {
        root._rules = root._rules.filter(r => r.id !== id)
        root._save()
    }

    // ── What the panel reads ──────────────────────────────────────────────────
    // The vocabulary lives in inactivity.js; these hand it over so the panel needs no
    // import of its own.
    readonly property var actionChips: Ia.ACTION_ORDER.map(a => ({ value: a, label: Ia.ACTIONS[a].label }))
    readonly property int warnSeconds: Ia.WARN_SECONDS
    readonly property int minMinutes: Ia.MIN_MINUTES
    readonly property int maxMinutes: Ia.MAX_MINUTES
    readonly property int maxRules: Ia.MAX_RULES
    function duration(minutes) { return Ia.duration(minutes) }
    function warns(action) { return Ia.warns(action) }
    function describe(rule) { return Ia.describe(rule) }

    // The header's second line.
    readonly property string summary: {
        if (!store.ready) return ""
        const live = root._rules.filter(r => r.enabled)
        if (root._rules.length === 0) return "No rules yet"
        if (!root.enabled) return "Off — " + root._rules.length + (root._rules.length === 1 ? " rule" : " rules") + " kept"
        if (live.length === 0) return "On, but every rule is off"
        return live.length + (live.length === 1 ? " rule" : " rules") + " · first: " + Ia.describe(live[0])
    }

    // ── Can this rule run on this machine right now? ──────────────────────────
    // "" = yes, otherwise the reason (the pattern of Discord.pressBlocker /
    // NightLight.blocker: a control says why it can't, it doesn't fail when it fires).
    // The panel reads it to disable an option; fire() reads it to skip.
    function blocker(action, command) {
        if (action === "hibernate" && !Session.canHibernate)
            return "Hibernate isn't set up on this machine (it needs swap and a resume device)"
        if (action === "command" && Ia.parseCommand(command) === null)
            return "Type a command first"
        return ""
    }

    // ── Carrying out ──────────────────────────────────────────────────────────
    // Every action goes through the service that already owns it (Session for the
    // power verbs, Hypr for the compositor), never a Process of its own — the one
    // exception is a command of the user's, which is theirs by definition.
    function fire(rule) {
        if (root.blocker(rule.action, rule.command) !== "") return
        root.last = { rule: rule, at: Date.now() }
        switch (rule.action) {
        case "lock":      Session.lock(); break
        case "screenoff": root._screenOffBy = rule.id; Hypr.setDpms(false); break
        case "suspend":   Session.suspend(); break
        case "hibernate": Session.hibernate(); break
        case "logout":    Session.logout(); break
        case "poweroff":  Session.poweroff(); break
        case "command":   Quickshell.execDetached(Ia.parseCommand(rule.command)); break
        }
    }

    // The rule that blanked the screen, "" when none did.
    property string _screenOffBy: ""
    function _wake(ruleId) {
        if (root._screenOffBy === "" || (ruleId !== undefined && root._screenOffBy !== ruleId)) return
        root._screenOffBy = ""
        Hypr.setDpms(true)
    }

    // A destructive action's heads-up: an ordinary notification (Notifications' server),
    // critical so Do Not Disturb doesn't swallow it — and so it never times out by
    // itself, which is why every way out of the window clears it (_clearWarning): a
    // cancelled "Powering off in 30 s" left on screen would be a lie.
    function warn(rule) {
        Quickshell.execDetached(["notify-send", "--app-name=Inactivity", "--urgency=critical",
            "--icon=dialog-warning", Ia.warningTitle(rule), "Move the mouse or press a key to cancel."])
    }
    // Dismissed (history too: a cancelled warning is not something that happened).
    function _clearWarning() {
        for (const w of Notifications.popups.slice()) {
            try { if (w.n && w.n.appName === "Inactivity") Notifications.dismiss(w.n) } catch (e) {}
        }
    }

    Instantiator {
        model: root._rules
        delegate: IdleMonitor {
            id: mon
            required property var modelData

            // In the warning window: idle has tripped, the notification is up, and the
            // action waits on `grace`. Input (isIdle → false) or anything that disables
            // or rebuilds this monitor cancels it.
            property bool pending: false

            // Locking while locked has nothing to add (Lock.qml makes the same call);
            // every other action is still wanted behind a lock — suspend after lock is
            // the usual pair.
            enabled: root.enabled && mon.modelData.enabled
                     && !(mon.modelData.action === "lock" && Lock.locked)
            timeout: Ia.monitorSeconds(mon.modelData)
            respectInhibitors: true

            onIsIdleChanged: {
                if (mon.isIdle) {
                    if (Ia.warns(mon.modelData.action) && root.blocker(mon.modelData.action, "") === "") {
                        mon.pending = true
                        root.warn(mon.modelData)
                    } else root.fire(mon.modelData)
                } else {
                    if (mon.pending) root._clearWarning()
                    mon.pending = false
                    root._wake(mon.modelData.id)
                }
            }
            // Switched off, edited or deleted while it held the screen dark: nothing
            // would be left to wake it.
            onEnabledChanged: if (!mon.enabled) {
                if (mon.pending) root._clearWarning()
                mon.pending = false
                root._wake(mon.modelData.id)
            }
            Component.onDestruction: {
                if (mon.pending) root._clearWarning()
                root._wake(mon.modelData.id)
            }

            property Timer grace: Timer {
                interval: Ia.WARN_SECONDS * 1000
                running: mon.pending
                onTriggered: { mon.pending = false; root._clearWarning(); root.fire(mon.modelData) }
            }
        }
    }

    // ── Persistence, and the migration ────────────────────────────────────────
    JsonStore {
        id: store
        path: Quickshell.statePath("inactivity.json")
        onLoaded: root._load()
    }

    function _load() {
        const v = store.value ?? ({})
        root.enabled = v.enabled === true
        root._rules = Ia.normalizeRules(v.rules)
        root._migrate(v.migrated === true)
    }

    // Once, and only after BOTH documents are in: the lock settings live in config.json,
    // which loads separately and may land second.
    function _migrate(done) {
        if (done || !store.ready || !Config.prefsLoaded) return
        if (root._rules.length === 0) {
            root._rules = Ia.fromLegacyLock(Config.lockIdleEnabled, Config.lockIdleMinutes)
            root.enabled = Config.lockIdleEnabled
        }
        root._save()
    }

    Connections {
        target: Config
        function onPrefsLoadedChanged() { if (store.ready) root._migrate(store.value?.migrated === true) }
    }

    // ══ IPC ═══════════════════════════════════════════════════════════════════
    // `qs ipc -c ~/.config/quicktest call inactivity status`
    // Read-only plus the master switch: a keybind or script can turn the whole thing
    // off (the "I'm presenting" case); editing rules is the panel's job.
    property var _ipc: IpcHandler {
        target: "inactivity"

        function status(): string {
            if (!store.ready) return "not loaded yet"
            const list = root._rules.map(r => (r.enabled ? "" : "(off) ") + Ia.describe(r)).join("; ")
            return (root.enabled ? "on" : "off") + "  ·  " + (list || "no rules")
                   + (Idle.inhibited ? "  ·  held awake: " + Idle.reasonText : "")
        }
        function on(): void  { root.setEnabled(true) }
        function off(): void { root.setEnabled(false) }
    }
}
