import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/materialwall.js" as MW

// The one wallpaper, drawn live from the screen's own palette (the same component the desktop
// draws, so what is previewed is what applies), and the style it takes. Style changes are live
// on the desktop when it is applied and on the preview always; Apply is what puts it on screen,
// and takes the picture / scene off (Wallpaper.applyMaterial). Behind a Loader so a panel opened
// for a picture never builds it.
//
// Laid out like the rest of the panel: a card for the picture and its one action on the left, a
// card of settings on the right in four pages (Looks, Colour, Shapes, Motion), both on the
// container fill with the card radius the hero strip wears. The style is read as ONE object
// (`mat.style`, keyed like services/materialwall.js STYLE) so a look can be recognised and applied
// as a whole.
RowLayout {
    required property var panel

    id: mat
    spacing: Tokens.spacingMd

    readonly property var style: {
        const o = ({})
        for (const k in MW.CONFIG_KEY) o[k] = Config[MW.CONFIG_KEY[k]]
        if (o.role === "primary") o.role = ""     // the same colour, said two ways
        return o
    }
    function applyStyle(s) {
        for (const k in MW.CONFIG_KEY) Config[MW.CONFIG_KEY[k]] = s[k]
    }

    // ── Left: the wallpaper, and the one action ──────────────────────
    Rectangle {
        Layout.preferredWidth: 236
        Layout.maximumWidth: 236
        Layout.fillHeight: true
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).surfaceContainer

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            spacing: Tokens.spacingSm

            ClippingRectangle {
                id: preview
                Layout.fillWidth: true
                // The real screen's shape, so the composition is framed as it will be.
                Layout.preferredHeight: Math.round(width / Math.max(1.2, Math.min(2.4,
                    (QsWindow.window?.screen?.width ?? 16) / Math.max(1, QsWindow.window?.screen?.height ?? 9))))
                Layout.fillHeight: false
                // Concentric with the card around it.
                radius: Tokens.radiusCard - Tokens.spacingSm / 2
                color: "transparent"
                // The wallpaper in force is outlined, as it is in the gallery.
                border.width: Config.wallMaterial ? 2 : Tokens.borderWidth
                border.color: Config.wallMaterial ? panel.accent : Colors.of(QsWindow.window).outline
                Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                MaterialWallpaper { anchors.fill: parent }

                // "On your desktop", said on the picture itself.
                Rectangle {
                    visible: Config.wallMaterial
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Tokens.spacingSm
                    radius: height / 2
                    color: panel.accent
                    implicitWidth: onRow.implicitWidth + Tokens.spacingMd * 2
                    implicitHeight: onRow.implicitHeight + Tokens.spacingXs * 2
                    Row {
                        id: onRow
                        anchors.centerIn: parent
                        spacing: Tokens.spacingXs
                        MaterialIcon { name: "check"; variant: "caption"; color: Colors.of(QsWindow.window).fgOnPrimary }
                        StyledText { text: "On screen"; variant: "caption"; color: Colors.of(QsWindow.window).fgOnPrimary }
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
                    accent: panel.accent
                    symbol: Config.wallMaterial ? "close" : "check"
                    label: Config.wallMaterial ? "Turn off" : "Apply"
                    enabled: Config.wallMaterial || Wallpaper.materialBlocker() === ""
                    onActivated: {
                        if (Config.wallMaterial) Config.wallMaterial = false
                        else                     Wallpaper.applyMaterial()
                    }
                }
                // A different arrangement of the same shapes.
                PanelButton {
                    variant: "normal"
                    accent: panel.accent
                    symbol: "shuffle"
                    label: Translation.tr("Shuffle")
                    onActivated: Config.wallMaterialSeed = 1 + Math.floor(Math.random() * 1000000)
                }
            }

            Item { Layout.fillHeight: true }

            Divider { Layout.fillWidth: true }

            // The fallback: a still of this held by awww, so it outlives the shell.
            WallpaperOptionRow {
                label: Translation.tr("Stay without the shell")
                detail: MaterialFallback.blocker() !== "" ? MaterialFallback.blocker()
                      : "A still is held by awww"
                enabled: MaterialFallback.blocker() === ""
                checked: Config.wallMaterialFallback && MaterialFallback.blocker() === ""
                onToggled: Config.wallMaterialFallback = !Config.wallMaterialFallback
            }
        }
    }

    // ── Right: the style, in four pages ──────────────────────────────
    Rectangle {
        id: styleSide
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.radiusCard
        color: Colors.of(QsWindow.window).surfaceContainer

        // looks | colour | shapes | motion
        property string page: "looks"
        // Which part of the picture the Shapes page is choosing for.
        property string slot: "stack"

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingSm
            spacing: Tokens.spacingSm

            SegmentSwitch {
                Layout.fillWidth: true
                Layout.fillHeight: false
                accent: panel.accent
                model: [
                    { value: "looks",  label: "Looks",  icon: "auto_awesome" },
                    { value: "colour", label: "Colour", icon: "palette", fillIcon: false },
                    { value: "shapes", label: "Shapes", icon: "category" },
                    { value: "motion", label: "Motion", icon: "animation", lit: Config.wallMaterialDrift || Config.wallMaterialSpin > 0 }
                ]
                current: styleSide.page
                onPicked: function (v) { styleSide.page = v }
            }

            Flickable {
                id: styleFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: styleCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                ColumnLayout {
                    id: styleCol
                    width: styleFlick.width
                    spacing: Tokens.spacingSm

                    // ── Looks ─────────────────────────────────────────
                    // Each sets the whole style; the one in force is lit, and any tweak after it
                    // leaves none lit (it is then your own mix: save it below). Yours come after
                    // the built-in ones, and a lock marks a look a colour scheme wears
                    // (services/MaterialPresets).
                    Flow {
                        id: looks
                        visible: styleSide.page === "looks"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs

                        Repeater {
                            model: styleSide.page === "looks" ? MaterialPresets.looks : []
                            delegate: Rectangle {
                                id: lk
                                required property var modelData
                                readonly property bool on: MaterialPresets.currentKey === lk.modelData.key
                                readonly property var wornBy: MaterialPresets.schemesOf(lk.modelData.key)
                                width: Math.floor((looks.width - looks.spacing * 2) / 3)
                                height: 54
                                radius: Tokens.radiusSm
                                color: lk.on ? Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                                     : lkHover.hovered ? Colors.of(QsWindow.window).alpha(panel.accent, 0.10)
                                     : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
                                border.width: lk.on ? 2 : 0
                                border.color: panel.accent
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                Column {
                                    anchors.centerIn: parent
                                    width: parent.width - Tokens.spacingSm * 2
                                    spacing: Tokens.spacingXs
                                    MaterialIcon {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        name: lk.modelData.icon
                                        fill: lk.on ? 1 : 0
                                        color: lk.on ? panel.accent : Colors.of(QsWindow.window).fgDim
                                    }
                                    StyledText {
                                        width: parent.width
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                        text: lk.modelData.label
                                        variant: "caption"
                                        color: lk.on ? panel.accent : Colors.of(QsWindow.window).fg
                                    }
                                }

                                // Worn by a colour scheme.
                                MaterialIcon {
                                    visible: lk.wornBy.length > 0
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.spacingXs
                                    name: "lock"
                                    fill: 1
                                    variant: "micro"
                                    color: panel.accent
                                }

                                HoverHandler { id: lkHover }
                                TapHandler { onTapped: MaterialPresets.apply(lk.modelData.key) }

                                // A saved look can go: one click arms it, the next removes it.
                                ArmLatch {
                                    id: lkDrop
                                    onConfirmed: MaterialPresets.remove(lk.modelData.key)
                                }
                                MaterialIcon {
                                    visible: !lk.modelData.builtIn && (lkHover.hovered || lkDrop.armed)
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Tokens.spacingXs
                                    name: "close"
                                    variant: "micro"
                                    color: lkDrop.armed ? Colors.of(QsWindow.window).danger : Colors.of(QsWindow.window).fgDim
                                    TapHandler { onTapped: lkDrop.trigger() }
                                }
                            }
                        }
                    }

                    // ── The lock: this look ↔ the colour scheme worn ──────
                    // Like the colours panel's lock, for the picture: link the look in use to the
                    // scheme the shell wears, and applying that scheme loads it.
                    Rectangle {
                        id: linkCard
                        visible: styleSide.page === "looks"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        implicitHeight: linkRow.implicitHeight + Tokens.spacingSm * 2
                        radius: Tokens.radiusSm
                        color: MaterialPresets.linkedKey !== "" ? Colors.of(QsWindow.window).alpha(panel.accent, 0.12)
                                                               : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        RowLayout {
                            id: linkRow
                            anchors.fill: parent
                            anchors.margins: Tokens.spacingSm
                            spacing: Tokens.spacingSm

                            MaterialIcon {
                                name: MaterialPresets.linkedKey !== "" ? "lock" : "lock_open"
                                fill: MaterialPresets.linkedKey !== "" ? 1 : 0
                                color: MaterialPresets.linkedKey !== "" ? panel.accent : Colors.of(QsWindow.window).fgDim
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: false
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    elide: Text.ElideRight
                                    variant: "body"
                                    text: MaterialPresets.wornScheme !== "" ? MaterialPresets.wornScheme : "No colour scheme applied"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 0
                                    wrapMode: Text.WordWrap
                                    variant: "caption"
                                    emphasis: "dim"
                                    text: MaterialPresets.linkBlocker() !== "" ? MaterialPresets.linkBlocker()
                                        : MaterialPresets.linkedKey !== "" ? "Loads “" + MaterialPresets.labelOf(MaterialPresets.linkedKey) + "” when applied"
                                        : "Lock it to wear this look whenever the scheme is applied"
                                }
                            }
                            PanelButton {
                                Layout.fillHeight: false
                                variant: MaterialPresets.linkedKey !== "" ? "normal" : "primary"
                                accent: panel.accent
                                symbol: MaterialPresets.linkedKey !== "" ? "lock_open" : "lock"
                                label: MaterialPresets.linkedKey !== "" ? "Unlock" : "Lock"
                                enabled: MaterialPresets.linkBlocker() === ""
                                onActivated: MaterialPresets.toggleLink()
                            }
                        }
                    }

                    // ── Save the mix in use ───────────────────────────────
                    RowLayout {
                        visible: styleSide.page === "looks"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm

                        InputField {
                            id: lookName
                            Layout.fillWidth: true
                            implicitHeight: Tokens.iconXl + Tokens.spacingMd
                            cornerRadius: implicitHeight / 2
                            placeholder: Translation.tr("Name this look…")
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
                            accent: panel.accent
                            symbol: "save"
                            label: Translation.tr("Save")
                            onActivated: if (MaterialPresets.save(lookName.text) !== "") lookName.clear()
                        }
                    }
                    WallpaperOptionRow {
                        visible: styleSide.page === "looks"
                        label: Translation.tr("Mirror")
                        detail: Translation.tr("Flip the picture left to right")
                        checked: Config.wallMaterialMirror
                        onToggled: Config.wallMaterialMirror = !Config.wallMaterialMirror
                    }

                    // ── Colour ────────────────────────────────────────
                    // ROLES of the palette (never a hex), so they follow every wallpaper.
                    StyledText { visible: styleSide.page === "colour"; text: "Colour"; variant: "label"; emphasis: "dim" }
                    RowLayout {
                        visible: styleSide.page === "colour"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0

                        Repeater {
                            // "" is the palette's primary, so "Default" and "Primary" would be one swatch twice.
                            model: styleSide.page === "colour" ? Config.accentRoles
                                .filter(r => r.id !== "primary")
                                .map(r => ({ id: r.id, label: r.id === "" ? "Primary" : r.label })) : []
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
                                        color: Colors.of(QsWindow.window).role(sw.modelData.id, Colors.of(QsWindow.window).primary)
                                        border.width: sw.on ? 2 : Tokens.borderWidth
                                        border.color: sw.on ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).outline
                                        scale: swHover.hovered ? 1.1 : 1
                                        Behavior on scale { NumberAnimation { duration: Motion.fast } }
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: sw.on
                                            name: "check"
                                            variant: "caption"
                                            color: Colors.of(QsWindow.window).fgOnPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: sw.modelData.label
                                        variant: "micro"
                                        color: sw.on ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                                    }
                                }
                                HoverHandler { id: swHover }
                                TapHandler { onTapped: Config.wallMaterialRole = sw.modelData.id }
                            }
                        }
                    }
                    StyledText { visible: styleSide.page === "colour"; text: "Second colour"; variant: "label"; emphasis: "dim" }
                    RowLayout {
                        visible: styleSide.page === "colour"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: 0

                        Repeater {
                            // For the second stack and the edge shapes. "None" keeps it to the one colour.
                            model: styleSide.page === "colour" ? [{ id: "", label: "None" }].concat(Config.accentRoles
                                .filter(r => r.id !== "" && r.id !== "primary")
                                .map(r => ({ id: r.id, label: r.label }))) : []
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
                                             : Colors.of(QsWindow.window).role(sw2.modelData.id, Colors.of(QsWindow.window).primary)
                                        border.width: sw2.on ? 2 : Tokens.borderWidth
                                        border.color: sw2.on ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).outline
                                        scale: sw2Hover.hovered ? 1.1 : 1
                                        Behavior on scale { NumberAnimation { duration: Motion.fast } }
                                        MaterialIcon {
                                            anchors.centerIn: parent
                                            visible: sw2.on || sw2.modelData.id === ""
                                            name: sw2.modelData.id === "" ? "block" : "check"
                                            variant: "caption"
                                            color: sw2.modelData.id === "" ? Colors.of(QsWindow.window).fgDim
                                                                           : Colors.of(QsWindow.window).fgOnPrimary
                                        }
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: sw2.modelData.label
                                        variant: "micro"
                                        color: sw2.on ? Colors.of(QsWindow.window).fg : Colors.of(QsWindow.window).fgDim
                                    }
                                }
                                HoverHandler { id: sw2Hover }
                                TapHandler { onTapped: Config.wallMaterialRole2 = sw2.modelData.id }
                            }
                        }
                    }
                    Fader {
                        visible: styleSide.page === "colour"
                        accent: panel.accent
                        label: Translation.tr("Contrast")
                        from: 0.5; to: 1.5; step: 0.05
                        value: Config.wallMaterialContrast
                        readout: Math.round(Config.wallMaterialContrast * 100) + "%"
                        onCommit: function (v) { Config.wallMaterialContrast = v }
                    }
                    Fader {
                        visible: styleSide.page === "colour"
                        accent: panel.accent
                        label: Translation.tr("Ground tint")
                        from: 0; to: 0.3; step: 0.01
                        value: Config.wallMaterialBackdrop
                        readout: Config.wallMaterialBackdrop <= 0 ? "off" : Math.round(Config.wallMaterialBackdrop / 0.3 * 100) + "%"
                        onCommit: function (v) { Config.wallMaterialBackdrop = v }
                    }

                    // ── Shapes ────────────────────────────────────────
                    // Pick the part of the picture, then the shape it wears. The composition's
                    // own shape is stored as "", never as a default baked into the config.
                    ChipRow {
                        visible: styleSide.page === "shapes"
                        Layout.fillHeight: false
                        accent: panel.accent
                        model: [
                            { value: "stack",  label: "Bursts" },
                            { value: "centre", label: "Centre" },
                            { value: "side",   label: "Side" },
                            { value: "corner", label: "Corner" }
                        ]
                        current: styleSide.slot
                        onPicked: function (v) { styleSide.slot = v }
                    }
                    Flow {
                        id: formGrid
                        visible: styleSide.page === "shapes"
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingXs

                        readonly property string chosen: mat.style[styleSide.slot] || MW.DEFAULT_FORMS[styleSide.slot]
                        readonly property int cols: 5

                        Repeater {
                            model: styleSide.page === "shapes" ? MW.FORM_LIST : []
                            delegate: Rectangle {
                                id: fm
                                required property var modelData
                                readonly property bool on: formGrid.chosen === fm.modelData.id
                                width: Math.floor((formGrid.width - formGrid.spacing * (formGrid.cols - 1)) / formGrid.cols)
                                height: width
                                radius: Tokens.radiusSm
                                color: fm.on ? Colors.of(QsWindow.window).alpha(panel.accent, 0.20)
                                     : fmHover.hovered ? Colors.of(QsWindow.window).alpha(panel.accent, 0.10)
                                     : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.05)
                                border.width: fm.on ? 2 : 0
                                border.color: panel.accent
                                Behavior on color { ColorAnimation { duration: Motion.respond } }

                                Shape {
                                    anchors.centerIn: parent
                                    width: fm.width * 0.62
                                    height: width
                                    preferredRendererType: Shape.CurveRenderer
                                    ShapePath {
                                        fillColor: fm.on ? panel.accent : Colors.of(QsWindow.window).fgDim
                                        strokeWidth: -1
                                        PathPolyline {
                                            path: MW.outline(MW.FORMS[fm.modelData.id], fm.width * 0.62, 1)
                                                .map(function (p) { return Qt.point(p.x, p.y) })
                                        }
                                    }
                                }
                                HoverHandler { id: fmHover }
                                TapHandler {
                                    onTapped: Config[MW.CONFIG_KEY[styleSide.slot]] =
                                        fm.modelData.id === MW.DEFAULT_FORMS[styleSide.slot] ? "" : fm.modelData.id
                                }
                            }
                        }
                    }
                    StyledText {
                        visible: styleSide.page === "shapes"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        emphasis: "dim"
                        text: MW.FORM_LIST.find(f => f.id === formGrid.chosen).label
                            + (mat.style[styleSide.slot] === "" ? " — the composition's own" : "")
                    }
                    Fader {
                        visible: styleSide.page === "shapes"
                        accent: panel.accent
                        label: Translation.tr("Softness")
                        from: 0.4; to: 1.8; step: 0.05
                        value: Config.wallMaterialSoftness
                        readout: Math.round(Config.wallMaterialSoftness * 100) + "%"
                        onCommit: function (v) { Config.wallMaterialSoftness = v }
                    }
                    Fader {
                        visible: styleSide.page === "shapes"
                        accent: panel.accent
                        label: Translation.tr("Size")
                        from: 0.7; to: 1.4; step: 0.05
                        value: Config.wallMaterialSize
                        readout: Math.round(Config.wallMaterialSize * 100) + "%"
                        onCommit: function (v) { Config.wallMaterialSize = v }
                    }

                    // ── Motion ────────────────────────────────────────
                    // A frame loop on the whole desktop: off until asked for, and stopped while a
                    // fullscreen window covers the screen.
                    WallpaperOptionRow {
                        visible: styleSide.page === "motion"
                        label: Translation.tr("Drift")
                        detail: Translation.tr("Every shape wanders slowly about where it sits")
                        checked: Config.wallMaterialDrift
                        onToggled: Config.wallMaterialDrift = !Config.wallMaterialDrift
                    }
                    Fader {
                        visible: styleSide.page === "motion"
                        accent: panel.accent
                        label: Translation.tr("Spin")
                        from: 0; to: 1; step: 0.05
                        value: Config.wallMaterialSpin
                        readout: Config.wallMaterialSpin <= 0 ? "off" : Math.round(Config.wallMaterialSpin * 100) + "%"
                        onCommit: function (v) { Config.wallMaterialSpin = v }
                    }
                    Fader {
                        visible: styleSide.page === "motion"
                        accent: panel.accent
                        label: Translation.tr("Speed")
                        enabled: Config.wallMaterialDrift || Config.wallMaterialSpin > 0
                        from: 0.2; to: 3; step: 0.1
                        value: Config.wallMaterialDriftSpeed
                        readout: Config.wallMaterialDriftSpeed.toFixed(1) + "×"
                        onCommit: function (v) { Config.wallMaterialDriftSpeed = v }
                    }
                    StyledText {
                        visible: styleSide.page === "motion"
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        wrapMode: Text.WordWrap
                        variant: "caption"
                        emphasis: "dim"
                        text: Translation.tr("Motion redraws the whole desktop every frame. It stops while a fullscreen window or Game Mode has the screen.")
                    }

                    PanelButton {
                        Layout.alignment: Qt.AlignLeft
                        variant: "ghost"
                        accent: panel.accent
                        symbol: "restart_alt"
                        label: Translation.tr("Reset style")
                        onActivated: mat.applyStyle(MW.lookStyle("default", 0))
                    }
                }
            }
        }
    }
}
