pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../state"
import "../../../services/gradient.js" as Grad

// ── SchemeGradient ────────────────────────────────────────────────────────────
// The colour scheme page's Gradient view: the bar and the islands' faces painted as a gradient of the colours
// you wear, instead of one flat fill. The blob draws it (Quicktest.Blobs), so it reaches exactly where the blob
// owns the fill: the bar, the screen frame and every island that is welded to it.
//
// One scroll of plates:
//   the hero       what the gradient looks like on a strip, in words, and the switch (the page's one loud pill).
//   Looks          cards that are miniatures of what they paint, made of palette roles so they follow the wallpaper.
//   Colours        the gradient as a strip with a handle for each colour: press one to change it to a role of the
//                  palette or a colour of your own, add or remove the middle one.
//   Direction      a slider round the whole turn, and four quick ones.
//   Strength       how far from the plain fill the colours go, and where the middle sits.
//   Glass          how much of the desktop shows through the shell, tinted and blurred, with or without a gradient.
//   Where it is kept  which saved scheme keeps the gradient.
//
// Everything edits Config.barGradient live (nothing to apply): the loud card on the left wears it as you go.
// The gradient belongs to the scheme: saving a scheme keeps it, wearing one brings it (off when it has none), and
// it is off until you turn it on for a scheme (ColorScheme.syncGradient, rememberGradient).
// All the rules and defaults are services/gradient.js; this file shows them and writes one document.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root

    required property var panel
    readonly property var palette: Colors.of(QsWindow.window)

    visible: root.panel.view === "gradient" && !root.panel.showProgress && !root.panel.picking

    ViewEnter { target: root; active: root.visible }

    readonly property var doc: Grad.clean(Config.barGradient)
    readonly property bool on: root.doc.on
    readonly property var stops: Grad.colours(root.doc, n => String(root.palette.role(n, root.palette.primary)), String(root.palette.frameFill))

    // Why the gradient cannot show, or "" when it can. The controls stay usable (a gradient set now shows once
    // the plugin is there) but the hero says so.
    readonly property string blocker: !Morph.available
        ? Translation.tr("The bar's blob plugin is not built, so the bar is drawn flat.")
        : !Morph.gradient
        ? Translation.tr("The installed blob plugin is older than gradients. Rebuild it with scripts/build-blobs-plugin.sh.")
        : !Config.barAnchored
        ? Translation.tr("A floating bar is drawn flat. Anchor the bar to the screen edge to see the gradient.")
        : ""

    function edit(patch) {
        Config.barGradient = Grad.clean(Object.assign({}, root.doc, patch, { from: "" }))
        ColorScheme.rememberGradient()
    }
    function colorOf(s) {
        return Grad.mix(String(s.startsWith("#") ? s : root.palette.role(s, root.palette.primary)), "#000000", 0)
    }
    function setStop(i, v) {
        const next = root.doc.stops.slice()
        next[i] = v
        root.edit({ stops: next })
    }
    readonly property bool hasMid: root.doc.stops.length === 3
    function toggleMid() {
        const s = root.doc.stops
        root.edit({ stops: root.hasMid ? [s[0], s[2]] : [s[0], "vivid", s[1]] })
    }

    readonly property var roles: [
        { id: "primary",          label: Translation.tr("Primary") },
        { id: "focus",            label: Translation.tr("Focus") },
        { id: "vivid",            label: Translation.tr("Vivid") },
        { id: "primaryContainer", label: Translation.tr("Soft") },
        { id: "fg",               label: Translation.tr("Text") }
    ]
    // The looks: roles only, so each follows the palette worn. `angle` is left alone (it is yours).
    readonly property var looks: [
        { name: Translation.tr("Tint"),  stops: ["primary", "focus"] },
        { name: Translation.tr("Glow"),  stops: ["primaryContainer", "vivid"] },
        { name: Translation.tr("Dusk"),  stops: ["focus", "primary", "vivid"] },
        { name: Translation.tr("Fade"),  stops: ["fg", "primary"] },
        { name: Translation.tr("Ember"), stops: ["vivid", "primaryContainer", "primary"] }
    ]
    // Which colour of the strip is being changed.
    property int sel: 0
    readonly property int selAt: Math.min(root.sel, root.doc.stops.length - 1)
    readonly property var directions: [
        { angle: 0,   label: Translation.tr("Across") },
        { angle: 30,  label: Translation.tr("Slant") },
        { angle: 90,  label: Translation.tr("Down") },
        { angle: 330, label: Translation.tr("Rise") }
    ]

    // Where this gradient is kept: in the saved scheme on show, which wears it whenever it is up.
    readonly property string worn: ColorScheme.worn
    readonly property bool saved: ColorScheme.wornSaved !== null

    component Heading: StyledText {
        variant: "caption"
        font.weight: Font.Bold
        font.letterSpacing: 1
        color: root.palette.fgMuted
    }

    Flickable {
        id: pane
        anchors.fill: parent
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: pane.width - Tokens.spacingLg
            spacing: Tokens.spacingLg

            // ══ The hero ══════════════════════════════════════════════════════════
            ClippingRectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Tokens.iconXl * 3 + Tokens.spacingMd
                radius: Tokens.radiusXl
                color: root.palette.section

                GradientFill {
                    anchors.fill: parent
                    colors: root.stops
                    mid: root.doc.mid
                    angle: root.doc.angle
                    opacity: root.on ? 1 : 0.35
                    Behavior on opacity { NumberAnimation { duration: Motion.standard } }
                }
                // A strip to say what it is painted on: the bar, with pills on it.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Tokens.iconXl + Tokens.spacingMd
                    color: root.palette.alpha(root.palette.base, 0.28)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        x: Tokens.spacingLg
                        spacing: Tokens.spacingSm
                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                required property int index
                                width: Tokens.iconLg * (index === 1 ? 2.4 : 1.4)
                                height: Tokens.iconSm
                                radius: height / 2
                                color: root.palette.alpha(root.palette.fg, 0.55)
                            }
                        }
                    }
                }
                ColumnLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: Tokens.spacingLg
                    spacing: 0
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingMd
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 0
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: root.on ? Translation.tr("Gradient on") : Translation.tr("Gradient off")
                                variant: "title"
                                font.weight: Font.Bold
                                color: root.palette.fg
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: root.blocker !== "" ? root.blocker
                                    : root.doc.from !== "" ? Translation.tr("From the scheme “%1”").arg(root.doc.from)
                                    : root.on ? Translation.tr("The bar and the islands wear it.")
                                    : Translation.tr("The bar and the islands are one flat colour.")
                                variant: "caption"
                                color: root.palette.alpha(root.palette.fg, 0.85)
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }
                        ChipButton {
                            solid: root.on
                            tonal: !root.on
                            symbol: "opacity"
                            label: root.on ? Translation.tr("Turn off") : Translation.tr("Turn on")
                            tint: root.panel.accent
                            onActivated: root.edit({ on: !root.on })
                        }
                    }
                }
            }

            // ══ Looks ═════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Heading { text: Translation.tr("Looks").toUpperCase() }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    uniformCellSizes: true
                    Repeater {
                        model: root.looks
                        delegate: ClippingRectangle {
                            id: look
                            required property var modelData
                            readonly property bool picked: root.doc.stops.join() === look.modelData.stops.join()
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            Layout.preferredHeight: Tokens.iconXl * 2 + Tokens.spacingMd
                            radius: Tokens.radiusCard
                            color: root.palette.section
                            border.width: look.picked ? Tokens.borderWidth * 2 : 0
                            border.color: root.panel.accent
                            Behavior on border.width { NumberAnimation { duration: Motion.fast } }

                            GradientFill {
                                anchors.fill: parent
                                angle: 60
                                mid: 0.5
                                colors: Grad.colours({ stops: look.modelData.stops, strength: 1, mid: 0.5 },
                                                     n => String(root.palette.role(n, root.palette.primary)),
                                                     String(root.palette.frameFill))
                            }
                            StyledText {
                                anchors.left: parent.left
                                anchors.bottom: parent.bottom
                                anchors.margins: Tokens.spacingSm
                                text: look.modelData.name
                                variant: "caption"
                                font.weight: Font.DemiBold
                                color: root.palette.fg
                            }
                            StateLayer {
                                anchors.fill: parent
                                radius: look.radius
                                hovered: lookHover.hovered
                                layerColor: root.palette.fg
                            }
                            HoverHandler { id: lookHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: root.edit({ stops: look.modelData.stops.slice(), on: true }) }
                            Accessible.role: Accessible.Button
                            Accessible.name: look.modelData.name
                            Accessible.onPressAction: root.edit({ stops: look.modelData.stops.slice(), on: true })
                        }
                    }
                }
            }

            // ══ Colours ═══════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Heading { text: Translation.tr("Colours").toUpperCase() }

                // The strip: the gradient as it runs, a handle at each colour.
                Item {
                    id: strip
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXl
                    ClippingRectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: Tokens.iconLg
                        radius: height / 2
                        color: root.palette.section
                        GradientFill {
                            anchors.fill: parent
                            angle: 0
                            mid: root.doc.mid
                            colors: Grad.colours({ stops: root.doc.stops, strength: 1, mid: root.doc.mid },
                                                 n => String(root.palette.role(n, root.palette.primary)),
                                                 String(root.palette.frameFill))
                        }
                    }
                    Repeater {
                        model: root.doc.stops.length
                        delegate: Rectangle {
                            id: handle
                            required property int index
                            readonly property bool chosen: handle.index === root.selAt
                            readonly property real frac: root.hasMid ? (handle.index === 0 ? 0 : handle.index === 1 ? root.doc.mid : 1)
                                                                      : (handle.index === 0 ? 0 : 1)
                            SpringValue { id: grow; target: handle.chosen ? 1 : 0; spec: Motion.springSpatialFast; epsilon: 0.002 }
                            width: Tokens.iconXl + Tokens.spacingXs + Math.max(0, grow.value) * Tokens.spacingSm
                            height: width
                            radius: width / 2
                            x: Tokens.spacingMd + (strip.width - Tokens.spacingMd * 2) * handle.frac - width / 2
                            anchors.verticalCenter: parent.verticalCenter
                            color: root.colorOf(root.doc.stops[handle.index])
                            border.width: Tokens.borderWidth * 2
                            border.color: handle.chosen ? root.palette.fg : root.palette.alpha(root.palette.fg, 0.35)
                            Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                            TapHandler { onTapped: root.sel = handle.index }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                            Accessible.role: Accessible.RadioButton
                            Accessible.checked: handle.chosen
                            Accessible.name: handle.index === 0 ? Translation.tr("Start") : handle.index === root.doc.stops.length - 1 ? Translation.tr("End") : Translation.tr("Middle")
                            Accessible.onPressAction: root.sel = handle.index
                        }
                    }
                }

                // The colour on the handle that is chosen.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    implicitHeight: pickCol.implicitHeight + Tokens.spacingMd * 2
                    radius: Tokens.radiusCard
                    color: root.palette.section

                    ColumnLayout {
                        id: pickCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.spacingMd
                        spacing: Tokens.spacingSm

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: false
                            spacing: Tokens.spacingSm
                            StyledText {
                                Layout.fillWidth: true
                                text: root.selAt === 0 ? Translation.tr("Start colour")
                                    : root.selAt === root.doc.stops.length - 1 ? Translation.tr("End colour")
                                    : Translation.tr("Middle colour")
                                variant: "body"
                                font.weight: Font.DemiBold
                                color: root.palette.fg
                            }
                            ChipButton {
                                visible: root.hasMid && root.selAt === 1
                                tonal: true
                                symbol: "delete"
                                label: Translation.tr("Remove")
                                tint: root.panel.accent
                                onActivated: { root.sel = 0; root.toggleMid() }
                            }
                            ChipButton {
                                visible: !root.hasMid
                                tonal: true
                                symbol: "palette"
                                label: Translation.tr("Add a middle")
                                tint: root.panel.accent
                                onActivated: { root.toggleMid(); root.sel = 1 }
                            }
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: Tokens.spacingSm
                            Repeater {
                                model: root.roles
                                delegate: ChipButton {
                                    id: roleChip
                                    required property var modelData
                                    tonal: true
                                    label: roleChip.modelData.label
                                    dot: root.colorOf(roleChip.modelData.id)
                                    on: root.doc.stops[root.selAt] === roleChip.modelData.id
                                    tint: root.panel.accent
                                    onActivated: root.setStop(root.selAt, roleChip.modelData.id)
                                }
                            }
                        }
                        ColorField {
                            label: Translation.tr("Your own")
                            value: root.colorOf(root.doc.stops[root.selAt])
                            onCommit: hex => root.setStop(root.selAt, hex)
                        }
                    }
                }
            }

            // ══ Direction ═════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Heading { text: Translation.tr("Direction").toUpperCase() }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    ValueSlider {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        accessibleName: Translation.tr("Angle")
                        thickness: Tokens.spacingMd
                        expressive: true
                        accent: root.panel.accent
                        maximum: 360
                        value: root.doc.angle
                        onMoved: v => root.edit({ angle: Math.round(v) })
                        onScrolled: d => root.edit({ angle: root.doc.angle + d * 5 })
                    }
                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.doc.angle) + "°"
                        variant: "label"
                        font.features: ({ tnum: 1 })
                        color: root.palette.fgMuted
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm
                    Repeater {
                        model: root.directions
                        delegate: ChipButton {
                            id: dirChip
                            required property var modelData
                            tonal: true
                            symbol: "arrow_downward"
                            iconAngle: dirChip.modelData.angle - 90
                            label: dirChip.modelData.label
                            on: Math.round(root.doc.angle) === dirChip.modelData.angle
                            tint: root.panel.accent
                            onActivated: root.edit({ angle: dirChip.modelData.angle })
                        }
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ══ Strength ══════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Heading { text: Translation.tr("Strength").toUpperCase() }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    ValueSlider {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        accessibleName: Translation.tr("Strength")
                        thickness: Tokens.spacingMd
                        expressive: true
                        accent: root.panel.accent
                        value: root.doc.strength
                        onMoved: v => root.edit({ strength: Math.round(v * 100) / 100 })
                        onScrolled: d => root.edit({ strength: root.doc.strength + d * 0.05 })
                    }
                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.doc.strength * 100) + "%"
                        variant: "label"
                        font.features: ({ tnum: 1 })
                        color: root.palette.fgMuted
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Translation.tr("How far the colours go from the plain bar. Full is the strongest that still reads well; lower keeps text calmer.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    enabled: root.hasMid
                    opacity: root.hasMid ? 1 : 0.4
                    StyledText {
                        text: Translation.tr("Middle at")
                        variant: "label"
                        color: root.palette.fgMuted
                    }
                    ValueSlider {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        accessibleName: Translation.tr("Where the middle colour sits")
                        thickness: Tokens.spacingMd
                        expressive: true
                        accent: root.panel.accent
                        value: (root.doc.mid - 0.1) / 0.8
                        onMoved: v => root.edit({ mid: Math.round((0.1 + v * 0.8) * 100) / 100 })
                    }
                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                        horizontalAlignment: Text.AlignRight
                        text: Math.round(root.doc.mid * 100) + "%"
                        variant: "label"
                        font.features: ({ tnum: 1 })
                        color: root.palette.fgMuted
                    }
                }
            }

            // ══ Glass ═════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm
                Heading { text: Translation.tr("Glass").toUpperCase() }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingMd
                    ValueSlider {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        accessibleName: Translation.tr("Glass")
                        thickness: Tokens.spacingMd
                        expressive: true
                        accent: root.panel.accent
                        value: Config.barGlass
                        onMoved: v => Config.barGlass = Math.round(v * 100) / 100
                        onScrolled: d => Config.barGlass = Math.max(0, Math.min(1, Config.barGlass + d * 0.05))
                    }
                    StyledText {
                        Layout.preferredWidth: Tokens.iconXl + Tokens.spacingMd
                        horizontalAlignment: Text.AlignRight
                        text: Config.barGlass <= 0 ? Translation.tr("Solid") : Math.round(Config.barGlass * 100) + "%"
                        variant: "label"
                        font.features: ({ tnum: 1 })
                        color: root.palette.fgMuted
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 0
                    text: Translation.tr("The bar, the islands and the cards on them turn to tinted glass: the desktop shows through, blurred by the compositor, with what is on the glass kept as a veil of the same tint. It works with or without a gradient.")
                    variant: "caption"
                    emphasis: "dim"
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
            }

            // ══ Where it is kept ══════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: keptRow.implicitHeight + Tokens.spacingMd * 2
                radius: Tokens.radiusCard
                color: root.palette.section
                RowLayout {
                    id: keptRow
                    anchors.fill: parent
                    anchors.margins: Tokens.spacingMd
                    spacing: Tokens.spacingMd
                    MaterialIcon {
                        name: root.saved ? "save" : "palette"
                        fill: root.saved ? 1 : 0
                        color: root.saved ? root.panel.accent : root.palette.fgMuted
                        font.pixelSize: Tokens.iconLg
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 0
                        text: root.saved
                            ? Translation.tr("The gradient is kept with “%1”. It is on whenever that scheme is, and off for every scheme without one.").arg(root.worn)
                            : root.worn !== ""
                            ? Translation.tr("“%1” is a classic and cannot keep one. Save its colours as a scheme of your own to keep a gradient with it.").arg(root.worn)
                            : Translation.tr("These colours are not a saved scheme, so the gradient lasts until you change scheme. Save them from Palette to keep it.")
                        variant: "caption"
                        color: root.palette.fgMuted
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
    Scrollbar { flickable: pane }
}
