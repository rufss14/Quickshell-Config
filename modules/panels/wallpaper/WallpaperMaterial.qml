import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/materialwall.js" as MW

// The Material Wallpaper's page: one wallpaper, drawn live from the screen's own palette (the same
// component the desktop draws, so what is previewed is what applies), and every way to shape it on ONE
// scroll, in plates: what it is doing and the one action; Looks, each drawn as itself; Colour; Shapes;
// Motion. Nothing hides behind a tab, so the whole style is one glance away from being found.
//
// ── Where the preview is ──────────────────────────────────────────────────────
// On an island page it is the side column's hero (WallpaperNow draws the Material preview while this
// tab is open: the screen's 16:9, large, and always in view while you scroll the controls). On the bar's
// panel there is no side column, so the first plate holds the preview. Either way a part being chosen on
// the Shapes plate dims the rest of it (`panel.materialSlot`, set while the pointer is on that plate).
//
// Style changes are live on the desktop when it is applied and on the preview always; Apply is what puts
// it on screen, and takes the picture / scene off (Wallpaper.applyMaterial). The style is read as ONE
// object (`mat.style`, keyed like services/materialwall.js STYLE) so a look can be recognised and applied
// as a whole. Behind a Loader, so a panel opened for a picture never builds it.
Item {
    required property var panel

    id: mat

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property var style: {
        const o = ({})
        for (const k in MW.CONFIG_KEY) o[k] = Config[MW.CONFIG_KEY[k]]
        if (o.role === "primary") o.role = ""     // the same colour, said two ways
        return o
    }
    function applyStyle(s) {
        for (const k in MW.CONFIG_KEY) Config[MW.CONFIG_KEY[k]] = s[k]
    }
    // Which part of the picture the Shapes plate is choosing a form for.
    property string slot: "stack"

    Component.onDestruction: mat.panel.materialSlot = ""

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: mat.panel.island ? Tokens.spacingSm : 0
        contentWidth: width
        contentHeight: col.implicitHeight + Tokens.spacingLg
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Tokens.spacingSm

            // ══ What it is, and the one action ════════════════════════════════
            Rectangle {
                id: hero
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: heroCol.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusXl
                color: mat.palette.primaryContainer

                ColumnLayout {
                    id: heroCol
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingSm

                    // The bar's panel has no side column: the preview stands here, at the real screen's shape,
                    // so the composition is framed as it will be.
                    ClippingRectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Math.round(width / Math.max(1.2, Math.min(2.4,
                            (QsWindow.window?.screen?.width ?? 16) / Math.max(1, QsWindow.window?.screen?.height ?? 9))))
                        visible: !mat.panel.island
                        radius: Math.max(Tokens.radiusSm, Tokens.radiusXl - Tokens.spacingMd)
                        color: "transparent"

                        MaterialWallpaper {
                            anchors.fill: parent
                            highlightSlot: mat.panel.materialSlot
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd

                        Item {
                            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                            Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                            MorphShape {
                                anchors.fill: parent
                                shape: Config.wallMaterial ? "sunny" : "cookie9"
                                spec: Motion.springSpatialFast
                                fillColor: mat.palette.primary
                            }
                            MaterialIcon {
                                anchors.centerIn: parent
                                name: "category"
                                fill: 1
                                font.pixelSize: Tokens.iconLg
                                color: mat.palette.fgOnPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Material Wallpaper")
                                variant: "title"
                                font.weight: Font.DemiBold
                                color: mat.palette.fgOnPrimaryContainer
                                elide: Text.ElideRight
                            }
                            // What the picture is: edits show on the preview at once, the desktop changes only on Apply.
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                color: mat.palette.alpha(mat.palette.fgOnPrimaryContainer, 0.72)
                                text: !Config.wallMaterial && Wallpaper.materialBlocker() !== "" ? Wallpaper.materialBlocker()
                                    : Config.wallMaterial ? Translation.tr("Live on your desktop. Changes show there as you make them.")
                                    : Translation.tr("A preview. Your desktop still shows ")
                                      + (mat.panel.heroName !== "" ? mat.panel.heroName : Translation.tr("your wallpaper"))
                                      + Translation.tr(", and Apply replaces it.")
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        PanelButton {
                            Layout.fillWidth: true
                            variant: Config.wallMaterial ? "normal" : "primary"
                            accent: mat.panel.accent
                            symbol: Config.wallMaterial ? "close" : "check"
                            label: Config.wallMaterial ? Translation.tr("Turn off") : Translation.tr("Apply")
                            enabled: Config.wallMaterial || Wallpaper.materialBlocker() === ""
                            onActivated: {
                                if (Config.wallMaterial) Config.wallMaterial = false
                                else                     Wallpaper.applyMaterial()
                            }
                        }
                        // A different arrangement of the same shapes. (Not "Shuffle": that is the wallpaper timer.)
                        PanelButton {
                            variant: "normal"
                            accent: mat.panel.accent
                            symbol: "casino"
                            label: Translation.tr("Rearrange")
                            onActivated: Config.wallMaterialSeed = 1 + Math.floor(Math.random() * 1000000)
                        }
                    }
                }
            }

            // ══ Looks ═════════════════════════════════════════════════════════
            // Each is drawn as itself, on the arrangement in use. One sets the whole style; the one in force
            // wears the accent, and any tweak after it leaves none lit (it is then your own mix: save it
            // below). Yours come after the built-in ones, and a lock marks a look a colour scheme wears
            // (services/MaterialPresets).
            WallpaperMaterialPlate {
                title: Translation.tr("Looks")
                symbol: "auto_awesome"
                shape: "sunny"
                note: String(MaterialPresets.looks.length)

                Flow {
                    id: looks
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    Repeater {
                        model: MaterialPresets.looks
                        delegate: Item {
                            id: lk
                            required property var modelData
                            required property int index
                            readonly property bool on: MaterialPresets.currentKey === lk.modelData.key
                            readonly property var wornBy: MaterialPresets.schemesOf(lk.modelData.key)
                            readonly property var st: MaterialPresets.styleOf(lk.modelData.key) ?? MW.lookStyle("default", 0)
                            width: Math.floor((looks.width - looks.spacing * 2) / 3)
                            height: Math.round(lk.width * 9 / 16)

                            PopIn { id: pop; active: true; index: lk.index; cap: 6 }
                            opacity: pop.opacity

                            SpringValue {
                                id: lean
                                target: lkTap.pressed ? 0.95 : lkHover.hovered ? 1.03 : 1
                                spec: Motion.springSpatialFast
                                epsilon: 0.001
                            }
                            SpringValue { id: ringK; target: lk.on ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }
                            scale: lean.value * pop.scale

                            // The frame in force, the accent, and the thumbnail inset by its width.
                            Rectangle {
                                anchors.fill: parent
                                radius: Tokens.radiusSm + Tokens.spacingXs
                                color: mat.panel.accent
                                opacity: Math.max(0, Math.min(1, ringK.value))
                                visible: opacity > 0.005
                            }
                            ClippingRectangle {
                                id: thumb
                                anchors.fill: parent
                                anchors.margins: Math.max(0, ringK.value) * Tokens.spacingSm
                                radius: Math.max(Tokens.radiusSm, Tokens.radiusSm + Tokens.spacingXs - thumb.anchors.margins)
                                color: mat.palette.section

                                MaterialWallpaper {
                                    anchors.fill: parent
                                    running: false
                                    role: lk.st.role
                                    role2: lk.st.role2
                                    contrast: lk.st.contrast
                                    softness: lk.st.softness
                                    sizeScale: lk.st.size
                                    seed: lk.st.seed
                                    drift: false
                                    spin: 0
                                    backdrop: lk.st.backdrop
                                    mirror: lk.st.mirror
                                    forms: ({ stack: lk.st.stack, centre: lk.st.centre, side: lk.st.side, corner: lk.st.corner })
                                }
                                StateLayer {
                                    anchors.fill: parent
                                    radius: thumb.radius
                                    hovered: lkHover.hovered
                                    layerColor: mat.panel.accent
                                }

                                // Its name, on a pill, with the look's own icon.
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.margins: Tokens.spacingSm
                                    width: Math.min(lkName.implicitWidth + lkIcon.width + Tokens.spacingMd * 2 + Tokens.spacingXs,
                                                    thumb.width - Tokens.spacingSm * 2)
                                    height: Tokens.iconLg + Tokens.spacingXs
                                    radius: height / 2
                                    color: mat.palette.alpha(mat.palette.surface, 0.86)
                                    Row {
                                        anchors.centerIn: parent
                                        spacing: Tokens.spacingXs
                                        MaterialIcon {
                                            id: lkIcon
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: lk.modelData.icon
                                            fill: lk.on ? 1 : 0
                                            font.pixelSize: Tokens.iconSm
                                            color: lk.on ? mat.panel.accent : mat.palette.fgMuted
                                        }
                                        StyledText {
                                            id: lkName
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: Math.min(implicitWidth, thumb.width - lkIcon.width - Tokens.spacingMd * 4)
                                            text: lk.modelData.label
                                            variant: "micro"
                                            font.weight: lk.on ? Font.DemiBold : Font.Medium
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // Worn by a colour scheme.
                                Rectangle {
                                    visible: lk.wornBy.length > 0
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.spacingSm
                                    width: Tokens.iconLg + Tokens.spacingXs
                                    height: width
                                    radius: width / 2
                                    color: mat.palette.alpha(mat.palette.surface, 0.86)
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: "lock"
                                        fill: 1
                                        font.pixelSize: Tokens.iconSm
                                        color: mat.panel.accent
                                    }
                                }

                                // A saved look can go: one press arms it, the next removes it.
                                ArmLatch {
                                    id: lkDrop
                                    onConfirmed: MaterialPresets.remove(lk.modelData.key)
                                }
                                Rectangle {
                                    visible: !lk.modelData.builtIn && (lkHover.hovered || lkDrop.armed)
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.spacingSm
                                    width: Tokens.iconLg + Tokens.spacingXs
                                    height: width
                                    radius: width / 2
                                    color: lkDrop.armed ? mat.palette.danger : mat.palette.alpha(mat.palette.surface, 0.86)
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: "close"
                                        font.pixelSize: Tokens.iconSm
                                        color: lkDrop.armed ? mat.palette.fgOnPrimary : mat.palette.fg
                                    }
                                    TapHandler { onTapped: lkDrop.trigger() }
                                }
                            }

                            HoverHandler { id: lkHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: lkTap; onTapped: MaterialPresets.apply(lk.modelData.key) }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: lk.modelData.label
                            Accessible.checkable: true
                            Accessible.checked: lk.on
                            Accessible.onPressAction: MaterialPresets.apply(lk.modelData.key)
                        }
                    }
                }

                // ── Save the mix in use ───────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        id: lookName
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingXs
                        cornerRadius: implicitHeight / 2
                        placeholder: Translation.tr("Name this look")
                        onAccepted: function (v) { if (MaterialPresets.save(v) !== "") lookName.clear() }
                        onKeyPressed: function (e) {
                            if (e.key !== Qt.Key_Escape) return
                            lookName.blur()
                            e.accepted = true
                        }
                    }
                    PanelButton {
                        Layout.fillHeight: false
                        variant: "normal"
                        accent: mat.panel.accent
                        symbol: "save"
                        label: Translation.tr("Save")
                        onActivated: if (MaterialPresets.save(lookName.text) !== "") lookName.clear()
                    }
                }

                // ── The lock: this look and the colour scheme worn ────
                // Like the colours panel's lock, for the picture: link the look in use to the scheme the
                // shell wears, and applying that scheme loads it.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: linkRow.implicitHeight + Tokens.spacingSm * 2
                    radius: Tokens.radiusSm
                    color: MaterialPresets.linkedKey !== "" ? mat.palette.alpha(mat.panel.accent, 0.14) : mat.palette.section
                    Behavior on color { ColorAnimation { duration: Motion.respond } }

                    RowLayout {
                        id: linkRow
                        anchors.fill: parent
                        anchors.margins: Tokens.spacingSm
                        spacing: Tokens.spacingSm

                        MaterialIcon {
                            name: MaterialPresets.linkedKey !== "" ? "lock" : "lock_open"
                            fill: MaterialPresets.linkedKey !== "" ? 1 : 0
                            color: MaterialPresets.linkedKey !== "" ? mat.panel.accent : mat.palette.fgDim
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                elide: Text.ElideRight
                                variant: "label"
                                text: MaterialPresets.wornScheme !== "" ? MaterialPresets.wornScheme : Translation.tr("No colour scheme applied")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                Layout.preferredWidth: 0
                                wrapMode: Text.WordWrap
                                variant: "caption"
                                emphasis: "dim"
                                text: MaterialPresets.linkBlocker() !== "" ? MaterialPresets.linkBlocker()
                                    : MaterialPresets.linkedKey !== "" ? Translation.tr("Loads “%1” when applied").arg(MaterialPresets.labelOf(MaterialPresets.linkedKey))
                                    : Translation.tr("Lock it to wear this look whenever the scheme is applied")
                            }
                        }
                        PanelButton {
                            Layout.fillHeight: false
                            variant: MaterialPresets.linkedKey !== "" ? "normal" : "primary"
                            accent: mat.panel.accent
                            symbol: MaterialPresets.linkedKey !== "" ? "lock_open" : "lock"
                            label: MaterialPresets.linkedKey !== "" ? Translation.tr("Unlock") : Translation.tr("Lock")
                            enabled: MaterialPresets.linkBlocker() === ""
                            onActivated: MaterialPresets.toggleLink()
                        }
                    }
                }
            }

            // ══ Colour ════════════════════════════════════════════════════════
            // ROLES of the palette (never a hex), so they follow every wallpaper.
            WallpaperMaterialPlate {
                title: Translation.tr("Colour")
                symbol: "palette"
                shape: "clover"

                StyledText { text: Translation.tr("Main colour"); variant: "caption"; emphasis: "dim" }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    Repeater {
                        // "" is the palette's primary, so "Default" and "Primary" would be one swatch twice.
                        model: Config.accentRoles
                            .filter(r => r.id !== "primary")
                            .map(r => ({ id: r.id, label: r.id === "" ? "Primary" : r.label }))
                        delegate: Item {
                            id: sw
                            required property var modelData
                            readonly property bool on: mat.style.role === sw.modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: swCol.implicitHeight

                            Column {
                                id: swCol
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Tokens.spacingXs
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Tokens.iconLg + Tokens.spacingSm
                                    height: width
                                    radius: width / 2
                                    color: mat.palette.role(sw.modelData.id, mat.palette.primary)
                                    border.width: sw.on ? 2 : Tokens.borderWidth
                                    border.color: sw.on ? mat.palette.fg : mat.palette.outline
                                    scale: swHover.hovered ? 1.1 : 1
                                    Behavior on scale { NumberAnimation { duration: Motion.fast } }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: sw.on
                                        name: "check"
                                        variant: "caption"
                                        color: mat.palette.fgOnPrimary
                                    }
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: sw.modelData.label
                                    variant: "micro"
                                    color: sw.on ? mat.palette.fg : mat.palette.fgDim
                                }
                            }
                            HoverHandler { id: swHover }
                            TapHandler { onTapped: Config.wallMaterialRole = sw.modelData.id }
                        }
                    }
                }

                StyledText { text: Translation.tr("Accent shapes"); variant: "caption"; emphasis: "dim" }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: Translation.tr("The edge shapes and the second stack. None keeps everything in the main colour.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: 0

                    Repeater {
                        // For the second stack and the edge shapes. "None" keeps it to the one colour.
                        model: [{ id: "", label: "None" }].concat(Config.accentRoles
                            .filter(r => r.id !== "" && r.id !== "primary")
                            .map(r => ({ id: r.id, label: r.label })))
                        delegate: Item {
                            id: sw2
                            required property var modelData
                            readonly property bool on: mat.style.role2 === sw2.modelData.id
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: sw2Col.implicitHeight

                            Column {
                                id: sw2Col
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: Tokens.spacingXs
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: Tokens.iconLg + Tokens.spacingSm
                                    height: width
                                    radius: width / 2
                                    color: sw2.modelData.id === "" ? "transparent"
                                         : mat.palette.role(sw2.modelData.id, mat.palette.primary)
                                    border.width: sw2.on ? 2 : Tokens.borderWidth
                                    border.color: sw2.on ? mat.palette.fg : mat.palette.outline
                                    scale: sw2Hover.hovered ? 1.1 : 1
                                    Behavior on scale { NumberAnimation { duration: Motion.fast } }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        visible: sw2.on || sw2.modelData.id === ""
                                        name: sw2.modelData.id === "" ? "block" : "check"
                                        variant: "caption"
                                        color: sw2.modelData.id === "" ? mat.palette.fgDim : mat.palette.fgOnPrimary
                                    }
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: sw2.modelData.label
                                    variant: "micro"
                                    color: sw2.on ? mat.palette.fg : mat.palette.fgDim
                                }
                            }
                            HoverHandler { id: sw2Hover }
                            TapHandler { onTapped: Config.wallMaterialRole2 = sw2.modelData.id }
                        }
                    }
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Contrast")
                    from: 0.5; to: 1.5; step: 0.05
                    value: Config.wallMaterialContrast
                    readout: Math.round(Config.wallMaterialContrast * 100) + "%"
                    onCommit: function (v) { Config.wallMaterialContrast = v }
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Ground tint")
                    from: 0; to: 0.3; step: 0.01
                    value: Config.wallMaterialBackdrop
                    readout: Config.wallMaterialBackdrop <= 0 ? "off" : Math.round(Config.wallMaterialBackdrop / 0.3 * 100) + "%"
                    onCommit: function (v) { Config.wallMaterialBackdrop = v }
                }
            }

            // ══ Shapes ════════════════════════════════════════════════════════
            // Pick the part of the picture, then the shape it wears. The composition's own shape is
            // stored as "", never as a default baked into the config. While the pointer is on this plate
            // the preview dims all but the part being chosen for.
            WallpaperMaterialPlate {
                title: Translation.tr("Shapes")
                symbol: "category"
                shape: "squircle"

                HoverHandler { id: shapesHover }
                Binding {
                    target: mat.panel
                    property: "materialSlot"
                    value: shapesHover.hovered ? mat.slot : ""
                    restoreMode: Binding.RestoreNone
                }

                ChipRow {
                    Layout.fillHeight: false
                    accent: mat.panel.accent
                    model: [
                        { value: "stack",  label: Translation.tr("Background") },
                        { value: "centre", label: Translation.tr("Centre") },
                        { value: "side",   label: Translation.tr("Side") },
                        { value: "corner", label: Translation.tr("Corner") }
                    ]
                    current: mat.slot
                    onPicked: function (v) { mat.slot = v }
                }
                Flow {
                    id: formGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingXs

                    readonly property string chosen: mat.style[mat.slot] || MW.DEFAULT_FORMS[mat.slot]
                    readonly property int cols: 6

                    Repeater {
                        model: MW.FORM_LIST
                        delegate: Rectangle {
                            id: fm
                            required property var modelData
                            readonly property bool on: formGrid.chosen === fm.modelData.id
                            width: Math.floor((formGrid.width - formGrid.spacing * (formGrid.cols - 1)) / formGrid.cols)
                            height: width
                            radius: Tokens.radiusSm
                            color: fm.on ? mat.palette.alpha(mat.panel.accent, 0.20)
                                 : fmHover.hovered ? mat.palette.alpha(mat.panel.accent, 0.10)
                                 : mat.palette.section
                            border.width: fm.on ? 2 : 0
                            border.color: mat.panel.accent
                            Behavior on color { ColorAnimation { duration: Motion.respond } }

                            Shape {
                                anchors.centerIn: parent
                                width: fm.width * 0.62
                                height: width
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: fm.on ? mat.panel.accent : mat.palette.fgDim
                                    strokeWidth: -1
                                    PathPolyline {
                                        path: MW.outline(MW.FORMS[fm.modelData.id], fm.width * 0.62, 1)
                                            .map(function (p) { return Qt.point(p.x, p.y) })
                                    }
                                }
                            }
                            HoverHandler { id: fmHover }
                            TapHandler {
                                onTapped: Config[MW.CONFIG_KEY[mat.slot]] =
                                    fm.modelData.id === MW.DEFAULT_FORMS[mat.slot] ? "" : fm.modelData.id
                            }
                        }
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: MW.FORM_LIST.find(f => f.id === formGrid.chosen).label
                        + (mat.style[mat.slot] === "" ? Translation.tr(", the composition's own") : "")
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Softness")
                    from: 0.4; to: 1.8; step: 0.05
                    value: Config.wallMaterialSoftness
                    readout: Math.round(Config.wallMaterialSoftness * 100) + "%"
                    onCommit: function (v) { Config.wallMaterialSoftness = v }
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Size")
                    from: 0.7; to: 1.4; step: 0.05
                    value: Config.wallMaterialSize
                    readout: Math.round(Config.wallMaterialSize * 100) + "%"
                    onCommit: function (v) { Config.wallMaterialSize = v }
                }
                WallpaperOptionRow {
                    label: Translation.tr("Mirror")
                    detail: Translation.tr("Flip the picture left to right")
                    checked: Config.wallMaterialMirror
                    onToggled: Config.wallMaterialMirror = !Config.wallMaterialMirror
                }
            }

            // ══ Motion ════════════════════════════════════════════════════════
            // A frame loop on the whole desktop: off until asked for, and stopped while a fullscreen
            // window covers the screen.
            WallpaperMaterialPlate {
                title: Translation.tr("Motion")
                symbol: "animation"
                shape: "cookie9"
                note: Config.wallMaterialDrift || Config.wallMaterialSpin > 0 ? Translation.tr("On") : Translation.tr("Still")

                WallpaperOptionRow {
                    label: Translation.tr("Drift")
                    detail: Translation.tr("Every shape wanders slowly about where it sits")
                    checked: Config.wallMaterialDrift
                    onToggled: Config.wallMaterialDrift = !Config.wallMaterialDrift
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Spin")
                    from: 0; to: 1; step: 0.05
                    value: Config.wallMaterialSpin
                    readout: Config.wallMaterialSpin <= 0 ? "off" : Math.round(Config.wallMaterialSpin * 100) + "%"
                    onCommit: function (v) { Config.wallMaterialSpin = v }
                }
                Fader {
                    accent: mat.panel.accent
                    label: Translation.tr("Speed")
                    enabled: Config.wallMaterialDrift || Config.wallMaterialSpin > 0
                    from: 0.2; to: 3; step: 0.1
                    value: Config.wallMaterialDriftSpeed
                    readout: Config.wallMaterialDriftSpeed.toFixed(1) + "×"
                    onCommit: function (v) { Config.wallMaterialDriftSpeed = v }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    wrapMode: Text.WordWrap
                    variant: "caption"
                    emphasis: "dim"
                    text: Translation.tr("Motion redraws the whole desktop every frame. It stops while a fullscreen window or Game Mode has the screen.")
                }
                Divider { Layout.fillWidth: true }
                // The fallback: a still of this held by awww, so it outlives the shell.
                WallpaperOptionRow {
                    label: Translation.tr("Keep it if the shell closes")
                    detail: MaterialFallback.blocker() !== "" ? MaterialFallback.blocker()
                          : Translation.tr("Saves a still image of this wallpaper")
                    enabled: MaterialFallback.blocker() === ""
                    checked: Config.wallMaterialFallback && MaterialFallback.blocker() === ""
                    onToggled: Config.wallMaterialFallback = !Config.wallMaterialFallback
                }
                PanelButton {
                    Layout.alignment: Qt.AlignLeft
                    variant: "ghost"
                    accent: mat.panel.accent
                    symbol: "restart_alt"
                    label: Translation.tr("Reset style")
                    onActivated: mat.applyStyle(MW.lookStyle("default", 0))
                }
            }
        }
    }
    Scrollbar { flickable: flick }
}
