pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── SchemeEditor ──────────────────────────────────────────────────────────────
// The colour scheme page's Palette view: build a palette, see it worn (the loud card on the left), put it on.
//
//   WHICH   a plate of the colours being edited. Four seed CARDS whose faces ARE the colours (Background, Text,
//           and the two accents); the chosen one goes round and its badge blooms into a shape of its own and a
//           tick. Or, in Every slot, the eighteen slots as chips the same way. A mode switch, undo and "back to
//           what the shell wears" sit in its header.
//   WHAT    a plate with the picker, the colour's name, its hex (large, mono), a ribbon of exactly what Apply
//           will commit, and under it the ways to make the second accent (shuffle, harmony) or, in Every slot,
//           the way to let a held colour go.
//   PUT ON  name it and save it, hold to peek at it on the whole shell, and Apply: the page's one loud pill.
//
// All of the state lives in ColorSchemePanel (`panel`): the seeds, the staged slots, undo, ripple, saving.
// ─────────────────────────────────────────────────────────────────────────────
ColumnLayout {
    id: root

    required property var panel
    property alias hexField: hexField
    property alias schemeName: schemeName

    readonly property var palette: Colors.of(QsWindow.window)
    readonly property bool simple: root.panel.mode === "simple"

    function slotLabel(slot) {
        if (slot === "background") return Translation.tr("Background")
        if (slot === "foreground") return Translation.tr("Text")
        return Translation.tr("Colour %1").arg(slot.substring(5))
    }

    spacing: Tokens.spacingMd
    visible: root.panel.view === "edit" && !root.panel.showProgress && !root.panel.picking

    // The page rises and fades in as the others do; its parts arrive on springs inside it.
    ViewEnter { target: root; active: root.visible }

    Connections {
        target: root.panel
        function onNameWanted(name) { schemeName.setText(name) }
        function onFieldsBlurRequested() {
            if (schemeName.editing) schemeName.blur()
            if (hexField.editing) hexField.blur()
        }
    }

    // ══ WHICH colour ══════════════════════════════════════════════════════════
    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: false
        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd * 2 + Tokens.spacingMd + 88 + Tokens.spacingSm
        radius: Tokens.radiusCard
        color: root.palette.section

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            // Header: the mode, and what acts on the colours as a whole.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                SegmentSwitch {
                    Layout.preferredWidth: 244
                    Layout.fillHeight: false
                    accent: root.panel.accent
                    model: [
                        { value: "simple",   label: Translation.tr("Four colours"), icon: "palette" },
                        { value: "advanced", label: Translation.tr("Every slot"),   icon: "format_list_bulleted" }
                    ]
                    current: root.panel.mode
                    onPicked: function (v) { root.panel.mode = v }
                }
                Item { Layout.fillWidth: true }

                // Staged slots, the way back out of them.
                ChipButton {
                    visible: root.panel.mode === "advanced" && root.panel.draftCount > 0
                    tonal: true
                    symbol: "undo"
                    label: Translation.tr("Discard %1").arg(root.panel.draftCount)
                    tint: root.panel.accent
                    onActivated: root.panel.discardDraft()
                }
                // Re-read what the shell wears, dropping every edit.
                ChipButton {
                    tonal: true
                    symbol: "restart_alt"
                    tint: root.panel.accent
                    iconAngle: root.panel._syncPhase
                    enabled: root.panel.editorDiffers
                    onActivated: root.panel.syncToCurrent()
                    HoverTip { text: Translation.tr("Back to what the shell wears") }
                }
                ChipButton {
                    tonal: true
                    symbol: "undo"
                    tint: root.panel.accent
                    enabled: root.panel.history.length > 0
                    onActivated: root.panel.undo()
                    HoverTip { text: Translation.tr("Undo"); alignEnd: true }
                }
            }

            // ── Four colours ───────────────────────────────────────────────────
            // Each card is the colour itself. The chosen one goes round and its badge blooms into a shape of
            // its own (a squircle, a hexagon, a cookie, a clover) with a tick, on springs. Its face follows the
            // picker live, so it tracks rather than easing: an eased colour would chase the drag.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.simple

                RowLayout {
                    id: seedRow
                    anchors.fill: parent
                    spacing: Tokens.spacingMd

                    readonly property var shapes: ["squircle", "hexagon", "cookie9", "clover"]

                    Repeater {
                        model: root.panel.seeds
                        delegate: Item {
                            id: seed
                            required property var modelData
                            required property int index
                            readonly property bool on: root.panel.seedIndex === seed.index
                            readonly property color face: seed.modelData.value
                            readonly property color ink: Palette.readableOn(seed.modelData.value)

                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Cards arrive one after another whenever Palette is shown, and bump in turn when
                            // a ripple goes by (Shuffle, a harmony, a scheme loaded, an undo).
                            PopIn { id: pop; active: seedRow.visible && root.visible; index: seed.index; cap: 4; step: Motion.stagger * 3 }
                            property real bump: 0
                            Connections {
                                target: root.panel
                                function onRippled() { bumpAnim.restart() }
                            }
                            SequentialAnimation {
                                id: bumpAnim
                                PauseAnimation { duration: seed.index * Motion.stagger * 2 }
                                NumberAnimation { target: seed; property: "bump"; to: 1; duration: Motion.fast; easing.type: Motion.enter }
                                NumberAnimation { target: seed; property: "bump"; to: 0; duration: Motion.standard; easing.type: Motion.overshoot }
                            }
                            opacity: pop.opacity

                            SpringValue { id: shapeK; target: seed.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
                            SpringValue {
                                id: lean
                                target: tap.pressed ? 0.95 : hover.hovered && !seed.on ? 1.03 : 1
                                spec: Motion.springSpatialFast
                                epsilon: 0.001
                            }

                            Rectangle {
                                id: face
                                anchors.fill: parent
                                radius: Tokens.radiusCard + Math.max(0, shapeK.value) * (height / 2 - Tokens.radiusCard)
                                color: seed.face
                                scale: lean.value * pop.scale * (1 + 0.05 * seed.bump)
                                border.width: Tokens.borderWidth
                                border.color: root.palette.alpha(root.palette.fg, seed.on ? 0 : 0.16)

                                // The badge: a plain disc while it is not the one, a shape with a tick when it is.
                                Item {
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.topMargin: Tokens.spacingMd
                                    anchors.rightMargin: Tokens.spacingMd + shapeK.value * Tokens.spacingXs
                                    width: Tokens.iconXl - Tokens.spacingSm
                                    height: width
                                    MorphShape {
                                        anchors.fill: parent
                                        shape: seed.on ? seedRow.shapes[seed.index % seedRow.shapes.length] : "circle"
                                        spec: Motion.springSpatialFast
                                        fillColor: root.palette.alpha(seed.ink, seed.on ? 0.92 : 0.2)
                                        Behavior on fillColor { ColorAnimation { duration: Motion.standard } }
                                    }
                                    MaterialIcon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        fill: 1
                                        font.pixelSize: Tokens.iconSm
                                        color: seed.face
                                        opacity: seed.on ? 1 : 0
                                        scale: seed.on ? 1 : 0.4
                                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                        Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                                    }
                                }

                                Column {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: Tokens.spacingLg + shapeK.value * Tokens.spacingXs
                                    anchors.bottomMargin: Tokens.spacingLg
                                    spacing: 0
                                    StyledText {
                                        text: seed.modelData.label
                                        variant: "label"
                                        font.weight: seed.on ? Font.Bold : Font.DemiBold
                                        color: seed.ink
                                    }
                                    StyledText {
                                        text: seed.modelData.value.toString().toUpperCase()
                                        variant: "micro"
                                        font.family: Tokens.fontMono
                                        color: root.palette.alpha(seed.ink, 0.72)
                                    }
                                }
                            }

                            HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { id: tap; onTapped: root.panel.seedIndex = seed.index }
                            Accessible.role: Accessible.RadioButton
                            Accessible.name: seed.modelData.label
                            Accessible.checkable: true
                            Accessible.checked: seed.on
                            Accessible.onPressAction: root.panel.seedIndex = seed.index
                        }
                    }
                }
            }

            // ── Every slot ─────────────────────────────────────────────────────
            // The same idea at chip size: the chosen slot goes round with a ring; a held (pin) or staged (pencil)
            // slot carries its mark, which pops in rather than appearing.
            GridLayout {
                id: slotGrid
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.simple
                columns: 9
                columnSpacing: Tokens.spacingSm
                rowSpacing: Tokens.spacingSm

                Repeater {
                    model: Palette.allSlots()
                    delegate: Item {
                        id: slotSw
                        required property var modelData
                        required property int index
                        readonly property bool on:     root.panel.selectedSlot === slotSw.modelData
                        readonly property bool pinned: ColorScheme.isOverridden(slotSw.modelData)
                        readonly property bool edited: root.panel.draft[slotSw.modelData] !== undefined

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        // A leaning chip paints over its neighbours rather than under them.
                        z: hover.hovered ? 1 : 0
                        // The chosen one's colour steps in from its ring. (A Behavior cannot sit on `anchors.*`.)
                        property real inset: slotSw.on ? Tokens.spacingXs + 1 : 0
                        Behavior on inset { NumberAnimation { duration: Motion.respond } }

                        PopIn { id: pop; active: slotGrid.visible && root.visible; index: slotSw.index; cap: 18; step: Motion.stagger * 0.6 }
                        SpringValue { id: shapeK; target: slotSw.on ? 1 : 0; spec: Motion.springSpatial; epsilon: 0.002 }
                        SpringValue {
                            id: lean
                            target: tap.pressed ? 0.92 : hover.hovered ? 1.08 : 1
                            spec: Motion.springSpatialFast
                            epsilon: 0.001
                        }
                        opacity: pop.opacity
                        scale: lean.value * pop.scale

                        Rectangle {
                            anchors.fill: parent
                            radius: Tokens.radiusSm + Math.max(0, shapeK.value) * (height / 2 - Tokens.radiusSm)
                            color: "transparent"
                            border.width: Tokens.borderWidth * 2
                            border.color: root.panel.accent
                            opacity: slotSw.on ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        }
                        Rectangle {
                            id: fill
                            anchors.fill: parent
                            anchors.margins: slotSw.inset
                            radius: Math.max(2, Tokens.radiusSm + Math.max(0, shapeK.value) * (parent.height / 2 - Tokens.radiusSm) - slotSw.inset)
                            color: root.panel.slotColor(slotSw.modelData)
                            border.width: slotSw.on ? 0 : Tokens.borderWidth
                            border.color: root.palette.alpha(root.palette.fg, 0.16)

                            MaterialIcon {
                                anchors.centerIn: parent
                                name: slotSw.edited ? "edit" : "push_pin"
                                fill: 1
                                color: Palette.readableOn(fill.color.toString())
                                variant: "caption"
                                opacity: slotSw.pinned || slotSw.edited ? 1 : 0
                                scale: slotSw.pinned || slotSw.edited ? 1 : 0.4
                                Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                                Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                            }
                        }

                        HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { id: tap; onTapped: root.panel.selectedSlot = slotSw.modelData }
                        HoverTip { text: root.slotLabel(slotSw.modelData) }
                        Accessible.role: Accessible.RadioButton
                        Accessible.name: root.slotLabel(slotSw.modelData)
                        Accessible.checkable: true
                        Accessible.checked: slotSw.on
                        Accessible.onPressAction: root.panel.selectedSlot = slotSw.modelData
                    }
                }
            }
        }
    }

    // ══ WHAT colour ═══════════════════════════════════════════════════════════
    Rectangle {
        id: tune
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Tokens.radiusCard
        color: root.palette.section

        ViewEnter { target: tune; active: root.visible; delay: Motion.stagger * 2; rise: Tokens.spacingMd }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Tokens.spacingMd
            spacing: Tokens.spacingMd

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacingMd

                // Stretches to the readout's height beside it.
                SpectrumPicker {
                    Layout.preferredWidth: 188
                    Layout.minimumWidth: 148
                    Layout.fillHeight: true
                    value: root.panel.curHex
                    onColorPicked: function (hex) { root.panel.setCurrent(hex) }
                    // A whole drag is ONE undo step: snapshot as it starts.
                    onDraggingChanged: if (dragging) root.panel.remember()
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Tokens.spacingSm

                    // Which colour, and whether it is held.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        spacing: Tokens.spacingSm
                        StyledText {
                            Layout.fillWidth: true
                            text: root.simple ? root.panel.seeds[root.panel.seedIndex].label
                                              : root.slotLabel(root.panel.selectedSlot)
                            variant: "label"
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Rectangle {
                            visible: !root.simple && ColorScheme.isOverridden(root.panel.selectedSlot)
                            implicitWidth: heldRow.implicitWidth + Tokens.spacingMd * 2
                            implicitHeight: Tokens.iconLg
                            radius: height / 2
                            color: root.palette.primaryContainer
                            Row {
                                id: heldRow
                                anchors.centerIn: parent
                                spacing: Tokens.spacingXs
                                MaterialIcon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    name: "push_pin"; fill: 1
                                    font.pixelSize: Tokens.iconSm
                                    color: root.palette.fgOnPrimaryContainer
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Translation.tr("Held")
                                    variant: "micro"
                                    font.weight: Font.DemiBold
                                    color: root.palette.fgOnPrimaryContainer
                                }
                            }
                        }
                    }

                    // The colour's hex: a capsule with the colour itself as its badge, the hex in large mono, and
                    // a copy tool (it ticks for a moment, so the press is answered).
                    SchemeField {
                        id: hexField
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        mono: true
                        swatch: root.panel.curHex
                        accent: root.panel.accent
                        lead: Translation.tr("Hex")
                        seed: root.panel.curHex

                        // Takes only a real #rrggbb that is not already the colour in use (blurring an
                        // untouched field must not stage the slot as edited), and puts back whatever else
                        // was typed.
                        onCommitted: function (v) {
                            const hex = v.trim().toLowerCase()
                            if (/^#[0-9a-f]{6}$/.test(hex) && hex !== root.panel.curHex.toLowerCase()) {
                                root.panel.remember()
                                root.panel.setCurrent(hex)
                            }
                            hexField.setText(root.panel.curHex)
                        }
                        onAccepted: hexField.blur()
                        onKeyPressed: function (e) {
                            if (e.key !== Qt.Key_Escape) return
                            hexField.setText(root.panel.curHex)
                            hexField.blur()
                            e.accepted = true
                        }

                        CardTool {
                            symbol: root.panel.justCopied ? "check" : "content_copy"
                            filled: root.panel.justCopied
                            tint: root.panel.justCopied ? root.panel.accent : root.palette.fgMuted
                            hoverTint: root.panel.accent
                            name: Translation.tr("Copy the hex")
                            onActivated: root.panel.copyCurrent()
                            HoverTip { text: Translation.tr("Copy the hex"); alignEnd: true }
                        }
                    }

                    // How readable the palette is: its text on its background, as the large numeral it is, graded
                    // the way WCAG names it. A warning tone below "Large".
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Tokens.spacingMd
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.panel.textContrast.toFixed(1)
                                font.pixelSize: Tokens.fontDisplay
                                font.weight: Font.Bold
                                font.features: ({ tnum: 1 })
                                color: root.panel.contrastGrade === "Low" ? root.palette.warning : root.palette.fg
                                Behavior on color { ColorAnimation { duration: Motion.respond } }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    text: root.panel.contrastGrade === "Low" ? Translation.tr("Hard to read")
                                        : root.panel.contrastGrade === "Large" ? Translation.tr("Fine for large text")
                                        : root.panel.contrastGrade === "AA" ? Translation.tr("Readable") : Translation.tr("Very readable")
                                    variant: "label"
                                    font.weight: Font.DemiBold
                                    color: root.panel.contrastGrade === "Low" ? root.palette.warning : root.palette.fg
                                }
                                StyledText {
                                    text: Translation.tr("Text on background · %1").arg(root.panel.contrastGrade)
                                    variant: "micro"
                                    emphasis: "dim"
                                }
                            }
                        }
                    }

                    // Exactly what Apply will commit: the background with its text on it, then the fifteen
                    // colours, as one ribbon. The hairline is laid over the top so the background cell still has
                    // an edge when it is nearly the plate's own colour.
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.preferredHeight: Tokens.iconXl

                        RowLayout {
                            anchors.fill: parent
                            spacing: 0

                            Rectangle {
                                Layout.preferredWidth: Tokens.iconXl + Tokens.spacingXl
                                Layout.fillHeight: true
                                topLeftRadius: height / 2
                                bottomLeftRadius: height / 2
                                color: Palette.slotValue(root.panel.pending, "background")
                                Behavior on color { ColorAnimation { duration: Motion.track } }
                                StyledText {
                                    anchors.centerIn: parent
                                    text: "Aa"
                                    color: Palette.slotValue(root.panel.pending, "foreground")
                                    variant: "caption"
                                    font.weight: Font.Bold
                                    Behavior on color { ColorAnimation { duration: Motion.track } }
                                }
                            }
                            // Each cell tracks its colour while it is dragged, and on a ripple takes it a beat
                            // after the one before: the change runs along the ribbon, left to right.
                            Repeater {
                                model: 15
                                delegate: Rectangle {
                                    id: cell
                                    required property int index
                                    readonly property color goal: Palette.slotValue(root.panel.pending, "color" + (cell.index + 1))
                                    property color shown: "transparent"
                                    property bool _ready: false
                                    Component.onCompleted: { cell.shown = cell.goal; cell._ready = true }
                                    onGoalChanged: {
                                        if (root.panel.rippleOn) { wave.restart(); return }
                                        wave.stop()
                                        cell.shown = cell.goal
                                    }
                                    Behavior on shown { enabled: cell._ready && !wave.running; ColorAnimation { duration: Motion.track } }
                                    SequentialAnimation {
                                        id: wave
                                        PauseAnimation { duration: cell.index * Motion.stagger }
                                        ColorAnimation { target: cell; property: "shown"; to: cell.goal; duration: Motion.standard }
                                    }
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    topRightRadius: cell.index === 14 ? height / 2 : 0
                                    bottomRightRadius: cell.index === 14 ? height / 2 : 0
                                    color: cell.shown
                                }
                            }
                        }
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: "transparent"
                            border.width: Tokens.borderWidth
                            border.color: root.palette.alpha(root.palette.fg, 0.16)
                        }
                    }
                }
            }

            // ── The second accent / the held colour ────────────────────────────
            // Palette: Shuffle redraws both accents; the harmony pills set Accent 2 to a partner of Accent. Each
            // carries a dot of the colour it would give and stays lit while Accent 2 IS that partner: the dots
            // are the explanation. Every slot: what holding means, and the way to let one go.
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                ChipButton {
                    visible: root.simple
                    tonal: true
                    symbol: "shuffle"
                    label: Translation.tr("Shuffle")
                    tint: root.panel.accent
                    iconAngle: root.panel._shufflePhase
                    onActivated: root.panel.shuffleAccents()
                    HoverTip { text: Translation.tr("New accents that go with the background") }
                }
                StyledText {
                    visible: root.simple
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: Tokens.spacingSm
                    text: Translation.tr("Accent 2")
                    variant: "caption"
                    emphasis: "dim"
                }
                Repeater {
                    model: root.simple ? root.panel.harmonies : []
                    delegate: ChipButton {
                        required property var modelData
                        tonal: true
                        label: modelData.label
                        dot: root.panel.partnerOf(modelData.kind)
                        tint: root.panel.accent
                        on: root.panel.seedB.toLowerCase() === root.panel.partnerOf(modelData.kind).toLowerCase()
                        onActivated: root.panel.applyHarmony(modelData.kind)
                    }
                }

                StyledText {
                    visible: !root.simple
                    Layout.fillWidth: true
                    text: Translation.tr("Apply holds the colours you changed, through every wallpaper change.")
                    variant: "caption"
                    emphasis: "dim"
                    elide: Text.ElideRight
                }
                Item { Layout.fillWidth: true; visible: root.simple }
                ChipButton {
                    visible: !root.simple && ColorScheme.isOverridden(root.panel.selectedSlot)
                    tonal: true
                    symbol: "lock_open"
                    label: Translation.tr("Release")
                    tint: root.panel.accent
                    enabled: !ColorScheme.busy
                    onActivated: ColorScheme.release(root.panel.selectedSlot)
                }
            }
        }
    }

    // ══ PUT it on ═════════════════════════════════════════════════════════════
    RowLayout {
        id: foot
        Layout.fillWidth: true
        Layout.fillHeight: false
        spacing: Tokens.spacingSm

        ViewEnter { target: foot; active: root.visible; delay: Motion.stagger * 4 }

        // The name and the Save that goes with it are one capsule: a bookmark badge, the name (it types its own
        // hints while idle), and a pill at its end that lights once there is a name, says Update when the name is
        // a saved scheme's, and ticks for a moment after it goes.
        SchemeField {
            id: schemeName
            Layout.fillWidth: true
            Layout.fillHeight: false
            tone: root.palette.section
            accent: root.panel.accent
            icon: "bookmark"
            lead: Translation.tr("Name this palette")
            hints: [{ key: "Dusk", text: Translation.tr("a name to keep it by") },
                    { key: "Enter", text: Translation.tr("saves it") }]
            onAccepted: if (savePill.ready) savePill.save()
            onKeyPressed: function (e) {
                if (e.key !== Qt.Key_Escape) return
                schemeName.blur()
                e.accepted = true
            }

            Rectangle {
                id: savePill
                readonly property bool ready: schemeName.text.trim().length > 0
                readonly property bool done: root.panel.justSaved
                function save() {
                    ColorScheme.saveScheme(schemeName.text, root.panel.saveVariants())
                    root.panel.justSaved = true
                    root.panel.savedTimer.restart()
                }
                width: saveRow.implicitWidth + Tokens.spacingLg * 2
                height: Tokens.iconXl
                radius: height / 2
                color: savePill.done ? root.palette.primary
                     : savePill.ready ? root.palette.primaryContainer
                     : root.palette.alpha(root.palette.fg, 0.08)
                Behavior on color { ColorAnimation { duration: Motion.standard } }
                SpringValue {
                    id: saveLean
                    target: saveTap.pressed ? 0.94 : saveHover.hovered && savePill.ready ? 1.05 : 1
                    spec: Motion.springSpatialFast
                    epsilon: 0.001
                }
                scale: saveLean.value
                readonly property color ink: savePill.done ? root.palette.fgOnPrimary
                    : savePill.ready ? root.palette.fgOnPrimaryContainer : root.palette.fgDim
                Row {
                    id: saveRow
                    anchors.centerIn: parent
                    spacing: Tokens.spacingSm
                    MaterialIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: savePill.done ? "check" : "save"
                        fill: savePill.ready ? 1 : 0
                        font.pixelSize: Tokens.iconMd
                        color: savePill.ink
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: savePill.done ? Translation.tr("Saved")
                            : ColorScheme.schemeExists(schemeName.text) ? Translation.tr("Update") : Translation.tr("Save")
                        variant: "label"
                        font.weight: Font.DemiBold
                        color: savePill.ink
                    }
                }
                HoverHandler { id: saveHover; cursorShape: Qt.PointingHandCursor }
                MouseArea {
                    id: saveTap
                    anchors.fill: parent
                    enabled: savePill.ready
                    onClicked: savePill.save()
                    Accessible.role: Accessible.Button
                    Accessible.name: Translation.tr("Save")
                    Accessible.onPressAction: savePill.save()
                }
            }
        }
        // Hold to wear the pending palette on the whole shell; let go and it is gone (a preview layer, nothing written).
        ChipButton {
            tonal: true
            symbol: "visibility"
            label: Translation.tr("Peek")
            on: ColorScheme.peeking
            tint: root.panel.accent
            enabled: !ColorScheme.busy
            onPressedChanged: if (pressed) ColorScheme.peek(root.panel.pending); else ColorScheme.endPeek()
            HoverTip { text: Translation.tr("Hold to see it on the whole shell"); alignEnd: true }
        }
        SchemeApply {
            label: root.simple ? Translation.tr("Apply")
                 : root.panel.draftCount > 0 ? Translation.tr("Hold %1").arg(root.panel.draftCount)
                 : Translation.tr("Re-apply")
            busyLabel: Translation.tr("Applying…")
            doneLabel: Translation.tr("Applied")
            busy: ColorScheme.busy
            done: root.panel.justApplied
            doneTint: Verdict.tint(true)
            enabled: !ColorScheme.busy && root.panel.blocked === ""
            onActivated: root.panel.applyCurrent()
        }
    }
}
