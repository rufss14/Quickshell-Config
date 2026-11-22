pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"

// ── WallpaperNow ──────────────────────────────────────────────────────────────
// What is on screen, as the island page's hero: the wallpaper itself at 16:9, the shape of the
// screen it is on, with everything about it riding on the picture:
//
//   top-left      "ON SCREEN", and what it is (its aspect and format, or the scene's kind)
//   top-right     the six colours it gave the shell, while it themes it
//   foot, left    its name, and where the colours come from
//   foot, right   what you can do to it: restart the apps that need it, undo, stop a scene, shuffle
//
// The foot stands on a scrim in the surface's own tone, so the name reads over any picture in a
// light scheme and a dark one. A click anywhere else finds it in the gallery.
//
// While the Material tab is open the card previews the Material Wallpaper instead (the page beside it has no
// preview of its own on an island), labelled PREVIEW until it is applied, and a part being chosen there dims the rest.
//
// The bar's panel draws the same facts as a strip (WallpaperPanel's `hero`); what they ARE is the
// panel's (`heroName`, `heroSource`, `heroKind`…), so the two cannot disagree.
// ─────────────────────────────────────────────────────────────────────────────
ClippingRectangle {
    id: now

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int pad: Tokens.spacingMd
    readonly property color pill: now.palette.alpha(now.palette.surface, 0.86)
    // The Material tab is open: its preview is the picture, whatever is on screen.
    readonly property bool previewing: now.panel.isMaterial
    readonly property string name: now.previewing ? Translation.tr("Material Wallpaper") : now.panel.heroName

    radius: Tokens.radiusXl
    color: now.palette.section

    // The picture's own aspect, from the loaded thumbnail (sourceSize keeps the ratio).
    readonly property string aspect: {
        const w = shot.implicitWidth, h = shot.implicitHeight
        if (!(w > 1) || !(h > 1)) return ""
        const r = w / h
        const known = [[16, 9], [16, 10], [21, 9], [4, 3], [3, 2], [1, 1], [9, 16], [9, 21], [3, 4], [2, 3]]
        for (let i = 0; i < known.length; i++)
            if (Math.abs(r - known[i][0] / known[i][1]) < 0.03) return known[i][0] + ":" + known[i][1]
        return r.toFixed(2)
    }
    readonly property string kind: {
        const p = now.panel, bits = []
        if (now.previewing) {
            if (Config.wallMaterial) bits.push(Translation.tr("Live"))
        } else if (p.gamePaused) {
            if (p.heroSceneId !== "") bits.push(p.heroKind)
        } else if (p.sceneOnScreen && p.heroKind !== "") {
            bits.push(p.heroKind)
        } else if (p.materialOnScreen) {
            bits.push(Translation.tr("Live"))
        } else if (!p.sceneOnScreen) {
            if (now.aspect !== "") bits.push(now.aspect)
            const ext = p.heroName.indexOf(".") !== -1 ? p.heroName.split(".").pop().toUpperCase() : ""
            if (ext !== "") bits.push(ext)
        }
        return bits.join("  ·  ")
    }

    // ── The picture ───────────────────────────────────────────────────────────
    // `shot` shows the current one; `before` holds the one it replaced underneath until the new one
    // has loaded, so a change dissolves instead of blinking through the empty card.
    readonly property string src: now.panel.bust(now.panel.heroSource)
    onSrcChanged: {
        before.source = shot.source
        before.opacity = 1
        shot.source = now.src
    }
    Component.onCompleted: shot.source = now.src

    Image {
        id: before
        visible: !now.previewing && !now.sceneWait
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        cache: true
        sourceSize.width: 640
        opacity: 0
        Behavior on opacity { NumberAnimation { duration: Motion.spatial } }
    }
    Image {
        id: shot
        visible: !now.previewing && !now.sceneWait
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize.width: 640
        opacity: (String(source) !== "" && status === Image.Ready) ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        onStatusChanged: if (status === Image.Ready) before.opacity = 0
    }
    // A scene's preview that is a GIF plays, over its first frame (`shot` holds that until the
    // animation has loaded). A JPEG preview has nothing to play. Not while a game has paused it.
    AnimatedImage {
        id: anim
        readonly property bool wanted: !now.previewing && now.panel.sceneOnScreen && !now.panel.gamePaused
            && String(now.panel.heroSource).toLowerCase().endsWith(".gif")
        anchors.fill: parent
        visible: !now.sceneWait
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: anim.wanted ? now.src : ""
        playing: anim.wanted && status === Image.Ready && Motion.ambientOn
        opacity: status === Image.Ready ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
    }
    // A video scene plays its own file here, muted and looping, over the GIF (which stays as the first
    // frame and as the answer where qt6-multimedia is missing). The GIF is a few seconds at low quality;
    // the file is what the desktop is playing. The file comes from the scene's project.json, read only
    // while the scene is on screen. Not under reduced motion, not while a game has the scene paused.
    readonly property string sceneDir: (now.panel.sceneOnScreen && !now.panel.gamePaused && !now.previewing)
        ? String(now.panel.heroSource).replace(/^file:\/\//, "").replace(/\/[^\/]*$/, "") : ""
    property string videoFile: ""
    // The scene the project.json last read belongs to: the read is over once it names the one on screen.
    property string projFor: ""
    readonly property string videoPath: now.videoFile !== "" && now.projFor === now.sceneDir
        ? now.sceneDir + "/" + now.videoFile : ""
    readonly property bool projRead: now.sceneDir !== "" && now.projFor === now.sceneDir
    readonly property bool expectVideo: now.videoPath !== "" && Media.available && Motion.ambientOn
    // The picture is not shown until it is the right one. A scene's GIF is a few seconds of a poor copy: seen
    // first and then swapped for the video it read as a bad preview loading into the good one. So while the
    // answer is on its way (the project file, then the first frame of the video) there is a loading mark
    // instead, and the video fades in alone. A video that never comes (it errors, or 12 s pass) gives the
    // GIF its turn rather than waiting for good.
    property bool waitGaveUp: false
    readonly property bool sceneWait: now.sceneDir !== "" && !now.waitGaveUp
        && (!now.projRead || (now.expectVideo && !(clip.item && clip.item.showing) && !(clip.item && clip.item.error !== "")))
    onSceneDirChanged: now.waitGaveUp = false
    Timer { interval: 12000; running: now.sceneWait; onTriggered: now.waitGaveUp = true }
    FileView {
        id: projFile
        path: now.sceneDir !== "" ? now.sceneDir + "/project.json" : ""
        printErrors: false
        onLoaded: {
            now.videoFile = ""
            try {
                const j = JSON.parse(projFile.text())
                const f = String(j.file || "")
                if (String(j.type || "").toLowerCase() === "video" && /\.(mp4|webm|mkv|mov|avi)$/i.test(f) && f.indexOf("/") === -1)
                    now.videoFile = f
            } catch (e) {}
            now.projFor = now.sceneDir
        }
        onLoadFailed: { now.videoFile = ""; now.projFor = now.sceneDir }
    }
    Loader {
        id: clip
        anchors.fill: parent
        active: now.videoPath !== "" && Media.available && Motion.ambientOn
        source: Media.playerUrl
        opacity: clip.item && clip.item.showing ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.spatial; easing.type: Motion.travel } }
        onLoaded: {
            clip.item.crop = true
            clip.item.muted = true
            clip.item.autoplay = true
            clip.item.loopAll = true
            clip.item.source = now.videoPath
        }
    }
    onVideoPathChanged: if (clip.item) clip.item.source = now.videoPath

    Loader {
        anchors.fill: parent
        active: now.panel.materialOnScreen || now.previewing
        sourceComponent: MaterialWallpaper { highlightSlot: now.panel.materialSlot }
    }
    // Nothing to show (no preview, a paused scene): a shape in the card's own tone.
    Item {
        anchors.centerIn: parent
        width: Tokens.iconXl * 2
        height: width
        visible: (shot.opacity < 0.05 && before.opacity < 0.05 && !now.panel.materialOnScreen && !now.previewing
                  && !(clip.item && clip.item.showing)) || now.sceneWait
        MorphShape {
            id: mark
            anchors.fill: parent
            shape: now.panel.gamePaused ? "hexagon" : "cookie9"
            fillColor: now.palette.primaryContainer
            // Loading: the cookie turns, the way the gallery's cards' does, instead of its idle breathing.
            turns: !now.sceneWait
            NumberAnimation on rotation {
                from: 0; to: 360
                duration: Motion.spin * 6
                loops: Animation.Infinite
                running: now.sceneWait && Config.motionEnabled
            }
        }
        MaterialIcon {
            anchors.centerIn: parent
            name: now.panel.gamePaused ? "gamepad" : now.panel.sceneOnScreen ? "movie" : "wallpaper"
            fill: 1
            font.pixelSize: Tokens.iconXl
            color: now.palette.fgOnPrimaryContainer
        }
    }
    // Paused for a game: the scene's preview, dimmed, with a pad on it.
    Rectangle {
        anchors.fill: parent
        visible: now.panel.gamePaused && now.panel.heroSceneId !== "" && !now.previewing
        color: now.palette.alpha(now.palette.base, 0.6)
        MaterialIcon {
            anchors.centerIn: parent
            name: "gamepad"
            fill: 1
            font.pixelSize: Tokens.iconXl
            color: now.palette.primary
        }
    }

    // The foot's ground: the surface's tone, coming up from the bottom edge.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.round(parent.height * 0.6)
        gradient: Gradient {
            GradientStop { position: 0.0; color: now.palette.alpha(now.palette.surface, 0) }
            GradientStop { position: 0.55; color: now.palette.alpha(now.palette.surface, 0.72) }
            GradientStop { position: 1.0; color: now.palette.alpha(now.palette.surface, 0.94) }
        }
    }

    HoverHandler { id: hover }
    StateLayer {
        id: feel
        anchors.fill: parent
        radius: now.radius
        hovered: hover.hovered
        layerColor: now.panel.accent
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: function (m) { feel.press(m.x, m.y) }
        onReleased: feel.release()
        onCanceled: feel.release()
        onClicked: now.panel.revealCurrent()
        Accessible.role: Accessible.Button
        Accessible.name: Translation.tr("Find it in the gallery")
        Accessible.onPressAction: now.panel.revealCurrent()
    }

    // ── Top-left: on screen, and what it is ───────────────────────────────────
    Row {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: now.pad
        spacing: Tokens.spacingXs

        Rectangle {
            width: onLabel.implicitWidth + Tokens.spacingMd * 2
            height: Tokens.iconLg + Tokens.spacingSm
            radius: height / 2
            color: now.palette.primary
            StyledText {
                id: onLabel
                anchors.centerIn: parent
                text: (now.previewing && !Config.wallMaterial ? Translation.tr("Preview") : Translation.tr("On screen")).toUpperCase()
                variant: "micro"
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: now.palette.fgOnPrimary
            }
        }
        Rectangle {
            visible: now.kind !== ""
            width: kindLabel.implicitWidth + Tokens.spacingMd * 2
            height: Tokens.iconLg + Tokens.spacingSm
            radius: height / 2
            color: now.pill
            StyledText {
                id: kindLabel
                anchors.centerIn: parent
                text: now.kind
                variant: "micro"
                font.weight: Font.DemiBold
            }
        }
    }

    // ── Top-right: the colours it gave the shell ──────────────────────────────
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: now.pad
        visible: Config.wallTheming
        width: dots.width + Tokens.spacingSm * 2
        height: Tokens.iconLg + Tokens.spacingSm
        radius: height / 2
        color: now.pill

        Row {
            id: dots
            anchors.centerIn: parent
            spacing: -Tokens.spacingXs
            Repeater {
                model: [1, 2, 3, 4, 5, 6]
                delegate: Rectangle {
                    id: dot
                    required property int index
                    required property int modelData
                    width: Tokens.iconMd
                    height: width
                    radius: width / 2
                    color: now.palette.ansi(dot.modelData)
                    border.width: Tokens.borderWidth
                    border.color: now.palette.surface
                    Behavior on color { ColorAnimation { duration: Motion.standard } }
                    // A colour that changes under it (a new wallpaper) bumps, one dot after another.
                    SpringValue { id: bump; target: 1; spec: Motion.springSpatialFast; epsilon: 0.002 }
                    scale: bump.value
                    onColorChanged: if (Config.motionEnabled) { bump.jump(1.35); bump.target = 1 }
                }
            }
        }
    }

    // ── The foot: its name, where the colours come from, what you can do ──────
    Column {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.right: actions.left
        anchors.margins: now.pad
        anchors.rightMargin: Tokens.spacingSm
        spacing: 0

        StyledText {
            id: title
            width: parent.width
            text: now.name
            variant: "title"
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle

            // A new wallpaper's name rises into place.
            property real rise: 0
            transform: Translate { y: title.rise }
            onTextChanged: if (Config.motionEnabled) { title.opacity = 0; title.rise = Tokens.spacingMd; titleIn.restart() }
            ParallelAnimation {
                id: titleIn
                NumberAnimation { target: title; property: "opacity"; to: 1; duration: Motion.spatial; easing.type: Motion.travel }
                NumberAnimation { target: title; property: "rise"; to: 0; duration: Motion.spatial; easing.type: Motion.travel }
            }
        }
        Row {
            width: parent.width
            spacing: Tokens.spacingXs
            MaterialIcon {
                id: themeIcon
                anchors.verticalCenter: parent.verticalCenter
                name: now.previewing ? "wallpaper"
                    : !Config.wallTheming ? "format_paint" : AlbumScheme.active ? "music_note" : "palette"
                fill: (!now.previewing && Config.wallTheming && AlbumScheme.active) ? 1 : 0
                font.pixelSize: Tokens.iconSm
                color: now.previewing || !Config.wallTheming ? now.palette.fgDim : now.panel.accent
            }
            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - themeIcon.width - Tokens.spacingXs
                text: now.previewing
                    ? (Config.wallMaterial ? Translation.tr("On your desktop")
                                           : Translation.tr("Your desktop shows %1").arg(now.panel.heroName !== "" ? now.panel.heroName : Translation.tr("your wallpaper")))
                    : now.panel.heroThemeSource
                      + (Config.wallTheming ? "  ·  " + (Config.themeMode === "light" ? Translation.tr("Light") : Translation.tr("Dark")) : "")
                variant: "caption"
                emphasis: "muted"
                elide: Text.ElideRight
            }
        }
    }

    ChipTray {
        id: actions
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: now.pad

        // Not consumed by the card's own click.
        ChipButton {
            visible: !now.panel.isMaterial && Wallpaper.needsRestart && !now.panel.applyBusy && !now.panel.pickingActive
            symbol: "restart_alt"
            on: true
            tint: now.palette.warning
            onActivated: Wallpaper.restartAll()
            HoverTip { text: Translation.tr("Restart the apps that need it") }
        }
        ChipButton {
            visible: !now.panel.isMaterial && now.panel.pickingActive
            symbol: "close"
            label: Translation.tr("Cancel")
            tint: now.panel.accent
            onActivated: { now.panel.pickingForScreen = ""; now.panel.pickingScreens = [] }
        }
        ChipButton {
            visible: Wallpaper.canUndo && !now.panel.applyBusy && !now.panel.pickingActive
            symbol: "undo"
            tint: now.panel.accent
            onActivated: Wallpaper.undo()
            HoverTip { text: Translation.tr("Back to %1").arg(Wallpaper.previousName) }
        }
        ChipButton {
            visible: now.panel.sceneOnScreen && WallpaperEngine.needsRefresh
            symbol: "refresh"
            on: true
            tint: now.panel.accent
            onActivated: WallpaperEngine.refresh()
            HoverTip { text: Translation.tr("Apply the changed options") }
        }
        ChipButton {
            visible: !now.panel.isMaterial && !now.panel.pickingActive && now.panel.sceneOnScreen
            symbol: "stop"
            label: Translation.tr("Stop")
            tint: now.panel.accent
            enabled: !WallpaperEngine.busy
            onActivated: WallpaperEngine.stop()
            HoverTip { text: Translation.tr("Stop the scene") }
        }
        ChipButton {
            visible: !now.panel.isMaterial && !now.panel.sceneOnScreen && Wallpaper.wallpapers.length > 1
            symbol: "shuffle"
            label: Translation.tr("Shuffle")
            tint: now.panel.accent
            enabled: !Wallpaper.applying
            onActivated: Wallpaper.shuffleNow(true)
            HoverTip { text: Config.wallShuffleFavs ? Translation.tr("Shuffle now (starred)") : Translation.tr("Shuffle now") }
        }
    }
}
