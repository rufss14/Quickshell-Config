pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette
import "../../../services/gradient.js" as Grad

// ── SchemeWorn ────────────────────────────────────────────────────────────────
// The colour scheme page's loud card: the palette you are BUILDING, worn. A miniature of the island itself
// (its rail with the chosen page's shape, a card with a title and a line, a button, a switch, a slider, the
// second accent as the shape behind) painted in the palette's own colours, so a colour is judged where it
// will be used and not as a swatch. It follows the picker live.
//
// Over it: what the shell is wearing right now (or what the editor holds, once it differs), the line that
// says why, and the light / dark pair. Under it, four tools: rebuild from the wallpaper, hold the colours
// against wallpaper changes, bind them to this wallpaper, the apply log. An app that needs a restart takes the
// line's place with the two answers.
// ─────────────────────────────────────────────────────────────────────────────
Rectangle {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)
    readonly property color ink: root.palette.fgOnPrimaryContainer
    readonly property color inkDim: root.palette.alpha(root.ink, 0.72)

    // The editor's palette, drawn as it will be worn (Simple's seeds or Advanced's slots); on the Album view, the
    // cover's (worn, or what it would give).
    readonly property var cover: AlbumScheme.coverPalette
    readonly property bool coverMode: root.panel.view === "album" && root.cover !== null && root.cover !== undefined
    readonly property var pal: root.coverMode ? root.cover : root.panel.pending
    readonly property real ratio: Palette.contrast(Palette.slotValue(root.pal, "background"), Palette.slotValue(root.pal, "foreground"))
    readonly property string grade: Palette.contrastGrade(root.ratio)
    readonly property color bg:      Palette.slotValue(root.pal, "background")
    readonly property color fg:      Palette.slotValue(root.pal, "foreground")
    readonly property color accent:  Palette.slotValue(root.pal, "color1")
    readonly property color second:  Palette.slotValue(root.pal, "color4")

    readonly property bool restart: ColorScheme.runner.needsRestart && !ColorScheme.busy
    readonly property bool editing: root.panel.editorDiffers && !root.coverMode

    // What the shell is wearing, by name; "Preview" and the loaded name once the editor has moved on.
    readonly property string wornName: AlbumScheme.active ? Translation.tr("Album cover")
        : ColorScheme.worn !== "" ? ColorScheme.worn
        : ColorScheme.wearingWallpaper ? Translation.tr("Wallpaper")
        : Translation.tr("Custom")
    readonly property string title: root.coverMode ? (AlbumScheme.player?.trackTitle || root.wornName)
        : root.editing
        ? (ColorScheme.loadedName !== "" ? ColorScheme.loadedName : Translation.tr("New palette"))
        : root.wornName

    radius: Tokens.radiusXl
    color: root.palette.primaryContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.spacingLg
        spacing: Tokens.spacingXs

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingSm

            StyledText {
                Layout.fillWidth: true
                text: (root.coverMode ? (AlbumScheme.active ? Translation.tr("Wearing the cover") : Translation.tr("Cover preview"))
                       : root.editing ? Translation.tr("Preview") : Translation.tr("Wearing")).toUpperCase()
                variant: "caption"
                font.weight: Font.Bold
                font.letterSpacing: 1
                color: root.inkDim
            }
            BusyDot { running: root.panel.applyingQuiet; tint: root.ink }

            // Light or dark: the shell's own mode (Settings flips the same one). Off while wallpaper theming is
            // off (nothing would change) or a run is going.
            Item {
                id: mode
                readonly property bool light: Config.themeMode === "light"
                readonly property bool usable: Config.wallTheming && !Wallpaper.applying && !ColorScheme.busy
                implicitWidth: Tokens.iconXl * 2 + Tokens.spacingXs * 3
                implicitHeight: Tokens.iconXl + Tokens.spacingXs * 2
                opacity: mode.usable ? 1 : 0.45

                SpringValue { id: modeK; target: mode.light ? 0 : 1; spec: Motion.springSpatial; epsilon: 0.002 }
                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: root.palette.alpha(root.ink, 0.12)
                }
                Rectangle {
                    x: Tokens.spacingXs + modeK.value * (Tokens.iconXl + Tokens.spacingXs)
                    y: Tokens.spacingXs
                    width: Tokens.iconXl
                    height: Tokens.iconXl
                    radius: width / 2
                    color: root.palette.primary
                }
                Row {
                    x: Tokens.spacingXs
                    y: Tokens.spacingXs
                    spacing: Tokens.spacingXs
                    Repeater {
                        model: ["light_mode", "dark_mode"]
                        delegate: Item {
                            id: seg
                            required property string modelData
                            required property int index
                            readonly property bool on: mode.light === (seg.index === 0)
                            width: Tokens.iconXl
                            height: Tokens.iconXl
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: seg.modelData
                                fill: seg.on ? 1 : 0
                                font.pixelSize: Tokens.iconMd
                                color: seg.on ? root.palette.fgOnPrimary : root.inkDim
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                                Behavior on fill  { NumberAnimation { duration: Motion.standard } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: mode.usable
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ColorScheme.switchMode(seg.index === 0 ? "light" : "dark")
                                Accessible.role: Accessible.RadioButton
                                Accessible.name: seg.index === 0 ? Translation.tr("Light") : Translation.tr("Dark")
                                Accessible.checked: seg.on
                                Accessible.onPressAction: ColorScheme.switchMode(seg.index === 0 ? "light" : "dark")
                            }
                        }
                    }
                }
                HoverTip {
                    text: Config.wallTheming ? Translation.tr("Light or dark") : Translation.tr("Turn wallpaper theming on to switch")
                    below: true
                    alignEnd: true
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.title
            variant: "headline"
            font.weight: Font.DemiBold
            color: root.ink
            elide: Text.ElideRight
        }

        // The line under the name, or, when an app is waiting for a restart, the two answers.
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.preferredHeight: Tokens.fontCaption * 2 + Tokens.spacingXs * 3
            Layout.minimumHeight: Layout.preferredHeight

            StyledText {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                visible: !root.restart
                text: root.panel.headerLine
                variant: "caption"
                color: root.inkDim
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }
            Rectangle {
                anchors.fill: parent
                visible: root.restart
                radius: height / 2
                color: root.palette.alpha(root.palette.warning, 0.22)
                StyledText {
                    anchors.left: parent.left
                    anchors.leftMargin: Tokens.spacingMd
                    anchors.right: restartBtn.left
                    anchors.rightMargin: Tokens.spacingSm
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.panel.restartNote
                    variant: "caption"
                    font.weight: Font.DemiBold
                    color: root.ink
                    elide: Text.ElideRight
                }
                Rectangle {
                    id: restartBtn
                    anchors.right: laterBtn.left
                    anchors.rightMargin: Tokens.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: restartLabel.implicitWidth + Tokens.spacingLg * 2
                    height: parent.height - Tokens.spacingSm
                    radius: height / 2
                    color: root.palette.warning
                    StyledText {
                        id: restartLabel
                        anchors.centerIn: parent
                        text: Translation.tr("Restart")
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: Palette.readableOn(root.palette.warning)
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ColorScheme.runner.restartAll()
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Restart")
                        Accessible.onPressAction: ColorScheme.runner.restartAll()
                    }
                }
                Item {
                    id: laterBtn
                    anchors.right: parent.right
                    anchors.rightMargin: Tokens.spacingXs
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.height - Tokens.spacingSm
                    height: width
                    MaterialIcon {
                        anchors.centerIn: parent
                        name: "close"
                        font.pixelSize: Tokens.iconSm
                        color: root.ink
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ColorScheme.runner.dismissRestart()
                        Accessible.role: Accessible.Button
                        Accessible.name: Translation.tr("Leave them")
                        Accessible.onPressAction: ColorScheme.runner.dismissRestart()
                    }
                }
            }
        }

        // ── The island, worn ──────────────────────────────────────────────────
        ClippingRectangle {
            id: mock
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacingXs
            radius: Tokens.radiusCard
            color: root.bg
            Behavior on color { enabled: !root.panel.rippleOn; ColorAnimation { duration: Motion.track } }

            // The gradient the bar and islands wear, when there is one: the miniature's ground becomes it.
            readonly property var gradDoc: Grad.clean(Config.barGradient)
            GradientFill {
                anchors.fill: parent
                visible: mock.gradDoc.on
                angle: mock.gradDoc.angle
                mid: mock.gradDoc.mid
                colors: Grad.colours(mock.gradDoc, n => String(root.palette.role(n, root.palette.primary)), String(root.bg))
            }

            // The second accent, as the big shape behind (a sun in light, a cookie in dark).
            MorphShape {
                width: Math.min(mock.width, mock.height) * 1.05
                height: width
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.rightMargin: -width * 0.34
                anchors.bottomMargin: -width * 0.36
                shape: Config.themeMode === "light" ? "sunny" : "cookie9"
                fillColor: root.second
            }

            // The rail: one pill, its chosen page in the accent.
            Rectangle {
                id: rail
                x: Tokens.spacingMd
                y: Tokens.spacingMd
                width: Tokens.iconLg + Tokens.spacingMd
                height: parent.height - Tokens.spacingMd * 2
                radius: width / 2
                color: root.palette.alpha(root.fg, 0.1)
                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Tokens.spacingSm
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: 3
                        delegate: MorphShape {
                            required property int index
                            width: rail.width - Tokens.spacingSm * 2
                            height: width
                            shape: index === 0 ? "clover" : "circle"
                            fillColor: index === 0 ? root.accent : root.palette.alpha(root.fg, 0.28)
                        }
                    }
                }
            }

            ColumnLayout {
                anchors.left: rail.right
                anchors.leftMargin: Tokens.spacingMd
                anchors.right: parent.right
                anchors.rightMargin: Tokens.spacingMd
                anchors.top: parent.top
                anchors.topMargin: Tokens.spacingMd
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Tokens.spacingMd
                spacing: Tokens.spacingSm

                StyledText {
                    text: "Aa"
                    font.pixelSize: Tokens.fontDisplay
                    font.weight: Font.Bold
                    color: root.fg
                }
                Rectangle {
                    Layout.preferredWidth: parent.width * 0.62
                    implicitHeight: Tokens.spacingSm
                    radius: height / 2
                    color: root.palette.alpha(root.fg, 0.6)
                }
                Rectangle {
                    Layout.preferredWidth: parent.width * 0.4
                    implicitHeight: Tokens.spacingSm
                    radius: height / 2
                    color: root.palette.alpha(root.fg, 0.32)
                }
                Item { Layout.fillHeight: true }
                // A switch, on, and the button.
                Row {
                    Layout.fillWidth: false
                    spacing: Tokens.spacingSm
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Tokens.iconXl + Tokens.spacingSm
                        height: Tokens.iconLg
                        radius: height / 2
                        color: root.accent
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width - width - Tokens.spacingXs - 1
                            width: parent.height - Tokens.spacingSm
                            height: width
                            radius: width / 2
                            color: root.bg
                        }
                    }
                    Rectangle {
                        width: tag.implicitWidth + Tokens.spacingLg * 2
                        height: Tokens.iconXl
                        radius: height / 2
                        color: root.accent
                        StyledText {
                            id: tag
                            anchors.centerIn: parent
                            text: Translation.tr("Accent")
                            variant: "label"
                            font.weight: Font.DemiBold
                            color: Palette.readableOn(root.accent)
                        }
                    }
                }
            }

            // Text on background, graded, as the palette reads it: a pill in the palette's own text colour.
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Tokens.spacingMd
                width: grade.implicitWidth + Tokens.spacingMd * 2
                height: Tokens.iconLg
                radius: height / 2
                color: root.grade === "Low" ? root.palette.warning : root.palette.alpha(root.fg, 0.14)
                Behavior on color { ColorAnimation { duration: Motion.respond } }
                PulseOnce { id: gradePulse; target: parent; peak: 1.12 }
                Connections {
                    target: root
                    function onGradeChanged() { gradePulse.fire() }
                }
                StyledText {
                    id: grade
                    anchors.centerIn: parent
                    text: root.grade + " " + root.ratio.toFixed(1)
                    variant: "micro"
                    font.weight: Font.DemiBold
                    font.features: ({ tnum: 1 })
                    color: root.grade === "Low" ? Palette.readableOn(root.palette.warning) : root.fg
                }
            }
        }

        // ── The tools ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false
            Layout.topMargin: Tokens.spacingXs
            spacing: Tokens.spacingXs

            // Held, in words: while it is, the colours stay through wallpaper changes; while it is not, the next
            // wallpaper repaints the shell. A press holds what is showing, or lets go. It is the page's lock, so it
            // is a labelled pill and not an icon among icons.
            Rectangle {
                id: hold
                readonly property bool held: ColorScheme.locked
                Layout.fillWidth: true
                Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXs
                radius: height / 2
                color: hold.held ? root.palette.primary : root.palette.alpha(root.ink, 0.12)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
                opacity: ColorScheme.busy ? 0.45 : 1
                SpringValue {
                    id: holdLean
                    target: holdTap.pressed ? 0.95 : holdHover.hovered ? 1.03 : 1
                    spec: Motion.springSpatialFast
                    epsilon: 0.001
                }
                scale: holdLean.value
                readonly property color fg: hold.held ? root.palette.fgOnPrimary : root.ink
                Row {
                    anchors.centerIn: parent
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: hold.held ? "lock" : "lock_open"
                        fill: hold.held ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: hold.fg
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: hold.held ? Translation.tr("Colours held") : Translation.tr("Follows wallpaper")
                        variant: "caption"
                        font.weight: Font.DemiBold
                        color: hold.fg
                    }
                }
                HoverHandler { id: holdHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    id: holdTap
                    anchors.fill: parent
                    enabled: !ColorScheme.busy
                    onClicked: ColorScheme.toggleLock()
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Hold the colours")
                    Accessible.checkable: true
                    Accessible.checked: hold.held
                    Accessible.onPressAction: ColorScheme.toggleLock()
                }
                HoverTip {
                    text: hold.held ? Translation.tr("Held: wallpaper changes leave these colours alone. Press to follow the wallpaper again")
                                    : Translation.tr("Press to hold these colours through wallpaper changes")
                }
            }
            Item { Layout.preferredWidth: Tokens.spacingSm }
            // Rebuild from the wallpaper (or, while the album drives the shell, re-read the cover).
            LitTool {
                Layout.alignment: Qt.AlignHCenter
                symbol: "refresh"
                ink: root.ink
                tip: root.panel.albumDriving ? Translation.tr("Read the cover again") : Translation.tr("Rebuild from the wallpaper")
                tipBelow: false
                enabled: root.panel.albumDriving ? !AlbumScheme.extracting : (!ColorScheme.busy && !ColorScheme.settled)
                opacity: enabled ? 1 : 0.4
                rotation: root.panel.regenSpin ? root.panel._regenPhase : 0
                onActivated: root.panel.doRegen()
            }
            // This wallpaper's own palette: bind the editor's, update it, or let it go back to the native one.
            LitTool {
                Layout.alignment: Qt.AlignHCenter
                readonly property bool bound: root.panel.wpHasPalette
                readonly property bool update: bound && root.panel.editorDiffers
                symbol: "wallpaper"
                lit: bound
                ink: root.ink
                tip: update ? Translation.tr("Update this wallpaper's palette")
                    : bound ? Translation.tr("Use the native colours for this wallpaper")
                    : root.panel.sceneOnScreen ? Translation.tr("Bind this palette to this scene")
                    : Translation.tr("Bind this palette to this wallpaper")
                enabled: !ColorScheme.busy && root.panel.paletteKey !== ""
                opacity: enabled ? 1 : 0.4
                onActivated: {
                    if (bound && !update) ColorScheme.clearWallpaperPalette(root.panel.paletteKey, root.panel.sceneOnScreen)
                    else ColorScheme.saveWallpaperPalette(root.panel.paletteKey, root.panel.pending, root.panel.sceneOnScreen)
                    bump()
                }
            }
            // The apply log: shown while a run goes, instead of a quiet note. Developers' tool.
            LitTool {
                Layout.alignment: Qt.AlignHCenter
                symbol: "terminal"
                lit: Config.colorApplyDebug
                ink: root.ink
                tip: Translation.tr("Show the apply log while it runs")
                onActivated: Config.colorApplyDebug = !Config.colorApplyDebug
            }
        }
    }
}
