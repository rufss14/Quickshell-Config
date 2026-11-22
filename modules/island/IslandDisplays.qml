pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../config"
import "../../components"
import "../../services"
import "../../services/displays.js" as D

// ── IslandDisplays ────────────────────────────────────────────────────────────
// The screens on an island (2026-11-15, one of the user's new pages; the right island, after Network):
//
//   left    the loud card: the night light (how warm, as a big number in kelvin, its switch, the warmth as the
//           media page's thick slider, and when it comes on: by hand, sunset to sunrise, or your hours), with
//           the reason in place of the switch when hyprsunset is missing (NightLight.blocker)
//   right   every screen drawn to scale where it stands; the chosen one's refresh rates and scales as chips,
//           Apply, and the keep-or-revert countdown after (services/Displays: a mode the screen cannot show
//           reverts itself); under them the anti-flashbang (dims a sudden bright screen) and its night-only option
//
// Applying writes the bundled hardware.lua (Displays.apply); with your own Hyprland config the button copies the
// lines instead, as Settings › Displays does. Everything real is the services'.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property int sideW: Tokens.spacingXl * 14 + Tokens.spacingSm

    // ── The screens being edited ──────────────────────────────────────────────
    property var edited: []
    property string selected: ""
    readonly property var sel: root.edited.find(m => m.name === root.selected) ?? null
    readonly property bool dirty: Displays.loaded && D.changed(Displays.monitors, root.edited)
    function reset() {
        root.edited = Displays.monitors.map(m => Object.assign({}, m))
        if (!root.edited.some(m => m.name === root.selected))
            root.selected = root.edited.length > 0 ? root.edited[0].name : ""
    }
    function patch(name, fields) {
        root.edited = root.edited.map(m => m.name === name ? Object.assign({}, m, fields) : m)
    }
    Component.onCompleted: { Displays.refresh(); root.reset() }
    Connections {
        target: Displays
        function onMonitorsChanged() { if (!Displays.pending) root.reset() }
    }
    // The refresh rates the chosen screen offers at its current size, highest first.
    readonly property var rates: {
        if (!root.sel) return []
        const out = []
        for (const m of root.sel.modes || [])
            if (m.width === root.sel.width && m.height === root.sel.height && out.indexOf(Math.round(m.refresh)) < 0) out.push(Math.round(m.refresh))
        return out.sort((a, b) => b - a).slice(0, 5)
    }
    // The layout's box, to draw the screens to scale.
    readonly property var box: {
        let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9
        for (const m of root.edited) {
            const w = m.width / (m.scale || 1), h = m.height / (m.scale || 1)
            x0 = Math.min(x0, m.x); y0 = Math.min(y0, m.y); x1 = Math.max(x1, m.x + w); y1 = Math.max(y1, m.y + h)
        }
        return root.edited.length ? { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) } : { x: 0, y: 0, w: 1, h: 1 }
    }

    RowLayout {
        anchors.fill: parent
        spacing: Tokens.spacingMd

        // ══ Night light, loud ═════════════════════════════════════════════════
        IslandPlate {
            id: hero
            Layout.fillWidth: false
            Layout.preferredWidth: root.sideW
            Layout.minimumWidth: root.sideW
            Layout.fillHeight: true
            hero: true
            order: 0
            radius: Tokens.radiusXl
            readonly property string why: NightLight.blocker()

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Tokens.spacingLg
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        filled: true
                        symbol: "bedtime"
                        shape: NightLight.running ? "sunny" : "circle"
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Night light")
                            variant: "title"
                            font.weight: Font.DemiBold
                            color: hero.ink
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: hero.why !== "" ? hero.why : NightLight.statusText
                            variant: "caption"
                            color: hero.inkDim
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                    }
                    Toggle {
                        visible: hero.why === ""
                        checked: Config.nightLight
                        accessibleName: Translation.tr("Night light")
                        onToggled: NightLight.toggle()
                    }
                }

                Item { Layout.fillHeight: true }

                StyledText {
                    text: Config.nightLightTemp + " K"
                    font.pixelSize: Tokens.fontDisplay * 2
                    font.weight: Font.Bold
                    font.features: ({ tnum: 1 })
                    color: hero.ink
                }
                StyledText {
                    text: Config.nightLightTemp <= 3200 ? Translation.tr("Very warm") : Config.nightLightTemp <= 4500 ? Translation.tr("Warm") : Translation.tr("A little warm")
                    variant: "caption"
                    color: hero.inkDim
                }
                // Warmer to the left, the way the light goes.
                ThickSlider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    enabled: hero.why === ""
                    maximum: Config.nightLightTempMax - Config.nightLightTempMin
                    value: Config.nightLightTemp - Config.nightLightTempMin
                    accessibleName: Translation.tr("Warmth")
                    onMoved: function (v) { Config.nightLightTemp = Math.round((Config.nightLightTempMin + v) / 100) * 100 }
                }

                Item { Layout.fillHeight: true }

                // When it comes on.
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    columns: 2
                    columnSpacing: Tokens.spacingXs
                    rowSpacing: Tokens.spacingXs
                    enabled: hero.why === ""
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: Translation.tr("By hand")
                        symbol: "power"
                        shape: "circle"
                        on: !Config.nightLightAuto
                        onActivated: Config.nightLightAuto = false
                    }
                    OptionCard {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        label: Config.nightLightFollowSun ? Translation.tr("At sunset") : Translation.tr("%1 to %2").arg(Config.nightLightFrom).arg(Config.nightLightTo)
                        symbol: "schedule"
                        shape: "sunny"
                        on: Config.nightLightAuto
                        onActivated: Config.nightLightAuto = true
                    }
                }
            }
        }

        // ══ Right ═════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Tokens.spacingMd

            // ── The screens ────────────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: true
                order: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        StyledText {
                            Layout.fillWidth: true
                            text: Displays.pending ? Translation.tr("Keep these settings? Reverting in %1 s").arg(Displays.secondsLeft)
                                : root.edited.length === 1 ? Translation.tr("1 screen") : Translation.tr("%1 screens").arg(root.edited.length)
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        ChipButton {
                            visible: Displays.pending
                            symbol: "undo"
                            label: Translation.tr("Revert")
                            tonal: true
                            onActivated: Displays.revert()
                        }
                        ChipButton {
                            visible: Displays.pending
                            symbol: "check"
                            label: Translation.tr("Keep")
                            solid: true
                            onActivated: Displays.keep()
                        }
                        ChipButton {
                            visible: !Displays.pending && root.dirty
                            symbol: "undo"
                            tonal: true
                            Accessible.name: Translation.tr("Undo edits")
                            onActivated: root.reset()
                        }
                        ChipButton {
                            visible: !Displays.pending
                            enabled: root.dirty && !Displays.busy
                            symbol: "check"
                            label: Displays.editable ? Translation.tr("Apply") : Translation.tr("Copy lines")
                            solid: true
                            onActivated: Displays.editable ? Displays.apply(root.edited) : Displays.copyLines(root.edited)
                        }
                    }

                    // The layout, to scale; press a screen to choose it.
                    Item {
                        id: stage
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        readonly property real k: Math.min(stage.width / root.box.w, stage.height / root.box.h) * 0.9
                        Repeater {
                            model: root.edited
                            delegate: Rectangle {
                                id: scr
                                required property var modelData
                                readonly property bool chosen: scr.modelData.name === root.selected
                                x: (stage.width - root.box.w * stage.k) / 2 + (scr.modelData.x - root.box.x) * stage.k
                                y: (stage.height - root.box.h * stage.k) / 2 + (scr.modelData.y - root.box.y) * stage.k
                                width: scr.modelData.width / (scr.modelData.scale || 1) * stage.k
                                height: scr.modelData.height / (scr.modelData.scale || 1) * stage.k
                                radius: Tokens.radiusCard
                                color: scr.chosen ? root.palette.primaryContainer : root.palette.plate
                                border.width: Tokens.borderWidth
                                border.color: scr.chosen ? root.palette.primary : root.palette.outline
                                Behavior on color { ColorAnimation { duration: Motion.standard } }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: scr.modelData.name
                                        variant: "title"
                                        font.weight: Font.Bold
                                        color: scr.chosen ? root.palette.fgOnPrimaryContainer : root.palette.fg
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Translation.tr("%1 × %2 · %3 Hz · %4×").arg(scr.modelData.width).arg(scr.modelData.height).arg(Math.round(scr.modelData.refresh)).arg(scr.modelData.scale)
                                        variant: "caption"
                                        color: scr.chosen ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.72) : root.palette.fgMuted
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: Math.min(implicitWidth, scr.width - Tokens.spacingLg)
                                        text: scr.modelData.desc
                                        variant: "micro"
                                        color: scr.chosen ? root.palette.alpha(root.palette.fgOnPrimaryContainer, 0.6) : root.palette.fgDim
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selected = scr.modelData.name
                                    Accessible.role: Accessible.Button
                                    Accessible.name: scr.modelData.name
                                }
                            }
                        }
                    }

                    // The chosen screen's rate and scale.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        visible: root.sel !== null && !Displays.pending
                        spacing: Tokens.spacingXs
                        StyledText { text: Translation.tr("Hz"); variant: "caption"; emphasis: "muted" }
                        Repeater {
                            model: root.rates
                            delegate: ChipButton {
                                required property int modelData
                                label: String(modelData)
                                labelVariant: "caption"
                                on: root.sel && Math.round(root.sel.refresh) === modelData
                                onActivated: {
                                    const mode = (root.sel.modes || []).find(m => m.width === root.sel.width && m.height === root.sel.height && Math.round(m.refresh) === modelData)
                                    if (mode) root.patch(root.selected, { refresh: mode.refresh })
                                }
                            }
                        }
                        Item { Layout.fillWidth: true }
                        StyledText { text: Translation.tr("Scale"); variant: "caption"; emphasis: "muted" }
                        Repeater {
                            model: [1, 1.25, 1.5, 2]
                            delegate: ChipButton {
                                required property real modelData
                                label: String(modelData)
                                labelVariant: "caption"
                                on: root.sel && Math.abs(root.sel.scale - modelData) < 0.01
                                onActivated: root.patch(root.selected, { scale: modelData })
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: Displays.lastError !== ""
                        text: Displays.lastError
                        variant: "caption"
                        color: root.palette.danger
                        elide: Text.ElideRight
                    }
                }
            }

            // ── Anti-flashbang ─────────────────────────────────────────────────
            IslandPlate {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: flashRow.implicitHeight + Tokens.spacingMd * 2
                order: 2

                RowLayout {
                    id: flashRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingMd
                    IslandBadge {
                        size: Tokens.iconXl
                        symbol: "brightness_6"
                        shape: AntiFlash.active ? "cookie9" : "circle"
                        filled: AntiFlash.active
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            text: Translation.tr("Anti-flashbang")
                            variant: "label"
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Dims a screen that suddenly goes bright")
                            variant: "caption"
                            emphasis: "muted"
                            elide: Text.ElideRight
                        }
                    }
                    ChipButton {
                        label: Translation.tr("At night only")
                        labelVariant: "caption"
                        on: Config.antiFlashNightOnly
                        enabled: Config.antiFlash
                        onActivated: Config.antiFlashNightOnly = !Config.antiFlashNightOnly
                    }
                    Toggle {
                        checked: Config.antiFlash
                        accessibleName: Translation.tr("Anti-flashbang")
                        onToggled: Config.antiFlash = !Config.antiFlash
                    }
                }
            }
        }
    }
}
