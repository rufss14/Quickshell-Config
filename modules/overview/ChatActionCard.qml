import QtQuick
import Quickshell
import "../../config"
import "../../components"
import "../../services"

// ── ChatActionCard ────────────────────────────────────────────────────────────
// One thing a reply did (or wants to do) on the Ask page (FeedAssistant → ChatMessage): what it
// is — a colour scheme as its swatches, anything else as its icon on a tile — and where it stands
// (services/Assistant `stateOf`):
//
//   working   still going (play: finding the track) — the icon turns
//   applied   "Done" and a tick that pops in, with Undo when there's something to put back
//   ask       it waits for you: Do it / Skip (lock, reload, the power menu, recording, Settings)
//   failed    why not, in the danger colour
//   undone    "Undone", with Redo
//   skipped   "Skipped"
//   invalid   what the model asked for that isn't allowed, and why
//
// A state change crossfades the right-hand side; the card's own colour follows.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var act
    required property int msg
    required property int slot
    property color accent: Colors.of(QsWindow.window).primary

    readonly property var st: Assistant.stateOf(root.msg, root.slot)
    readonly property string state_: root.act.do === "invalid" ? "invalid" : (root.st ? root.st.state : "")
    readonly property bool asking: root.state_ === "ask"
    readonly property bool done: root.state_ === "applied"
    readonly property bool bad: root.state_ === "invalid" || root.state_ === "failed"

    // A colour scheme shows its colours: the reply's own, or a saved one's.
    readonly property var swatch: {
        if (root.act.do === "scheme") return root.act.swatch ?? []
        if (root.act.do === "preset") {
            const p = ColorScheme.schemePalette(root.act.name)
            if (!p || !p.colors) return []
            const c = p.colors
            return [p.special?.background ?? c.color0, c.color1, c.color2, c.color3, c.color4, c.color5, c.color6, p.special?.foreground ?? c.color7]
        }
        return []
    }
    readonly property string symbol: {
        switch (root.act.do) {
        case "set":        return root.act.key === "themeMode" ? (root.act.value === "light" ? "light_mode" : "dark_mode") : "tune"
        case "action":     return (ShellActions.table.find(x => x.id === root.act.id) ?? { symbol: "bolt" }).symbol
        case "volume":     return "volume_up"
        case "brightness": return "brightness_6"
        case "wallpaper":  return root.act.random ? "shuffle" : "wallpaper"
        case "media":      return root.act.command === "next" ? "skip_next" : root.act.command === "previous" ? "skip_previous"
                                : root.act.command === "pause" ? "pause" : "play_arrow"
        case "workspace":  return "grid_view"
        case "launch":     return "open_in_new"
        case "timer":      return "timer"
        case "scene":      return "wallpaper"
        case "play":       return "music_note"
        case "open":       return "language"
        case "search":     return "search"
        case "remind":     return "notifications"
        case "todo":       return "checklist"
        case "alarm":      return "alarm"
        case "window":     return "window"
        case "output":     return "speaker"
        case "appvolume":  return "volume_up"
        case "bluetooth":  return "bluetooth"
        case "clip":       return "movie"
        case "screenshot": return "screenshot"
        case "look":       return "palette"
        case "discord":    return root.act.command === "deafen" || root.act.command === "undeafen" ? "headset"
                                : root.act.command === "leave" ? "logout" : root.act.command === "camera" ? "videocam"
                                : root.act.command === "screenshare" ? "monitor" : "mic_off"
        case "discordvolume": return root.act.target === "input" ? "mic" : "volume_up"
        case "discorduser":   return "volume_off"
        case "discordsetting": return "tune"
        case "findsetting": return "settings"
        case "remember":
        case "forget":     return "bookmark"
        }
        return "error"
    }
    readonly property string kind: {
        switch (root.act.do) {
        case "scheme":     return Translation.tr("New colour scheme")
        case "preset":     return Translation.tr("Saved colour scheme")
        case "set":        return Translation.tr("Setting")
        case "action":     return Translation.tr("Shell")
        case "launch":     return Translation.tr("App")
        case "scene":      return Translation.tr("Wallpaper Engine")
        case "play":       return "Spotify"
        case "open":       return Translation.tr("Website")
        case "remind":     return Translation.tr("Reminder")
        case "todo":       return Translation.tr("To-do list")
        case "alarm":      return Translation.tr("Alarm")
        case "look":       return Translation.tr("Workspace look")
        case "remember":
        case "forget":     return Translation.tr("Memory")
        }
        return ""
    }
    readonly property string line: root.state_ === "invalid" ? root.act.reason
                                 : root.st && root.st.note !== "" ? root.st.note
                                 : root.asking ? Translation.tr("Waiting for your OK")
                                 : root.state_ === "working" ? Translation.tr("Working…")
                                 : root.done ? (root.kind !== "" ? root.kind + " · " : "") + Translation.tr("done")
                                 : root.state_ === "undone" ? Translation.tr("Undone")
                                 : root.state_ === "skipped" ? Translation.tr("Skipped")
                                 : root.kind

    implicitHeight: row.implicitHeight + Tokens.spacingSm * 2
    radius: Tokens.radiusCard - Tokens.spacingXs
    color: Colors.of(QsWindow.window).fade(
               root.asking ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceHigh, root.accent, 0.14)
             : root.bad ? Colors.of(QsWindow.window).mix(Colors.of(QsWindow.window).surfaceContainer, Colors.of(QsWindow.window).danger, 0.08)
             : Colors.of(QsWindow.window).surfaceHigh, 0.94)
    border.width: Tokens.borderWidth
    border.color: root.asking ? Colors.of(QsWindow.window).alpha(root.accent, 0.6)
                : root.bad ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.4)
                : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.08)
    Behavior on color { ColorAnimation { duration: Motion.standard } }
    Behavior on border.color { ColorAnimation { duration: Motion.standard } }

    Item {
        id: row
        x: Tokens.spacingSm
        y: Tokens.spacingSm
        width: root.width - Tokens.spacingSm * 2
        implicitHeight: Math.max(tile.height, words.implicitHeight, side.height)

        // ── What: its colours, or its icon on a tile ────────────────────────────
        Rectangle {
            id: tile
            anchors.verticalCenter: parent.verticalCenter
            width: root.swatch.length > 0 ? swatches.width + Tokens.spacingSm * 2 : Tokens.iconXl
            height: Tokens.iconXl
            radius: Tokens.radiusSm
            color: root.bad ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).danger, 0.16)
                            : Colors.of(QsWindow.window).alpha(root.accent, 0.16)
            MaterialIcon {
                id: tileIcon
                anchors.centerIn: parent
                visible: root.swatch.length === 0
                name: root.bad ? "error" : root.symbol
                // A sway while it works.
                SequentialAnimation on rotation {
                    running: root.state_ === "working" && Config.motionEnabled
                    loops: Animation.Infinite
                    NumberAnimation { from: -12; to: 12; duration: 420; easing.type: Motion.ambient }
                    NumberAnimation { from: 12; to: -12; duration: 420; easing.type: Motion.ambient }
                    onRunningChanged: if (!running) tileIcon.rotation = 0
                }
                fill: 1
                color: root.bad ? Colors.of(QsWindow.window).danger : root.accent
                font.pixelSize: Tokens.iconMd
            }
            Row {
                id: swatches
                anchors.centerIn: parent
                visible: root.swatch.length > 0
                spacing: -5
                Repeater {
                    model: root.swatch
                    delegate: Rectangle {
                        required property var modelData
                        width: 16
                        height: 16
                        radius: Tokens.radiusSm
                        color: modelData
                        border.width: 2
                        border.color: tile.color.a > 0 ? Colors.of(QsWindow.window).surfaceHigh : "transparent"
                    }
                }
            }
        }

        // ── Its name, and where it stands ───────────────────────────────────────
        Column {
            id: words
            anchors.left: tile.right
            anchors.leftMargin: Tokens.spacingSm
            anchors.right: side.left
            anchors.rightMargin: Tokens.spacingSm
            anchors.verticalCenter: parent.verticalCenter
            StyledText {
                width: parent.width
                text: root.state_ === "invalid" ? Translation.tr("Not allowed") : root.act.label
                variant: "caption"
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Row {
                width: parent.width
                spacing: Tokens.spacingXs
                MaterialIcon {
                    id: tick
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.done
                    name: "check"
                    color: root.accent
                    font.pixelSize: Tokens.iconSm - 2
                    SpringValue { id: tickPop; target: root.done ? 1 : 0.4; spec: Motion.springSpatial; epsilon: 0.002 }
                    scale: tickPop.value
                }
                StyledText {
                    width: parent.width - (tick.visible ? tick.width + Tokens.spacingXs : 0)
                    text: root.line
                    variant: "micro"
                    color: root.bad ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgMuted
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
            }
        }

        // ── The buttons for this state ──────────────────────────────────────────
        Row {
            id: side
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.spacingXs
            opacity: 1
            Behavior on opacity { NumberAnimation { duration: Motion.fast } }

            ChipButton {
                visible: root.asking
                symbol: "check"
                label: Translation.tr("Do it")
                solid: true
                tint: root.accent
                onActivated: Assistant.confirm(root.msg, root.slot)
            }
            ChipButton {
                visible: root.asking
                symbol: "close"
                tint: root.accent
                onActivated: Assistant.skip(root.msg, root.slot)
            }
            ChipButton {
                visible: root.done && root.st && root.st.undo !== null
                symbol: "undo"
                label: Translation.tr("Undo")
                tint: root.accent
                onActivated: Assistant.undo(root.msg, root.slot)
            }
            ChipButton {
                visible: root.state_ === "undone"
                symbol: "replay"
                label: Translation.tr("Redo")
                tint: root.accent
                onActivated: Assistant.redo(root.msg, root.slot)
            }
        }
    }
}
