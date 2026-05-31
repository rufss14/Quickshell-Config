import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "../../theming" as T

// ── KeyboardLayout ────────────────────────────────────────────────────────────
// Pill button showing the active keyboard layout. Updates instantly on any
// layout change (button click, keybind, other app) via Hyprland's IPC.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    property bool barShape: false

    implicitHeight: T.Theme.pillHeight
    implicitWidth:  layoutLabel.implicitWidth + T.Theme.pillPadding * 2
    radius: T.Theme.radius(barShape)
    color:  T.Theme.pillBg

    Behavior on radius        { NumberAnimation { duration: T.Theme.animSlow;   easing.type: Easing.OutCubic } }
    Behavior on implicitWidth { NumberAnimation { duration: T.Theme.animNormal; easing.type: Easing.OutCubic } }

    // ── State ─────────────────────────────────────────────────────────────────
    property string currentLayout: "??"

    // ── Hover overlay ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: ma.containsMouse ? T.Theme.hoverAccent : "transparent"
        Behavior on color { ColorAnimation { duration: T.Theme.animFast } }
    }

    // ── Label ─────────────────────────────────────────────────────────────────
    Text {
        id: layoutLabel
        anchors.centerIn: parent
        text: root.currentLayout.toUpperCase()
        color: T.Theme.fg
        font.family:    T.Theme.fontFamily
        font.pixelSize: T.Theme.fontSize
        font.bold:      true
    }

    // ── Mouse area ────────────────────────────────────────────────────────────
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    switchLayout.running = true
    }

    // ── Hyprland IPC listener ─────────────────────────────────────────────────
    // `activelayout` fires on every layout change regardless of trigger source.
    // event.data → "keyboardName,Full Layout Name"
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activelayout") return
            var sep = event.data.lastIndexOf(",")
            if (sep < 0) return
            var layoutName = event.data.substring(sep + 1).trim()
            root.currentLayout = root.extractTag(layoutName)
        }
    }

    // ── Initial layout query ──────────────────────────────────────────────────
    // Reads the current layout once on startup before any IPC events arrive.
    Process {
        id: initialQuery
        running: true
        command: [
            "bash", "-c",
            "hyprctl devices -j | python3 -c '" +
            "import json,sys;" +
            "d=json.load(sys.stdin);" +
            "kbs=d.get(\"keyboards\",\"\");" +
            "kb=next((k for k in kbs if k.get(\"main\",False)),kbs[0] if kbs else None);" +
            "print(kb[\"active_keymap\"] if kb else \"??\")' 2>/dev/null || hyprctl devices | grep -A1 \"main: yes\" | grep \"active keymap\" | cut -d: -f2- | xargs"
        ]
        stdout: SplitParser {
            onRead: function(line) {
                var trimmed = line.trim()
                if (trimmed !== "") root.currentLayout = root.extractTag(trimmed)
            }
        }
    }

    // ── Switch layout ─────────────────────────────────────────────────────────
    // Cycles to next; the IPC event above updates the label automatically.
    Process {
        id: switchLayout
        command: ["hyprctl", "switchxkblayout", "all", "next"]
        onExited: function(code, status) {
            if (code === 0) notifyTimer.start()
        }
    }

    // Delay notification slightly so IPC event updates label first
    Timer {
        id: notifyTimer
        interval: 150
        repeat: false
        onTriggered: notifyProc.running = true
    }

    // ── Notification ──────────────────────────────────────────────────────────
    Process {
        id: notifyProc
        command: [
            "notify-send",
            "--app-name=Keyboard",
            "--icon=input-keyboard",
            "--urgency=low",
            "--expire-time=2000",
            "Keyboard Layout",
            "Switched to " + root.currentLayout
        ]
    }

    // ── Tag extractor ─────────────────────────────────────────────────────────
    // "English (US)"  → "US"   (prefers parenthesised variant)
    // "Portuguese"    → "PT"   (language name map)
    // "Foobar"        → "FO"   (first 2 chars fallback)
    function extractTag(name) {
        var m = name.match(/\(([^)]+)\)/)
        if (m) return m[1].trim().toUpperCase()

        var map = {
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
        var lower = name.toLowerCase().trim()
        for (var lang in map) {
            if (lower.startsWith(lang)) return map[lang]
        }

        return name.substring(0, 2).toUpperCase()
    }
}
