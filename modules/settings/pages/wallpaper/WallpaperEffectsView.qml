pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Widgets
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../.."

// WallpaperEffectsView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
// ── EFFECTS (2026-10-31) ─────────────────────────────────────────
// The wallpaper moved by the music (modules/desktop/WallFx): its own tab — it sat
// among Appearance's cards, where the user couldn't find it.
Flickable {
    id: fxFlick
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    anchors.fill: parent
    contentWidth: width
    contentHeight: fxGrid.implicitHeight - fxGrid.topTrim
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: page.view === "effects"

    opacity: page.view === "effects" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    BentoGrid {
        id: fxGrid
        y: -fxGrid.topTrim
        width: fxFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
        bentoCols: page.colsFor(fxFlick.width)
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingLg

        // The switch, the bars' outline, the intensity, and the sound map (2026-10-31).
        // No presets: the user wanted the effects to "adapt to the song itself, letting
        // the user change intensity" — the song weighs every sound (services/wallfx.js
        // adapt), and the map's trims are for a sound you want more or less of.
        QuickToggleTile {
            roomy: true
            symbol: "music_note"
            label:  Translation.tr("Music effects")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallFx
            available: Config.wallShellRender
            subLabel: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                    : Config.wallFx ? "The wallpaper moves with what's playing"
                    :                 "The wallpaper stays still"
            help: Translation.tr("Pictures, and Wallpaper Engine scenes the shell plays from a window (scene preload on). Rests while nothing plays, behind a fullscreen window and in Game Mode.")
            onToggled: Config.wallFx = !Config.wallFx
        }

        QuickToggleTile {
            roomy: true
            symbol: "auto_awesome"
            label:  Translation.tr("Bars glow with the music")
            accent: Colors.of(QsWindow.window).primary
            active: Config.barMusicReact
            subLabel: Config.barMusicReact ? "A thin outline on both bars' pills, as loud as the music"
                    :                        "The bars stay still"
            onToggled: Config.barMusicReact = !Config.barMusicReact
        }

        Section {
            span: 2
            symbol: "tune"
            title: Translation.tr("Intensity")
            // What the beat clock hears, and what the effects are adapting to.
            subtitle: !MusicPulse.probed ? ""
                    : !MusicPulse.dspOk ? "Following the bass with cava"
                    : !MusicPulse.live ? "Listens while music plays"
                    : MusicPulse.locked ? "In time at " + Math.round(MusicPulse.bpm) + " BPM"
                    :                     "Finding the beat…"
            padding: Tokens.spacingMd
            enabled: Config.wallShellRender && Config.wallFx
            opacity: enabled ? 1 : 0.5
            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Intensity")
                help: Translation.tr("How strong everything is at its biggest. The song does the rest: calm parts settle to a soft glow, big parts move, the drop hits hardest, and a busy part (sixteenth hi-hats) plays smaller.")
                from: 0; to: 1; step: 0.05
                value: Config.wallFxIntensity
                readout: Math.round(Config.wallFxIntensity * 100) + "%"
                onCommit: function(v) { Config.wallFxIntensity = v }
            }
            StyledText {
                Layout.fillWidth: true
                visible: MusicPulse.probed && !MusicPulse.dspOk
                text: Translation.tr("Install python-numpy to hear the drums apart and keep time with the beat.")
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }
            // The rhythm engine already shows each hit when the speakers play it (the
            // latency PipeWire reports); Sync is on top of that.
            StyledText {
                Layout.fillWidth: true
                visible: MusicPulse.dspOk && MusicPulse.latencyMs > 0
                text: "Lined up with your speakers: " + MusicPulse.latencyMs + " ms behind what's played"
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }
            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Sync")
                enabled: MusicPulse.dspOk    // the cava fallback has no clock to move
                help: Translation.tr("The effects already wait for your speakers. If they still land before the beat you hear (Bluetooth adds more delay than it reports), hold them back further.")
                from: 0; to: 300; step: 5
                value: Config.wallFxSyncMs
                readout: Config.wallFxSyncMs === 0 ? "as heard" : Config.wallFxSyncMs + " ms later"
                onCommit: function(v) { Config.wallFxSyncMs = Math.round(v) }
            }
        }

        // ── The sound map ──────────────────────────────────────────
        // A row per sound: a dot that lights when it's heard, the look it drives, and
        // its trim (auto = what the song gives it; 0 is off, up to twice as strong).
        Section {
            span: 2
            symbol: "equalizer"
            title: Translation.tr("Sound map")
            subtitle: !MusicPulse.live ? "Each sound and what it moves"
                    : MusicPulse.character !== "" ? "This song: " + MusicPulse.character
                    :                               "Getting to know this song…"
            help: Translation.tr("Every sound is on, and the song decides how much each one shows: little in a calm part, all of it in a big one, more on the drop. Slide one to want more or less of it; Auto puts every sound back. Strobe is never on unless you turn it on.")
            padding: Tokens.spacingMd
            enabled: Config.wallShellRender && Config.wallFx
            opacity: enabled ? 1 : 0.5
            actions: ChipTray {
                visible: Object.keys(Config.wallFxMix || {}).length > 0
                ChipButton {
                    label:  Translation.tr("Auto")
                    symbol: "refresh"
                    tint:   Colors.of(QsWindow.window).primary
                    onActivated: Config.wallFxMix = ({})
                }
            }

            Repeater {
                model: FX.SOUNDS
                // The row is shared with the Wallpaper panel's Effects view.
                delegate: WallFxSoundRow {
                    required property var modelData
                    sound: modelData
                }
            }
        }
    }
}
