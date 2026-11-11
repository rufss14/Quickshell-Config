import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/wallfx.js" as FX

// The wallpaper moved by the music, at panel width (Settings' Effects tab has the same controls on a
// bigger page; the sound rows are the one shared component, WallFxSoundRow). Everything the effects
// need to run is said before the controls: they draw through the shell's own renderer, so they are
// disabled with a reason when that is off. Switches apply live, as there is nothing to restart.
Item {
    id: fx
    required property var panel

    // Why the controls below are dead, or "".
    readonly property string blocker: !Config.wallShellRender ? Translation.tr("Needs the shell to draw the wallpaper")
                                    : !Config.wallFx          ? Translation.tr("Turn on Music effects to use these")
                                    : ""

    Flickable {
        id: pane
        anchors.fill: parent
        contentWidth: width
        contentHeight: col.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            width: pane.width
            spacing: Tokens.spacingSm

            WallpaperOptionRow {
                label: Translation.tr("Music effects")
                detail: !Config.wallShellRender ? Translation.tr("Needs the shell to draw the wallpaper")
                      : Config.wallFx ? Translation.tr("The wallpaper moves with what's playing")
                      :                 Translation.tr("The wallpaper stays still")
                enabled: Config.wallShellRender
                checked: Config.wallFx
                onToggled: Config.wallFx = !Config.wallFx
            }
            WallpaperOptionRow {
                label: Translation.tr("Bars glow with the music")
                detail: Translation.tr("A thin outline on both bars' pills, as loud as the music")
                checked: Config.barMusicReact
                onToggled: Config.barMusicReact = !Config.barMusicReact
            }

            StyledText {
                Layout.fillWidth: true
                Layout.preferredWidth: 0
                visible: fx.blocker !== "" && Config.wallShellRender
                text: fx.blocker
                variant: "caption"
                emphasis: "dim"
                wrapMode: Text.WordWrap
            }

            Divider {}

            // Everything below is the effects' own tuning: dead while they are off.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                enabled: fx.blocker === ""
                opacity: enabled ? 1 : 0.5
                Behavior on opacity { NumberAnimation { duration: Motion.fast } }

                Fader {
                    accent: fx.panel.accent
                    label: Translation.tr("Intensity")
                    help: Translation.tr("How strong everything is at its biggest. The song does the rest: calm parts settle to a soft glow, big parts move, the drop hits hardest, and a busy part (sixteenth hi-hats) plays smaller.")
                    from: 0; to: 1; step: 0.05
                    value: Config.wallFxIntensity
                    readout: Math.round(Config.wallFxIntensity * 100) + "%"
                    onCommit: function (v) { Config.wallFxIntensity = v }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    visible: MusicPulse.probed && !MusicPulse.dspOk
                    text: Translation.tr("Install python-numpy to hear the drums apart and keep time with the beat.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
                Fader {
                    accent: fx.panel.accent
                    label: Translation.tr("Sync")
                    enabled: MusicPulse.dspOk    // the cava fallback has no clock to move
                    help: Translation.tr("The effects already wait for your speakers. If they still land before the beat you hear (Bluetooth adds more delay than it reports), hold them back further.")
                    from: 0; to: 300; step: 5
                    value: Config.wallFxSyncMs
                    readout: Config.wallFxSyncMs === 0 ? "as heard" : Config.wallFxSyncMs + " ms later"
                    onCommit: function (v) { Config.wallFxSyncMs = Math.round(v) }
                }

                Divider {}

                // The sound map: a row per sound, and what it moves.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        elide: Text.ElideRight
                        text: !MusicPulse.live ? Translation.tr("Each sound and what it moves")
                            : MusicPulse.character !== "" ? Translation.tr("This song: ") + MusicPulse.character
                            :                               Translation.tr("Getting to know this song…")
                        variant: "label"
                        emphasis: "dim"
                    }
                    PanelButton {
                        Layout.fillHeight: false
                        visible: Object.keys(Config.wallFxMix || {}).length > 0
                        variant: "ghost"
                        accent: fx.panel.accent
                        symbol: "refresh"
                        label: Translation.tr("Auto")
                        onActivated: Config.wallFxMix = ({})
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Translation.tr("The song decides how much each sound shows. Slide one to want more or less of it; Auto puts every sound back. Strobe is never on unless you turn it on.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: FX.SOUNDS
                    delegate: WallFxSoundRow {
                        required property var modelData
                        sound: modelData
                    }
                }
            }
        }
    }
    Scrollbar { flickable: pane }
}
