pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// ── Keyboard ──────────────────────────────────────────────────────────────────
// Active XKB layout, e.g. "US".
//
// Live updates are event-driven: Hyprland's `activelayout` event fires on every
// layout change regardless of what caused it (this button, a keybind, another
// app). Nothing polls.
//
// ── Why hyprctl, and not the Hyprland singleton ───────────────────────────────
// Two things that LOOK like they should work, don't:
//
//   1. There is no `Hyprland.request()`. The IPC singleton exposes exactly
//      `dispatch()`, `monitorFor()` and `parse()` — nothing that runs a query
//      and hands back its output. So reading the initial layout means asking
//      hyprctl.
//
//   2. `Hyprland.dispatch("switchxkblayout all next")` is the LEGACY dispatch
//      syntax. This Hyprland runs in Lua dispatch mode (every other dispatch in
//      this shell is `hl.dsp.focus({...})` style, and `Hyprland.usingLua` is a
//      thing), where the old space-separated form doesn't fire — the button
//      would silently do nothing.
//
// So both go through hyprctl. This still deletes the `python3` interpreter that
// the old bar widget spawned to parse the device list, and it still happens once
// rather than once per bar layout per monitor.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    property string layout: "??"

    // ── Live updates ──────────────────────────────────────────────────────────
    // event.data → "keyboardName,Full Layout Name"
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            const sep = event.data.lastIndexOf(",")
            if (sep < 0) return
            root.layout = root.tagFor(event.data.substring(sep + 1).trim())
        }
    }

    // ── Initial read ──────────────────────────────────────────────────────────
    // One shot at startup, before any event has had a reason to fire.
    Process {
        id: query
        running: true
        command: ["hyprctl", "-j", "devices"]

        stdout: StdioCollector { id: queryOut }

        onExited: function(code) {
            if (code !== 0) {
                console.warn("Keyboard: hyprctl devices failed (exit " + code + ")")
                return
            }
            try {
                const kbs = JSON.parse(queryOut.text).keyboards ?? []
                if (kbs.length === 0) return
                // The "main" keyboard is the one whose layout Hyprland reports
                // and switches; fall back to the first if none is flagged.
                const kb = kbs.find(k => k.main) ?? kbs[0]
                if (kb && kb.active_keymap) root.layout = root.tagFor(kb.active_keymap)
            } catch (e) {
                console.warn("Keyboard: could not parse device list —", e)
            }
        }
    }

    function refresh() { query.running = true }

    // ══ Input configuration ═══════════════════════════════════════════════════
    // The settings page edits these. They live here rather than in the page for the
    // usual reason: the page is a Loader that gets torn down every time you flip to
    // Battery, and system state must not be owned by something that transient.
    //
    // ── kb_layout is a LIST, and that matters ─────────────────────────────────
    // It reads "us,pt" here — two layouts, which is what the bar's pill cycles
    // between. A settings page that models the layout as one string and writes it
    // back on click would silently delete the second one: you'd click "us" to
    // confirm what you already had, and lose Portuguese. So this is a list, and the
    // page adds to and removes from it.
    //
    // ── hyprctl keyword is session-only ───────────────────────────────────────
    // These changes die with the Hyprland session — they are not written to
    // hyprland.conf. The page says so, because a settings page that silently forgets
    // is worse than one that doesn't offer the setting.
    property var    layouts:     []      // e.g. ["us", "pt"]
    property string variant:     ""
    property int    repeatRate:  25
    property int    repeatDelay: 600

    // ── Reading them back ─────────────────────────────────────────────────────
    // One process, four options, no interpreter. `--batch` prints one JSON object
    // per option separated by blank lines, which is NOT valid JSON as a whole — so
    // it's parsed a line at a time rather than handed to JSON.parse() whole.
    Process {
        id: optionsQuery
        running: true
        command: ["hyprctl", "-j", "--batch",
                  "getoption input:kb_layout ; getoption input:kb_variant ; "
                + "getoption input:repeat_rate ; getoption input:repeat_delay"]

        stdout: StdioCollector { id: optionsOut }

        onExited: function(code) {
            if (code !== 0) {
                console.warn("Keyboard: hyprctl getoption failed (exit " + code + ")")
                return
            }
            for (const line of optionsOut.text.split("\n")) {
                const trimmed = line.trim()
                if (trimmed === "") continue
                try {
                    const o = JSON.parse(trimmed)
                    switch (o.option) {
                        case "input:kb_layout":
                            root.layouts = root._clean(o.str).split(",")
                                .map(s => s.trim()).filter(s => s !== "")
                            break
                        case "input:kb_variant":  root.variant     = root._clean(o.str); break
                        case "input:repeat_rate": root.repeatRate  = o.int; break
                        case "input:repeat_delay": root.repeatDelay = o.int; break
                    }
                } catch (e) {
                    console.warn("Keyboard: could not parse option line —", e)
                }
            }
        }
    }

    // Hyprland reports an UNSET string option as the literal "[[EMPTY]]", not "".
    // Taken at face value it displays as `us ([[EMPTY]])` and, worse, gets written
    // straight back as a variant named "[[EMPTY]]".
    function _clean(s) { return (!s || s === "[[EMPTY]]") ? "" : s }

    // ── Writing them ──────────────────────────────────────────────────────────
    // `keyword`, not a dispatch — so this is unaffected by the Lua dispatch mode
    // that rules out the legacy space-separated dispatch syntax everywhere else.
    Process { id: keywordProc }

    function _keyword(key, value) {
        keywordProc.running = false
        keywordProc.command = ["hyprctl", "keyword", key, String(value)]
        keywordProc.running = true
    }

    function setLayouts(list) {
        const next = list.filter(s => s !== "")
        if (next.length === 0) return          // no layouts at all = no keyboard
        root.layouts = next
        root._keyword("input:kb_layout", next.join(","))
    }

    function addLayout(name) {
        if (root.layouts.indexOf(name) !== -1) return
        root.setLayouts(root.layouts.concat([name]))
    }

    function removeLayout(name) {
        root.setLayouts(root.layouts.filter(l => l !== name))
    }

    function setRepeat(rate, delay) {
        root.repeatRate  = rate
        root.repeatDelay = delay
        keywordProc.running = false
        keywordProc.command = ["hyprctl", "--batch",
                               "keyword input:repeat_rate " + rate + " ; "
                             + "keyword input:repeat_delay " + delay]
        keywordProc.running = true
    }

    // ── Switch ────────────────────────────────────────────────────────────────
    // The `activelayout` event above updates `layout` once this lands, so there
    // is nothing to read back here.
    Process {
        id: switcher
        running: false
        command: ["hyprctl", "switchxkblayout", "all", "next"]
    }

    function next() {
        switcher.running = false
        switcher.running = true
    }

    // ── Tag extraction ────────────────────────────────────────────────────────
    // "English (US)" → "US"   (the parenthesised variant is the useful part)
    // "Portuguese"   → "PT"   (language name)
    // "Foobar"       → "FO"   (first two characters)
    function tagFor(name) {
        const paren = name.match(/\(([^)]+)\)/)
        if (paren) return paren[1].trim().toUpperCase()

        const map = {
            "english":    "EN", "portuguese": "PT", "polish":    "PL",
            "russian":    "RU", "german":     "DE", "french":    "FR",
            "spanish":    "ES", "italian":    "IT", "dutch":     "NL",
            "czech":      "CZ", "slovak":     "SK", "hungarian": "HU",
            "romanian":   "RO", "turkish":    "TR", "greek":     "GR",
            "arabic":     "AR", "hebrew":     "HE", "japanese":  "JA",
            "korean":     "KO", "chinese":    "ZH", "ukrainian": "UA",
            "swedish":    "SE", "norwegian":  "NO", "danish":    "DK",
            "finnish":    "FI", "belarusian": "BY", "serbian":   "RS",
            "croatian":   "HR", "slovenian":  "SI", "bulgarian": "BG",
        }
        const lower = name.toLowerCase().trim()
        for (const lang in map) {
            if (lower.startsWith(lang)) return map[lang]
        }
        return name.substring(0, 2).toUpperCase()
    }
}
