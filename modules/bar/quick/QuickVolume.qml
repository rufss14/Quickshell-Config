import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickVolume ───────────────────────────────────────────────────────────────
// The volume pill's card: the level on a fader, mute, and the output devices to switch between. All of it
// is the Audio service (`setVolume`, `toggleMute`, `setDefaultSink`); the same calls as the mixer panel.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var outputs: Audio.sinks.slice(0, 3)

    symbol: Audio.muted ? "volume_off" : "volume_up"
    shape: "sunny"
    title: Translation.tr("Volume")
    value: Audio.muted ? Translation.tr("Muted") : Math.round(Audio.volume * 100) + "%"

    trailing: ChipButton {
        symbol: Audio.muted ? "volume_off" : "volume_up"
        tint: root.palette.primary
        solid: true
        on: Audio.muted
        onActivated: Audio.toggleMute()
    }

    ValueSlider {
        width: parent.width
        expressive: true
        thickness: Tokens.spacingXl
        value: Audio.volume * 100
        maximum: 100
        accent: Audio.muted ? root.palette.fgMuted : root.palette.primary
        accessibleName: Translation.tr("Output volume")
        onMoved: function (v) { Audio.setVolume(v / 100) }
        onScrolled: function (d) { Audio.setVolume(Audio.steppedLevel(Audio.volume, d > 0)) }
    }

    Repeater {
        model: root.outputs
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: /headphone|headset|bluez/i.test(modelData.name || "") ? "headphones" : "speaker"
            label: Audio.shortLabelFor(modelData)
            shape: "cookie9"
            on: Audio.sink === modelData
            onActivated: Audio.setDefaultSink(modelData)
        }
    }
}
