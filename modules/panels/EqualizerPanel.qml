pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../config"
import "../../components"
import "../../services"
import "../../state"
import "mixer"

// ── EqualizerPanel ────────────────────────────────────────────────────────────
// The audio mixer, laid out like the wallpaper and colour scheme pages (docs/island-style.md).
//
// A column on the LEFT: the loud card (`MixerHero`: the output as a shape that swells with the sound, its level as
// a numeral, the fader, and tools for mute, the next output and boost) and under it the source rail (`SourceRail`:
// Apps, Devices, Microphone, Options, a sliding pill, a figure each). The page on show takes the rest:
//
//   Apps         `MixerApps`     a card per app that is making sound (its picture is its meter; a tap mutes; under
//                                the pointer: keep it as it is, play it elsewhere), and the apps the mixer remembers
//   Devices      `MixerDevices`  every output and input; the one in use is the loud card; an output opens its
//                                limit and balance inline
//   Microphone   `MixerMic`      its level, hear yourself, and which apps are recording you
//   Options      `MixerOptions`  boost, per-output volume memory, and restarting audio behind a confirm layer
//
// One size on the island and in the bar's plain dock: 780 x 436, as the colour scheme page is.
//
// ── It owns no state ──────────────────────────────────────────────────────────
// A view over the Audio service (native PipeWire: a level is read from a property and written by assigning one,
// PipeWire pushes, no timer, no subprocess) and MixerMemory (pins). Routing, codec and the mic test are the
// service's too (Audio.moveStream, bluetoothCodecOf, MicTest); the files in mixer/ only show them.
//
// ── Two things that bit the first attempts ────────────────────────────────────
// 1. The shell's own sound effects. Each cue is a `pw-play` process, which shows up as a playback stream for a few
//    hundred ms on every hover and keystroke. Bound straight to Audio.streams the app list was rebuilt (and every
//    card's entrance replayed) with each one. `apps` leaves them out, and MixerApps keys its model by node id, so an
//    app starting or stopping adds or removes ITS card and nothing else moves.
// 2. Meters cost. A PwNodePeakMonitor asks PipeWire to keep streaming peak data for its node, so every meter is
//    enabled only while its page is showing, and the dock's Loader tears the panel down on close.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    // ── As an island page ─────────────────────────────────────────────────────
    // On the island (IslandCard) it has no outer padding: the rail names it and the card has its gutter. Off it, in
    // the bar's plain dock, it is the same page at the same size with a margin round it.
    property bool island: false
    readonly property int bodyW: 780
    readonly property int bodyH: 436
    readonly property int sideW: Math.round(root.bodyW / 3)
    implicitWidth:  root.bodyW + (root.island ? 0 : Tokens.spacingMd * 2)
    implicitHeight: root.bodyH + (root.island ? 0 : Tokens.spacingMd * 2)
    // Set by the side dock, which has less room on a short screen. The page is one size, so it is not used.
    property real maxHeight: 0

    readonly property color accent: Colors.of(QsWindow.window).primary

    property string view: "apps"            // "apps" | "devices" | "mic" | "options"

    // `qs ipc call island part equalizer devices`: open on a page (apps | devices | mic | options).
    Component.onCompleted: {
        const asked = UiState.islandPartFor("equalizer")
        const part = asked === "input" ? "mic" : asked
        if (root.island && ["apps", "devices", "mic", "options"].indexOf(part) >= 0) root.view = part
    }

    // A loopback on speakers howls, and MicTest only stops itself after a minute. The panel closing is a good
    // moment to not leave it running.
    Component.onDestruction: MicTest.stop()

    // ── Output past 100% ──────────────────────────────────────────────────────
    // Off by default; kept across reloads (Config.mixerBoost), and so is a boosted level (Audio.qml restores it above
    // 100% only while this is on). A boosted sink clips: turning it off pulls the output back to 100%.
    readonly property bool boost: Config.mixerBoost
    readonly property real maxLevel: root.boost ? Math.round(Audio.boostCeiling * 100) : 100
    onBoostChanged: if (!root.boost && Audio.volume > 1) Audio.setVolume(1, false)

    // The apps playing, without the shell's own cues (see the header).
    readonly property var apps: Audio.streams.filter(n => Audio.appIdFor(n) !== "pw-play")

    // The pinned apps, newest first.
    readonly property var pins: Object.keys(MixerMemory.apps)
        .map(k => Object.assign({ key: k }, MixerMemory.apps[k]))
        .sort((a, b) => b.at - a.at)
    function pinLine(rec) {
        const sink = rec.sink !== "" ? Audio.sinks.find(s => s.name === rec.sink) : null
        return Math.round(rec.level * 100) + "%" + (rec.muted ? " · " + Translation.tr("muted") : "")
             + (rec.sink !== "" ? " · " + (sink ? Audio.shortLabelFor(sink) : Translation.tr("output not connected")) : "")
    }

    // ── App presentation ──────────────────────────────────────────────────────
    // Icon resolution lives in the Icons service (Audio.iconPathFor delegates to it): declared icon name → desktop
    // entry lookup by process binary → "". The glyph is the LAST resort, for an app that resolves to no icon at all:
    // it still names the app rather than saying "audio".
    function glyphFor(node) {
        const n = Audio.labelFor(node).toLowerCase()
        if (n.includes("firefox") || n.includes("zen"))                              return "󰈹"
        if (n.includes("chrome") || n.includes("chromium"))                           return "󰊯"
        if (n.includes("spotify"))                                                    return "󰓇"
        if (n.includes("mpv"))                                                        return "󰎁"
        if (n.includes("vlc"))                                                        return "󰕼"
        if (n.includes("discord") || n.includes("vesktop") || n.includes("vencord"))  return "󰙯"
        if (n.includes("telegram"))                                                   return "󰔁"
        if (n.includes("steam"))                                                      return "󰓓"
        if (n.includes("lutris"))                                                     return "󰊗"
        if (n.includes("obs"))                                                        return "󰐋"
        if (n.includes("zoom") || n.includes("teams"))                                return "󰤅"
        return "󰓃"
    }

    Item {
        id: frame
        anchors.fill: parent
        anchors.margins: root.island ? 0 : Tokens.spacingMd

        // ══ The left column: the output, and where to go ═════════════════════════
        ColumnLayout {
            id: sideCol
            width: root.sideW
            height: parent.height
            spacing: Tokens.spacingMd

            MixerHero {
                Layout.fillWidth: true
                Layout.fillHeight: true
                panel: root
            }
            SourceRail {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 4 * (Tokens.iconXl + Tokens.spacingMd) + Tokens.spacingSm * 2 + Tokens.spacingXs * 3
                current: root.view
                model: [
                    { value: "apps",    label: Translation.tr("Apps"),       icon: "music_note",   shape: "cookie7",
                      figure: String(root.apps.length) },
                    { value: "devices", label: Translation.tr("Devices"),    icon: "speaker",      shape: "cookie9",
                      figure: String(Audio.sinks.length + Audio.sources.length) },
                    { value: "mic",     label: Translation.tr("Microphone"), icon: Audio.micMuted ? "mic_off" : "mic", shape: "sunny",
                      figure: Audio.recordingApps.length > 0 ? String(Audio.recordingApps.length) : (Audio.micMuted ? Translation.tr("Off") : ""),
                      big: Audio.recordingApps.length > 0, live: Audio.recordingApps.length > 0 },
                    { value: "options", label: Translation.tr("Options"),    icon: "tune",         shape: "clover",
                      figure: Config.mixerBoost ? Translation.tr("Boost") : "", big: false }
                ]
                onPicked: function (v) { root.view = v }
            }
        }

        // ══ The page on show ═════════════════════════════════════════════════════
        Item {
            id: pageArea
            anchors.left: sideCol.right
            anchors.leftMargin: Tokens.spacingMd
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            MixerApps    { anchors.fill: parent; panel: root }
            MixerDevices { anchors.fill: parent; panel: root }
            MixerMic     { anchors.fill: parent; panel: root }
            MixerOptions { anchors.fill: parent; panel: root }
        }
    }
}
