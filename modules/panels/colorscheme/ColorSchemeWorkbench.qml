pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import QtQuick.Layouts
import "../../../config"
import "../../../components"
import "../../../services"
import "../../../services/palette.js" as Palette

// ── ColorSchemeWorkbench ── part of ColorSchemePanel.qml; `panel` is the ColorSchemePanel it belongs to. ──
Rectangle {
    id: workbench
    required property var panel
    property alias hexField: hexField
    property alias schemeName: schemeName
    Layout.fillWidth: true
    Layout.rightMargin: panel.contentPad
    Layout.fillHeight: false
    implicitHeight: benchCol.implicitHeight + Tokens.spacingMd * 2
    visible: panel.view === "edit" && !panel.showProgress
    radius: Tokens.radiusCard
    color: Colors.of(QsWindow.window).section

    // The card only fades; its parts rise one after another (seeds, tools, picker, then the
    // footer below), a few frames apart.
    ViewEnter { target: workbench; active: workbench.visible; rise: 0 }

    ColumnLayout {
        id: benchCol
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Tokens.spacingMd
        spacing: Tokens.spacingMd

        // ── Simple: four seed swatches ──────────────────────────────
        // The chosen one wears a ring and the colour pulls back from it (a spring, so
        // it overshoots a hair and settles); a swatch leans toward the pointer and
        // dips under a press. Its fill follows the picker live, so it tracks (Motion.track)
        // rather than easing — an eased colour would chase the drag.
        RowLayout {
            id: seedRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: panel.mode === "simple"
            spacing: Tokens.spacingSm


            Repeater {
                model: panel.seeds
                delegate: Item {
                    id: seed
                    required property var modelData
                    required property int index
                    readonly property bool on: panel.seedIndex === seed.index

                    property real inset: seed.on ? Tokens.spacingSm : 0
                    Behavior on inset { SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.05 } }

                    // Pops in one after another whenever Palette is shown, and bumps in turn
                    // when a ripple goes by (Shuffle, a harmony, a scheme loaded, an undo).
                    PopIn { id: pop; active: seedRow.visible; index: seed.index; cap: 4; step: Motion.stagger * 3 }
                    property real bump: 0
                    Connections {
                        target: panel
                        function onRippled() { bumpAnim.restart() }
                    }
                    SequentialAnimation {
                        id: bumpAnim
                        PauseAnimation { duration: seed.index * Motion.stagger * 2 }
                        NumberAnimation { target: seed; property: "bump"; to: 1; duration: Motion.fast; easing.type: Motion.enter }
                        NumberAnimation { target: seed; property: "bump"; to: 0; duration: Motion.standard; easing.type: Motion.overshoot }
                    }

                    Layout.fillWidth: true
                    Layout.preferredHeight: Tokens.iconXl + Tokens.spacingXs
                    property real lean: seedTap.pressed ? 0.96 : seedHover.hovered ? 1.03 : 1.0
                    Behavior on lean { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }
                    opacity: pop.opacity
                    scale:   seed.lean * pop.scale * (1 + 0.06 * seed.bump)

                    // The ring: it closes in on the swatch as it is chosen.
                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: "transparent"
                        border.width: Tokens.borderWidth * 2
                        border.color: panel.accent
                        opacity: seed.on ? 1 : 0
                        scale:   seed.on ? 1 : 0.92
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: Math.max(0, seed.inset)
                        radius: height / 2
                        color: seed.modelData.value
                        border.width: seed.on ? 0 : Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg,
                                                                      seedHover.hovered ? 0.4 : 0.18)
                        Behavior on color        { ColorAnimation { duration: Motion.track } }
                        Behavior on border.color { ColorAnimation { duration: Motion.respond } }

                        StyledText {
                            anchors.centerIn: parent
                            text: seed.modelData.label
                            variant: "micro"
                            font.weight: seed.on ? Font.DemiBold : Font.Medium
                            color: Palette.readableOn(seed.modelData.value)
                            Behavior on color { ColorAnimation { duration: Motion.track } }
                        }
                    }

                    HoverHandler { id: seedHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { id: seedTap;   onTapped: panel.seedIndex = seed.index }
                }
            }
        }

        // ── Advanced: every slot ────────────────────────────────────
        // Same ring-and-inset as the seeds, at swatch size. A held (pin) or staged (pencil)
        // slot carries its mark, which pops in rather than appearing.
        GridLayout {
            id: slotGrid
            Layout.fillWidth: true
            Layout.fillHeight: false
            visible: panel.mode === "advanced"
            columns: 9
            columnSpacing: Tokens.spacingXs + 1
            rowSpacing:    Tokens.spacingXs + 1


            Repeater {
                model: Palette.allSlots()
                delegate: Item {
                    id: slotSw
                    required property var modelData
                    required property int index
                    readonly property bool on:     panel.selectedSlot === slotSw.modelData
                    readonly property bool pinned: ColorScheme.isOverridden(slotSw.modelData)
                    readonly property bool edited: panel.draft[slotSw.modelData] !== undefined

                    property real inset: slotSw.on ? Tokens.spacingXs + 1 : 0
                    Behavior on inset { SpringAnimation { spring: 5.5; damping: 0.34; epsilon: 0.05 } }

                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    // A leaning swatch paints over its neighbours rather than under them.
                    z: slotHover.hovered ? 1 : 0
                    // The grid fills in as a wave, row by row, whenever Slots is shown.
                    PopIn { id: pop; active: slotGrid.visible; index: slotSw.index; cap: 18; step: Motion.stagger * 0.6 }
                    property real lean: slotTap.pressed ? 0.92 : slotHover.hovered ? 1.08 : 1.0
                    Behavior on lean { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }
                    opacity: pop.opacity
                    scale:   slotSw.lean * pop.scale

                    Rectangle {
                        anchors.fill: parent
                        radius: Tokens.radiusXs
                        color: "transparent"
                        border.width: Tokens.borderWidth * 2
                        border.color: panel.accent
                        opacity: slotSw.on ? 1 : 0
                        scale:   slotSw.on ? 1 : 0.9
                        Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                        Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                    }

                    Rectangle {
                        id: slotFill
                        anchors.fill: parent
                        anchors.margins: Math.max(0, slotSw.inset)
                        radius: Math.max(2, Tokens.radiusXs - slotSw.inset)
                        color: panel.slotColor(slotSw.modelData)
                        border.width: slotSw.on ? 0 : Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).outline
                        Behavior on color { ColorAnimation { duration: Motion.track } }

                        MaterialIcon {
                            anchors.centerIn: parent
                            name: slotSw.edited ? "edit" : "push_pin"
                            fill: 1
                            color: Palette.readableOn(slotFill.color.toString())
                            variant: "micro"
                            opacity: slotSw.pinned || slotSw.edited ? 1 : 0
                            scale:   slotSw.pinned || slotSw.edited ? 1 : 0.4
                            Behavior on opacity { NumberAnimation { duration: Motion.respond } }
                            Behavior on scale   { NumberAnimation { duration: Motion.standard; easing.type: Motion.overshoot } }
                        }
                    }

                    HoverHandler { id: slotHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler   { id: slotTap;   onTapped: panel.selectedSlot = slotSw.modelData }
                }
            }
        }

        // ── Tools: shuffle, harmony, undo ───────────────────────────
        // Shuffle redraws both accents. The harmony chips set Accent 2 to a partner of Accent
        // — each carries a dot of the colour it would give and lights while Accent 2 IS that
        // partner. Undo steps back through everything the editor held before (see `history`),
        // and the refresh beside it throws the edits away and re-reads the colours the shell is
        // wearing. Shuffle and harmony are Palette mode's; undo and refresh are both.
        ColumnLayout {
            id: toolsCol
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingXs

            ViewEnter { target: toolsCol; active: workbench.visible; delay: Motion.stagger * 2; rise: Tokens.spacingMd }

            RowLayout {
                id: tools
                Layout.fillWidth: true
                Layout.fillHeight: false
                spacing: Tokens.spacingSm

                ChipTray {
                    groupShown: panel.mode === "simple"
                    ChipButton {
                        symbol: "shuffle"
                        label:  Translation.tr("Shuffle")
                        tint:   panel.accent
                        iconAngle: panel._shufflePhase
                        onActivated: panel.shuffleAccents()
                    }
                }
                StyledText {
                    visible: panel.mode === "simple"
                    Layout.alignment: Qt.AlignVCenter
                    text: Translation.tr("Accent 2")
                    variant: "caption"; emphasis: "dim"
                }
                ChipTray {
                    groupShown: panel.mode === "simple"
                    Repeater {
                        model: panel.harmonies
                        delegate: ChipButton {
                            required property var modelData
                            label: modelData.label
                            dot:   panel.partnerOf(modelData.kind)
                            tint:  panel.accent
                            on:    panel.seedB.toLowerCase() === panel.partnerOf(modelData.kind).toLowerCase()
                            onActivated: panel.applyHarmony(modelData.kind)
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                ChipTray {
                    // Re-read the colours the shell is wearing, dropping every edit.
                    ChipButton {
                        symbol: "refresh"
                        tint:   panel.accent
                        iconAngle: panel._syncPhase
                        enabled: panel.editorDiffers
                        onActivated: panel.syncToCurrent()
                    }
                    ChipButton {
                        symbol: "undo"
                        tint:   panel.accent
                        enabled: panel.history.length > 0
                        onActivated: panel.undo()
                    }
                }
            }
        }

        // ── Picker + readout ───────────────────────────────────────
        RowLayout {
            id: pickerRow
            Layout.fillWidth: true
            Layout.fillHeight: false
            spacing: Tokens.spacingMd

            ViewEnter { target: pickerRow; active: workbench.visible; delay: Motion.stagger * 3; rise: Tokens.spacingMd }

            // Stretches to the readout's height beside it.
            SpectrumPicker {
                Layout.preferredWidth: 126
                Layout.preferredHeight: 126
                Layout.fillHeight: true
                value: panel.curHex
                onColorPicked: function(hex) { panel.setCurrent(hex) }
                // A whole drag is ONE undo step: snapshot as it starts.
                onDraggingChanged: if (dragging) panel.remember()
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.alignment: Qt.AlignVCenter
                spacing: Tokens.spacingSm

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    // A chip's height always, so choosing a held slot (which shows
                    // Release) or switching mode moves nothing below it.
                    Layout.minimumHeight: Tokens.iconXl + Tokens.spacingXs
                    spacing: Tokens.spacingSm
                    StyledText {
                        Layout.fillWidth: true
                        text: (panel.mode === "simple"
                               ? panel.seeds[panel.seedIndex].label
                               : panel.selectedSlot)
                            + (panel.mode === "advanced"
                               && ColorScheme.isOverridden(panel.selectedSlot) ? " · held" : "")
                        variant: "caption"; emphasis: "dim"; elide: Text.ElideRight
                    }
                    // Text on background, graded. Quiet while it is fine; warns at "Low".
                    Rectangle {
                        id: gradeBadge
                        readonly property bool low: panel.contrastGrade === "Low"
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth:  gradeText.implicitWidth + Tokens.spacingLg * 2
                        implicitHeight: Tokens.iconLg + Tokens.spacingXs
                        radius: height / 2
                        color: gradeBadge.low
                             ? Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).warning, 0.18)
                             : Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.06)
                        Behavior on color { ColorAnimation { duration: Motion.respond } }

                        // One pop when the grade changes (AAA → AA, or into "Low"), so it is noticed.
                        PulseOnce { id: gradePulse; target: gradeBadge; peak: 1.12 }
                        Connections {
                            target: panel
                            function onContrastGradeChanged() { gradePulse.fire() }
                        }

                        StyledText {
                            id: gradeText
                            anchors.centerIn: parent
                            text: "Text · " + panel.contrastGrade + " " + panel.textContrast.toFixed(1)
                            variant: "caption"
                            font.weight: Font.Medium
                            color: gradeBadge.low ? Colors.of(QsWindow.window).warning
                                                  : Colors.of(QsWindow.window).fgMuted
                            Behavior on color { ColorAnimation { duration: Motion.respond } }
                        }
                    }
                    ChipButton {
                        visible: panel.mode === "advanced"
                              && ColorScheme.isOverridden(panel.selectedSlot)
                        symbol: "lock_open"
                        label:  Translation.tr("Release")
                        tint:   panel.accent
                        enabled: !ColorScheme.busy
                        onActivated: ColorScheme.release(panel.selectedSlot)
                    }
                }

                // The colour itself as a disc, and its hex as a pill beside it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    Rectangle {
                        Layout.preferredWidth:  Tokens.iconXl + Tokens.spacingMd
                        Layout.preferredHeight: Tokens.iconXl + Tokens.spacingMd
                        radius: height / 2
                        color: panel.curHex
                        border.width: Tokens.borderWidth
                        border.color: Colors.of(QsWindow.window).outline
                        Behavior on color { ColorAnimation { duration: Motion.track } }

                        // The disc is the colour; a tap on it copies its hex.
                        scale: discTap.pressed ? 0.92 : discHover.hovered ? 1.06 : 1.0
                        Behavior on scale { SpringAnimation { spring: 6.0; damping: 0.34; epsilon: 0.002 } }
                        HoverHandler { id: discHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler   { id: discTap;   onTapped: panel.copyCurrent() }
                    }

                    InputField {
                        id: hexField
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        mono: true
                        seed: panel.curHex

                        // Takes only a real #rrggbb that is not already the colour in use —
                        // blurring an untouched field must not stage the slot as edited —
                        // and puts back whatever else was typed.
                        onCommitted: function (v) {
                            const hex = v.trim().toLowerCase()
                            if (/^#[0-9a-f]{6}$/.test(hex) && hex !== panel.curHex.toLowerCase()) {
                                panel.remember()
                                panel.setCurrent(hex)
                            }
                            hexField.setText(panel.curHex)
                        }
                        onAccepted: hexField.blur()
                        onKeyPressed: function (e) {
                            if (e.key !== Qt.Key_Escape) return
                            hexField.setText(panel.curHex)
                            hexField.blur()
                            e.accepted = true
                        }
                    }

                    // Copy it. Ticks for a moment, so the click is answered.
                    ChipTray {
                        ChipButton {
                            symbol: panel.justCopied ? "check" : "content_copy"
                            on:     panel.justCopied
                            tint:   panel.accent
                            onActivated: panel.copyCurrent()
                        }
                    }
                }

                // Exactly what Apply will commit: the background with its text on it, then
                // the fifteen colours, as one ribbon. The outline is laid over the top so the
                // background cell still has an edge when it is nearly the card's own colour.
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    Layout.preferredHeight: Tokens.iconLg + Tokens.spacingXs

                    RowLayout {
                        anchors.fill: parent
                        spacing: 0

                        Rectangle {
                            Layout.preferredWidth: Tokens.iconXl + Tokens.spacingXl
                            Layout.fillHeight: true
                            topLeftRadius:    height / 2
                            bottomLeftRadius: height / 2
                            color: Palette.slotValue(panel.pending, "background")
                            Behavior on color { ColorAnimation { duration: Motion.track } }
                            StyledText {
                                anchors.centerIn: parent
                                text: Translation.tr("Aa")
                                color: Palette.slotValue(panel.pending, "foreground")
                                variant: "caption"
                                Behavior on color { ColorAnimation { duration: Motion.track } }
                            }
                        }
                        // Each cell tracks its colour while it is dragged, and on a ripple (Shuffle, a
                        // harmony, a scheme loaded, an undo) takes it a beat after the one before —
                        // the change runs along the ribbon, left to right.
                        Repeater {
                            model: 15
                            delegate: Rectangle {
                                id: cell
                                required property int index
                                readonly property color goal: Palette.slotValue(panel.pending, "color" + (cell.index + 1))
                                property color shown: "transparent"
                                property bool _ready: false
                                Component.onCompleted: { cell.shown = cell.goal; cell._ready = true }
                                onGoalChanged: {
                                    if (panel.rippleOn) { wave.restart(); return }
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
                                topRightRadius:    cell.index === 14 ? height / 2 : 0
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
                        border.color: Colors.of(QsWindow.window).alpha(Colors.of(QsWindow.window).fg, 0.15)
                    }
                }

                // Name it, save it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: false
                    spacing: Tokens.spacingSm

                    InputField {
                        id: schemeName
                        Layout.fillWidth: true
                        implicitHeight: Tokens.iconXl + Tokens.spacingMd
                        cornerRadius: implicitHeight / 2
                        placeholder: Translation.tr("Name this palette…")
                        onKeyPressed: function (e) {
                            if (e.key !== Qt.Key_Escape) return
                            schemeName.blur()
                            e.accepted = true
                        }
                    }

                    ChipTray {
                        ChipButton {
                            symbol: panel.justSaved ? "check" : "save"
                            on:     panel.justSaved
                            // "Update" when the name matches a saved preset — you're
                            // editing it. Type a new name and it becomes "Save". A tick for a
                            // moment after it goes.
                            label:  panel.justSaved ? "Saved"
                                  : ColorScheme.schemeExists(schemeName.text) ? "Update" : "Save"
                            tint:   panel.accent
                            enabled: schemeName.text.trim().length > 0
                            onActivated: {
                                ColorScheme.saveScheme(schemeName.text, panel.saveVariants())
                                panel.justSaved = true
                                panel.savedTimer.restart()
                            }
                        }
                    }
                }
            }
        }
    }
}
