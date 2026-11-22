pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../../../../services/wallfx.js" as FX
import "../../../../state"
import "../.."

// ── WallpaperEffectsView — Wallpaper › Music on the desktop ───────────────────
// The rail page `WallpaperPage.qml#music`: the wallpaper moved by the music
// (modules/desktop/WallFx) and the desktop visualiser (CavaBG), the two things on the
// desktop that answer the song. Grouped rows (docs/settings-style.md §1.6), no hero.
// Reads the page's state through `page` (WallpaperPage.qml's root), which shows this
// while `page.view === "music"`.
//
// No presets for the effects: they adapt to the song itself (services/wallfx.js adapt),
// the user sets the intensity, and the sound map's trims are for a sound you want more or
// less of. The bars' own music glow is a bar setting (Bar & islands › Style); a link row
// stands where its switch was.
SettingsPage {
    id: view
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page

    anchors.fill: parent
    // Disabled while hidden: SettingsPage.reveal() answers only an enabled page, so a hidden
    // view never consumes a search hit meant for the one on show. Turning on reveals it.
    enabled: page.view === "music"
    onEnabledChanged: if (view.enabled) view.reveal()
    opacity: page.view === "music" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity {
        enabled: view.page.viewMotion
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // The effects need the shell to draw the wallpaper, and their own switch on.
    readonly property bool fxLive: Config.wallShellRender && Config.wallFx

    // The visualiser can wear the shell's gradient only while that is on (CavaBG `matchGrad`); when
    // it does, its own colour picks have nothing to say.
    readonly property bool gradOn: Config.barGradient?.on === true
    readonly property bool gradMatch: Config.cavaBgGradient && view.gradOn

    grouped:     true
    headerShape: "clover"
    glyph:       "󰲹"
    title:       Translation.tr("Wallpaper")
    titleTail:   Translation.tr("Music on the desktop")
    accent:      Colors.of(QsWindow.window).primary
    subtitle: {
        const fx = !Config.wallShellRender ? Translation.tr("Effects need the shell to draw the wallpaper")
                 : Config.wallFx ? Translation.tr("Moving with the music")
                 : Translation.tr("Effects off. The wallpaper stays still")
        return Config.cavaBg ? fx + " · " + Translation.tr("Visualiser on") : fx
    }

    // ══ Music effects ═════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "music_note"
        title:   Translation.tr("Music effects")
        // What the beat clock hears, and what the effects are adapting to.
        subtitle: !MusicPulse.probed ? ""
                : !MusicPulse.dspOk ? "Following the bass with cava"
                : !MusicPulse.live ? "Listens while music plays"
                : MusicPulse.locked ? "In time at " + Math.round(MusicPulse.bpm) + " BPM"
                :                     "Finding the beat…"

        SettingRow {
            rowTap: true
            enabled: Config.wallShellRender
            opacity: enabled ? 1 : 0.4
            label:  Translation.tr("Music effects")
            detail: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                  : Config.wallFx ? "The wallpaper moves with what's playing"
                  :                 "The wallpaper stays still"
            help:   Translation.tr("Pictures, and Wallpaper Engine scenes the shell plays from a window (scene preload on). Rests while nothing plays, behind a fullscreen window and in Game Mode.")
            onTapped: Config.wallFx = !Config.wallFx

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallFx
                onToggled: Config.wallFx = !Config.wallFx
            }
        }

        Fader {
            enabled: view.fxLive
            opacity: enabled ? 1 : 0.4
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
        // latency PipeWire reports); Sync is on top of that. One segment with its note.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs
            enabled: view.fxLive && MusicPulse.dspOk    // the cava fallback has no clock to move
            opacity: enabled ? 1 : 0.4

            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Sync")
                help: Translation.tr("The effects already wait for your speakers. If they still land before the beat you hear (Bluetooth adds more delay than it reports), hold them back further.")
                from: 0; to: 300; step: 5
                value: Config.wallFxSyncMs
                readout: Config.wallFxSyncMs === 0 ? "as heard" : Config.wallFxSyncMs + " ms later"
                onCommit: function(v) { Config.wallFxSyncMs = Math.round(v) }
            }
            StyledText {
                Layout.fillWidth: true
                visible: MusicPulse.dspOk && MusicPulse.latencyMs > 0
                text: "Lined up with your speakers: " + MusicPulse.latencyMs + " ms behind what's played"
                variant: "caption"
                color: Colors.of(QsWindow.window).fgDim
                wrapMode: Text.WordWrap
            }
        }

        // The bars' glow moved to the bar's own page; this row takes you there.
        SettingRow {
            rowTap: true
            label:  Translation.tr("Bar glow is set in Bar & islands › Style")
            detail: Config.barMusicReact ? Translation.tr("On") : Translation.tr("Off")
            onTapped: view.page.openKey("BarStylePage.qml")

            MaterialIcon {
                name: "chevron_right"
                color: Colors.of(QsWindow.window).fgDim
                variant: "body"
            }
        }
    }

    // ══ The sound map ═════════════════════════════════════════════════════════
    // A row per sound: a dot that lights when it's heard, the look it drives, and its
    // trim (auto = what the song gives it; 0 is off, up to twice as strong).
    Section {
        grouped: true
        symbol:  "equalizer"
        title:   Translation.tr("Sound map")
        subtitle: !MusicPulse.live ? "Each sound and what it moves"
                : MusicPulse.character !== "" ? "This song: " + MusicPulse.character
                :                               "Getting to know this song…"
        help: Translation.tr("Every sound is on, and the song decides how much each one shows: little in a calm part, all of it in a big one, more on the drop. Slide one to want more or less of it; Auto puts every sound back. Strobe is never on unless you turn it on.")
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
            delegate: WallFxSoundRow {
                required property var modelData
                sound: modelData
                gutterMark: true
                live: view.fxLive
                // The Fader dims itself while the effects are off.
                enabled: view.fxLive
            }
        }
    }

    // ══ Desktop visualiser ════════════════════════════════════════════════════
    // A live spectrum pinned behind your windows (CavaBG). Config, not UiState: a
    // preference that survives a restart. The group's switch is in its heading; the rest
    // shows once it is on (a style picker for a spectrum you can't see is noise).
    Section {
        grouped: true
        visible: Audio.ready
        glyph:   "󰺣"
        title:   Translation.tr("Desktop visualiser")
        subtitle: Config.cavaBg ? "Behind your windows" : "Off"
        help:    Translation.tr("A live spectrum of what's playing, pinned behind your windows.")
        actions: Toggle {
            checked: Config.cavaBg
            accent:  Colors.of(QsWindow.window).primary
            accessibleName: Translation.tr("Desktop visualiser")
            onToggled: Config.cavaBg = !Config.cavaBg
        }

        // Four renderers over the one analyser (CavaBG.qml).
        TabStrip {
            visible: Config.cavaBg
            connected: true
            Layout.fillWidth: true
            accent: Colors.of(QsWindow.window).primary
            model: [
                { value: "bars", label: "Bars",     icon: "bar_chart" },
                { value: "wave", label: "Waveform", icon: "equalizer" },
                { value: "dots", label: "Dots",     icon: "more_horiz" },
                { value: "ring", label: "Ring",     icon: "radio_button_unchecked" }
            ]
            current: Config.cavaBgStyle
            onPicked: function(v) { Config.cavaBgStyle = v }
        }

        Fader {
            visible: Config.cavaBg
            label:  Translation.tr("Intensity")
            accent: Colors.of(QsWindow.window).primary
            from: 0.5; to: 3.0; step: 0.1
            value:   Config.cavaBgIntensity
            readout: Config.cavaBgIntensity.toFixed(1) + "×"
            onCommit: function(v) { Config.cavaBgIntensity = Math.round(v * 10) / 10 }
        }

        SettingRow {
            rowTap: true
            visible: Config.cavaBg
            label:  Translation.tr("Music only")
            detail: Config.cavaBgMusicOnly ? Translation.tr("The player's own sound. Calls and alerts don't move it")
                                           : "Everything you hear"
            onTapped: Config.cavaBgMusicOnly = !Config.cavaBgMusicOnly
            Toggle {
                checked: Config.cavaBgMusicOnly
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBgMusicOnly = !Config.cavaBgMusicOnly
            }
        }
        SettingRow {
            rowTap: true
            visible: Config.cavaBg && (Config.cavaBgStyle === "bars" || Config.cavaBgStyle === "ring")
            label:  Translation.tr("Peak caps")
            detail: Translation.tr("A cap over each bar that holds, then falls")
            onTapped: Config.cavaBgPeaks = !Config.cavaBgPeaks
            Toggle {
                checked: Config.cavaBgPeaks
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBgPeaks = !Config.cavaBgPeaks
            }
        }
        SettingRow {
            rowTap: true
            visible: Config.cavaBg
            label:  Translation.tr("Glow")
            detail: Translation.tr("A soft light round it, in its colour")
            onTapped: Config.cavaBgGlow = !Config.cavaBgGlow
            Toggle {
                checked: Config.cavaBgGlow
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBgGlow = !Config.cavaBgGlow
            }
        }
        SettingRow {
            rowTap: true
            visible: Config.cavaBg && Config.cavaBgStyle === "ring"
            label:  Translation.tr("Album cover")
            detail: Translation.tr("The cover inside the ring while music plays")
            onTapped: Config.cavaBgRingCover = !Config.cavaBgRingCover
            Toggle {
                checked: Config.cavaBgRingCover
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBgRingCover = !Config.cavaBgRingCover
            }
        }
    }

    // ══ The visualiser's colours ═════════════════════════════════════════════
    // Its own group, so the visualiser's switches and its palette sit in two columns.
    // A blend of up to cavaBgBlendMax: tap a swatch to add it, numbered in the order
    // they blend; tap a numbered one to take it out. Full, a tap swaps the last one.
    // Album is the cover's accent. The swatch is drawn inline (SoundPage's CavaSwatch
    // is an inline component there, and a new type here would need a cold restart).
    Section {
        grouped: true
        visible: Audio.ready && Config.cavaBg
        symbol:  "palette"
        title:   Translation.tr("Visualiser colours")

        SettingRow {
            rowTap: true
            visible: Config.cavaBg
            enabled: view.gradOn
            label:  Translation.tr("Match the gradient")
            detail: view.gradOn ? Translation.tr("The bar's colours and angle, in place of your own")
                                : Translation.tr("Needs the gradient on: Colours › Gradient")
            onTapped: Config.cavaBgGradient = !Config.cavaBgGradient
            Toggle {
                checked: Config.cavaBgGradient
                accent:  Colors.of(QsWindow.window).primary
                onToggled: Config.cavaBgGradient = !Config.cavaBgGradient
            }
        }

        ColumnLayout {
            visible: Config.cavaBg && !view.gradMatch
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            SettingRow {
                label:  Translation.tr("Colours")
                detail: Translation.tr("Tap up to %1. They blend in the order you pick them").arg(Config.cavaBgBlendMax)
            }
            Flow {
                Layout.fillWidth: true
                spacing: Tokens.spacingSm
                Repeater {
                    model: Config.cavaBgColors
                    delegate: Rectangle {
                        id: sw
                        required property var modelData
                        readonly property int order: Config.cavaBlendClean(Config.cavaBgBlend).indexOf(sw.modelData.id) + 1
                        implicitWidth: Tokens.iconXl
                        implicitHeight: Tokens.iconXl
                        radius: Tokens.radiusSm
                        color: sw.modelData.id === "album" ? AlbumArt.accent
                             : Colors.of(QsWindow.window).role(sw.modelData.id, Colors.of(QsWindow.window).ramp3)
                        border.width: sw.order > 0 ? 2 : Tokens.borderWidth
                        border.color: sw.order > 0 ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).outline
                        // Its place in the blend: a small badge, legible on any swatch.
                        Rectangle {
                            visible: sw.order > 0
                            anchors.centerIn: parent
                            width: Tokens.iconSm
                            height: Tokens.iconSm
                            radius: width / 2
                            color: Colors.of(QsWindow.window).fg
                            StyledText {
                                anchors.centerIn: parent
                                text: sw.order
                                variant: "caption"
                                color: Colors.of(QsWindow.window).base
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const b = Config.cavaBlendClean(Config.cavaBgBlend).slice()
                                const i = b.indexOf(sw.modelData.id)
                                if (i >= 0) { if (b.length > 1) b.splice(i, 1) }
                                else if (b.length < Config.cavaBgBlendMax) b.push(sw.modelData.id)
                                else b[b.length - 1] = sw.modelData.id
                                Config.cavaBgBlend = b
                            }
                        }
                    }
                }
            }
        }

        Flow {
            visible: Config.cavaBg && !view.gradMatch
            Layout.fillWidth: true
            spacing: Tokens.spacingSm
            ChipRow {
                visible: Config.cavaBlendClean(Config.cavaBgBlend).length > 1
                accent: Colors.of(QsWindow.window).primary
                model: Config.cavaBgStyle === "ring"
                    ? [{ value: "across", label: "Round the ring" }, { value: "up", label: "Circle to tips" }]
                    : [{ value: "across", label: "Left to right" }, { value: "up", label: "Base to tips" }]
                current: Config.cavaBgBlendDir === "up" ? "up" : "across"
                onPicked: function(v) { Config.cavaBgBlendDir = v }
            }
            ChipButton {
                label:  Translation.tr("Whole scheme")
                symbol: "auto_awesome"
                tint:   Colors.of(QsWindow.window).primary
                onActivated: {
                    Config.cavaBgBlend = Config.cavaBgWholeScheme
                    Config.cavaBgBlendDir = "across"
                }
            }
        }

        Fader {
            visible: Config.cavaBg
            label:  Translation.tr("Opacity")
            accent: Colors.of(QsWindow.window).primary
            from: 0.2; to: 1.0; step: 0.05
            value:   Config.cavaBgOpacity
            readout: Math.round(Config.cavaBgOpacity * 100) + "%"
            onCommit: function(v) { Config.cavaBgOpacity = v }
        }
    }
}
