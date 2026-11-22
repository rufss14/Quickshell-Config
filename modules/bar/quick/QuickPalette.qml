import QtQuick
import "../../../config"
import "../../../components"
import "../../../services"

// ── QuickPalette ──────────────────────────────────────────────────────────────
// The colour scheme pill's card: light or dark, back to the wallpaper's own colours, and a few schemes to
// wear. Wearing one is the panel's own `ColorScheme.wear` (it holds through wallpaper changes). The
// schemes are the user's saved ones once the library has been listed (opening the panel does that), the
// shell's classic ones before.
// ─────────────────────────────────────────────────────────────────────────────
QuickFrame {
    id: root

    readonly property var schemes: (ColorScheme.presetsReady && ColorScheme.presets.length > 0
                                    ? ColorScheme.presets : ColorScheme.classics).slice(0, 3)

    symbol: "palette"
    shape: "cookie6"
    title: Translation.tr("Colour scheme")
    value: ColorScheme.wearingWallpaper ? Translation.tr("Wallpaper colours")
         : ColorScheme.worn !== "" ? ColorScheme.worn : Translation.tr("Edited scheme")

    trailing: ChipButton {
        symbol: Config.themeMode === "dark" ? "dark_mode" : "light_mode"
        tint: root.palette.primary
        solid: true
        enabled: !ColorScheme.busy
        onActivated: ColorScheme.switchMode(Config.themeMode === "dark" ? "light" : "dark")
    }

    OptionCard {
        width: parent.width
        symbol: "wallpaper"
        label: Translation.tr("Wallpaper colours")
        detail: Translation.tr("Follows each new wallpaper")
        shape: "cookie9"
        on: ColorScheme.wearingWallpaper
        enabled: !ColorScheme.busy
        onActivated: ColorScheme.useWallpaper()
    }

    Repeater {
        model: root.schemes
        OptionCard {
            required property var modelData
            width: parent.width
            symbol: "palette"
            label: modelData.name
            shape: "clover"
            on: ColorScheme.worn === modelData.name
            enabled: !ColorScheme.busy
            onActivated: ColorScheme.wear(modelData)
        }
    }

    ChipButton {
        symbol: "palette"
        label: Translation.tr("All schemes")
        tint: root.palette.primary
        onActivated: root.openPanel("colorScheme")
    }
}
