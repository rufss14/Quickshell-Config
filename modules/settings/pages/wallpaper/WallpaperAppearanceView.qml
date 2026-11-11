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

// WallpaperAppearanceView — part of WallpaperPage.qml, moved into its own file (2026-11-08). Reads and writes the
// page's state through `page` (was `root`).
// ── APPEARANCE ──────────────────────────────────────────────────
// A BentoGrid of the settings app's cards: switches are tiles that light up,
// a group of sliders is a card, and the grid fills its rows (see BentoGrid).
Flickable {
    id: appFlick
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page
    anchors.fill: parent
    contentWidth: width
    contentHeight: appGrid.implicitHeight - appGrid.topTrim
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: page.view === "appearance"

    opacity: page.view === "appearance" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Motion.standard } }

    // Theming (theme from wallpaper, light/dark) and Album colours live in
    // Appearance › Theme — they decide the palette, and the palette had
    // three homes. The hero's "colours frozen" note reads Config.wallTheming;
    // it's status, not a control.
    BentoGrid {
        id: appGrid
        y: -appGrid.topTrim
        width: appFlick.width - Tokens.scrollRoom   // clear of the Scrollbar
        bentoCols: page.colsFor(appFlick.width)
        columnSpacing: Tokens.spacingLg
        rowSpacing: Tokens.spacingLg

        Section {
            glyph: "󰐬"
            title: Translation.tr("Drawn by")
            subtitle: Translation.tr("Static images only.")
            padding: Tokens.spacingMd

            ChipRow {
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: true,  label: "The shell",  glyph: "󰐬" },
                    { value: false, label: "awww daemon", glyph: "󰸉" }
                ]
                current: Config.wallShellRender
                onPicked: function(v) { Config.wallShellRender = v }
            }
        }

        QuickToggleTile {
            roomy: true
            symbol: "category"
            label:  Translation.tr("Material Wallpaper")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallMaterial
            available: Wallpaper.materialBlocker() === "" || Config.wallMaterial
            subLabel: Wallpaper.materialBlocker() !== "" && !Config.wallMaterial ? Wallpaper.materialBlocker()
                    : Config.wallMaterial ? "Style it in the bar's Wallpaper panel › Material"
                    :                       "The picture is shown"
            onToggled: if (Config.wallMaterial) Config.wallMaterial = false
                       else                     Wallpaper.applyMaterial()
        }

        QuickToggleTile {
            roomy: true
            symbol: "layers"
            label:  Translation.tr("Parallax")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallParallax
            available: Config.wallShellRender
            subLabel: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                    : Config.wallParallax ? "The picture moves a little with the pointer"
                    :                       "The picture stays still"
            onToggled: Config.wallParallax = !Config.wallParallax
        }

        QuickToggleTile {
            roomy: true
            symbol: "view_quilt"
            label:  Translation.tr("Follow workspace")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallParallaxWorkspace
            available: Config.wallShellRender && Config.wallParallax
            subLabel: !Config.wallParallax ? "Needs parallax on"
                    : Config.wallParallaxWorkspace ? "Switching workspace slides the picture"
                    :                                "Only the pointer moves it"
            onToggled: Config.wallParallaxWorkspace = !Config.wallParallaxWorkspace
        }

        Section {
            glyph: "󰐬"
            title: Translation.tr("Parallax strength")
            padding: Tokens.spacingMd
            enabled: Config.wallShellRender && Config.wallParallax
            opacity: enabled ? 1 : 0.5

            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Zoom")
                from: 1.0; to: 1.5; step: 0.05
                value: Config.wallParallaxZoom
                readout: Config.wallParallaxZoom.toFixed(2) + "×"
                onCommit: function(v) { Config.wallParallaxZoom = v }
            }
            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Pointer")
                from: 0; to: 0.4; step: 0.02
                value: Config.wallParallaxMouse
                readout: Config.wallParallaxMouse <= 0 ? "off"
                    : Math.round(Config.wallParallaxMouse * 100) + "%"
                onCommit: function(v) { Config.wallParallaxMouse = v }
            }
        }

        QuickToggleTile {
            roomy: true
            symbol: "schedule"
            label:  Translation.tr("Depth clock")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallDepth
            // Off and not set up: the tile is the way to set up, so it stays pressable
            // unless that can't work (no uv) or is already running.
            available: Config.wallShellRender
                && (Config.wallDepth || WallpaperDepth.ready
                    || (WallpaperDepth.checked && WallpaperDepth.hasUv && !WallpaperDepth.installing))
            subLabel: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                    : WallpaperDepth.installing ? WallpaperDepth.installNote
                    : WallpaperDepth.installNote !== "" ? WallpaperDepth.installNote
                    : WallpaperDepth.blocker() !== "" ? WallpaperDepth.blocker()
                    : Config.wallDepth ? "The time sits behind whatever stands in front of it"
                    :                    "The time is not drawn on the picture"
            onToggled: if (Config.wallDepth)          Config.wallDepth = false
                       else if (WallpaperDepth.ready) Config.wallDepth = true
                       else                           WallpaperDepth.install()
        }

        // ── The depth clock's own controls ────────────────────────────────
        // Only while it is on. The preview is the real thing in miniature: drag the clock
        // and the mask is measured again at the new spot.
        Section {
            span: 3
            symbol: "schedule"
            title: Translation.tr("Depth clock")
            subtitle: page.depthPath === "" ? "No still wallpaper to show"
                    : Config.wallDepthPlaces[page.depthPath] !== undefined ? "Placed by you"
                    : "Placed automatically"
            padding: Tokens.spacingMd
            visible: Config.wallDepth
            actions: [
                PanelButton {
                    capsule: true
                    variant: "ghost"
                    label: Translation.tr("Auto")
                    visible: Config.wallDepthPlaces[page.depthPath] !== undefined
                    onActivated: WallpaperDepth.unplace(page.depthPath)
                }
            ]

            DepthPlacer {
                Layout.fillWidth: true
                Layout.maximumWidth: 560
                Layout.alignment: Qt.AlignHCenter
                path: page.depthPath
                aspect: page.depthAspect
            }

            ChipRow {
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "tl",  label: "Top left" },
                    { value: "t",   label: "Top" },
                    { value: "tr",  label: "Top right" },
                    { value: "b",   label: "Bottom" }
                ]
                current: page.depthPreset
                onPicked: function(v) {
                    const at = page.depthSpots[v]
                    if (page.depthPath !== "") WallpaperDepth.place(page.depthPath, at[0], at[1])
                }
            }

            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Size")
                from: 0.6; to: 1.4; step: 0.05
                value: Config.wallDepthScale
                readout: Math.round(Config.wallDepthScale * 100) + "%"
                onCommit: function(v) { Config.wallDepthScale = v }
            }
            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Depth")
                help: Translation.tr("How far the clock stays behind when the picture moves, so it slides behind the subject. Needs parallax on.")
                enabled: Config.wallShellRender && Config.wallParallax
                from: 0; to: 1; step: 0.05
                value: Config.wallDepthDepth
                readout: Config.wallDepthDepth <= 0 ? "rides the picture" : Math.round(Config.wallDepthDepth * 100) + "%"
                onCommit: function(v) { Config.wallDepthDepth = v }
            }
            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Edge softness")
                help: Translation.tr("Blurs the edge where the subject covers the clock, so the pixels of the cut-out don't show.")
                from: 0; to: 3; step: 0.1
                value: Config.wallDepthSoft
                readout: Config.wallDepthSoft <= 0 ? "sharp" : Config.wallDepthSoft.toFixed(1) + " px"
                onCommit: function(v) { Config.wallDepthSoft = v }
            }
            ChipRow {
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "auto",    label: "Auto contrast" },
                    { value: "primary", label: "Accent" },
                    { value: "text",    label: "Palette text" }
                ]
                current: Config.wallDepthInk
                onPicked: function(v) { Config.wallDepthInk = v }
            }
        }

        QuickToggleTile {
            roomy: true
            symbol: "today"
            label:  Translation.tr("Date")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallDepthDate
            visible: Config.wallDepth
            subLabel: Config.wallDepthDate ? "Under the time" : "The time alone"
            onToggled: Config.wallDepthDate = !Config.wallDepthDate
        }

        QuickToggleTile {
            roomy: true
            symbol: "update"
            label:  Translation.tr("12-hour")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallDepthHour12
            visible: Config.wallDepth
            subLabel: Config.wallDepthHour12 ? "3:07" : "15:07"
            onToggled: Config.wallDepthHour12 = !Config.wallDepthHour12
        }

        QuickToggleTile {
            roomy: true
            symbol: "deployed_code"
            label:  Translation.tr("Prepare the library")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallDepthPrepare
            visible: Config.wallDepth
            subLabel: !Config.wallDepthPrepare ? "Analyse a wallpaper when it is picked"
                    : WallpaperDepth.preparing ? "Analysing in the background: " + WallpaperDepth.bgDone + " of " + WallpaperDepth.bgTotal
                    :                            "Every wallpaper is ready"
            onToggled: Config.wallDepthPrepare = !Config.wallDepthPrepare
        }

        QuickToggleTile {
            roomy: true
            symbol: "shuffle"
            label:  Translation.tr("Shuffle")
            accent: Colors.of(QsWindow.window).primary
            active: Config.wallShuffle
            subLabel: Config.wallShuffle
                ? "A random image every " + Config.wallShuffleMins + " min"
                : "The wallpaper only changes when you pick one"
            onToggled: Config.wallShuffle = !Config.wallShuffle
        }

        Section {
            glyph: "󰒝"
            title: Translation.tr("Shuffle timer")
            padding: Tokens.spacingMd

            Fader {
                accent: Colors.of(QsWindow.window).primary
                label: Translation.tr("Every")
                from: Config.wallShuffleMinsMin
                to:   Config.wallShuffleMinsMax
                value: Config.wallShuffleMins
                readout: Config.wallShuffleMins + " min"
                enabled: Config.wallShuffle
                onCommit: function(v) { Config.wallShuffleMins = v }
            }
            PanelButton {
                capsule: true
                label: Translation.tr("Surprise me")
                glyph: "󰒝"
                variant: "ghost"
                enabled: !Wallpaper.applying && Wallpaper.wallpapers.length > 1
                onActivated: Wallpaper.shuffleNow(true)
            }
        }

        Section {
            span: 3
            glyph: "󰍹"
            title: Translation.tr("Apply images to")
            subtitle: Translation.tr("Scenes always cover every screen.")
            padding: Tokens.spacingMd
            visible: Quickshell.screens.length > 1

            ChipRow {
                accent: Colors.of(QsWindow.window).primary
                model: [{ value: "", label: "All" }].concat(
                    Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
                current: Config.wallTarget
                onPicked: function(v) { Config.wallTarget = v }
            }
        }

        // ── A wallpaper per workspace ─────────────────────────────
        // Picking a workspace here sends you to the Gallery, where the next
        // wallpaper you click becomes that workspace's own.
        WallpaperWorkspaces {
            span: 3
            picking: page.pickingWs
            onPick: function (n) {
                page.pickingForScreen = ""
                page.pickingScreens = []
                page.pickingWs = n
                page.view = "gallery"
            }
        }
    }
}
