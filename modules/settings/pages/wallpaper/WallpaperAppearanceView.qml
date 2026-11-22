pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../../config"
import "../../../../components"
import "../../../../services"
import "../.."

// ── WallpaperAppearanceView — Wallpaper › Placement & motion ──────────────────
// The rail page `WallpaperPage.qml#placement`: what the picture does on the desktop.
// Grouped rows (docs/settings-style.md §1.6) in balanced columns under one hero: the
// wallpaper as it is on the desktop now (WallpaperNowCard). Reads and writes the page's
// state through `page` (WallpaperPage.qml's root), which shows this while
// `page.view === "placement"`.
//
// Theming (theme from wallpaper, light/dark) and Album colours live in Look & feel ›
// Theme: they decide the palette. The gallery hero's colour line reads Config.wallTheming;
// it's status, not a control.
SettingsPage {
    id: view
    // The page that owns the state (WallpaperPage.qml's root).
    required property var page

    anchors.fill: parent
    // Disabled while hidden: SettingsPage.reveal() answers only an enabled page, so a hidden
    // view never consumes a search hit meant for the one on show. Turning on reveals it.
    enabled: page.view === "placement"
    onEnabledChanged: if (view.enabled) view.reveal()
    opacity: page.view === "placement" ? 1 : 0
    visible: opacity > 0.01
    Behavior on opacity {
        enabled: view.page.viewMotion
        NumberAnimation { duration: Motion.standard; easing.type: Motion.travel }
    }

    // Room for the two named segments of "Drawn by".
    readonly property int choiceWidth: Tokens.fieldHeight * 9

    grouped:     true
    headerShape: "clover"
    glyph:       "󰸉"
    title:       Translation.tr("Wallpaper")
    titleTail:   Translation.tr("Placement & motion")
    accent:      Colors.of(QsWindow.window).primary
    subtitle: {
        const bits = [Config.wallShellRender ? Translation.tr("Drawn by the shell") : Translation.tr("Drawn by awww")]
        if (Config.wallShellRender && Config.wallParallax) bits.push(Translation.tr("Parallax"))
        if (Config.wallShuffle) bits.push(Translation.tr("Shuffles every %1 min").arg(Config.wallShuffleMins))
        if (Wallpaper.perWorkspace) bits.push(Translation.tr("%1 workspaces of their own").arg(Wallpaper.marked.length))
        return bits.join(" · ")
    }

    // The depth clock's switch: off and not set up, it is the way to set up.
    function toggleDepth() {
        if (Config.wallDepth)          Config.wallDepth = false
        else if (WallpaperDepth.ready) Config.wallDepth = true
        else                           WallpaperDepth.install()
    }

    // ══ What is on the desktop ════════════════════════════════════════════════
    // The live subject, full width above the columns of options that change it.
    WallpaperNowCard { page: view.page }

    // ══ The picture ═══════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "wallpaper"
        title:   Translation.tr("Picture")
        subtitle: Config.wallMaterial ? Translation.tr("Material") : ""

        SettingRow {
            label:  Translation.tr("Drawn by")
            detail: Translation.tr("Static images only.")

            TabStrip {
                connected: true
                // A SettingRow's control slot is a plain Item: size by implicitWidth.
                implicitWidth: view.choiceWidth
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: true,  label: "The shell",   icon: "wallpaper" },
                    { value: false, label: "awww daemon", icon: "image" }
                ]
                current: Config.wallShellRender
                onPicked: function (v) { Config.wallShellRender = v }
            }
        }

        SettingRow {
            rowTap: true
            enabled: Wallpaper.materialBlocker() === "" || Config.wallMaterial
            opacity: enabled ? 1 : 0.4
            label:  Translation.tr("Material wallpaper")
            detail: Wallpaper.materialBlocker() !== "" && !Config.wallMaterial ? Wallpaper.materialBlocker()
                  : Config.wallMaterial ? "Style it in the bar's Wallpaper panel › Material"
                  :                       "The picture is shown"
            onTapped: if (Config.wallMaterial) Config.wallMaterial = false
                      else                     Wallpaper.applyMaterial()

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallMaterial
                onToggled: if (Config.wallMaterial) Config.wallMaterial = false
                           else                     Wallpaper.applyMaterial()
            }
        }
    }

    // ══ Depth clock ═══════════════════════════════════════════════════════════
    // The switch, then (only while it is on) the clock's own controls. The preview is the
    // real thing in miniature: drag the clock and the mask is measured again at the new spot.
    Section {
        grouped: true
        symbol:  "schedule"
        title:   Translation.tr("Depth clock")
        subtitle: !Config.wallDepth ? ""
                : view.page.depthPath === "" ? "No still wallpaper to show"
                : Config.wallDepthPlaces[view.page.depthPath] !== undefined ? "Placed by you"
                : "Placed automatically"
        actions: [
            PanelButton {
                capsule: true
                variant: "ghost"
                label: Translation.tr("Auto")
                visible: Config.wallDepth && Config.wallDepthPlaces[view.page.depthPath] !== undefined
                onActivated: WallpaperDepth.unplace(view.page.depthPath)
            }
        ]

        SettingRow {
            rowTap: true
            // Off and not set up: the row is the way to set up, so it stays pressable
            // unless that can't work (no uv) or is already running.
            enabled: Config.wallShellRender
                && (Config.wallDepth || WallpaperDepth.ready
                    || (WallpaperDepth.checked && WallpaperDepth.hasUv && !WallpaperDepth.installing))
            opacity: enabled ? 1 : 0.4
            label:  Translation.tr("Depth clock")
            detail: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                  : WallpaperDepth.installing ? WallpaperDepth.installNote
                  : WallpaperDepth.installNote !== "" ? WallpaperDepth.installNote
                  : WallpaperDepth.blocker() !== "" ? WallpaperDepth.blocker()
                  : Config.wallDepth ? "The time sits behind whatever stands in front of it"
                  :                    "The time is not drawn on the picture"
            onTapped: view.toggleDepth()

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallDepth
                onToggled: view.toggleDepth()
            }
        }

        DepthPlacer {
            visible: Config.wallDepth
            Layout.fillWidth: true
            Layout.maximumWidth: 560
            Layout.alignment: Qt.AlignHCenter
            path: view.page.depthPath
            aspect: view.page.depthAspect
        }

        // Four spots, or none (a hand-placed clock): a ChipRow, which can show no choice.
        ColumnLayout {
            visible: Config.wallDepth
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            SettingRow { label: Translation.tr("Place") }
            ChipRow {
                Layout.fillHeight: false
                accent: Colors.of(QsWindow.window).primary
                model: [
                    { value: "tl",  label: "Top left" },
                    { value: "t",   label: "Top" },
                    { value: "tr",  label: "Top right" },
                    { value: "b",   label: "Bottom" }
                ]
                current: view.page.depthPreset
                onPicked: function(v) {
                    const at = view.page.depthSpots[v]
                    if (view.page.depthPath !== "") WallpaperDepth.place(view.page.depthPath, at[0], at[1])
                }
            }
        }

        Fader {
            visible: Config.wallDepth
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Size")
            from: 0.6; to: 1.4; step: 0.05
            value: Config.wallDepthScale
            readout: Math.round(Config.wallDepthScale * 100) + "%"
            onCommit: function(v) { Config.wallDepthScale = v }
        }
        Fader {
            visible: Config.wallDepth
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Depth")
            help: Translation.tr("How far the clock stays behind when the picture moves, so it slides behind the subject. Needs parallax on.")
            enabled: Config.wallShellRender && Config.wallParallax
            opacity: enabled ? 1 : 0.4
            from: 0; to: 1; step: 0.05
            value: Config.wallDepthDepth
            readout: Config.wallDepthDepth <= 0 ? "rides the picture" : Math.round(Config.wallDepthDepth * 100) + "%"
            onCommit: function(v) { Config.wallDepthDepth = v }
        }
        Fader {
            visible: Config.wallDepth
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Edge softness")
            help: Translation.tr("Blurs the edge where the subject covers the clock, so the pixels of the cut-out don't show.")
            from: 0; to: 3; step: 0.1
            value: Config.wallDepthSoft
            readout: Config.wallDepthSoft <= 0 ? "sharp" : Config.wallDepthSoft.toFixed(1) + " px"
            onCommit: function(v) { Config.wallDepthSoft = v }
        }

        SettingRow {
            visible: Config.wallDepth
            label: Translation.tr("Colour")

            TabStrip {
                connected: true
                implicitWidth: view.choiceWidth + Tokens.fieldHeight * 4
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

        SettingRow {
            rowTap: true
            visible: Config.wallDepth
            label:  Translation.tr("Date")
            detail: Config.wallDepthDate ? "Under the time" : "The time alone"
            onTapped: Config.wallDepthDate = !Config.wallDepthDate

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallDepthDate
                onToggled: Config.wallDepthDate = !Config.wallDepthDate
            }
        }

        SettingRow {
            rowTap: true
            visible: Config.wallDepth
            label:  Translation.tr("12-hour")
            detail: Config.wallDepthHour12 ? "3:07" : "15:07"
            onTapped: Config.wallDepthHour12 = !Config.wallDepthHour12

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallDepthHour12
                onToggled: Config.wallDepthHour12 = !Config.wallDepthHour12
            }
        }

        SettingRow {
            rowTap: true
            visible: Config.wallDepth
            label:  Translation.tr("Prepare the library")
            detail: !Config.wallDepthPrepare ? "Analyse a wallpaper when it is picked"
                  : WallpaperDepth.preparing ? "Analysing in the background: " + WallpaperDepth.bgDone + " of " + WallpaperDepth.bgTotal
                  :                            "Every wallpaper is ready"
            onTapped: Config.wallDepthPrepare = !Config.wallDepthPrepare

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallDepthPrepare
                onToggled: Config.wallDepthPrepare = !Config.wallDepthPrepare
            }
        }
    }

    // ══ Parallax ══════════════════════════════════════════════════════════════
    Section {
        grouped: true
        symbol:  "layers"
        title:   Translation.tr("Parallax")
        subtitle: !Config.wallShellRender ? Translation.tr("Needs the shell") : ""

        SettingRow {
            rowTap: true
            enabled: Config.wallShellRender
            opacity: enabled ? 1 : 0.4
            label:  Translation.tr("Parallax")
            detail: !Config.wallShellRender ? "Needs the shell to draw the wallpaper"
                  : Config.wallParallax ? "The picture moves a little with the pointer"
                  :                       "The picture stays still"
            onTapped: Config.wallParallax = !Config.wallParallax

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallParallax
                onToggled: Config.wallParallax = !Config.wallParallax
            }
        }

        SettingRow {
            rowTap: true
            enabled: Config.wallShellRender && Config.wallParallax
            opacity: enabled ? 1 : 0.4
            label:  Translation.tr("Follow workspace")
            detail: !Config.wallParallax ? "Needs parallax on"
                  : Config.wallParallaxWorkspace ? "Switching workspace slides the picture"
                  :                                "Only the pointer moves it"
            onTapped: Config.wallParallaxWorkspace = !Config.wallParallaxWorkspace

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallParallaxWorkspace
                onToggled: Config.wallParallaxWorkspace = !Config.wallParallaxWorkspace
            }
        }

        Fader {
            enabled: Config.wallShellRender && Config.wallParallax
            opacity: enabled ? 1 : 0.4
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Zoom")
            from: 1.0; to: 1.5; step: 0.05
            value: Config.wallParallaxZoom
            readout: Config.wallParallaxZoom.toFixed(2) + "×"
            onCommit: function(v) { Config.wallParallaxZoom = v }
        }
        Fader {
            enabled: Config.wallShellRender && Config.wallParallax
            opacity: enabled ? 1 : 0.4
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Pointer")
            from: 0; to: 0.4; step: 0.02
            value: Config.wallParallaxMouse
            readout: Config.wallParallaxMouse <= 0 ? "off"
                : Math.round(Config.wallParallaxMouse * 100) + "%"
            onCommit: function(v) { Config.wallParallaxMouse = v }
        }
    }

    // ══ Shuffle ═══════════════════════════════════════════════════════════════
    // A shuffle right now is the gallery header's Shuffle button.
    Section {
        grouped: true
        symbol:  "shuffle"
        title:   Translation.tr("Shuffle")
        subtitle: Config.wallShuffle ? Translation.tr("Every %1 min").arg(Config.wallShuffleMins) : ""

        SettingRow {
            rowTap: true
            label:  Translation.tr("Shuffle")
            detail: Config.wallShuffle
                ? "A random image every " + Config.wallShuffleMins + " min"
                : "The wallpaper only changes when you pick one"
            onTapped: Config.wallShuffle = !Config.wallShuffle

            Toggle {
                accent:  Colors.of(QsWindow.window).primary
                checked: Config.wallShuffle
                onToggled: Config.wallShuffle = !Config.wallShuffle
            }
        }

        Fader {
            enabled: Config.wallShuffle
            opacity: enabled ? 1 : 0.4
            accent: Colors.of(QsWindow.window).primary
            label: Translation.tr("Every")
            from: Config.wallShuffleMinsMin
            to:   Config.wallShuffleMinsMax
            value: Config.wallShuffleMins
            readout: Config.wallShuffleMins + " min"
            onCommit: function(v) { Config.wallShuffleMins = v }
        }
    }

    // ══ Which screen ══════════════════════════════════════════════════════════
    Section {
        grouped: true
        visible: Quickshell.screens.length > 1
        symbol:  "monitor"
        title:   Translation.tr("Apply images to")
        help:    Translation.tr("Scenes always cover every screen.")
        subtitle: Config.wallTarget === "" ? Translation.tr("Every screen") : Config.wallTarget

        ChipRow {
            Layout.fillHeight: false
            accent: Colors.of(QsWindow.window).primary
            model: [{ value: "", label: "All" }].concat(
                Quickshell.screens.map(s => ({ value: s.name, label: s.name })))
            current: Config.wallTarget
            onPicked: function(v) { Config.wallTarget = v }
        }
    }

    // ══ A wallpaper per workspace ═════════════════════════════════════════════
    // Picking a workspace here goes to the Gallery through the settings shell; the next
    // wallpaper clicked there becomes that workspace's own, and the page comes back here
    // (WallpaperPage.beginPick / endPick).
    WallpaperWorkspaces {
        picking: view.page.pickingWs
        onPick: function (n) {
            view.page.dropPick()
            view.page.pickingWs = n
            view.page.beginPick("WallpaperPage.qml#placement")
        }
    }
}
