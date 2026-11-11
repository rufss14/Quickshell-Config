import QtQuick
import QtQuick.Layouts
import Quickshell
import "../config"
import "../services"
import "../services/wallfx.js" as FX

// One sound of the wallpaper's music effects: a dot that lights when it's heard, and a Fader for its
// trim (auto = what the song gives it; 0 is off, up to twice as strong; an opt-in sound like Strobe goes
// 0..1 and starts off). Shared by Settings' Effects tab and the Wallpaper panel's Effects view, so the
// two can't drift. `sound` is one entry of FX.SOUNDS (services/wallfx.js).
ColumnLayout {
    id: row
    required property var sound

    readonly property bool optIn: row.sound.optIn === true
    readonly property real trim: FX.trimOf(Config.wallFxMix, row.sound.id)
    // How loud this sound is right now, for its dot.
    readonly property real heard: !MusicPulse.live ? 0
        : ({ kick: MusicPulse.kick,
             // a kick whose bass is big (the rumble's rule, wallfx.js HEAVY_FROM)
             bass: MusicPulse.heavy < 0 || MusicPulse.heavy >= 0.65 ? MusicPulse.kick : 0,
             snare: MusicPulse.snare,
             hats: MusicPulse.hat, vocals: MusicPulse.mid, loudness: MusicPulse.level,
             hardest: MusicPulse.impact, breakdown: MusicPulse.songView.breakdown,
             strobe: MusicPulse.flash })[row.sound.id] ?? 0
    readonly property color tone: row.sound.warning === true
        ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).primary

    Layout.fillWidth: true
    Layout.fillHeight: false
    spacing: Tokens.spacingXs

    // Flashing light: said before the control, not after.
    StyledText {
        Layout.fillWidth: true
        Layout.preferredWidth: 0
        visible: row.sound.warning === true
        text: Translation.tr("Flashing light. Leave Strobe off if you're sensitive to it (photosensitive epilepsy). It flashes three times a second at most.")
        variant: "caption"
        color: Colors.of(QsWindow.window).danger
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingMd
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Tokens.spacingMd
            implicitHeight: Tokens.spacingMd
            radius: width / 2
            color: row.trim > 0 && row.heard > 0.05 ? row.tone : Colors.of(QsWindow.window).outline
            opacity: row.trim > 0 && row.heard > 0.05 ? 0.35 + 0.65 * Math.min(1, row.heard) : 1
        }
        Fader {
            Layout.fillWidth: true
            accent: row.tone
            label: row.sound.label + " · " + row.sound.effect
            help: row.sound.about
            from: 0; to: row.optIn ? 1 : 2; step: 0.05
            value: row.trim
            readout: row.trim <= 0 ? "off"
                   : !row.optIn && Math.abs(row.trim - 1) < 0.001 ? "auto"
                   : Math.round(row.trim * 100) + "%"
            // Auto is no entry at all (and Strobe's off), so Auto follows the song and a reset is
            // one assignment.
            onCommit: function (v) {
                const e = Object.assign({}, Config.wallFxMix)
                const auto = row.optIn ? v <= 0 : Math.abs(v - 1) < 0.001
                if (auto) delete e[row.sound.id]
                else e[row.sound.id] = v
                Config.wallFxMix = e
            }
        }
    }
}
