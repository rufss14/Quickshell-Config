import QtQuick
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"

// ── WallpaperSources ──────────────────────────────────────────────────────────
// Where the island page's gallery draws from: Images, Scenes (Wallpaper Engine) and Material (the shell's own
// drawn wallpaper), as the island's source rail (components/SourceRail). Each row says how much it holds in
// numerals as large as the Dashboard's clock; Material holds nothing to count, so its state stands there.
//
// A dot by a name that is not the one on show says its source is what is on SCREEN (a scene running while you
// browse images, Material switched on).
//
// `picked(value)` is the panel's own tab change (WallpaperPanel.pickSource), so the rail and the bar panel's
// SegmentSwitch cannot behave differently.
// ─────────────────────────────────────────────────────────────────────────────
SourceRail {
    id: root

    required property var panel

    current: root.panel.tab
    model: [
        { value: "images",   label: Translation.tr("Images"),   icon: "image",    shape: "cookie9",
          figure: String(Wallpaper.wallpapers.length),
          live: !root.panel.sceneOnScreen && !root.panel.materialOnScreen && !root.panel.gamePaused },
        { value: "engine",   label: Translation.tr("Scenes"),   icon: "movie",    shape: "clover",
          figure: String(WallpaperEngine.items.length),
          live: root.panel.sceneOnScreen },
        { value: "material", label: Translation.tr("Material"), icon: "category", shape: "sunny",
          figure: Config.wallMaterial ? Translation.tr("On") : Translation.tr("Off"), big: false,
          live: root.panel.materialOnScreen }
    ]
}
